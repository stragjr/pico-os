#!/bin/sh
# Runs INSIDE the Docker container (started by scripts/docker-build.sh, used by the macOS script).
# /pico = this repo (read-only), /build = persistent volume for sources, /out = results on the host.
# The actual build is scripts/build-all.sh, the same one used natively on Linux.
set -eu

export BUILD_DIR=/build OUT_DIR=/out
sh /pico/scripts/build-all.sh

if [ -n "${HOST_UID:-}" ]; then
    chown "$HOST_UID:${HOST_GID:-$HOST_UID}" /out/pico-boot.img /out/Image.gz /out/*.dtb \
        /out/kernel.config /out/initramfs.cpio.gz /out/busybox-aarch64
fi
