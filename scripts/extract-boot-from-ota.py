#!/usr/bin/env python3
"""Extract the boot partition from a FULL Android A/B OTA (payload.bin), standard library only.

Usage: extract-boot-from-ota.py OTA.zip|payload.bin OUT.img [partition]

Reads only the pieces it needs, so a multi-gigabyte OTA zip is not unpacked. Supports full OTAs
(operations REPLACE, REPLACE_BZ, REPLACE_XZ, ZERO, DISCARD); an incremental/delta OTA is refused.
"""
import bz2
import hashlib
import io
import lzma
import struct
import sys
import zipfile

REPLACE, REPLACE_BZ, ZERO, DISCARD, REPLACE_XZ = 0, 1, 6, 7, 8


def varint(buf, pos):
    shift = value = 0
    while True:
        b = buf[pos]
        pos += 1
        value |= (b & 0x7F) << shift
        if not b & 0x80:
            return value, pos
        shift += 7


def fields(buf):
    """Yield (field number, value) for a protobuf message: ints for varints, bytes otherwise."""
    pos = 0
    while pos < len(buf):
        key, pos = varint(buf, pos)
        num, wire = key >> 3, key & 7
        if wire == 0:
            val, pos = varint(buf, pos)
        elif wire == 2:
            n, pos = varint(buf, pos)
            val, pos = buf[pos:pos + n], pos + n
        elif wire == 1:
            val, pos = buf[pos:pos + 8], pos + 8
        elif wire == 5:
            val, pos = buf[pos:pos + 4], pos + 4
        else:
            raise ValueError("unsupported protobuf wire type %d" % wire)
        yield num, val


def parse_op(buf):
    op = {"type": 0, "data_offset": 0, "data_length": 0, "dst": [], "sha": None}
    for num, val in fields(buf):
        if num == 1:
            op["type"] = val
        elif num == 2:
            op["data_offset"] = val
        elif num == 3:
            op["data_length"] = val
        elif num == 6:
            start = count = 0
            for n2, v2 in fields(val):
                if n2 == 1:
                    start = v2
                elif n2 == 2:
                    count = v2
            op["dst"].append((start, count))
        elif num == 8:
            op["sha"] = val
    return op


def parse_manifest(buf):
    block_size, parts = 4096, {}
    for num, val in fields(buf):
        if num == 3:
            block_size = val
        elif num == 13:
            name, ops = None, []
            for n2, v2 in fields(val):
                if n2 == 1:
                    name = v2.decode()
                elif n2 == 8:
                    ops.append(parse_op(v2))
            parts[name] = ops
    return block_size, parts


def open_payload(path):
    if zipfile.is_zipfile(path):
        zf = zipfile.ZipFile(path)
        if "payload.bin" not in zf.namelist():
            sys.exit("%s has no payload.bin; this needs a full A/B OTA zip" % path)
        return zf.open("payload.bin")
    return open(path, "rb")


def main():
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    want = sys.argv[3] if len(sys.argv) == 4 else "boot"

    f = open_payload(src)
    head = f.read(24)
    if head[:4] != b"CrAU":
        sys.exit("not an Android OTA payload (no CrAU magic)")
    version, manifest_size, sig_size = struct.unpack(">QQI", head[4:24])
    if version != 2:
        sys.exit("unsupported payload version %d" % version)
    block_size, parts = parse_manifest(f.read(manifest_size))
    if want not in parts:
        sys.exit("partition %r not in this payload; it has: %s" % (want, ", ".join(sorted(parts))))
    blob_start = 24 + manifest_size + sig_size

    out = io.BytesIO()
    for op in parts[want]:
        if op["type"] in (ZERO, DISCARD):
            continue  # unwritten space reads back as zeros
        if op["type"] not in (REPLACE, REPLACE_BZ, REPLACE_XZ):
            sys.exit("this is an incremental OTA (operation type %d); download the FULL OTA zip" % op["type"])
        f.seek(blob_start + op["data_offset"])
        data = f.read(op["data_length"])
        if op["sha"] and hashlib.sha256(data).digest() != op["sha"]:
            sys.exit("checksum mismatch in the OTA data: the download is corrupt")
        if op["type"] == REPLACE_BZ:
            data = bz2.decompress(data)
        elif op["type"] == REPLACE_XZ:
            data = lzma.decompress(data)
        pos = op["dst"][0][0] * block_size
        out.seek(pos)
        out.write(data)

    img = out.getvalue()
    if img[:8] != b"ANDROID!":
        sys.exit("extracted %s does not look like a boot image (no ANDROID! magic)" % want)
    with open(dst, "wb") as o:
        o.write(img)
    print("wrote %s (%d bytes, partition %s)" % (dst, len(img), want))


if __name__ == "__main__":
    main()
