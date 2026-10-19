#!/usr/bin/env python3
"""Genera le icone dell'app (chiara, scura, monocromatica) in 1024x1024.
Uso: python3 Tools/make_icon.py   (richiede Pillow e numpy)"""
import math, os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048          # si disegna in grande e si riduce a 1024 per l'antialiasing
OUT = os.path.join(os.path.dirname(__file__), "..", "Sources", "Resources", "Assets.xcassets", "AppIcon.appiconset")

def gradient(size, c1, c2, angle_deg=135):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = math.radians(angle_deg)
    t = (xx * math.cos(a) + yy * math.sin(a))
    t = (t - t.min()) / (t.max() - t.min())
    c1, c2 = np.array(c1, np.float32), np.array(c2, np.float32)
    arr = c1[None, None, :] * (1 - t[..., None]) + c2[None, None, :] * t[..., None]
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB").convert("RGBA")

def radial_glow(size, center, radius, color, strength):
    w, h = size
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    a = np.clip(1 - d, 0, 1) ** 2 * strength
    img = np.zeros((h, w, 4), np.uint8)
    img[..., 0], img[..., 1], img[..., 2] = color
    img[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(img, "RGBA")

def rounded_mask(box, radius):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m

def render(style):
    if style == "light":
        bg = gradient((S, S), (88, 108, 255), (146, 78, 255), 120)
        bg = Image.alpha_composite(bg, radial_glow((S, S), (480, 380), 1300, (170, 200, 255), 0.55))
        bg = Image.alpha_composite(bg, radial_glow((S, S), (1700, 1800), 1100, (40, 20, 110), 0.45))
        glyph = (255, 255, 255)
    elif style == "dark":
        bg = gradient((S, S), (22, 24, 52), (48, 30, 104), 120)
        bg = Image.alpha_composite(bg, radial_glow((S, S), (500, 420), 1200, (90, 110, 255), 0.35))
        bg = Image.alpha_composite(bg, radial_glow((S, S), (1750, 1750), 1100, (130, 70, 255), 0.25))
        glyph = (255, 255, 255)
    else:  # tinted: scala di grigi su nero (iOS applica il colore scelto dall'utente)
        bg = Image.new("RGBA", (S, S), (0, 0, 0, 255))
        glyph = (255, 255, 255)

    img = bg.copy()
    cx = S // 2

    # --- corpo del telecomando
    rw, rh = 640, 1130
    top = 650
    box = (cx - rw // 2, top, cx + rw // 2, top + rh)
    radius = 270

    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 50, box[2], box[3] + 50), radius=radius, fill=(10, 8, 40, 120))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(60)))

    body_alpha = 70 if style != "tinted" else 60
    body = Image.new("RGBA", (S, S), glyph + (0,))
    grad = np.linspace(1.25, 0.65, S, dtype=np.float32)[:, None]
    a = (rounded_mask(box, radius)).copy()
    a_arr = (np.asarray(a, np.float32) / 255.0) * body_alpha * grad
    body.putalpha(Image.fromarray(a_arr.clip(0, 255).astype(np.uint8), "L"))
    img = Image.alpha_composite(img, body)

    edge = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(box, radius=radius, outline=glyph + (150,), width=8)
    img = Image.alpha_composite(img, edge)

    hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(hl).rounded_rectangle((box[0] + 22, box[1] + 22, box[2] - 22, box[1] + 300), radius=radius - 22, fill=glyph + (34,))
    hl.putalpha(Image.fromarray(((np.asarray(hl.split()[3], np.float32)) * (np.asarray(rounded_mask((box[0] + 22, box[1] + 22, box[2] - 22, box[3] - 22), radius - 22), np.float32) / 255.0)).astype(np.uint8), "L"))
    img = Image.alpha_composite(img, hl)

    def comp(fn):
        """Disegna su un livello trasparente e lo miscela: così la trasparenza dei colori è rispettata."""
        nonlocal img
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        fn(ImageDraw.Draw(layer))
        img = Image.alpha_composite(img, layer)

    # --- D-pad
    py = top + 400
    pr = 235
    comp(lambda d: d.ellipse((cx - pr, py - pr, cx + pr, py + pr), fill=glyph + (46,), outline=glyph + (130,), width=6))

    w = 26
    def chevron(pts):
        def draw(d):
            d.line(pts, fill=glyph + (235,), width=w, joint="curve")
            for (x, y) in (pts[0], pts[-1]):
                d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=glyph + (235,))
        comp(draw)
    o, k = 168, 34
    chevron([(cx - k, py - o + k // 2 + 6), (cx, py - o - k // 2 + 6), (cx + k, py - o + k // 2 + 6)])
    chevron([(cx - k, py + o - k // 2 - 6), (cx, py + o + k // 2 - 6), (cx + k, py + o - k // 2 - 6)])
    chevron([(cx - o + k // 2 + 6, py - k), (cx - o - k // 2 + 6, py), (cx - o + k // 2 + 6, py + k)])
    chevron([(cx + o - k // 2 - 6, py - k), (cx + o + k // 2 - 6, py), (cx + o - k // 2 - 6, py + k)])

    # tasto OK
    orad = 98
    ok_shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ok_shadow).ellipse((cx - orad, py - orad + 14, cx + orad, py + orad + 14), fill=(20, 10, 80, 110))
    img = Image.alpha_composite(img, ok_shadow.filter(ImageFilter.GaussianBlur(18)))
    if style != "tinted":
        ok = gradient((orad * 2, orad * 2), (255, 255, 255), (214, 220, 255), 90)
    else:
        ok = Image.new("RGBA", (orad * 2, orad * 2), (255, 255, 255, 255))
    m = Image.new("L", (orad * 2, orad * 2), 0)
    ImageDraw.Draw(m).ellipse((0, 0, orad * 2 - 1, orad * 2 - 1), fill=255)
    img.paste(ok, (cx - orad, py - orad), m)

    # --- tasti in basso
    by = top + 925
    def bottom(d):
        for dx in (-190, 0, 190):
            r = 62
            d.ellipse((cx + dx - r, by - r, cx + dx + r, by + r), fill=glyph + (60,), outline=glyph + (120,), width=5)
        d.rounded_rectangle((cx - 120, by + 120, cx + 120, by + 150), radius=15, fill=glyph + (80,))
    comp(bottom)

    # --- onde di segnale sopra il telecomando (archi con estremità tonde)
    ay = top - 40
    def waves(d):
        for r, alpha in ((150, 255), (270, 210), (390, 160)):
            steps = 90
            for i in range(steps + 1):
                ang = math.radians(235 + (305 - 235) * i / steps)
                x, y = cx + r * math.cos(ang), ay + r * math.sin(ang)
                d.ellipse((x - 22, y - 22, x + 22, y + 22), fill=glyph + (alpha,))
    arcs = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    waves(ImageDraw.Draw(arcs))
    img = Image.alpha_composite(img, arcs)

    out = img.convert("RGB").resize((1024, 1024), Image.LANCZOS)
    if style == "tinted":
        out = out.convert("L").convert("RGB")
    return out

os.makedirs(OUT, exist_ok=True)
for style, name in (("light", "AppIcon.png"), ("dark", "AppIcon-Dark.png"), ("tinted", "AppIcon-Tinted.png")):
    render(style).save(os.path.join(OUT, name))
    print("scritto", name)
