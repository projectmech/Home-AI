#!/usr/bin/env bash
# Home AI installer for Debian and Ubuntu (x86-64, systemd).
#
#   sudo ./install.sh --bundle /path/to/home-ai-<version>-linux-x86_64.tar.gz
#   sudo ./install.sh --version v0.1.0        # downloads the release; asks for a GitHub token
#
# It installs a prebuilt, signed release. It never compiles anything, never
# touches disks or boot settings, and never creates a default password.
# Existing settings, data and certificate are always kept. If Home AI is
# already running it refuses and points to update.sh.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=packaging/lib.sh
. "$REPO_DIR/packaging/lib.sh"

PUBKEY=${HOME_AI_PUBKEY:-$REPO_DIR/packaging/release-signing.pub.pem}
GITHUB_REPO=${HOME_AI_REPO:-projectmech/Home-AI}
BUNDLE=""
RELEASE_TAG=""
ALLOW_UNSIGNED=0
FORCE_DISTRO=0

usage() {
  cat <<EOF
Usage: sudo ./install.sh [--version TAG | --bundle FILE] [options]

  (no arguments)              Download and install the latest release from GitHub.
  --version TAG               Download release TAG (for example v0.1.0) instead.
                              While the repository is private, downloading asks for
                              a read-only GitHub token. The token is not saved.
  --bundle FILE               Install from a release bundle already on disk.
                              SHA256SUMS and SHA256SUMS.sig must be in the same folder.
  --force-distro              Continue on a distribution other than Debian or Ubuntu.
  --insecure-skip-signature   Install without verifying who built the bundle.
  -h, --help                  Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE=${2:-}; shift 2 ;;
    --version) RELEASE_TAG=${2:-}; shift 2 ;;
    --force-distro) FORCE_DISTRO=1; shift ;;
    --insecure-skip-signature) ALLOW_UNSIGNED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

need_root "$@"
# With no arguments: the latest published release.
[ -n "$BUNDLE" ] || [ -n "$RELEASE_TAG" ] || RELEASE_TAG=latest
[ -z "$BUNDLE" ] || [ -z "$RELEASE_TAG" ] || die "Give only one of --bundle and --version."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- 1-8: checks
step "Checking this machine"

[ -r /etc/os-release ] || die "Cannot read /etc/os-release; unsupported system."
# shellcheck disable=SC1091
. /etc/os-release
DISTRO="${PRETTY_NAME:-$ID}"
case "${ID:-}" in
  debian|ubuntu) log "Distribution: $DISTRO" ;;
  *)
    if [ "$FORCE_DISTRO" = "1" ]; then warn "Untested distribution: $DISTRO"
    else die "Unsupported distribution: $DISTRO. Supported: Debian, Ubuntu. Use --force-distro to try anyway."
    fi ;;
esac

ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] || die "Unsupported CPU architecture: $ARCH. Releases are built for x86_64 only."
CPU_MODEL=$(awk -F': ' '/^model name/ {print $2; exit}' /proc/cpuinfo)
CPU_FLAGS=$(awk -F': ' '/^flags/ {print $2; exit}' /proc/cpuinfo)
log "CPU: ${CPU_MODEL:-unknown} ($ARCH)"
case " $CPU_FLAGS " in
  *" sse2 "*) ;;
  *) die "This CPU does not report SSE2, which every x86-64 build needs." ;;
esac
case " $CPU_FLAGS " in
  *" avx "*) ;;
  *) log "CPU has no AVX (expected on a Core 2 Duo). Releases are built without it." ;;
esac

