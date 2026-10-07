#!/usr/bin/env python3
"""Convert a flat binary to a 32-bit-word .vmem file for $readmemh.

Equivalent to `srec_cat in.bin -binary -byte-swap 4 -o out.vmem -vmem`, without
needing srecord installed.
"""
import sys


def main(src: str, dst: str) -> None:
    data = open(src, "rb").read()
    data += b"\0" * (-len(data) % 4)
    with open(dst, "w") as f:
        f.write("@00000000\n")
        for i in range(0, len(data), 4):
            f.write(f"{int.from_bytes(data[i:i + 4], 'little'):08X}\n")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: bin2vmem.py in.bin out.vmem")
    main(sys.argv[1], sys.argv[2])
