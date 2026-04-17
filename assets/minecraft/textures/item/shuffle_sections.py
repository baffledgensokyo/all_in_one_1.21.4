from pathlib import Path
import random

from PIL import Image


SOURCE_IMAGE = Path("assets/minecraft/textures/item/omegaflag.png")
OUTPUT_IMAGE = None
SECTION_SIZE = 16
COPIES_PER_SECTION = 8
RANDOM_SEED = None


def reflect_anti_diagonal(tile: Image.Image) -> Image.Image:
    return tile.transpose(Image.Transpose.TRANSVERSE)


def reflect_main_diagonal(tile: Image.Image) -> Image.Image:
    return tile.transpose(Image.Transpose.TRANSPOSE)


def build_output_path(source_path: Path) -> Path:
    if OUTPUT_IMAGE is not None:
        return Path(OUTPUT_IMAGE)
    return source_path.with_name(f"{source_path.stem}_shuffled.png")


def validate_source_image(image: Image.Image) -> int:
    width, height = image.size
    if width != SECTION_SIZE:
        raise ValueError(
            f"Ширина PNG должна быть {SECTION_SIZE}px, сейчас {width}px."
        )
    if height % SECTION_SIZE != 0:
        raise ValueError(
            f"Высота PNG должна быть кратна {SECTION_SIZE}px, сейчас {height}px."
        )
    return height // SECTION_SIZE


def extract_sections(image: Image.Image, section_count: int) -> list[Image.Image]:
    sections = []
    for index in range(section_count):
        top = index * SECTION_SIZE
        section = image.crop((0, top, SECTION_SIZE, top + SECTION_SIZE))
        sections.append(section.copy())
    return sections


def expand_section(section: Image.Image) -> list[Image.Image]:
    # Буквально по описанию:
    # 1) 2 копии с отражением по диагонали лево-низ -> право-верх
    # 2) 2 копии с отражением по диагонали лево-верх -> право-низ
    # 3) 2 копии: по одному отражению по каждой из двух диагоналей
    # 4) 2 копии без изменений
    return [
        reflect_anti_diagonal(section),
        reflect_anti_diagonal(section),
        reflect_main_diagonal(section),
        reflect_main_diagonal(section),
        reflect_main_diagonal(reflect_anti_diagonal(section)),
        reflect_anti_diagonal(reflect_main_diagonal(section)),
        section.copy(),
        section.copy(),
    ]


def build_output_image(tiles: list[Image.Image], mode: str) -> Image.Image:
    output = Image.new(mode, (SECTION_SIZE, SECTION_SIZE * len(tiles)))
    for index, tile in enumerate(tiles):
        output.paste(tile, (0, index * SECTION_SIZE))
    return output


def main() -> None:
    if COPIES_PER_SECTION != 8:
        raise ValueError("Скрипт рассчитан на 8 копий каждой секции.")

    if RANDOM_SEED is not None:
        random.seed(RANDOM_SEED)

    source_path = Path(SOURCE_IMAGE)
    output_path = build_output_path(source_path)

    with Image.open(source_path) as image:
        section_count = validate_source_image(image)
        sections = extract_sections(image, section_count)
        expanded_tiles = []
        for section in sections:
            expanded_tiles.extend(expand_section(section))

        random.shuffle(expanded_tiles)
        output = build_output_image(expanded_tiles, image.mode)
        output.save(output_path)

    print(f"Готово: {output_path}")
    print(f"Секций найдено: {section_count}")
    print(f"Сохранено блоков: {len(expanded_tiles)}")
    print(f"Размер итогового PNG: {SECTION_SIZE}x{SECTION_SIZE * len(expanded_tiles)}")


if __name__ == "__main__":
    main()
