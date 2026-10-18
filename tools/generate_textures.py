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


def flame(x, y):
    """An asymmetric, tapered flame with two smaller tongues."""
    center = 0.51 + 0.09 * math.sin(y * 7.5)
    width = 0.018 + 0.25 * y ** 1.3
    main = max(0, 1 - abs(x - center) / width) ** 1.4
    side = max(0, 1 - abs(x - (0.33 + 0.08 * y)) / (0.018 + 0.12 * y)) ** 2
    small = max(0, 1 - abs(x - (0.68 - 0.07 * y)) / (0.014 + 0.10 * y)) ** 2
    return max(main, side * 0.65, small * 0.5) * math.sin(math.pi * y) ** 0.65


def frost_spark(x, y):
    dx, dy = (x - 0.5) * 2, (y - 0.5) * 2
    radius = math.hypot(dx, dy)
    angle = math.atan2(dy, dx)
    branches = max(0, math.cos(angle * 6)) ** 26
    core = math.exp(-radius * radius * 130)
    rays = branches * math.exp(-radius * 2.8) * max(0, 1 - radius)
    return min(1, core + rays * 1.8)


def frost_shard(x, y):
    diamond = abs(x - 0.5) / 0.21 + abs(y - 0.5) / 0.48
    body = max(0, 1 - diamond) ** 0.65
    facet = math.exp(-((x - 0.5) * 65) ** 2) * max(0, 1 - abs(y - 0.5) / 0.48)
    return min(1, body * 0.8 + facet * 0.5)


def arcane_rune(x, y):
    dx, dy = x - 0.5, y - 0.5
    radius = math.hypot(dx, dy)
    angle = math.atan2(dy, dx)
    outer = math.exp(-((radius - 0.35) / 0.012) ** 2)
    inner = math.exp(-((radius - 0.25) / 0.009) ** 2)
    glyphs = math.exp(-((radius - 0.30) / 0.026) ** 2) * max(0, math.cos(angle * 8)) ** 12
    diamond = math.exp(-((abs(dx) + abs(dy) - 0.13) / 0.014) ** 2)
    return min(1, outer * 0.7 + inner * 0.5 + glyphs + diamond * 0.85)


def smoke_density(x, y):
    """Overlapping soft lobes form an original, deterministic billowing cloud."""
    blobs = (
        (0.48, 0.50, 0.23, 0.9), (0.31, 0.39, 0.15, 0.7),
        (0.65, 0.37, 0.17, 0.8), (0.67, 0.61, 0.14, 0.65),
        (0.40, 0.69, 0.16, 0.8), (0.23, 0.57, 0.11, 0.5),
    )
    clear = 1.0
    for cx, cy, radius, strength in blobs:
        density = strength * math.exp(-((x - cx) ** 2 + (y - cy) ** 2) / radius ** 2)
        clear *= 1 - density
    envelope = math.sin(math.pi * x) * math.sin(math.pi * y)
    detail = 0.87 + 0.08 * math.sin(x * 31 + y * 11) + 0.05 * math.cos(y * 37 - x * 9)
    return max(0, min(1, (1 - clear) * envelope ** 0.5 * detail))


def smoke_rim(x, y):
    density = smoke_density(x, y)
    return math.exp(-((density - 0.25) / 0.065) ** 2) * min(1, density * 8) * 0.8


def generate():
    destination = Path(__file__).resolve().parents[1] / "ForeverXP" / "Textures"
    destination.mkdir(parents=True, exist_ok=True)
    write_texture(destination / "Glow.tga", 64, 64,
                  lambda x, y: max(0, math.exp(-((x - 0.5) ** 2 * 42 + (y - 0.5) ** 2 * 18)) - 0.012))
    write_texture(destination / "Shine.tga", 64, 32,
                  lambda x, y: math.sin(math.pi * x) ** 8 * math.sin(math.pi * y) ** 2)
    for name, sampler in (
        ("Flame", flame), ("FrostSpark", frost_spark), ("FrostShard", frost_shard),
        ("ArcaneRune", arcane_rune), ("Smoke", smoke_density), ("SmokeRim", smoke_rim),
    ):
        write_texture(destination / (name + ".tga"), 64, 64, sampler)


if __name__ == "__main__":
    generate()
