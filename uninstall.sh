#!/usr/bin/env bash
# Remove Home AI.
#
#   sudo ./uninstall.sh            # removes the program and service; KEEPS data and settings
#   sudo ./uninstall.sh --purge    # also deletes the database, certificate, backups,
#                                  # settings and the service account. Cannot be undone.
set -euo pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=packaging/lib.sh
. "$REPO_DIR/packaging/lib.sh"

PURGE=0
ASSUME_YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --purge) PURGE=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
    *) die "Unknown option: $1" ;;
  esac
done

need_root "$@"

if [ "$PURGE" = "1" ] && [ "$ASSUME_YES" != "1" ]; then
  printf 'This permanently deletes %s and %s (database, certificate, backups, settings).\n' "$DATA_DIR" "$ETC_DIR"
  printf 'Type DELETE to continue: '
  read -r answer
  [ "$answer" = "DELETE" ] || die "Nothing was removed."
fi

step "Stopping and removing the service"
if [ -f "$UNIT_FILE" ]; then
  systemctl disable --now "$SERVICE" >/dev/null 2>&1 || true
  rm -f "$UNIT_FILE"
  systemctl daemon-reload
fi
rm -rf "$PREFIX" "$PREFIX.prev" "$PREFIX.new" "$PREFIX.failed"
rm -f "$WRAPPER"
log "Removed program files and the service."

if [ "$PURGE" = "1" ]; then
  step "Deleting data and settings"
  rm -rf "$DATA_DIR" "$ETC_DIR"
  if id "$SVC_USER" >/dev/null 2>&1; then userdel "$SVC_USER" >/dev/null 2>&1 || true; fi
  log "Deleted $DATA_DIR, $ETC_DIR and the '$SVC_USER' account."
else
  log ""
  log "Kept: $DATA_DIR (database, certificate, backups) and $ETC_DIR (settings)."
  log "Installing again will reuse them. To delete them too: sudo ./uninstall.sh --purge"
fi
