#!/usr/bin/env bash
# Fetch the Vosk library and the small English model into voice/vendor/.
# Each download is checked against a pinned SHA-256. While a pin is empty the
# script prints the hash it saw and refuses to continue unless
# ALLOW_UNPINNED=1 (used once, to learn the hash, never in a release).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p vendor
VOSK_VERSION=0.3.45
LIB_URL="https://github.com/alphacep/vosk-api/releases/download/v${VOSK_VERSION}/vosk-linux-x86_64-${VOSK_VERSION}.zip"
LIB_SHA256=""
MODEL_NAME=vosk-model-small-en-us-0.15
MODEL_URL="https://alphacephei.com/vosk/models/${MODEL_NAME}.zip"
MODEL_SHA256=""

fetch() { # url sha256 file
  [ -f "vendor/$3" ] || curl -fsSL --retry 3 -o "vendor/$3" "$1"
  local got
  got=$(sha256sum "vendor/$3" | cut -d' ' -f1)
  echo "$3 sha256=$got size=$(stat -c %s "vendor/$3")"
  if [ -z "$2" ]; then
    [ "${ALLOW_UNPINNED:-0}" = 1 ] || { echo "no pinned hash for $3" >&2; exit 1; }
  elif [ "$got" != "$2" ]; then
    echo "HASH MISMATCH for $3 (expected $2)" >&2
    exit 1
  fi
}

fetch "$LIB_URL" "$LIB_SHA256" vosk-lib.zip
fetch "$MODEL_URL" "$MODEL_SHA256" model.zip
if [ ! -d vendor/lib ]; then
  mkdir -p vendor/lib
  unzip -q -o vendor/vosk-lib.zip -d vendor/lib
fi
if [ ! -d vendor/model ]; then
  unzip -q -o vendor/model.zip -d vendor/model-tmp
  mv "vendor/model-tmp/${MODEL_NAME}" vendor/model
  rmdir vendor/model-tmp
fi
find vendor/lib -type f | head -n 20
