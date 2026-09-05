#!/usr/bin/env bash
# Stage 60: compress the rootfs and stage the kernel for the ISO.
log "Building squashfs"

umount_pseudo
mkdir -p "$WORKDIR/iso/live" "$OUTDIR"

# Pull the kernel and initramfs out of the rootfs for the bootloader to load
# directly. Doing this before mksquashfs means they are still inside the image
# too, which is what the installer copies to the eMMC.
kver=$(basename "$(ls -1 "$ROOTFS"/boot/vmlinuz-* | sort -V | tail -1)")
kver=${kver#vmlinuz-}
log "  kernel $kver"
cp "$ROOTFS/boot/vmlinuz-$kver"   "$WORKDIR/iso/live/vmlinuz"
cp "$ROOTFS/boot/initrd.img-$kver" "$WORKDIR/iso/live/initrd.img"
echo "$kver" > "$WORKDIR/kernel-version"

rm -f "$WORKDIR/iso/live/filesystem.squashfs"
# zstd rather than xz: about 8% larger, but decompresses roughly 4x faster.
# On a 1.33 GHz Atom, decompression is on the critical path of every page fault
# against the live filesystem, so this trades a little size for real speed.
mksquashfs "$ROOTFS" "$WORKDIR/iso/live/filesystem.squashfs" \
    -comp "$SQUASHFS_COMP" -Xcompression-level "$SQUASHFS_LEVEL" \
    -b 1M -no-recovery -noappend -wildcards \
    -e "boot/grub" "var/cache/apt/archives/*.deb" \
    -processors "$JOBS"

sz=$(du -h "$WORKDIR/iso/live/filesystem.squashfs" | cut -f1)
ok "squashfs built: $sz"
