#!/usr/bin/env bash
# Can llama.cpp built FROM SOURCE for a 2010 Core 2 (no AVX, no SSE4.2) run a
# model? Ollama's own server stopped on an emulated Core 2; llama.cpp's server is
# what Ollama wraps, and building it ourselves lets us pick the instruction set.
#
# Builds llama-server with -march=core2, checks the binary for AVX, and runs it on
# QEMU user-mode emulating a Core 2 (Penryn: SSE4.1, no AVX) with a tiny test
# model, then once natively for a rough comparison. The emulated timing is NOT a
# speed measurement. Real speed needs llm/bench-models.sh on the Mac mini.
set -euo pipefail
cd "$(dirname "$0")"
OUT=llamacpp-out
rm -rf "$OUT"
mkdir -p "$OUT" vendor

note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}
warn() {
  printf '::warning title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

# ---- source: a release tag, printed so it can be pinned ---------------------------
TAG="${LLAMACPP_TAG:-}"
if [ -z "$TAG" ]; then
  TAG=$(curl -fsSL --retry 3 https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | jq -r .tag_name)
fi
if [ ! -d vendor/llama.cpp ]; then
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp.git vendor/llama.cpp
fi
COMMIT=$(git -C vendor/llama.cpp rev-parse HEAD)
note "llama.cpp source (pin these)" "tag $TAG commit $COMMIT"

# ---- build for a Core 2 -----------------------------------------------------------------
FLAGS="-march=core2 -mtune=core2 -O2"
cmake -S vendor/llama.cpp -B vendor/llama.cpp/build -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_SERVER=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_LLAMAFILE=OFF \
  -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF \
  -DGGML_BMI2=OFF -DGGML_SSE42=OFF \
  -DCMAKE_C_FLAGS="$FLAGS" -DCMAKE_CXX_FLAGS="$FLAGS" > "$OUT/cmake.log" 2>&1 || {
  warn "llama.cpp configure FAILED" "$(tail -n 15 "$OUT/cmake.log")"
  exit 1
}
cmake --build vendor/llama.cpp/build -j4 --target llama-server > "$OUT/build.log" 2>&1 || {
  warn "llama.cpp build FAILED" "$(tail -n 20 "$OUT/build.log")"
  exit 1
}
BIN=$(find vendor/llama.cpp/build -name llama-server -type f | head -n 1)
[ -n "$BIN" ] || { warn "llama.cpp" "llama-server not found after the build"; exit 1; }
note "llama-server built" "$(ls -l "$BIN" | awk '{print $5, $9}') bytes; flags: $FLAGS"

# ---- instruction check ---------------------------------------------------------------------
objdump -d --no-show-raw-insn "$BIN" > "$OUT/server.asm" 2> /dev/null || true
YMM=$(grep -cE '%(ymm|zmm)[0-9]+' "$OUT/server.asm" || true)
VEX=$(grep -cE '^[[:space:]]*[0-9a-f]+:[[:space:]]+v[a-z0-9]+[[:space:]]' "$OUT/server.asm" || true)
SSE42=$(grep -cE '\b(popcnt|crc32|pcmpestri|pcmpistri|pcmpgtq)\b' "$OUT/server.asm" || true)
note "llama-server instruction scan" "ymm/zmm lines: $YMM; VEX instructions: $VEX; SSE4.2/POPCNT lines: $SSE42 (all three must be 0 for a Core 2)"
awk '/^[0-9a-f]+ <.*>:$/ {fn=$2} /%(ymm|zmm)[0-9]+/ {c[fn]++} END {for (f in c) print c[f], f}' "$OUT/server.asm" | sort -rn | head -n 10 > "$OUT/ymm-functions.txt" || true
note "functions with AVX registers (empty means none)" "$(cat "$OUT/ymm-functions.txt")"
rm -f "$OUT/server.asm"

# ---- a tiny test model --------------------------------------------------------------------------
MODEL=vendor/stories260K.gguf
[ -f "$MODEL" ] || curl -fsSL --retry 3 -o "$MODEL" https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf
note "test model (pin this)" "stories260K.gguf sha256 $(sha256sum "$MODEL" | cut -d' ' -f1) $(stat -c %s "$MODEL") bytes"

generate() { # label, port, command prefix...
  local label=$1 port=$2
  shift 2
  "$@" "$BIN" -m "$MODEL" --host 127.0.0.1 --port "$port" -t 2 -c 256 --no-warmup > "$OUT/serve-$label.log" 2>&1 &
  local pid=$!
  local t=0 ready=0
  while [ "$t" -lt 600 ]; do
    if curl -fsS --max-time 3 "http://127.0.0.1:$port/health" > /dev/null 2>&1; then
      ready=1
      break
    fi
    kill -0 "$pid" 2> /dev/null || break
    sleep 3
    t=$((t + 3))
  done
  if [ "$ready" != 1 ]; then
    warn "llama-server ($label): did not start" "$(tail -n 12 "$OUT/serve-$label.log")"
    kill "$pid" 2> /dev/null || true
    return 1
  fi
  local start end text
  start=$(date +%s.%N)
  if text=$(curl -fsS --max-time 900 "http://127.0.0.1:$port/completion" -d '{"prompt":"Once upon a time","n_predict":24,"temperature":0}' | jq -r .content); then
    end=$(date +%s.%N)
    note "llama-server ($label): generated text" "'$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-160)' in $(echo "$end - $start" | bc -l | cut -c1-6) s (emulated timing is not a speed)"
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
    return 0
  fi
  warn "llama-server ($label): generation failed" "$(tail -n 8 "$OUT/serve-$label.log")"
  kill "$pid" 2> /dev/null || true
  return 1
}

generate native 18091 env
EMU=1
if command -v qemu-x86_64 > /dev/null; then
  if generate penryn 18092 qemu-x86_64 -cpu Penryn; then EMU=0; fi
else
  warn "emulated Core 2" "qemu-x86_64 is not installed"
fi
[ "$YMM" -eq 0 ] || { echo "AVX registers found in llama-server" >&2; exit 1; }
[ "$EMU" -eq 0 ] || { echo "llama-server did not run on the emulated Core 2" >&2; exit 1; }
echo "RESULT: PASS"
