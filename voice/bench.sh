#!/usr/bin/env bash
# Can a 2010 Core 2 Duo understand home commands? Builds the Vosk command
# recogniser, feeds it synthetic speech, and runs it twice: natively, and under
# QEMU user-mode emulating a Core 2 (Penryn: SSE4.1, no AVX). The second run
# proves the code contains no instruction a Core 2 lacks (an illegal
# instruction would kill it). The emulated timing is NOT a speed measurement.
set -euo pipefail
cd "$(dirname "$0")"
OUT=bench-out
rm -rf "$OUT"
mkdir -p "$OUT"

# Report through a GitHub annotation (the run page's logs need a sign-in).
note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

bash fetch.sh | tee "$OUT/fetch.txt"
note "download hashes (pin these in voice/fetch.sh)" "$(grep 'sha256=' "$OUT/fetch.txt")"
LIBDIR=$(dirname "$(find vendor/lib -name libvosk.so | head -n 1)")
echo "libvosk in $LIBDIR"

# ---- instruction check: any AVX in the library? ------------------------------
objdump -d --no-show-raw-insn "$LIBDIR/libvosk.so" > "$OUT/libvosk.asm" 2>/dev/null || true
YMM=$(grep -cE '%(ymm|zmm)[0-9]+' "$OUT/libvosk.asm" || true)
VEX=$(grep -cE '^[[:space:]]*[0-9a-f]+:[[:space:]]+v[a-z0-9]+[[:space:]]' "$OUT/libvosk.asm" || true)
note "libvosk instruction scan" "lines using ymm/zmm registers: $YMM; VEX (AVX-encoded) instructions: $VEX. Non-zero is only a problem if that code runs on a CPU without AVX; the Penryn run below decides."
# Which functions hold the AVX code? OpenBLAS ships per-CPU kernels (names with
# HASWELL, SKYLAKEX, ZEN ...) and picks one at run time: those are harmless.
# AVX anywhere else means the library itself needs an AVX CPU.
awk '/^[0-9a-f]+ <.*>:$/ {fn=$2} /^[[:space:]]*[0-9a-f]+:[[:space:]]+v[a-z0-9]+[[:space:]]/ {c[fn]++} END {for (f in c) print c[f], f}' "$OUT/libvosk.asm" | sort -rn > "$OUT/vex-by-function.txt"
KERNEL_RE='HASWELL|SKYLAKEX|ZEN|SANDYBRIDGE|BULLDOZER|PILEDRIVER|STEAMROLLER|EXCAVATOR|COOPERLAKE|SAPPHIRERAPIDS'
OTHER=$(grep -vE "$KERNEL_RE" "$OUT/vex-by-function.txt" | wc -l || true)
note "AVX outside the per-CPU kernels" "functions with AVX that are NOT named like a per-CPU kernel: $OTHER. Top 12 of all: $(head -n 12 "$OUT/vex-by-function.txt" | tr '\n' ';') Top 12 outside kernels: $(grep -vE "$KERNEL_RE" "$OUT/vex-by-function.txt" | head -n 12 | tr '\n' ';')"
# Other instructions a Core 2 (Penryn: SSE4.1) lacks, outside the per-CPU
# kernels: POPCNT, SSE4.2, BMI/ABM and friends. A library built for a newer
# baseline (x86-64-v2/v3) would crash here even with no AVX in its own code.
SUSPECT='popcnt|crc32|pcmpestri|pcmpistri|pcmpestrm|pcmpistrm|pcmpgtq|lzcnt|tzcnt|movbe|andn|blsr|blsi|blsmsk|bextr|shlx|shrx|sarx|rorx|mulx|pdep|pext|adcx|adox|rdtscp|rdrand|rdseed|cmpxchg16b|prefetchw'
awk -v re="$KERNEL_RE" -v sus="^($SUSPECT)\$" '
  /^[0-9a-f]+ <.*>:$/ { fn = $2; next }
  fn !~ re { n = split($0, a, "\t"); if (n >= 2) { split(a[2], m, " "); if (m[1] ~ sus) { c[m[1]]++; f[m[1] " in " fn]++ } } }
  END { for (k in c) print "TOTAL", c[k], k; for (k in f) print "IN", f[k], k }' "$OUT/libvosk.asm" | sort -k2 -rn > "$OUT/suspects.txt"
note "instructions a Core 2 lacks, outside the OpenBLAS kernels" "$(head -n 25 "$OUT/suspects.txt")
(empty means none found)"

# ---- build the recogniser ----------------------------------------------------
gcc -O2 -Wall -o "$OUT/vosk-recognise" stt/vosk-recognise.c -I"$LIBDIR" -L"$LIBDIR" -lvosk -Wl,-rpath,"$PWD/$LIBDIR"
export LD_LIBRARY_PATH="$PWD/$LIBDIR"

# ---- grammar: what the home can be told --------------------------------------
phrases=()
for room in kitchen ceiling "living room" counter; do
  phrases+=("turn on the $room light" "turn off the $room light" "$room light on" "$room light off")
done
phrases+=("turn on the light" "turn off the light" "turn on the music" "turn off the music"
  "pause the music" "play the music" "resume the music" "volume up" "volume down"
  "lock the front door" "unlock the front door" "what is the temperature in the bedroom"
  "what is the temperature" "set the thermostat to twenty two degrees")
for n in sixteen seventeen eighteen nineteen twenty "twenty one" "twenty two" "twenty three" "twenty four" "twenty five"; do
  phrases+=("set the thermostat to $n degrees")
