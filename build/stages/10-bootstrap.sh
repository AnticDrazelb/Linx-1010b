#!/usr/bin/env bash
# Stage 10: create the minimal Debian root filesystem.
log "Bootstrapping Debian $SUITE ($ARCH) into $ROOTFS"

if [ -d "$ROOTFS/usr/bin" ]; then
    ok "rootfs already bootstrapped, skipping (rm -rf $ROOTFS to force)"
else
    mkdir -p "$ROOTFS"
    # --variant=minbase gives us essential+required only: no editor, no cron,
    # no mail transport, no recommends. Everything else is explicit.
    debootstrap \
        --arch="$ARCH" \
        --variant=minbase \
        --components="$(echo "$COMPONENTS" | tr ' ' ',')" \
        --include=apt-transport-https,ca-certificates \
        "$SUITE" "$ROOTFS" "$MIRROR"
    ok "Bootstrap complete: $(du -sh "$ROOTFS" | cut -f1)"
fi

log "Writing apt sources"
# Debian 13 uses the deb822 sources format.
mkdir -p "$ROOTFS/etc/apt/sources.list.d"
: > "$ROOTFS/etc/apt/sources.list"
cat > "$ROOTFS/etc/apt/sources.list.d/debian.sources" <<SOURCES
Types: deb
URIs: $MIRROR
Suites: $SUITE $SUITE-updates
Components: $COMPONENTS
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security
Suites: $SUITE-security
Components: $COMPONENTS
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SOURCES

# Apply the apt policy (no recommends, no translations) BEFORE the first
# apt install, or the very first transaction pulls in hundreds of MB we then
# have to remove again.
install -Dm644 "$SRCDIR/overlay/etc/apt/apt.conf.d/99-linx" \
    "$ROOTFS/etc/apt/apt.conf.d/99-linx"

# Keep services from being started by the package manager inside the chroot.
cat > "$ROOTFS/usr/sbin/policy-rc.d" <<'POLICY'
#!/bin/sh
exit 101
POLICY
chmod +x "$ROOTFS/usr/sbin/policy-rc.d"

ok "Sources and apt policy in place"
