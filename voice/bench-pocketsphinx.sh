#!/usr/bin/env bash
# PocketSphinx (CMU, BSD-style licence) with a fixed grammar of home commands.
# Runs INSIDE a debian:trixie container (the same base as the JARVIS OS image),
# so the package is exactly what the image will carry. Reports: no AVX in the
# binaries, runs on an emulated Core 2 (Penryn), accuracy on synthetic speech,
# native timing.  Usage (CI): docker run --rm -v "$PWD:/w" debian:trixie bash /w/voice/bench-pocketsphinx.sh
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
OUT=/tmp/ps
mkdir -p "$OUT"

note() {
  printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}

apt-get update -qq > /dev/null
apt-get install -y -qq --no-install-recommends pocketsphinx pocketsphinx-en-us espeak-ng sox libsox-fmt-all qemu-user binutils bc ca-certificates > "$OUT/apt.log" 2>&1 || {
  note "apt install FAILED" "$(tail -n 8 "$OUT/apt.log")"
  exit 1
}
PS=$(command -v pocketsphinx || command -v pocketsphinx_continuous || true)
if [ -z "$PS" ]; then
  note "pocketsphinx binary not found after install" "$(dpkg -l | grep -i -E 'sphinx' | awk '{print $2, $3}'; dpkg -L pocketsphinx 2> /dev/null | grep -E 'bin/' | head -n 20; apt-cache policy pocketsphinx | head -n 4)"
  exit 1
fi
echo "using $PS"
VERSION=$(dpkg-query -W -f='${Package} ${Version}\n' pocketsphinx pocketsphinx-en-us libpocketsphinx3 2> /dev/null | tr '\n' ';' || true)
MODELDIR=$(dirname "$(find /usr/share -name 'cmudict-en-us.dict' 2> /dev/null | head -n 1)")
note "pocketsphinx packages (Debian trixie)" "$VERSION model dir: $MODELDIR; sizes: $(du -sh /usr/share/pocketsphinx 2> /dev/null | cut -f1) model, $(du -shL "$PS" | cut -f1) binary"

# ---- any AVX in the binary or the libraries it loads? -------------------------
AVX=0
for f in "$PS" $(ldd "$PS" | grep -E 'sphinx' | awk '{print $3}'); do
  [ -f "$f" ] || continue
  c=$(objdump -d --no-show-raw-insn "$f" 2> /dev/null | grep -cE '%(ymm|zmm)[0-9]+' || true)
  AVX=$((AVX + c))
done
note "AVX scan of pocketsphinx" "lines using ymm/zmm registers in the binary and its sphinx libraries: $AVX (0 expected: Debian builds amd64 for the baseline CPU)"

# ---- grammar (JSGF): exactly the phrases the home understands ----------------
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
  printf '#JSGF V1.0;\ngrammar home;\npublic <command> = '
  first=1
  for p in "${phrases[@]}"; do
    if [ "$first" = 1 ]; then first=0; else printf ' | '; fi
    printf '%s' "$p"
  done
  printf ';\n'
} > "$OUT/home.gram"

# ---- synthetic speech ----------------------------------------------------------
SAMPLES=("turn off the kitchen light" "set the thermostat to twenty two degrees" "volume up"
  "pause the music" "lock the front door" "what is the temperature in the bedroom"
  "turn on the living room light" "set volume to fifty percent")
i=0
for s in "${SAMPLES[@]}"; do
  i=$((i + 1))
  espeak-ng -v en-us -s 150 -w "$OUT/s$i.wav" "$s"
  sox "$OUT/s$i.wav" -r 16000 -c 1 -b 16 "$OUT/a$i.wav"
done

# Find a working command line (the CLI changed between versions).
CMD=""
for form in "-loglevel ERROR -jsgf $OUT/home.gram single" "-loglevel ERROR -jsgf $OUT/home.gram -infile" "-jsgf $OUT/home.gram -logfn /dev/null -infile"; do
  # shellcheck disable=SC2086
  if out=$($PS $form "$OUT/a1.wav" 2> "$OUT/probe.err") && [ -n "$out" ]; then
    CMD="$form"
    break
  fi
done
if [ -z "$CMD" ]; then
  note "pocketsphinx command line not working" "$(tail -n 5 "$OUT/probe.err"; $PS --help 2>&1 | head -n 25)"
  exit 1
fi

norm() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr ' ' '\n' | { grep -vxE 'set|to|the|' || true; } | tr '\n' ' '; }

run_all() { # label, then a command prefix (env or qemu ...)
  local label=$1
  shift
  local ok=0 total=0 lines="" idx=0 s heard verdict start end secs
  for s in "${SAMPLES[@]}"; do
    idx=$((idx + 1))
    total=$((total + 1))
    start=$(date +%s.%N)
    # shellcheck disable=SC2086
    heard=$("$@" $PS $CMD "$OUT/a$idx.wav" 2> "$OUT/err$idx.txt" | tr -d '\n') || heard="FAILED: $(tail -n 1 "$OUT/err$idx.txt")"
    end=$(date +%s.%N)
    secs=$(echo "$end - $start" | bc -l)
    verdict=WRONG
    if [ "$(norm "$heard")" = "$(norm "$s")" ]; then
      verdict=ok
      ok=$((ok + 1))
    fi
    lines="$lines
[$verdict] said '$s' heard '$heard' ($(printf '%.2f' "$secs") s including start-up)"
  done
  note "$label: $ok of $total commands understood" "$lines"
  RESULT_OK=$ok
}

RESULT_OK=0
run_all "native (this runner's modern CPU)" env
NATIVE_OK=$RESULT_OK

RESULT_OK=0
EMU_OK=-1
if command -v qemu-x86_64 > /dev/null; then
  run_all "emulated Core 2 (qemu-user Penryn; timing is NOT representative)" qemu-x86_64 -cpu Penryn -L / || true
  EMU_OK=$RESULT_OK
fi

[ "$AVX" -eq 0 ] || { echo "AVX found in pocketsphinx" >&2; exit 1; }
[ "$NATIVE_OK" -ge 6 ] || { echo "too few commands understood natively" >&2; exit 1; }
[ "$EMU_OK" -ge 6 ] || { echo "too few commands understood on the emulated Core 2" >&2; exit 1; }
echo "RESULT: PASS"
