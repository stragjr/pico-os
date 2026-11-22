#!/bin/sh
# Boot the Pico kernel and initramfs in QEMU (aarch64 virt machine).
#
# Usage: run-qemu.sh KERNEL_IMAGE INITRAMFS
# KERNEL_IMAGE is the uncompressed arch/arm64/boot/Image from a kernel built with
# the generic arm64 defconfig plus kernel/pico.config (virtio drivers come from the defconfig).
set -eu

KERNEL=${1:?path to arch/arm64/boot/Image}
INITRAMFS=${2:?path to initramfs.cpio.gz}

command -v qemu-system-aarch64 >/dev/null || { echo "qemu-system-aarch64 not installed" >&2; exit 1; }

exec qemu-system-aarch64 \
    -machine virt \
    -cpu cortex-a72 \
    -smp 4 \
    -m 2048 \
    -kernel "$KERNEL" \
    -initrd "$INITRAMFS" \
    -append "console=ttyAMA0 pico.debug=1" \
    -device virtio-gpu-pci \
    -device virtio-keyboard-pci \
    -device virtio-tablet-pci \
    -nic user \
    -serial mon:stdio
