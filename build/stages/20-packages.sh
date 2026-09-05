#!/usr/bin/env bash
# Stage 20: install the curated package set.
log "Installing packages"

mount_pseudo "$ROOTFS"

in_chroot "$ROOTFS" apt-get update

# If a custom kernel was built (kernel/build-kernel.sh), prefer it over the
# Debian stock kernel. Opt-in purely by the .debs existing.
CUSTOM_KERNEL_DEBS=()
if compgen -G "$KERNEL_DEB_DIR/linux-image-*.deb" >/dev/null 2>&1; then
    mapfile -t CUSTOM_KERNEL_DEBS < <(ls "$KERNEL_DEB_DIR"/linux-*.deb)
    log "  found ${#CUSTOM_KERNEL_DEBS[@]} custom kernel package(s) in $KERNEL_DEB_DIR"
fi

# Install list by list rather than in one transaction, so a failure names the
# list that caused it instead of dumping 300 packages.
for list in "$SRCDIR"/config/packages/*.list; do
    name=$(basename "$list" .list)
    mapfile -t pkgs < <(read_pkg_list "$list")
    # Drop the stock kernel from the list when a custom one is supplied.
    if [ ${#CUSTOM_KERNEL_DEBS[@]} -gt 0 ]; then
        mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx 'linux-image-amd64' || true)
    fi
    [ ${#pkgs[@]} -gt 0 ] || continue
    log "  package list: $name (${#pkgs[@]} packages)"
    in_chroot "$ROOTFS" apt-get install -y --no-install-recommends "${pkgs[@]}"
done

if [ ${#CUSTOM_KERNEL_DEBS[@]} -gt 0 ]; then
    log "  installing custom kernel packages"
    mkdir -p "$ROOTFS/tmp/kdebs"
    cp "${CUSTOM_KERNEL_DEBS[@]}" "$ROOTFS/tmp/kdebs/"
    in_chroot "$ROOTFS" bash -c 'apt-get install -y --no-install-recommends /tmp/kdebs/*.deb'
    rm -rf "$ROOTFS/tmp/kdebs"
fi

ok "Packages installed: $(in_chroot "$ROOTFS" dpkg-query -f '.\n' -W | wc -l) total"
