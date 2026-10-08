import json
from pathlib import Path


lang_dir = Path(__file__).resolve().parent / "assets" / "minecraft" / "lang"

with (lang_dir / "ru_ru.json").open(encoding="utf-8-sig") as file:
    ru_translations = json.load(file)

en_path = lang_dir / "en_us.json"
with en_path.open(encoding="utf-8-sig") as file:
    en_translations = json.load(file)

ru_keys = set(ru_translations)
en_keys = set(en_translations)

for title, keys in (
    ("Есть в ru_ru, но нет в en_us", ru_keys - en_keys),
    ("Есть в en_us, но нет в ru_ru", en_keys - ru_keys),
):
    print(f"\n{title} ({len(keys)}):")
    for key in sorted(keys):
        print(f"  {key}")
    if not keys:
        print("  Нет таких ключей")

ordered_en = {
    key: en_translations[key]
    for key in ru_translations
    if key in en_translations
}
ordered_en.update(
    (key, value)
    for key, value in en_translations.items()
    if key not in ru_keys
)

with en_path.open("w", encoding="utf-8") as file:
    file.write(json.dumps(ordered_en, ensure_ascii=False, indent=2) + "\n")

print("\nen_us.json: ключи упорядочены по ru_ru.json, дополнительные — в конце.")
