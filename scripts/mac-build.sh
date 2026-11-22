#!/bin/bash
# One command on a Mac: install the tools, fetch the kernel and BusyBox, build Pico's boot image.
#
#   ./scripts/mac-build.sh            build out/pico-boot.img
#   ./scripts/mac-build.sh --boot     build, then offer to boot it from RAM on a phone in fastboot mode
#
# Needs Homebrew (https://brew.sh). The build itself runs in a Linux container (colima + docker, or
# Docker Desktop if you already have it). Expect 20 to 60 minutes the first time and about 10 GB of disk.
set -euo pipefail

cd "$(dirname "$0")/.."

say() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

BOOT=0
for arg in "$@"; do
    case "$arg" in
        --boot) BOOT=1 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) die "unknown option: $arg" ;;
    esac
done

[ "$(uname -s)" = "Darwin" ] || die "this script is for macOS; on Linux run: sh scripts/docker-build.sh"
command -v brew >/dev/null 2>&1 || die "Homebrew is not installed. Install it from https://brew.sh, then run this again."

# --- 1. Tools -----------------------------------------------------------------------------------
say "Installing tools with Homebrew"
command -v git >/dev/null 2>&1 || brew install git
brew list --cask android-platform-tools >/dev/null 2>&1 || brew install --cask android-platform-tools
if ! command -v docker >/dev/null 2>&1; then
    brew install colima docker
fi

# --- 2. Container runtime -----------------------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
    if command -v colima >/dev/null 2>&1; then
        say "Starting colima (the Linux VM the build runs in)"
        cpus=$(sysctl -n hw.ncpu)
        [ "$cpus" -gt 8 ] && cpus=8
        colima start --cpu "$cpus" --memory 8 --disk 80
    else
        die "Docker is installed but not running. Open Docker Desktop, wait until it says it is running, then run this again."
    fi
fi
docker info >/dev/null 2>&1 || die "Docker still is not reachable"

# --- 3. Fetch and build -------------------------------------------------------------------------
say "Fetching sources and building"
sh scripts/docker-build.sh

say "Built: $PWD/out/pico-boot.img"
cat <<'EOF'

Before the first boot on the phone:
  - the bootloader must be unlocked (this wipes the phone) and the stock partitions backed up
  - check the offsets in scripts/mkboot.sh against your stock boot image
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
            ;;
    esac
fi
