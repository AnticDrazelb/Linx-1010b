#!/usr/bin/env bash
#
# Build a stripped kernel for the Linx 1010B as Debian packages.
#
# This is OPTIONAL. The stock Debian linux-image-amd64 works correctly on this
# tablet; a custom kernel buys a smaller image, fewer modules to probe at boot,
# and a slightly smaller resident footprint. Expect 30-60 minutes on a decent
# desktop and rather longer on anything slow.
#
# Output: kernel/out/*.deb, which build/stages/20-packages.sh picks up
# automatically on the next image build.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SRC=${SRC:-$HERE/linux}
OUT=$HERE/out
JOBS=${JOBS:-$(nproc)}
KVER=${KVER:-}   # e.g. 6.12.48; empty means "latest stable tag in the clone"

command -v git >/dev/null || { echo "git required" >&2; exit 1; }
for p in build-essential bc kmod cpio flex bison libssl-dev libelf-dev dwarves rsync debhelper; do
    dpkg -s "$p" >/dev/null 2>&1 || { echo "Missing build dependency: $p"; MISSING=1; }
done
[ "${MISSING:-0}" = 0 ] || {
    echo
    echo "Install them with:"
    echo "  sudo apt install build-essential bc kmod cpio flex bison libssl-dev libelf-dev dwarves rsync debhelper"
    exit 1
}

mkdir -p "$OUT"

if [ ! -d "$SRC" ]; then
    echo "==> Cloning the stable kernel tree (this is a large download)"
    git clone --depth 1 --branch "${KVER:+v$KVER}" \
        https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$SRC" \
        || git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git "$SRC"
fi

cd "$SRC"

echo "==> Seeding config from the running Debian kernel"
if [ -f /boot/config-"$(uname -r)" ]; then
    cp /boot/config-"$(uname -r)" .config
else
    make x86_64_defconfig
fi

echo "==> Merging the Linx 1010B fragment"
# merge_config.sh reports any option the fragment asks for that the merge could
# not satisfy, which is the signal that the fragment needs updating for a newer
# kernel. Do not ignore that output.
./scripts/kconfig/merge_config.sh -m .config "$HERE/linx1010b.fragment"
make olddefconfig

echo "==> Verifying the options that actually matter for this tablet"
fail=0
for opt in CONFIG_MMC_SDHCI_ACPI CONFIG_TOUCHSCREEN_GOODIX CONFIG_PWM_LPSS_PLATFORM \
           CONFIG_DRM_I915 CONFIG_SND_SST_ATOM_HIFI2_PLATFORM_ACPI CONFIG_EFI_MIXED \
           CONFIG_ZRAM CONFIG_AXP288_FUEL_GAUGE; do
    if ! grep -qE "^${opt}=(y|m)" .config; then
        echo "  MISSING: $opt - the resulting kernel may not boot or may lose hardware"
        fail=1
    fi
done
[ "$fail" = 0 ] && echo "  all critical options present"

echo "==> Building ($JOBS jobs)"
# Debian's own kernel signing/debug packages are not wanted here.
make -j"$JOBS" bindeb-pkg \
    LOCALVERSION=-linx1010b \
    KDEB_PKGVERSION="$(make kernelversion)-1linx"

mv -f ../linux-*.deb "$OUT"/ 2>/dev/null || true
echo
echo "==> Done. Packages in $OUT:"
ls -la "$OUT"
echo
echo "The next run of build/build.sh will install these instead of linux-image-amd64."
