#!/usr/bin/env bash
# Build Ollama from source for an OLD x86-64 CPU (a 2010 Core 2 Duo: SSE4.1,
# no AVX, no POPCNT).
#
# Why: the official v0.40.16 binary needs x86-64-v3 (a Haswell-class CPU, 2013
# or newer). In CI it dies with an illegal instruction on an emulated Core 2 and
# the dynamic linker says "CPU does not support x86-64-v3" on a Sandy Bridge.
# Ollama is MIT-licensed, so we build it ourselves: Go code with GOAMD64=v1 and
# the native engine (ggml) with only the baseline CPU backend.
#
#   llm/build-ollama.sh <path to an Ollama source checkout> [output dir]
#
# Output (same layout as the official tarball): <out>/bin/ollama and
# <out>/lib/ollama/*.so (+ llama-server if the build makes one).
set -euo pipefail
SRC=$(readlink -f "${1:?usage: build-ollama.sh <ollama source dir> [out dir]}")
OUT=$(readlink -m "${2:-$(dirname "$0")/dist}")
LOG="$(dirname "$0")/build-out"
mkdir -p "$LOG" "$OUT/bin" "$OUT/lib/ollama"
LOG=$(readlink -f "$LOG")

note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}
warn() {
  printf '::warning title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

cd "$SRC"
echo "source: $(git rev-parse --short HEAD 2>/dev/null || echo unknown); go: $(go version)"
{
  echo "presets:"; cmake --list-presets 2>&1 | head -n 20 || true
  echo "go.mod: $(grep -E '^(go|toolchain) ' go.mod | tr '\n' ' ')"
  echo "cmake options mentioning CPU/AVX/VARIANT:"
  grep -rniE 'ALL_VARIANTS|GGML_NATIVE|GGML_AVX|GGML_SSE|GGML_CPU' CMakeLists.txt CMakePresets.json 2>/dev/null | head -n 20 || true
} > "$LOG/source-info.txt"
note "ollama source layout" "$(cat "$LOG/source-info.txt")"

# ---- native engine: baseline CPU backend only -----------------------------------------
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=OFF -DGGML_CPU_ALL_VARIANTS=OFF -DGGML_BACKEND_DL=ON \
  -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF \
  -DGGML_BMI2=OFF -DGGML_SSE42=OFF \
  > "$LOG/cmake-configure.log" 2>&1 || { warn "cmake configure failed" "$(tail -n 25 "$LOG/cmake-configure.log")"; exit 1; }
if ! cmake --build build -j"$(nproc)" > "$LOG/cmake-build.log" 2>&1; then
  warn "cmake build failed" "$(tail -n 30 "$LOG/cmake-build.log")"
  exit 1
fi
note "native engine built" "$(find build -name '*.so*' -o -name 'llama-server' | sort | head -n 30)"

# ---- Go server for a baseline x86-64 CPU ------------------------------------------------
export GOAMD64=v1 CGO_ENABLED=1
export CGO_CFLAGS="-O2" CGO_CXXFLAGS="-O2"
if ! go build -trimpath -o "$OUT/bin/ollama" . > "$LOG/go-build.log" 2>&1; then
  warn "go build failed" "$(tail -n 30 "$LOG/go-build.log")"
  exit 1
fi

# ---- assemble the layout the program expects ---------------------------------------------
if [ -d build/lib/ollama ]; then
  cp -a build/lib/ollama/. "$OUT/lib/ollama/"
else
  find build -name '*.so*' -exec cp -a {} "$OUT/lib/ollama/" \;
  [ ! -x build/bin/llama-server ] || cp -a build/bin/llama-server "$OUT/lib/ollama/"
fi
ls -la "$OUT/bin" "$OUT/lib/ollama" > "$LOG/dist.txt"

# ---- what CPU level does each file ask for? -------------------------------------------------
{
  for f in "$OUT/bin/ollama" "$OUT"/lib/ollama/*.so* "$OUT"/lib/ollama/llama-server; do
    [ -f "$f" ] || continue
    isa=$(readelf -n "$f" 2>/dev/null | grep -i 'x86 ISA needed' | head -n 1 | sed 's/^ *//' || true)
    echo "$(basename "$f"): ${isa:-no ISA note}"
  done
} > "$LOG/isa.txt"
note "CPU level each built file asks for (baseline is fine; x86-64-v2/v3 is not)" "$(cat "$LOG/isa.txt")"
note "built layout" "$(cat "$LOG/dist.txt")"

# ---- where does the v3 requirement come from? --------------------------------------------------
# Run 4 showed the built binary still asks for x86-64-v3 and dies on a Core 2.
{
  echo "ISA/AVX compile flags found in the build files (count flag):"
  find build -name 'build.ninja' -print0 | xargs -0 grep -ohE -- '-march=[a-z0-9_.-]+|-m(avx[a-z0-9]*|fma|f16c|bmi2?|sse4[.0-9]*|popcnt|lzcnt|movbe|xsave)' 2>/dev/null | sort | uniq -c | sort -rn | head -n 12
  echo "static libraries and objects whose notes say v3:"
  for f in $(find build -name '*.a' -o -name '*.o' | head -n 400); do
    if readelf -n "$f" 2>/dev/null | grep -qE 'x86 ISA (needed|used).*x86-64-v3'; then echo "  $f"; fi
  done | head -n 12
  echo "Go functions with AVX (VEX) instructions, most first:"
  timeout 400 go tool objdump "$OUT/bin/ollama" 2>/dev/null | awk '/^TEXT /{fn=$2} $3 ~ /^V[A-Z0-9]+$/ || $4 ~ /^V[A-Z0-9]+$/ {c[fn]++} END {for (f in c) print c[f], f}' | sort -rn | head -n 15
} > "$LOG/v3-origin.txt" 2>&1 || true
note "where the x86-64-v3 requirement comes from" "$(cat "$LOG/v3-origin.txt")"

# ---- does it start on an emulated Core 2? -----------------------------------------------------
r=$(QEMU_CPU=Penryn timeout 180 qemu-x86_64 -cpu Penryn "$OUT/bin/ollama" --version 2>&1 | head -n 3 | tr '\n' ' ') || true
note "built ollama --version on an emulated Core 2 (Penryn)" "${r:-no output}"
echo "built: $OUT"
