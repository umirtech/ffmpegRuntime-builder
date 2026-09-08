/*
 * appfd - FFmpeg URLProtocol for accessing an existing POSIX FD.
 *
 * Usage:
 *
 *     ffmpeg -i appfd:190 ...
 *
 * The protocol does NOT own the caller's original FD.
 * appfd_open() duplicates it and appfd_close() closes the duplicate.
 *
 * This makes the protocol safe to use with an FD managed by the application.
 */

#include "libavformat/url.h"
#include "config_components.h"
#include "libavutil/avassert.h"
#include "libavutil/common.h"
#include "libavutil/log.h"
#include "libavutil/mem.h"
#include "libavutil/opt.h"

#include <inttypes.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>


typedef struct AppFdContext {
    /*
     * MUST be first.
     *
     * FFmpeg's url_alloc_for_protocol() stores priv_data_class here and
     * av_opt_find2()/child_next() later read it back. Without this field,
     * appfd_open() overwrites the class pointer with the fd value and
     * the first av_opt_get() on the AVIOContext walks into a wild AVClass
     * (infinite av_opt_find2 recursion -> SIGSEGV in av_probe_input_buffer2).
     * Same convention as FileContext in file.c.
     */
    const AVClass *class;

    int fd;

    /* Logical position exposed to FFmpeg. */
    int64_t offset;

    /*
     * Known data size.
     *
     * For seekable input:
     *     actual file size
     *
     * For output:
     *     largest logical position written
     *
     * For unknown-size streams:
     *     -1
     */
    int64_t data_size;

    /*
     * Whether the underlying descriptor supports lseek.
     */
    int seekable;

    /*
     * Whether this protocol was opened for writing.
     */
    int writable;

    /*
     * Whether pread/pwrite can be used.
     *
     * Regular files normally support these.
     * Pipes/FIFOs generally don't.
     */
    int positional_io;
} AppFdContext;


/* ------------------------------------------------------------- */
/* Helpers                                                       */
/* ------------------------------------------------------------- */

static int appfd_check_offset(int64_t offset)
{
    if (offset < 0)
        return AVERROR(EINVAL);

    /*
     * Make sure the value can be represented by off_t.
     * On normal Android 64-bit builds this is effectively a no-op.
     */
    if ((uint64_t)offset > (uint64_t)INT64_MAX)
        return AVERROR(EOVERFLOW);

    return 0;
}


/*
 * Parse:
 *
 *     appfd:190
 *
 * FFmpeg passes the complete URL to url_open().
 */
static int appfd_parse_fd(const char *url, int *fd_out)
{
    const char *p;
    char *end;
    long value;

    if (!url || !fd_out)
        return AVERROR(EINVAL);

    p = strchr(url, ':');

    if (!p || !p[1])
        return AVERROR(EINVAL);

    p++;

    errno = 0;

    value = strtol(p, &end, 10);

    if (errno == ERANGE)
        return AVERROR(EOVERFLOW);

    if (end == p || *end != '\0')
        return AVERROR(EINVAL);

    if (value < 0 || value > INT_MAX)
        return AVERROR(EINVAL);

    *fd_out = (int)value;

    return 0;
}


/*
 * Test whether the FD is seekable.
 *
 * The current kernel FD position is restored.
 */
static int appfd_detect_seekable(int fd, int64_t *size)
{
    off_t current;
    off_t end;

    if (size)
        *size = -1;

    errno = 0;

    current = lseek(fd, 0, SEEK_CUR);

    if (current < 0) {
        if (errno == ESPIPE || errno == EINVAL)
            return 0;

        return 0;
    }

    errno = 0;

    end = lseek(fd, 0, SEEK_END);

    if (end < 0) {
        /*
         * Restore the original position even if SEEK_END failed.
         */
        (void)lseek(fd, current, SEEK_SET);
        return 0;
    }

    /*
     * Restore the original kernel position.
     *
     * This is important for the read()/write() fallback.
     */
    if (lseek(fd, current, SEEK_SET) < 0)
        return 0;

    if (size)
        *size = (int64_t)end;

    return 1;
}


