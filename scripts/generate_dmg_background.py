#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


WIDTH = 720
HEIGHT = 480


def rounded_rectangle_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def make_background(icon_path: Path) -> Image.Image:
    background = Image.new("RGBA", (WIDTH, HEIGHT), (246, 249, 252, 255))
    draw = ImageDraw.Draw(background)

    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        color = (
            round(250 - 12 * t),
            round(252 - 13 * t),
            round(255 - 10 * t),
            255,
        )
        draw.line((0, y, WIDTH, y), fill=color)

    icon = Image.open(icon_path).convert("RGBA")
    hero = icon.resize((360, 360), Image.Resampling.LANCZOS)
    hero_alpha = hero.getchannel("A").point(lambda value: round(value * 0.18))
    hero.putalpha(hero_alpha)
    hero = hero.filter(ImageFilter.GaussianBlur(0.4))
    background.alpha_composite(hero, (180, 36))

    card_shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(card_shadow)
    shadow_draw.rounded_rectangle((54, 54, 666, 426), radius=28, fill=(35, 52, 70, 22))
    card_shadow = card_shadow.filter(ImageFilter.GaussianBlur(22))
    background = Image.alpha_composite(background, card_shadow)

    panel = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    panel_draw = ImageDraw.Draw(panel)
    panel_draw.rounded_rectangle((54, 54, 666, 426), radius=28, fill=(255, 255, 255, 132), outline=(210, 224, 236, 150), width=1)
    background = Image.alpha_composite(background, panel)

    accent = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    accent_draw = ImageDraw.Draw(accent)
    accent_draw.line((302, 242, 418, 242), fill=(20, 170, 205, 72), width=4)
    accent_draw.line((418, 242, 394, 222), fill=(20, 170, 205, 72), width=4)
    accent_draw.line((418, 242, 394, 262), fill=(20, 170, 205, 72), width=4)
    accent_draw.arc((276, 206, 444, 278), start=178, end=2, fill=(37, 203, 156, 52), width=2)
    background = Image.alpha_composite(background, accent)

    return background


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: generate_dmg_background.py <icon-source.png> <output.png>", file=sys.stderr)
        return 2

    icon_path = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)
    make_background(icon_path).save(output)
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
