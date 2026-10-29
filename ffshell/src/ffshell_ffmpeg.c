/*
 * FFShell wrapper - embeds the real FFmpeg CLI frontend into libffmpeg.so.
 *
 * This translation unit is linked together with the FFmpeg library objects
 * and the patched fftools objects (ffshell_cli_main, ffshell_request_cancel)
 * into the single umbrella libffmpeg.so. No external ffmpeg process, no
 * execve(), no shell is involved.
 */
#include "../include/ffshell/ffshell_ffmpeg.h"

#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <limits.h>
#include <sys/socket.h>

#include <libavutil/log.h>
#include <libavutil/mem.h>
#include <libavutil/avutil.h>
#include <libavutil/avstring.h>

#define FFSHELL_LOG_LINE 8192

/* ------------------------------------------------------------------ */
/* Command string parsing — FFmpeg cmdutils tokenization                */
/* Uses av_get_token semantics: single-quote + backslash escaping,     */
/* whitespace outside quotes delimits arguments. Double quotes are     */
/* additionally supported for shell compatibility. Whitespace chars    */
/* are " \t\n\r". Each token is av_malloc'd (av_get_token style)  */
/* so av_free must be used.                                           */
/* ------------------------------------------------------------------ */

#define FFSHELL_WS " \t\n\r"

/*
 * POSIX shell line-continuation: `<backslash><newline>` (and `<backslash><CR>`,
 * `<backslash><CRLF>` for pasted/Windows text) is removed BEFORE tokenization —
 * the same job a real shell does for you before execve(). Without this step the
 * tokenizer below would copy the literal LF into a token (creating a stray
 * "\n" argv entry) and multiline commands would fail. We strip globally (matching
 * the pre-token phase of bash/zsh/cmd-parsing); inside a '...' literal this also
 * strips, which is acceptable for ffmpeg paths. `C:\path` is untouched because
 * the backslash is not immediately followed by a newline.
 */
static char *ffshell_normalize_line_continuations(const char *s)
{
    if (!s)
        return NULL;
    size_t n = strlen(s);
    char *out = malloc(n + 1);
    if (!out)
        return NULL;
    size_t i = 0, j = 0;
    while (s[i]) {
        if (s[i] == '\\' && s[i + 1] == '\n') {
            i += 2;
        } else if (s[i] == '\\' && s[i + 1] == '\r' && s[i + 2] == '\n') {
            i += 3;
        } else if (s[i] == '\\' && s[i + 1] == '\r') {
            i += 2;
        } else {
            out[j++] = s[i++];
        }
    }
    out[j] = '\0';
    return out;
}

static char *ffshell_get_token_ws(const char **buf)
{
    const char *p = *buf;
    p += strspn(p, FFSHELL_WS);
    if (!*p) {
        *buf = p;
        return NULL;
    }
    char *out = av_malloc(strlen(p) + 1);
    if (!out)
        return NULL;
    char *q = out;

    while (*p && !strchr(FFSHELL_WS, *p)) {
        /* Defensive: in case a raw continuation survives normalization,
         * treat `<backslash><newline>` as whitespace boundary, not content. */
        if (*p == '\\' && *(p + 1) == '\n') {
            p += 2;
            continue;
        }
        if (*p == '\\' && *(p + 1) == '\r' && *(p + 2) == '\n') {
            p += 3;
            continue;
        }
        if (*p == '\\' && *(p + 1) == '\r') {
            p += 2;
            continue;
        }
        if (*p == '\\' && *(p + 1)) {
            p++;
            *q++ = *p++;
        } else if (*p == '\'') {
            p++; /* skip opening ' */
            while (*p && *p != '\'')
                *q++ = *p++;
            if (*p == '\'')
                p++; /* skip closing ' */
        } else if (*p == '"') {
            p++; /* skip opening " */
            while (*p && *p != '"') {
                if (*p == '\\' && *(p + 1)) {
                    p++;
                    *q++ = *p++;
                } else {
                    *q++ = *p++;
                }
            }
            if (*p == '"')
                p++; /* skip closing " */
        } else {
            *q++ = *p++;
        }
    }
    *q = '\0';
    char *ret = av_realloc(out, (size_t)(q - out + 1));
    if (ret)
        out = ret;
    *buf = p;
    return out;
}

