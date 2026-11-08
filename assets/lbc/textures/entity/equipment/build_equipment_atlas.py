#!/usr/bin/env python3
"""Build the TMT armor source atlas. Copy this file into textures/entity/equipment.

Python 3.10+ and Pillow: py -m pip install Pillow
No downloads, Minecraft mods, shader changes or project checkout are required.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import ExitStack
import hashlib
import io
import json
import math
from pathlib import Path
import random
import secrets
import sys
import tempfile
import zipfile

try:
    from PIL import Image
except ImportError:
    raise SystemExit("Pillow is required. Run: py -m pip install Pillow")

MARKER = (31, 197, 83, 255)
OUTPUTS = ("humanoid/tmt/procedural.png", "humanoid_leggings/tmt/procedural.png")
REPORT = "tmt_atlas_build.json"
ZERO_ALPHA_MASK = [255] + [0] * 255


def atomic_write(target: Path, data: bytes):
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".tmt-", suffix=".tmp", delete=False) as temporary:
            staged = Path(temporary.name)
            temporary.write(data)
        staged.replace(target)
    finally:
        if staged is not None:
            staged.unlink(missing_ok=True)


def texture_path(name: str) -> bool:
    parts = name.split("/")
    return len(parts) >= 4 and parts[0] == "assets" and parts[2] == "textures" and name.lower().endswith(".png")


def find_pack(start: Path) -> Path:
    for parent in (start, *start.parents):
        if (parent / "pack.mcmeta").is_file() and (parent / "assets").is_dir():
            return parent
    for parent in (start, *start.parents):
        if parent.name == "assets":
            return parent.parent
    raise ValueError("Put the script in assets/lbc/textures/entity/equipment, or pass --pack PATH.")


def version_of(pack: Path) -> str | None:
    for parent in pack.parents:
        config = parent / "mmc-pack.json"
        if config.is_file():
            for component in json.loads(config.read_text(encoding="utf-8-sig")).get("components", []):
                if component.get("uid") == "net.minecraft":
                    return component.get("version")
    return None


def vanilla_jar(pack: Path) -> Path:
    version = version_of(pack)
    candidates = []
    for parent in pack.parents:
        if version:
            # Prism/MultiMC/FreesmLauncher and the official launcher.
            candidates.extend((
                parent / f"libraries/com/mojang/minecraft/{version}/minecraft-{version}-client.jar",
                parent / f"versions/{version}/{version}.jar",
            ))
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise ValueError("Cannot find the matching Minecraft client JAR. Pass --vanilla-jar PATH (no download is performed).")


def frame_boxes(image: Image.Image, metadata: dict):
    animation = metadata.get("animation")
    if not isinstance(animation, dict):
        yield (0, 0, image.width, image.height)
        return
    width, height = animation.get("width"), animation.get("height")
    if width is None and height is None:
        width = height = min(image.size)
    else:
        width = image.width if width is None else width
        height = image.height if height is None else height
    if (type(width) is not int or type(height) is not int or width <= 0 or height <= 0
            or image.width % width or image.height % height):
        raise ValueError(f"Invalid animation frame dimensions {width}x{height} for {image.size}")
    # Include every physical frame, even frames not used by the playback order.
    for y in range(0, image.height, height):
        for x in range(0, image.width, width):
            yield x, y, x + width, y + height


def normalize(tile: Image.Image, size: int) -> bytes | None:
    alpha = tile.getchannel("A")
    bounds = alpha.getbbox()
    if bounds is None:
        return None
    tile = tile.crop(bounds)
    tile = tile.resize((size, size), Image.Resampling.NEAREST)
    # Hidden RGB under zero alpha has no visible meaning and must not defeat deduplication.
    tile.paste((0, 0, 0, 0), mask=tile.getchannel("A").point(ZERO_ALPHA_MASK))
    return tile.tobytes()


def tiles(image: Image.Image, metadata: dict, cell: int, source_size: int, stats: Counter):
    for box in frame_boxes(image, metadata):
        stats["frames"] += 1
        with image.crop(box).convert("RGBA") as frame:
            bounds = frame.getchannel("A").getbbox()
            if bounds is None:
                stats["transparentFrames"] += 1
                continue
            with frame.crop(bounds) as visible:
                # Keep all native low-resolution pixels; bound HD skins/GUI images.
                visible.thumbnail((source_size, source_size), Image.Resampling.BOX)
                # BOX can round away an exceptionally sparse high-resolution texture.
                if visible.getchannel("A").getbbox() is None:
                    row = frame.getchannel("A").crop((bounds[0], bounds[1], bounds[2], bounds[1] + 1)).getbbox()
                    visible.paste(frame.getpixel((bounds[0] + row[0], bounds[1])), (0, 0, *visible.size))
                    stats["sparseFallbacks"] += 1
                for y in range(0, visible.height, cell):
                    for x in range(0, visible.width, cell):
                        with visible.crop((x, y, min(x + cell, visible.width), min(y + cell, visible.height))) as part:
                            pixels = normalize(part, cell)
                        if pixels is not None:
                            yield pixels


def build(pack: Path, jar: Path, output: Path, cell: int = 16, source_size: int = 64,
          max_side: int = 8192, seed: int | None = None) -> dict:
    pack, jar, output = pack.resolve(), jar.resolve(), output.resolve()
    if not (pack / "assets").is_dir():
        raise ValueError(f"No assets directory: {pack}")
    if cell < 1 or source_size < cell or max_side < cell:
        raise ValueError("Require 1 <= tile-size <= source-size, and max-side >= tile-size.")
    seed = secrets.randbits(64) if seed is None else seed
    rng = random.Random(seed)
    stats = Counter()
    records = []
    excluded = {f"assets/lbc/textures/entity/equipment/{name}" for name in OUTPUTS}
    generated_paths = {(output / name).resolve() for name in OUTPUTS}
    # One disk-backed pixel store: never retain thousands of PIL images in RAM.
    with ExitStack() as stack:
        archive = stack.enter_context(zipfile.ZipFile(jar))
        spool = stack.enter_context(tempfile.TemporaryFile())
        unique = {}
        stride = cell * cell * 4
        capacity = (max_side // cell) ** 2

        def consume(name, stream, metadata):
            stats["inputTextures"] += 1
            contributed = 0
            visible_pixels = False
            try:
                with Image.open(stream) as image:
                    if image.width * image.height > 64 * 1024 * 1024:
                        raise ValueError("Texture exceeds 64 million pixels; reduce this source image first.")
                    for pixels in tiles(image, metadata, cell, source_size, stats):
                        visible_pixels = True
                        stats["nonemptyTiles"] += 1
                        key = hashlib.sha256(pixels).digest()
                        if key in unique:
                            stats["duplicateTiles"] += 1
                            continue
                        if len(unique) >= capacity:
                            raise ValueError("All unique tiles exceed --max-side. Increase it, or reduce --source-size/--tile-size. Nothing was replaced.")
                        unique[key] = len(unique)
                        spool.write(pixels)
                        contributed += 1
            except Exception as error:
                raise ValueError(f"{name}: {error}") from error
            if not visible_pixels:
                stats["transparentTextures"] += 1
            records.append({"source": name, "newTiles": contributed})

        def meta(data):
            value = json.loads(data.decode("utf-8-sig"))
            if not isinstance(value, dict):
                raise ValueError("Texture metadata must be an object")
            return value

        names = set(archive.namelist())
        vanilla_textures = sorted(n for n in names if texture_path(n) and n not in excluded)
        if not vanilla_textures:
            raise ValueError("The selected JAR contains no vanilla texture PNGs. Use the client JAR.")
        for name in vanilla_textures:
            metadata = meta(archive.read(name + ".mcmeta")) if name + ".mcmeta" in names else {}
            with archive.open(name) as stream:
                consume("vanilla:" + name, stream, metadata)
        roots = [pack / "assets"]
        pack_metadata = pack / "pack.mcmeta"
        if pack_metadata.is_file():
            for entry in json.loads(pack_metadata.read_text(encoding="utf-8-sig")).get("overlays", {}).get("entries", []):
                directory = (pack / entry["directory"]).resolve()
                if not directory.is_relative_to(pack):
                    raise ValueError("Overlay directory must stay inside this resource pack.")
                if directory / "assets" not in roots:
                    roots.append(directory / "assets")
        for path in sorted(p for root in roots for p in root.glob("*/textures/**/*")):
            if not path.is_file() or path.suffix.lower() != ".png":
                continue
            relative = path.relative_to(pack).as_posix()
            # Never feed a previous generated atlas (or an output under this pack) into itself.
            if (relative in excluded or any(relative.endswith("/" + name) for name in excluded)
                    or path.resolve() in generated_paths):
                continue
            metadata_path = path.with_name(path.name + ".mcmeta")
            metadata = meta(metadata_path.read_bytes()) if metadata_path.is_file() else {}
            with path.open("rb") as stream:
                consume("pack:" + relative, stream, metadata)
        count = len(unique)
        if not count:
            raise ValueError("No nontransparent texture pixels found; existing atlases were not replaced.")
        # A near-square rectangle wastes at most one row; powers of two are unnecessary here.
        columns = math.isqrt(count)
        if columns * columns < count:
            columns += 1
        rows = (count + columns - 1) // columns
        if columns * cell > max_side or rows * cell > max_side:
            raise ValueError("Atlas exceeds --max-side; nothing was replaced.")
        order = list(range(count))
        rng.shuffle(order)
        with Image.new("RGBA", (columns * cell, rows * cell)) as atlas:
            for position in range(columns * rows):
                # Fill the tiny last-row slack with existing art, never transparent empty tiles.
                index = order[position] if position < count else rng.randrange(count)
                spool.seek(index * stride)
                with Image.frombytes("RGBA", (cell, cell), spool.read(stride)) as tile:
                    atlas.paste(tile, ((position % columns) * cell, (position // columns) * cell))
            # One reserved texel; existing entity shaders read this exact signature at LOD0.
            atlas.putpixel((0, 0), MARKER)
            encoded = io.BytesIO()
            atlas.save(encoded, format="PNG", optimize=True, compress_level=9)
            png = encoded.getvalue()
            dimensions = list(atlas.size)
        result = {
            "format": "lbc-tmt-equipment-atlas-v1", "seed": seed,
            "vanillaJar": str(jar), "pack": str(pack), "tileSize": cell,
            "maxSourceDimension": source_size, "size": dimensions,
            "uniqueTiles": count, "paddingTiles": columns * rows - count,
            "rgbaGpuBytesPerLayer": dimensions[0] * dimensions[1] * 4,
            "rgbaGpuBytesBothLayers": dimensions[0] * dimensions[1] * 8,
            "pngBytesPerLayer": len(png), "pngSha256": hashlib.sha256(png).hexdigest(),
            "statistics": dict(stats), "sources": records,
        }
        # Everything is decoded and validated before touching any existing generated file.
        output.mkdir(parents=True, exist_ok=True)
        for name in OUTPUTS:
            atomic_write(output / name, png)
        atomic_write(output / REPORT, (json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
        return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack", type=Path, help="Resource pack root (auto-detected from script location)")
    parser.add_argument("--vanilla-jar", type=Path, help="Minecraft client JAR (auto-detected for Freesm/Prism/MultiMC)")
    parser.add_argument("--output", type=Path, help="Equipment directory; default: this pack's assets/lbc/textures/entity/equipment")
    parser.add_argument("--seed", type=int, help="Reproduce a shuffle; default: a new random seed each run")
    parser.add_argument("--tile-size", type=int, default=16, help="Tile pixels; default16")
    parser.add_argument("--source-size", type=int, default=64, help="Maximum detail dimension per source frame; default64")
    parser.add_argument("--max-side", type=int, default=8192, help="Fail rather than omit textures beyond this atlas dimension")
    args = parser.parse_args(argv)
    try:
        pack = args.pack.resolve() if args.pack else find_pack(Path(__file__).resolve().parent)
        jar = args.vanilla_jar or vanilla_jar(pack)
        output = args.output or pack / "assets/lbc/textures/entity/equipment"
        result = build(pack, jar, output, args.tile_size, args.source_size, args.max_side, args.seed)
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print(f"Textures: {result['statistics']['inputTextures']}; unique tiles: {result['uniqueTiles']}")
    print(f"Atlas: {result['size'][0]} x {result['size'][1]}; seed: {result['seed']}")
    print(f"GPU memory, both layers (RGBA8, no mipmaps): {result['rgbaGpuBytesBothLayers'] / 1048576:.2f} MiB")
    print(f"PNG, each layer: {result['pngBytesPerLayer'] / 1048576:.2f} MiB")
    print(f"Written to: {output.resolve()}\nReload the pack with F3+T after the build completes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
