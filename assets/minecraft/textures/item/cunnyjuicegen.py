#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from PIL import Image
import sys
from pathlib import Path

def tile_block_4x(block16: Image.Image) -> Image.Image:
    """
    Из одного квадрата 16×16 собрать квадрат 64×64 путём 4×4 тайлинга,
    а не масштабирования пикселей.
    """
    w, h = block16.size
    assert w == 16 and h == 16, f"Ожидался блок 16×16, получено {w}×{h}"
    out = Image.new(block16.mode, (64, 64))
    for ty in range(4):
        for tx in range(4):
            out.paste(block16, (tx * 16, ty * 16))
    return out

def process(src_path: Path, dst_path: Path, tile_size: int = 16, repeat: int = 4):
    im = Image.open(src_path)
    w, h = im.size

    # Базовые проверки
    if w != tile_size:
        raise ValueError(f"Ширина исходника должна быть {tile_size}px, сейчас {w}px.")
    if h % tile_size != 0:
        raise ValueError(f"Высота должна быть кратна {tile_size}px, сейчас {h}px.")

    num_tiles_vert = h // tile_size
    out_w = tile_size * repeat               # 16*4 = 64
    out_h = num_tiles_vert * tile_size * repeat  # 32*16*4 = 2048 для 16×512

    out = Image.new(im.mode, (out_w, out_h))

    # Идём сверху вниз по блокам 16×16
    for i in range(num_tiles_vert):
        top = i * tile_size
        block16 = im.crop((0, top, tile_size, top + tile_size))
        block64 = tile_block_4x(block16)
        out.paste(block64, (0, i * (tile_size * repeat)))

    out.save(dst_path)
    print(f"Готово: {dst_path} ({out.size[0]}×{out.size[1]})")

if __name__ == "__main__":
    # Использование:
    #   python make_tiled_texture.py [вход=./cunnyjuice.png] [выход=./cunnyjuice_tiled.png]
    src = Path(sys.argv[1]) if len(sys.argv) >= 2 else Path("cunnyjuice.png")
    dst = Path(sys.argv[2]) if len(sys.argv) >= 3 else Path("cunnyjuice_tiled.png")
    process(src, dst)