static int ffshell_parse_command(const char *command, int *argc_out, char ***argv_out)
{
    if (!command || !argc_out || !argv_out)
        return -1;

    /* Emulate the shell's `<backslash><newline>` line-continuation removal. */
    char *norm = ffshell_normalize_line_continuations(command);
    if (!norm)
        return -1;

    const char *p = norm;
    p += strspn(p, FFSHELL_WS);
    if (!*p) {
        free(norm);
        return -1;
    }

    int cap = 8;
    int argc = 0;
    char **argv = malloc((size_t)cap * sizeof(*argv));
    if (!argv)
        return -1;

    const char *cur = p;
    while (1) {
        cur = p;
        cur += strspn(cur, FFSHELL_WS);
        if (!*cur)
            break;
        char *tok = ffshell_get_token_ws(&p);
        if (!tok)
            break;
        if (tok[0] == '\0') {
            av_free(tok);
            continue;
        }
        if (argc >= cap) {
            int ncap = cap * 2;
            char **n = realloc(argv, (size_t)ncap * sizeof(*n));
            if (!n) {
                av_free(tok);
                for (int i = 0; i < argc; i++)
                    av_free(argv[i]);
                free(argv);
                free(norm);
                return -1;
            }
            argv = n;
            cap = ncap;
        }
        argv[argc++] = tok;
    }

    if (argc == 0) {
        free(argv);
        free(norm);
        return -1;
    }
    *argc_out = argc;
    *argv_out = argv;
    free(norm);
    return 0;
}

static void ffshell_free_parsed(int argc, char **argv)
{
    if (!argv)
        return;
    for (int i = 0; i < argc; i++)
        av_free(argv[i]);
    free(argv);
}

/*
 * Provided by fftools inside this same library:
 *  - ffmpeg_main:        the CLI entry point (compiled with -Dmain=ffmpeg_main)
 *  - ffprobe_main:       the ffprobe CLI entry point (compiled with -Dmain=ffprobe_main)
 *  - ffshell_* hooks:    tiny integration helpers appended to fftools/ffmpeg.c,
 *                        fftools/ffmpeg_opt.c and fftools/ffprobe.c by android.sh
 *                        (cancel + interrupt-state reset + io-path rewrite).
 */
extern int  ffmpeg_main(int argc, char **argv);
extern int  ffprobe_main(int argc, char **argv);
extern void ffshell_request_cancel(void);
extern void ffshell_reset_interrupt_state(void);
extern void ffshell_reset_state(void);

/* Appended to ffmpeg_opt.c / ffprobe.c: use each tool's own tokenizer to
 * identify input/output args and swap in wrapper-provided URLs. */
extern int  ffshell_rewrite_io_paths(int argc, char **argv);
extern int  ffshell_rewrite_probe_paths(int argc, char **argv);

/* Original signal actions saved before the first run; restored after every
 * run so the embedding application owns its process signals again. */
static struct sigaction g_saved_sig[3];
static int g_saved_sig_valid = 0;

static const int g_watch_sigs[3] = { SIGINT, SIGTERM,
#ifdef SIGQUIT
                                     SIGQUIT };
#else
                                     SIGINT };
#endif

#ifdef __linux__


static long fd_inode(int fd)
{
    char path[32], link[128];
    snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    long n = (long)readlink(path, link, sizeof(link) - 1);
    if (n <= 0)
        return -1;
    link[n] = '\0';
    /* link looks like "pipe:[12345]" or "socket:[12345]" */
    const char *open_br = strchr(link, '[');
    if (!open_br)
        return -1;
    return strtoll(open_br + 1, NULL, 10);
}

static long readlink_fdfd(int fd, char *out, size_t outsz)
{
    char path[32];
    snprintf(path, sizeof(path), "/proc/self/fd/%d", fd);
    long n = (long)readlink(path, out, outsz - 1);
    if (n > 0)
        out[n] = '\0';
    return n;
}

#endif /* __linux__ */


/* ------------------------------------------------------------------ */
/* Global state                                                        */
/* ------------------------------------------------------------------ */

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static _Atomic int g_running = 0;
static _Atomic int g_cancel_requested = 0;
static _Atomic int g_cli_thread = 0;

static ffshell_log_callback g_log_cb   = NULL;
static void *g_log_user = NULL;



/* Original log state captured once at load, restored per-run without hardcoding
 * AV_LOG_INFO. This preserves FFmpeg's build-time default even if upstream
 * changes it, while keeping per-command isolation (fresh→transcode == 
 * fresh→-version→transcode). User -loglevel in command still wins via
 * parse_loglevel after restore. */
