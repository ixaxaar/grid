# Blender headless: generated CC0-free trees (our own geometry, nothing to attribute) for GRID's woods, gardens and benches (1128c C17).
# Each tree is one skeleton: a tapering trunk, branches that fork, and foliage cards (alpha-tested sprites) that SIT ON a twig end, so no card hangs free
# of wood by construction (tests/vegetation_truth.gd checks it). Objects: "tr" (all wood, material "trunk"; vertex colours carry the tint) and "cd"
# (cards, material "twig"). usage: blender -b -P treegen.py -- <kind> <out-prefix>      kind: spruce | pine | oak | birch | shrub
import bpy, sys, math, random
import numpy as np
kind, outp = sys.argv[sys.argv.index("--") + 1:][:2]

def norm(v):
    n = np.linalg.norm(v); return v / n if n > 1e-9 else np.array([0.0, 0.0, 1.0])

class Mesh:
    def __init__(self): self.V = []; self.N = []; self.UV = []; self.C = []; self.T = []
    def add_tri(self, a, b, c):
        g = np.cross(np.array(self.V[b]) - np.array(self.V[a]), np.array(self.V[c]) - np.array(self.V[a]))
        n = np.array(self.N[a]) + np.array(self.N[b]) + np.array(self.N[c])
        self.T.append((a, b, c) if float(g @ n) >= 0 else (a, c, b))

