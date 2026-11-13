#!/usr/bin/env bash
# Build the JARVIS OS ISO.
#
#   os/build.sh --bundle home-ai-<version>-linux-x86_64.tar.gz [--out DIR] [--selftest]
#
# The bundle (and its .sigstore.json beside it) is the signed release of the
# JARVIS core and dashboard. It is verified with the same Sigstore check the
# installer uses BEFORE anything is built; an unsigned or altered bundle stops
# the build. The image itself is assembled by live-build inside a debian:trixie
# container, so the build does not depend on the host distribution.
#
# Needs: docker, curl, tar, sha256sum. Output: <out>/jarvis-os-amd64.iso and
# <out>/jarvis-os-amd64.iso.sha256.
#
# --selftest adds the kernel parameter jarvis.selftest=1 to the boot entry,
# which makes the image run its boot self-test and power off. CI uses it; a
# release image is built without it.
set -euo pipefail

OSDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$OSDIR")
BUNDLE=""
OUT="$REPO/out"
SELFTEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE=${2:-}; shift 2 ;;
    --out) OUT=${2:-}; shift 2 ;;
    --selftest) SELFTEST=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done
[ -n "$BUNDLE" ] || { echo "give --bundle FILE (see --help)" >&2; exit 1; }
BUNDLE=$(readlink -f "$BUNDLE")
mkdir -p "$OUT"
OUT=$(readlink -f "$OUT")
command -v docker >/dev/null 2>&1 || { echo "docker is required (it runs the Debian trixie build container)" >&2; exit 1; }

# ---- verify the release bundle: production Sigstore path only ----------------
unset HOME_AI_TEST_PUBKEY
export HOME_AI_TOOLS_DIR=${HOME_AI_TOOLS_DIR:-$OUT/.tools}
# shellcheck source=../packaging/lib.sh
. "$REPO/packaging/lib.sh"
step "Verifying the release bundle"
verify_bundle "$BUNDLE"

# ---- stage the live-build configuration --------------------------------------
step "Staging the image configuration"
WORK="$OUT/work"
rm -rf "$WORK"
mkdir -p "$WORK/unpack"
cp -a "$OSDIR/config" "$WORK/config"
tar --no-same-owner -xzf "$BUNDLE" -C "$WORK/unpack"
ROOT=$(find "$WORK/unpack" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ -f "$ROOT/home-ai" ] && [ -f "$ROOT/web/index.html" ] && [ -f "$ROOT/VERSION" ] || die "unexpected bundle layout"

INC="$WORK/config/includes.chroot"
install -D -m 0755 "$ROOT/home-ai" "$INC/opt/home-ai/bin/home-ai"
cp -r "$ROOT/web" "$INC/opt/home-ai/web"
install -D -m 0644 "$ROOT/VERSION" "$INC/opt/home-ai/VERSION"
install -D -m 0644 "$REPO/packaging/home-ai.service" "$INC/etc/systemd/system/home-ai.service"
rm -rf "$WORK/unpack"
log "JARVIS core $(cat "$INC/opt/home-ai/VERSION") staged"

# ---- build ------------------------------------------------------------------
step "Building the image in a debian:trixie container (this takes several minutes)"
docker run --rm --privileged \
  -e SELFTEST="$SELFTEST" -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
  -v "$WORK":/stage \
  -v "$OSDIR/in-container.sh":/in-container.sh:ro \
  debian:trixie bash /in-container.sh

ISO="$WORK/out/jarvis-os-amd64.iso"
[ -f "$ISO" ] || die "the build finished without producing an ISO"
mv "$ISO" "$OUT/jarvis-os-amd64.iso"
( cd "$OUT" && sha256sum jarvis-os-amd64.iso > jarvis-os-amd64.iso.sha256 )
rm -rf "$WORK"
step "Done"
ls -l "$OUT/jarvis-os-amd64.iso" "$OUT/jarvis-os-amd64.iso.sha256"
cat "$OUT/jarvis-os-amd64.iso.sha256"