/*
 * Determine whether pread/pwrite are usable.
 *
 * We don't actually need a separate syscall probe.
 * The first positional operation can fall back on ESPIPE.
 */
static int appfd_initial_positional_io(int fd)
{
    struct stat st;

    if (fstat(fd, &st) < 0)
        return 0;

    /*
     * pread/pwrite are appropriate for regular/block files.
     *
     * For unusual Android descriptors, let the first operation
     * determine whether positional I/O actually works.
     */
    if (S_ISREG(st.st_mode) || S_ISBLK(st.st_mode))
        return 1;

    return 1;
}


/* ------------------------------------------------------------- */
/* Read                                                          */
/* ------------------------------------------------------------- */

static int appfd_read(URLContext *h,
                          unsigned char *buf,
                          int size)
{
    AppFdContext *ctx;
    int total = 0;

    if (!h || !buf || size <= 0)
        return AVERROR(EINVAL);

    ctx = h->priv_data;

    if (!ctx || ctx->fd < 0)
        return AVERROR(EBADF);

    /*
     * If this is a known-size seekable input, don't read past EOF.
     */
    if (!ctx->writable &&
        ctx->data_size >= 0 &&
        ctx->offset >= ctx->data_size) {
        return AVERROR_EOF;
    }

    if (!ctx->writable && ctx->data_size >= 0) {
        int64_t remaining = ctx->data_size - ctx->offset;

        if (remaining <= 0)
            return AVERROR_EOF;

        if ((int64_t)size > remaining)
            size = (int)FFMIN((int64_t)size, remaining);
    }

    while (total < size) {
        ssize_t ret;

        /*
         * Preferred path:
         *
         *     pread()
         *
         * This keeps FFmpeg's logical position independent from
         * the kernel FD offset.
         */
        if (ctx->positional_io) {

            /*
             * Prevent int64 -> off_t overflow.
             */
            if (ctx->offset > INT64_MAX - total)
                return total > 0 ? total : AVERROR(EOVERFLOW);

            ret = pread(
                    ctx->fd,
                    buf + total,
                    (size_t)(size - total),
                    (off_t)(ctx->offset + total)
            );

            if (ret < 0) {

                if (errno == EINTR)
                    continue;

                /*
                 * Pipes/FIFOs may reject pread().
                 * Permanently switch to sequential I/O.
                 */
                if (errno == ESPIPE) {
                    ctx->positional_io = 0;

                    if (lseek(ctx->fd,
                              (off_t)ctx->offset,
                              SEEK_SET) < 0) {
                        if (errno == ESPIPE)
                            ; /* genuinely non-seekable */
                        else
                            return total > 0 ?
                                   total :
                                   AVERROR(errno);
                    }

                    continue;
                }

                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return total > 0 ?
                           total :
                           AVERROR(EAGAIN);
                }

                return total > 0 ?
                       total :
                       AVERROR(errno);
            }

        } else {

            /*
             * Sequential fallback.
             *
             * If the FD is seekable, synchronize its kernel position
             * with our logical offset before reading.
             */
            if (ctx->seekable) {
                if (lseek(ctx->fd,
                          (off_t)ctx->offset,
                          SEEK_SET) < 0) {
                    return total > 0 ?
                           total :
                           AVERROR(errno);
                }
            }

            ret = read(
                    ctx->fd,
                    buf + total,
                    (size_t)(size - total)
            );

            if (ret < 0) {

                if (errno == EINTR)
                    continue;

                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return total > 0 ?
                           total :
                           AVERROR(EAGAIN);
                }

                return total > 0 ?
                       total :
                       AVERROR(errno);
            }
        }

        /*
         * EOF.
         */
        if (ret == 0) {
            return total > 0 ?
                   total :
                   AVERROR_EOF;
        }

        total += (int)ret;

        /*
         * A short read is perfectly valid.
         *
         * Especially important for pipes/streams.
         */
        if (ret < size - total)
            break;
    }

    ctx->offset += total;

    return total;
}


/* ------------------------------------------------------------- */
/* Write                                                         */
/* ------------------------------------------------------------- */

