/*
 * FFShell - stable C API for running the FFmpeg CLI frontend in-process.
 *
 * This header is the only interface the FFShell Android/JNI layer depends on.
 * It intentionally exposes NO FFmpeg internal structures (no AVFormatContext,
 * no AVCodecContext, ...). FFmpeg may be upgraded without changing this API.
 *
 * Threading model:
 *   - All functions are thread-safe unless noted otherwise.
 *   - Only ONE ffshell_ffmpeg_run() may be active at a time; a second
 *     concurrent call returns FFSHELL_ERR_ALREADY_RUNNING.
 *
 * File descriptor ownership:
 *   - You may pass Android fds as input/output paths, e.g. "/proc/self/fd/3".
 *   - The caller keeps ownership of such descriptors: FFShell never closes
 *     them. Keep them open for the duration of ffshell_ffmpeg_run() and
 *     close them yourself afterwards.
 *
 * Callback lifetime:
 *   - Callbacks stay registered until replaced or until the library is
 *     unloaded. They may fire from arbitrary FFmpeg worker threads, so they
 *     must be reentrant/thread-safe and must not call back into
 *     ffshell_ffmpeg_run().
 */
#ifndef FFSHELL_FFMPEG_H
#define FFSHELL_FFMPEG_H



#ifdef __cplusplus
#include <cstdint>
#include <cstddef>
extern "C" {
#else
#include <stdint.h>
#include <stddef.h>
#endif

/* Status codes returned by ffshell_ffmpeg_run()/ffprobe_run(). */
typedef enum {
    FFSHELL_OK = 0,               /* command completed successfully        */
    FFSHELL_ERR_INVALID_ARGUMENT, /* bad command (NULL/empty/parse fail)   */
    FFSHELL_ERR_ALREADY_RUNNING,  /* another run is still active           */
    FFSHELL_ERR_CANCELLED,        /* cancelled via ffshell_ffmpeg_cancel() */
    FFSHELL_ERR_INTERNAL          /* ffmpeg exited with a non-zero code    */
} ffshell_status;

/* Raw terminal callback — delivers byte-identical stdout+stderr bytes
 * as they would appear on a real TTY (including \r, \n, ANSI CSI/SGR,
 * UTF-8). Level is informational (currently always AV_LOG_INFO) — the
 * 1:1 guarantee is on bytes, not levels. `data` is NOT NUL-terminated;
 * `len` is its exact length. May be called from an internal reader
 * thread; must be reentrant/thread-safe and must not call back into run().
 * Progress is now delivered via the standard ffmpeg stats lines in this
 * log callback (byte-identical to official ffmpeg); use -stats/-nostats
 * in the command string to control it, just like on a Linux TTY/Windows
 * cmd. */
typedef void (*ffshell_log_callback)(int level, const char *data, size_t len,void *user_data);

/* ------------------------------------------------------------------ */
/* Input-path replacement hook                                         */
/* ------------------------------------------------------------------ */

/*
 * Called once per identified file during command rewriting (before the
 * CLI starts). Uses FFmpeg's own tokenizer (split_commandline) for ffmpeg
 * and a robust linear scan for ffprobe, so "-i", positional inputs and
 * duplicate paths are handled correctly. is_output==0 for inputs,
 * is_output==1 for outputs (-o / GROUP_OUTFILE). Callback may return
 * NULL to keep the original argv entry, or a malloc'd replacement URL
 * (e.g. "/proc/self/fd/3") which the library will free after the run.
 *
 * Reliability:
 *   - Each distinct argv slot is offered at most once (replaced[] tracking),
 *     duplicates like "-i a -i a" get separate URLs.
 *   - Thread-safe: may be called from the thread that invoked run(),
 *     never concurrently.
 *
 * Lifetime / threading:
 *   - Must be registered BEFORE ffshell_ffmpeg_run()/ffshell_ffprobe_run().
 *   - Fires on the thread calling run(), before any decoding starts; must
 *     not call back into run().
 *   - The library owns every string returned and frees them after the run
 *     completes or is cancelled.
 */
typedef char * (*ffshell_path_callback)(
        int is_output,
        const char *raw_path,
        void *user_data);

/*
 * Register the input-path replacement callback. Pass NULL to disable.
 * When no callback is registered the rewrite step is skipped entirely
 * (zero overhead, byte-identical argv passthrough).
 */
void ffshell_set_path_callback(
        ffshell_path_callback callback,
        void *user_data);

/*
 * Run the embedded FFmpeg CLI frontend with the given command string.
 *
 * The full command is parsed with shell-like tokenization — single-quote,
 * double-quote and backslash escaping are honoured, whitespace outside
 * quotes delimits arguments. POSIX `<backslash><newline>` line-continuation
 * (and `<backslash><CRLF>`) is removed before tokenization, so multiline
 * commands pasted from a shell work as on Linux/macOS:
 *
 *   ffshell_ffmpeg_run("ffmpeg -i in.mp4 \\\n"
 *                      "  -c copy \\\n"
 *                      "  out.mkv");
 *
 * argv[0] handling is preserved: if the first
 * token does not start with '-', it is treated as the program name
 * ("ffmpeg"/"ffprobe"), otherwise the program name is assumed. Example:
 *
 *   ffshell_ffmpeg_run("ffmpeg -nostdin -i /proc/self/fd/3 -c:v libdav1d -crf 23 -y /proc/self/fd/4");
 *   ffshell_ffmpeg_run("-i input.mp4 -c:v libx264 output.mp4");
 *   ffshell_ffmpeg_run("ffmpeg -i 'my file.mp4' -c:v libx264 \"out file.mp4\"");
 *
 * "-nostdin" is always forced internally (no TTY/stdin usage). Blocks the
 * calling thread until completion/cancellation. Returns an ffshell_status.
 * Returns FFSHELL_ERR_INVALID_ARGUMENT if command is NULL/empty or fails
 * to tokenize.
 */
ffshell_status ffshell_ffmpeg_run(const char *command);


/* Function-pointer typedefs for dlopen()/dlsym() consumers - declare the
 * symbol type once here so wrappers never redefine them:
 *
 *   static ffshell_ffmpeg_run_fn p_run;
 *   p_run = (ffshell_ffmpeg_run_fn) dlsym(handle, "ffshell_ffmpeg_run");
 */
typedef ffshell_status (*ffshell_ffmpeg_run_fn)(const char *command);
typedef void           (*ffshell_cancel_fn)();
typedef const char     *(*ffshell_get_version_fn)();
typedef void           (*ffshell_set_log_callback_fn)(ffshell_log_callback callback, void *user_data);
typedef void           (*ffshell_set_path_callback_fn)(ffshell_path_callback callback, void *user_data);

/*
 * Request cooperative cancellation of the active run. Thread-safe; may be
 * called from any thread while ffshell_ffmpeg_run() is executing. The active
 * run finishes gracefully (trailer written where possible) and returns
 * FFSHELL_ERR_CANCELLED. Calling it while no run is active is a harmless
 * no-op (the flag is cleared by the next run).
 */
void ffshell_cancel(void);

/*
 * Return the version string of the actually compiled FFmpeg (same string as
 * `ffmpeg -version`, e.g. "N-116242-g40000d0f20"). The pointer remains valid
 * for the lifetime of the library. Never NULL after a successful load.
 */
const char *ffshell_get_version(void);

/*
 * Register a callback receiving raw terminal bytes (merged stdout+stderr).
 * `data/len` is a raw chunk as written to fd 1/2 (preserves \r, ANSI).
 * Feed directly to TerminalParser: parser.write(data,len,level).
 * Pass NULL to remove the current callback.
 *
 * Byte identity: the stream is identical to `ffmpeg 2>&1` on a Linux TTY /
 * Windows cmd when the same command string is used. User controls verbosity
 * exactly like the official CLI: embed `-loglevel`, `-hide_banner`, `-report`,
 * `-stats`/`-nostats`/`-stats_period` in the command string (e.g.
 * `"-hide_banner -loglevel warning -i in.mp4 out.mp4"`). Progress (periodic
 * `frame=… fps=… speed=…`) is delivered via the standard stats lines in
 * this callback — just like the official binary — and can be parsed from
 * the log or handled via TerminalParser. No separate progress callback.
 */
void ffshell_set_log_callback(
        ffshell_log_callback callback,
        void *user_data);

/* ------------------------------------------------------------------ */
/* ffprobe mirror API - same semantics, same thread-safety, same      */
/* FFSHELL_* status codes. Shares g_running lock with ffmpeg: only   */
/* ONE of ffshell_ffmpeg_run / ffshell_ffprobe_run may be active at  */
/* a time (returns FFSHELL_ERR_ALREADY_RUNNING otherwise).           */
/* Takes a full command string, parsed with the same shell-like       */
/* tokenization as ffshell_ffmpeg_run.                               */
/* ------------------------------------------------------------------ */

ffshell_status ffshell_ffprobe_run(const char *command);

typedef ffshell_status (*ffshell_ffprobe_run_fn)(const char *command);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* FFSHELL_FFMPEG_H */