static int g_orig_log_level = INT_MIN;
static int g_orig_log_flags = INT_MIN;
static int g_orig_hide_banner = 0;
static _Atomic int g_orig_saved = 0;

static void ffshell_ensure_orig_saved(void)
{
    int expected = 0;
    if (atomic_load(&g_orig_saved))
        return;
    if (!atomic_compare_exchange_strong(&g_orig_saved, &expected, 1))
        return;
    g_orig_log_level = av_log_get_level();
    g_orig_log_flags = av_log_get_flags();
    extern int hide_banner;
    g_orig_hide_banner = hide_banner;
}

__attribute__((constructor))
static void ffshell_init_orig(void)
{
    ffshell_ensure_orig_saved();
}

/* ------------------------------------------------------------------ */
/* Input-path replacement hook                                        */
/* ------------------------------------------------------------------ */

static ffshell_path_callback g_path_cb    = NULL;
static void                 *g_path_user  = NULL;
/* Track every URL returned by the callback so we can free after run and
 * reliably map raw→argv without leaking or double-freeing. Thread-safe
 * via g_lock (only mutated while g_running==1 or under lock). */
static char **g_rewritten_urls = NULL;
static int    g_rewritten_cnt = 0;
static int    g_rewritten_cap = 0;

void ffshell_set_path_callback(
    ffshell_path_callback callback,
    void *user_data)
{
    pthread_mutex_lock(&g_lock);
    g_path_cb   = callback;
    g_path_user = user_data;
    pthread_mutex_unlock(&g_lock);
}

static void ffshell_track_rewritten(char *url)
{
    if (!url) return;
    pthread_mutex_lock(&g_lock);
    if (g_rewritten_cnt >= g_rewritten_cap) {
        int ncap = g_rewritten_cap ? g_rewritten_cap * 2 : 8;
        char **n = realloc(g_rewritten_urls, (size_t)ncap * sizeof(*n));
        if (n) { g_rewritten_urls = n; g_rewritten_cap = ncap; }
        else { pthread_mutex_unlock(&g_lock); return; }
    }
    g_rewritten_urls[g_rewritten_cnt++] = url;
    pthread_mutex_unlock(&g_lock);
}

static void ffshell_cleanup_rewritten(void)
{
    pthread_mutex_lock(&g_lock);
    for (int i = 0; i < g_rewritten_cnt; i++) {
        free(g_rewritten_urls[i]);
    }
    free(g_rewritten_urls);
    g_rewritten_urls = NULL;
    g_rewritten_cnt = 0;
    g_rewritten_cap = 0;
    pthread_mutex_unlock(&g_lock);
}


/* Returns 1 if raw_path is a synthetic lavfi/filter source and not a
 * genuine file path that should be offered to the path callback.
 * Example: "testsrc=duration=10:size=1280x720:rate=30" (from
 * "ffmpeg -f lavfi -i testsrc=...") must NOT be treated as a file.
 * Genuine files on Android always contain '/' or have a file extension
 * and never look like lavfi descriptors (contain '=' without '/'). */
static int ffshell_is_synthetic_path(const char *raw_path, int is_output)
{
    if (!raw_path || !*raw_path)
        return 1;
    /* URLs and pipes are not files */
    if (strstr(raw_path, "://"))
        return 1;
    if (!strncmp(raw_path, "pipe:", 5))
        return 1;
    /* Only inputs can be lavfi sources; outputs are almost always files */
    if (!is_output) {
        const char *eq = strchr(raw_path, '=');
        if (eq) {
            /* lavfi descriptors contain '=' and ':'/',' and no '/' */
            if (!strchr(raw_path, '/') && !strchr(raw_path, '\\')) {
                /* Has '=' and no slash -> very likely lavfi, not a file */
                return 1;
            }
            /* Also catch cases like "testsrc=..." even with slash? Check prefix */
            size_t pre = (size_t)(eq - raw_path);
            if (pre < 32) {
                static const char *const lavfi_prefixes[] = {
                    "testsrc", "testsrc2", "color", "smptebars", "smptehdbars",
                    "allrgb", "allyuv", "cellauto", "mandelbrot", "life",
                    "haldclutsrc", "nullsrc", "anullsrc", "sine", "aevalsrc",
                    "anoisesrc", "aevalsrc", "frei0r_src", "mptestsrc", NULL
                };
                char tmp[32];
                if (pre < sizeof(tmp)) {
                    memcpy(tmp, raw_path, pre);
                    tmp[pre] = '\0';
                    for (int i = 0; lavfi_prefixes[i]; i++) {
                        if (!strcmp(tmp, lavfi_prefixes[i]))
                            return 1;
                    }
                }
            }
        } else {
            /* Bare lavfi source names without '=' (e.g. "testsrc") */
            static const char *const lavfi_bare[] = {
                "testsrc", "testsrc2", "color", "smptebars", "smptehdbars",
                "allrgb", "allyuv", "cellauto", "mandelbrot", "life",
                "haldclutsrc", "nullsrc", "anullsrc", "sine", "aevalsrc",
                "anoisesrc", NULL
            };
            for (int i = 0; lavfi_bare[i]; i++) {
                if (!strcmp(raw_path, lavfi_bare[i]))
                    return 1;
            }
        }
    }
    return 0;
}

