#!/usr/bin/env python3
"""Print the header of an Android boot image and compare it with what Pico's mkboot.sh builds.

Usage: inspect-bootimg.py stock-boot.img [pico-boot.img]

Run it on your phone's stock boot.img to check the offsets and page size in scripts/mkboot.sh.
Read-only: it never writes anything.
"""
import struct
import sys

# What scripts/mkboot.sh uses today (keep in sync with that file).
PICO = {
    "page size": 4096,
    "kernel address": 0x00008000,
    "ramdisk address": 0x01000000,
    "second address": 0x00F00000,
    "tags address": 0x00000100,
    "header version": 0,
}


def parse(path):
    with open(path, "rb") as f:
        d = f.read(4096)
    if d[:8] != b"ANDROID!":
        sys.exit("%s: not an Android boot image (no ANDROID! magic)" % path)
    (ksize, kaddr, rsize, raddr, ssize, saddr, tags, page, ver, osver) = struct.unpack("<10I", d[8:48])
    name = d[48:64].split(b"\0")[0].decode(errors="replace")
    cmd = d[64:576].split(b"\0")[0].decode(errors="replace")
    extra = d[608:1632].split(b"\0")[0].decode(errors="replace")
    return {
        "page size": page,
        "kernel address": kaddr,
        "ramdisk address": raddr,
        "second address": saddr,
        "tags address": tags,
        "header version": ver,
        "_kernel size": ksize,
        "_ramdisk size": rsize,
        "_second size": ssize,
        "_os version": osver,
        "_name": name,
        "_cmdline": (cmd + extra).strip(),
    }


def show(label, h):
    print("== %s" % label)
    for k in ("header version", "page size", "kernel address", "ramdisk address", "second address", "tags address"):
        v = h[k]
        print("  %-16s %s" % (k, v if k in ("header version", "page size") else "0x%08x" % v))
    print("  %-16s %d bytes" % ("kernel size", h["_kernel size"]))
    print("  %-16s %d bytes" % ("ramdisk size", h["_ramdisk size"]))
    print("  %-16s %s" % ("cmdline", h["_cmdline"] or "(empty)"))
    if h["header version"] > 0:
        print("  note: header version %d has extra fields that this tool does not decode" % h["header version"])


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    stock = parse(sys.argv[1])
    show("stock: %s" % sys.argv[1], stock)
    if len(sys.argv) == 3:
        show("pico: %s" % sys.argv[2], parse(sys.argv[2]))

    print("== check against scripts/mkboot.sh")
    ok = True
    for k, want in PICO.items():
        have = stock[k]
        same = have == want
        ok &= same
        fmt = (lambda v: str(v)) if k in ("page size", "header version") else (lambda v: "0x%08x" % v)
        print("  %-16s stock %-12s pico %-12s %s" % (k, fmt(have), fmt(want), "ok" if same else "DIFFERENT"))
    if ok:
        print("All values match.")
    else:
        print("Some values differ: edit scripts/mkboot.sh (and PICO above) to the stock values, rebuild, and try again.")
        print("Addresses are base + offset; mkboot.sh uses base 0, so stock addresses are the offsets to use.")


if __name__ == "__main__":
    main()
