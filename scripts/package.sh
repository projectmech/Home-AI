#!/usr/bin/env bash
# Build a release bundle from an already-built binary and frontend.
# Usage: scripts/package.sh <home-ai-binary> <web-dist-dir> <output-dir>
#
# Produces in <output-dir>:
#   home-ai-<version>-linux-x86_64.tar.gz   binary, web/, VERSION
#   SHA256SUMS                              checksum of the tarball
#   SHA256SUMS.sig                          Ed25519 signature of SHA256SUMS,
#                                           only if RELEASE_SIGNING_KEY_FILE is set
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

OUT=$(readlink -f "$OUT")
# Fixed owner and order so the same inputs give the same archive.
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$STAGE" -czf "$OUT/$NAME.tar.gz" "$NAME"
( cd "$OUT" && sha256sum "$NAME.tar.gz" > SHA256SUMS )

if [ -n "${RELEASE_SIGNING_KEY_FILE:-}" ]; then
  openssl pkeyutl -sign -rawin -inkey "$RELEASE_SIGNING_KEY_FILE" \
    -in "$OUT/SHA256SUMS" -out "$OUT/SHA256SUMS.sig"
  echo "signed: $OUT/SHA256SUMS.sig"
else
  echo "RELEASE_SIGNING_KEY_FILE not set: bundle is NOT signed" >&2
fi

echo "$OUT/$NAME.tar.gz"
