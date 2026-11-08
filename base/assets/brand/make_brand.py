"""Smof channel art: avatar (two variants) and banner. Run from base/splash."""
import math
from PIL import Image, ImageDraw, ImageFont, ImageFilter

FONT = "../assets/GoogleSansFlex.ttf"
NAVY_T, NAVY_B = (30, 21, 52), (13, 11, 20)
PEACH = (255, 183, 138)

def font(size, wght=420):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([min(size, 144), wght])
    return f

def gradient(w, h):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        c = tuple(int(NAVY_T[i] + (NAVY_B[i] - NAVY_T[i]) * t) for i in range(3))
        for x in range(w): px[x, y] = c
    return img

def dunes(w, h):
    """soft peach dunes along the bottom, like the wallpaper"""
    base = gradient(w, h).convert("RGBA")
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k, (amp, y0, ph, alpha) in enumerate([(0.07, 0.72, 0.0, 34), (0.06, 0.80, 1.7, 52), (0.05, 0.89, 3.1, 80)]):
        pts = [(0, h)]
        for x in range(0, w + 8, 8):
            pts.append((x, h * (y0 + amp * math.sin(x / w * 5.2 + ph) + 0.03 * math.sin(x / w * 11 + ph * 2))))
        pts.append((w, h))
        d.polygon(pts, fill=PEACH + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(h * 0.004))
    return Image.alpha_composite(base, layer)

def spaced(draw, text, f, cx, y, track, fill):
    w = sum(f.getlength(c) for c in text) + track * (len(text) - 1)
    x = cx - w / 2
    for c in text:
        draw.text((x, y), c, font=f, fill=fill)
        x += f.getlength(c) + track
    return w

S = 2   # draw at double size and shrink for smooth edges

# ---- avatar A: the wordmark ----
W = 800 * S
a = dunes(W, W)
d = ImageDraw.Draw(a)
f = font(190 * S, 420)
bb = f.getbbox("smof")
spaced(d, "smof", f, W / 2, W / 2 - (bb[1] + bb[3]) / 2 - 6 * S, 10 * S, (255, 255, 255, 255))
a.convert("RGB").resize((800, 800), Image.LANCZOS).save("../assets/brand/avatar-wordmark.png")

# ---- avatar B: a donut ring with the s ----
b = dunes(W, W)
d = ImageDraw.Draw(b)
cx = cy = W / 2
R, r = 300 * S, 118 * S
# soft shadow under the ring
sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ImageDraw.Draw(sh).ellipse([cx - R, cy - R + 16 * S, cx + R, cy + R + 16 * S], fill=(0, 0, 0, 110))
b = Image.alpha_composite(b, sh.filter(ImageFilter.GaussianBlur(14 * S)))
d = ImageDraw.Draw(b)
d.ellipse([cx - R, cy - R, cx + R, cy + R], fill=PEACH + (255,))
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(0, 0, 0, 0))
# punch the hole to the background
hole = dunes(W, W).crop((int(cx - r), int(cy - r), int(cx + r), int(cy + r)))
mask = Image.new("L", hole.size, 0); ImageDraw.Draw(mask).ellipse([0, 0, hole.size[0] - 1, hole.size[1] - 1], fill=255)
b.paste(hole, (int(cx - r), int(cy - r)), mask)
d = ImageDraw.Draw(b)
# glaze: a wavy lighter band on top half of the ring
glaze = Image.new("RGBA", (W, W), (0, 0, 0, 0)); g = ImageDraw.Draw(glaze)
mid = (R + r) / 2
for i in range(0, 361, 2):
    ang = math.radians(i)
    wob = 1 + 0.11 * math.sin(ang * 7)
    rad_o = R * 0.985; rad_i = mid * wob
    # draw the lighter glaze on the upper half only
glaze_mask = Image.new("L", (W, W), 0); gm = ImageDraw.Draw(glaze_mask)
pts = []
for i in range(0, 361, 2):
    ang = math.radians(i)
    pts.append((cx + (mid + (R - mid) * 0.0 + 36 * S * math.sin(ang * 6)) * math.cos(ang), cy + (mid + 36 * S * math.sin(ang * 6)) * math.sin(ang)))
gm.ellipse([cx - R * 0.97, cy - R * 0.97, cx + R * 0.97, cy + R * 0.97], fill=255)
gm.ellipse([cx - (r + 26 * S), cy - (r + 26 * S), cx + (r + 26 * S), cy + (r + 26 * S)], fill=0)
gcol = Image.new("RGBA", (W, W), (255, 214, 176, 255))
b = Image.composite(gcol, b, glaze_mask.point(lambda v: int(v * 0.55)))
d = ImageDraw.Draw(b)
# the s in the middle of the hole is too small to read, so it sits on the ring's bottom-right like a bite mark: use the dark navy s in the hole
fs = font(150 * S, 520)
sb = fs.getbbox("s")
d.text((cx - (sb[0] + sb[2]) / 2, cy - (sb[1] + sb[3]) / 2), "s", font=fs, fill=(255, 255, 255, 255))
b.convert("RGB").resize((800, 800), Image.LANCZOS).save("../assets/brand/avatar-donut.png")

# ---- banner 2560x1440, safe area 1546x423 in the middle ----
BW, BH = 2560 * S // 2, 1440 * S // 2   # work at 1.0 x S/2 to keep it light
BW, BH = 2560, 1440
ban = dunes(BW, BH)
d = ImageDraw.Draw(ban)
f = font(230, 420)
bb = f.getbbox("smof")
spaced(d, "smof", f, BW / 2, BH / 2 - (bb[1] + bb[3]) / 2 - 40, 30, (255, 255, 255, 255))
f2 = font(58, 360)
t2 = "a friendly arch linux desktop"
w2 = f2.getlength(t2)
d.text(((BW - w2) / 2, BH / 2 + 120), t2, font=f2, fill=PEACH + (255,))
ban.convert("RGB").save("../assets/brand/banner.png")
print("ok")
