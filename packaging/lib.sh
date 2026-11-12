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
  apt-get install -y ca-certificates curl openssl tar coreutils util-linux iproute2 passwd"
  fi
}

# verify_bundle <tarball> <public-key-file> <allow-unsigned: 0|1>
# Authenticity first (signature over SHA256SUMS), then integrity (checksum).
verify_bundle() {
  local bundle=$1 pubkey=$2 allow_unsigned=$3
  local dir base
  dir=$(dirname "$bundle"); base=$(basename "$bundle")
  [ -f "$bundle" ] || die "Bundle not found: $bundle"
  [ -f "$dir/SHA256SUMS" ] || die "SHA256SUMS must be in the same folder as the bundle ($dir)."

  if [ "$allow_unsigned" = "1" ]; then
    warn "Signature check skipped (--insecure-skip-signature). Authenticity of this bundle is NOT verified."
  else
    [ -f "$pubkey" ] || die "No release signing key at $pubkey.
The repository does not contain a public key yet, so authenticity cannot be verified.
See docs/INSTALL.md, 'Release signing key'."
    [ -f "$dir/SHA256SUMS.sig" ] || die "SHA256SUMS.sig must be in the same folder as the bundle ($dir)."
    openssl pkeyutl -verify -pubin -inkey "$pubkey" -rawin \
      -in "$dir/SHA256SUMS" -sigfile "$dir/SHA256SUMS.sig" >/dev/null 2>&1 \
      || die "Signature check FAILED. This bundle was not signed by the key in $pubkey. Nothing was installed."
    log "Signature: valid (key $pubkey)"
  fi

  local line
  line=$(grep -F "  $base" "$dir/SHA256SUMS" || true)
  [ -n "$line" ] || die "$base is not listed in SHA256SUMS."
  ( cd "$dir" && printf '%s\n' "$line" | sha256sum --check --status ) \
    || die "Checksum mismatch for $base: the file is corrupt or was altered. Nothing was installed."
  log "Checksum: matches"
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
