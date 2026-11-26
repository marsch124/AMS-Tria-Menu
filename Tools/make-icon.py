#!/usr/bin/env python3
"""Builds the AMS Tria Menu app icon: a flat calm green tile with the white training wave (three blocks of work on a
rest line, the line of AMS Triathlon Training's app icon; the app mark "trainingWave" in the AMS Icon Library).

Writes, all from the same numbers (the same way AMS Tria Menu does it):
  App/Resources/AppIcon.icon   layered icon (Icon Composer format): green background, ONE layer (the mark),
                               every glass effect off, same by day and night.
  App/Resources/AppIcon.icns   loose picture on Apple's tile shape (824 px tile on a 1024 canvas, radius 185.4).
  Docs/icon-1024.png           the same picture as a PNG.

Run:  python3 Tools/make-icon.py        (needs Pillow and the Mac's own iconutil)
"""
import json, math, os, shutil, subprocess, tempfile
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

GREEN = (0.0, 135 / 255, 90 / 255)   # #00875A
WHITE = (1.0, 1.0, 1.0)
GLYPH = 0.86            # the mark's 24-unit grid takes this share of the tile's width
STROKE = 2.3
STROKE_SMALL = 2.6      # heavier line for the 64 px and smaller pictures in the .icns
CANVAS, TILE, RADIUS = 1024, 824, 185.4

# The training wave on the 24 grid (AMS-Icons AppMark.trainingWave): one line through these points. It is centred already.
WAVE = [(2.5, 16.05), (3.89, 7.95), (6.43, 7.95), (7.82, 16.05), (9.34, 16.05), (10.73, 7.95), (13.27, 7.95),
        (14.66, 16.05), (16.18, 16.05), (17.57, 7.95), (20.11, 7.95), (21.5, 16.05)]
LINES = list(zip(WAVE, WAVE[1:]))
DY = 0.0


def rgb8(c):
    return tuple(round(v * 255) for v in c) + (255,)


def colour(c):
    return "srgb:" + ",".join(f"{v:.5f}" for v in c) + ",1.00000"


def write_layered_icon(folder):
    shutil.rmtree(folder, ignore_errors=True)
    os.makedirs(os.path.join(folder, "Assets"))
    # The layered icon fills whatever it is given, so the line drawing is turned into one filled outline first.
    d = subprocess.run(["swift", os.path.join(ROOT, "Tools", "mark-outline.swift"), str(CANVAS), str(GLYPH), str(STROKE)],
                       check=True, capture_output=True, text=True).stdout.strip()
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{CANVAS}" height="{CANVAS}" viewBox="0 0 {CANVAS} {CANVAS}">'
           f'<path fill="#FFFFFF" fill-rule="nonzero" d="{d}"/></svg>\n')
    with open(os.path.join(folder, "Assets", "mark.svg"), "w") as f:
        f.write(svg)

    def same(c):
        return [{"value": {"solid": colour(c)}}, {"appearance": "dark", "value": {"solid": colour(c)}}]

    doc = {
        "fill-specializations": same(GREEN),
        "groups": [{"layers": [{"fill-specializations": same(WHITE), "glass": False,
                                "image-name": "mark.svg", "name": "Mark"}], "name": "Mark",
                    "blur-material": None, "lighting": "individual",
                    "shadow": {"kind": "none", "opacity": 0}, "specular": False,
                    "translucency": {"enabled": False, "value": 0}}],
        "supported-platforms": {"squares": ["macOS"]},
    }
    with open(os.path.join(folder, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
        f.write("\n")


def apple_tile(size, tile, radius, steps=48):
    x0 = y0 = (size - tile) / 2
    x1 = y1 = x0 + tile
    r = radius

    def bez(p0, p1, p2, p3):
        out = []
        for i in range(1, steps + 1):
            t = i / steps
            a, b, c, d = (1 - t) ** 3, 3 * (1 - t) ** 2 * t, 3 * (1 - t) * t * t, t ** 3
            out.append((a * p0[0] + b * p1[0] + c * p2[0] + d * p3[0], a * p0[1] + b * p1[1] + c * p2[1] + d * p3[1]))
        return out

    corner = [(1.528665, 0), (1.088493, 0), (0.868407, 0), (0.631494, 0.074911),
              (0.372824, 0.169060), (0.169060, 0.372824), (0.074911, 0.631494),
              (0, 0.868407), (0, 1.088493), (0, 1.528665)]
    pts = []
    for (cx, cy), (ax, ay), (bx, by) in (((x1, y0), (-1, 0), (0, 1)), ((x1, y1), (0, -1), (-1, 0)),
                                         ((x0, y1), (1, 0), (0, -1)), ((x0, y0), (0, 1), (1, 0))):
        p = [(cx + ax * u * r + bx * v * r, cy + ay * u * r + by * v * r) for u, v in corner]
        pts.append(p[0])
        pts += bez(p[0], p[1], p[2], p[3]) + bez(p[3], p[4], p[5], p[6]) + bez(p[6], p[7], p[8], p[9])
    return pts


def render_flat(stroke, ss=4):
    s = CANVAS * ss
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).polygon([(x * ss, y * ss) for x, y in apple_tile(CANVAS, TILE, RADIUS)], fill=255)
    tile = Image.new("RGBA", (s, s), rgb8(GREEN))
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    img.paste(tile, (0, 0), mask)

    d = ImageDraw.Draw(img)
    scale = TILE * GLYPH * ss / 24
    ox = oy = s / 2 - 12 * scale
    P = lambda p: (ox + p[0] * scale, oy + (p[1] + DY) * scale)
    r = stroke * scale / 2
    white = rgb8(WHITE)

    def dab(pt):
        d.ellipse([pt[0] - r, pt[1] - r, pt[0] + r, pt[1] + r], fill=white)

    for a, b in LINES:
        pa, pb = P(a), P(b)
        n = 400
        for i in range(n + 1):
            t = i / n
            dab((pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t))
    return img.convert("RGBa")


def shrink(master, px):
    return master.reduce(master.width // px).convert("RGBA")


def write_icns(path, img, heavy):
    tmp = tempfile.mkdtemp()
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    for base in (16, 32, 128, 256, 512):
        for mult, suffix in ((1, ""), (2, "@2x")):
            px = base * mult
            shrink(heavy if px <= 64 else img, px).save(os.path.join(iconset, f"icon_{base}x{base}{suffix}.png"))
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", path], check=True)
    shutil.rmtree(tmp)


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "Docs"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "App", "Resources"), exist_ok=True)
    write_layered_icon(os.path.join(ROOT, "App", "Resources", "AppIcon.icon"))
    img = render_flat(STROKE)
    shrink(img, CANVAS).save(os.path.join(ROOT, "Docs", "icon-1024.png"))
    write_icns(os.path.join(ROOT, "App", "Resources", "AppIcon.icns"), img, render_flat(STROKE_SMALL))
    print("ok")
