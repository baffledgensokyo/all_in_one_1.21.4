#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Варианты работы:
- insert-blanks: вставляет прозрачные 256x256 кадры перед/после каждого исходного.
- pad-inside: увеличивает КАЖДЫЙ кадр, добавляя внутри прозрачные зоны:
    по умолчанию: top=1, bottom=2, left=1, right=6 (итог: кадр 1024x2048 при базовом 256).
Требует: Pillow (pip install pillow)
"""

import argparse
import json
from PIL import Image

def load_frames_vertical(path, frame_size):
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    if w != frame_size or h % frame_size != 0:
        raise ValueError(
            f"Ожидался вертикальный спрайт-щит шириной {frame_size}px, "
            f"а получено {w}x{h}. Высота должна быть кратна {frame_size}."
        )
    n = h // frame_size
    return [img.crop((0, i*frame_size, frame_size, (i+1)*frame_size)) for i in range(n)]

def assemble_vertical(frames, frame_w, frame_h):
    out = Image.new("RGBA", (frame_w, frame_h * len(frames)), (0, 0, 0, 0))
    for i, fr in enumerate(frames):
        out.paste(fr, (0, i * frame_h))
    return out

def insert_blank_frames(frames, frame_size=256, blank_top=1, blank_bottom=2):
    blank = Image.new("RGBA", (frame_size, frame_size), (0, 0, 0, 0))
    out = []
    for fr in frames:
        out.extend([blank.copy() for _ in range(blank_top)])
        out.append(fr)
        out.extend([blank.copy() for _ in range(blank_bottom)])
    return out

def pad_inside_each_frame(
    frames,
    base_size=256,
    pad_top_blocks=1,
    pad_bottom_blocks=2,
    pad_left_blocks=1,
    pad_right_blocks=6,
):
    """Возвращает (список_увеличенных_кадров, new_w, new_h)."""
    new_w = (pad_left_blocks + 1 + pad_right_blocks) * base_size
    new_h = (pad_top_blocks + 1 + pad_bottom_blocks) * base_size
    out = []
    for fr in frames:
        canvas = Image.new("RGBA", (new_w, new_h), (0, 0, 0, 0))
        # Позиция оригинального 256x256 внутри нового кадра:
        x = pad_left_blocks * base_size
        y = pad_top_blocks * base_size
        canvas.paste(fr, (x, y))
        out.append(canvas)
    return out, new_w, new_h

def write_mcmeta(path_png, frametime=5, interpolate=False, width=None, height=None, frames=None):
    meta = {"animation": {"frametime": int(frametime)}}
    if interpolate:
        meta["animation"]["interpolate"] = True
    if width is not None:
        meta["animation"]["width"] = int(width)
    if height is not None:
        meta["animation"]["height"] = int(height)
    if frames is not None:
        meta["animation"]["frames"] = list(frames)
    with open(f"{path_png}.mcmeta", "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

def main():
    ap = argparse.ArgumentParser(description="Работа со спрайт-листом Minecraft (вертикальная лента).")
    ap.add_argument("--in", dest="in_path", default="mellstroy.png", help="Путь к исходному вертикальному спрайт-листу (PNG).")
    ap.add_argument("--out", dest="out_path", default="mellstroy_out.png", help="Куда сохранить результат (PNG).")
    ap.add_argument("--frame-size", type=int, default=256, help="Размер исходного кадра (квадрат), по умолчанию 256.")
    ap.add_argument("--mode", choices=["insert-blanks", "pad-inside"], default="pad-inside",
                    help="insert-blanks — вставляет пустые кадры между; pad-inside — подложка внутри каждого кадра.")
    # Параметры для insert-blanks
    ap.add_argument("--blank-top", type=int, default=1, help="Сколько пустых кадров вставлять сверху (insert-blanks).")
    ap.add_argument("--blank-bottom", type=int, default=2, help="Сколько пустых кадров вставлять снизу (insert-blanks).")
    # Параметры для pad-inside
    ap.add_argument("--pad-top", type=int, default=1, help="Подложка сверху в блоках base_size (pad-inside).")
    ap.add_argument("--pad-bottom", type=int, default=2, help="Подложка снизу в блоках base_size (pad-inside).")
    ap.add_argument("--pad-left", type=int, default=1, help="Подложка слева в блоках base_size (pad-inside).")
    ap.add_argument("--pad-right", type=int, default=6, help="Подложка справа в блоках base_size (pad-inside).")

    ap.add_argument("--frametime", type=int, default=5, help="frametime для .mcmeta (тики на кадр, 20 тиков = 1с).")
    ap.add_argument("--no-mcmeta", action="store_true", help="Не создавать .png.mcmeta.")
    args = ap.parse_args()

    frames = load_frames_vertical(args.in_path, args.frame_size)

    if args.mode == "insert-blanks":
        seq = insert_blank_frames(frames, frame_size=args.frame_size,
                                  blank_top=args.blank_top, blank_bottom=args.blank_bottom)
        out_img = assemble_vertical(seq, args.frame_size, args.frame_size)
        out_img.save(args.out_path)
        if not args.no_mcmeta:
            write_mcmeta(args.out_path, frametime=args.frametime)
    else:
        # pad-inside: делаем кадры  (pad_left + 1 + pad_right)*size  на  (pad_top + 1 + pad_bottom)*size
        padded_frames, new_w, new_h = pad_inside_each_frame(
            frames,
            base_size=args.frame_size,
            pad_top_blocks=args.pad_top,
            pad_bottom_blocks=args.pad_bottom,
            pad_left_blocks=args.pad_left,
            pad_right_blocks=args.pad_right,
        )
        out_img = assemble_vertical(padded_frames, new_w, new_h)
        out_img.save(args.out_path)
        if not args.no_mcmeta:
            write_mcmeta(args.out_path, frametime=args.frametime, width=new_w, height=new_h)

    print(f"Готово: {args.out_path}")

if __name__ == "__main__":
    main()
