# Blender headless: re-cut a Poly Haven photoscanned tree (CC0) so that NO foliage card hangs free of wood (1128c C17, third pass).
#   wood    = the trunk, branches and twigs of the scan, decimated with COLLAPSE (the surface stays connected) and kept;
#   foliage = the scan's thousands of needle / leaf islands are grouped by voxel into clusters; each cluster becomes two crossed cards laid along its own
#             axes, whose alpha atlas is BAKED from the real islands (their segments painted in the colour the scan's texture gives them); a thin
#             stub of wood joins the nearest kept wood vertex to the cluster, so every card has a twig end inside it (tests/vegetation_truth.gd).
# usage: blender -b -P recut.py -- <gltf> <objname-substring> <foliage-mat-substr> <out-prefix> <kind fir|broad> <clusters0> <clusters1> <tile0> <tile1> <trunk_tris> <bark_tris>
import bpy, sys, math, random
import numpy as np
from scipy.sparse import coo_matrix
from scipy.sparse.csgraph import connected_components
from scipy.spatial import cKDTree
from PIL import Image
a = sys.argv[sys.argv.index("--") + 1:]
src, objsub, folsub, outp, kind = a[:5]
K0, K1, T0, T1, TR_T, BK_T = [int(x) for x in a[5:11]]
DIL = float(a[11]) if len(a) > 11 else 0.0

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obj = [o for o in bpy.context.scene.objects if o.type == "MESH" and objsub in o.name][0]
me = obj.data
mats = [m.name for m in me.materials]
print("MATS", mats)
nv = len(me.vertices); npoly = len(me.polygons)
co = np.empty(nv * 3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3).astype(np.float64)
pm = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("material_index", pm)
nl = len(me.loops)
lv = np.empty(nl, dtype=np.int32); me.loops.foreach_get("vertex_index", lv)
ls = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_start", ls)
lt = np.empty(npoly, dtype=np.int32); me.polygons.foreach_get("loop_total", lt)
uvl = me.uv_layers.active
uvs = np.empty(nl * 2, dtype=np.float32); uvl.data.foreach_get("uv", uvs); uvs = uvs.reshape(-1, 2)
print("MESH", nv, npoly)

def is_fol(i): return folsub in mats[i]
fol_mats = np.array([is_fol(i) for i in range(len(mats))])
fpoly = np.where(fol_mats[pm])[0]
# triangles of the foliage (the scan is triangulated; quads are split)
tri = []; tuv = []
for p in fpoly:
    s = ls[p]; n = lt[p]
    for k in range(1, n - 1): tri.append((lv[s], lv[s + k], lv[s + k + 1])); tuv.append((uvs[s], uvs[s + k], uvs[s + k + 1]))
tri = np.array(tri, dtype=np.int64); tuv = np.array(tuv, dtype=np.float64)
print("FOLIAGE TRIS", len(tri))
# islands = connected components of the foliage vertex graph
used = np.unique(tri.ravel()); remap = -np.ones(nv, dtype=np.int64); remap[used] = np.arange(len(used))
t2 = remap[tri]
rows = np.concatenate([t2[:, 0], t2[:, 1], t2[:, 2]]); cols = np.concatenate([t2[:, 1], t2[:, 2], t2[:, 0]])
g = coo_matrix((np.ones(len(rows)), (rows, cols)), shape=(len(used), len(used)))
ncomp, lab = connected_components(g, directed=False)
print("ISLANDS", ncomp)
P = co[used]
cnt = np.bincount(lab, minlength=ncomp).astype(np.float64)
cen = np.stack([np.bincount(lab, weights=P[:, k], minlength=ncomp) for k in range(3)], 1) / cnt[:, None]
# island colour: the scan's texture at the mean UV of the island's triangles
img = bpy.data.images
twig_img = None
for m in me.materials:
    if folsub in m.name and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image is not None: twig_img = n.image; break
