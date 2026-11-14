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

# ---- control: does an ordinary program run on an emulated Core 2 HERE? -----------------
# Runs inside debian:trixie (the OS image's base). A system C library built for a
# newer CPU makes EVERY program stop on an emulated Core 2, which would make this
# whole test meaningless; this control tells the two cases apart.
if command -v qemu-x86_64 > /dev/null; then
  if qemu-x86_64 -cpu Penryn /bin/true 2> "$OUT/control.err"; then
    control="/bin/true RUNS on an emulated Core 2 here"
  else
    control="/bin/true FAILS on an emulated Core 2 here: $(tail -n 1 "$OUT/control.err")"
  fi
  note "control: an ordinary program on an emulated Core 2" "$control. $(ldd --version 2> /dev/null | head -n 1)"
fi

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
# Other instructions a Core 2 (Penryn: SSE4.1) lacks: BMI/ABM, AES, PCLMUL, MOVBE, RDRAND ...
SUSPECT='lzcnt|tzcnt|movbe|andn|bextr|blsr|blsi|blsmsk|shlx|shrx|sarx|rorx|mulx|pdep|pext|adcx|adox|rdrand|rdseed|aesenc|aesdec|aeskeygenassist|pclmulqdq|rdtscp|xgetbv|xsave|xrstor|vzeroupper|sha1rnds4|sha256rnds2|prefetchw|cmpxchg16b'
awk -v re="^($SUSPECT)\$" '/^[0-9a-f]+ <.*>:$/ {fn=$2; next} {n = split($0, a, "\t"); if (n >= 2) {split(a[2], m, " "); if (m[1] ~ re) c[m[1] " in " fn]++}} END {for (k in c) print c[k], k}' "$OUT/server.asm" | sort -rn | head -n 15 > "$OUT/suspects.txt" || true
note "other instructions a Core 2 lacks, in the server binary (empty means none)" "$(cat "$OUT/suspects.txt")"
rm -f "$OUT/server.asm"

# ---- which emulated CPU does it run on, and where does it stop on a Core 2? ----------------
sweep() {
  local cpu r
  for cpu in Penryn Nehalem SandyBridge Haswell; do
    if timeout 120 qemu-x86_64 -cpu "$cpu" "$BIN" --version > "$OUT/v-$cpu.txt" 2>&1; then
      r="runs: $(head -n 1 "$OUT/v-$cpu.txt" | cut -c1-80)"
    else
      r="FAILED: $(tail -n 1 "$OUT/v-$cpu.txt" | cut -c1-100)"
    fi
    echo "$cpu: $r"
  done
}
if command -v qemu-x86_64 > /dev/null; then
  note "llama-server --version on emulated CPUs (Penryn=Core 2; Nehalem adds SSE4.2; SandyBridge adds AVX)" "$(sweep)"
  timeout 300 qemu-x86_64 -cpu Penryn -d in_asm,nochain -D "$OUT/asm.log" "$BIN" --version > /dev/null 2>&1 || true
  note "last translated blocks before the Penryn stop" "$(tail -n 40 "$OUT/asm.log" 2> /dev/null | cut -c1-130)"
  rm -f "$OUT/asm.log"
fi

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
# ---- the assistant's real model: hash to pin, a rough speed, and does it answer in JSON? -------
# (Reported as warnings only because GitHub caps notices at ten per step.)
QWEN_URL=https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf
QWEN=vendor/qwen2.5-1.5b-instruct-q4_k_m.gguf
if [ ! -f "$QWEN" ]; then curl -fsSL --retry 3 -o "$QWEN" "$QWEN_URL" || warn "(info) assistant model download failed" "$QWEN_URL"; fi
if [ -f "$QWEN" ]; then
  QSHA=$(sha256sum "$QWEN" | cut -d' ' -f1)
  QSIZE=$(stat -c %s "$QWEN")
  "$BIN" -m "$QWEN" --host 127.0.0.1 --port 18093 -t 2 -c 1024 --no-warmup > "$OUT/serve-qwen.log" 2>&1 &
  QPID=$!
  t=0
  until curl -fsS --max-time 3 http://127.0.0.1:18093/health > /dev/null 2>&1; do
    kill -0 "$QPID" 2> /dev/null || break
    t=$((t + 3))
    [ "$t" -lt 240 ] || break
    sleep 3
  done
  BODY='{"messages":[{"role":"system","content":"You are a home assistant. Reply with ONE JSON object and nothing else: {\"reply\": \"what you say\", \"command\": \"a home command, or null\"}. A command is exactly one of: turn on the <room> light; turn off the <room> light; volume up; lock the front door. Use null when no action is needed. You cannot unlock anything."},{"role":"user","content":"it is cold and dark in the kitchen, switch the light on please"}],"max_tokens":80,"temperature":0.3}'
  if curl -fsS --max-time 300 http://127.0.0.1:18093/v1/chat/completions -d "$BODY" > "$OUT/qwen-reply.json" 2> "$OUT/qwen.err"; then
    TEXT=$(jq -r '.choices[0].message.content' "$OUT/qwen-reply.json" | tr '\n' ' ' | cut -c1-300)
    SPEED=$(jq -r '"read \(.timings.prompt_per_second // 0 | floor) t/s, write \(.timings.predicted_per_second // 0 | floor) t/s"' "$OUT/qwen-reply.json" 2> /dev/null || echo "no timings")
    warn "(info) assistant model Qwen2.5-1.5B Q4_K_M" "sha256 $QSHA size $QSIZE bytes. Native on this runner's modern CPU, 2 threads: $SPEED (a Core 2 will be several times slower). Reply: $TEXT"
  else
    warn "(info) assistant model: generation failed" "$(tail -n 6 "$OUT/qwen.err") | $(tail -n 6 "$OUT/serve-qwen.log")"
  fi
  kill "$QPID" 2> /dev/null || true
fi

[ "$YMM" -eq 0 ] || { echo "AVX registers found in llama-server" >&2; exit 1; }
[ "$EMU" -eq 0 ] || { echo "llama-server did not run on the emulated Core 2" >&2; exit 1; }
echo "RESULT: PASS"
