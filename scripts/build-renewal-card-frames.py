from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "production/card-frames/final/card-frame-common-master.png"
MASTER_DIR = ROOT / "production/card-frames/final"
RUNTIME_DIR = ROOT / "assets/renewal/card-frames"
PREVIEW_DIR = ROOT / "production/card-frames/previews"
PHOTO = ROOT / "assets/cards/arisongi-4.jpg"
EX_SOURCE = ROOT / "production/card-frames/ex/work/card-frame-ex-alpha-v1.png"
EX_PHOTO = ROOT / "assets/cards/group-1.avif"
EX_MASTER_SIZE = (1600, 900)
EX_RUNTIME_SIZE = (1200, 675)
EX_OPENING_BOX_RUNTIME = (56, 57, 1144, 618)
EX_OPENING_LOCAL_RUNTIME = [(89, 0), (999, 0), (1088, 65), (1088, 488), (1000, 561), (87, 561), (0, 488), (0, 65)]

OPENING = [(84, 68), (1916, 68), (1932, 84), (1932, 2716), (1916, 2732), (84, 2732), (68, 2716), (68, 84)]
OPENING_RUNTIME = [(42, 34), (958, 34), (966, 42), (966, 1358), (958, 1366), (42, 1366), (34, 1358), (34, 42)]
OPENING_BOX_RUNTIME = (34, 34, 966, 1366)
OPENING_LOCAL_RUNTIME = [(8, 0), (924, 0), (932, 8), (932, 1324), (924, 1332), (8, 1332), (0, 1324), (0, 8)]
INDEPENDENT_RARITIES = {"S", "SS", "SSS"}

RARITIES = {
    "F": {"color": "#89939b", "tint": 0.04, "line": 0, "glow": 0, "core": 0, "double": False},
    "E": {"color": "#58b97a", "tint": 0.11, "line": 2, "glow": 2, "core": 0, "double": False},
    "D": {"color": "#4aa8d8", "tint": 0.16, "line": 2, "glow": 3, "core": 0, "double": False},
    "C": {"color": "#7f79df", "tint": 0.21, "line": 3, "glow": 4, "core": 0, "double": False},
    "B": {"color": "#bb69e8", "tint": 0.27, "line": 3, "glow": 5, "core": 0, "double": False},
    "A": {"color": "#ef5f83", "tint": 0.32, "line": 4, "glow": 7, "core": 0, "double": False},
    "S": {"color": "#ff9b3f", "tint": 0.37, "line": 5, "glow": 10, "core": 1, "double": False},
    "SS": {"color": "#ffd449", "tint": 0.42, "line": 6, "glow": 14, "core": 2, "double": True},
    "SSS": {"color": "#d7ff35", "tint": 0.48, "line": 7, "glow": 19, "core": 3, "double": True},
}


def rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) for index in (0, 2, 4))


def clipped_alpha(layer, frame_alpha):
    layer_alpha = layer.getchannel("A")
    layer.putalpha(ImageChops.multiply(layer_alpha, frame_alpha))
    return layer


def clear_photo_opening(image, polygon):
    cut = Image.new("L", image.size, 0)
    ImageDraw.Draw(cut).polygon(polygon, fill=255)
    alpha = image.getchannel("A")
    alpha.paste(0, mask=cut)
    image.putalpha(alpha)
    return image


def clear_outer_inset(image, inset):
    alpha = image.getchannel("A")
    draw = ImageDraw.Draw(alpha)
    width, height = image.size
    draw.rectangle((0, 0, width - 1, inset - 1), fill=0)
    draw.rectangle((0, height - inset, width - 1, height - 1), fill=0)
    draw.rectangle((0, 0, inset - 1, height - 1), fill=0)
    draw.rectangle((width - inset, 0, width - 1, height - 1), fill=0)
    image.putalpha(alpha)
    return image


