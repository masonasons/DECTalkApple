/*
 * dtk_shim — a small, clean C surface over the legacy DECtalk TTS API.
 *
 * The DECtalk public header (ttsapi.h) drags in a large tree of 1990s
 * Windows-multimedia typedefs (WORD/DWORD/LPTTS_HANDLE_T/...). This shim hides
 * all of that behind plain C types so Swift can import a tiny, stable module.
 *
 * Audio is produced by the in-memory synthesis path (no audio device): text in,
 * signed 16-bit mono PCM out, delivered incrementally to a callback.
 */
#ifndef DTK_SHIM_H
#define DTK_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct dtk_engine dtk_engine;

/* Predefined DECtalk speakers (index passed to dtk_set_speaker). */
enum {
    DTK_PAUL = 0, DTK_BETTY = 1, DTK_HARRY = 2, DTK_FRANK = 3, DTK_DENNIS = 4,
    DTK_KIT = 5, DTK_URSULA = 6, DTK_RITA = 7, DTK_WENDY = 8
};

/*
 * Receives a block of signed 16-bit mono PCM samples at dtk_sample_rate().
 * `samples` is valid only for the duration of the call.
 */
typedef void (*dtk_sample_cb)(const int16_t *samples, size_t count, void *ctx);

/*
 * Create an engine. `dic_dir` is the directory containing the pronunciation
 * dictionary (e.g. dtalk_us.dic); pass NULL to search the current directory.
 * Returns NULL on failure.
 */
dtk_engine *dtk_create(const char *dic_dir);
void        dtk_destroy(dtk_engine *e);

/* Native output sample rate in Hz (e.g. 11025). */
int         dtk_sample_rate(const dtk_engine *e);

/* Speaking rate in words per minute (roughly 75..600). */
void        dtk_set_rate(dtk_engine *e, int words_per_minute);

/* Predefined speaker (one of the DTK_* constants). */
void        dtk_set_speaker(dtk_engine *e, int speaker);

/*
 * Synthesize UTF-8 `text`, delivering PCM to `cb` (with `ctx`) and blocking
 * until synthesis is complete. Returns 0 on success. Not reentrant per engine;
 * concurrent calls (across engines) are serialized internally.
 */
int         dtk_speak(dtk_engine *e, const char *text, dtk_sample_cb cb, void *ctx);

/* Convenience: synthesize `text` to a 16-bit mono WAV file at `path`. */
int         dtk_speak_to_wav(dtk_engine *e, const char *path, const char *text);

#ifdef __cplusplus
}
#endif

#endif /* DTK_SHIM_H */
