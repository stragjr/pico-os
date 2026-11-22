#!/usr/bin/env python3
"""Repack a stock Android boot image with Pico's packer, optionally swapping one piece.

Usage: repack-stock.py STOCK.img OUT.img [--ramdisk FILE] [--kernel FILE] [--cmdline TEXT]

Keeps the stock addresses, page size, header version, os_version and name. With no options the result
should be functionally identical to the stock image, which tests the packer and the way it is booted.
Header versions 0 and 1 with no second stage and no recovery dtbo are supported (the OnePlus 6 boot image).
"""
import argparse
import os
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stock")
    ap.add_argument("out")
    ap.add_argument("--ramdisk")
    ap.add_argument("--kernel")
    ap.add_argument("--cmdline")
    args = ap.parse_args()

    d = open(args.stock, "rb").read()
    if d[:8] != b"ANDROID!":
        sys.exit("%s is not an Android boot image" % args.stock)
    ksize, kaddr, rsize, raddr, ssize, saddr, tags, page, ver, osver = struct.unpack("<10I", d[8:48])
    if ver > 1:
        sys.exit("header version %d is not supported" % ver)
    if ssize:
        sys.exit("this image has a second stage; not supported")
    if ver == 1 and struct.unpack("<IQI", d[1632:1648])[0]:
        sys.exit("this image has a recovery dtbo; not supported")

    name = d[48:64].split(b"\0")[0].decode(errors="replace")
    cmdline = (d[64:576].split(b"\0")[0] + d[608:1632].split(b"\0")[0]).decode(errors="replace")
    kernel = d[page:page + ksize]
    roff = page + ((ksize + page - 1) // page) * page
    ramdisk = d[roff:roff + rsize]

    if args.kernel:
        kernel = open(args.kernel, "rb").read()
    if args.ramdisk:
        ramdisk = open(args.ramdisk, "rb").read()
    if args.cmdline is not None:
        cmdline = args.cmdline

    with tempfile.TemporaryDirectory() as tmp:
        kpath, rpath = os.path.join(tmp, "kernel"), os.path.join(tmp, "ramdisk")
        open(kpath, "wb").write(kernel)
        open(rpath, "wb").write(ramdisk)
        subprocess.run([
            sys.executable, os.path.join(HERE, "mkbootimg.py"),
            "--kernel", kpath, "--ramdisk", rpath, "--cmdline", cmdline, "--board", name,
            "--base", "0", "--kernel_offset", hex(kaddr), "--ramdisk_offset", hex(raddr),
            "--second_offset", hex(saddr), "--tags_offset", hex(tags),
            "--pagesize", str(page), "--header_version", str(ver), "--os_version", hex(osver),
            "--output", args.out,
        ], check=True, stdout=subprocess.DEVNULL)
    print("wrote %s (kernel %s, ramdisk %s)" % (
        args.out, "replaced" if args.kernel else "stock", "replaced" if args.ramdisk else "stock"))


if __name__ == "__main__":
    main()
