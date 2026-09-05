#!/usr/bin/env bash
#
# linx-install - install the running live system onto the Linx 1010B's eMMC.
#
# This is deliberately a simple, whole-disk installer. It ERASES the target
# device. If you want to dual-boot with the existing Windows install, do NOT use
# this - follow the manual procedure in docs/install.md instead, which resizes
# the Windows partition and reuses the existing ESP.

set -euo pipefail

C_R=$'\033[1;31m'; C_G=$'\033[1;32m'; C_Y=$'\033[1;33m'; C_B=$'\033[1;34m'; C_0=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
ok()   { printf '%s -->%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$*"; }
die()  { printf '%s[x]%s %s\n' "$C_R" "$C_0" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root: sudo linx-install"

ESP_SIZE=${ESP_SIZE:-512MiB}
TARGET=${1:-}
MNT=/mnt/linx-install

# --- pick the target ---------------------------------------------------------
list_targets() {
    # Internal eMMC is non-removable; the microSD slot and USB sticks are not.
    for d in /sys/block/mmcblk*; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        # Skip the eMMC boot hardware partitions (mmcblk0boot0 etc).
        case "$name" in *boot*|*rpmb*) continue ;; esac
        removable=$(cat "$d/removable" 2>/dev/null || echo 0)
        size=$(( $(cat "$d/size") * 512 / 1024 / 1024 / 1024 ))
        kind="eMMC (internal)"; [ "$removable" = "1" ] && kind="removable card"
        printf '  /dev/%-12s %4dG  %s\n' "$name" "$size" "$kind"
    done
}

if [ -z "$TARGET" ]; then
    log "Available storage devices:"
    list_targets
    echo
    # Prefer the non-removable eMMC as the suggestion.
    for d in /sys/block/mmcblk*; do
        case "$(basename "$d")" in *boot*|*rpmb*) continue ;; esac
        if [ "$(cat "$d/removable" 2>/dev/null || echo 0)" = "0" ]; then
            TARGET=/dev/$(basename "$d"); break
        fi
    done
    [ -n "$TARGET" ] || die "Could not identify the internal eMMC. Pass it explicitly: linx-install /dev/mmcblkN"
    warn "Suggested target: $TARGET"
fi

[ -b "$TARGET" ] || die "$TARGET is not a block device"

# Refuse to install onto the device we are running from.
live_src=$(findmnt -n -o SOURCE / 2>/dev/null || true)
if [ -n "$live_src" ] && [[ "$live_src" == "$TARGET"* ]]; then
    die "$TARGET appears to be the live medium you booted from."
fi

# --- confirm -----------------------------------------------------------------
size_g=$(( $(blockdev --getsize64 "$TARGET") / 1024 / 1024 / 1024 ))
cat <<CONFIRM

${C_R}================= THIS WILL ERASE EVERYTHING =================${C_0}

  Target : $TARGET  (${size_g} GB)
  Layout : GPT
             ${TARGET}p1  ${ESP_SIZE}  FAT32  EFI System Partition
             ${TARGET}p2  rest       ext4   /

  Every existing partition on $TARGET, including any Windows
  installation and its recovery partition, will be destroyed.

CONFIRM
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTLABEL "$TARGET" 2>/dev/null || true
echo
printf 'Type the device name (%s) to confirm, anything else to abort: ' "$TARGET"
read -r reply
[ "$reply" = "$TARGET" ] || die "Aborted - nothing was written."

# --- partition ---------------------------------------------------------------
log "Partitioning $TARGET"
umount -R "$MNT" 2>/dev/null || true
for p in "$TARGET"p* "$TARGET"[0-9]*; do [ -b "$p" ] && umount "$p" 2>/dev/null || true; done
swapoff -a 2>/dev/null || true

wipefs -a "$TARGET"
sgdisk --zap-all "$TARGET" >/dev/null
sgdisk \
    --new=1:0:+"$ESP_SIZE" --typecode=1:ef00 --change-name=1:"EFI System" \
    --new=2:0:0           --typecode=2:8300 --change-name=2:"linxroot" \
    "$TARGET" >/dev/null
partprobe "$TARGET"; udevadm settle; sleep 2

# mmcblk devices use a 'p' separator; be tolerant anyway.
if [ -b "${TARGET}p1" ]; then ESP=${TARGET}p1; ROOT=${TARGET}p2
else                          ESP=${TARGET}1;  ROOT=${TARGET}2; fi
[ -b "$ESP" ] && [ -b "$ROOT" ] || die "Partitions did not appear after partprobe"

# --- filesystems -------------------------------------------------------------
log "Creating filesystems"
mkfs.vfat -F 32 -n LINXEFI "$ESP" >/dev/null
# ext4 rather than f2fs: GRUB reads it reliably, e2fsck is dependable, and with
# noatime + a weekly fstrim the write amplification difference on eMMC is small.
# ^has_journal is NOT disabled - losing the journal on a tablet that will be
# hard-powered-off is a bad trade for a few percent of write throughput.
mkfs.ext4 -q -L linxroot -O ^64bit -E lazy_itable_init=0,lazy_journal_init=0 "$ROOT"

mkdir -p "$MNT"
mount "$ROOT" "$MNT"
mkdir -p "$MNT/boot/efi"
mount "$ESP" "$MNT/boot/efi"