MEM_MB=$(awk '/^MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
log "RAM: ${MEM_MB} MB"
[ "$MEM_MB" -ge 512 ] || die "Only ${MEM_MB} MB of RAM. At least 512 MB is required."

mkdir -p /opt /var/lib
for path in /opt /var/lib; do
  FREE_MB=$(df -Pm "$path" | awk 'NR == 2 {print $4}')
  log "Free space on $path: ${FREE_MB} MB"
  [ "$FREE_MB" -ge 1024 ] || die "Less than 1 GB free on $path. Free some space and run again."
done

ROOT_SRC=$(findmnt -no SOURCE / 2>/dev/null || true)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null | head -n 1 || true)
[ -n "$ROOT_DISK" ] || ROOT_DISK=$(basename "${ROOT_SRC:-}")
case "$(cat "/sys/block/$ROOT_DISK/queue/rotational" 2>/dev/null || echo "?")" in
  0) DRIVE_TYPE="SSD (non-rotational)" ;;
  1) DRIVE_TYPE="HDD (rotational)" ;;
  *) DRIVE_TYPE="Unknown" ;;
esac
log "System drive: ${ROOT_DISK:-unknown}, type: $DRIVE_TYPE"

[ -d /run/systemd/system ] || die "systemd is not running. Home AI is installed as a systemd service."
need_commands systemctl curl openssl tar sha256sum ip runuser useradd findmnt lsblk install

HOST_IP=$(lan_ip)
if [ -n "$HOST_IP" ]; then log "Network: address $HOST_IP"
else warn "No default IPv4 route found. The server will still start; reach it by whatever address this machine has."
fi
HOST_NAME=$(hostname 2>/dev/null || echo "")

