# Foliage sprites and the birch bark for the generated trees (treegen.py), drawn here (no source asset, nothing to attribute).
# python3 -I tools/blender/sprites.py <out-dir>
import sys, math, random
from PIL import Image, ImageDraw
out = sys.argv[1]
SS = 3

def fir_spray(seed):
    r = random.Random(seed); S = 256 * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    n = 38
    pts = []
    for i in range(n + 1):   # the stem: a gentle curve from the bottom centre up
        t = i / n; pts.append((S * (0.5 + 0.04 * math.sin(t * 2.2)), S * (0.97 - 0.94 * t)))
    d.line(pts, fill=(70, 52, 34, 255), width=int(3.2 * SS))
    for i in range(2, n):
        t = i / n; x, y = pts[i]; ln = S * 0.30 * (1.0 - 0.75 * t) * r.uniform(0.85, 1.1)
        for side in (-1, 1):
            a = math.radians(62 + r.uniform(-12, 12)) * side + math.radians(-18)   # forward-swept needles
            for k in range(3):
                aa = a + math.radians(r.uniform(-10, 10)); l2 = ln * r.uniform(0.7, 1.0)
                ex = x + math.sin(aa) * l2; ey = y - math.cos(aa) * l2 * 0.5 + l2 * 0.25
                g = r.randint(0, 30)
                d.line([(x, y), (ex, ey)], fill=(30 + g // 2, 78 + g, 34 + g // 2, 255), width=int(2.4 * SS))
    return im.resize((256, 256), Image.LANCZOS)

def leaf_cluster(seed, n, size, cols, pointed=0.0):
    r = random.Random(seed); S = 256 * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    leaves = []
    for i in range(n):
        a = r.uniform(0, math.tau); rr = math.sqrt(r.random()) * S * 0.40
        x = S / 2 + math.cos(a) * rr; y = S / 2 + math.sin(a) * rr * 0.9
        leaves.append((y, x, a))
    for y, x, a in sorted(leaves):   # back to front
        L = size * SS * r.uniform(0.8, 1.2); W = L * r.uniform(0.42, 0.6)
        ang = a + r.uniform(-0.6, 0.6)
        pts = []
        for k in range(14):
            t = k / 13 * math.tau
            px = math.cos(t) * L * 0.5; py = math.sin(t) * W * 0.5
            px *= 1.0 + pointed * (1 if px > 0 else 0.0) * (1.0 - abs(math.sin(t)))
            pts.append((x + px * math.cos(ang) - py * math.sin(ang), y + px * math.sin(ang) + py * math.cos(ang)))
        c = r.choice(cols); sh = r.uniform(0.75, 1.15)
        d.polygon(pts, fill=(min(255, int(c[0] * sh)), min(255, int(c[1] * sh)), min(255, int(c[2] * sh)), 255))
        d.line([(x - math.cos(ang) * L * 0.5, y - math.sin(ang) * L * 0.5), (x + math.cos(ang) * L * 0.4, y + math.sin(ang) * L * 0.4)], fill=(int(c[0] * 0.6), int(c[1] * 0.65), int(c[2] * 0.6), 255), width=SS)
    return im.resize((256, 256), Image.LANCZOS)

fir_spray(3).save(out + "/tree_spray_fir.png")
leaf_cluster(5, 90, 46, [(52, 92, 34), (66, 108, 40), (44, 80, 30), (78, 118, 46)], 0.5).save(out + "/tree_leaf_oak.png")
leaf_cluster(9, 70, 40, [(104, 140, 52), (120, 156, 60), (90, 126, 46), (136, 164, 70)], 0.9).save(out + "/tree_leaf_birch.png")
leaf_cluster(13, 80, 38, [(60, 100, 38), (84, 120, 44), (48, 88, 34), (110, 132, 50)], 0.3).save(out + "/tree_leaf_shrub.png")
# birch bark: white with dark horizontal lenticels
r = random.Random(21); S = 512
bark = Image.new("RGB", (S, S), (222, 218, 208)); d = ImageDraw.Draw(bark)
for i in range(520):
    x = r.randrange(S); y = r.randrange(S); w = r.randint(8, 46); h = r.randint(2, 6); g = r.randint(40, 90)
    for dx in (-S, 0, S):
        for dy in (-S, 0, S): d.ellipse([x + dx, y + dy, x + dx + w, y + dy + h], fill=(g, g - 6, g - 12))
for i in range(900):
    x = r.randrange(S); y = r.randrange(S); v = r.randint(190, 235); d.rectangle([x, y, x + r.randint(2, 14), y + 1], fill=(v, v - 3, v - 10))
bark.save(out + "/tree_birch_bark_albedo.jpg", quality=88)
