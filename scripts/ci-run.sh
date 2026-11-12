#!/usr/bin/env bash
# Run a CI command. If it fails, repeat the useful part of its output as a
# GitHub annotation, so the cause shows on the run's summary page.
# Usage: scripts/ci-run.sh <name> <command...>
name=${1:?usage: ci-run.sh <name> <command...>}
shift

log=$(mktemp)
"$@" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}

if [ "$rc" -ne 0 ]; then
  excerpt=$(grep -E -A 14 '^(error|---- .* stdout ----|failures:)' "$log" | head -n 45)
  [ -n "$excerpt" ] || excerpt=$(tail -n 40 "$log")
  printf '::error title=%s failed::%s\n' "$name" \
    "$(printf '%s\n' "$excerpt" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
fi
rm -f "$log"
exit "$rc"
