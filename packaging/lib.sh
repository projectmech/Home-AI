# Shared by install.sh, update.sh and uninstall.sh. Sourced, not executed.
# shellcheck shell=bash

PREFIX=/opt/home-ai
ETC_DIR=/etc/home-ai
ENV_FILE=$ETC_DIR/home-ai.env
DATA_DIR=/var/lib/home-ai
SVC_USER=home-ai
SERVICE=home-ai.service
UNIT_FILE=/etc/systemd/system/$SERVICE
WRAPPER=/usr/local/bin/home-ai
PORT=8443
CERT_FILE=$DATA_DIR/tls/cert.pem

log()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

need_root() {
  [ "$(id -u)" -eq 0 ] || die "This must run as root. Try: sudo $0 $*"
}

need_commands() {
  local missing=()
  for c in "$@"; do command -v "$c" >/dev/null 2>&1 || missing+=("$c"); done
  if [ "${#missing[@]}" -gt 0 ]; then
    die "Missing required commands: ${missing[*]}
On Debian or Ubuntu install them with:
  apt-get install -y ca-certificates curl tar coreutils util-linux iproute2 passwd gawk"
  fi
}

# ---- release verification (Sigstore keyless) --------------------------------
#
# Releases are signed in GitHub Actions with a short-lived certificate that
# Sigstore issues to the workflow's GitHub OIDC identity. There is no long-lived
# private key anywhere. A release is accepted only if its Sigstore bundle proves
# it was signed by THIS workflow, in THIS repository, on a version tag.

# The only identity releases are accepted from.
RELEASE_IDENTITY_REGEXP='^https://github\.com/projectmech/Home-AI/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'
RELEASE_OIDC_ISSUER='https://token.actions.githubusercontent.com'

# The verifier itself is pinned: exact version and SHA-256 of the official
# sigstore/cosign release binary (digest as published on its release page).
COSIGN_VERSION=v3.1.4
COSIGN_SHA256=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa
COSIGN_URL="https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64"
TOOLS_DIR=${HOME_AI_TOOLS_DIR:-/usr/local/lib/home-ai}
COSIGN="$TOOLS_DIR/cosign-$COSIGN_VERSION"

sha256_of() { sha256sum "$1" | awk '{print $1}'; }

