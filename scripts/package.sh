#!/usr/bin/env bash
# Build a release bundle from an already-built binary and frontend.
# Usage: scripts/package.sh <home-ai-binary> <web-dist-dir> <output-dir>
#
# Produces <output-dir>/home-ai-<version>-linux-x86_64.tar.gz (binary, web/,
# VERSION, installer/) and prints its path on the last line.
#
# Signing is NOT done here. Real releases are signed with Sigstore in the
# Release workflow (scripts/release-sign.sh). For CI install tests only,
# TEST_SIGNING_KEY_FILE adds a throwaway-key signature as <bundle>.testsig.
set -euo pipefail

BIN=$(readlink -f "${1:?usage: package.sh <binary> <web-dist> <out-dir>}")
WEB=$(readlink -f "${2:?usage: package.sh <binary> <web-dist> <out-dir>}")
OUT=${3:?usage: package.sh <binary> <web-dist> <out-dir>}

[ -x "$BIN" ] || { echo "not executable: $BIN" >&2; exit 1; }
[ -f "$WEB/index.html" ] || { echo "no index.html in $WEB" >&2; exit 1; }

VERSION=$("$BIN" version | awk '{print $2}')
[ -n "$VERSION" ] || { echo "could not read version from binary" >&2; exit 1; }
NAME="home-ai-${VERSION}-linux-x86_64"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$NAME" "$OUT"
install -m 0755 "$BIN" "$STAGE/$NAME/home-ai"
cp -r "$WEB" "$STAGE/$NAME/web"
printf '%s\n' "$VERSION" > "$STAGE/$NAME/VERSION"

# The installer travels inside the signed bundle, so `get.sh` can run it only
# after the whole bundle has been verified.
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$STAGE/$NAME/installer/packaging"
for f in install.sh update.sh uninstall.sh; do
  install -m 0755 "$REPO/$f" "$STAGE/$NAME/installer/$f"
done
install -m 0644 "$REPO/packaging/lib.sh" "$REPO/packaging/home-ai.service" \
  "$REPO/packaging/home-ai.env.template" "$STAGE/$NAME/installer/packaging/"

OUT=$(readlink -f "$OUT")
# Fixed owner and order so the same inputs give the same archive.
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$STAGE" -czf "$OUT/$NAME.tar.gz" "$NAME"

if [ -n "${TEST_SIGNING_KEY_FILE:-}" ]; then
  openssl pkeyutl -sign -rawin -inkey "$TEST_SIGNING_KEY_FILE" \
    -in "$OUT/$NAME.tar.gz" -out "$OUT/$NAME.tar.gz.testsig"
fi

echo "$OUT/$NAME.tar.gz"
