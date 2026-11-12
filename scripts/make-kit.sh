#!/usr/bin/env bash
# Assemble the USB install kit in <output-dir> from the newest published
# release. Needs the GitHub CLI (gh) signed in with read access to the
# repository (in CI: GH_TOKEN), curl and sha256sum.
#
# Usage: scripts/make-kit.sh <output-dir>
set -euo pipefail

OUT=${1:?usage: make-kit.sh <output-dir>}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SLUG=projectmech/Home-AI

COSIGN_VERSION=$(sed -n 's/^COSIGN_VERSION=//p' "$REPO/get.sh")
COSIGN_SHA256=$(sed -n 's/^COSIGN_SHA256=//p' "$REPO/get.sh")
[ -n "$COSIGN_VERSION" ] && [ -n "$COSIGN_SHA256" ] || { echo "could not read the pinned cosign from get.sh" >&2; exit 1; }

mkdir -p "$OUT"

echo "== newest published release"
TAG=$(gh release list --repo "$SLUG" --limit 10 --json tagName,isDraft \
  --jq '[.[] | select(.isDraft | not)][0].tagName')
[ -n "$TAG" ] || { echo "no published release found" >&2; exit 1; }
echo "release: $TAG"

gh release download "$TAG" --repo "$SLUG" --dir "$OUT" \
  --pattern 'home-ai-*-linux-x86_64.tar.gz' \
  --pattern 'home-ai-*-linux-x86_64.tar.gz.sigstore.json'

BUNDLE=$(ls "$OUT"/home-ai-*-linux-x86_64.tar.gz)
[ "$(echo "$BUNDLE" | wc -l)" -eq 1 ] || { echo "expected exactly one bundle" >&2; exit 1; }
[ -f "$BUNDLE.sigstore.json" ] || { echo "release $TAG has no .sigstore.json evidence" >&2; exit 1; }
tar tzf "$BUNDLE" > "$OUT/.listing"
grep -q '/installer/install.sh$' "$OUT/.listing" || { echo "release $TAG has no installer inside it; it is too old for the kit" >&2; exit 1; }
rm -f "$OUT/.listing"
VERSION=$(basename "$BUNDLE" | sed 's/^home-ai-\(.*\)-linux-x86_64\.tar\.gz$/\1/')

echo "== pinned verifier (cosign $COSIGN_VERSION)"
curl --silent --show-error --fail --location --max-time 900 \
  "https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64" \
  -o "$OUT/cosign-linux-amd64"
GOT=$(sha256sum "$OUT/cosign-linux-amd64" | awk '{print $1}')
[ "$GOT" = "$COSIGN_SHA256" ] || { echo "cosign checksum mismatch: expected $COSIGN_SHA256 got $GOT" >&2; exit 1; }

echo "== scripts and instructions"
install -m 0755 "$REPO/get.sh" "$OUT/get.sh"
install -m 0755 "$REPO/packaging/kit/start.sh" "$OUT/start.sh"
sed "s/@VERSION@/$VERSION/g" "$REPO/packaging/kit/START-HERE.txt" > "$OUT/START-HERE.txt"

echo "kit for $TAG assembled in $OUT:"
ls -l "$OUT"