__attribute__((visibility("hidden")))
char *ffshell_path_hook_request(int is_output, const char *raw_path)
{
    ffshell_path_callback cb;
    void *user;

    if (!raw_path || !*raw_path)
        return NULL;

    /* Do not invoke user callback for synthetic lavfi/filter sources */
    if (ffshell_is_synthetic_path(raw_path, is_output))
        return NULL;

    pthread_mutex_lock(&g_lock);
    cb   = g_path_cb;
    user = g_path_user;
    pthread_mutex_unlock(&g_lock);

    if (!cb)
        return NULL;

    char *url = cb(is_output, raw_path, user);
    if (url) ffshell_track_rewritten(url);
    return url;
}

/* ------------------------------------------------------------------ */
/* Caller-owned path hook for per-file image2 output (SAF patterns)     */
/* ------------------------------------------------------------------ */

static char *ffshell_owned_path_hook_request(int is_output, const char *raw_path, int *fd_to_close)
{
    ffshell_path_callback cb;
    void *user;
    char *url;

    if (!raw_path || !*raw_path)
        return NULL;
    if (strstr(raw_path, "://"))
        return NULL;
    if (!strncmp(raw_path, "pipe:", 5))
        return NULL;
    if (fd_to_close)
        *fd_to_close = -1;

    pthread_mutex_lock(&g_lock);
    cb   = g_path_cb;
    user = g_path_user;
    pthread_mutex_unlock(&g_lock);

    if (!cb)
        return NULL;

    url = cb(is_output, raw_path, user);
    if (!url)
        return NULL;

    if (fd_to_close && !strncmp(url, "appfd:", 6)) {
        const char *p = url + 6;
        char *end = NULL;
        long fd;
        errno = 0;
        fd = strtol(p, &end, 10);
        if (errno == 0 && end != p && *end == '\0' &&
            fd >= 0 && fd <= INT_MAX)
            *fd_to_close = (int)fd;
    }
    return url;
}

__attribute__((visibility("hidden")))
char *ffshell_saf_pattern_path_hook_request(const char *raw_path, int *fd_to_close)
{
    return ffshell_owned_path_hook_request(1, raw_path, fd_to_close);
}

__attribute__((visibility("default"), used))
int ffshell_saf_pattern_output_supported(void)
{
    return 1;
}

/* ------------------------------------------------------------------ */
/* Concat-entry path hook                                             */
/* ------------------------------------------------------------------ */

/*
 * Called by the patched libavformat/concatdec.c immediately before each
 * entry's avformat_open_input(). Unlike ffshell_path_hook_request():
 *  - entries are known files, so the lavfi heuristic must not run;
 *  - the returned string is owned by concatdec (freed after the open),
 *    not retained in g_rewritten_urls;
 *  - when the result is appfd:N, N is handed back so concatdec can close
 *    the original detached descriptor after appfd_open() duplicated it.
 *
 * Returns NULL to keep the upstream-resolved URL. On success the caller
 * must av_free() the returned string and close *fd_to_close when >= 0.
 */
__attribute__((visibility("hidden")))
char *ffshell_concat_path_hook_request(const char *raw_path, int *fd_to_close)
{
    ffshell_path_callback cb;
    void *user;
    char *url;

    if (fd_to_close)
        *fd_to_close = -1;
    if (!raw_path || !*raw_path)
        return NULL;

    /* URLs and pipes are passed through untouched, mirroring pathCallback. */
    if (strstr(raw_path, "://"))
        return NULL;
    if (!strncmp(raw_path, "pipe:", 5))
        return NULL;

    pthread_mutex_lock(&g_lock);
    cb   = g_path_cb;
    user = g_path_user;
    pthread_mutex_unlock(&g_lock);
    if (!cb)
        return NULL;

    url = cb(0, raw_path, user);
    if (!url)
        return NULL;

    if (fd_to_close && !strncmp(url, "appfd:", 6)) {
        const char *p = url + 6;
        char *end = NULL;
        long fd;

        errno = 0;
        fd = strtol(p, &end, 10);
        if (errno == 0 && end != p && *end == '\0' &&
            fd >= 0 && fd <= INT_MAX)
            *fd_to_close = (int)fd;
    }
    return url;
}