def energy_layer(size, color, line_width, core_level, double_line):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    rgba = (*color, 235)
    points = OPENING + [OPENING[0]]
    if line_width:
        draw.line(points, fill=rgba, width=line_width, joint="curve")
    if double_line:
        secondary = [(x + (5 if x < 1000 else -5), y + (5 if y < 1400 else -5)) for x, y in OPENING]
        draw.line(secondary + [secondary[0]], fill=(*color, 150), width=max(2, line_width - 2), joint="curve")

    tick_length = 68 if core_level == 0 else 104
    for x, y, dx, dy in ((24, 190, 0, tick_length), (1976, 190, 0, tick_length), (24, 2610, 0, -tick_length), (1976, 2610, 0, -tick_length)):
        draw.line((x, y, x + dx, y + dy), fill=(*color, 150), width=max(2, line_width))

    if core_level:
        half_width = 62 + core_level * 18
        core = [(1000 - half_width, 5), (1000 + half_width, 5), (1000 + half_width + 16, 22), (1000 + half_width, 39), (1000 - half_width, 39), (1000 - half_width - 16, 22)]
        draw.polygon(core, fill=(*color, 80 + core_level * 40), outline=(*color, 255))
        draw.line((1000 - half_width + 18, 22, 1000 + half_width - 18, 22), fill=(255, 255, 255, 170 + core_level * 20), width=2 + core_level)
        bottom_core = [(x, 2800 - y) for x, y in core]
        draw.polygon(bottom_core, fill=(*color, 55 + core_level * 35), outline=(*color, 220))
        for offset in (-1, 1):
            x = 1000 + offset * (half_width + 42)
            draw.line((x, 7, x + offset * 24, 22, x, 37), fill=(*color, 190), width=3 + core_level)

        horizontal_segments = [(220, 340), (520, 690), (1310, 1480), (1660, 1780)]
        vertical_segments = [(390, 520), (790, 900), (1900, 2010), (2280, 2410)]
        segment_count = min(len(horizontal_segments), core_level + 1)
        for start, end in horizontal_segments[:segment_count]:
            draw.line((start, 21, end, 21), fill=(*color, 125 + core_level * 35), width=2 + core_level)
            draw.line((2000 - end, 2779, 2000 - start, 2779), fill=(*color, 105 + core_level * 35), width=2 + core_level)
        for start, end in vertical_segments[:segment_count]:
            draw.line((21, start, 21, end), fill=(*color, 110 + core_level * 35), width=2 + core_level)
            draw.line((1979, 2800 - end, 1979, 2800 - start), fill=(*color, 110 + core_level * 35), width=2 + core_level)

        if core_level >= 2:
            node_radius = 7 + core_level * 2
            for x, y in ((34, 34), (1966, 34), (34, 2766), (1966, 2766)):
                draw.ellipse((x - node_radius, y - node_radius, x + node_radius, y + node_radius), fill=(255, 255, 255, 110 + core_level * 35), outline=(*color, 255), width=2 + core_level)

    return layer


