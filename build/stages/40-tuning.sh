#!/usr/bin/env bash
# Stage 40: system configuration and service stripping.
log "Configuring system and stripping services"

mount_pseudo "$ROOTFS"

# --- identity, locale, time --------------------------------------------------
echo "$HOSTNAME_DEFAULT" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" <<HOSTS
127.0.0.1	localhost
127.0.1.1	$HOSTNAME_DEFAULT
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
HOSTS

chroot_sh "$ROOTFS" <<CHROOT
# Generate only the locale we actually use. Every extra locale is disk and a
# slower locale-archive lookup.
sed -i 's/^# *\(${LOCALE} UTF-8\)/\1/' /etc/locale.gen
locale-gen
update-locale LANG=${LOCALE} LC_ALL=

ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
echo "${TIMEZONE}" > /etc/timezone

# Console keymap.
sed -i 's/^XKBLAYOUT=.*/XKBLAYOUT="${KEYMAP}"/' /etc/default/keyboard || true
CHROOT

# --- live user ---------------------------------------------------------------
chroot_sh "$ROOTFS" <<CHROOT
if ! id -u "${LIVE_USER}" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev,input "${LIVE_USER}"
    echo "${LIVE_USER}:${LIVE_PASS}" | chpasswd
fi
# Root login stays disabled; sudo is the way in.
passwd -l root || true
CHROOT

# --- service stripping -------------------------------------------------------
# Each of these is a daemon that would otherwise sit resident in 2 GB of RAM or
# wake the CPU on a timer. Masked rather than disabled so a package update
# cannot silently re-enable them.
log "  masking unnecessary system services"
MASK_SYSTEM=(
    # No cellular modem in this tablet.
    ModemManager.service
    # mDNS/DNS-SD. Costs a resident daemon and periodic multicast wakeups.
    # Mask breaks zero-config discovery of network printers - see docs/performance.md.
    avahi-daemon.service
    avahi-daemon.socket
    # Printing off by default; cups is installed so `linx-tune printing-on` is instant.
    cups.service
    cups-browsed.service
    cups.socket
    # PackageKit is GNOME Software's backend. It is a large resident daemon that
    # wakes to refresh metadata; on a 32 GB eMMC and this CPU it is a real tax.
    packagekit.service
    packagekit-offline-update.service
    # Background apt work: multi-megabyte downloads and a CPU spike on a timer.
    apt-daily.timer
    apt-daily-upgrade.timer
    apt-daily.service
    apt-daily-upgrade.service
    # Rebuilding the man page index on a slow eMMC, for man pages we strip anyway.
    man-db.timer
    # Adds seconds of boot delay waiting for a network we do not need to boot.
    NetworkManager-wait-online.service
    systemd-networkd-wait-online.service
    # Single-GPU machine.
    switcheroo-control.service
    # Colour management for a fixed, uncalibrated tablet panel.
    colord.service
    # Not a remote-desktop host.
    gnome-remote-desktop.service
    # Filesystem checks that thrash a flash device.
    e2scrub_all.timer
    e2scrub_all.service
    # Location services; nothing in this image uses them by default.
    geoclue.service
)
for u in "${MASK_SYSTEM[@]}"; do
    in_chroot "$ROOTFS" systemctl mask "$u" >/dev/null 2>&1 || true
done

# User-session services, masked globally so they never start for any user.
log "  masking unnecessary user services"
MASK_USER=(
    # Tracker: full-text indexing of the home directory. Sustained CPU and
    # sustained writes to a wear-limited eMMC. The dconf settings already tell
    # it to index nothing; masking makes sure it never even starts.
    tracker-miner-fs-3.service
    tracker-extract-3.service
    tracker-miner-rss-3.service
    tracker-writeback-3.service
    tracker-miner-fs-control-3.service
    # Text-to-speech we do not ship a voice for.
    speech-dispatcher.service
    speech-dispatcherd.service
)
for u in "${MASK_USER[@]}"; do
    in_chroot "$ROOTFS" systemctl --global mask "$u" >/dev/null 2>&1 || true
done

# --- services we DO want -----------------------------------------------------
log "  enabling wanted services"
ENABLE=(
    gdm3.service
    NetworkManager.service
    bluetooth.service
    systemd-timesyncd.service
    systemd-resolved.service
    # Periodic TRIM. This is the correct way to trim flash: a weekly batch,
    # rather than the `discard` mount option, which makes every delete slow.
    fstrim.timer
)
for u in "${ENABLE[@]}"; do
    in_chroot "$ROOTFS" systemctl enable "$u" >/dev/null 2>&1 || warn "could not enable $u"
done
in_chroot "$ROOTFS" systemctl set-default graphical.target >/dev/null 2>&1 || true

# --- GNOME defaults ----------------------------------------------------------
log "  compiling dconf defaults"
in_chroot "$ROOTFS" dconf update

# --- initramfs ---------------------------------------------------------------
# MODULES=dep would be smaller and faster, but it bakes in the build host's
# hardware. This image must boot one specific machine plus arbitrary USB
# controllers on the install media, so keep the generic set.
log "  rebuilding initramfs (this pulls in pwm_lpss for backlight control)"
in_chroot "$ROOTFS" update-initramfs -u -k all

ok "System configured"
