#!/usr/bin/env bash
#
# Build a stripped GNOME image for the Linx 1010B tablet.
#
# Usage:
#   sudo ./build/build.sh                 # full build
#   sudo ./build/build.sh 60 70 80        # re-run only these stages
#   sudo SUITE=forky ./build/build.sh     # override any config.sh value
#
# The build is staged and resumable: the rootfs in work/ is kept between runs,
# so iterating on the overlay or the package lists does not mean re-bootstrapping.

set -euo pipefail

SRCDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export SRCDIR

# shellcheck source=lib/common.sh
source "$SRCDIR/build/lib/common.sh"
# shellcheck source=config.sh
source "$SRCDIR/build/config.sh"

need_root

# Always unmount the chroot's pseudo-filesystems, however we exit. Leaving
# /proc bind-mounted inside work/rootfs and then running `rm -rf work` is the
# classic way to have a very bad day.
trap 'umount_pseudo' EXIT INT TERM

mkdir -p "$WORKDIR" "$OUTDIR"

ALL_STAGES=(00-deps 10-bootstrap 20-packages 30-overlay 40-tuning 50-cleanup 60-squashfs 70-efi 80-iso 85-usbimg)

# Select stages: either the ones named on the command line (by number prefix)
# or all of them.
if [ $# -gt 0 ]; then
    SELECTED=()
    for want in "$@"; do
        found=0
        for s in "${ALL_STAGES[@]}"; do
            if [ "${s%%-*}" = "$want" ] || [ "$s" = "$want" ]; then
                SELECTED+=("$s"); found=1
            fi
        done
        [ "$found" = 1 ] || die "Unknown stage '$want'. Known: ${ALL_STAGES[*]}"
    done
else
    SELECTED=("${ALL_STAGES[@]}")
fi

started=$(date +%s)
log "Linx 1010B image builder"
log "  suite=$SUITE arch=$ARCH  work=$WORKDIR  out=$OUTDIR"
log "  stages: ${SELECTED[*]}"

for stage in "${SELECTED[@]}"; do
    script="$SRCDIR/build/stages/${stage}.sh"
    [ -f "$script" ] || die "Missing stage script: $script"
    t0=$(date +%s)
    printf '\n'
    log "STAGE $stage"
    # Sourced, not executed, so stages share the config, the helper functions
    # and the MOUNTED array that the EXIT trap depends on.
    # shellcheck disable=SC1090
    source "$script"
    ok "stage $stage finished in $(( $(date +%s) - t0 ))s"
done

printf '\n'
ok "Build complete in $(( $(date +%s) - started ))s"
[ -f "$OUTDIR/${IMAGE_NAME}.iso" ] && ok "Image: $OUTDIR/${IMAGE_NAME}.iso"
cat <<'NEXT'

Next steps:
  1. Write the ISO to a USB stick:
       sudo dd if=out/linx1010b-*.iso of=/dev/sdX bs=4M status=progress conv=fsync
     (or use the exact same file with Rufus in "DD image" mode on Windows)
  2. On the tablet: power off, then hold Volume Up while pressing Power to reach
     the firmware menu, choose Boot Manager, and select the USB device.
  3. Log in as the live user, then run `sudo linx-install` to install to eMMC.

See docs/install.md for the full procedure and docs/troubleshooting.md if the
tablet does not offer the USB stick as a boot option.
NEXT
