#!/usr/bin/env python3
"""Draws the app icon and writes Resources/AppIcon.icns (needs Pillow + macOS iconutil)."""
import math, os, subprocess, tempfile
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 2048            # supersampled canvas; Apple's grid: 824px squircle inside 1024
K = S / 1024

def squircle_mask(size, n=5.0):
    m = Image.new("L", (S, S), 0)
    a = size * K / 2
    pts = []
    for i in range(720):
        t = 2 * math.pi * i / 720
        c, s = math.cos(t), math.sin(t)
        pts.append((S / 2 + a * math.copysign(abs(c) ** (2 / n), c), S / 2 + a * math.copysign(abs(s) ** (2 / n), s)))
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m

def glow(img, c, r, color):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], fill=color)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(r * 0.4)))

def note_font(size):
    for p in ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/System/Library/Fonts/Apple Symbols.ttf"):
        try: return ImageFont.truetype(p, size)
        except Exception: pass
    return ImageFont.load_default()

def draw():
    mask = squircle_mask(824)
    # background gradient + glows
    small = Image.new("RGB", (2, 2)); small.putdata([(26, 36, 84), (44, 40, 104), (60, 38, 98), (150, 64, 150)])
    body = small.resize((S, S), Image.BICUBIC).convert("RGBA")
    glow(body, (int(S * .22), int(S * .8)), int(S * .22), (70, 130, 220, 120))
    glow(body, (int(S * .8), int(S * .22)), int(S * .2), (230, 110, 170, 110))
    d = ImageDraw.Draw(body)

    # lyrics card
    cx, cy, w, h = S // 2, int(S * .53), int(560 * K), int(340 * K)
    card = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle([cx - w // 2, cy - h // 2, cx + w // 2, cy + h // 2], int(60 * K), fill=(8, 10, 24, 190))
    body.alpha_composite(card)
    d = ImageDraw.Draw(body)
    x0 = cx - w // 2 + int(52 * K)
    for y, width, thick, alpha in ((-86, 330, 30, 95), (0, 430, 46, 255), (86, 280, 30, 95)):
        yy = cy + int(y * K)
        d.rounded_rectangle([x0, yy - int(thick * K / 2), x0 + int(width * K), yy + int(thick * K / 2)],
                            int(thick * K / 2), fill=(255, 255, 255, alpha))

    # music-note badge
    bx, by, br = cx + int(250 * K), cy - int(170 * K), int(92 * K)
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([bx - br, by - br + int(10 * K), bx + br, by + br + int(10 * K)], fill=(0, 0, 0, 120))
    body.alpha_composite(sh.filter(ImageFilter.GaussianBlur(14 * K)))
    d = ImageDraw.Draw(body)
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=(255, 255, 255, 255))
    d.text((bx, by), "♪", font=note_font(int(150 * K)), fill=(96, 52, 150, 255), anchor="mm")

    # clip to squircle, add drop shadow
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0)); clipped.paste(body, (0, 0), mask)
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), (0, int(14 * K)), mask)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16 * K)))
    out.alpha_composite(clipped)
    return out.resize((1024, 1024), Image.LANCZOS)

if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    master = draw()
    master.save(os.path.join(here, "Resources", "icon-1024.png"))
    with tempfile.TemporaryDirectory() as t:
        iconset = os.path.join(t, "AppIcon.iconset"); os.makedirs(iconset)
        for base in (16, 32, 128, 256, 512):
            master.resize((base, base), Image.LANCZOS).save(os.path.join(iconset, f"icon_{base}x{base}.png"))
            master.resize((base * 2, base * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{base}x{base}@2x.png"))
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(here, "Resources", "AppIcon.icns")], check=True)
    print("wrote Resources/AppIcon.icns")
