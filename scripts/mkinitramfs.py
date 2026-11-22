#!/usr/bin/env python3
"""Pack initramfs/ plus a busybox binary into a gzipped newc cpio archive.

Usage: mkinitramfs.py --root initramfs --busybox /path/to/busybox --out out/initramfs.cpio.gz

Written in Python so the build does not depend on a system `cpio`.
"""
import argparse
import gzip
import os
import stat
import sys

S_IFDIR = 0o040000
S_IFREG = 0o100000


def pad4(n):
    return (4 - n % 4) % 4


def entry(ino, name, mode, data=b""):
    name_b = name.encode() + b"\0"
    header = "070701" + "".join(
        "%08X" % v
        for v in (
            ino,        # c_ino
            mode,       # c_mode
            0,          # c_uid
            0,          # c_gid
            1,          # c_nlink
            0,          # c_mtime
            len(data),  # c_filesize
            0, 0,       # c_devmajor, c_devminor
            0, 0,       # c_rdevmajor, c_rdevminor
            len(name_b),
            0,          # c_check
        )
    )
    out = header.encode() + name_b + b"\0" * pad4(110 + len(name_b))
    out += data + b"\0" * pad4(len(data))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--busybox", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if not os.path.isfile(args.busybox):
        sys.exit("busybox not found: %s" % args.busybox)

    ino = 1
    blob = bytearray()

    for d in ("bin", "sbin", "usr", "dev", "proc", "sys", "run", "tmp", "config", "etc"):
        blob += entry(ino, d, S_IFDIR | 0o755)
        ino += 1

    with open(args.busybox, "rb") as f:
        blob += entry(ino, "bin/busybox", S_IFREG | 0o755, f.read())
    ino += 1

    for dirpath, _dirs, files in os.walk(args.root):
        for name in sorted(files):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, args.root)
            mode = os.stat(full).st_mode
            perm = 0o755 if mode & stat.S_IXUSR else 0o644
            with open(full, "rb") as f:
                blob += entry(ino, rel, S_IFREG | perm, f.read())
            ino += 1

    blob += entry(0, "TRAILER!!!", 0)

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with gzip.GzipFile(args.out, "wb", mtime=0) as gz:
        gz.write(bytes(blob))
    print("wrote %s (%d bytes uncompressed)" % (args.out, len(blob)))


if __name__ == "__main__":
    main()
