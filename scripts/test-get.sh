#!/usr/bin/env bash
# Tests get.sh against the REAL published release v0.1.0: GitHub download,
# anonymous refusal then token use, pinned cosign fetch, and genuine Sigstore
# verification. v0.1.0 predates the one-command installer, so the expected end
# is a clean refusal with nothing installed. That also proves an old release
# without the installer is rejected rather than half-run.
#
# CI ONLY: needs root via sudo and GH_TOKEN (the workflow's own read token).
set -euo pipefail

[ "${CI:-}" = "true" ] || { echo "Refusing to run outside CI." >&2; exit 1; }
[ -n "${GH_TOKEN:-}" ] || { echo "GH_TOKEN is required." >&2; exit 1; }
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

echo "== get.sh and lib.sh must carry identical verification constants"
for var in RELEASE_IDENTITY_REGEXP RELEASE_OIDC_ISSUER COSIGN_VERSION COSIGN_SHA256; do
  a=$(grep -m1 "^$var=" get.sh || true)
  b=$(grep -m1 "^$var=" packaging/lib.sh || true)
  [ -n "$a" ] && [ "$a" = "$b" ] || fail "$var differs between get.sh and packaging/lib.sh"
done

echo "== get.sh refuses to run without root"
out=$(bash get.sh --version v0.1.0 2>&1 || true)
printf '%s\n' "$out" | grep -q 'Run as root' || fail "get.sh did not demand root"

echo "== real download and Sigstore verification of v0.1.0"
set +e
out=$(sudo HOME_AI_GITHUB_TOKEN="$GH_TOKEN" bash get.sh --version v0.1.0 2>&1)
rc=$?
set -e
printf '%s\n' "$out"
[ "$rc" -ne 0 ] || fail "get.sh accepted a release that has no installer"
printf '%s\n' "$out" | grep -q 'Downloaded home-ai-0.1.0-linux-x86_64.tar.gz' || fail "bundle was not downloaded"
printf '%s\n' "$out" | grep -q 'Verified: signed by the Home-AI release workflow' || fail "real release was not verified by Sigstore"
printf '%s\n' "$out" | grep -q 'does not contain the installer' || fail "missing-installer refusal not shown"
[ ! -e /opt/home-ai ] || fail "something was installed"
[ ! -e /etc/systemd/system/home-ai.service ] || fail "a service was installed"

echo "== a release that does not exist is refused cleanly"
set +e
out=$(sudo HOME_AI_GITHUB_TOKEN="$GH_TOKEN" bash get.sh --version v9.9.9 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "get.sh accepted a nonexistent release"
printf '%s\n' "$out" | grep -q 'was not found' || fail "no clear message for a missing release"

echo "GET TEST PASSED"