if twig_img is None: twig_img = [i for i in bpy.data.images if folsub in i.name or "twig" in i.name or "leaves" in i.name][0]
W, H = twig_img.size; px = np.empty(W * H * 4, dtype=np.float32); twig_img.pixels.foreach_get(px); px = px.reshape(H, W, 4)
tri_lab = lab[t2[:, 0]]
uvm = tuv.mean(1)
ixs = np.clip((uvm[:, 0] % 1.0) * W, 0, W - 1).astype(int); iys = np.clip((uvm[:, 1] % 1.0) * H, 0, H - 1).astype(int)
tcol = px[iys, ixs, :3]
icol = np.stack([np.bincount(tri_lab, weights=tcol[:, k], minlength=ncomp) for k in range(3)], 1)
tcount = np.bincount(tri_lab, minlength=ncomp).astype(np.float64)
icol = icol / np.maximum(tcount, 1)[:, None]
# island segment: farthest vertex from the centre, then the farthest from that
d1 = np.linalg.norm(P - cen[lab], axis=1)
order = np.lexsort((d1, lab)); last = np.r_[np.where(np.diff(lab[order]) != 0)[0], len(order) - 1]
pa = P[order[last]]
d2 = np.linalg.norm(P - pa[lab], axis=1)
order2 = np.lexsort((d2, lab)); last2 = np.r_[np.where(np.diff(lab[order2]) != 0)[0], len(order2) - 1]
pb = P[order2[last2]]
print("ISLAND SEGMENTS", len(pa))

