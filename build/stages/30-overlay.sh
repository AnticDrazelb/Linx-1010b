#!/usr/bin/env bash
# Stage 30: drop the tuning overlay and the linx-* tools into the rootfs.
log "Applying configuration overlay"

rsync -a --chown=root:root "$SRCDIR/overlay/" "$ROOTFS/"

# The maintenance/diagnostic tools.
install -d -m755 "$ROOTFS/usr/local/bin"
for t in "$SRCDIR"/tools/linx-*; do
    [ -f "$t" ] || continue
    install -Dm755 "$t" "$ROOTFS/usr/local/bin/$(basename "$t")"
done
# The installer is carried in the live image so it can be run from the desktop.
install -Dm755 "$SRCDIR/installer/linx-install.sh" "$ROOTFS/usr/local/bin/linx-install"

ok "Overlay applied ($(find "$SRCDIR/overlay" -type f | wc -l) config files, $(ls "$SRCDIR"/tools/linx-* 2>/dev/null | wc -l) tools)"