def tube(m, pts, radii, seg, col, uv_len=2.0, cap_end=True):
    """A tapering tube along `pts` (z up), `seg` sides. Smooth normals; UV u round, v along the length in uv_len metres."""
    rings = []; acc = 0.0
    prev_up = np.array([1.0, 0.0, 0.0])
    for i, p in enumerate(pts):
        d = norm(pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
        s = np.cross(d, prev_up)
        if np.linalg.norm(s) < 1e-4: s = np.cross(d, np.array([0.0, 1.0, 0.0]))
        s = norm(s); u = norm(np.cross(s, d)); prev_up = u
        if i > 0: acc += np.linalg.norm(pts[i] - pts[i - 1])
        ring = []
        for k in range(seg + 1):
            a = math.tau * k / seg; o = math.cos(a) * s + math.sin(a) * u
            m.V.append(tuple(p + o * radii[i])); m.N.append(tuple(o)); m.UV.append((k / seg, acc / uv_len)); m.C.append(col); ring.append(len(m.V) - 1)
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(seg):
            a, b, c, d = rings[i][k], rings[i][k + 1], rings[i + 1][k + 1], rings[i + 1][k]
            m.add_tri(a, b, c); m.add_tri(a, c, d)

def card(m, c, au, av, out_dir, col=(1, 1, 1, 1), bend=0.0):
    """A quad centred at c, spanned by au (half width) and av (half height), shaded as part of a mass: the normal leans outward."""
    q = norm(np.cross(au, av))
    if q @ out_dir < 0: q = -q
    n = norm(0.6 * q + 0.4 * norm(out_dir))
    if abs(q[2]) < 0.6: n = norm(np.array([n[0], n[1], min(n[2], 0.35 * np.linalg.norm(n))]))   # a standing card is never shaded as a roof (mesh_winding_truth)
    base = len(m.V)
    for (su, sv, uu, vv) in ((-1, -1, 0, 0), (1, -1, 1, 0), (1, 1, 1, 1), (-1, 1, 0, 1)):
        m.V.append(tuple(c + au * su + av * sv + (q * bend * (1 - abs(su)) if bend else 0))); m.N.append(tuple(n)); m.UV.append((uu, 1 - vv)); m.C.append(col)
    m.add_tri(base, base + 1, base + 2); m.add_tri(base, base + 2, base + 3)

rnd = random.Random(7 if kind != "spruce" else 4)
W = Mesh(); L = Mesh()   # wood, leaves
LOD = 0
P = {}

def lerp3(a, b, t): return a + (b - a) * t

def branch(start, d0, length, r0, r1, bend, level, droop, seg, nseg, wood_col, leaf_fn):
    """A curved branch: returns its points. Leaves are placed by leaf_fn(points, level)."""
    pts = [np.array(start)]; d = norm(d0)
    step = length / nseg
    for i in range(nseg):
        d = norm(d + np.array([rnd.uniform(-bend, bend), rnd.uniform(-bend, bend), 0.0]) + np.array([0, 0, droop]))
        pts.append(pts[-1] + d * step)
    radii = [lerp3(r0, r1, i / nseg) for i in range(nseg + 1)]
    tube(W, pts, radii, seg, wood_col)
    leaf_fn(pts, level, d)
    return pts, d

def spray_cards(pts, d_end, n, size, out_dir, flat=True):
    """Fir/pine needle sprays along the outer part of a branch: a drooping vertical frond and a flat one per position."""
    for i in range(n):
        t = 0.3 + 0.7 * (i + 1) / n
        k = min(int(t * (len(pts) - 1)), len(pts) - 2)
        p = lerp3(pts[k], pts[k + 1], t * (len(pts) - 1) - k)
        along = norm(pts[min(k + 1, len(pts) - 1)] - pts[k])
        sidev = norm(np.cross(along, np.array([0, 0, 1.0])))
        w = size * (1.15 - 0.5 * t)
        # frond lying in the branch plane (needles fan out to both sides), then one hanging below
        card(L, p + along * w * 0.35, sidev * w * 0.55, along * w * 0.5, out_dir)
        if flat: card(L, p + np.array([0, 0, -w * 0.18]) + along * w * 0.25, np.array([0, 0, w * 0.34]), along * w * 0.5, out_dir)

def tuft(p, size, out_dir, n=3):
    """A round clump of foliage on a twig end: n crossed quads (a star) around a tilted axis."""
    base = rnd.uniform(0, math.pi)
    for i in range(n):
        a = base + math.pi * i / n
        au = np.array([math.cos(a), math.sin(a), 0.0]) * size * 0.5
        av = np.array([0, 0, 1.0]) * size * 0.42
        card(L, p, au, av, out_dir)
    card(L, p, np.array([1.0, 0, 0]) * size * 0.5, np.array([0, 1.0, 0]) * size * 0.5, out_dir + np.array([0, 0, 0.6]))   # a roof to the clump, through the twig end like the others

def fan_tuft(p, size, out_dir, n=5):
    """A pine's needle tuft: n fronds of the spray sprite fanned out and up from the twig end (each frond's stem points away from the twig)."""
    out = norm(out_dir)
    for i in range(n):
        a = math.tau * i / n + rnd.uniform(-0.3, 0.3)
        dirv = norm(out * 0.7 + np.array([math.cos(a), math.sin(a), 0.0]) * 0.75 + np.array([0, 0, 0.45 + 0.2 * rnd.random()]))
        side = norm(np.cross(dirv, np.array([0, 0, 1.0])))
        card(L, p + dirv * size * 0.5, side * size * 0.30, dirv * size * 0.5, out)

# ---------------------------------------------------------------------------------------------------------------------
lod = int(sys.argv[sys.argv.index("--") + 3]) if len(sys.argv) > sys.argv.index("--") + 3 else 0
def build(kind, lod):
    global W, L, rnd
    W = Mesh(); L = Mesh(); rnd = random.Random({"spruce": 4, "pine": 6, "oak": 8, "birch": 10, "shrub": 12}[kind])
    seg = 6 if lod == 0 else 4
    dens = 1.0 if lod == 0 else 0.45
    brown = (0.92, 0.88, 0.84, 1.0)
    if kind == "spruce":
        H = 14.0; r0 = 0.20
        n = 18 if lod == 0 else 8
        trunk = [np.array([0.12 * math.sin(i * 0.6), 0.08 * math.cos(i * 0.5), H * i / n]) for i in range(n + 1)]
        tube(W, trunk, [lerp3(r0, 0.015, (i / n) ** 0.8) for i in range(n + 1)], seg + 2 if lod == 0 else 5, brown, 3.0)
        z = 1.2
        while z < H * 0.97:
            f = (z - 1.2) / (H * 0.97 - 1.2)
            nb = 5 if lod == 0 else 4
            a0 = rnd.uniform(0, math.tau)
            for b in range(nb):
                a = a0 + math.tau * b / nb + rnd.uniform(-0.25, 0.25)
                ln = (2.9 * (1 - f) ** 0.85 + 0.45) * rnd.uniform(0.85, 1.1)
                zi = min(int(z / H * n), n - 1); st = lerp3(trunk[zi], trunk[zi + 1], z / H * n - zi)
                d0 = np.array([math.cos(a), math.sin(a), -0.28 + 0.5 * f])
                nseg = 3 if lod == 0 else 2
                def lf(pts, level, d, ln=ln, a=a):
                    spray_cards(pts, d, 3 if lod == 0 else 2, ln * 0.62, np.array([math.cos(a), math.sin(a), 0.2]))
                branch(st, d0, ln, 0.045 * (1 - f) + 0.012, 0.008, 0.06, 1, 0.04 + 0.0 * f, 4 if lod == 0 else 3, nseg, brown, lf)
            z += (0.46 if lod == 0 else 0.95) * (0.85 + 0.3 * rnd.random())
        # the leader tip
        spray_cards([trunk[-2], trunk[-1]], np.array([0, 0, 1.0]), 2, 1.2, np.array([0, 0, 1.0]), flat=False)
    elif kind == "pine":
        H = 15.0; r0 = 0.24
        n = 14 if lod == 0 else 6
        trunk = [np.array([0.35 * math.sin(i * 0.45) , 0.25 * math.cos(i * 0.4), H * i / n]) for i in range(n + 1)]
        tube(W, trunk, [lerp3(r0, 0.03, (i / n) ** 1.1) for i in range(n + 1)], seg + 2 if lod == 0 else 5, (0.92, 0.88, 0.84, 1.0), 3.0)
        zs = [H * t for t in (0.50, 0.58, 0.66, 0.73, 0.80, 0.86, 0.92, 0.97)]
        if lod == 1: zs = zs[::2]
        for zi_, z in enumerate(zs):
            a0 = rnd.uniform(0, math.tau)
            for b in range(3):
                a = a0 + math.tau * b / 3 + rnd.uniform(-0.4, 0.4); f = (z / H - 0.5) / 0.47
                ln = 3.4 * (1 - 0.65 * f) * rnd.uniform(0.85, 1.1)
                zi = min(int(z / H * n), n - 1); st = lerp3(trunk[zi], trunk[zi + 1], z / H * n - zi)
                def lf(pts, level, d, a=a, ln=ln):
                    if level == 2:
                        fan_tuft(pts[-1], 3.5 if lod == 0 else 4.0, np.array([math.cos(a), math.sin(a), 0.4]), 9 if lod == 0 else 5)
                        if lod == 0: fan_tuft(pts[1], 2.6, np.array([math.cos(a), math.sin(a), 0.5]), 6)
                        return
                    pts_t = pts[-1]
                    for s2 in (-1, 1):
                        dd = norm(d + np.array([-math.sin(a) * s2 * 0.9, math.cos(a) * s2 * 0.9, 0.25]))
                        branch(pts_t, dd, ln * 0.45, 0.02, 0.006, 0.08, 2, 0.0, 3, 2, (0.92, 0.88, 0.84, 1.0), lf)
                branch(st, np.array([math.cos(a), math.sin(a), 0.32]), ln, 0.05 * (1 - f * 0.6) + 0.02, 0.012, 0.07, 1, 0.0, 4 if lod == 0 else 3, 3, (0.92, 0.88, 0.84, 1.0), lf)
        fan_tuft(trunk[-1], 2.6, np.array([0, 0, 1.0]), 6)
    elif kind in ("oak", "birch"):
        H = 11.0 if kind == "oak" else 12.0
        r0 = 0.34 if kind == "oak" else 0.13
        col = brown if kind == "oak" else (0.95, 0.95, 0.92, 1.0)
        hsplit = 0.32 if kind == "oak" else 0.42
        n = 6
        trunk = [np.array([0.25 * math.sin(i * 0.8), 0.2 * math.cos(i * 0.6), H * hsplit * i / n]) for i in range(n + 1)]
        tube(W, trunk, [lerp3(r0, r0 * 0.62, i / n) for i in range(n + 1)], seg + 2 if lod == 0 else 5, col, 2.0)
        top = trunk[-1]
        nl = (5 if lod == 0 else 4) if kind == "oak" else (6 if lod == 0 else 4)
        csize = 2.9 if kind == "oak" else 2.3
        for b in range(nl):
            a = math.tau * b / nl + rnd.uniform(-0.3, 0.3)
            up = 0.9 if kind == "oak" else 1.8
            ln = H * (0.5 if kind == "oak" else 0.55) * rnd.uniform(0.8, 1.05)
            def lf(pts, level, d, a=a):
                out = norm(np.array([math.cos(a), math.sin(a), 0.5]))
                if level >= 2 or (level == 1 and lod == 1):
                    tuft(pts[-1], csize * (1.0 if lod == 0 else 1.35), out, 3)
                    if lod == 0:
                        tuft(lerp3(pts[len(pts) // 2], pts[-1], 0.5) + np.array([0, 0, 0.15]), csize * 0.85, out, 3)
                        tuft(pts[-2], csize * 0.75, out, 3)
                    return
                if level == 1:
                    tw = 4 if kind == "oak" else 2
                    for q in range(tw):
                        sa = a + (q - (tw - 1) / 2) * 0.9 + rnd.uniform(-0.2, 0.2)
                        dd = norm(d + np.array([math.cos(sa) * 0.8, math.sin(sa) * 0.8, 0.15]))
                        branch(pts[-1] if q else pts[len(pts) // 2 + 1 if len(pts) > 2 else -1], dd, ln * 0.42, 0.045 if kind == "oak" else 0.02, 0.012, 0.15, 2, 0.0, 4, 2, col if kind == "oak" else (0.9, 0.9, 0.88, 1), lf)
            def lf0(pts, level, d, a=a, lf=lf):
                lf(pts, 1, d, a)
            main_pts, d_end = branch(top, np.array([math.cos(a), math.sin(a), up]), ln, r0 * 0.42 if kind == "oak" else 0.06, 0.03, 0.12, 0.012, 0, 4 if lod == 0 else 3, 3, col, lf0)
        # a leader: one limb straight up with its own crown clump
        def lfl(pts, level, d): tuft(pts[-1], csize * 1.1, np.array([0, 0, 1.0]), 3)
        branch(top, np.array([0.05, 0.05, 1.0]), H * 0.5, r0 * 0.36 if kind == "oak" else 0.05, 0.03, 0.05, 0, 0.0, 4 if lod == 0 else 3, 3, col, lfl)
    else:   # shrub
        H = 1.6
        for b in range(7 if lod == 0 else 4):
            a = math.tau * b / 7 + rnd.uniform(-0.3, 0.3)
            def lf(pts, level, d, a=a):
                tuft(pts[-1], 0.95, np.array([math.cos(a), math.sin(a), 0.5]), 3)
                if lod == 0: tuft(pts[1], 0.7, np.array([math.cos(a), math.sin(a), 0.5]), 3)
            branch(np.array([0.05 * math.cos(a), 0.05 * math.sin(a), 0.0]), np.array([math.cos(a) * 0.55, math.sin(a) * 0.55, 1.0]), 1.5 * rnd.uniform(0.75, 1.05), 0.03, 0.01, 0.1, 0, 0.0, 4, 2, (0.85, 0.8, 0.75, 1), lf)

def to_obj(m, name, matname):
    me = bpy.data.meshes.new(name); me.from_pydata(m.V, [], m.T); me.update()
    uv = me.uv_layers.new(name="UVMap")
    for li, l in enumerate(me.loops): uv.data[li].uv = m.UV[l.vertex_index]
    try: me.normals_split_custom_set_from_vertices(m.N)
    except Exception as ex: print("NOCUSTOMN", ex)
    ca = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    for i, c in enumerate(m.C): ca.data[i].color = c
    me.materials.append(bpy.data.materials.get(matname) or bpy.data.materials.new(matname))
    o = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(o); return o

bpy.ops.wm.read_factory_settings(use_empty=True)
for lod in (0, 1):
    build(kind, lod)
    objs = [to_obj(W, "tr", "trunk")]
    if L.V:
        L.C = [(1, 1, 1, 1)] * len(L.V); objs.append(to_obj(L, "cd", "twig"))
    for o in bpy.context.scene.objects: o.select_set(o in objs)
    print("LOD", lod, kind, [(o.name, len(o.data.polygons)) for o in objs])
    bpy.ops.export_scene.gltf(filepath=f"{outp}_lod{lod}.glb", export_format="GLB", use_selection=True, export_apply=True, export_materials="EXPORT", export_image_format="NONE", export_yup=True, export_vertex_color="ACTIVE")
    for o in objs: bpy.data.objects.remove(o)
print("DONE")
