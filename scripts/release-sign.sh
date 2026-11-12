#!/usr/bin/env bash
# Sign a release bundle with Sigstore keyless signing, then verify it exactly
# the way install.sh will. Runs only inside the Release workflow, which has the
# GitHub OIDC token (permissions: id-token: write) that Sigstore needs.
#
# Usage: scripts/release-sign.sh <bundle.tar.gz>
# Writes <bundle.tar.gz>.sigstore.json (signature, certificate, log proof).
set -euo pipefail

BUNDLE=$(readlink -f "${1:?usage: release-sign.sh <bundle.tar.gz>}")
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

[ -n "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ] || {
  echo "No GitHub OIDC token available. This script signs only inside GitHub Actions with id-token: write." >&2
  exit 1
}

export HOME_AI_TOOLS_DIR="${RUNNER_TEMP:-/tmp}/home-ai-tools"
# The CI-only test hook must not be what verifies a real release.
unset HOME_AI_TEST_PUBKEY
# shellcheck source=packaging/lib.sh
. "$REPO/packaging/lib.sh"

ensure_cosign

echo "== signing (keyless: certificate issued to this workflow run)"
"$COSIGN" sign-blob --yes --bundle "$BUNDLE.sigstore.json" "$BUNDLE"

echo "== verifying as the installer does"
verify_bundle "$BUNDLE"

echo "== an altered file must be rejected"
ALTERED="${RUNNER_TEMP:-/tmp}/altered-$(basename "$BUNDLE")"
cp "$BUNDLE" "$ALTERED"
printf 'x' >> "$ALTERED"
cp "$BUNDLE.sigstore.json" "$ALTERED.sigstore.json"
if ( verify_bundle "$ALTERED" ) >/dev/null 2>&1; then
  echo "an altered bundle passed verification" >&2
  exit 1
fi

echo "== a bundle with no evidence must be rejected"
BARE="${RUNNER_TEMP:-/tmp}/bare-$(basename "$BUNDLE")"
cp "$BUNDLE" "$BARE"
if ( verify_bundle "$BARE" ) >/dev/null 2>&1; then
  echo "a bundle without evidence passed verification" >&2
  exit 1
fi

echo "== a signature from any other repository must be rejected"
if "$COSIGN" verify-blob --bundle "$BUNDLE.sigstore.json" \
    --certificate-identity-regexp '^https://github\.com/not-this-owner/.*$' \
    --certificate-oidc-issuer "$RELEASE_OIDC_ISSUER" "$BUNDLE" >/dev/null 2>&1; then
  echo "verification ignored the signer identity" >&2
  exit 1
fi

rm -f "$ALTERED" "$ALTERED.sigstore.json" "$BARE"
echo "signed and verified: $BUNDLE.sigstore.json"
