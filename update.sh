#!/usr/bin/env bash
# Update (or roll back) an installed Home AI from a verified release bundle.
#
#   sudo ./update.sh --bundle /path/to/home-ai-<version>-linux-x86_64.tar.gz
#   sudo ./update.sh --rollback
#
# Before replacing anything it stops the service and copies the database.
# If the new version does not become healthy, the previous program files and
# the database copy are restored and the old version is started again.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=packaging/lib.sh
. "$REPO_DIR/packaging/lib.sh"

PUBKEY=${HOME_AI_PUBKEY:-$REPO_DIR/packaging/release-signing.pub.pem}
BUNDLE=""
ALLOW_UNSIGNED=0
ROLLBACK=0

usage() {
  cat <<EOF
Usage: sudo ./update.sh --bundle FILE [--insecure-skip-signature]
       sudo ./update.sh --rollback

  --bundle FILE   Release bundle; SHA256SUMS and SHA256SUMS.sig beside it.
  --rollback      Go back to the version and database from before the last update.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --bundle) BUNDLE=${2:-}; shift 2 ;;
    --rollback) ROLLBACK=1; shift ;;
    --insecure-skip-signature) ALLOW_UNSIGNED=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
done

need_root "$@"
[ -d "$PREFIX" ] || die "Home AI is not installed. Use install.sh first."
need_commands systemctl curl openssl tar sha256sum install

BACKUP_ROOT=$DATA_DIR/backups
LAST_BACKUP_LINK=$BACKUP_ROOT/last-pre-update

# Restores program files from $PREFIX.prev and the database from <backup-dir>.
restore_previous() {
  local backup=$1
  systemctl stop "$SERVICE" || true
  if [ -d "$PREFIX.prev" ]; then
    rm -rf "$PREFIX.failed"
    mv "$PREFIX" "$PREFIX.failed"
    mv "$PREFIX.prev" "$PREFIX"
  fi
  if [ -n "$backup" ] && [ -f "$backup/home-ai.db" ]; then
    rm -f "$DATA_DIR/home-ai.db" "$DATA_DIR/home-ai.db-wal" "$DATA_DIR/home-ai.db-shm"
    for f in home-ai.db home-ai.db-wal home-ai.db-shm; do
      [ -f "$backup/$f" ] && cp -p "$backup/$f" "$DATA_DIR/$f" || true
    done
  fi
  # A version that kept crashing may have tripped systemd's start limit.
  systemctl reset-failed "$SERVICE" 2>/dev/null || true
  systemctl start "$SERVICE"
}

if [ "$ROLLBACK" = "1" ]; then
  [ -d "$PREFIX.prev" ] || die "No previous version is kept on this machine; nothing to roll back to."
  BACKUP=$(readlink -f "$LAST_BACKUP_LINK" 2>/dev/null || true)
  [ -n "$BACKUP" ] && [ -f "$BACKUP/home-ai.db" ] \
    || die "No pre-update database copy found in $BACKUP_ROOT; refusing to roll back program files alone."
  step "Rolling back from $(installed_version) to $(cat "$PREFIX.prev/VERSION")"
  log "Changes made since the update will be lost: the database returns to its pre-update copy."
  restore_previous "$BACKUP"
  wait_healthy || die "The previous version did not become healthy either. See: journalctl -u home-ai -n 100"
  log "Rolled back. Running version: $(installed_version)"
  exit 0
fi

[ -n "$BUNDLE" ] || { usage >&2; die "Give --bundle FILE or --rollback."; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

step "Verifying the release bundle"
verify_bundle "$BUNDLE" "$PUBKEY" "$ALLOW_UNSIGNED"
SRC=$(extract_bundle "$BUNDLE" "$TMP")
check_binary_runs "$SRC"
OLD_VERSION=$(installed_version)
NEW_VERSION=$(cat "$SRC/VERSION")
log "Installed: $OLD_VERSION   Bundle: $NEW_VERSION"

step "Stopping the service and backing up the database"
systemctl stop "$SERVICE"
BACKUP=$BACKUP_ROOT/pre-update-$(date -u +%Y%m%dT%H%M%SZ)-from-$OLD_VERSION
install -d -m 0750 -o "$SVC_USER" -g "$SVC_USER" "$BACKUP_ROOT" "$BACKUP"
if [ -f "$DATA_DIR/home-ai.db" ]; then
  # The service is stopped, so the database file is complete on its own once
  # SQLite has checkpointed; copy any leftover WAL too, to be safe.
  cp -p "$DATA_DIR/home-ai.db" "$BACKUP/"
  for extra in home-ai.db-wal home-ai.db-shm; do
    [ -f "$DATA_DIR/$extra" ] && cp -p "$DATA_DIR/$extra" "$BACKUP/" || true
  done
  log "Database copied to $BACKUP"
  log "(This copy is on the same drive. It protects against a bad update, not against drive failure.)"
fi
ln -sfn "$BACKUP" "$LAST_BACKUP_LINK"

step "Installing $NEW_VERSION"
swap_in "$SRC"
install -m 0644 "$REPO_DIR/packaging/$SERVICE" "$UNIT_FILE"
systemctl daemon-reload
systemctl start "$SERVICE"

if wait_healthy; then
  log ""
  log "Update completed. Running version: $NEW_VERSION"
  log "To undo it:  sudo ./update.sh --rollback"
  exit 0
fi

warn "Version $NEW_VERSION did not become healthy. Rolling back to $OLD_VERSION."
systemctl --no-pager --lines=20 status "$SERVICE" >&2 || true
restore_previous "$BACKUP"
if wait_healthy; then
  die "Update FAILED and was rolled back. Version $OLD_VERSION is running again with its pre-update database.
The failed files are kept in $PREFIX.failed for inspection."
fi
die "Update FAILED and the rollback did not become healthy either.
Database copy: $BACKUP
See: journalctl -u home-ai -n 100 --no-pager"
