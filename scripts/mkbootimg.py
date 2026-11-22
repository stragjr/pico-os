#!/usr/bin/env python3
"""Minimal Android boot image packer (header version 0), no dependencies.

Same option names as AOSP mkbootimg for the fields Pico uses, so the real tool can be
dropped in through the MKBOOTIMG variable in mkboot.sh if you prefer it.
"""
import argparse
import hashlib
import struct
import sys

MAGIC = b"ANDROID!"
HEADER = struct.Struct("<8s10I16s512s32s1024s")  # 1632 bytes


def num(text):
    return int(text, 0)


def pad(data, page):
    return data + b"\0" * ((-len(data)) % page)


def read(path):
    if not path:
        return b""
    with open(path, "rb") as f:
        return f.read()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--ramdisk", default="")
    ap.add_argument("--second", default="")
    ap.add_argument("--cmdline", default="")
    ap.add_argument("--board", default="")
    ap.add_argument("--base", type=num, default=0x10000000)
    ap.add_argument("--kernel_offset", type=num, default=0x00008000)
    ap.add_argument("--ramdisk_offset", type=num, default=0x01000000)
    ap.add_argument("--second_offset", type=num, default=0x00F00000)
    ap.add_argument("--tags_offset", type=num, default=0x00000100)
    ap.add_argument("--pagesize", type=num, default=2048, choices=[2048, 4096, 8192, 16384])
    ap.add_argument("--header_version", type=num, default=0)
    ap.add_argument("--output", "-o", required=True)
    args = ap.parse_args()

    if args.header_version != 0:
        sys.exit("only boot image header version 0 is supported here")

    cmdline = args.cmdline.encode()
    if len(cmdline) > 512 + 1024 - 1:
        sys.exit("kernel command line is too long")
    cmd_main, cmd_extra = cmdline[:512], cmdline[512:]
    if len(cmd_main) == 512:  # field must stay NUL terminated; spill the last byte over
        cmd_main, cmd_extra = cmdline[:511], cmdline[511:]

    kernel, ramdisk, second = read(args.kernel), read(args.ramdisk), read(args.second)
    if not kernel:
        sys.exit("kernel file is empty")

    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        sha.update(blob)
        sha.update(struct.pack("<I", len(blob)))
    image_id = sha.digest().ljust(32, b"\0")

    header = HEADER.pack(
        MAGIC,
        len(kernel), args.base + args.kernel_offset,
        len(ramdisk), args.base + args.ramdisk_offset,
        len(second), args.base + args.second_offset,
        args.base + args.tags_offset,
        args.pagesize,
        args.header_version,
        0,  # os_version
        args.board.encode()[:15],
        cmd_main,
        image_id,
        cmd_extra,
    )

    with open(args.output, "wb") as out:
        out.write(pad(header, args.pagesize))
        out.write(pad(kernel, args.pagesize))
        if ramdisk:
            out.write(pad(ramdisk, args.pagesize))
        if second:
            out.write(pad(second, args.pagesize))
    print("wrote %s" % args.output)


if __name__ == "__main__":
    main()