# ------------------------------------------------- 9-10: obtain and verify
if [ -n "$RELEASE_TAG" ]; then
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
      [ -r /dev/tty ] || die "No terminal to ask for a token. Set HOME_AI_GITHUB_TOKEN, or download the bundle yourself and use --bundle."
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
Either no such release has been published yet, or the token cannot read $GITHUB_REPO.
A fine-grained token needs: Repository access = this repository, Permissions = Contents: Read-only." ;;
      *) die "Could not reach GitHub (HTTP ${HTTP:-none}). Check this machine's internet connection." ;;
    esac
  fi
  TAG_NAME=$(awk -F'"' '/"tag_name": *"/ { print $4; exit }' "$TMP/release.json")
  log "Release: ${TAG_NAME:-$RELEASE_TAG}"
  # Pairs of "<asset api url> <asset name>".
  awk -F'"' '
    /"url": *"[^"]*\/releases\/assets\/[0-9]+"/ { url = $4 }
    /"name": *"/ && url != "" { print url, $4; url = "" }
  ' "$TMP/release.json" > "$TMP/assets.txt"
  mkdir -p "$TMP/dl"
  FOUND=0
  while read -r url name; do
    case "$name" in
      home-ai-*-linux-x86_64.tar.gz) BUNDLE="$TMP/dl/$name"; FOUND=1 ;;
      SHA256SUMS|SHA256SUMS.sig) ;;
      *) continue ;;
    esac
    case "$name" in */*|..*) die "Refusing odd asset name: $name" ;; esac
    curl --silent --show-error --fail --location --max-time 300 \
      "${AUTH[@]}" -H "Accept: application/octet-stream" \
      "$url" -o "$TMP/dl/$name" || die "Download of $name failed."
    log "Downloaded $name"
  done < "$TMP/assets.txt"
  unset GH_TOKEN AUTH
  [ "$FOUND" = "1" ] || die "Release $RELEASE_TAG has no linux-x86_64 bundle. No compatible binary is available; nothing will be compiled here."
fi

step "Verifying the release bundle"
verify_bundle "$BUNDLE" "$PUBKEY" "$ALLOW_UNSIGNED"
mkdir -p "$TMP/x"
SRC=$(extract_bundle "$BUNDLE" "$TMP/x")
NEW_VERSION=$(cat "$SRC/VERSION")
check_binary_runs "$SRC"

OLD_VERSION=$(installed_version)
if [ "$OLD_VERSION" != "none" ] && systemctl is-active --quiet "$SERVICE"; then
  die "Home AI $OLD_VERSION is installed and running.
To change versions use:  sudo ./update.sh --bundle $BUNDLE
(update.sh takes a backup first and rolls back if the new version is unhealthy.)"
fi

# ------------------------------------------------------- 11-17: install
step "Installing Home AI $NEW_VERSION"

if ! id "$SVC_USER" >/dev/null 2>&1; then
  useradd --system --user-group --home-dir "$DATA_DIR" --no-create-home \
    --shell /usr/sbin/nologin "$SVC_USER"
  log "Created service account '$SVC_USER' (no login, no password)."
fi

swap_in "$SRC"
log "Program files: $PREFIX"

install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$DATA_DIR"
install -d -m 0750 -o root -g "$SVC_USER" "$ETC_DIR"
if [ -f "$ENV_FILE" ]; then
  log "Keeping existing settings: $ENV_FILE"
else
  NAMES=$(printf '%s\n' "$HOST_IP" "$HOST_NAME" | awk 'NF' | paste -sd, -)
  sed "s|@TLS_NAMES@|$NAMES|" "$REPO_DIR/packaging/home-ai.env.template" > "$ENV_FILE"
  chown root:"$SVC_USER" "$ENV_FILE"; chmod 0640 "$ENV_FILE"
  log "Settings: $ENV_FILE"
fi

# `home-ai <command>` for administrators: runs as the service account with the
# service's settings, so files it creates have the right owner.
cat > "$WRAPPER" <<EOF
#!/bin/sh
# Installed by Home AI install.sh.
[ "\$(id -u)" -eq 0 ] || { echo "Run with sudo: sudo home-ai \$*" >&2; exit 1; }
set -a; . $ENV_FILE; set +a
exec runuser -u $SVC_USER -- $PREFIX/bin/home-ai "\$@"
EOF
chmod 0755 "$WRAPPER"

# Database migrations run on first start. The certificate is created now so
# its fingerprint can be shown below.
FINGERPRINT=$("$WRAPPER" tls-fingerprint) || die "Could not create the HTTPS certificate."

install -m 0644 "$REPO_DIR/packaging/$SERVICE" "$UNIT_FILE"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null 2>&1

# ------------------------------------------------------- 18-19: start, verify
step "Starting the service"
systemctl restart "$SERVICE"
if ! wait_healthy; then
  systemctl --no-pager --lines=30 status "$SERVICE" >&2 || true
  die "The service did not become healthy. The log above shows why.
More: journalctl -u home-ai -n 100 --no-pager"
fi
HEALTH=$(is_healthy)
log "Health check: OK"

# ------------------------------------------------------------- 20: report
ADDR=$HOST_IP
[ -n "$ADDR" ] || ADDR="SERVER-ADDRESS"
SETUP_TOKEN=""
case "$HEALTH" in
  *'"setup_required":true'*)
    SETUP_TOKEN=$("$WRAPPER" setup-token | grep -Eo '[0-9a-f]{64}' || true) ;;
esac

cat <<EOF

Installation completed successfully.

Status: RUNNING (version $NEW_VERSION, starts automatically at boot)

Web Dashboard:
  https://$ADDR:$PORT
EOF

if [ -n "$SETUP_TOKEN" ]; then
  cat <<EOF

Initial Setup:
  https://$ADDR:$PORT/setup

One-time Setup Token (valid 60 minutes, single use):
  $SETUP_TOKEN

  Lost or expired? Run:  sudo home-ai setup-token
EOF
else
  log ""
  log "An administrator already exists; sign in with that account."
fi

cat <<EOF

About the browser warning
  The connection is encrypted, but this server's certificate is self-signed,
  so your browser cannot know it is talking to this machine and will warn you.
  It is NOT a trusted connection until you check it. Do one of these:

  1. Compare fingerprints. In the browser's warning, open the certificate
     details and compare its SHA-256 fingerprint with this one:

       $FINGERPRINT

     Continue only if they are identical.

  2. Or install the certificate as trusted on your devices. Copy this file
     from the server and add it to the device's trusted certificates:

       $CERT_FILE

  Show the fingerprint again:  sudo home-ai tls-fingerprint
EOF
