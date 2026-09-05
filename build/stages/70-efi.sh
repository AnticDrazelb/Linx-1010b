#!/usr/bin/env bash
# Stage 70: build the EFI boot images.
#
# THIS IS THE STAGE THAT MAKES THE TABLET BOOT AT ALL.
#
# The Linx 1010B has a 64-bit Atom CPU behind a 32-bit UEFI implementation.
# Its firmware looks for \EFI\BOOT\BOOTIA32.EFI and cannot load a 64-bit PE
# binary, so a stock amd64 ISO shows "no bootable device" with no further
# explanation. We therefore build BOTH:
#   BOOTIA32.EFI - i386-efi GRUB, what the tablet actually runs
#   BOOTX64.EFI  - x86_64-efi GRUB, so the same ISO boots normal PCs for testing
#
# A 32-bit GRUB loading a 64-bit kernel is fine: GRUB uses the Linux boot
# protocol and performs the mode switch itself. Only the firmware/bootloader
# handoff is bitness-sensitive.
log "Building EFI bootloaders (ia32 + x64)"

ISO=$WORKDIR/iso
mkdir -p "$ISO/EFI/BOOT" "$ISO/boot/grub"

# Modules the bootloader needs: enough to find the ISO, read squashfs/FAT/ext,
# set a graphics mode and load a Linux kernel.
GRUB_MODULES="
    part_gpt part_msdos fat exfat ext2 iso9660 udf squash4
    normal linux boot configfile loopback chain
    search search_fs_uuid search_fs_file search_label
    efi_gop efi_uga video video_fb gfxterm gfxterm_background gfxmenu all_video
    font terminal loadenv test echo halt reboot minicmd sleep
    ls cat help probe regexp true gzio xzio
"

build_grub() {
    local target=$1 out=$2
    [ -d "/usr/lib/grub/$target" ] || { warn "skipping $target (modules not installed)"; return 1; }
    grub-mkimage \
        --format="$target" \
        --directory="/usr/lib/grub/$target" \
        --prefix="/boot/grub" \
        --output="$out" \
        $GRUB_MODULES
    ok "  $(basename "$out"): $(stat -c%s "$out") bytes ($target)"
}

build_grub i386-efi   "$ISO/EFI/BOOT/BOOTIA32.EFI" || \
    die "Could not build BOOTIA32.EFI - the Linx 1010B cannot boot without it."
build_grub x86_64-efi "$ISO/EFI/BOOT/BOOTX64.EFI" || \
    warn "No BOOTX64.EFI; ISO will boot the tablet but not 64-bit UEFI PCs."

# --- the live boot menu ------------------------------------------------------
cat > "$ISO/boot/grub/grub.cfg" <<'GRUBCFG'
# Live boot menu for the Linx 1010B image.

set default=0
set timeout=5

# Bay Trail firmware gives us a working GOP, so gfxterm is safe and gives a
# readable menu on a 1280x800 panel instead of 80x25 text.
if loadfont /boot/grub/fonts/unicode.pf2 ; then
    set gfxmode=1280x800,auto
    insmod all_video
    insmod gfxterm
    terminal_output gfxterm
fi

# Find the medium we booted from by looking for a file unique to this image,
# rather than trusting a device order that changes between USB controllers.
search --set=root --file /live/filesystem.squashfs

set LINX_CMDLINE="boot=live components quiet loglevel=3 i915.fastboot=1 i915.enable_fbc=1 nmi_watchdog=0"

menuentry "Linx 1010B GNOME (live)" {
    linux  /live/vmlinuz $LINX_CMDLINE
    initrd /live/initrd.img
}

menuentry "Linx 1010B GNOME (live, safe graphics)" {
    linux  /live/vmlinuz boot=live components nomodeset loglevel=3
    initrd /live/initrd.img
}

menuentry "Linx 1010B GNOME (live, C-states limited)" {
    # Use this if the tablet freezes hard at random. Costs battery life; the
    # real fix is current intel-microcode, which this image already installs.
    linux  /live/vmlinuz $LINX_CMDLINE intel_idle.max_cstate=1
    initrd /live/initrd.img
}

menuentry "Linx 1010B GNOME (live, verbose - for bug reports)" {
    linux  /live/vmlinuz boot=live components loglevel=7 ignore_loglevel
    initrd /live/initrd.img
}

menuentry "UEFI firmware settings" {
    fwsetup
}
GRUBCFG

# Ship the unicode font so gfxterm above actually works.
if [ -f /usr/share/grub/unicode.pf2 ]; then
    install -Dm644 /usr/share/grub/unicode.pf2 "$ISO/boot/grub/fonts/unicode.pf2"
fi

# --- the EFI System Partition image ------------------------------------------
# xorriso needs a FAT image to expose as the El Torito EFI boot entry.
log "  packing EFI system partition image"
EFI_IMG=$WORKDIR/efi.img
# Size it from the actual payload plus FAT overhead, rounded up to 64 KiB.
# Size from the payload plus slack, but never below 16 MiB: FAT16 needs at
# least ~4085 clusters to be a valid FAT16 rather than FAT12, and mkfs.vfat
# will refuse or silently produce FAT12 on a ~2 MB image.
need=$(( $(du -sk "$ISO/EFI" | cut -f1) + 2048 ))
[ "$need" -lt 16384 ] && need=16384
rm -f "$EFI_IMG"
mkfs.vfat -C -F 16 -n LINXEFI "$EFI_IMG" "$need" >/dev/null
mmd  -i "$EFI_IMG" ::/EFI ::/EFI/BOOT
for f in "$ISO"/EFI/BOOT/*.EFI; do
    mcopy -i "$EFI_IMG" "$f" "::/EFI/BOOT/$(basename "$f")"
done
ok "EFI images ready ($(du -h "$EFI_IMG" | cut -f1) ESP)"