/* ------------------------------------------------------------------ */
/* Short-circuit commands (-version/-h/...) never carry real input     */
/* files - skip rewrite for them.                                      */
/* ------------------------------------------------------------------ */
static int argv_has_info_flag(int argc, char **argv)
{
    static const char *const flags[] = {
        "-version", "-L", "-license", "-h", "-help", "-?", "--help",
        "-buildconf", "-formats", "-muxers", "-demuxers", "-devices",
        "-codecs", "-decoders", "-encoders", "-bsfs", "-protocols",
        "-filters", "-pix_fmts", "-layouts", "-sample_fmts", "-dispositions",
        "-colors", "-sources", "-sinks", "-hwaccels",
    };

    /* compare full token so "-hide_banner" != "-h" etc. */
    for (int i = 0; i < argc; i++) {

        if (!argv[i])
            continue;

        for (size_t f = 0; f < sizeof(flags) / sizeof(flags[0]); f++)
            if (!strcmp(argv[i], flags[f]))
                return 1;
    }

    return 0;
}

/* ------------------------------------------------------------------ */
/* Log forwarding — raw 1:1 terminal bytes (merged stdout+stderr)      */
/* No av_log hook, no source patches. The log callback receives raw    */
/* chunks preserving \r, \n, ANSI CSI/SGR and UTF-8 split across       */
/* reads — feed directly to TerminalParser::write(data,len).           */
/* User controls verbosity exactly like official ffmpeg via -loglevel,  */
/* -hide_banner, -stats/-nostats in the command string. Progress is    */
/* delivered via the standard ffmpeg stats lines in the log (no        */
/* separate progress callback).                                         */
/* ------------------------------------------------------------------ */

void ffshell_set_log_callback(ffshell_log_callback callback,void *user_data)
{
    pthread_mutex_lock(&g_lock);
    g_log_cb   = callback;
    g_log_user = user_data;
    pthread_mutex_unlock(&g_lock);
}

int ffshell_log_cb_active(void)
{
    int active;
    pthread_mutex_lock(&g_lock);
    active = g_log_cb != NULL;
    pthread_mutex_unlock(&g_lock);
    return active;
}

/* Legacy shim kept for android.sh injected helpers (log_callback_help/report).
 * When someone still calls it, forward as raw chunk via length. */
void ffshell_forward_log(int level, const char *msg)
{
    if (!msg) return;
    size_t len = strlen(msg);
    pthread_mutex_lock(&g_lock);
    ffshell_log_callback cb = g_log_cb;
    void *user = g_log_user;
    pthread_mutex_unlock(&g_lock);
    if (cb) cb(level, msg, len, user);
}

static void ffshell_forward_raw(int level, const char *data, size_t len)
{
    if (!data || len == 0) return;
    pthread_mutex_lock(&g_lock);
    ffshell_log_callback cb = g_log_cb;
    void *user = g_log_user;
    pthread_mutex_unlock(&g_lock);
    if (cb) cb(level, data, len, user);
}

/* ------------------------------------------------------------------ */
/* Raw terminal capture — merged stdout+stderr, 1:1 byte identity       */
/* Uses AF_UNIX socketpair so shutdown(SHUT_RD) can force EOF even if  */
/* a stray dup of the write end survives.                              */
/* ------------------------------------------------------------------ */
#define TERM_BUF_SIZE 8192
struct raw_term_ctx { int fd; };
static void *raw_terminal_reader_thread(void *arg)
{
    struct raw_term_ctx *ctx = arg;
    char buf[TERM_BUF_SIZE];
    ssize_t n;
    while ((n = read(ctx->fd, buf, sizeof(buf))) > 0) {
        ffshell_forward_raw(AV_LOG_INFO, buf, (size_t)n);
    }
    close(ctx->fd);
    free(ctx);
    return NULL;
}

static int term_saved_stdout = -1;
static int term_saved_stderr = -1;
static int term_pipe_read = -1;