static int appfd_write(URLContext *h,
                           const unsigned char *buf,
                           int size)
{
    AppFdContext *ctx;
    int total = 0;

    if (!h || !buf || size <= 0)
        return AVERROR(EINVAL);

    ctx = h->priv_data;

    if (!ctx || ctx->fd < 0)
        return AVERROR(EBADF);

    if (!ctx->writable)
        return AVERROR(EACCES);

    while (total < size) {
        ssize_t ret;

        if (ctx->positional_io) {

            if (ctx->offset > INT64_MAX - total)
                return total > 0 ?
                       total :
                       AVERROR(EOVERFLOW);

            ret = pwrite(
                    ctx->fd,
                    buf + total,
                    (size_t)(size - total),
                    (off_t)(ctx->offset + total)
            );

            if (ret < 0) {

                if (errno == EINTR)
                    continue;

                if (errno == ESPIPE) {
                    /*
                     * Switch permanently to sequential writes.
                     */
                    ctx->positional_io = 0;
                    continue;
                }

                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return total > 0 ?
                           total :
                           AVERROR(EAGAIN);
                }

                return total > 0 ?
                       total :
                       AVERROR(errno);
            }

        } else {

            /*
             * For seekable descriptors, keep kernel offset synchronized.
             */
            if (ctx->seekable) {
                if (lseek(ctx->fd,
                          (off_t)ctx->offset,
                          SEEK_SET) < 0) {
                    return total > 0 ?
                           total :
                           AVERROR(errno);
                }
            }

            ret = write(
                    ctx->fd,
                    buf + total,
                    (size_t)(size - total)
            );

            if (ret < 0) {

                if (errno == EINTR)
                    continue;

                if (errno == EAGAIN || errno == EWOULDBLOCK) {
                    return total > 0 ?
                           total :
                           AVERROR(EAGAIN);
                }

                return total > 0 ?
                       total :
                       AVERROR(errno);
            }
        }

        /*
         * A zero-byte write is not useful and avoiding an infinite
         * loop is important for unusual descriptors.
         */
        if (ret == 0) {
            return total > 0 ?
                   total :
                   AVERROR(EIO);
        }

        total += (int)ret;

        /*
         * Track logical output size.
         *
         * This also works if FFmpeg seeks backwards and overwrites
         * an existing region.
         */
        ctx->offset += ret;

        if (ctx->data_size < ctx->offset)
            ctx->data_size = ctx->offset;
    }

    return total;
}


/* ------------------------------------------------------------- */
/* Seek                                                          */
/* ------------------------------------------------------------- */

static int64_t appfd_seek(URLContext *h,
                              int64_t offset,
                              int whence)
{
    AppFdContext *ctx;
    int clean_whence;
    int64_t base;
    int64_t new_offset;

    if (!h)
        return AVERROR(EINVAL);

    ctx = h->priv_data;

    if (!ctx || ctx->fd < 0)
        return AVERROR(EBADF);

    clean_whence = whence & ~AVSEEK_FORCE;

    /*
     * FFmpeg asks for the size using:
     *
     *     AVSEEK_SIZE
     */
    if (clean_whence == AVSEEK_SIZE) {

        if (ctx->data_size >= 0)
            return ctx->data_size;

        return AVERROR(ENOSYS);
    }

    /*
     * Non-seekable FD.
     */
    if (!ctx->seekable)
        return AVERROR(ESPIPE);

    switch (clean_whence) {

        case SEEK_SET:
            base = 0;
            break;

        case SEEK_CUR:
            base = ctx->offset;
            break;

        case SEEK_END:
            if (ctx->data_size < 0)
                return AVERROR(ENOSYS);

            base = ctx->data_size;
            break;

        default:
            return AVERROR(EINVAL);
    }

    /*
     * Overflow-safe addition.
     */
    if (offset > 0 && base > INT64_MAX - offset)
        return AVERROR(EOVERFLOW);

    if (offset < 0 && base < INT64_MIN - offset)
        return AVERROR(EOVERFLOW);

    new_offset = base + offset;

    if (new_offset < 0)
        return AVERROR(EINVAL);

    if (appfd_check_offset(new_offset) < 0)
        return AVERROR(EOVERFLOW);

    /*
     * Important:
     *
     * For writable files, seeking beyond EOF is valid.
     * FFmpeg may create sparse output files or seek before writing.
     *
     * For input, seeking beyond EOF is also allowed here.
     * The subsequent read simply returns EOF.
     */
    ctx->offset = new_offset;

    return new_offset;
}


