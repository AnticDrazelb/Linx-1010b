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

# Read a package list file, stripping comments and blank lines.
read_pkg_list() {
    sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$1"
}
