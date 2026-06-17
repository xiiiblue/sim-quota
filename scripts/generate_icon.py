#!/usr/bin/env python3
from pathlib import Path
import math
import struct

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"
ICONSET = RESOURCES / "AppIcon.iconset"
PNG_PATH = RESOURCES / "AppIcon.png"
ICNS_PATH = RESOURCES / "AppIcon.icns"
SOURCE_PATH = RESOURCES / "AppIconSource.png"


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon(size: int = 1024) -> Image.Image:
    scale = 4
    canvas_size = size * scale
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))

    # Background gradient.
    bg = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    px = bg.load()
    for y in range(canvas_size):
        for x in range(canvas_size):
            nx = x / canvas_size
            ny = y / canvas_size
            t = (nx * 0.35 + ny * 0.65)
            r = int(246 * (1 - t) + 219 * t)
            g = int(252 * (1 - t) + 244 * t)
            b = int(250 * (1 - t) + 255 * t)
            px[x, y] = (r, g, b, 255)
    bg.putalpha(rounded_mask(canvas_size, int(220 * scale)))
    image.alpha_composite(bg)

    draw = ImageDraw.Draw(image)

    def s(value: float) -> int:
        return int(value * scale)

    # Soft tile shadow.
    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sim = [(s(236), s(160)), (s(670), s(160)), (s(790), s(280)), (s(790), s(814)), (s(236), s(814))]
    sd.polygon(sim, fill=(23, 79, 107, 70))
    shadow = shadow.filter(ImageFilter.GaussianBlur(s(18)))
    image.alpha_composite(shadow, (0, s(22)))

    # SIM body.
    sim_body = Image.new("RGBA", image.size, (0, 0, 0, 0))
    bd = ImageDraw.Draw(sim_body)
    bd.polygon(sim, fill=(255, 255, 255, 245))
    bd.line(sim + [sim[0]], fill=(188, 214, 218, 255), width=s(10), joint="curve")
    image.alpha_composite(sim_body)

    # Cut corner accent.
    draw.line([(s(670), s(160)), (s(790), s(280))], fill=(52, 166, 210, 255), width=s(12))

    # Chip.
    chip_box = (s(334), s(298), s(594), s(522))
    draw.rounded_rectangle(chip_box, radius=s(34), fill=(235, 249, 247, 255), outline=(70, 190, 175, 255), width=s(10))
    for x in [398, 464, 530]:
        draw.line([(s(x), s(318)), (s(x), s(502))], fill=(136, 211, 201, 255), width=s(5))
    for y in [370, 450]:
        draw.line([(s(354), s(y)), (s(574), s(y))], fill=(136, 211, 201, 255), width=s(5))

    # Data gauge arc.
    arc_box = (s(368), s(536), s(710), s(878))
    draw.arc(arc_box, start=138, end=402, fill=(222, 235, 236, 255), width=s(38))
    draw.arc(arc_box, start=138, end=326, fill=(34, 196, 128, 255), width=s(38))
    # Gauge needle/dot.
    cx, cy = s(539), s(707)
    angle = math.radians(326)
    dot = (cx + int(math.cos(angle) * s(171)), cy + int(math.sin(angle) * s(171)))
    draw.ellipse((dot[0] - s(21), dot[1] - s(21), dot[0] + s(21), dot[1] + s(21)), fill=(20, 166, 108, 255))

    # Cellular signal bars.
    bars = [
        (s(308), s(710), s(348), s(784)),
        (s(374), s(666), s(414), s(784)),
        (s(440), s(614), s(480), s(784)),
    ]
    for index, box in enumerate(bars):
        alpha = 225 + index * 10
        draw.rounded_rectangle(box, radius=s(18), fill=(45, 145, 230, alpha))

    # Highlight.
    draw.rounded_rectangle((s(84), s(70), s(940), s(940)), radius=s(186), outline=(255, 255, 255, 115), width=s(6))

    return image.resize((size, size), Image.Resampling.LANCZOS)


def main() -> None:
    RESOURCES.mkdir(exist_ok=True)
    if SOURCE_PATH.exists():
        source = Image.open(SOURCE_PATH).convert("RGBA")
        width, height = source.size
        side = min(width, height)
        left = (width - side) // 2
        top = (height - side) // 2
        icon = source.crop((left, top, left + side, top + side)).resize((1024, 1024), Image.Resampling.LANCZOS)
    else:
        icon = draw_icon()
    icon.save(PNG_PATH)

    ICONSET.mkdir(exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        resized = icon.resize((size, size), Image.Resampling.LANCZOS)
        if size == 64:
            resized.save(ICONSET / "icon_32x32@2x.png")
        elif size == 1024:
            resized.save(ICONSET / "icon_512x512@2x.png")
        else:
            point_size = size
            resized.save(ICONSET / f"icon_{point_size}x{point_size}.png")
            if size <= 512:
                double_size = size * 2
                icon.resize((double_size, double_size), Image.Resampling.LANCZOS).save(
                    ICONSET / f"icon_{point_size}x{point_size}@2x.png"
                )

    entries = [
        ("icp4", 16),
        ("icp5", 32),
        ("icp6", 64),
        ("ic07", 128),
        ("ic08", 256),
        ("ic09", 512),
        ("ic10", 1024),
    ]
    chunks = []
    for code, entry_size in entries:
        entry = icon.resize((entry_size, entry_size), Image.Resampling.LANCZOS)
        tmp_path = ICONSET / f"icns_{entry_size}.png"
        entry.save(tmp_path)
        data = tmp_path.read_bytes()
        chunks.append(code.encode("ascii") + struct.pack(">I", len(data) + 8) + data)
        tmp_path.unlink()
    body = b"".join(chunks)
    ICNS_PATH.write_bytes(b"icns" + struct.pack(">I", len(body) + 8) + body)


if __name__ == "__main__":
    main()
