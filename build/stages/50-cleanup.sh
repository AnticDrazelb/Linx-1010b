#!/usr/bin/env bash
# Stage 50: strip the rootfs.
log "Stripping rootfs"

before=$(du -sm "$ROOTFS" | cut -f1)

mount_pseudo "$ROOTFS"
in_chroot "$ROOTFS" apt-get -y autoremove --purge
in_chroot "$ROOTFS" apt-get clean

if [ "$STRIP_DOCS" = "1" ]; then
    log "  removing documentation, man pages and unused locales"
    # Keep licence files: removing them is a licence-compliance problem, and
    # they are small. Everything else under /usr/share/doc goes.
    find "$ROOTFS/usr/share/doc" -mindepth 1 -type f \
        ! -name 'copyright' ! -name 'LICENSE*' -delete 2>/dev/null || true
    find "$ROOTFS/usr/share/doc" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    rm -rf "$ROOTFS/usr/share/man" "$ROOTFS/usr/share/info" \
           "$ROOTFS/usr/share/groff" "$ROOTFS/usr/share/lintian" \
           "$ROOTFS/usr/share/linda" "$ROOTFS/usr/share/doc-base"

    # Locales: keep C, the configured locale, and its language fallback.
    lang=${LOCALE%%.*}; lang_short=${lang%%_*}
    if [ -d "$ROOTFS/usr/share/locale" ]; then
        find "$ROOTFS/usr/share/locale" -mindepth 1 -maxdepth 1 -type d \
            ! -name "$lang" ! -name "$lang_short" ! -name 'C' ! -name 'en*' \
            -exec rm -rf {} + 2>/dev/null || true
    fi
fi

# Firmware for hardware this machine does not have is the single biggest
# remaining chunk. firmware-misc-nonfree and friends install blobs for hundreds
# of devices; keep only the families this tablet can actually use.
log "  pruning firmware for absent hardware"
FW="$ROOTFS/lib/firmware"
if [ -d "$FW" ]; then
    for d in amdgpu radeon nvidia i915/adl* i915/dg* i915/tgl* i915/skl* \
             i915/kbl* i915/cml* i915/icl* i915/jsl* i915/ehl* i915/rkl* \
             mellanox netronome qcom qed liquidio bnx2x cxgb4 dpaa2 \
             ath10k ath11k ath12k mrvl libertas ti-connectivity brcm/brcmfmac43* \
             mediatek intel/ice intel/irdma; do
        rm -rf "${FW:?}/$d" 2>/dev/null || true
    done
fi

# Caches that will be regenerated on first boot.
rm -rf "$ROOTFS"/var/lib/apt/lists/* \
       "$ROOTFS"/var/cache/apt/* \
       "$ROOTFS"/var/tmp/* \
       "$ROOTFS"/tmp/* \
       "$ROOTFS"/root/.bash_history \
       "$ROOTFS"/var/log/*.log \
       "$ROOTFS"/var/log/apt \
       "$ROOTFS"/var/log/journal
mkdir -p "$ROOTFS"/var/lib/apt/lists/partial "$ROOTFS"/var/cache/apt/archives/partial

# Allow services to start normally on the real system.
rm -f "$ROOTFS/usr/sbin/policy-rc.d"

# Zero machine-id so every installed system gets its own.
: > "$ROOTFS/etc/machine-id"
rm -f "$ROOTFS/var/lib/dbus/machine-id"

after=$(du -sm "$ROOTFS" | cut -f1)
ok "Rootfs stripped: ${before}MB -> ${after}MB (saved $((before-after))MB)"
