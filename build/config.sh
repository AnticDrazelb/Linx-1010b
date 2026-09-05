#!/usr/bin/env bash
# Build configuration. Override any of these from the environment:
#   SUITE=forky ./build/build.sh

# --- Distribution base -------------------------------------------------------
# Debian is used rather than Fedora/Ubuntu because debootstrap --variant=minbase
# plus an explicit package list gives exact control over what ends up in the
# image, which is the whole point of this project. See docs/build.md.
: "${SUITE:=trixie}"                      # Debian 13
: "${MIRROR:=http://deb.debian.org/debian}"
: "${COMPONENTS:=main contrib non-free-firmware}"

# --- Target architecture -----------------------------------------------------
# amd64 userland on a 64-bit CPU, even though the FIRMWARE is 32-bit. Only the
# bootloader needs to be i386. Debian's i386 port no longer ships a usable GNOME
# desktop, and the extra registers of x86-64 are worth more than the slightly
# larger pointers cost on 2 GB. See docs/boot-32bit-uefi.md.
: "${ARCH:=amd64}"

# --- Output ------------------------------------------------------------------
: "${WORKDIR:=$PWD/work}"
: "${ROOTFS:=$WORKDIR/rootfs}"
: "${OUTDIR:=$PWD/out}"
: "${IMAGE_NAME:=linx1010b-gnome-${SUITE}-$(date +%Y%m%d)}"

# --- Image identity ----------------------------------------------------------
: "${HOSTNAME_DEFAULT:=linx1010b}"
: "${LIVE_USER:=linx}"
: "${LIVE_PASS:=linx}"
: "${TIMEZONE:=Europe/London}"
: "${LOCALE:=en_GB.UTF-8}"
: "${KEYMAP:=gb}"

# --- Feature switches --------------------------------------------------------
# If kernel/out/ contains linux-image*.deb (built by kernel/build-kernel.sh),
# stage 20 installs those instead of Debian's linux-image-amd64. This is opt-in
# purely by the presence of the files. See kernel/README.md.
: "${KERNEL_DEB_DIR:=$PWD/kernel/out}"

# Strip documentation, man pages and non-selected locales from the rootfs.
: "${STRIP_DOCS:=1}"

# squashfs compression. zstd -19 makes a smaller image that decompresses FASTER
# than xz on this CPU, which matters because every page read from the live ISO
# (and from a squashfs-backed install) costs a decompression.
: "${SQUASHFS_COMP:=zstd}"
: "${SQUASHFS_LEVEL:=19}"

: "${JOBS:=$(nproc)}"
