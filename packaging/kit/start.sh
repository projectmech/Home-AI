#!/usr/bin/env bash
# Starts the Home AI installation from the files on this USB stick.
# Run it with:  sudo bash start.sh      (see START-HERE.txt)
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[ "$(id -u)" -eq 0 ] || { echo "Run it with sudo:  sudo bash $0" >&2; exit 1; }
[ -f "$HERE/get.sh" ] || { echo "get.sh is missing from $HERE. Copy the whole kit folder, not single files." >&2; exit 1; }

exec bash "$HERE/get.sh" --from "$HERE" "$@"
