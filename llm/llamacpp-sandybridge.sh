#!/usr/bin/env bash
# The model server exactly as the OS image builds it: llama.cpp at the pinned commit,
# built for Sandy Bridge (the owner's Core i5-2415M: AVX yes, AVX2/FMA/F16C no).
# Runs inside debian:trixie. Checks that the binary has no instruction Sandy Bridge
# lacks, runs it on an emulated Sandy Bridge CPU, and measures the real model
# (Qwen2.5 1.5B) natively for a rough speed. Keep the flags in step with os/in-container.sh.
set -euo pipefail
cd "$(dirname "$0")"
OUT=sandybridge-out
rm -rf "$OUT"
mkdir -p "$OUT" vendor

note() { printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"; }
warn() { printf '::warning title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"; }

COMMIT=b1b770d90d94cad9e9ea5b993bdbc383a522fb28
SRC=vendor/llama-sb
if [ ! -d "$SRC/.git" ]; then
  mkdir -p "$SRC"
  git -C "$SRC" init -q .
  git -C "$SRC" remote add origin https://github.com/ggml-org/llama.cpp.git
  git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
  git -C "$SRC" checkout -q FETCH_HEAD
fi
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
  -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_LLAMAFILE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF \
  -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF -DGGML_SSE42=ON \
  -DCMAKE_C_FLAGS="-march=sandybridge -mtune=sandybridge -O2" -DCMAKE_CXX_FLAGS="-march=sandybridge -mtune=sandybridge -O2" > "$OUT/cmake.log" 2>&1 || { warn "configure FAILED" "$(tail -n 15 "$OUT/cmake.log")"; exit 1; }
cmake --build "$SRC/build" -j"$(nproc)" --target llama-server > "$OUT/build.log" 2>&1 || { warn "build FAILED" "$(tail -n 20 "$OUT/build.log")"; exit 1; }
BIN="$SRC/build/bin/llama-server"

objdump -d --no-show-raw-insn "$BIN" > "$OUT/asm.txt" 2> /dev/null || true
BAD=$(grep -cE '%zmm[0-9]+|[[:space:]](vfmadd|vfnmadd|vfmsub|vfnmsub|vcvtph2ps|vcvtps2ph|vpbroadcast|vperm2i128|vpermd|vpermq|vpgather|vgather)[a-z0-9]*[[:space:]]' "$OUT/asm.txt" || true)
YMM=$(grep -cE '%ymm[0-9]+' "$OUT/asm.txt" || true)
note "Sandy Bridge build: instruction scan" "AVX (ymm) lines: $YMM (expected, Sandy Bridge has AVX); instructions Sandy Bridge lacks (AVX2/FMA/F16C/AVX-512): $BAD (must be 0)"
rm -f "$OUT/asm.txt"

# On an emulated Sandy Bridge, with the tiny test model.
MODEL=vendor/stories260K.gguf
[ -f "$MODEL" ] || curl -fsSL --retry 3 -o "$MODEL" https://huggingface.co/ggml-org/models/resolve/main/tinyllamas/stories260K.gguf
serve_and_ask() { # label port path-to-model prompt-json  command-prefix...
  local label=$1 port=$2 model=$3 body=$4
  shift 4
  "$@" "$BIN" -m "$model" --host 127.0.0.1 --port "$port" -t 2 -c 1024 --no-warmup > "$OUT/serve-$label.log" 2>&1 &
  local pid=$! t=0
  until curl -fsS --max-time 3 "http://127.0.0.1:$port/health" > /dev/null 2>&1; do
    kill -0 "$pid" 2> /dev/null || { warn "$label: server stopped" "$(tail -n 8 "$OUT/serve-$label.log")"; return 1; }
    t=$((t + 3))
    [ "$t" -lt 600 ] || { warn "$label: server did not start in time" ""; kill "$pid" 2> /dev/null; return 1; }
    sleep 3
  done
  curl -fsS --max-time 900 "http://127.0.0.1:$port/completion" -d "$body" > "$OUT/reply-$label.json" || { warn "$label: request failed" "$(tail -n 6 "$OUT/serve-$label.log")"; kill "$pid" 2> /dev/null; return 1; }
  kill "$pid" 2> /dev/null || true
  wait "$pid" 2> /dev/null || true
  return 0
}
EMU=1
if command -v qemu-x86_64 > /dev/null && serve_and_ask sandybridge 18101 "$MODEL" '{"prompt":"Once upon a time","n_predict":16,"temperature":0}' qemu-x86_64 -cpu SandyBridge; then
  EMU=0
  note "Sandy Bridge build on an emulated Sandy Bridge" "generated: '$(jq -r .content "$OUT/reply-sandybridge.json" | tr '\n' ' ' | cut -c1-100)'"
fi

# The real model, natively on this runner: a rough speed for the AVX build.
QWEN=vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf
[ -f "$QWEN" ] || curl -fsSL --retry 3 -o "$QWEN" https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf || true
if [ -f "$QWEN" ]; then
  SHA=$(sha256sum "$QWEN" | cut -d' ' -f1)
  if serve_and_ask qwen 18102 "$QWEN" '{"prompt":"<|im_start|>user\nSay hello in five words.<|im_end|>\n<|im_start|>assistant\n","n_predict":24,"temperature":0}' env; then
    SPEED=$(jq -r '"read \(.timings.prompt_per_second // 0 | floor) t/s, write \(.timings.predicted_per_second // 0 | floor) t/s"' "$OUT/reply-qwen.json" 2> /dev/null || echo "no timings")
    warn "(info) Qwen2.5 1.5B with the Sandy Bridge AVX build" "sha256 $SHA; native on this runner, 2 threads: $SPEED (the no-AVX build measured read 5, write 4). Reply: $(jq -r .content "$OUT/reply-qwen.json" | tr '\n' ' ' | cut -c1-100)"
  fi
fi

[ "$BAD" = 0 ] || { echo "instructions Sandy Bridge lacks were found" >&2; exit 1; }
[ "$EMU" = 0 ] || { echo "the build did not run on an emulated Sandy Bridge" >&2; exit 1; }
echo "RESULT: PASS"
