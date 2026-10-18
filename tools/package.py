"""Build an installable addon zip with only its runtime files."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def package():
    root = Path(__file__).resolve().parents[1]
    addon = root / "ForeverXP"
    required = [
        "ForeverXP.toc", "Core.lua", "Effects.lua", "NativeBar.lua", "Options.lua", "Minimap.lua",
        "Textures/Glow.tga", "Textures/Shine.tga", "Textures/Flame.tga",
        "Textures/FrostSpark.tga", "Textures/FrostShard.tga", "Textures/ArcaneRune.tga",
        "Textures/Smoke.tga", "Textures/SmokeRim.tga",
    ]
    for name in required:
        if not (addon / name).is_file():
            raise FileNotFoundError(f"Missing addon file: {name}")
    destination = root / "dist" / "ForeverXP.zip"
    destination.parent.mkdir(exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        for name in required:
            archive.write(addon / name, f"ForeverXP/{name}")
        archive.write(root / "README.md", "ForeverXP/README.md")
    with ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Archive verification failed")
    print(destination)


if __name__ == "__main__":
    package()
