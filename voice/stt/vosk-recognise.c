/* Small command recogniser around libvosk (Apache-2.0).
 *
 *   vosk-recognise MODEL_DIR [GRAMMAR_JSON_FILE] < audio.raw > result.json
 *
 * Reads raw 16 kHz, 16-bit, mono, little-endian PCM from stdin and prints one
 * line of JSON, {"text": "..."}. With a grammar (a JSON array of phrases, plus
 * "[unk]") only those phrases can be recognised: much faster and more accurate
 * on a small vocabulary than free-form recognition, and exactly what a home
 * command needs. Timings go to stderr.
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include "vosk_api.h"

static double now(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static char *slurp(const char *path) {
  FILE *f = fopen(path, "rb");
  if (!f) return NULL;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  char *buf = malloc((size_t)n + 1);
  if (!buf) { fclose(f); return NULL; }
  size_t got = fread(buf, 1, (size_t)n, f);
  buf[got] = 0;
  fclose(f);
  return buf;
}

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s MODEL_DIR [GRAMMAR_JSON_FILE]\n", argv[0]);
    return 2;
  }
  vosk_set_log_level(-1);
  double t0 = now();
  VoskModel *model = vosk_model_new(argv[1]);
  if (!model) { fprintf(stderr, "cannot load the model\n"); return 3; }
  char *grammar = argc > 2 ? slurp(argv[2]) : NULL;
  if (argc > 2 && !grammar) { fprintf(stderr, "cannot read the grammar\n"); return 4; }
  VoskRecognizer *rec = grammar ? vosk_recognizer_new_grm(model, 16000.0f, grammar)
                                : vosk_recognizer_new(model, 16000.0f);
  if (!rec) { fprintf(stderr, "cannot create the recogniser\n"); return 5; }
  double t1 = now();

  char buf[4000];
  size_t n, total = 0;
  while ((n = fread(buf, 1, sizeof buf, stdin)) > 0) {
    total += n;
    vosk_recognizer_accept_waveform(rec, buf, (int)n);
  }
  const char *result = vosk_recognizer_final_result(rec);
  double t2 = now();
  printf("%s\n", result);
  double audio_s = (double)total / 32000.0;
  fprintf(stderr, "load_s=%.3f decode_s=%.3f audio_s=%.3f rtf=%.3f\n", t1 - t0, t2 - t1,
          audio_s, audio_s > 0 ? (t2 - t1) / audio_s : 0.0);
  vosk_recognizer_free(rec);
  vosk_model_free(model);
  free(grammar);
  return 0;
}
