#!/bin/sh
# Build the bisect images that show which piece of Pico's boot image the bootloader refuses.
#
# Usage: scripts/make-test-images.sh [stock boot.img]     (default: build/stock/ota.zip)
# Needs out/initramfs.cpio.gz from a finished build (./scripts/arch-build.sh).
#
# Then, phone in fastboot mode, try each with `fastboot boot` and note what happens:
#   test1: your STOCK kernel and ramdisk, repacked by Pico's packer
#          -> expected: Android boots as normal (orange "bootloader unlocked" warning first).
#             If it stays on the fastboot screen, `fastboot boot` or the packer is the problem.
#   test2: your STOCK kernel with Pico's initramfs
#          -> if the screen leaves fastboot (black, logo, reboot loop), the bootloader accepted Pico's
#             packaging and the problem is Pico's kernel or device tree.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
STOCK=${1:-$ROOT/build/stock/ota.zip}
OUT=$ROOT/out

[ -f "$STOCK" ] || { echo "no stock boot image at $STOCK (pass the path)" >&2; exit 1; }
[ -f "$OUT/initramfs.cpio.gz" ] || { echo "missing $OUT/initramfs.cpio.gz: run ./scripts/arch-build.sh first" >&2; exit 1; }

python3 "$ROOT/scripts/repack-stock.py" "$STOCK" "$OUT/test1-stock-repacked.img"
python3 "$ROOT/scripts/repack-stock.py" "$STOCK" "$OUT/test2-stock-kernel-pico-initramfs.img" \
    --ramdisk "$OUT/initramfs.cpio.gz"

echo
echo "Now, with the phone in fastboot mode, one at a time:"
echo "  fastboot boot $OUT/test1-stock-repacked.img"
echo "  fastboot boot $OUT/test2-stock-kernel-pico-initramfs.img"