# Makes sure the pinned cosign is present, intact and runs on this CPU.
ensure_cosign() {
  if [ -x "$COSIGN" ] && [ "$(sha256_of "$COSIGN")" = "$COSIGN_SHA256" ]; then
    return 0
  fi
  log "Fetching the release verifier (cosign $COSIGN_VERSION, about 140 MB)..."
  mkdir -p "$TOOLS_DIR"
  local tmp="$COSIGN.download"
  curl --silent --show-error --fail --location --max-time 900 "$COSIGN_URL" -o "$tmp" \
    || { rm -f "$tmp"; die "Could not download cosign from $COSIGN_URL.
Releases cannot be verified without it, so nothing was installed."; }
  local got
  got=$(sha256_of "$tmp")
  if [ "$got" != "$COSIGN_SHA256" ]; then
    rm -f "$tmp"
    die "The downloaded cosign does not match its pinned checksum.
  expected $COSIGN_SHA256
  got      $got
Nothing was installed."
  fi
  chmod 0755 "$tmp"
  mv "$tmp" "$COSIGN"
  "$COSIGN" version >/dev/null 2>&1 \
    || die "cosign $COSIGN_VERSION does not run on this machine, so releases cannot be verified. Nothing was installed."
}

# verify_bundle <tarball>
# Requires <tarball>.sigstore.json beside it. Proves integrity (the signature
# covers the file's digest) and provenance (who signed it). There is no way to
# skip this.
verify_bundle() {
  local bundle=$1
  [ -f "$bundle" ] || die "Bundle not found: $bundle"

  # Test hook, honoured only on CI runners: lets the install tests exercise
  # install/update/rollback with throwaway bundles. Still a real signature check.
  if [ "${CI:-}" = "true" ] && [ -n "${HOME_AI_TEST_PUBKEY:-}" ]; then
    [ -f "$bundle.testsig" ] || die "Test signature missing: $bundle.testsig. Nothing was installed."
    openssl pkeyutl -verify -pubin -inkey "$HOME_AI_TEST_PUBKEY" -rawin \
      -in "$bundle" -sigfile "$bundle.testsig" >/dev/null 2>&1 \
      || die "Test signature check FAILED for $(basename "$bundle"). Nothing was installed."
    warn "Verified with a CI TEST KEY, not Sigstore. This must never appear outside CI."
    return 0
  fi

  local evidence="$bundle.sigstore.json"
  [ -f "$evidence" ] || die "No verification evidence: $(basename "$evidence") must be in the same folder as the bundle.
A release without it is not accepted. Nothing was installed."

  ensure_cosign
  local out
  if ! out=$("$COSIGN" verify-blob \
      --bundle "$evidence" \
      --certificate-identity-regexp "$RELEASE_IDENTITY_REGEXP" \
      --certificate-oidc-issuer "$RELEASE_OIDC_ISSUER" \
      "$bundle" 2>&1); then
    die "Release verification FAILED for $(basename "$bundle").
It is not proven to come from the release workflow of github.com/projectmech/Home-AI,
or the file was altered. Nothing was installed.
cosign said:
$(printf '%s\n' "$out" | tail -n 6)"
  fi
  log "Verified: signed by the Home-AI release workflow (Sigstore, keyless), contents intact."
}

# extract_bundle <tarball> <empty-dir>; prints the directory holding home-ai, web/, VERSION.
extract_bundle() {
  local bundle=$1 dest=$2 root
  tar --no-same-owner -xzf "$bundle" -C "$dest" || die "Could not unpack $bundle."
  root=$(find "$dest" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  [ -n "$root" ] && [ -f "$root/home-ai" ] && [ -f "$root/web/index.html" ] && [ -f "$root/VERSION" ] \
    || die "Bundle layout is wrong: expected home-ai, web/index.html and VERSION."
  chmod 0755 "$root/home-ai"
  printf '%s\n' "$root"
}

# Proves the binary runs on this CPU before anything is installed.
check_binary_runs() {
  local out
  out=$("$1/home-ai" version 2>&1) || die "The release binary does not run on this machine:
  $out
If this says 'Illegal instruction', the build needs CPU features this processor lacks.
No compatible binary is available; nothing was installed and nothing will be compiled here."
  log "Binary runs here: $out"
}

# swap_in <extracted-root>: installs to $PREFIX, keeping the old one as $PREFIX.prev
swap_in() {
  local src=$1
  rm -rf "$PREFIX.new"
  mkdir -p "$PREFIX.new/bin"
  install -m 0755 "$src/home-ai" "$PREFIX.new/bin/home-ai"
  cp -r "$src/web" "$PREFIX.new/web"
  install -m 0644 "$src/VERSION" "$PREFIX.new/VERSION"
  chown -R root:root "$PREFIX.new"
  chmod -R go-w "$PREFIX.new"
  if [ -d "$PREFIX" ]; then
    rm -rf "$PREFIX.prev"
    mv "$PREFIX" "$PREFIX.prev"
  fi
  mv "$PREFIX.new" "$PREFIX"
}

# Health over HTTPS, verified against the server's own certificate.
is_healthy() {
  [ -f "$CERT_FILE" ] && curl --silent --fail --max-time 5 --cacert "$CERT_FILE" \
    "https://localhost:${PORT}/api/health" 2>/dev/null
}

wait_healthy() {
  local i
  for i in $(seq 1 40); do
    if is_healthy >/dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}

lan_ip() {
  ip -4 route get 1.1.1.1 2>/dev/null \
    | awk '{for (i = 1; i < NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}

installed_version() {
  if [ -f "$PREFIX/VERSION" ]; then cat "$PREFIX/VERSION"; else echo "none"; fi
}
