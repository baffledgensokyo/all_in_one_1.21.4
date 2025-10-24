#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from PIL import Image

# отключаем ограничение Pillow на большие изображения
Image.MAX_IMAGE_PIXELS = None

def halve_bicubic(in_path="mellstroy.png", out_path="mellstroy_halved.png"):
    img = Image.open(in_path).convert("RGBA")  # сохраняем альфу
    w, h = img.size
    new_w = max(1, w // 2)
    new_h = max(1, h // 2)
    img_resized = img.resize((new_w, new_h), resample=Image.BICUBIC)
    img_resized.save(out_path, optimize=True)
    print(f"Сохранено: {out_path} ({new_w}x{new_h})")

if __name__ == "__main__":
    halve_bicubic()