# ---- wood: everything that is not foliage and not the dead twigs of the ground, decimated by collapse
def sub(pred):
    import bmesh
    bm = bmesh.new(); bm.from_mesh(me)
    bad = [f for f in bm.faces if not pred(mats[f.material_index])]
    bmesh.ops.delete(bm, geom=bad, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    return bm
def to_obj(bm, name, matname):
    m = bpy.data.meshes.new(name); bm.to_mesh(m); bm.free()
    m.materials.clear(); mt = bpy.data.materials.get(matname) or bpy.data.materials.new(matname); m.materials.append(mt)
    o = bpy.data.objects.new(name, m); bpy.context.scene.collection.objects.link(o); return o
exec(open("tools/nrm.py").read())
def tri_count(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
def decimate(o, target):
    t = tri_count(o)
    if t <= target: return
    md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = target / t; md.use_collapse_triangulate = True
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.scene.objects: x.select_set(x == o)
    bpy.ops.object.modifier_apply(modifier="d")
trunk_names = [n for n in mats if ("trunk" in n or n.endswith("_trunk"))]
bark_names = [n for n in mats if ("bark" in n or "branches" in n) and "dead" not in n]
def make_wood(trt, bkt):
    global wood_v, wood_kd
    tr = to_obj(sub(lambda n: n in trunk_names), "tr", "trunk"); decimate(tr, trt); clean_normals(tr)
    bk = None
    if bkt > 0: bk = to_obj(sub(lambda n: n in bark_names), "bk", "bark"); decimate(bk, bkt); clean_normals(bk)
    ws = [o for o in (tr, bk) if o is not None]
    for o in ws:
        for v in o.data.vertices: v.co.z -= zb
    wood_v = np.array([tuple(v.co) for o in ws for v in o.data.vertices], dtype=np.float64)
    wood_kd = cKDTree(wood_v)
    return tr, bk
_t = to_obj(sub(lambda n: n in trunk_names), "t0", "trunk"); zb = min(v.co.z for v in _t.data.vertices); bpy.data.objects.remove(_t)
P[:, 2] -= zb; cen[:, 2] -= zb; pa[:, 2] -= zb; pb[:, 2] -= zb
tree_h = float(cen[:, 2].max())

# ---- clusters: voxels of the island centres
fmin = cen.min(0); fmax = cen.max(0)
def build(K, T, lod):
    vol = float(np.prod(np.maximum(fmax - fmin, 1e-3)))
    cell = (vol / K) ** (1 / 3) * 0.9
    for _ in range(6):
        key = np.floor((cen - fmin) / cell).astype(np.int64)
        ukey, inv = np.unique(key, axis=0, return_inverse=True)
        good = np.bincount(inv) >= 12
        if good.sum() > K * 1.25: cell *= 1.12
        elif good.sum() < K * 0.8: cell *= 0.92
        else: break
    inv = inv.ravel()
    cl = [np.where(inv == c)[0] for c in range(len(ukey)) if (inv == c).sum() >= 12]
    print("LOD", lod, "clusters", len(cl), "cell %.2f" % cell)
    n_cards = len(cl) * 2
    side = int(math.ceil(math.sqrt(n_cards)))
    atlas = np.zeros((side * T, side * T, 4), dtype=np.uint8)
    V = []; N = []; UV = []; Tt = []; stubs = []
    rnd = random.Random(3)
    axis_xy = np.array([0.0, 0.0])
    tile = 0
    for ci, idx in enumerate(cl):
        c = cen[idx].mean(0)
        C = np.cov((cen[idx] - c).T) + np.eye(3) * 1e-9
        w, v = np.linalg.eigh(C); e1, e2, e3 = v[:, 2], v[:, 1], v[:, 0]
        pts = np.concatenate([pa[idx], pb[idx]]); cols = np.concatenate([icol[idx], icol[idx]])
        out = np.array([c[0], c[1], 0.0]); out = out / (np.linalg.norm(out) + 1e-9) if np.linalg.norm(out) > 1e-6 else np.array([1.0, 0, 0])
        for (au_, av_, nrm_) in ((e1, e2, e3), (e1, e3, e2)):
            u = (pts - c) @ au_; vv = (pts - c) @ av_
            hu = max(np.abs(u).max(), 0.08); hv = max(np.abs(vv).max(), 0.08)
            ty, tx = divmod(tile, side); tile += 1
            tl = np.zeros((T, T, 4), dtype=np.uint8)
            # island segments painted as short thick strokes in the island's colour (back to front by depth along the card normal)
            dep = (pts[: len(idx)] - c) @ nrm_
            o_ = np.argsort(dep)
            sa = pa[idx][o_]; sb = pb[idx][o_]; sc = icol[idx][o_]
            for f in np.linspace(0.0, 1.0, 5):
                q = sa + (sb - sa) * f
                x = (((q - c) @ au_) / hu * 0.5 + 0.5) * (T - 1); y = (((q - c) @ av_) / hv * 0.5 + 0.5) * (T - 1)
                xi = np.clip(np.round(x).astype(int), 0, T - 1); yi = np.clip(np.round(y).astype(int), 0, T - 1)
                col8 = np.clip(sc * 255.0 * 1.0, 0, 255).astype(np.uint8)
                for dx, dy in ((0, 0), (1, 0), (0, 1), (-1, 0), (0, -1)):
                    xx = np.clip(xi + dx, 0, T - 1); yy = np.clip(yi + dy, 0, T - 1)
                    tl[yy, xx, :3] = col8; tl[yy, xx, 3] = 255
            if DIL > 0:   # thicken: every empty pixel within DIL of a painted one takes that pixel's colour (a needle / leaf is bigger than the sampled stroke)
                from scipy import ndimage
                emp = tl[:, :, 3] == 0
                dist, (iy_, ix_) = ndimage.distance_transform_edt(emp, return_indices=True)
                fill = emp & (dist <= DIL)
                tl[fill] = tl[iy_[fill], ix_[fill]]
            atlas[ty * T:(ty + 1) * T, tx * T:(tx + 1) * T] = tl[::-1]
            n = au_ * 0 + nrm_
            if n @ out < 0: n = -n
            nn = 0.6 * n + 0.4 * out
            if abs(nrm_[2]) < 0.6: nn = np.array([nn[0], nn[1], min(nn[2], 0.35 * np.linalg.norm(nn))])
            nn = nn / np.linalg.norm(nn)
            b = len(V)
            for (su, sv, uu, vv_) in ((-1, -1, 0, 0), (1, -1, 1, 0), (1, 1, 1, 1), (-1, 1, 0, 1)):
                V.append(tuple(c + au_ * hu * su + av_ * hv * sv)); N.append(tuple(nn))
                UV.append(((tx + (0.02 + 0.96 * uu)) / side, 1.0 - (ty + (0.02 + 0.96 * (1 - vv_))) / side))
            for tr_ in ((b, b + 1, b + 2), (b, b + 2, b + 3)):
                pa_, pb_, pc_ = [np.array(V[k]) for k in tr_]
                gn = np.cross(pb_ - pa_, pc_ - pa_)
                Tt.append(tr_ if float(gn @ nn) >= 0 else (tr_[0], tr_[2], tr_[1]))
        d, wi = wood_kd.query(c)
        if d > 0.03: stubs.append((wood_v[wi], c))
    centres_ = np.array([cen[idx].mean(0) for idx in cl]); radius_ = cell * 0.5
    return V, N, UV, Tt, atlas, stubs, centres_, radius_

def trim_bark(bk, tr, ccen, crad):
    """Cut every piece of branch that ends outside the foliage (a bare twig tip poking out of the crown reads as a stray bit): a bark face stays when
    all its vertices are inside some cluster's sphere or within 0.15 m of the trunk."""
    import bmesh
    kd = cKDTree(ccen); tk = cKDTree(np.array([tuple(v.co) for v in tr.data.vertices]))
    bm = bmesh.new(); bm.from_mesh(bk.data)
    def ok(co):
        p = np.array(co); return kd.query(p)[0] <= crad or tk.query(p)[0] <= 0.15
    bad = [f for f in bm.faces if not all(ok(v.co) for v in f.verts)]
    bmesh.ops.delete(bm, geom=bad, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(bk.data); bm.free()

def stub_obj(stubs):
    V = []; Tt = []
    for (a_, b_) in stubs:
        d = b_ - a_; L = np.linalg.norm(d)
        if L < 1e-3: continue
        d = d / L; s = np.cross(d, [0, 0, 1.0]);
        if np.linalg.norm(s) < 1e-3: s = np.cross(d, [0, 1.0, 0])
        s = s / np.linalg.norm(s); u = np.cross(d, s)
        base = len(V)
        for end, r in ((a_, 0.014), (b_, 0.006)):
            for k in range(3):
                ang = math.tau * k / 3; V.append(tuple(end + (s * math.cos(ang) + u * math.sin(ang)) * r))
        for k in range(3):
            k2 = (k + 1) % 3
            Tt.append((base + k, base + k2, base + 3 + k2)); Tt.append((base + k, base + 3 + k2, base + 3 + k))
    me2 = bpy.data.meshes.new("st"); me2.from_pydata(V, [], Tt); me2.update()
    me2.materials.append(bpy.data.materials.get("bark") or bpy.data.materials.new("bark"))
    uv = me2.uv_layers.new(name="UVMap")
    for l in me2.loops: uv.data[l.index].uv = (0.5, 0.5)
    o = bpy.data.objects.new("bs", me2); bpy.context.scene.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.scene.objects: x.select_set(x == o)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    return o

for lod, (K, T) in enumerate(((K0, T0), (K1, T1))):
    for o in list(bpy.data.objects):
        if o.name in ("tr", "bk", "cd", "bs"): bpy.data.objects.remove(o)
    tr, bk = make_wood(TR_T, BK_T) if lod == 0 else make_wood(250, 0)
    V, N, UV, Tt, atlas, stubs, ccen, crad = build(K, T, lod)
    if bk is not None: trim_bark(bk, tr, ccen, crad)
    Image.fromarray(atlas, "RGBA").save(f"{outp}_atlas{lod}.png")
    me2 = bpy.data.meshes.new("cd"); me2.from_pydata([(x, y, z) for x, y, z in V], [], Tt); me2.update()
    uv = me2.uv_layers.new(name="UVMap")
    for li, l in enumerate(me2.loops): uv.data[li].uv = UV[l.vertex_index]
    try: me2.normals_split_custom_set_from_vertices(N)
    except Exception as ex: print("NOCUSTOMN", ex)
    me2.materials.append(bpy.data.materials.get("twig") or bpy.data.materials.new("twig"))
    cd = bpy.data.objects.new("cd", me2); bpy.context.scene.collection.objects.link(cd)
    bs = stub_obj(stubs)
    parts = [o for o in (tr, bk, bs, cd) if o is not None]
    if lod == 1:   # the far model keeps less wood
        pass
    for o in bpy.context.scene.objects: o.select_set(o in parts)
    print("LOD", lod, [(p.name, tri_count(p)) for p in parts], "atlas", atlas.shape)
    bpy.ops.export_scene.gltf(filepath=f"{outp}_lod{lod}.glb", export_format="GLB", use_selection=True, export_apply=True, export_materials="EXPORT", export_image_format="NONE", export_yup=True)
print("TREE_H %.2f" % tree_h)
print("DONE")
