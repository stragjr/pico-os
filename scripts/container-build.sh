#!/bin/sh
# Runs INSIDE the Docker container (started by scripts/docker-build.sh).
# /pico = this repo (read-only), /build = persistent volume for sources, /out = results on the host.
set -eu

KERNEL_TAG=${KERNEL_TAG:-v6.12}
BUSYBOX_VERSION=${BUSYBOX_VERSION:-1.36.1}
export KERNEL_TAG
export KERNEL_SRC=/build/linux

# On an arm64 host (Apple Silicon) the container's own gcc already targets arm64.
if [ "$(uname -m)" = "aarch64" ]; then
    CROSS=""
else
    CROSS="aarch64-linux-gnu-"
fi
export CROSS

mkdir -p /build /out

# --- Kernel ---------------------------------------------------------------------
echo "==> kernel"
sh /pico/scripts/build-kernel.sh

# --- BusyBox (static arm64) -----------------------------------------------------
echo "==> BusyBox $BUSYBOX_VERSION"
BB=/build/busybox-$BUSYBOX_VERSION
if [ ! -d "$BB" ]; then
    curl -fsSL "https://busybox.net/downloads/busybox-$BUSYBOX_VERSION.tar.bz2" | tar -xj -C /build
fi
cd "$BB"
make ARCH=arm64 CROSS_COMPILE="$CROSS" defconfig >/dev/null
sed -i 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/' .config
yes "" | make ARCH=arm64 CROSS_COMPILE="$CROSS" oldconfig >/dev/null
for sym in STATIC TELNETD FEATURE_TELNETD_STANDALONE IP FEATURE_IP_ADDRESS ASH; do
    grep -q "^CONFIG_$sym=y" .config || { echo "BusyBox config is missing CONFIG_$sym" >&2; exit 1; }
done
make ARCH=arm64 CROSS_COMPILE="$CROSS" -j"${JOBS:-$(nproc)}" busybox >/dev/null
file busybox | grep -q "statically linked" || { echo "BusyBox is not statically linked" >&2; exit 1; }
cd /

# --- Initramfs and boot image ---------------------------------------------------
echo "==> initramfs and boot image"
python3 /pico/scripts/mkinitramfs.py --root /pico/initramfs --busybox "$BB/busybox" --out /build/initramfs.cpio.gz

DTB=$KERNEL_SRC/arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dtb
if [ -f /pico/kernel/bootloader-ids.txt ]; then
    echo "==> adding bootloader IDs (kernel/bootloader-ids.txt) to the device tree"
    sh /pico/scripts/patch-dtb-ids.sh /pico/kernel/bootloader-ids.txt "$DTB" /build/enchilada-patched.dtb
    DTB=/build/enchilada-patched.dtb
else
    echo "NOTE: kernel/bootloader-ids.txt not found; the device tree has no qcom,msm-id/board-id," >&2
    echo "      and the OnePlus bootloader may accept the image but not start it." >&2
    echo "      Create it with: python3 scripts/dtb-ids.py <stock boot.img> --write kernel/bootloader-ids.txt" >&2
fi
export DTB
sh /pico/scripts/mkboot.sh "$KERNEL_SRC" /build/initramfs.cpio.gz /out/pico-boot.img

cp "$KERNEL_SRC/arch/arm64/boot/Image.gz" /out/Image.gz
cp "$DTB" /out/sdm845-oneplus-enchilada.dtb
cp "$KERNEL_SRC/.config" /out/kernel.config
cp /build/initramfs.cpio.gz /out/
cp "$BB/busybox" /out/busybox-aarch64

if [ -n "${HOST_UID:-}" ]; then
    chown "$HOST_UID:${HOST_GID:-$HOST_UID}" /out/pico-boot.img /out/Image.gz /out/*.dtb \
        /out/kernel.config /out/initramfs.cpio.gz /out/busybox-aarch64
fi

echo
echo "done: /out/pico-boot.img"