static int setup_raw_terminal_capture(pthread_t *thr)
{
    int sv[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, sv) != 0) return -1;
    term_pipe_read = sv[0];
    int write_fd = sv[1];

    term_saved_stdout = dup(STDOUT_FILENO);
    if (term_saved_stdout < 0) { close(sv[0]); close(sv[1]); return -1; }
    term_saved_stderr = dup(STDERR_FILENO);
    if (term_saved_stderr < 0) { close(sv[0]); close(sv[1]); close(term_saved_stdout); term_saved_stdout=-1; return -1; }

    /* Keep real TTY semantics: do NOT force AV_LOG_FORCE_COLOR — let
     * libavutil/log.c:check_color_terminal (isatty+TERM) decide, exactly
     * as real linux `ffmpeg` does. Caller may set AV_LOG_FORCE_COLOR=1
     * explicitly to force ANSI for TerminalParser. */
    /* Match real TTY buffering: stdout line-buffered (isatty), stderr unbuffered */
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);

    if (dup2(write_fd, STDOUT_FILENO) < 0) { close(sv[0]); close(sv[1]); close(term_saved_stdout); close(term_saved_stderr); term_saved_stdout=term_saved_stderr=-1; return -1; }
    if (dup2(write_fd, STDERR_FILENO) < 0) { /* restore stdout on failure */ dup2(term_saved_stdout, STDOUT_FILENO); close(sv[0]); close(write_fd); close(term_saved_stdout); close(term_saved_stderr); term_saved_stdout=term_saved_stderr=-1; return -1; }
    close(write_fd); /* now 1 and 2 both reference the socket write end */

    struct raw_term_ctx *ctx = calloc(1, sizeof(*ctx));
    if (!ctx) { dup2(term_saved_stdout, STDOUT_FILENO); dup2(term_saved_stderr, STDERR_FILENO); close(term_saved_stdout); close(term_saved_stderr); close(term_pipe_read); term_saved_stdout=term_saved_stderr=-1; term_pipe_read=-1; return -1; }
    ctx->fd = term_pipe_read;
    if (pthread_create(thr, NULL, raw_terminal_reader_thread, ctx) != 0) {
        dup2(term_saved_stdout, STDOUT_FILENO);
        dup2(term_saved_stderr, STDERR_FILENO);
        close(term_saved_stdout); close(term_saved_stderr);
        close(term_pipe_read);
        free(ctx);
        term_saved_stdout=term_saved_stderr=-1; term_pipe_read=-1;
        return -1;
    }
    return 0;
}

static void teardown_raw_terminal_capture(pthread_t thr)
{
    if (term_saved_stdout < 0 && term_saved_stderr < 0) return;
    /* Flush stdio before restoring real fds — otherwise buffered bytes are lost */
    fflush(stdout);
    fflush(stderr);
    if (term_saved_stdout >= 0) { dup2(term_saved_stdout, STDOUT_FILENO); close(term_saved_stdout); term_saved_stdout=-1; }
    if (term_saved_stderr >= 0) { dup2(term_saved_stderr, STDERR_FILENO); close(term_saved_stderr); term_saved_stderr=-1; }
    /* Write end refs (1 and 2) are now closed — reader should see EOF.
     * Force it even if a stray dup of the socket write end survived (e.g. pipe: protocol). */
    if (term_pipe_read >= 0) {
        shutdown(term_pipe_read, SHUT_RD);
        pthread_join(thr, NULL);
        term_pipe_read = -1;
    }
}

/* ------------------------------------------------------------------ */
/* Run                                                                 */
/* ------------------------------------------------------------------ */

static void save_signal_handlers(void)
{
    if (g_saved_sig_valid)
        return;
    for (int i = 0; i < 3; i++)
        sigaction(g_watch_sigs[i], NULL, &g_saved_sig[i]);
    g_saved_sig_valid = 1;
}

static void restore_signal_handlers(void)
{
    if (!g_saved_sig_valid)
        return;
    for (int i = 0; i < 3; i++)
        sigaction(g_watch_sigs[i], &g_saved_sig[i], NULL);
}

struct cli_thread_ctx {
    int  argc;
    char **argv;
    int  ret;
    int  is_ffprobe;
};

