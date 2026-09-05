#!/usr/bin/env bash
#
# Boot the built ISO under 32-bit UEFI firmware in QEMU.
#
# This reproduces the Linx 1010B's defining constraint - IA32 UEFI firmware in
# front of a 64-bit CPU - so it verifies the one thing most likely to be wrong:
# that BOOTIA32.EFI is present, is a valid 32-bit PE, and can load and start a
# 64-bit kernel. Booting this successfully means the tablet should boot too.
#
#   ./tools/test-boot-qemu.sh out/linx1010b-*.iso [seconds]
#
# Screenshots are written to /tmp/linxboot/*.png.

set -euo pipefail

ISO=${1:-}
RUNTIME=${2:-180}
OUT=${OUT:-/tmp/linxboot}
MEM=${MEM:-2048}          # match the tablet's 2 GB

[ -n "$ISO" ] && [ -f "$ISO" ] || { echo "usage: $0 <iso> [seconds]" >&2; exit 1; }

# 32-bit OVMF. This is the whole point - OVMF (64-bit) would not prove anything,
# because a normal amd64 ISO boots that just fine and still fails on the tablet.
FW_CODE=/usr/share/OVMF/OVMF32_CODE_4M.fd
FW_VARS_SRC=/usr/share/OVMF/OVMF32_VARS_4M.fd
[ -f "$FW_CODE" ] || { echo "Missing $FW_CODE - apt install ovmf-ia32" >&2; exit 1; }

rm -rf "$OUT"; mkdir -p "$OUT"
cp "$FW_VARS_SRC" "$OUT/vars.fd"

echo "==> Booting $(basename "$ISO") under 32-bit UEFI (${MEM}MB, ${RUNTIME}s)"

qemu-system-x86_64 \
    -machine q35 \
    -m "$MEM" \
    -smp 4 \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$FW_CODE" \
    -drive if=pflash,format=raw,unit=1,file="$OUT/vars.fd" \
    -cdrom "$ISO" \
    -boot d \
    -display none \
    -serial file:"$OUT/serial.log" \
    -monitor unix:"$OUT/mon.sock",server,nowait \
    -daemonize \
    -pidfile "$OUT/qemu.pid"

# Screenshot at intervals so we can see firmware -> GRUB -> kernel -> desktop.
shot() {
    printf 'screendump %s\n' "$OUT/shot-$1.ppm" \
        | socat - UNIX-CONNECT:"$OUT/mon.sock" >/dev/null 2>&1 || true
    [ -f "$OUT/shot-$1.ppm" ] && pnmtopng "$OUT/shot-$1.ppm" > "$OUT/shot-$1.png" 2>/dev/null || true
}

elapsed=0
for t in 15 30 45 60 90 120 150 180 240 300; do
    [ "$t" -gt "$RUNTIME" ] && break
    sleep $(( t - elapsed )); elapsed=$t
    shot "$(printf '%03d' "$t")"
    echo "  t=${t}s  screenshot taken"
done

if [ -f "$OUT/qemu.pid" ]; then kill "$(cat "$OUT/qemu.pid")" 2>/dev/null || true; fi

echo
echo "==> Serial log:"; tail -30 "$OUT/serial.log" 2>/dev/null || echo "  (empty)"
echo
echo "==> Screenshots in $OUT:"; ls -la "$OUT"/*.png 2>/dev/null || echo "  none captured"
