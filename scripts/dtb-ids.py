#!/usr/bin/env python3
"""List the device trees appended to a stock kernel and the IDs the bootloader matches them by.

Usage: dtb-ids.py stock-boot.img                      # print every appended device tree
       dtb-ids.py stock-boot.img --write kernel/bootloader-ids.txt

Qualcomm bootloaders choose the appended device tree by qcom,msm-id (SoC id + revision) and
qcom,board-id (platform + subtype). The upstream Linux tree for the OnePlus 6 has neither, so the
bootloader can accept `fastboot boot` and still never start the kernel. --write collects every
msm-id and board-id found in the stock image into a file the Pico build adds to its own device tree
(a property may list several pairs, and the bootloader accepts a match on any of them).
Read-only except for the file given to --write.
"""
import re
import struct
import sys

FDT_MAGIC = b"\xd0\x0d\xfe\xed"
BEGIN, END_NODE, PROP, NOP, END = 1, 2, 3, 4, 9


def cstr(buf, pos):
    end = buf.index(b"\0", pos)
    return buf[pos:end].decode(errors="replace"), end


def parse_fdt(data, off):
    """Return (size, root_properties) for a flattened device tree at data[off:], or None."""
    if len(data) - off < 40:
        return None
    (magic, total, off_struct, off_strings, _rsv, version, _compat, _cpu, size_strings, size_struct) = \
        struct.unpack(">10I", data[off:off + 40])
    if version < 16 or total < 64 or off + total > len(data):
        return None
    if off_struct + size_struct > total or off_strings + size_strings > total:
        return None
    blob = data[off:off + total]
    strings = blob[off_strings:off_strings + size_strings]
    pos, end, depth, props = off_struct, off_struct + size_struct, 0, {}
    while pos + 4 <= end:
        (tok,) = struct.unpack(">I", blob[pos:pos + 4])
        pos += 4
        if tok == BEGIN:
            _name, e = cstr(blob, pos)
            pos = (e + 1 + 3) & ~3
            depth += 1
        elif tok == END_NODE:
            depth -= 1
            if depth <= 0:
                break
        elif tok == PROP:
            length, nameoff = struct.unpack(">II", blob[pos:pos + 8])
            pos += 8
            value = blob[pos:pos + length]
            pos = (pos + length + 3) & ~3
            if depth == 1:
                props[cstr(strings, nameoff)[0]] = value
        elif tok == NOP:
            continue
        elif tok == END:
            break
        else:
            return None
    if not props:
        return None
    return total, props


def kernel_region(data):
    """For an Android boot image, just the kernel (where the appended trees live)."""
    if data[:8] != b"ANDROID!":
        return data
    ksize, page = struct.unpack("<I", data[8:12])[0], struct.unpack("<I", data[36:40])[0]
    return data[page:page + ksize]


def find_dtbs(data):
    found = []
    for m in re.finditer(re.escape(FDT_MAGIC), data):
        r = parse_fdt(data, m.start())
        if r:
            found.append((m.start(), r[0], r[1]))
    return found


def words(value):
    return list(struct.unpack(">%dI" % (len(value) // 4), value[: len(value) // 4 * 4]))


def strings_of(value):
    return [s.decode(errors="replace") for s in value.split(b"\0") if s]


def pairs(ws):
    return [tuple(ws[i:i + 2]) for i in range(0, len(ws) - 1, 2)]


def main():
    args = sys.argv[1:]
    out = None
    if "--write" in args:
        i = args.index("--write")
        try:
            out = args[i + 1]
        except IndexError:
            sys.exit(__doc__)
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)

    data = kernel_region(open(args[0], "rb").read())
    dtbs = find_dtbs(data)
    if not dtbs:
        sys.exit("no appended device trees found in %s. If the kernel there is not Image.gz-dtb, "
                 "the IDs live somewhere else (tell me what this image is)." % args[0])

    msm, board = [], []
    for n, (off, size, props) in enumerate(dtbs):
        print("[%d] offset %d, %d bytes" % (n, off, size))
        if "model" in props:
            print("    model       %s" % strings_of(props["model"])[0])
        if "compatible" in props:
            print("    compatible  %s" % ", ".join(strings_of(props["compatible"])))
        for key in ("qcom,msm-id", "qcom,board-id", "qcom,pmic-id"):
            if key in props:
                ws = words(props[key])
                print("    %-12s %s" % (key.split(",")[1], " ".join("0x%x" % w for w in ws)))
        for key, bucket in (("qcom,msm-id", msm), ("qcom,board-id", board)):
            if key in props:
                for p in pairs(words(props[key])):
                    if p not in bucket:
                        bucket.append(p)

    print("\n%d device tree(s); %d distinct msm-id pair(s), %d distinct board-id pair(s)"
          % (len(dtbs), len(msm), len(board)))

    if out:
        if not msm or not board:
            sys.exit("the stock trees have no msm-id or board-id; nothing to write")
        with open(out, "w") as f:
            f.write("# Written by scripts/dtb-ids.py from the stock OnePlus 6 boot image.\n")
            f.write("# The Pico build adds these to its device tree so the bootloader will accept it.\n")
            f.write("qcom,msm-id = %s\n" % " ".join("0x%x 0x%x" % p for p in msm))
            f.write("qcom,board-id = %s\n" % " ".join("0x%x 0x%x" % p for p in board))
        print("wrote %s" % out)


if __name__ == "__main__":
    main()
