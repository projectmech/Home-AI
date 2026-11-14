#!/usr/bin/env bash
# Fetch the Ollama Linux tarball into llm/vendor/ollama/.
#
# Ollama (MIT licence) is the local model service: a Go server that runs
# llama.cpp underneath and listens on localhost only. The download is checked
# against the release's own sha256sum.txt and, once OLLAMA_SHA256 below is
# filled in, against a pinned hash. While the pin is empty (the learning run)
# the script prints the version and hash it saw and carries on only if
# ALLOW_UNPINNED=1 is set; a release build must have the pin set.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p vendor

OLLAMA_VERSION="${OLLAMA_VERSION:-v0.40.16}"   # empty = newest release (learning run only)
# Pinned from the first CI run (2026-11-14): the hash of the tarball as GitHub served it then.
OLLAMA_SHA256="${OLLAMA_SHA256:-87bfafb2acbc89b2e6a1be0a9043de6aa75fb450696f86bc426e65fc448f788d}"

if [ -z "$OLLAMA_VERSION" ]; then
  OLLAMA_VERSION=$(curl -fsSL --retry 3 https://api.github.com/repos/ollama/ollama/releases/latest | jq -r .tag_name)
fi
BASE="https://github.com/ollama/ollama/releases/download/${OLLAMA_VERSION}"
ASSET=ollama-linux-amd64.tar.zst
curl -fsI "$BASE/$ASSET" >/dev/null 2>&1 || ASSET=ollama-linux-amd64.tgz
echo "ollama version=$OLLAMA_VERSION asset=$ASSET"

[ -f "vendor/$ASSET" ] || curl -fsSL --retry 3 -o "vendor/$ASSET" "$BASE/$ASSET"
got=$(sha256sum "vendor/$ASSET" | cut -d' ' -f1)
echo "$ASSET sha256=$got size=$(stat -c %s "vendor/$ASSET")"

# The release publishes its own hashes: a download that does not match was damaged.
if curl -fsSL --retry 3 -o vendor/sha256sum.txt "$BASE/sha256sum.txt" 2>/dev/null; then
  want=$(grep -E "[ *]${ASSET}\$" vendor/sha256sum.txt | cut -d' ' -f1 || true)
  if [ -n "$want" ] && [ "$want" != "$got" ]; then
    echo "HASH MISMATCH against the release's sha256sum.txt (expected $want)" >&2
    exit 1
  fi
  [ -z "$want" ] || echo "matches the release's sha256sum.txt"
fi

if [ -z "$OLLAMA_SHA256" ]; then
  [ "${ALLOW_UNPINNED:-0}" = 1 ] || { echo "no pinned hash for $ASSET" >&2; exit 1; }
elif [ "$got" != "$OLLAMA_SHA256" ]; then
  echo "HASH MISMATCH against the pinned hash (expected $OLLAMA_SHA256)" >&2
  exit 1
fi

if [ ! -x vendor/ollama/bin/ollama ]; then
  rm -rf vendor/ollama
  mkdir -p vendor/ollama
  case "$ASSET" in
    *.tar.zst) tar --zstd -xf "vendor/$ASSET" -C vendor/ollama ;;
    *) tar -xzf "vendor/$ASSET" -C vendor/ollama ;;
  esac
fi
echo "binary: $(ls -l vendor/ollama/bin/ollama)"
ls vendor/ollama/lib/ollama 2>/dev/null | head -n 40 || true
