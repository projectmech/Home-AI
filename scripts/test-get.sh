#!/usr/bin/env bash
# Tests get.sh against the REAL published release v0.1.0: GitHub download,
# anonymous refusal then token use, pinned cosign fetch, and genuine Sigstore
# verification. v0.1.0 predates the one-command installer, so the expected end
# is a clean refusal with nothing installed. That also proves an old release
# without the installer is rejected rather than half-run. The last stage then
# runs the plain default command and really installs the newest release.
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
grep -q 'Run as root' <<< "$out" || fail "get.sh did not demand root"

echo "== real download and Sigstore verification of v0.1.0"
set +e
out=$(sudo HOME_AI_GITHUB_TOKEN="$GH_TOKEN" bash get.sh --version v0.1.0 2>&1)
rc=$?
set -e
printf '%s\n' "$out"
[ "$rc" -ne 0 ] || fail "get.sh accepted a release that has no installer"
grep -q 'Downloaded home-ai-0.1.0-linux-x86_64.tar.gz' <<< "$out" || fail "bundle was not downloaded"
grep -q 'Verified: signed by the Home-AI release workflow' <<< "$out" || fail "real release was not verified by Sigstore"
grep -q 'does not contain the installer' <<< "$out" || fail "missing-installer refusal not shown"
[ ! -e /opt/home-ai ] || fail "something was installed"
[ ! -e /etc/systemd/system/home-ai.service ] || fail "a service was installed"

echo "== a release that does not exist is refused cleanly"
set +e
out=$(sudo HOME_AI_GITHUB_TOKEN="$GH_TOKEN" bash get.sh --version v9.9.9 2>&1)
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "get.sh accepted a nonexistent release"
grep -q 'was not found' <<< "$out" || fail "no clear message for a missing release"

echo "== the default command: newest release, real download, real verification, real install"
set +e
out=$(sudo HOME_AI_GITHUB_TOKEN="$GH_TOKEN" bash get.sh 2>&1)
rc=$?
set -e
printf '%s\n' "$out" | tail -n 40
[ "$rc" -eq 0 ] || fail "the default install failed (exit $rc)"
grep -q 'Verified: signed by the Home-AI release workflow' <<< "$out" || fail "default install did not verify the release"
grep -q 'Installation completed successfully' <<< "$out" || fail "default install did not complete"
grep -q 'Status: RUNNING' <<< "$out" || fail "service not reported running"
if grep -q '^Release: v0.1.0$' <<< "$out"; then fail "picked v0.1.0, which has no installer; newest release was not chosen"; fi
systemctl is-active --quiet home-ai || fail "service is not active after the default install"
sudo bash uninstall.sh --purge --yes
[ ! -e /opt/home-ai ] || fail "purge left files behind"

echo "GET TEST PASSED"
