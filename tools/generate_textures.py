"""Generate original, uncompressed power-of-two TGA assets understood by WoW."""

import math
from pathlib import Path
import struct


def write_texture(path, width, height, alpha):
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            opacity = round(255 * max(0, min(1, alpha((x + 0.5) / width, (y + 0.5) / height))))
            pixels.extend((255, 255, 255, opacity))
    path.write_bytes(header + pixels)


def generate():
    destination = Path(__file__).resolve().parents[1] / "ForeverXP" / "Textures"
    destination.mkdir(parents=True, exist_ok=True)
    write_texture(destination / "Glow.tga", 64, 64,
                  lambda x, y: max(0, math.exp(-((x - 0.5) ** 2 * 42 + (y - 0.5) ** 2 * 18)) - 0.012))
    write_texture(destination / "Shine.tga", 64, 32,
                  lambda x, y: math.sin(math.pi * x) ** 8 * math.sin(math.pi * y) ** 2)


if __name__ == "__main__":
    generate()