static void *cli_thread_main(void *arg)
{
    struct cli_thread_ctx *c = arg;
    /* Fix program_name clash in single libffmpeg.so umbrella (both ffmpeg.c
     * and ffprobe.c define program_name/program_birth_year, linker picks
     * first with --allow-multiple-definition, so ffprobe -version/-h would
     * show "ffmpeg version"). Set per-run based on is_ffprobe. */
    extern const char *program_name;
    extern const char *program_birth_year;
    program_name = c->is_ffprobe ? "ffprobe" : "ffmpeg";
    program_birth_year = c->is_ffprobe ? "2007" : "2000";
    if (c->is_ffprobe)
        c->ret = ffprobe_main(c->argc, c->argv);
    else
        c->ret = ffmpeg_main(c->argc, c->argv);

    free(c->argv);

    return NULL;
}


void ffshell_cancel(void)
{
    if (!atomic_load(&g_running))
        return;
    atomic_store(&g_cancel_requested, 1);
    ffshell_request_cancel();
}

const char *ffshell_get_version(void)
{
    return av_version_info();
}

ffshell_status ffshell_ffmpeg_run(const char *command)
{
    int expected = 0;

    if (!command || !*command)
        return FFSHELL_ERR_INVALID_ARGUMENT;
    {
        const char *tmp = command;
        tmp += strspn(tmp, FFSHELL_WS);
        if (!*tmp)
            return FFSHELL_ERR_INVALID_ARGUMENT;
    }

    if (!atomic_compare_exchange_strong(&g_running, &expected, 1))
        return FFSHELL_ERR_ALREADY_RUNNING;

    atomic_store(&g_cancel_requested, 0);

    int argc = 0;
    char **argv = NULL;
    if (ffshell_parse_command(command, &argc, &argv) != 0) {
        atomic_store(&g_running, 0);
        return FFSHELL_ERR_INVALID_ARGUMENT;
    }
    if (argc <= 0 || !argv || !argv[0]) {
        ffshell_free_parsed(argc, argv);
        atomic_store(&g_running, 0);
        return FFSHELL_ERR_INVALID_ARGUMENT;
    }

    ffshell_reset_interrupt_state();
    ffshell_reset_state();
    save_signal_handlers();
    /* Restore original log state saved at load (no hardcode) so user
     * -loglevel controls exactly like TTY and upstream default changes
     * are preserved. Also restore av_log callback: show_help/report set
     * it to helper/report callbacks that ignore level and leak TRACE
     * Writing block flood to the next transcode after OPT_EXIT. */
    ffshell_ensure_orig_saved();
    av_log_set_level(g_orig_log_level == INT_MIN ? AV_LOG_INFO : g_orig_log_level);
    av_log_set_flags(g_orig_log_flags == INT_MIN ? AV_LOG_SKIP_REPEATED : g_orig_log_flags);
    av_log_set_callback(av_log_default_callback);
    extern int hide_banner;
    hide_banner = g_orig_hide_banner;

    ffshell_status status = FFSHELL_ERR_INTERNAL;
    {
        const char *prog = (argv[0][0] == '-') ? "ffmpeg" : argv[0];
        int firstarg = (argv[0][0] == '-') ? 0 : 1;

        const int inject = 1; /* -nostdin */
        int total = 1 + (argc - firstarg) + inject + 1;
        char **full = calloc((size_t)total, sizeof(*full));
        int nargs  = 0;
        int ret = 1;

        if (!full) {
            ffshell_free_parsed(argc, argv);
            atomic_store(&g_running, 0);
            return FFSHELL_ERR_INTERNAL;
        }

        int has_nostdin = 0;
        for (int i = 0; i < argc; i++) {
            if (!argv[i]) continue;
            if (!strcmp(argv[i], "-nostdin") || !strcmp(argv[i], "-stdin")) has_nostdin = 1;
        }

        full[nargs++] = (char *)prog;

        if (!has_nostdin) full[nargs++] = (char *)"-nostdin";

        for (int i = firstarg; i < argc && argv[i]; i++)
            full[nargs++] = argv[i];

        ffshell_rewrite_io_paths(nargs, full);

        int use_term = 0;
        pthread_t term_thr;
        if (ffshell_log_cb_active()) {
            if (setup_raw_terminal_capture(&term_thr) == 0) use_term = 1;
        }




        {
            struct cli_thread_ctx cctx = { nargs, full, 0, 0 };

            pthread_t cli_thr;

            if (pthread_create(&cli_thr, NULL, cli_thread_main, &cctx) == 0) {
                atomic_store(&g_cli_thread, 1);
                pthread_join(cli_thr, NULL);
                atomic_store(&g_cli_thread, 0);
                ret = cctx.ret;
            } else {
                /* Fall back to running on the calling thread. */
                extern const char *program_name;
                extern const char *program_birth_year;
                program_name = "ffmpeg";
                program_birth_year = "2000";
                ret = ffmpeg_main(nargs, full);

                free(full);
            }
        }



        if (use_term) teardown_raw_terminal_capture(term_thr);

        restore_signal_handlers();
        ffshell_cleanup_rewritten();

        if (atomic_exchange(&g_cancel_requested, 0))
            status = FFSHELL_ERR_CANCELLED;
        else if (ret == 0)
            status = FFSHELL_OK;
        else
            status = FFSHELL_ERR_INTERNAL;

        ffshell_free_parsed(argc, argv);
        atomic_store(&g_running, 0);
        return status;
    }
}

