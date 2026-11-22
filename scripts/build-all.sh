#!/bin/sh
# Build everything natively: Linux kernel, static BusyBox, initramfs and out/pico-boot.img.
# No container. Needs an aarch64 cross-compiler (or an arm64 machine) and the usual kernel build tools;
# scripts/arch-build.sh installs them on Arch. Also used inside the container by scripts/container-build.sh.
#
# Environment: KERNEL_TAG (default v6.12), BUSYBOX_VERSION (default 1.36.1), JOBS,
#              BUILD_DIR (default ./build), OUT_DIR (default ./out), CROSS (default: auto)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR=${BUILD_DIR:-$ROOT/build}
OUT_DIR=${OUT_DIR:-$ROOT/out}
KERNEL_TAG=${KERNEL_TAG:-v6.12}
BUSYBOX_VERSION=${BUSYBOX_VERSION:-1.36.1}
JOBS=${JOBS:-$(nproc)}
export KERNEL_TAG
export KERNEL_SRC=$BUILD_DIR/linux

# On an arm64 machine the compiler already targets arm64.
if [ -z "${CROSS+x}" ]; then
    if [ "$(uname -m)" = "aarch64" ]; then CROSS=""; else CROSS="aarch64-linux-gnu-"; fi
fi
export CROSS

missing=""
for t in "${CROSS}gcc" make flex bison bc git curl python3 readelf; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
    echo "missing tools:$missing" >&2
    echo "On Arch, ./scripts/arch-build.sh installs everything. Elsewhere see README.md." >&2
    exit 1
fi

mkdir -p "$BUILD_DIR" "$OUT_DIR"

# --- Kernel ---------------------------------------------------------------------
echo "==> kernel"
sh "$ROOT/scripts/build-kernel.sh"

# --- BusyBox (static arm64) -----------------------------------------------------
echo "==> BusyBox $BUSYBOX_VERSION"
BB=$BUILD_DIR/busybox-$BUSYBOX_VERSION
if [ ! -d "$BB" ]; then
    curl -fsSL "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" | tar -xj -C "$BUILD_DIR"
fi
cd "$BB"
make ARCH=arm64 CROSS_COMPILE="$CROSS" defconfig >/dev/null
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
yes "" | make ARCH=arm64 CROSS_COMPILE="$CROSS" oldconfig >/dev/null
for sym in STATIC TELNETD FEATURE_TELNETD_STANDALONE IP FEATURE_IP_ADDRESS ASH; do
    grep -q "^CONFIG_$sym=y" .config || { echo "BusyBox config is missing CONFIG_$sym" >&2; exit 1; }
done
make ARCH=arm64 CROSS_COMPILE="$CROSS" -j"$JOBS" busybox >/dev/null
if readelf -d busybox 2>/dev/null | grep -q NEEDED; then
    echo "BusyBox came out dynamically linked; the cross glibc has no static libraries (libc.a)" >&2
    exit 1
fi
cd "$ROOT"

# --- Initramfs, device tree IDs and boot image ------------------------------------
echo "==> initramfs and boot image"
python3 "$ROOT/scripts/mkinitramfs.py" --root "$ROOT/initramfs" --busybox "$BB/busybox" --out "$BUILD_DIR/initramfs.cpio.gz"

DTB=$KERNEL_SRC/arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dtb
if [ -f "$ROOT/kernel/bootloader-ids.txt" ]; then
    echo "==> adding bootloader IDs (kernel/bootloader-ids.txt) to the device tree"
    sh "$ROOT/scripts/patch-dtb-ids.sh" "$ROOT/kernel/bootloader-ids.txt" "$DTB" "$BUILD_DIR/enchilada-patched.dtb"
    DTB=$BUILD_DIR/enchilada-patched.dtb
else
    echo "NOTE: kernel/bootloader-ids.txt not found; the device tree has no qcom,msm-id/board-id," >&2
    echo "      and the OnePlus bootloader may accept the image but not start it." >&2
    echo "      Create it with: python3 scripts/dtb-ids.py <stock boot.img> --write kernel/bootloader-ids.txt" >&2
fi
export DTB
sh "$ROOT/scripts/mkboot.sh" "$KERNEL_SRC" "$BUILD_DIR/initramfs.cpio.gz" "$OUT_DIR/pico-boot.img"

cp "$KERNEL_SRC/arch/arm64/boot/Image.gz" "$OUT_DIR/Image.gz"
cp "$DTB" "$OUT_DIR/sdm845-oneplus-enchilada.dtb"
cp "$KERNEL_SRC/.config" "$OUT_DIR/kernel.config"
cp "$BUILD_DIR/initramfs.cpio.gz" "$OUT_DIR/"
cp "$BB/busybox" "$OUT_DIR/busybox-aarch64"

echo
echo "done: $OUT_DIR/pico-boot.img"