def make_frame(source, rarity, spec):
    frame_alpha = source.getchannel("A")
    base_rgb = source.convert("RGB")
    gray = ImageOps.grayscale(base_rgb)
    dark = tuple(max(3, channel // 13) for channel in rgb(spec["color"]))
    colorized = ImageOps.colorize(gray, dark, rgb(spec["color"]))
    tinted = Image.blend(base_rgb, colorized, spec["tint"]).convert("RGBA")
    tinted.putalpha(frame_alpha)

    energy = energy_layer(source.size, rgb(spec["color"]), spec["line"], spec["core"], spec["double"])
    energy = clipped_alpha(energy, frame_alpha)
    if spec["glow"]:
        glow = energy.filter(ImageFilter.GaussianBlur(spec["glow"]))
        glow = clipped_alpha(glow, frame_alpha)
        tinted = Image.alpha_composite(tinted, glow)
    return Image.alpha_composite(tinted, energy)


def card_preview(frame_path, rarity, color):
    opening_width = OPENING_BOX_RUNTIME[2] - OPENING_BOX_RUNTIME[0]
    opening_height = OPENING_BOX_RUNTIME[3] - OPENING_BOX_RUNTIME[1]
    photo = Image.open(PHOTO).convert("RGB")
    photo = ImageOps.fit(photo, (opening_width, opening_height), method=Image.Resampling.LANCZOS, centering=(0.5, 0.22)).convert("RGBA")
    mask = Image.new("L", photo.size, 0)
    ImageDraw.Draw(mask).polygon(OPENING_LOCAL_RUNTIME, fill=255)
    photo.putalpha(mask)

    card = Image.new("RGBA", (1000, 1400), (3, 6, 5, 255))
    card.alpha_composite(photo, OPENING_BOX_RUNTIME[:2])
    shade = Image.new("RGBA", photo.size, (0, 0, 0, 0))
    shade_draw = ImageDraw.Draw(shade)
    for y in range(840, photo.height):
        t = (y - 840) / (photo.height - 840)
        shade_draw.line((0, y, photo.width, y), fill=(3, 7, 5, int(220 * (t ** 1.7))))
    shade.putalpha(ImageChops.multiply(shade.getchannel("A"), mask))
    card.alpha_composite(shade, OPENING_BOX_RUNTIME[:2])
    card = Image.alpha_composite(card, Image.open(frame_path).convert("RGBA"))

    draw = ImageDraw.Draw(card)
    grade_font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 56)
    name_font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 50)
    meta_font = ImageFont.truetype("C:/Windows/Fonts/malgun.ttf", 24)
    draw.text((58, 52), rarity, font=grade_font, fill=color, stroke_width=2, stroke_fill=(0, 0, 0, 220))
    draw.text((58, 1260), "\uc544\ub9ac\uc1a1\uc774", font=name_font, fill=(248, 249, 246, 255), stroke_width=2, stroke_fill=(0, 0, 0, 220))
    draw.text((60, 1330), "\ud504\ub85c\ud1a0\uc2a4  \u00b7  +0", font=meta_font, fill=(190, 202, 194, 255))
    return card


