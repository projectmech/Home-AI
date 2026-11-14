#!/usr/bin/env bash
# How fast does a model run on THIS computer? Run it on the Mac mini.
#
#   OLLAMA_HOST=127.0.0.1:11434 bash llm/bench-models.sh [model ...]
#
# Needs a running Ollama (`ollama serve`) and curl and jq. For each model it
# pulls (if missing), loads it, answers one short prompt, and prints how many
# words (tokens) per second it reads and writes. With no arguments it tries
# the candidate list below; a name that cannot be pulled is skipped, not fatal.
set -uo pipefail
HOST="${OLLAMA_HOST:-127.0.0.1:11434}"
HOST="${HOST#http://}"
API="http://$HOST"
OLLAMA_BIN="${OLLAMA_BIN:-ollama}"
PROMPT="${PROMPT:-You are a calm, dry-witted home assistant. In two sentences, tell me good morning and mention the weather is unknown.}"
TOKENS="${TOKENS:-64}"

# Candidates, smallest first. The abliterated/uncensored builds are community
# models: check each model card's licence before using one for real. Names that
# do not exist on the registry are simply skipped.
DEFAULTS=(
  "llama3.2:1b"
  "llama3.2:3b"
  "huihui_ai/llama3.2-abliterate:1b"
  "huihui_ai/llama3.2-abliterate:3b"
  "hf.co/mradermacher/Llama-3.2-1B-Instruct-Uncensored-GGUF:Q4_K_M"
)
MODELS=("$@")
[ "${#MODELS[@]}" -gt 0 ] || MODELS=("${DEFAULTS[@]}")

command -v jq >/dev/null || { echo "jq is needed" >&2; exit 2; }
curl -fsS --max-time 10 "$API/api/version" >/dev/null || { echo "no Ollama answering at $API (start it with: ollama serve)" >&2; exit 2; }
echo "Ollama $(curl -fsS "$API/api/version" | jq -r .version) at $API; $(nproc) CPU threads"
echo "cpu: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')"
echo "avx: $(grep -qw avx /proc/cpuinfo && echo yes || echo no)"
printf '%-62s %8s %9s %9s %9s\n' MODEL "SIZE-MB" "LOAD-s" "READ-t/s" "WRITE-t/s"

for m in "${MODELS[@]}"; do
  if ! OLLAMA_HOST="$HOST" "$OLLAMA_BIN" pull "$m" >/dev/null 2>&1; then
    printf '%-62s %s\n' "$m" "(could not be pulled, skipped)"
    continue
  fi
  size=$(curl -fsS "$API/api/tags" | jq -r --arg m "$m" '[.models[] | select(.name==$m or .model==$m or (.name|startswith($m+":")))][0].size // 0')
  body=$(jq -n --arg m "$m" --arg p "$PROMPT" --argjson n "$TOKENS" \
    '{model:$m, prompt:$p, stream:false, options:{num_predict:$n, temperature:0}}')
  out=$(curl -fsS --max-time "${MAX_SECONDS:-1800}" "$API/api/generate" -d "$body" 2>&1) || { printf '%-62s %s\n' "$m" "(generation failed)"; continue; }
  echo "$out" | jq -r --arg m "$m" --argjson sz "$size" '
    def s(x): if x == null or x == 0 then 0 else x / 1e9 end;
    [$m, ($sz/1048576|floor), (s(.load_duration)*10|floor/10),
     (if .prompt_eval_duration > 0 then (.prompt_eval_count / s(.prompt_eval_duration)*10|floor/10) else 0 end),
     (if .eval_duration > 0 then (.eval_count / s(.eval_duration)*10|floor/10) else 0 end)]
    | @tsv' | awk -F'\t' '{ printf "%-62s %8s %9s %9s %9s\n", $1, $2, $3, $4, $5 }'
  echo "    says: $(echo "$out" | jq -r .response | tr '\n' ' ' | cut -c1-160)"
done
