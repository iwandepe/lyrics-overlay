#!/usr/bin/env python3
"""Composites overlay frames (from LYRICS_CAPTURE) onto a mock desktop -> hero.gif + stills.
Usage: compose.py FRAMES_DIR OUT_DIR   (needs Pillow)"""
import glob, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 900, 520            # logical size of the mock screen (points)
OVERLAY = (380, 172)       # overlay size in points
OVERLAY_POS = (W - 24 - OVERLAY[0], 48)

def font(size, bold=False):
    for path in ("/System/Library/Fonts/HelveticaNeue.ttc", "/System/Library/Fonts/Helvetica.ttc"):
        try: return ImageFont.truetype(path, size, index=1 if bold else 0)
        except Exception: pass
    return ImageFont.load_default()

def note_font(size):
    for path in ("/System/Library/Fonts/Supplemental/Arial Unicode.ttf", "/System/Library/Fonts/Apple Symbols.ttf"):
        try: return ImageFont.truetype(path, size)
        except Exception: pass
    return font(size)

def rr(d, box, r, fill, S):
    d.rounded_rectangle([v * S for v in box], r * S, fill=fill)

def glow(img, center, radius, color, S):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse([(center[0]-radius)*S, (center[1]-radius)*S, (center[0]+radius)*S, (center[1]+radius)*S], fill=color)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius * S * 0.45)))

def backdrop(S):
    # diagonal gradient
    small = Image.new("RGB", (2, 2))
    small.putdata([(40, 20, 14), (92, 38, 16), (120, 52, 20), (236, 124, 42)])
    img = small.resize((W * S, H * S), Image.BICUBIC).convert("RGBA")
    glow(img, (120, 430), 190, (255, 150, 50, 110), S)
    glow(img, (760, 360), 220, (255, 190, 80, 95), S)
    d = ImageDraw.Draw(img)

    # menu bar
    bar = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(bar).rectangle([0, 0, W * S, 24 * S], fill=(255, 255, 255, 40))
    img.alpha_composite(bar)
    d = ImageDraw.Draw(img)
    d.text((W * S - 150 * S, 4 * S), "\u266a", font=note_font(15 * S), fill=(255, 255, 255, 245))
    d.text((W * S - 120 * S, 5 * S), "Fri 10:41", font=font(12 * S, True), fill=(255, 255, 255, 220))
    for i, label in enumerate(("Browser", "File", "Edit", "View", "Window")):
        d.text((16 * S + [0, 62, 98, 134, 176][i] * S, 5 * S), label, font=font(12 * S, i == 0),
               fill=(255, 255, 255, 230))

    # window shadow
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([34*S, 94*S, 700*S, 506*S], 14 * S, fill=(0, 0, 0, 150))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(18 * S)))
    d = ImageDraw.Draw(img)

    # browser window (the "work" in the foreground)
    rr(d, (30, 80, 700, 500), 12, (30, 30, 36, 255), S)
    d.rounded_rectangle([30*S, 80*S, 700*S, 122*S], 12 * S, fill=(44, 44, 52, 255))
    d.rectangle([30*S, 106*S, 700*S, 122*S], fill=(44, 44, 52, 255))
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        d.ellipse([(46 + i * 20) * S, 94 * S, (58 + i * 20) * S, 106 * S], fill=c)
    rr(d, (130, 90, 300, 122), 8, (30, 30, 36, 255), S)                      # active tab
    d.text((144 * S, 98 * S), "Project notes", font=font(12 * S, True), fill=(235, 235, 240, 255))
    d.text((318 * S, 98 * S), "♪  Morning Light (demo)", font=note_font(12 * S), fill=(150, 150, 165, 255))
    for k, h in enumerate((7, 11, 5)):                                       # little "playing" bars
        rr(d, (470 + k * 6, 110 - h, 474 + k * 6, 110), 1, (255, 150, 60, 255), S)

    # fake document
    rr(d, (60, 148, 280, 164), 4, (214, 214, 224, 255), S)
    y = 190
    for widths in ((420, 380, 300), (400, 330), (410, 390, 260), (350,)):
        for w in widths:
            rr(d, (60, y, 60 + w, y + 8), 4, (78, 78, 92, 255), S)
            y += 20
        y += 14
    rr(d, (60, y, 560, y + 74), 8, (22, 22, 28, 255), S)                     # code block
    for i, (indent, w, c) in enumerate(((0, 120, (255, 160, 80)), (24, 210, (214, 204, 196)),
                                         (24, 160, (255, 206, 120)), (0, 40, (255, 160, 80)))):
        rr(d, (76 + indent, y + 12 + i * 15, 76 + indent + w, y + 19 + i * 15), 3, c + (255,), S)
    return img

_cache = {}
def compose(overlay, S):
    base = _cache.setdefault(S, backdrop(S)).copy()
    ov = overlay.convert("RGBA")
    ov = ov.resize((OVERLAY[0] * S, OVERLAY[1] * S), Image.LANCZOS)
    pos = (OVERLAY_POS[0] * S, OVERLAY_POS[1] * S)
    shadow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    a = ov.split()[3].point(lambda v: int(v * 0.55))
    shadow.paste((0, 0, 0, 255), (pos[0], pos[1] + 8 * S), a)
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(12 * S)))
    base.alpha_composite(ov, pos)
    return base

def smooth(raws, at, steps=3):
    """The offscreen renderer only captures settled states, so the hover fade would jump.
    Cross-fade over `steps` frames starting at each frame index in `at` (~0.3s at 10fps).
    Lyric line changes are left as quick snaps; cross-fading moving text looks like a double exposure."""
    out = list(raws)
    for i in at:
        for k in range(steps):
            j = i + k
            if j < len(raws):
                out[j] = Image.blend(raws[i - 1], raws[i], (k + 1) / (steps + 1))
    return out

if __name__ == "__main__":
    frames_dir, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    files = sorted(glob.glob(os.path.join(frames_dir, "frame_*.png")))
    raws = [Image.open(f).convert("RGBA") for f in files]
    pick = lambda t: raws[min(int(t * 10), len(raws) - 1)]

    # Stills at 2x
    compose(pick(4.0), 2).convert("RGB").save(os.path.join(out, "overlay-desktop.png"), optimize=True)
    compose(pick(12.4), 2).convert("RGB").save(os.path.join(out, "overlay-hover.png"), optimize=True)
    crop = compose(pick(12.4), 2).crop((430 * 2, 20 * 2, W * 2, 250 * 2))
    crop.convert("RGB").save(os.path.join(out, "overlay-closeup.png"), optimize=True)

    # Hero GIF at 1x. One shared palette (built from several states) so colours don't flicker.
    sample = Image.new("RGB", (W, H * 3))
    for k, t in enumerate((4.0, 10.5, 12.4)):
        sample.paste(compose(pick(t), 1).convert("RGB"), (0, k * H))
    pal = sample.quantize(colors=255, method=Image.Quantize.FASTOCTREE)
    # Dither only the static backdrop (GIFs band badly on gradients); its pixels become exact palette
    # colours, so they stay identical frame to frame and the GIF stays small.
    _cache[1] = backdrop(1).convert("RGB").quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG).convert("RGBA")
    frames = [compose(f, 1).convert("RGB") for f in smooth(raws, at=(95, 145))]
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    q[0].save(os.path.join(out, "hero.gif"), save_all=True, append_images=q[1:], duration=100, loop=0, optimize=False)
    for n in ("hero.gif", "overlay-desktop.png", "overlay-hover.png", "overlay-closeup.png"):
        print(n, round(os.path.getsize(os.path.join(out, n)) / 1024), "KB")
