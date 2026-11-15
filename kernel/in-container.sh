#!/bin/bash
# Builds the JARVIS kernel as Debian packages. Runs INSIDE debian:trixie.
#   /src = the repository (read only), /out = where the .deb files go.
#
# 1. picks the newest 6.12 long-term kernel from kernel.org (or $KERNEL_VERSION),
# 2. verifies the source: the signed sha256sums.asc (kernel.org's maintainers' keys)
#    and then the tarball's hash against it,
# 3. configures it (x86_64_defconfig + kernel/jarvis.config), checks every option in
#    kernel/required.txt really ended up set, and reports options that were dropped,
# 4. builds linux-image, linux-headers and linux-libc-dev packages.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

note() { printf '::notice title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"; }
warn() { printf '::warning title=%s::%s\n' "$1" "$(printf '%s' "$2" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"; }

apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential bc bison flex libssl-dev libelf-dev libncurses-dev rsync kmod cpio \
  debhelper dpkg-dev fakeroot curl ca-certificates gnupg xz-utils zstd jq python3 > /tmp/apt.log 2>&1 \
  || { warn "kernel build: apt failed" "$(tail -n 8 /tmp/apt.log)"; exit 1; }

WORK=/tmp/kbuild
mkdir -p "$WORK" /out
cd "$WORK"

VER="${KERNEL_VERSION:-}"
if [ -z "$VER" ]; then
  VER=$(curl -fsSL --retry 3 https://www.kernel.org/releases.json \
    | jq -r '[.releases[] | select(.moniker == "longterm" and (.version | startswith("6.12.")))][0].version')
fi
[[ "$VER" =~ ^6\.12\.[0-9]+$ ]] || { warn "kernel build" "could not determine a 6.12 kernel version (got '$VER')"; exit 1; }
BASE=https://cdn.kernel.org/pub/linux/kernel/v6.x
curl -fsSLO --retry 3 "$BASE/linux-$VER.tar.xz"
curl -fsSLO --retry 3 "$BASE/sha256sums.asc"

# ---- verify the source ---------------------------------------------------------------------
export GNUPGHOME
GNUPGHOME=$(mktemp -d)
SIG="NOT verified"
if gpg --batch --quiet --auto-key-locate wkd --locate-keys torvalds@kernel.org gregkh@kernel.org > gpg-keys.log 2>&1 \
  && gpg --batch --verify sha256sums.asc > gpg-verify.log 2>&1; then
  SIG="verified: $(grep -m1 'Good signature' gpg-verify.log | sed 's/^gpg: //')"
fi
if [ "$SIG" = "NOT verified" ] && [ "${ALLOW_UNVERIFIED:-0}" != 1 ]; then
  warn "kernel source signature could not be verified" "$(tail -n 6 gpg-keys.log; tail -n 6 gpg-verify.log 2> /dev/null)"
  exit 1
fi
grep "  linux-$VER.tar.xz\$" sha256sums.asc > want.sha
[ -s want.sha ] || { warn "kernel build" "linux-$VER.tar.xz is not in sha256sums.asc"; exit 1; }
sha256sum -c want.sha
note "kernel source" "linux-$VER.tar.xz sha256 $(cut -d' ' -f1 want.sha); sums file signature $SIG"

tar -xf "linux-$VER.tar.xz"
cd "linux-$VER"

# ---- configure -----------------------------------------------------------------------------
make x86_64_defconfig > /dev/null
scripts/kconfig/merge_config.sh -m .config /src/kernel/jarvis.config > "$WORK/merge.log" 2>&1
make olddefconfig > /dev/null

missing=""
while read -r opt; do
  [ -n "$opt" ] || continue
  grep -qx "$opt" .config || missing="$missing $opt"
done < /src/kernel/required.txt
# Options the fragment asked for that the dependency resolution dropped or changed.
dropped=$(grep -E '^CONFIG_[A-Z0-9_]+=[ym]$|^CONFIG_[A-Z0-9_]+=y$' /src/kernel/jarvis.config | while read -r want; do
  grep -qx "$want" .config || echo "$want"
done | head -n 40 || true)
note "kernel configuration" "version $VER; options asked for but not set after dependency resolution (not necessarily a problem): ${dropped:-none}"
if [ -n "$missing" ]; then
  warn "kernel configuration: REQUIRED options are missing" "$missing"
  exit 1
fi
make -s kernelrelease > "$WORK/release.txt"
REL=$(cat "$WORK/release.txt")
case "$REL" in *-jarvis-amd64) ;; *) warn "kernel build" "unexpected release '$REL' (must end in -jarvis-amd64)"; exit 1 ;; esac

# ---- build the packages --------------------------------------------------------------------
export KBUILD_BUILD_USER=jarvis KBUILD_BUILD_HOST=jarvis
START=$(date +%s)
make -j"$(nproc)" bindeb-pkg DPKG_FLAGS=-d KDEB_PKGVERSION="$VER-1" > "$WORK/build.log" 2>&1 || {
  warn "kernel build FAILED" "$(tail -n 25 "$WORK/build.log")"
  exit 1
}
MIN=$(( ($(date +%s) - START) / 60 ))

cp ../*.deb /out/
{
  echo "kernel $REL built in $MIN minutes"
  ls -l /out/*.deb | awk '{printf "%s  %.1f MB\n", $9, $5 / 1048576}'
  echo "modules in the image package: $(dpkg-deb -c /out/linux-image-"$REL"_*.deb | grep -c '\.ko'  || true)"
} > "$WORK/summary.txt"
note "kernel packages" "$(cat "$WORK/summary.txt")"
echo "$REL" > /out/RELEASE
echo "RESULT: PASS"
