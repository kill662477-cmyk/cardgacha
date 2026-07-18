from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "production/packs/source"
RUNTIME_DIR = ROOT / "assets/renewal/packs"
PREVIEW_DIR = ROOT / "production/packs/previews"
RUNTIME_SIZE = (640, 960)
SOURCE_CROP = (64, 80, 960, 1424)

PACKS = {
    "general": ("pack-general-v1.png", "일반"),
    "elite": ("pack-elite-v1.png", "정예"),
    "premium": ("pack-premium-v1.png", "프리미엄"),
    "zerg": ("pack-zerg-v1.png", "저그"),
    "terran": ("pack-terran-v1.png", "테란"),
    "protoss": ("pack-protoss-v1.png", "프로토스"),
}


def extract_capsule(source):
    rgb = source.convert("RGB")
    value = ImageOps.grayscale(rgb)
    bright = value.point(lambda pixel: 255 if pixel > 8 else 0)
    alpha = Image.new("L", rgb.size, 0)
    draw = ImageDraw.Draw(alpha)

    for y in range(rgb.height):
        row_box = bright.crop((0, y, rgb.width, y + 1)).getbbox()
        if row_box and row_box[2] - row_box[0] >= 8:
            draw.line((row_box[0], y, row_box[2] - 1, y), fill=255)

    alpha = alpha.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(0.7))
    capsule = rgb.convert("RGBA")
    capsule.putalpha(alpha)
    return capsule


def main():
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    previews = []

    for pack_id, (filename, label) in PACKS.items():
        source = extract_capsule(Image.open(SOURCE_DIR / filename)).crop(SOURCE_CROP)
        runtime = ImageOps.fit(source, RUNTIME_SIZE, method=Image.Resampling.LANCZOS)
        runtime_path = RUNTIME_DIR / f"pack-{pack_id}.webp"
        runtime.save(runtime_path, "WEBP", quality=88, method=6)
        previews.append((label, runtime.resize((240, 360), Image.Resampling.LANCZOS)))

    sheet = Image.new("RGB", (800, 820), (5, 7, 6))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 24)
    for index, (label, preview) in enumerate(previews):
        column = index % 3
        row = index // 3
        x = 20 + column * 260
        y = 18 + row * 400
        checker = Image.new("RGB", preview.size, (15, 19, 16))
        checker_draw = ImageDraw.Draw(checker)
        for tile_y in range(0, preview.height, 30):
            for tile_x in range(0, preview.width, 30):
                if (tile_x // 30 + tile_y // 30) % 2:
                    checker_draw.rectangle((tile_x, tile_y, tile_x + 29, tile_y + 29), fill=(28, 34, 29))
        checker.paste(preview, (0, 0), preview)
        sheet.paste(checker, (x, y))
        draw.text((x, y + 364), label, font=font, fill=(231, 235, 230))
    sheet.save(PREVIEW_DIR / "card-pack-season2-sheet.jpg", quality=92, optimize=True)
    print(f"Built {len(PACKS)} Season 2 pack assets")


if __name__ == "__main__":
    main()
