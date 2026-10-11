#!/usr/bin/env python3
"""Draw the Ichido disk-image background: paper, with an arrow between the icons.

The Finder window is 660 by 400. Ichido sits at (180, 190) and Applications at
(480, 190). The arrow occupies the gap so the drop direction is obvious.
"""

import struct
import zlib
from pathlib import Path

WIDTH = 660
HEIGHT = 400
PAPER = (0xF4, 0xF1, 0xE9)
BLUE = (0x28, 0x48, 0xE8)


def inside_arrow(x, y):
    shaft = 268 <= x <= 352 and 183 <= y <= 197
    # Tip at x=404, y=190, in line with the icon positions. The base is x=344.
    if x < 344 or x > 404:
        return shaft
    half = (404 - x) * (28 / 60)
    return abs(y - 190) <= half or shaft


def pixel(x, y):
    samples = 0
    for sy in range(4):
        for sx in range(4):
            if inside_arrow(x + (sx + 0.5) / 4, y + (sy + 0.5) / 4):
                samples += 1
    if samples == 0:
        return PAPER
    cover = samples / 16
    return tuple(round(PAPER[i] + (BLUE[i] - PAPER[i]) * cover) for i in range(3))


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def main():
    raw = bytearray()
    for y in range(HEIGHT):
        raw.append(0)
        for x in range(WIDTH):
            raw.extend(pixel(x, y))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", WIDTH, HEIGHT, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    destination = Path(__file__).resolve().parent.parent / "Resources" / "dmg-background.png"
    destination.write_bytes(png)
    print(f"Wrote {destination} ({WIDTH}x{HEIGHT})")


if __name__ == "__main__":
    main()
