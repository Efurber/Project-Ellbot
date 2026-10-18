"""Generate only LumenUI's original RGBA masks and monoline dock icons.

All assets use deterministic procedural geometry, without external artwork,
third-party images, logos, fonts, or image-library dependencies.
"""

import math
from pathlib import Path
import struct


def write_texture(path, width, height, alpha):
    """Write uncompressed BGRA pixels: top-left origin, eight alpha bits."""
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    pixels = bytearray()
    for y in range(height):
        for x in range(width):
            opacity = round(255 * max(0, min(1, alpha((x + 0.5) / width, (y + 0.5) / height))))
            pixels.extend((255, 255, 255, opacity))
    path.write_bytes(header + pixels)


def circle(x, y):
    """A one-pixel antialiased circular edge at the 128-pixel output size."""
    radius = math.hypot(x - 0.5, y - 0.5) * 2
    return max(0, min(1, (1 - radius) * 64 + 0.5))


def shadow(x, y):
    """Opaque core with a radial feather, also sampled for nine-slice edges."""
    radius = math.hypot(x - 0.5, y - 0.5) * 2
    coverage = max(0, min(1, (1 - radius) / 0.22))
    return coverage * coverage * (3 - 2 * coverage)


class Drawing:
    """Small signed-distance canvas, with round-ended 2.25-pixel strokes."""

    def __init__(self):
        self.shapes = []

    def line(self, x1, y1, x2, y2, width=2.25):
        dx, dy = x2 - x1, y2 - y1
        length_squared = dx * dx + dy * dy

        def sample(x, y):
            position = max(0, min(1, ((x - x1) * dx + (y - y1) * dy) / length_squared))
            return math.hypot(x - x1 - position * dx, y - y1 - position * dy) - width / 2

        self.shapes.append(sample)
        return self

    def path(self, points, closed=False, width=2.25):
        for first, second in zip(points, points[1:]):
            self.line(*first, *second, width)
        if closed:
            self.line(*points[-1], *points[0], width)
        return self

    def circle(self, cx, cy, radius, width=2.25, filled=False):
        def sample(x, y):
            distance = math.hypot(x - cx, y - cy) - radius
            return distance if filled else abs(distance) - width / 2

        self.shapes.append(sample)
        return self

    def rect(self, x, y, width, height, radius=3, stroke=2.25):
        def sample(px, py):
            dx = abs(px - x - width / 2) - width / 2 + radius
            dy = abs(py - y - height / 2) - height / 2 + radius
            distance = math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius
            return abs(distance) - stroke / 2

        self.shapes.append(sample)
        return self

    def arc(self, cx, cy, rx, ry, start=math.pi, end=math.tau, width=2.25):
        points = [
            (cx + math.cos(start + (end - start) * step / 24) * rx,
             cy + math.sin(start + (end - start) * step / 24) * ry)
            for step in range(25)
        ]
        return self.path(points, width=width)

    def alpha(self, x, y):
        distance = min(shape(x * 64, y * 64) for shape in self.shapes)
        return max(0, min(1, 0.5 - distance))


def icons():
    character = Drawing().circle(32, 21, 7)
    character.arc(32, 46, 14, 12).path([(18, 46), (18, 50), (46, 50), (46, 46)])

    bags = Drawing().rect(17, 23, 30, 29, 4)
    bags.arc(32, 23, 8, 9).line(25, 31, 25, 34).line(39, 31, 39, 34)

    spells = Drawing().rect(14, 17, 36, 34, 3).line(32, 18, 32, 49)
    spells.path([(20, 27), (25, 25), (27, 25)]).path([(37, 25), (39, 25), (44, 27)])
    spells.line(20, 34, 27, 34).line(37, 34, 44, 34).line(20, 41, 27, 41).line(37, 41, 44, 41)

    talents = Drawing()
    for x, y in ((32, 15), (22, 31), (42, 31), (15, 48), (30, 48), (49, 48)):
        talents.circle(x, y, 3.5)
    for segment in ((30, 19, 24, 27), (34, 19, 40, 27), (20, 35, 17, 44),
                    (24, 35, 28, 44), (44, 35, 47, 44)):
        talents.line(*segment)

    quests = Drawing().rect(17, 14, 31, 39, 4).rect(25, 10, 15, 8, 3)
    quests.path([(23, 27), (25, 29), (29, 24)]).line(34, 27, 41, 27)
    quests.path([(23, 39), (25, 41), (29, 36)]).line(34, 39, 41, 39)

    map_icon = Drawing().path([(12, 19), (25, 13), (39, 19), (52, 13),
                               (52, 45), (39, 51), (25, 45), (12, 51)], closed=True)
    map_icon.line(25, 13, 25, 45).line(39, 19, 39, 51)

    social = Drawing().circle(24, 22, 6).circle(43, 24, 5)
    social.arc(24, 45, 12, 12).path([(12, 45), (12, 49), (36, 49), (36, 45)])
    social.arc(43, 45, 10, 11, start=math.pi * 1.38).path([(53, 45), (53, 49), (42, 49)])

    guild = Drawing().path([(32, 12), (49, 18), (47, 35), (42, 45), (32, 52),
                            (22, 45), (17, 35), (15, 18)], closed=True)
    guild.path([(32, 23), (39, 32), (32, 41), (25, 32)], closed=True)

    calendar = Drawing().rect(14, 17, 36, 35, 5).line(15, 27, 49, 27)
    calendar.line(24, 12, 24, 22).line(40, 12, 40, 22)
    for x, y in ((23, 35), (32, 35), (41, 35), (23, 44), (32, 44), (41, 44)):
        calendar.circle(x, y, 1.4, filled=True)

    menu = Drawing().line(17, 21, 47, 21).line(17, 32, 47, 32).line(17, 43, 47, 43)

    layout = Drawing()
    for x, y in ((15, 15), (35, 15), (15, 35), (35, 35)):
        layout.rect(x, y, 14, 14, 3)

    settings = Drawing()
    gear = []
    for tooth in range(8):
        for angle_offset, radius in ((-0.5, 13), (-0.24, 17), (0.24, 17), (0.5, 13)):
            angle = (tooth + angle_offset) * math.tau / 8
            gear.append((32 + math.cos(angle) * radius, 32 + math.sin(angle) * radius))
    # Adjacent tooth endpoints coincide; omit duplicate points before drawing.
    gear = [point for index, point in enumerate(gear)
            if index == 0 or math.hypot(point[0] - gear[index - 1][0],
                                        point[1] - gear[index - 1][1]) > 0.001]
    if math.hypot(gear[-1][0] - gear[0][0], gear[-1][1] - gear[0][1]) < 0.001:
        gear.pop()
    settings.path(gear, closed=True).circle(32, 32, 5.5)

    return {
        "Character": character, "Bags": bags, "Spells": spells, "Talents": talents,
        "Quests": quests, "Map": map_icon, "Social": social, "Guild": guild,
        "Calendar": calendar, "Menu": menu, "Layout": layout, "Settings": settings,
    }


def generate():
    destination = Path(__file__).resolve().parents[1] / "LumenUI" / "Textures"
    destination.mkdir(parents=True, exist_ok=True)
    for name, sampler in (("Circle", circle), ("Shadow", shadow)):
        write_texture(destination / (name + ".tga"), 128, 128, sampler)
    icon_directory = destination / "Icons"
    icon_directory.mkdir(exist_ok=True)
    for name, drawing in icons().items():
        write_texture(icon_directory / (name + ".tga"), 64, 64, drawing.alpha)


if __name__ == "__main__":
    generate()
