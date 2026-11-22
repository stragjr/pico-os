#!/bin/sh
# Check Pico's boot image settings against your phone's stock boot.img, in one command.
#
# Usage: scripts/check-stock-boot.sh <FULL-OxygenOS-OTA.zip | payload.bin | boot.img | https://link-to-the-zip>
#
# - a link is downloaded first (a few GB; you can also download the zip in a browser and pass the file)
# - an OTA zip or payload.bin has its boot partition extracted
# - then scripts/inspect-bootimg.py compares the stock header with scripts/mkboot.sh
#   (and with out/pico-boot.img when you have built it)
# Needs only python3 and curl. Writes under build/stock/.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK=$ROOT/build/stock
INPUT=${1:?usage: $0 <OTA.zip | payload.bin | boot.img | https://link>}

mkdir -p "$WORK"

case "$INPUT" in
    http://*|https://*)
        echo "==> downloading $INPUT"
        curl -fL --progress-bar -o "$WORK/ota.zip" "$INPUT"
        INPUT=$WORK/ota.zip
        ;;
esac

[ -f "$INPUT" ] || { echo "no such file: $INPUT" >&2; exit 1; }

if [ "$(head -c 8 "$INPUT")" = "ANDROID!" ]; then
    echo "==> $INPUT is already a boot image"
    BOOTIMG=$INPUT
else
    echo "==> extracting the boot partition from $INPUT"
    BOOTIMG=$WORK/boot.img
    python3 "$ROOT/scripts/extract-boot-from-ota.py" "$INPUT" "$BOOTIMG"
fi

echo
if [ -f "$ROOT/out/pico-boot.img" ]; then
    python3 "$ROOT/scripts/inspect-bootimg.py" "$BOOTIMG" "$ROOT/out/pico-boot.img"
else
    python3 "$ROOT/scripts/inspect-bootimg.py" "$BOOTIMG"
fi
