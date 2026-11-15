#!/usr/bin/env bash
# Build the JARVIS Probe ISO: a small read-only hardware inspection medium that
# boots UEFI or legacy BIOS (docs/PROBE.md).
#
#   probe/build.sh [--out DIR]
#
# Needs: docker, sha256sum. Output: <out>/jarvis-probe-amd64.iso and its .sha256.
# The image is assembled by live-build inside a debian:trixie container.
set -euo pipefail

PROBEDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$PROBEDIR")
OUT="$REPO/out"
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

WORK="$OUT/probe-work"
rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$PROBEDIR/config" "$WORK/config"

docker run --rm --privileged \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$WORK":/stage \
  -v "$PROBEDIR/in-container.sh":/in-container.sh:ro \
  debian:trixie bash /in-container.sh

ISO="$WORK/out/jarvis-probe-amd64.iso"
[ -f "$ISO" ] || { echo "the build finished without producing an ISO" >&2; exit 1; }
mv "$ISO" "$OUT/jarvis-probe-amd64.iso"
(cd "$OUT" && sha256sum jarvis-probe-amd64.iso > jarvis-probe-amd64.iso.sha256)
rm -rf "$WORK"
ls -l "$OUT/jarvis-probe-amd64.iso"
cat "$OUT/jarvis-probe-amd64.iso.sha256"
