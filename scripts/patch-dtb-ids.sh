#!/bin/sh
# Add the bootloader-matching IDs from kernel/bootloader-ids.txt to a compiled device tree.
#
# Usage: patch-dtb-ids.sh IDS.txt IN.dtb OUT.dtb
# Needs fdtput/fdtget (package device-tree-compiler). IN.dtb is left untouched.
set -eu

IDS=${1:?ids file}
IN=${2:?input dtb}
OUT=${3:?output dtb}

command -v fdtput >/dev/null 2>&1 || { echo "fdtput not installed (package device-tree-compiler)" >&2; exit 1; }
[ -f "$IDS" ] || { echo "no such file: $IDS" >&2; exit 1; }

cp "$IN" "$OUT"

while read -r prop eq vals; do
    case "$prop" in ''|'#'*) continue ;; esac
    if [ "$eq" != "=" ] || [ -z "$vals" ]; then
        echo "bad line in $IDS: '$prop $eq $vals' (expected: property = 0x.. 0x..)" >&2
        exit 1
    fi
    hex=$(printf '%s' "$vals" | sed 's/0x//g')
    # $hex is deliberately unquoted: one argument per cell.
    fdtput -t x "$OUT" / "$prop" $hex
    echo "  $prop = $(fdtget -t x "$OUT" / "$prop")"
done < "$IDS"