ffshell_status ffshell_ffprobe_run(const char *command)
{
    int expected = 0;
    if (!command || !*command)
        return FFSHELL_ERR_INVALID_ARGUMENT;
    {
        const char *tmp = command;
        tmp += strspn(tmp, FFSHELL_WS);
        if (!*tmp)
            return FFSHELL_ERR_INVALID_ARGUMENT;
    }
    if (!atomic_compare_exchange_strong(&g_running, &expected, 1))
        return FFSHELL_ERR_ALREADY_RUNNING;
    atomic_store(&g_cancel_requested, 0);

    int argc = 0;
    char **argv = NULL;
    if (ffshell_parse_command(command, &argc, &argv) != 0) {
        atomic_store(&g_running, 0);
        return FFSHELL_ERR_INVALID_ARGUMENT;
    }
    if (argc <= 0 || !argv || !argv[0]) {
        ffshell_free_parsed(argc, argv);
        atomic_store(&g_running, 0);
        return FFSHELL_ERR_INVALID_ARGUMENT;
    }

    ffshell_reset_interrupt_state();
    ffshell_reset_state();
    save_signal_handlers();
    ffshell_ensure_orig_saved();
    av_log_set_level(g_orig_log_level == INT_MIN ? AV_LOG_INFO : g_orig_log_level);
    av_log_set_flags(g_orig_log_flags == INT_MIN ? AV_LOG_SKIP_REPEATED : g_orig_log_flags);
    av_log_set_callback(av_log_default_callback);
    extern int hide_banner;
    hide_banner = g_orig_hide_banner;
    {
        const char *prog = (argv[0][0] == '-') ? "ffprobe" : argv[0];
        int firstarg = (argv[0][0] == '-') ? 0 : 1;
        const int total = 1 + (argc - firstarg) + 1;
        char **full = calloc((size_t)total, sizeof(*full));
        int nargs = 0;
        int ret; ffshell_status status;
        if (!full) {
            ffshell_free_parsed(argc, argv);
            atomic_store(&g_running, 0);
            return FFSHELL_ERR_INTERNAL;
        }
        full[nargs++] = (char *)prog;
        for (int i = firstarg; i < argc && argv[i]; i++)
            full[nargs++] = argv[i];

        ffshell_rewrite_probe_paths(nargs, full);

        int use_term_probe = 0;
        pthread_t term_thr_probe;
        {
            if (ffshell_log_cb_active()) {
                if (setup_raw_terminal_capture(&term_thr_probe)==0) use_term_probe=1;
            }
        }

        {
            struct cli_thread_ctx cctx = { nargs, full, 0, 1 };
            pthread_t cli_thr;
            if (pthread_create(&cli_thr, NULL, cli_thread_main, &cctx) == 0) {
                atomic_store(&g_cli_thread, 1);
                pthread_join(cli_thr, NULL);
                atomic_store(&g_cli_thread, 0);
                ret = cctx.ret;
            } else {
                extern const char *program_name;
                extern const char *program_birth_year;
                program_name = "ffprobe";
                program_birth_year = "2007";
                ret = ffprobe_main(nargs, full);
                free(full);
            }
        }

        if (use_term_probe) teardown_raw_terminal_capture(term_thr_probe);

        restore_signal_handlers();
        ffshell_cleanup_rewritten();
        if (atomic_exchange(&g_cancel_requested, 0))
            status = FFSHELL_ERR_CANCELLED;
        else if (ret == 0)
            status = FFSHELL_OK;
        else
            status = FFSHELL_ERR_INTERNAL;
        ffshell_free_parsed(argc, argv);
        atomic_store(&g_running, 0);
        return status;
    }
}
