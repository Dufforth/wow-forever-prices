"""Draws the addon's round guide icon (user, 2026-11-14: a yellow camera aperture on a dark stone button, a D in the middle):
addon/DufforthTweaksHelper/Media/GuideIcon.tga, 64x64 with a transparent outside (the game reads TGA)."""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(__file__).resolve().parents[1] / "addon" / "DufforthTweaksHelper" / "Media" / "GuideIcon.tga"
SIZE, SCALE = 64, 4  # drawn 4x larger, then shrunk for smooth edges
FONT = "C:/Windows/Fonts/arialbd.ttf"


def main():
    n = SIZE * SCALE
    c = n / 2
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # Dark stone disc with a little texture.
    rnd = random.Random(7)
    stone = Image.new("RGBA", (n, n), (52, 54, 50, 255))
    sd = ImageDraw.Draw(stone)
    for _ in range(900):
        x, y, r = rnd.uniform(0, n), rnd.uniform(0, n), rnd.uniform(2, 9)
        g = rnd.randint(36, 76)
        sd.ellipse((x - r, y - r, x + r, y + r), fill=(g, g + 2, g - 2, 255))
    stone = stone.filter(ImageFilter.GaussianBlur(3))
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse((6, 6, n - 6, n - 6), fill=255)
    img.paste(stone, (0, 0), mask)
    # Light rim.
    d.ellipse((6, 6, n - 6, n - 6), outline=(225, 225, 220, 255), width=7)
    # Yellow aperture: a ring of six blades around a dark centre.
    outer, inner = n * 0.27, n * 0.11
    d.ellipse((c - outer, c - outer, c + outer, c + outer), fill=(236, 196, 28, 255))
    for k in range(6):
        a = math.radians(k * 60 + 15)
        x1, y1 = c + inner * math.cos(a), c + inner * math.sin(a)
        x2, y2 = c + outer * math.cos(a + math.radians(40)), c + outer * math.sin(a + math.radians(40))
        d.line((x1, y1, x2, y2), fill=(40, 34, 10, 255), width=int(n * 0.025))
    # A "D" for Dufforth in the middle (user, 2026-11-14), on a dark centre.
    hole = n * 0.16
    d.ellipse((c - hole, c - hole, c + hole, c + hole), fill=(26, 26, 24, 255))
    font = ImageFont.truetype(FONT, int(n * 0.24)) if Path(FONT).exists() else ImageFont.load_default()
    d.text((c, c), "D", font=font, fill=(244, 206, 40, 255), anchor="mm")
    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"{OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
