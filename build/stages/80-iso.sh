#!/usr/bin/env bash
# Stage 80: master the hybrid ISO.
log "Mastering ISO"

ISO=$WORKDIR/iso
OUT="$OUTDIR/${IMAGE_NAME}.iso"
mkdir -p "$OUTDIR"

# UEFI-only image. The Linx 1010B has no CSM and cannot boot in legacy BIOS mode
# at all, so a BIOS El Torito entry would only add a grub-pc-bin build dependency
# for a path this hardware can never take.
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "LINX1010B" \
    -eltorito-alt-boot \
    -e --interval:appended_partition_2:all:: \
    -no-emul-boot \
    -append_partition 2 0xef "$WORKDIR/efi.img" \
    -partition_offset 16 \
    -partition_cyl_align all \
    -output "$OUT" \
    "$ISO"

sha256sum "$OUT" > "$OUT.sha256"
ok "ISO: $OUT ($(du -h "$OUT" | cut -f1))"
ok "SHA256: $(cut -d' ' -f1 < "$OUT.sha256")"
