# Foliage albedo for the solid tree crowns (1128c C17): the CC0 twig / leaf atlas of each Poly Haven tree, scattered at random angles over a dark green
# ground with wrap-around, so it tiles. python3 -I tools/blender/crown_tex.py <twig.png> <out.jpg> <seed> <n> <scale>
import sys, random, math
from PIL import Image
src, out, seed, n, sc = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
rnd = random.Random(seed)
tw = Image.open(src).convert("RGBA")
r0, g0, b0, a0 = tw.split()   # keep only the green needles / leaves: the atlas also holds brown stems and a flat background
import numpy as np
arr = np.array(tw).astype(int); green = (arr[:, :, 1] > arr[:, :, 0] * 1.08) & (arr[:, :, 1] > arr[:, :, 2] * 1.1) & (arr[:, :, 3] > 60)
arr[:, :, 3] = np.where(green, 255, 0); tw = Image.fromarray(arr.astype("uint8"), "RGBA")
bb = tw.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
tw = tw.crop(bb)
S = 512
base = Image.new("RGB", (S, S), (22, 38, 14))
for i in range(n):
    t = tw.rotate(rnd.uniform(0, 360), expand=True, resample=Image.BICUBIC)
    k = sc * rnd.uniform(0.6, 1.2) * S / max(t.size)
    t = t.resize((max(2, int(t.width * k)), max(2, int(t.height * k))), Image.BICUBIC)
    shade = rnd.uniform(0.55, 1.0)
    r, g, b, a = t.split()
    t = Image.merge("RGBA", (r.point(lambda v: int(v * shade)), g.point(lambda v: int(v * shade)), b.point(lambda v: int(v * shade)), a))
    x = rnd.randrange(S); y = rnd.randrange(S)
    for dx in (-S, 0, S):
        for dy in (-S, 0, S):
            base.paste(t, (x + dx - t.width // 2, y + dy - t.height // 2), t)
base.save(out, quality=88)
