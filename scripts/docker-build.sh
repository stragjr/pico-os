#!/bin/sh
# Build the Pico boot image in a Linux container (macOS or Linux host with Docker).
#
# Sources live in a Docker VOLUME, not in a folder on your Mac: the Linux kernel tree has
# files whose names differ only by upper/lower case, which breaks on macOS's default
# case-insensitive filesystem. Only the finished files are copied to ./out.
#
# Options through the environment: KERNEL_TAG (default v6.12), JOBS.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$ROOT/out

command -v docker >/dev/null 2>&1 || { echo "docker is not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "the Docker daemon is not running" >&2; exit 1; }

mkdir -p "$OUT"

echo "==> preparing the build image"
docker build -q -t pico-builder -f "$ROOT/docker/Dockerfile" "$ROOT/docker" >/dev/null

docker volume create pico-build >/dev/null

echo "==> building (the first run downloads the kernel and takes a while)"
docker run --rm \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    -e KERNEL_TAG -e JOBS \
    -v pico-build:/build \
    -v "$ROOT":/pico:ro \
    -v "$OUT":/out \
    pico-builder sh /pico/scripts/container-build.sh

echo
echo "boot image: $OUT/pico-boot.img"
echo "test it from RAM (phone in fastboot mode): fastboot boot $OUT/pico-boot.img"
