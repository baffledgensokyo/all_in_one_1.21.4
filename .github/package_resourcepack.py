import hashlib
import shutil
import subprocess
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


PACK_ROOT = ("pack.mcmeta", "pack.png")
MAX_DOWNLOAD_BYTES = 250 * 1024 * 1024
ASSET_EXTENSIONS = {".fsh", ".frag", ".glsl", ".mcmeta", ".ogg", ".png", ".ttf", ".vsh"}
JSON_DIRECTORIES = {
    "atlases", "blockstates", "equipment", "font", "items", "lang",
    "models", "particles", "post_effect", "shaders",
}
LICENSES = {
    "assets/nvidium/licenses/GPL-3.0.txt",
    "assets/nvidium/licenses/LICENSE.txt",
    "assets/sodium/licenses/LICENSE.md",
}


def is_client_asset(name):
    parts = name.split("/")
    if len(parts) < 3:
        return False
    suffix = Path(name).suffix
    if suffix == ".json":
        return parts[2:] == ["sounds.json"] or (len(parts) > 3 and parts[2] in JSON_DIRECTORIES)
    return suffix in ASSET_EXTENSIONS or name in LICENSES


def package(output):
    root = Path(__file__).resolve().parents[1]
    tracked_assets = subprocess.check_output(
        ["git", "ls-files", "-z", "--", "assets"], cwd=root,
    ).decode("utf-8").split("\0")
    assets = sorted({name for name in tracked_assets if is_client_asset(name)})
    if not assets:
        raise SystemExit("No tracked client assets found.")

    with ZipFile(output, "w") as archive:
        for name in (*PACK_ROOT, *assets):
            source = root / name
            if source.is_symlink() or not source.is_file():
                raise SystemExit(f"Expected a regular file: {name}")
            entry = ZipInfo(name)
            entry.compress_type = ZIP_DEFLATED
            entry.external_attr = 0o100644 << 16
            entry.file_size = source.stat().st_size
            with source.open("rb") as original, archive.open(entry, "w") as compressed:
                shutil.copyfileobj(original, compressed, length=1024 * 1024)

    size = output.stat().st_size
    if size > MAX_DOWNLOAD_BYTES:
        output.unlink()
        raise SystemExit(f"Pack is {size / 1024**2:.1f} MiB. Minecraft's download limit is 250 MiB.")
    with output.open("rb") as archive_file:
        print(hashlib.file_digest(archive_file, "sha1").hexdigest())


if __name__ == "__main__":
    package(Path(sys.argv[1]))
