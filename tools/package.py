"""Build the LumenUI addon zip with only runtime files and its install guide."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


def package():
    root = Path(__file__).resolve().parents[1]
    addon = root / "LumenUI"
    required = ["LumenUI.toc", "Core.lua", "Style.lua", "Actions.lua", "Dock.lua", "Layout.lua", "Skins.lua", "Editor.lua"]
    textures = sorted(path.relative_to(addon).as_posix() for path in (addon / "Textures").rglob("*.tga"))
    if len(textures) != 14:
        raise RuntimeError("Expected Circle, Shadow, and 12 dock icon textures; run tools/generate_textures.py")
    required.extend(textures)
    for name in required:
        if not (addon / name).is_file():
            raise FileNotFoundError(f"Missing addon file: {name}")
    destination = root / "dist" / "LumenUI.zip"
    destination.parent.mkdir(exist_ok=True)
    with ZipFile(destination, "w", compression=ZIP_DEFLATED) as archive:
        for name in required:
            archive.write(addon / name, f"LumenUI/{name}")
        archive.write(root / "README.md", "LumenUI/README.md")
    with ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("Archive verification failed")
    print(destination)


if __name__ == "__main__":
    package()
