#!/usr/bin/env bash
# One-command installer for Home AI (Debian or Ubuntu, x86-64, systemd).
#
# Download this file, read it, then run it as root:
#
#   curl -fsSL <address of get.sh> -o get-home-ai.sh && sudo bash get-home-ai.sh && rm get-home-ai.sh
#
# What it does: downloads the latest release bundle from GitHub, PROVES with
# Sigstore that the bundle was signed by this project's release workflow and is
# unaltered, and only then unpacks it and runs the installer that ships inside
# it. Nothing from the bundle runs before it is verified. There is no option to
# skip verification. It never compiles anything.
#
# This file is the trust anchor: it is fetched over HTTPS from the repository,
# so read it (or pin a commit) before running it as root.
set -euo pipefail

GITHUB_REPO=projectmech/Home-AI

# These four lines must match packaging/lib.sh; CI checks that they do.
RELEASE_IDENTITY_REGEXP='^https://github\.com/projectmech/Home-AI/\.github/workflows/release\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$'
RELEASE_OIDC_ISSUER='https://token.actions.githubusercontent.com'
COSIGN_VERSION=v3.1.4
COSIGN_SHA256=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa

COSIGN_URL="https://github.com/sigstore/cosign/releases/download/$COSIGN_VERSION/cosign-linux-amd64"
TOOLS_DIR=/usr/local/lib/home-ai
COSIGN="$TOOLS_DIR/cosign-$COSIGN_VERSION"

log()  { printf '%s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

RELEASE_TAG=latest
PASSTHROUGH=()

usage() {
  cat <<EOF
Usage: sudo bash get.sh [--version TAG] [--force-distro]

  (no arguments)   Install the latest release.
  --version TAG    Install release TAG (for example v0.1.1).
  --force-distro   Continue on a distribution other than Debian or Ubuntu.

While the repository is private, GitHub refuses the download without a token.
The script then asks for one (read access to $GITHUB_REPO, input hidden, not
saved), or reads it from the environment variable HOME_AI_GITHUB_TOKEN.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version) RELEASE_TAG=${2:-}; [ -n "$RELEASE_TAG" ] || die "--version needs a tag."; shift 2 ;;
    --force-distro) PASSTHROUGH+=(--force-distro); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"
[ "$(uname -m)" = "x86_64" ] || die "Unsupported CPU architecture: $(uname -m). Releases are built for x86_64 only."
for c in curl tar sha256sum awk mktemp; do
  command -v "$c" >/dev/null 2>&1 || die "Missing command: $c. On Debian or Ubuntu: apt-get install -y ca-certificates curl tar coreutils gawk"
done

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ------------------------------------------------------------ find the release
step "Finding release '$RELEASE_TAG' on github.com/$GITHUB_REPO"
API="https://api.github.com/repos/$GITHUB_REPO"
if [ "$RELEASE_TAG" = "latest" ]; then RELEASE_URL="$API/releases/latest"
else RELEASE_URL="$API/releases/tags/$RELEASE_TAG"
fi
AUTH=()
fetch_release() {
  curl --silent --show-error --max-time 30 --output "$TMP/release.json" --write-out '%{http_code}' \
    "${AUTH[@]}" -H "Accept: application/vnd.github+json" "$RELEASE_URL" || true
}
HTTP=$(fetch_release)
if [ "$HTTP" != "200" ]; then
  # A private repository answers anonymous requests exactly like a missing one.
  GH_TOKEN=${HOME_AI_GITHUB_TOKEN:-}
  if [ -z "$GH_TOKEN" ]; then
    log "GitHub did not return the release without signing in (HTTP ${HTTP:-none})."
    log "If the repository is private, a token with read access is needed."
    [ -r /dev/tty ] || die "No terminal to ask for a token. Set HOME_AI_GITHUB_TOKEN and run again."
    printf 'GitHub token for %s (input hidden, not saved): ' "$GITHUB_REPO" > /dev/tty
    IFS= read -rs GH_TOKEN < /dev/tty; printf '\n' > /dev/tty
    [ -n "$GH_TOKEN" ] || die "No token entered."
  fi
  AUTH=(-H "Authorization: Bearer $GH_TOKEN")
  HTTP=$(fetch_release)
  case "$HTTP" in
    200) ;;
    401) die "GitHub rejected the token (HTTP 401). Check that it was copied completely and has not expired." ;;
    404) die "Release '$RELEASE_TAG' was not found (HTTP 404).
Either no such release exists, or the token cannot read $GITHUB_REPO.
A fine-grained token needs: Repository access = this repository, Permissions = Contents: Read-only." ;;
    *) die "Could not reach GitHub (HTTP ${HTTP:-none}). Check this machine's internet connection." ;;
  esac
