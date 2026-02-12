from pathlib import Path
from PIL import Image

SCRIPT_DIR = Path(__file__).resolve().parent
files = sorted(SCRIPT_DIR.glob("cunny*.png"))

print("Script dir:", SCRIPT_DIR)
print("Found:", len(files))

for path in files:
    with Image.open(path) as img:
        img = img.convert("RGBA")
        r, g, b, a = img.split()
        a = a.point(lambda _: 254)
        Image.merge("RGBA", (r, g, b, a)).save(path)
    print("Processed:", path.name)