/* ------------------------------------------------------------- */
/* Open                                                          */
/* ------------------------------------------------------------- */

static int appfd_open(URLContext *h,
                          const char *url,
                          int flags)
{
    AppFdContext *ctx;
    int supplied_fd;
    int duplicated_fd;
    int fd_flags;
    int acc_mode;
    int writable;
    int64_t size = -1;

    if (!h || !url)
        return AVERROR(EINVAL);

    ctx = h->priv_data;

    if (!ctx)
        return AVERROR(EINVAL);

    ctx->fd = -1;
    ctx->offset = 0;
    ctx->data_size = -1;
    ctx->seekable = 0;
    ctx->writable = 0;
    ctx->positional_io = 0;

    /*
     * Parse:
     *
     *     appfd:190
     */
    if (appfd_parse_fd(url, &supplied_fd) < 0) {
        av_log(
                h,
                AV_LOG_ERROR,
                "appfd: invalid URL '%s'\n",
                url
        );

        return AVERROR(EINVAL);
    }

    /*
     * Validate supplied FD.
     */
    fd_flags = fcntl(supplied_fd, F_GETFL);

    if (fd_flags < 0) {
        av_log(
                h,
                AV_LOG_ERROR,
                "appfd: invalid fd %d: %s\n",
                supplied_fd,
                strerror(errno)
        );

        return AVERROR(errno);
    }

    acc_mode = fd_flags & O_ACCMODE;

    writable = !!(flags & AVIO_FLAG_WRITE);

    /*
     * Validate access mode.
     */
    if (writable) {

        if (acc_mode != O_WRONLY &&
            acc_mode != O_RDWR) {

            av_log(
                    h,
                    AV_LOG_ERROR,
                    "appfd: fd %d is not writable\n",
                    supplied_fd
            );

            return AVERROR(EACCES);
        }

    } else {

        if (acc_mode == O_WRONLY) {

            av_log(
                    h,
                    AV_LOG_ERROR,
                    "appfd: fd %d is not readable\n",
                    supplied_fd
            );

            return AVERROR(EACCES);
        }
    }

    /*
     * Duplicate the FD.
     *
     * VERY IMPORTANT:
     *
     * FFmpeg now owns the duplicate, NOT the application's FD.
     *
     * If FFmpeg closes its protocol, fd 190 remains valid in your
     * application.
     */
#ifdef F_DUPFD_CLOEXEC
    duplicated_fd = fcntl(supplied_fd, F_DUPFD_CLOEXEC, 0);
#else
    duplicated_fd = dup(supplied_fd);
#endif

    if (duplicated_fd < 0) {
        av_log(
                h,
                AV_LOG_ERROR,
                "appfd: dup(%d) failed: %s\n",
                supplied_fd,
                strerror(errno)
        );

        return AVERROR(errno);
    }

#ifndef F_DUPFD_CLOEXEC
    /*
     * Best effort close-on-exec.
     */
    {
        int flags2 = fcntl(duplicated_fd, F_GETFD);

        if (flags2 >= 0)
            (void)fcntl(
                duplicated_fd,
                F_SETFD,
                flags2 | FD_CLOEXEC
            );
    }
#endif

    ctx->fd = duplicated_fd;
    ctx->writable = writable;

    /*
     * Detect seekability and size.
     */
    ctx->seekable = appfd_detect_seekable(
            ctx->fd,
            &size
    );

    if (ctx->seekable) {
        ctx->data_size = size;
    } else {
        ctx->data_size = -1;
    }

    /*
     * Positional I/O is preferred.
     *
     * If it fails with ESPIPE later, read/write automatically
     * falls back to sequential I/O.
     */
    ctx->positional_io =
            appfd_initial_positional_io(ctx->fd);

    /*
     * Since our logical position starts at zero, do not inherit
     * the original FD's current kernel position.
     *
     * pread/pwrite don't care, but the sequential fallback does.
     */
    if (ctx->seekable) {
        if (lseek(ctx->fd, 0, SEEK_SET) < 0) {

            av_log(
                    h,
                    AV_LOG_ERROR,
                    "appfd: failed to seek fd %d: %s\n",
                    ctx->fd,
                    strerror(errno)
            );

            close(ctx->fd);
            ctx->fd = -1;

            return AVERROR(errno);
        }
    }

    /*
     * FFmpeg uses this to determine whether seeking is available.
     */
    h->is_streamed = !ctx->seekable;

    av_log(
            h,
            AV_LOG_VERBOSE,
            "appfd: opened fd=%d "
            "(original=%d, writable=%d, seekable=%d, size=%" PRId64 ")\n",
            ctx->fd,
            supplied_fd,
            ctx->writable,
            ctx->seekable,
            ctx->data_size
    );

    return 0;
}