def build_ex_frame():
    source = Image.open(EX_SOURCE).convert("RGBA")
    master = ImageOps.fit(source, EX_MASTER_SIZE, method=Image.Resampling.LANCZOS)
    master = clear_outer_inset(master, 2)
    master_path = MASTER_DIR / "card-frame-ex-master.png"
    master.save(master_path, optimize=True)

    runtime = master.resize(EX_RUNTIME_SIZE, Image.Resampling.LANCZOS)
    runtime = clear_outer_inset(runtime, 2)
    runtime_path = RUNTIME_DIR / "card-frame-ex.webp"
    runtime.save(runtime_path, "WEBP", lossless=True, method=6)

    opening_width = EX_OPENING_BOX_RUNTIME[2] - EX_OPENING_BOX_RUNTIME[0]
    opening_height = EX_OPENING_BOX_RUNTIME[3] - EX_OPENING_BOX_RUNTIME[1]
    photo = ImageOps.contain(
        Image.open(EX_PHOTO).convert("RGB"),
        (opening_width, opening_height),
        method=Image.Resampling.LANCZOS,
    ).convert("RGBA")
    opening = Image.new("RGBA", (opening_width, opening_height), (6, 8, 7, 255))
    photo_position = ((opening_width - photo.width) // 2, (opening_height - photo.height) // 2)
    opening.alpha_composite(photo, photo_position)
    opening_mask = Image.new("L", opening.size, 0)
    ImageDraw.Draw(opening_mask).polygon(EX_OPENING_LOCAL_RUNTIME, fill=255)
    opening.putalpha(opening_mask)

    preview = Image.new("RGBA", EX_RUNTIME_SIZE, (3, 5, 4, 255))
    preview.alpha_composite(opening, EX_OPENING_BOX_RUNTIME[:2])
    shade = Image.new("RGBA", opening.size, (0, 0, 0, 0))
    shade_draw = ImageDraw.Draw(shade)
    for y in range(370, opening_height):
        t = (y - 370) / (opening_height - 370)
        shade_draw.line((0, y, opening_width, y), fill=(3, 7, 6, int(180 * (t ** 1.6))))
    shade.putalpha(ImageChops.multiply(shade.getchannel("A"), opening_mask))
    preview.alpha_composite(shade, EX_OPENING_BOX_RUNTIME[:2])
    preview = Image.alpha_composite(preview, runtime)

    draw = ImageDraw.Draw(preview)
    grade_font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 48)
    name_font = ImageFont.truetype("C:/Windows/Fonts/malgunbd.ttf", 40)
    draw.text((64, 50), "EX", font=grade_font, fill=(248, 242, 214, 255), stroke_width=2, stroke_fill=(0, 0, 0, 230))
    draw.text((66, 586), "\ub2e8\uccb4\uc0ac\uc9c4", font=name_font, fill=(250, 250, 246, 255), stroke_width=2, stroke_fill=(0, 0, 0, 230))
    preview.convert("RGB").save(PREVIEW_DIR / "card-frame-ex-preview.jpg", quality=92, optimize=True)

    alpha = master.getchannel("A")
    if alpha.getpixel((EX_MASTER_SIZE[0] // 2, EX_MASTER_SIZE[1] // 2)) != 0:
        raise RuntimeError("EX frame photo opening is not transparent")
    if alpha.getbbox() is None:
        raise RuntimeError("EX frame is empty")


def main():
    MASTER_DIR.mkdir(parents=True, exist_ok=True)
    RUNTIME_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    source_alpha_bbox = source.getchannel("A").getbbox()
    previews = []

    for rarity, spec in RARITIES.items():
        master_path = MASTER_DIR / f"card-frame-{rarity.lower()}-master.png"
        runtime_path = RUNTIME_DIR / f"card-frame-{rarity.lower()}.webp"
        if rarity in INDEPENDENT_RARITIES:
            if not master_path.exists():
                raise RuntimeError(f"Missing independent {rarity} frame: {master_path}")
            master = Image.open(master_path).convert("RGBA")
        else:
            master = make_frame(source, rarity, spec)
        master = clear_photo_opening(master, OPENING)
        master.save(master_path, optimize=True)
        runtime = master.resize((1000, 1400), Image.Resampling.LANCZOS)
        runtime = clear_photo_opening(runtime, OPENING_RUNTIME)
        runtime = clear_outer_inset(runtime, 2)
        runtime.save(runtime_path, "WEBP", lossless=True, method=6)

        if master.getchannel("A").getbbox() != source_alpha_bbox or master.getchannel("A").getpixel((1000, 1400)) != 0:
            raise RuntimeError(f"{rarity} changed the locked frame geometry")
        previews.append((rarity, card_preview(runtime_path, rarity, rgb(spec["color"]))))

    build_ex_frame()

    sheet = Image.new("RGB", (1056, 1476), (5, 8, 6))
    label_font = ImageFont.truetype("C:/Windows/Fonts/arialbd.ttf", 28)
    draw = ImageDraw.Draw(sheet)
    for index, (rarity, preview) in enumerate(previews):
        column = index % 3
        row = index // 3
        x = 24 + column * 344
        y = 20 + row * 480
        thumb = preview.resize((320, 448), Image.Resampling.LANCZOS)
        sheet.paste(thumb.convert("RGB"), (x, y))
        draw.text((x + 8, y + 8), rarity, font=label_font, fill=rgb(RARITIES[rarity]["color"]), stroke_width=2, stroke_fill=(0, 0, 0))
    sheet.save(PREVIEW_DIR / "card-frame-rarity-sheet.jpg", quality=92, optimize=True)
    print(f"Built {len(RARITIES)} locked-geometry rarity frames and 1 EX archive frame")


if __name__ == "__main__":
    main()
