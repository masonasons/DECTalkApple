/*
 * dtk_say — minimal native harness to validate DECtalkEngine.
 * Renders argv[2] text to a WAV file argv[1] using the in-memory (no audio
 * device) path. Adapted from upstream/ports/emscripten/src/say.c.
 *
 *   dtk_say <out.wav> "<text to speak>"
 */
#include "ttsapi.h"
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    LPTTS_HANDLE_T h = NULL;
    int status;

    if (argc != 3) {
        fprintf(stderr, "usage: %s <out.wav> \"<text>\"\n", argv[0]);
        return 2;
    }

    status = TextToSpeechStartup(&h, WAVE_MAPPER, DO_NOT_USE_AUDIO_DEVICE,
                                 NULL, (long)0);
    if (status != MMSYSERR_NOERROR) {
        fprintf(stderr, "TextToSpeechStartup failed: %d\n", status);
        return 1;
    }

    if (TextToSpeechOpenWaveOutFile(h, argv[1], WAVE_FORMAT_1M16) != MMSYSERR_NOERROR) {
        fprintf(stderr, "OpenWaveOutFile failed\n");
        return 1;
    }

    TextToSpeechSpeak(h, argv[2], TTS_FORCE);
    TextToSpeechSync(h);
    TextToSpeechCloseWaveOutFile(h);
    TextToSpeechShutdown(h);

    fprintf(stderr, "wrote %s\n", argv[1]);
    return 0;
}