/* ------------------------------------------------------------- */
/* Close                                                         */
/* ------------------------------------------------------------- */

static int appfd_close(URLContext *h)
{
    AppFdContext *ctx;
    int ret = 0;

    if (!h)
        return 0;

    ctx = h->priv_data;

    if (!ctx)
        return 0;

    if (ctx->fd >= 0) {

        /*
         * For output, make a best effort to flush filesystem data.
         *
         * Do not make failure to fsync() prevent the FD from closing.
         */
        if (ctx->writable) {

            if (fsync(ctx->fd) < 0) {
                av_log(
                        h,
                        AV_LOG_WARNING,
                        "appfd: fsync failed: %s\n",
                        strerror(errno)
                );
            }

            /*
             * Only truncate regular files.
             *
             * This is useful when an existing output FD was reused
             * and the new output is smaller than the previous content.
             */
            if (ctx->data_size >= 0) {
                struct stat st;

                if (fstat(ctx->fd, &st) == 0 &&
                    S_ISREG(st.st_mode)) {

                    if (ftruncate(
                            ctx->fd,
                            (off_t)ctx->data_size
                    ) < 0) {

                        av_log(
                                h,
                                AV_LOG_WARNING,
                                "appfd: ftruncate failed: %s\n",
                                strerror(errno)
                        );
                    }
                }
            }
        }

        /*
         * This closes ONLY the duplicated FD.
         *
         * The application's original FD remains open.
         */
        if (close(ctx->fd) < 0)
            ret = AVERROR(errno);

        ctx->fd = -1;
    }

    return ret;
}


/* ------------------------------------------------------------- */
/* Get underlying FD                                              */
/* ------------------------------------------------------------- */

static int appfd_get_handle(URLContext *h)
{
    AppFdContext *ctx;

    if (!h)
        return -1;

    ctx = h->priv_data;

    if (!ctx)
        return -1;

    return ctx->fd;
}


/* ------------------------------------------------------------- */
/* AVClass                                                         */
/* ------------------------------------------------------------- */

#if CONFIG_APPFD_PROTOCOL

static const AVClass appfd_class = {
        .class_name = "appfd",
        .item_name  = av_default_item_name,
        .version    = LIBAVUTIL_VERSION_INT,
};


/* ------------------------------------------------------------- */
/* URLProtocol                                                     */
/* ------------------------------------------------------------- */

const URLProtocol ff_appfd_protocol = {
        .name                = "appfd",

        .url_open            = appfd_open,
        .url_read            = appfd_read,
        .url_write           = appfd_write,
        .url_seek            = appfd_seek,
        .url_close           = appfd_close,

        .url_get_file_handle = appfd_get_handle,

        .priv_data_size      = sizeof(AppFdContext),
        .priv_data_class     = &appfd_class,

        /*
         * This is NOT a network protocol.
         */
        .flags               = 0,
};

#endif /* CONFIG_APPFD_PROTOCOL */