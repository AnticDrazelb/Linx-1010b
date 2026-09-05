#!/usr/bin/env bash
# Stage 85: build a single-partition FAT32 USB image.
#
# WHY THIS EXISTS, instead of just shipping the hybrid ISO:
#
# The ISO puts the kernel, initrd and squashfs on an ISO9660 filesystem covering
# the whole disk, and only the .EFI binaries on a small FAT EFI System Partition.
# That is the conventional layout and it works on most firmware - but it depends
# on GRUB being able to read a filesystem OTHER than the one it was loaded from.
#
# On the Linx 1010B it cannot. GRUB starts fine from BOOTIA32.EFI, then
#   search --no-floppy --set-root --file /boot/grub/grub.cfg
# returns "error: no such device": the ISO9660 filesystem is not reachable at
# all, so /live/vmlinuz can never be loaded and you are stuck at a grub> prompt.
#
# This image removes the dependency entirely. ONE FAT32 partition holds the EFI
# binaries, GRUB's config AND the live filesystem, so GRUB only ever touches the
# partition the firmware already handed it. There is no second filesystem to find.
log "Building single-partition FAT32 USB image"

ISO=$WORKDIR/iso
IMG="$OUTDIR/${IMAGE_NAME}-usb.img"
STAGE=$WORKDIR/usbimg
rm -rf "$STAGE"; mkdir -p "$STAGE" "$OUTDIR"

# Size: payload + 2% + 24 MB. FAT32 overhead at this scale is small (two FAT
# copies of well under 2 MB), and per-file cluster slack is negligible for seven
# files. Every 29 MB of waste here is another chunk for anyone transferring the
# image, so do not be generous.
payload_k=$(du -sk "$ISO" | cut -f1)
size_m=$(( (payload_k * 102 / 100 / 1024) + 24 ))
log "  payload $(( payload_k / 1024 ))MB -> image ${size_m}MB"

part_start=2048                                   # 1 MiB alignment
part_sectors=$(( (size_m * 1024 * 1024 / 512) - part_start ))

rm -f "$IMG"
truncate -s "${size_m}M" "$IMG"

# MBR with a single EFI System Partition. This firmware demonstrably boots an
# MBR 0xef partition - that is how it found BOOTIA32.EFI on the hybrid ISO.
sfdisk "$IMG" >/dev/null <<SFD
label: dos
start=$part_start, size=$part_sectors, type=ef, bootable
SFD

# Build the filesystem separately, then place it, so no loop device is needed.
FSIMG=$WORKDIR/usbfs.img
rm -f "$FSIMG"
truncate -s "$(( part_sectors * 512 ))" "$FSIMG"
mkfs.vfat -F 32 -n LINXLIVE "$FSIMG" >/dev/null

log "  copying payload into the filesystem"
mmd -i "$FSIMG" ::/EFI ::/EFI/BOOT ::/boot ::/boot/grub ::/boot/grub/fonts ::/live ::/.disk
for f in "$ISO"/EFI/BOOT/*.EFI; do
    mcopy -i "$FSIMG" "$f" "::/EFI/BOOT/$(basename "$f")"
done
mcopy -i "$FSIMG" "$ISO/.disk/linx1010b.id"            ::/.disk/
[ -f "$ISO/boot/grub/fonts/unicode.pf2" ] && \
    mcopy -i "$FSIMG" "$ISO/boot/grub/fonts/unicode.pf2" ::/boot/grub/fonts/
mcopy -i "$FSIMG" "$ISO/live/vmlinuz"                  ::/live/
mcopy -i "$FSIMG" "$ISO/live/initrd.img"               ::/live/
mcopy -i "$FSIMG" "$ISO/live/filesystem.squashfs"      ::/live/

# The menu for this layout. NO search command: $root is already the partition
# GRUB was loaded from, and everything lives on it.
#
# This is not just simplification. On the Linx 1010B the search command fails
# outright - "error: no such device" - even for files GRUB can demonstrably read
# via an explicit device name:
#
#     grub> search --no-floppy --set=root --file /boot/grub/grub.cfg
#     error: no such device: /boot/grub/grub.cfg
#     grub> ls (hd0)/live/
#     filesystem.squashfs  initrd.img  vmlinuz          <- same medium, readable
#
# So device enumeration for search is broken on this firmware while direct
# access works. Any layout that depends on search finding the medium is
# unreliable here; addressing everything relative to $root is not.
cat > "$WORKDIR/usb-grub.cfg" <<'GRUBCFG'
set default=0
set timeout=5

# Deliberately NOT switching to gfxterm. On this panel a graphical terminal can
# come up blank, and a menu you cannot see is worse than a plain text one.
terminal_output console

set LINX_CMDLINE="boot=live components quiet loglevel=3 i915.fastboot=1 i915.enable_fbc=1 nmi_watchdog=0"

menuentry "Linx 1010B GNOME (live)" {
    linux  ($root)/live/vmlinuz $LINX_CMDLINE
    initrd ($root)/live/initrd.img
}
menuentry "Linx 1010B GNOME (live, safe graphics)" {
    linux  ($root)/live/vmlinuz boot=live components nomodeset loglevel=3
    initrd ($root)/live/initrd.img
}
menuentry "Linx 1010B GNOME (live, C-states limited)" {
    linux  ($root)/live/vmlinuz $LINX_CMDLINE intel_idle.max_cstate=1
    initrd ($root)/live/initrd.img
}
menuentry "Linx 1010B GNOME (live, verbose)" {
    linux  ($root)/live/vmlinuz boot=live components loglevel=7 ignore_loglevel
    initrd ($root)/live/initrd.img
}
menuentry "UEFI firmware settings" { fwsetup }
GRUBCFG
mcopy -i "$FSIMG" "$WORKDIR/usb-grub.cfg" ::/boot/grub/grub.cfg

dd if="$FSIMG" of="$IMG" bs=512 seek="$part_start" conv=notrunc status=none
rm -f "$FSIMG"

sha256sum "$IMG" > "$IMG.sha256"
ok "USB image: $IMG ($(du -h "$IMG" | cut -f1))"
ok "SHA256: $(cut -d' ' -f1 < "$IMG.sha256")"
