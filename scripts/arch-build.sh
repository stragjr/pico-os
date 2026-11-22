#!/bin/bash
# One command on Arch Linux: install the tools, fetch the kernel and BusyBox, build Pico's boot image.
# Fully native: no Docker, no containers.
#
#   ./scripts/arch-build.sh            build out/pico-boot.img
#   ./scripts/arch-build.sh --boot     build, then offer to boot it from RAM on a phone in fastboot mode
#
# Run as your normal user (it uses sudo for pacman). Expect 15 to 60 minutes the first time
# (depends on your CPU) and about 10 GB of disk. Sources are kept in ./build.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

BOOT=0
for arg in "$@"; do
    case "$arg" in
        --boot) BOOT=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

[ -r /etc/arch-release ] || die "this script is for Arch Linux. Elsewhere, install the tools yourself and run: sh scripts/build-all.sh"
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"
command -v sudo >/dev/null 2>&1 || die "sudo is not installed"

# --- 1. Packages ----------------------------------------------------------------------------------
say "Installing packages"
sudo pacman -S --needed --noconfirm \
    base-devel git python bc flex bison openssl libelf cpio curl dtc \
    aarch64-linux-gnu-gcc aarch64-linux-gnu-glibc aarch64-linux-gnu-binutils \
    android-tools inetutils \
    || die "pacman failed. If it reports 404s, update first with: sudo pacman -Syu"

# --- 2. Can the cross toolchain link a static program? (BusyBox needs that) ------------------------
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
printf 'int main(void){return 0;}\n' > "$tmp/t.c"
aarch64-linux-gnu-gcc -static -o "$tmp/t" "$tmp/t.c" 2>"$tmp/err" || {
    cat "$tmp/err" >&2
    die "the aarch64 toolchain cannot link static programs (no libc.a in aarch64-linux-gnu-glibc). Tell me this output."
}

# --- 3. Fetch and build --------------------------------------------------------------------------
say "Fetching sources and building"
sh scripts/build-all.sh

say "Built: $PWD/out/pico-boot.img"
cat <<'EOF'

Before the first boot on the phone:
  - the bootloader must be unlocked (this wipes the phone) and the stock partitions backed up
  - run ./scripts/check-stock-boot.sh with your stock OxygenOS OTA zip or boot.img, then
    python3 scripts/dtb-ids.py <that file> --write kernel/bootloader-ids.txt and rebuild
    (without those IDs the bootloader may accept the image and still not start it)
  - always use "fastboot boot", never "fastboot flash", for the first tests
EOF

# --- 4. Optional: boot from RAM ------------------------------------------------------------------
if [ "$BOOT" = 1 ]; then
    say "Looking for a phone in fastboot mode"
    found=$(fastboot devices 2>/dev/null || true)
    case "$found" in
        *fastboot*)
            read -r -p "Boot Pico from RAM on the connected phone now? Nothing is flashed. [y/N] " ans
            if [ "$ans" = "y" ] || [ "$ans" = "Y" ]; then
                fastboot boot out/pico-boot.img
            fi
            ;;
        *)
            echo "No phone found. Power it off, hold Volume Up + Power to reach fastboot mode, connect USB, and run:"
            echo "  fastboot boot out/pico-boot.img"
            echo "If 'fastboot devices' stays empty with the phone connected, it is usually a udev permission:"
            echo "  try 'sudo fastboot devices' once, and if that works install the android-udev package."
            ;;
    esac
fi
