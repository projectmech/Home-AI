#!/usr/bin/env bash
# Can a 2010 Core 2 Duo run Ollama? (CI.)
#
# Fetches Ollama, then (1) looks at which CPU backends it ships and whether the
# baseline one is free of AVX, (2) runs a tiny model natively and through the
# bench-models.sh script that you will run on the Mac, and (3) runs the server
# and one generation under QEMU user-mode emulating a Core 2 (Penryn: SSE4.1,
# no AVX). A crash with an illegal instruction in step 3 means a real Core 2
# cannot run it. The emulated timing is NOT a speed measurement; real speed
# needs llm/bench-models.sh on the Mac itself.
set -euo pipefail
cd "$(dirname "$0")"
OUT=bench-out
rm -rf "$OUT"
mkdir -p "$OUT"
MODEL="${LLM_TEST_MODEL:-smollm2:135m}"
FALLBACK="${LLM_TEST_FALLBACK:-qwen2.5:0.5b}"

# Report through GitHub annotations (the run page's logs need a sign-in).
note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}
warn() {
  printf '::warning title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

# OLLAMA_DIR points at a tree with bin/ollama and lib/ollama (for example one
# made by build-ollama.sh); without it the official release is downloaded.
if [ -n "${OLLAMA_DIR:-}" ]; then
  OLLAMA_DIR=$(readlink -f "$OLLAMA_DIR")
  echo "using the tree at $OLLAMA_DIR" | tee "$OUT/fetch.txt"
else
  bash fetch.sh | tee "$OUT/fetch.txt"
  note "ollama download" "$(grep -E 'version=|sha256=|matches' "$OUT/fetch.txt")"
  OLLAMA_DIR="$PWD/vendor/ollama"
fi
OL="$OLLAMA_DIR/bin/ollama"
LIBDIR="$OLLAMA_DIR/lib/ollama"

# ---- 1. which CPU backends does it ship, and does the baseline use AVX? -------------
{
  echo "files in lib/ollama:"
  ls -1 "$LIBDIR" 2>/dev/null | head -n 60 || true
  echo
  "$OL" --version 2>&1 | head -n 3 || true
} > "$OUT/layout.txt"
note "ollama layout" "$(head -n 70 "$OUT/layout.txt")"
{
  for f in "$LIBDIR"/libggml-cpu-*.so; do
    [ -f "$f" ] || continue
    v=$(objdump -d --no-show-raw-insn "$f" 2>/dev/null | grep -cE '%(ymm|zmm)[0-9]+' || true)
    echo "$(basename "$f") ymm/zmm uses: $v"
  done
} > "$OUT/variants.txt" || true
note "CPU backend variants and AVX use" "$(cat "$OUT/variants.txt")
(a baseline variant with 0 is what a Core 2 would use)"
objdump -d --no-show-raw-insn "$OL" 2>/dev/null \
  | awk '/^[0-9a-f]+ <.*>:$/ {fn=$2} /^[[:space:]]*[0-9a-f]+:[[:space:]]+v[a-z0-9]+[[:space:]]/ {c[fn]++} END {for (f in c) print c[f], f}' \
  | sort -rn | head -n 10 > "$OUT/ollama-vex.txt" || true
note "AVX in the ollama binary itself" "top functions: $(tr '\n' ';' < "$OUT/ollama-vex.txt") (empty means none)"

# ---- 2. native run, through the same script you will run on the Mac --------------------
export OLLAMA_HOST=127.0.0.1:11436
export OLLAMA_MODELS="$PWD/$OUT/models"
export OLLAMA_NUM_PARALLEL=1 OLLAMA_MAX_LOADED_MODELS=1 OLLAMA_KEEP_ALIVE=1m
export OLLAMA_LLM_LIBRARY=cpu CUDA_VISIBLE_DEVICES=-1 HIP_VISIBLE_DEVICES=-1

wait_ready() { # seconds
  local t=0
  while [ "$t" -lt "$1" ]; do
    curl -fsS --max-time 5 "http://$OLLAMA_HOST/api/version" >/dev/null 2>&1 && return 0
    sleep 3
    t=$((t + 3))
  done
  return 1
}

"$OL" serve > "$OUT/serve-native.log" 2>&1 &
SERVE=$!
trap 'kill "$SERVE" 2>/dev/null || true' EXIT
if ! wait_ready 120; then
  warn "ollama serve (native)" "did not start: $(tail -n 8 "$OUT/serve-native.log")"
  exit 1
fi
OLLAMA_BIN="$OL" TOKENS=16 bash bench-models.sh "$MODEL" | tee "$OUT/bench-native.txt"
if grep -q 'skipped' "$OUT/bench-native.txt"; then
  echo "falling back to $FALLBACK"
  OLLAMA_BIN="$OL" TOKENS=16 bash bench-models.sh "$FALLBACK" | tee -a "$OUT/bench-native.txt"
  MODEL="$FALLBACK"
fi
note "native run through bench-models.sh" "$(cat "$OUT/bench-native.txt")"
grep -iE 'cpu backend|load_backend|system info|library=|inference compute|avx|sse' "$OUT/serve-native.log" | head -n 12 > "$OUT/native-backend.txt" || true
note "which backend the native server loaded" "$(cat "$OUT/native-backend.txt")"
kill "$SERVE" 2>/dev/null || true
wait "$SERVE" 2>/dev/null || true
trap - EXIT

# ---- 2b. which CPU does the ollama binary itself need? ---------------------------------
# The first run died with an illegal instruction under Penryn. Try the same
# binary on a few emulated CPUs to find the lowest one it runs on, and look at
# the last instructions the emulator translated before it stopped.
{
  for cpu in Penryn Nehalem SandyBridge Haswell; do
    r=$(QEMU_CPU=$cpu timeout 120 qemu-x86_64 -cpu "$cpu" "$OL" --version 2>&1 | head -n 3 | tr '\n' ' ') || true
    echo "$cpu: ${r:-no output}"
  done
} > "$OUT/cpu-sweep.txt" 2>&1 || true
note "ollama --version on emulated CPUs (Penryn = Core 2, Nehalem adds SSE4.2/POPCNT, SandyBridge adds AVX)" "$(cat "$OUT/cpu-sweep.txt")"
QEMU_CPU=Penryn timeout 180 qemu-x86_64 -cpu Penryn -d in_asm,nochain -D "$OUT/asm.log" "$OL" --version > /dev/null 2>&1 || true
tail -n 40 "$OUT/asm.log" > "$OUT/asm-tail.txt" 2>/dev/null || true
note "last instructions translated before the emulated Core 2 stopped" "$(cat "$OUT/asm-tail.txt")"
rm -f "$OUT/asm.log"

# ---- 3. the same server under an emulated Core 2 -----------------------------------------
# QEMU_CPU makes the child processes Ollama starts (its runner) emulate it too.
export QEMU_CPU=Penryn
qemu-x86_64 -cpu Penryn "$OL" serve > "$OUT/serve-penryn.log" 2>&1 &
SERVE=$!
trap 'kill "$SERVE" 2>/dev/null || true' EXIT
RESULT=fail
if wait_ready 600; then
  body=$(jq -n --arg m "$MODEL" '{model:$m, prompt:"Say hello.", stream:false, options:{num_predict:6, temperature:0}}')
  if timeout 2400 curl -fsS --max-time 2300 "http://$OLLAMA_HOST/api/generate" -d "$body" > "$OUT/gen-penryn.json" 2> "$OUT/gen-penryn.err"; then
    note "PENRYN (Core 2) RUN: generated text" "response: $(jq -r .response "$OUT/gen-penryn.json" | tr '\n' ' ' | cut -c1-200); tokens: $(jq -r .eval_count "$OUT/gen-penryn.json") (emulated timing is not a speed)"
    RESULT=pass
  else
    warn "PENRYN (Core 2) RUN: generation failed" "$(tail -n 5 "$OUT/gen-penryn.err") | server log: $(tail -n 12 "$OUT/serve-penryn.log")"
  fi
else
  warn "PENRYN (Core 2) RUN: server did not start" "$(tail -n 15 "$OUT/serve-penryn.log")"
fi
# ---- 3b. the ENGINE (llama-server) itself on the emulated Core 2 ----------------------------
# Ollama starts its engine as a separate program. Whether that child really
# ran emulated is not certain (the server log above reported AVX-512, which an
# emulated Core 2 does not have), so run the engine directly under the emulator
# on the model Ollama just downloaded.
kill "$SERVE" 2>/dev/null || true
wait "$SERVE" 2>/dev/null || true
BLOB=$(ls -S "$OLLAMA_MODELS"/blobs/sha256-* 2>/dev/null | head -n 1 || true)
if [ -n "$BLOB" ] && [ -x "$LIBDIR/llama-server" ]; then
  QEMU_CPU=Penryn qemu-x86_64 -cpu Penryn "$LIBDIR/llama-server" -m "$BLOB" --host 127.0.0.1 --port 18090 -c 256 -t 2 > "$OUT/engine-penryn.log" 2>&1 &
  ENGINE=$!
  ready=0
  for _ in $(seq 1 200); do
    curl -fsS --max-time 5 http://127.0.0.1:18090/health > /dev/null 2>&1 && { ready=1; break; }
    kill -0 "$ENGINE" 2>/dev/null || break
    sleep 3
  done
  if [ "$ready" = 1 ]; then
    r=$(timeout 1200 curl -fsS --max-time 1100 http://127.0.0.1:18090/completion -d '{"prompt":"Hello","n_predict":6,"temperature":0}' | jq -r '.content' | tr '
' ' ') || true
    note "ENGINE (llama-server) ON AN EMULATED CORE 2: answered" "text: ${r:-nothing}"
  else
    warn "ENGINE (llama-server) ON AN EMULATED CORE 2: did not start" "$(tail -n 15 "$OUT/engine-penryn.log")"
  fi
  grep -iE 'system_info|load_backend|CPU :|SSE|AVX' "$OUT/engine-penryn.log" | head -n 8 > "$OUT/engine-flags.txt" || true
  note "which CPU features the engine saw on the emulated Core 2" "$(cat "$OUT/engine-flags.txt") (no AVX here means the emulation is real)"
  kill "$ENGINE" 2>/dev/null || true
else
  warn "engine test skipped" "no model blob or no llama-server in $LIBDIR"
fi

grep -iE 'illegal instruction|SIGILL|unsupported|requires|avx|sse4|cpu backend|load_backend|system info' "$OUT/serve-penryn.log" | head -n 12 > "$OUT/penryn-flags.txt" || true
note "what the emulated Core 2 server said about the CPU" "$(cat "$OUT/penryn-flags.txt") (empty: nothing about instruction sets)"
kill "$SERVE" 2>/dev/null || true
trap - EXIT
echo "RESULT: $RESULT"
[ "$RESULT" = pass ]
