#!/usr/bin/env bash
# Stage 00: verify the host has everything needed to build the image.
log "Checking host build dependencies"

require_cmds \
    debootstrap:debootstrap \
    chroot:coreutils \
    mksquashfs:squashfs-tools \
    xorriso:xorriso \
    grub-mkimage:grub-common \
    mkfs.vfat:dosfstools \
    mtools:mtools \
    rsync:rsync \
    mountpoint:util-linux

# The i386-efi GRUB modules must be present on the BUILD host to produce the
# BOOTIA32.EFI that this tablet requires. This is the one dependency people miss,
# and missing it produces an ISO that silently will not boot on the target.
[ -d /usr/lib/grub/i386-efi ] || \
    die "/usr/lib/grub/i386-efi is missing - apt install grub-efi-ia32-bin.
This is required to build the 32-bit EFI bootloader the Linx 1010B needs."

[ -d /usr/lib/grub/x86_64-efi ] || \
    warn "/usr/lib/grub/x86_64-efi missing (apt install grub-efi-amd64-bin).
The ISO will boot the tablet but not ordinary 64-bit UEFI PCs, which makes testing harder."

# Without the Debian archive keyring on the HOST, debootstrap cannot verify the
# Release signature and silently bootstraps from unverified packages - it prints
# one warning and carries on. An OS image is exactly the wrong thing to build out
# of unauthenticated packages, so make this a hard failure.
if [ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ] && [ "${LINX_ALLOW_UNVERIFIED:-0}" != "1" ]; then
    die "/usr/share/keyrings/debian-archive-keyring.gpg is missing.
debootstrap would fall back to an UNVERIFIED bootstrap. Install it with:

    apt install debian-archive-keyring

(Set LINX_ALLOW_UNVERIFIED=1 to override, which you should not do for an image
you intend to actually run.)"
fi
ok "Debian archive keyring present; bootstrap will be signature-verified"

# Verify the build filesystem before anything else writes to it - see
# docs/build-on-windows.md for why this matters on WSL2.
log "Checking that $(dirname "$WORKDIR") can hold a Linux rootfs"
mkdir -p "$WORKDIR"
check_fs_capable "$WORKDIR"
ok "Filesystem supports device nodes, ownership and case-sensitive names"

df_avail=$(df -BG --output=avail "$(dirname "$WORKDIR")" | tail -1 | tr -dc '0-9')
[ "${df_avail:-0}" -ge 12 ] || \
    warn "Only ${df_avail}G free at $(dirname "$WORKDIR"); a full build needs roughly 12G."

ok "Host dependencies satisfied"