fi
TAG_NAME=$(awk -F'"' '/"tag_name": *"/ { print $4; exit }' "$TMP/release.json")
log "Release: ${TAG_NAME:-$RELEASE_TAG}"

# ------------------------------------------------------------------ download
step "Downloading the bundle and its verification evidence"
awk -F'"' '
  /"url": *"[^"]*\/releases\/assets\/[0-9]+"/ { url = $4 }
  /"name": *"/ && url != "" { print url, $4; url = "" }
' "$TMP/release.json" > "$TMP/assets.txt"
mkdir -p "$TMP/dl"
BUNDLE=""
HAVE_EVIDENCE=0
while read -r url name; do
  case "$name" in
    home-ai-*-linux-x86_64.tar.gz) BUNDLE="$TMP/dl/$name" ;;
    home-ai-*-linux-x86_64.tar.gz.sigstore.json) HAVE_EVIDENCE=1 ;;
    *) continue ;;
  esac
  case "$name" in */*|..*) die "Refusing odd asset name: $name" ;; esac
  curl --silent --show-error --fail --location --max-time 300 \
    "${AUTH[@]}" -H "Accept: application/octet-stream" \
    "$url" -o "$TMP/dl/$name" || die "Download of $name failed."
  log "Downloaded $name"
done < "$TMP/assets.txt"
unset GH_TOKEN AUTH
[ -n "$BUNDLE" ] || die "This release has no linux-x86_64 bundle. No compatible binary is available; nothing will be compiled here."
[ "$HAVE_EVIDENCE" = "1" ] || die "This release has no verification evidence (.sigstore.json). It is not accepted. Nothing was installed."

# ------------------------------------------------------------------- verify
step "Verifying the release (Sigstore, keyless)"
sha256_of() { sha256sum "$1" | awk '{print $1}'; }
if ! { [ -x "$COSIGN" ] && [ "$(sha256_of "$COSIGN")" = "$COSIGN_SHA256" ]; }; then
  log "Fetching the verifier (cosign $COSIGN_VERSION, about 140 MB)..."
  mkdir -p "$TOOLS_DIR"
  curl --silent --show-error --fail --location --max-time 900 "$COSIGN_URL" -o "$COSIGN.download" \
    || { rm -f "$COSIGN.download"; die "Could not download cosign from $COSIGN_URL. Releases cannot be verified without it, so nothing was installed."; }
  GOT=$(sha256_of "$COSIGN.download")
  if [ "$GOT" != "$COSIGN_SHA256" ]; then
    rm -f "$COSIGN.download"
    die "The downloaded cosign does not match its pinned checksum.
  expected $COSIGN_SHA256
  got      $GOT
Nothing was installed."
  fi
  chmod 0755 "$COSIGN.download"
  mv "$COSIGN.download" "$COSIGN"
fi
"$COSIGN" version >/dev/null 2>&1 \
  || die "cosign $COSIGN_VERSION does not run on this machine, so releases cannot be verified. Nothing was installed."

if ! OUT=$("$COSIGN" verify-blob \
    --bundle "$BUNDLE.sigstore.json" \
    --certificate-identity-regexp "$RELEASE_IDENTITY_REGEXP" \
    --certificate-oidc-issuer "$RELEASE_OIDC_ISSUER" \
    "$BUNDLE" 2>&1); then
  die "Release verification FAILED for $(basename "$BUNDLE").
It is not proven to come from the release workflow of github.com/$GITHUB_REPO,
or the file was altered. Nothing was installed.
cosign said:
$(printf '%s\n' "$OUT" | tail -n 6)"
fi
log "Verified: signed by the Home-AI release workflow (Sigstore, keyless), contents intact."

# ----------------------------------------------------------- hand over
# Only now is anything from the bundle unpacked, and only its installer runs.
step "Unpacking and starting the installer from the verified bundle"
mkdir -p "$TMP/x"
tar --no-same-owner -xzf "$BUNDLE" -C "$TMP/x" || die "Could not unpack the bundle."
ROOT=$(find "$TMP/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ -n "$ROOT" ] && [ -f "$ROOT/installer/install.sh" ] \
  || die "This release does not contain the installer (installer/install.sh).
It was published before the one-command installer existed. Use a newer release,
or install from a clone of the repository: see docs/INSTALL.md."

# The installer verifies the bundle again with the same pinned verifier.
bash "$ROOT/installer/install.sh" --bundle "$BUNDLE" "${PASSTHROUGH[@]}"
