# Build environment for the Linx 1010B image.
#
# Exists mainly for Windows and macOS, where there is no native debootstrap.
# On Windows this runs under Docker Desktop's WSL2 backend, which provides the
# real Linux kernel that debootstrap and chroot require.
#
# The container must run --privileged: the build bind-mounts /dev, /proc and
# /sys into the chroot. It does NOT need loop devices - the EFI system partition
# is assembled with mtools rather than by mounting an image.

FROM debian:trixie-slim

# Match the host tool list in build/stages/00-deps.sh.
RUN apt-get update && apt-get install -y --no-install-recommends \
        debootstrap \
        squashfs-tools \
        xorriso \
        mtools \
        dosfstools \
        rsync \
        grub-common \
        grub-efi-ia32-bin \
        grub-efi-amd64-bin \
        ca-certificates \
        attr \
        util-linux \
        coreutils \
        procps \
        file \
    && rm -rf /var/lib/apt/lists/*

# /src  - the repository, bind-mounted read-only from the host
# /work - the rootfs under construction. MUST be a Docker volume, never a
#         Windows bind mount: a rootfs cannot live on DrvFs/NTFS (no device
#         nodes, no ownership, case-insensitive). build/stages/00-deps.sh
#         checks this and refuses to continue if it is wrong.
# /out  - finished ISO. A plain file, so a Windows bind mount is fine here.
ENV WORKDIR=/work \
    OUTDIR=/out \
    KERNEL_DEB_DIR=/src/kernel/out

VOLUME /work
WORKDIR /src

ENTRYPOINT ["/src/build/build.sh"]
