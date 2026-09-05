#!/usr/bin/env bash
# Shared helpers for the build stages.

set -euo pipefail

C_RESET=$'\033[0m'; C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'; C_RED=$'\033[1;31m'

log()  { printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*" >&2; }
ok()   { printf '%s -->%s %s\n' "$C_GREEN"  "$C_RESET" "$*" >&2; }
warn() { printf '%s[!]%s %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s[x]%s %s\n'  "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }

need_root() {
    [ "$(id -u)" -eq 0 ] || die "This must run as root (it calls debootstrap and chroot)."
}

# Verify a list of host commands exist, naming the Debian package for each.
require_cmds() {
    local missing=() pair cmd pkg
    for pair in "$@"; do
        cmd=${pair%%:*}; pkg=${pair##*:}
        command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd (apt install $pkg)")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        printf 'Missing host tools:\n' >&2
        printf '  - %s\n' "${missing[@]}" >&2
        die "Install the packages above and re-run."
    fi
}

# --- chroot plumbing ---------------------------------------------------------
# Track what we mounted so the EXIT trap can unmount exactly that, in reverse.
MOUNTED=()

mount_pseudo() {
    local root=$1
    local m
    for m in /dev /dev/pts /proc /sys /run; do
        mkdir -p "$root$m"
        if ! mountpoint -q "$root$m"; then
            mount --rbind "$m" "$root$m"
            mount --make-rslave "$root$m"
            MOUNTED+=("$root$m")
        fi
    done
}

umount_pseudo() {
    local i m
    for (( i=${#MOUNTED[@]}-1; i>=0; i-- )); do
        m=${MOUNTED[i]}
        mountpoint -q "$m" && umount -R -l "$m" || true
    done
    MOUNTED=()
}

# Run a command inside the chroot with a clean, predictable environment.
in_chroot() {
    local root=$1; shift
    LC_ALL=C LANGUAGE=C LANG=C \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    chroot "$root" "$@"
}

# Feed a heredoc script to bash inside the chroot.
chroot_sh() {
    local root=$1
    LC_ALL=C LANGUAGE=C LANG=C \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    chroot "$root" /bin/bash -euo pipefail -s
}

# Verify the build directory's filesystem can actually hold a Linux rootfs.
#
# This exists because of Windows/WSL2: building under /mnt/c (or any other
# DrvFs/9p/NTFS/exFAT mount) appears to work and then produces a subtly broken
# image - debootstrap cannot create device nodes, file ownership silently
# collapses to the mounting user, and a case-insensitive filesystem merges files
# whose names differ only in case. The failure surfaces much later, usually as a
# rootfs that will not boot, so test it up front with real operations rather than
# guessing from the filesystem name.
check_fs_capable() {
    local dir=$1
    local t="$dir/.fscheck.$$"
    mkdir -p "$t"
    # Always clean up, even on the die() paths below.
    trap 'rm -rf "$t" 2>/dev/null || true' RETURN

    local fstype; fstype=$(stat -f -c %T "$dir" 2>/dev/null || echo unknown)
    local hint="
The build directory is on a '$fstype' filesystem.
If you are on Windows/WSL2, you are almost certainly building under /mnt/c.
Move the checkout onto the Linux filesystem instead, e.g:

    cp -r /mnt/c/Users/you/Linx-1010b ~/Linx-1010b && cd ~/Linx-1010b

See docs/build-on-windows.md."

    # 1. Device nodes: debootstrap creates /dev/console, /dev/null and friends.
    mknod "$t/devnode" c 1 3 2>/dev/null || die "Cannot create device nodes in $dir.$hint"

    # 2. Ownership: the rootfs contains files owned by many different uids.
    : > "$t/owned"
    chown 12345:12345 "$t/owned" 2>/dev/null || die "Cannot set file ownership in $dir.$hint"
    [ "$(stat -c '%u:%g' "$t/owned")" = "12345:12345" ] \
        || die "File ownership is not preserved in $dir.$hint"

    # 3. Case sensitivity: a Debian rootfs contains files differing only in case.
    : > "$t/CaseTest"
    if : > "$t/casetest" 2>/dev/null && [ "$(find "$t" -maxdepth 1 -iname 'casetest' | wc -l)" -lt 2 ]; then
        die "The filesystem at $dir is case-insensitive.$hint"
    fi

    # 4. Extended attributes: rsync -X in the installer, and capabilities on
    #    binaries such as ping, are stored as xattrs.
    if command -v setfattr >/dev/null 2>&1; then
        setfattr -n user.linxtest -v 1 "$t/owned" 2>/dev/null \
            || warn "Extended attributes are not supported in $dir; file capabilities (e.g. on ping) will be lost."
    fi
}

# Read a package list file, stripping comments and blank lines.
read_pkg_list() {
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1"
}
