#!/usr/bin/env bash
#
# Build the ISO inside a Docker container.
#
# For Windows (Docker Desktop) the equivalent PowerShell commands are in
# docs/build-on-windows.md - this script is the bash version, for WSL, Linux
# and macOS.
#
#   ./docker/build-in-docker.sh              # full build
#   ./docker/build-in-docker.sh 60 70 80     # selected stages

set -euo pipefail

SRCDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=linx1010b-builder
VOLUME=linx1010b-work

command -v docker >/dev/null || { echo "docker not found" >&2; exit 1; }

echo "==> Building the builder image"
docker build -t "$IMAGE" -f "$SRCDIR/docker/Dockerfile" "$SRCDIR"

# A named volume rather than a bind mount, so the rootfs lives on a real Linux
# filesystem even when the host is Windows or macOS.
docker volume create "$VOLUME" >/dev/null

mkdir -p "$SRCDIR/out"

echo "==> Running the build (privileged: the chroot needs /dev, /proc, /sys)"
docker run --rm -it \
    --privileged \
    -v "$SRCDIR":/src:ro \
    -v "$VOLUME":/work \
    -v "$SRCDIR/out":/out \
    "$IMAGE" "$@"

echo
echo "==> ISO written to $SRCDIR/out:"
ls -lh "$SRCDIR/out"/*.iso 2>/dev/null || echo "  (no ISO - check the build output above)"
echo
echo "To reclaim the ~10 GB of intermediate rootfs:  docker volume rm $VOLUME"
