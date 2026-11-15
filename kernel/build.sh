#!/usr/bin/env bash
# Build the JARVIS kernel packages (docs/KERNEL.md).
#
#   kernel/build.sh [--out DIR]
#
# Needs docker. Output: <out>/linux-image-*-jarvis-amd64_*.deb, linux-headers-*,
# linux-libc-dev_*, and RELEASE (the kernel release string). Takes 10 to 25 minutes.
set -euo pipefail
KDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$KDIR")
OUT="$REPO/out/kernel"
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=${2:-}; shift 2 ;;
    -h | --help) sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
mkdir -p "$OUT"
OUT=$(readlink -f "$OUT")
command -v docker > /dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker run --rm \
  -e KERNEL_VERSION="${KERNEL_VERSION:-}" -e ALLOW_UNVERIFIED="${ALLOW_UNVERIFIED:-0}" \
  -v "$REPO":/src:ro -v "$OUT":/out \
  debian:trixie bash /src/kernel/in-container.sh
ls -l "$OUT"