done
for n in ten twenty thirty forty fifty sixty seventy eighty ninety "one hundred"; do
  phrases+=("set the living room light to $n percent" "set volume to $n percent")
done
{
  printf '['
  for p in "${phrases[@]}"; do printf '"%s", ' "$p"; done
  printf '"[unk]"]\n'
} > "$OUT/grammar.json"
echo "grammar phrases: ${#phrases[@]}"

# ---- synthetic speech (robotic, but fixed and repeatable) ---------------------
SAMPLES=("turn off the kitchen light" "set the thermostat to twenty two degrees" "volume up"
  "pause the music" "lock the front door" "what is the temperature in the bedroom"
  "turn on the living room light" "set volume to fifty percent")
i=0
for s in "${SAMPLES[@]}"; do
  i=$((i + 1))
  espeak-ng -v en-us -s 150 -w "$OUT/s$i.wav" "$s"
  sox "$OUT/s$i.wav" -r 16000 -c 1 -b 16 -e signed-integer -t raw "$OUT/s$i.raw"
done

norm() { printf '%s' "$1" | tr ' ' '\n' | { grep -vxE 'set|to|the' || true; } | tr '\n' ' '; }

RESULT_OK=0
run_all() { # label, then the command prefix (may be just "env")
  local label=$1
  shift
  local ok=0 total=0 lines="" idx=0 s json heard verdict t
  for s in "${SAMPLES[@]}"; do
    idx=$((idx + 1))
    total=$((total + 1))
    t="$OUT/t$idx.txt"
    if ! json=$("$@" "$OUT/vosk-recognise" vendor/model "$OUT/grammar.json" < "$OUT/s$idx.raw" 2> "$t"); then
      note "$label FAILED on sample $idx" "$(cat "$t")"
      return 1
    fi
    heard=$(printf '%s' "$json" | sed -n 's/.*"text" *: *"\([^"]*\)".*/\1/p')
    verdict=WRONG
    # The command parser ignores "set", "to" and "the", and so does this check.
    if [ "$(norm "$heard")" = "$(norm "$s")" ]; then
      verdict=ok
      ok=$((ok + 1))
    fi
    lines="$lines
[$verdict] said '$s' heard '$heard' ($(cat "$t"))"
  done
  note "$label: $ok of $total commands understood" "$lines"
  RESULT_OK=$ok
}

run_all "native (this runner's modern CPU)" env
NATIVE_OK=$RESULT_OK

# ---- the same code on an emulated Core 2 --------------------------------------
EMU_OK=-1
if command -v qemu-x86_64 > /dev/null; then
  # Diagnosis: does forcing OpenBLAS to a Core 2 kernel make it run?
  diag=""
  for core in none PENRYN CORE2; do
    if [ "$core" = none ]; then unset OPENBLAS_CORETYPE; else export OPENBLAS_CORETYPE=$core; fi
    if timeout 600 qemu-x86_64 -cpu Penryn -L / "$OUT/vosk-recognise" vendor/model "$OUT/grammar.json" < "$OUT/s1.raw" > "$OUT/d.out" 2> "$OUT/d.err"; then
      diag="$diag
OPENBLAS_CORETYPE=$core: runs ($(tail -n 1 "$OUT/d.err"))"
    else
      diag="$diag
OPENBLAS_CORETYPE=$core: FAILED ($(tail -n 1 "$OUT/d.err"))"
    fi
  done
  unset OPENBLAS_CORETYPE
  note "emulated Core 2 diagnosis" "$diag"
  # Where does it die? The last translated instructions before the illegal one.
  # Does it already die while loading (no audio), or only while decoding?
  if timeout 600 qemu-x86_64 -cpu Penryn -L / "$OUT/vosk-recognise" vendor/model "$OUT/grammar.json" < /dev/null > /dev/null 2> "$OUT/load.err"; then
    note "emulated Core 2, load only (no audio)" "survives loading the model and grammar"
  else
    note "emulated Core 2, load only (no audio)" "dies during load: $(tail -n 1 "$OUT/load.err")"
  fi
  timeout 900 qemu-x86_64 -cpu Penryn -L / -strace -d in_asm -D "$OUT/asm.log" "$OUT/vosk-recognise" vendor/model "$OUT/grammar.json" < "$OUT/s1.raw" > /dev/null 2> "$OUT/strace.log" || true
  note "last translated instructions before the crash" "$(tail -n 30 "$OUT/asm.log" | cut -c1-110)"
  note "where libvosk was mapped (strace)" "$(grep -A14 -m1 'libvosk.so' "$OUT/strace.log" | cut -c1-160)"
  note "last system calls before the crash" "$(tail -n 8 "$OUT/strace.log" | cut -c1-160)"
  rm -f "$OUT/asm.log" "$OUT/strace.log"
  RESULT_OK=0   # a failed run must not inherit the native result
  run_all "emulated Core 2 (qemu-user Penryn; timing is NOT representative)" qemu-x86_64 -cpu Penryn -L / || true
  EMU_OK=$RESULT_OK
else
  note "emulated Core 2" "qemu-x86_64 is not installed"
fi

du -sh vendor/model "$LIBDIR/libvosk.so" > "$OUT/sizes.txt" || true
note "sizes to ship" "$(cat "$OUT/sizes.txt")"

[ "$NATIVE_OK" -ge 6 ] || { echo "too few commands understood natively" >&2; exit 1; }
[ "$EMU_OK" -ge 6 ] || { echo "too few commands understood on the emulated Core 2" >&2; exit 1; }
echo "RESULT: PASS"
