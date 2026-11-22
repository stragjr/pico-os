#!/bin/sh
# Fetch, configure and build the Pico M0 kernel for the OnePlus 6 (arm64).
#
# Usage: scripts/build-kernel.sh            # build natively with aarch64-linux-gnu-gcc
#        make kernel-docker                 # same build inside a Debian container
#
# Environment:
#   KERNEL_TAG   kernel version tag to build (default v6.12, a long-term release)
#   KERNEL_SRC   where the source lives (default build/linux)
#   JOBS         parallel jobs (default: number of CPUs)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL_TAG=${KERNEL_TAG:-v6.12}
KERNEL_SRC=${KERNEL_SRC:-$ROOT/build/linux}
JOBS=${JOBS:-$(nproc)}
CROSS=${CROSS:-aarch64-linux-gnu-}

# --- 1. Tools -----------------------------------------------------------------
missing=""
for t in "${CROSS}gcc" make flex bison bc git; do
    command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
    echo "missing tools:$missing" >&2
    echo "Debian/Ubuntu: sudo apt install build-essential gcc-aarch64-linux-gnu flex bison bc libssl-dev libelf-dev git" >&2
    echo "Or run the build in a container: make kernel-docker" >&2
    exit 1
fi

# --- 2. Source ----------------------------------------------------------------
if [ ! -d "$KERNEL_SRC/.git" ]; then
    echo "==> cloning Linux $KERNEL_TAG (shallow) into $KERNEL_SRC"
    mkdir -p "$(dirname "$KERNEL_SRC")"
    git clone --depth 1 --branch "$KERNEL_TAG" \
        https://github.com/torvalds/linux.git "$KERNEL_SRC"
fi

DTS=$KERNEL_SRC/arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dts
[ -f "$DTS" ] || { echo "enchilada device tree not found in $KERNEL_SRC" >&2; exit 1; }

# --- 3. Configure ---------------------------------------------------------------
echo "==> configuring (arm64 defconfig + kernel/pico.config)"
cd "$KERNEL_SRC"
export ARCH=arm64 CROSS_COMPILE="$CROSS"
make defconfig
./scripts/kconfig/merge_config.sh -m .config "$ROOT/kernel/pico.config" >/dev/null
make olddefconfig

# olddefconfig silently drops symbols this kernel version does not know,
# so check that the ones M0 cannot boot without actually survived.
bad=0
for sym in BLK_DEV_INITRD DEVTMPFS DEVTMPFS_MOUNT SCSI_UFS_QCOM DRM_MSM \
           DRM_PANEL_SAMSUNG_SOFEF00 RMI4_I2C USB_DWC3_QCOM USB_CONFIGFS \
           USB_CONFIGFS_RNDIS PSTORE_RAM ANDROID_BINDER_IPC; do
    if ! grep -q "^CONFIG_$sym=y" .config; then
        echo "WARNING: CONFIG_$sym is not =y in the final .config" >&2
        bad=1
    fi
done
[ "$bad" = 0 ] || echo "Fix kernel/pico.config for $KERNEL_TAG (symbol renamed or missing dependency), then rebuild." >&2

# --- 4. Build -------------------------------------------------------------------
echo "==> building Image.gz and device trees with $JOBS jobs"
make -j"$JOBS" Image.gz dtbs

DTB=arch/arm64/boot/dts/qcom/sdm845-oneplus-enchilada.dtb
[ -f arch/arm64/boot/Image.gz ] && [ -f "$DTB" ] || { echo "build finished without the expected outputs" >&2; exit 1; }

if [ -n "${HOST_UID:-}" ]; then
    chown -R "$HOST_UID:${HOST_GID:-$HOST_UID}" "$ROOT/build" 2>/dev/null || true
fi

echo
echo "kernel built: $KERNEL_SRC/arch/arm64/boot/Image.gz"
echo "device tree:  $KERNEL_SRC/$DTB"
echo "next:         make boot BUSYBOX=/path/to/busybox-aarch64 KERNEL_SRC=$KERNEL_SRC"