# --- copy the system ---------------------------------------------------------
log "Copying system to $ROOT (this takes 10-20 minutes on eMMC)"
rsync -aHAXx --info=progress2 \
    --exclude=/dev/\* --exclude=/proc/\* --exclude=/sys/\* \
    --exclude=/tmp/\* --exclude=/run/\* --exclude=/mnt/\* \
    --exclude=/media/\* --exclude=/lost+found \
    --exclude=/var/log/\* --exclude=/swapfile \
    / "$MNT/"

mkdir -p "$MNT"/{dev,proc,sys,tmp,run,mnt,media}
chmod 1777 "$MNT/tmp"

# --- fstab -------------------------------------------------------------------
log "Writing fstab"
ROOT_UUID=$(blkid -s UUID -o value "$ROOT")
ESP_UUID=$(blkid -s UUID -o value "$ESP")
cat > "$MNT/etc/fstab" <<FSTAB
# /etc/fstab for the Linx 1010B
#
# noatime: every read would otherwise cause a metadata write. On a slow,
# wear-limited eMMC that is pure loss.
# commit=60: batch journal commits instead of every 5s, which cuts the number
# of small synchronous writes considerably. The cost is up to 60s of work lost
# on an unclean shutdown.
# No 'discard': continuous TRIM makes deletes slow on this controller.
# fstrim.timer runs a weekly batch TRIM instead, which is enabled in this image.
UUID=$ROOT_UUID  /          ext4  defaults,noatime,commit=60,errors=remount-ro  0 1
UUID=$ESP_UUID   /boot/efi  vfat  umask=0077,noatime,shortname=mixed            0 2

# Keep build/browser scratch off the eMMC entirely.
tmpfs            /tmp       tmpfs rw,nosuid,nodev,size=512M,mode=1777           0 0
FSTAB

# --- bootloader: the part that matters ---------------------------------------
log "Installing the 32-bit EFI bootloader"
for m in dev dev/pts proc sys run; do
    mount --rbind "/$m" "$MNT/$m"; mount --make-rslave "$MNT/$m"
done

chroot "$MNT" /bin/bash -euo pipefail <<'CHROOT'
# The Linx 1010B's firmware is 32-bit UEFI. It can only load a 32-bit PE
# binary, so we install grub for i386-efi even though the kernel and the whole
# userland are 64-bit.
#
# --removable puts GRUB at \EFI\BOOT\BOOTIA32.EFI, the fallback path every UEFI
# implementation checks. These tablets frequently lose or ignore NVRAM boot
# entries after a firmware reset or a flat battery, so relying on efibootmgr
# alone leaves you with an unbootable machine. Install to both.
grub-install --target=i386-efi --efi-directory=/boot/efi \
             --bootloader-id=linx --recheck --removable

grub-install --target=i386-efi --efi-directory=/boot/efi \
             --bootloader-id=linx --recheck || \
    echo "NVRAM entry could not be created; the removable path above will still boot."

update-grub
update-initramfs -u -k all
CHROOT

# --- first-boot cleanup ------------------------------------------------------
log "Removing live-only components"
chroot "$MNT" /bin/bash -euo pipefail <<'CHROOT'
apt-get -y purge live-boot live-config live-config-systemd >/dev/null 2>&1 || true
apt-get -y autoremove --purge >/dev/null 2>&1 || true
# A fresh machine-id per install.
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup >/dev/null 2>&1 || true
CHROOT

# --- set up the real user ----------------------------------------------------
echo
log "Create your user account"
printf 'Username [linx]: '; read -r NEWUSER; NEWUSER=${NEWUSER:-linx}
printf 'Hostname [linx1010b]: '; read -r NEWHOST; NEWHOST=${NEWHOST:-linx1010b}

echo "$NEWHOST" > "$MNT/etc/hostname"
sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$NEWHOST/" "$MNT/etc/hosts"

chroot "$MNT" /bin/bash -euo pipefail <<CHROOT
if ! id -u "$NEWUSER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G sudo,audio,video,netdev,plugdev,input "$NEWUSER"
fi
CHROOT
until chroot "$MNT" passwd "$NEWUSER"; do warn "Try again."; done

# The live image ships a well-known account (user "linx", password "linx", in
# the sudo group). Leaving it on an installed system would be a trivially
# exploitable back door, so remove it unless it IS the account just set up.
LIVE_ACCOUNT=linx
if [ "$NEWUSER" != "$LIVE_ACCOUNT" ] && chroot "$MNT" id -u "$LIVE_ACCOUNT" >/dev/null 2>&1; then
    log "Removing the live image's default '$LIVE_ACCOUNT' account"
    chroot "$MNT" userdel -r "$LIVE_ACCOUNT" >/dev/null 2>&1 || \
        warn "Could not remove '$LIVE_ACCOUNT' - do it by hand: sudo userdel -r $LIVE_ACCOUNT"
fi

# --- finish ------------------------------------------------------------------
sync
umount -R "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/run" 2>/dev/null || true
umount -R "$MNT" 2>/dev/null || true

cat <<'DONE'

Installation complete.

  Remove the USB stick and reboot.

  If the tablet boots straight back into the firmware menu, choose Boot Manager
  and pick the internal eMMC entry once - some units need to be told the first
  time. If it still will not boot, see docs/troubleshooting.md; the fallback
  path \EFI\BOOT\BOOTIA32.EFI is installed, which every UEFI must honour.

  After first boot, run:
      linx-gpe-scan        find an ACPI interrupt storm eating a CPU core
      linx-report          full hardware status
      linx-tune            performance / compatibility switches
DONE
