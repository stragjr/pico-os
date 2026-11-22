#!/bin/sh
# Build an Android boot image for the OnePlus 6 (enchilada).
#
# Usage: mkboot.sh KERNEL_SRC INITRAMFS OUT
#
# The offsets and command line below are STARTING VALUES. Check them against your
# own unit (unpack the stock boot.img and compare) before you flash anything.
set -eu

KERNEL_SRC=${1:?kernel source dir}
INITRAMFS=${2:?initramfs.cpio.gz}
OUT=${3:?output boot.img}

IMAGE=$KERNEL_SRC/arch/arm64/boot/Image.gz
DTB=$KERNEL_SRC/arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dtb

[ -f "$IMAGE" ] || { echo "missing $IMAGE (run: make kernel)" >&2; exit 1; }
[ -f "$DTB" ]   || { echo "missing $DTB (is the enchilada device tree in your kernel?)" >&2; exit 1; }

# Uses the bundled pure-Python packer. Set MKBOOTIMG=/path/to/mkbootimg to use the AOSP tool instead.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ -n "${MKBOOTIMG:-}" ]; then
    mkbootimg() { "$MKBOOTIMG" "$@"; }
else
    mkbootimg() { python3 "$SCRIPT_DIR/mkbootimg.py" "$@"; }
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The bootloader here expects the device tree appended to the compressed kernel.
cat "$IMAGE" "$DTB" > "$TMP/Image.gz-dtb"

CMDLINE="console=tty0 pstore.backend=ramoops pico.debug=1"

mkbootimg \
    --kernel "$TMP/Image.gz-dtb" \
    --ramdisk "$INITRAMFS" \
    --pagesize 4096 \
    --base 0x00000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x00000100 \
    --header_version 1 \
    --cmdline "$CMDLINE" \
    --output "$OUT"

echo "wrote $OUT"
echo "test it from RAM:  fastboot boot $OUT"
