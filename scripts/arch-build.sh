#!/bin/bash
# One command on Arch Linux: install the tools, fetch the kernel and BusyBox, build Pico's boot image.
#
#   ./scripts/arch-build.sh            build out/pico-boot.img
#   ./scripts/arch-build.sh --boot     build, then offer to boot it from RAM on a phone in fastboot mode
#
# Run as your normal user (it uses sudo where needed). The build itself runs in a Docker container.
# Expect 20 to 60 minutes the first time and about 10 GB of disk.
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

[ -r /etc/arch-release ] || die "this script is for Arch Linux. Elsewhere: install Docker, then run: sh scripts/docker-build.sh"
[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not root"
command -v sudo >/dev/null 2>&1 || die "sudo is not installed"

# --- 1. Packages ----------------------------------------------------------------------------------
say "Installing packages (git, python, docker, android-tools for fastboot, inetutils for telnet)"
sudo pacman -S --needed --noconfirm git python docker docker-buildx android-tools inetutils \
    || die "pacman failed. If it reports 404s, update first with: sudo pacman -Syu"

# --- 2. Docker -----------------------------------------------------------------------------------
if ! systemctl is-active --quiet docker; then
    say "Starting the Docker service"
    sudo systemctl enable --now docker
fi

if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
    say "Adding $USER to the docker group (takes full effect at your next login)"
    sudo usermod -aG docker "$USER"
fi

# Right after usermod this shell does not have the group yet; run the build through `sg` then.
run_in_docker_group() {
    if docker info >/dev/null 2>&1; then
        "$@"
    else
        sg docker -c "$(printf '%q ' "$@")"
    fi
}

run_in_docker_group docker info >/dev/null 2>&1 \
    || die "cannot reach Docker. Log out and back in (so the docker group applies) and run this again."

# --- 3. Fetch and build --------------------------------------------------------------------------
say "Fetching sources and building"
run_in_docker_group sh scripts/docker-build.sh

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
