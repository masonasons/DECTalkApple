/*
 * dtk_shim implementation — see dtk_shim.h.
 *
 * Compiled as part of the DECtalkEngine static library (it needs the engine's
 * internal include tree), so the shim symbols ship inside the xcframework.
 */
#include "dtk_shim.h"
#include "ttsapi.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <pthread.h>
#include <unistd.h>
#include <limits.h>

#define DTK_NUM_BUFFERS 4
#define DTK_BUFFER_BYTES 16384   /* ~0.37s of 11025 Hz / 16-bit mono per buffer */

struct dtk_engine {
    LPTTS_HANDLE_T handle;
    TTS_BUFFER_T   buffers[DTK_NUM_BUFFERS];
    int            sample_rate;

    /* Active only for the duration of a dtk_speak() call. */
    dtk_sample_cb  cb;
    void          *ctx;
};

/*
 * The DECtalk callback delivers only a 32-bit user word — too small for a
 * 64-bit engine pointer. Since dtk_speak() is synchronous (TextToSpeechSync
 * blocks until every buffer has been delivered), we route the callback through
 * a process-global "active engine" pointer guarded by a mutex that serializes
 * dtk_speak() across engines.
 */
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static dtk_engine     *g_active = NULL;

static void dtk_dt_callback(long param1, long param2, DWORD user, UINT msg)
{
    (void)param1; (void)user;
    if (msg != TTS_MSG_BUFFER)
        return;

    LPTTS_BUFFER_T buf = (LPTTS_BUFFER_T)(intptr_t)param2;
    dtk_engine *e = g_active;
    if (!e || !buf)
        return;

    if (e->cb && buf->dwBufferLength > 0)
        e->cb((const int16_t *)buf->lpData, (size_t)(buf->dwBufferLength / 2), e->ctx);

    /* Recycle the buffer so synthesis can keep filling. */
    buf->dwBufferLength = 0;
    TextToSpeechAddBuffer(e->handle, buf);
}

dtk_engine *dtk_create(const char *dic_dir)
{
    dtk_engine *e = (dtk_engine *)calloc(1, sizeof(*e));
    if (!e)
        return NULL;
    e->sample_rate = 11025;

    /*
     * The engine locates its dictionary relative to the current directory, so
     * briefly switch there while it starts up (startup loads the dictionary).
     */
    char saved_cwd[PATH_MAX];
    int  cwd_changed = 0;
    if (dic_dir && dic_dir[0]) {
        if (getcwd(saved_cwd, sizeof(saved_cwd)) != NULL && chdir(dic_dir) == 0)
            cwd_changed = 1;
    }

    MMRESULT status = TextToSpeechStartup(&e->handle, WAVE_MAPPER,
                                          DO_NOT_USE_AUDIO_DEVICE,
                                          dtk_dt_callback, (long)0);

    if (cwd_changed)
        (void)chdir(saved_cwd);

    if (status != MMSYSERR_NOERROR || e->handle == NULL) {
        free(e);
        return NULL;
    }

    for (int i = 0; i < DTK_NUM_BUFFERS; i++) {
        e->buffers[i].lpData = (LPSTR)malloc(DTK_BUFFER_BYTES);
        e->buffers[i].dwMaximumBufferLength = DTK_BUFFER_BYTES;
        e->buffers[i].lpPhonemeArray = NULL;
        e->buffers[i].dwMaximumNumberOfPhonemeChanges = 0;
        e->buffers[i].lpIndexArray = NULL;
        e->buffers[i].dwMaximumNumberOfIndexMarks = 0;
    }
    return e;
}

void dtk_destroy(dtk_engine *e)
{
    if (!e)
        return;
    if (e->handle)
        TextToSpeechShutdown(e->handle);
    for (int i = 0; i < DTK_NUM_BUFFERS; i++)
        free(e->buffers[i].lpData);
    free(e);
}

int dtk_sample_rate(const dtk_engine *e)
{
    return e ? e->sample_rate : 0;
}

void dtk_set_rate(dtk_engine *e, int words_per_minute)
{
    if (e && e->handle)
        TextToSpeechSetRate(e->handle, (DWORD)words_per_minute);
}

void dtk_set_speaker(dtk_engine *e, int speaker)
{
    if (e && e->handle)
        TextToSpeechSetSpeaker(e->handle, (SPEAKER_T)speaker);
}

int dtk_speak(dtk_engine *e, const char *text, dtk_sample_cb cb, void *ctx)
{
    if (!e || !e->handle || !text)
        return -1;

    pthread_mutex_lock(&g_lock);
    g_active = e;
    e->cb = cb;
    e->ctx = ctx;

    int rc = 0;
    if (TextToSpeechOpenInMemory(e->handle, WAVE_FORMAT_1M16) != MMSYSERR_NOERROR) {
        rc = -2;
        goto out;
    }
    for (int i = 0; i < DTK_NUM_BUFFERS; i++) {
        e->buffers[i].dwBufferLength = 0;
        TextToSpeechAddBuffer(e->handle, &e->buffers[i]);
    }

    TextToSpeechSpeak(e->handle, (LPSTR)text, TTS_FORCE);
    TextToSpeechSync(e->handle);

    /* Drain any buffer still holding samples that never triggered a callback. */
    for (int i = 0; i < DTK_NUM_BUFFERS; i++) {
        LPTTS_BUFFER_T last = NULL;
        if (TextToSpeechReturnBuffer(e->handle, &last) != MMSYSERR_NOERROR)
            break;
        if (!last)
            break;
        if (cb && last->dwBufferLength > 0)
            cb((const int16_t *)last->lpData, (size_t)(last->dwBufferLength / 2), ctx);
    }

    TextToSpeechCloseInMemory(e->handle);

out:
    e->cb = NULL;
    e->ctx = NULL;
    g_active = NULL;
    pthread_mutex_unlock(&g_lock);
    return rc;
}

int dtk_speak_to_wav(dtk_engine *e, const char *path, const char *text)
{
    if (!e || !e->handle || !path || !text)
        return -1;
    if (TextToSpeechOpenWaveOutFile(e->handle, (char *)path, WAVE_FORMAT_1M16) != MMSYSERR_NOERROR)
        return -2;
    TextToSpeechSpeak(e->handle, (LPSTR)text, TTS_FORCE);
    TextToSpeechSync(e->handle);
    TextToSpeechCloseWaveOutFile(e->handle);
    return 0;
}
