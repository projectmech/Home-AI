#!/usr/bin/env bash
# Fallback engine check: whisper.cpp built WITHOUT AVX (plain SSE2), tiny English
# model. Free-form recognition, much slower than a grammar recogniser, but it
# builds from source for a Core 2 on purpose. Reports: no AVX in the binary,
# runs on an emulated Core 2 (Penryn), and native single-thread timing.
set -euo pipefail
cd "$(dirname "$0")"
OUT=bench-whisper-out
rm -rf "$OUT"
mkdir -p "$OUT" vendor

note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

TAG=v1.7.4
if [ ! -d vendor/whisper.cpp ]; then
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/whisper.cpp.git vendor/whisper.cpp
fi
COMMIT=$(git -C vendor/whisper.cpp rev-parse HEAD)
cmake -S vendor/whisper.cpp -B vendor/whisper.cpp/build -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=OFF -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF \
  -DGGML_F16C=OFF -DGGML_BMI2=OFF -DGGML_SSE42=OFF -DGGML_OPENMP=OFF \
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_SERVER=OFF > "$OUT/cmake.log" 2>&1
cmake --build vendor/whisper.cpp/build -j4 --target whisper-cli > "$OUT/build.log" 2>&1 || {
  note "whisper.cpp build FAILED" "$(tail -n 15 "$OUT/build.log")"
  exit 1
}
BIN=$(find vendor/whisper.cpp/build -name whisper-cli -type f | head -n 1)
[ -n "$BIN" ] || { note "whisper.cpp" "whisper-cli not found after build"; exit 1; }

# Model, with its hash printed so it can be pinned.
MODEL=vendor/ggml-tiny.en.bin
[ -f "$MODEL" ] || curl -fsSL --retry 3 -o "$MODEL" https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin
note "whisper.cpp inputs (pin these)" "tag $TAG commit $COMMIT
model $(sha256sum "$MODEL" | cut -d' ' -f1) $(stat -c %s "$MODEL") bytes"

# Any AVX in the binary itself (shared libs next to it included)?
AVX=0
for f in $(find vendor/whisper.cpp/build -type f \( -name 'whisper-cli' -o -name '*.so*' \)); do
  c=$(objdump -d --no-show-raw-insn "$f" 2> /dev/null | grep -cE '%(ymm|zmm)[0-9]+' || true)
  AVX=$((AVX + c))
done
note "whisper.cpp AVX scan" "lines using ymm/zmm registers in the built binary and libraries: $AVX (0 is required for a Core 2)"

espeak-ng -v en-us -s 150 -w "$OUT/a.wav" "turn off the kitchen light"
sox "$OUT/a.wav" -r 16000 -c 1 -b 16 "$OUT/a16.wav"
espeak-ng -v en-us -s 150 -w "$OUT/b.wav" "set the thermostat to twenty two degrees"
sox "$OUT/b.wav" -r 16000 -c 1 -b 16 "$OUT/b16.wav"

timed() { # label, then the command
  local label=$1 start end text
  shift
  start=$(date +%s.%N)
  text=$("$@" 2> /dev/null | tr -d '\n' | sed 's/^ *//') || text="FAILED"
  end=$(date +%s.%N)
  printf '%s: "%s" in %.2f s\n' "$label" "$text" "$(echo "$end - $start" | bc -l)"
}

LINES=$(
  timed "native 1 thread, 'turn off the kitchen light' (1.9 s of speech)" "$BIN" -m "$MODEL" -f "$OUT/a16.wav" -t 1 -nt -np
  timed "native 2 threads, 'turn off the kitchen light'" "$BIN" -m "$MODEL" -f "$OUT/a16.wav" -t 2 -nt -np
  timed "native 2 threads, 'set the thermostat to twenty two degrees' (3 s of speech)" "$BIN" -m "$MODEL" -f "$OUT/b16.wav" -t 2 -nt -np
)
note "whisper.cpp tiny.en, native (this runner's modern CPU)" "$LINES"

if command -v qemu-x86_64 > /dev/null; then
  start=$(date +%s)
  if EMU=$(timeout 1500 qemu-x86_64 -cpu Penryn -L / "$BIN" -m "$MODEL" -f "$OUT/a16.wav" -t 1 -nt -np 2> "$OUT/emu.err" | tr -d '\n'); then
    note "whisper.cpp on an emulated Core 2 (Penryn)" "runs; heard: '$EMU' (took $(($(date +%s) - start)) s emulated; timing is NOT representative)"
  else
    note "whisper.cpp on an emulated Core 2 (Penryn) FAILED" "$(tail -n 3 "$OUT/emu.err")"
    exit 1
  fi
fi
[ "$AVX" -eq 0 ] || { echo "AVX found in the whisper.cpp build" >&2; exit 1; }
echo "RESULT: PASS"
