# Blender headless: a Quaternius pine (CC0, poly.pizza) -> LOD0 (as it is) and LOD1 (collapse-decimated), textures taken out to PNG so both share them.
# usage: blender -b -P quat.py -- <in.glb> <out-prefix> <lod1_tris> [tex-dir|-] [cut_below]
# [mode] sheets|cards, see below.
# cut_below (0..1, a share of the tree's height): bark faces that stand off the trunk below that height are dropped (the pine's bare lower branches, "spider legs").
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, outp, tris1 = a[0], a[1], int(a[2])
texdir = a[3] if len(a) > 3 and a[3] != "-" else None
cut_below = float(a[4]) if len(a) > 4 else 0.0
mode = a[5] if len(a) > 5 else "sheets"   # "sheets": the pines (big leaf sheets, LOD1 by collapse). "cards": the common trees (single leaf quads on branches: LOD1 keeps the bark, thins the cards)
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
if texdir:
    for im in bpy.data.images:
        im.filepath_raw = f"{texdir}/{im.name}"; im.file_format = "PNG"; im.save()
def fix_normals(tiny_area=6e-4, smooth_bark=True):
    """The pine's leaf sheets are double-sided with windings that disagree with their normals (mesh_winding_truth): drop the custom normals, shade the leaves flat
    (each face's normal is its own winding) and the bark smooth."""
    import math
    for o in objs:
        bpy.context.view_layer.objects.active = o
        for x in bpy.context.scene.objects: x.select_set(x == o)
        import bmesh
        bm = bmesh.new(); bm.from_mesh(o.data)
        tiny = [f for f in bm.faces if f.calc_area() < tiny_area and "Bark" in o.data.materials[f.material_index].name]   # slivers of the thin branch stubs: their smooth normals disagree with their winding
        bmesh.ops.delete(bm, geom=tiny, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data); bm.free()
        bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.dissolve_degenerate(threshold=0.0005); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
        try: bpy.ops.mesh.customdata_custom_splitnormals_clear()
        except Exception as e: print("NOCLEAR", e)
        leafmat = [i for i, m in enumerate(o.data.materials) if "Leaves" in m.name]
        for p in o.data.polygons: p.use_smooth = smooth_bark and p.material_index not in leafmat
def tri_count(o): return sum(len(p.vertices) - 2 for p in o.data.polygons)
def export(path):
    for o in bpy.context.scene.objects: o.select_set(o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_materials="EXPORT", export_image_format="NONE", export_yup=True)
def cut_branches(share):
    """Drop bark faces whose centre is far off the trunk axis below `share` of the height: the bare lower branches of a pine. The trunk (a thin cone up the axis) stays."""
    import bmesh
    zs = [v.co.z for o in objs for v in o.data.vertices]; z0, z1 = min(zs), max(zs); zc = z0 + share * (z1 - z0)
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data)
        gone = []
        for f in bm.faces:
            if "Bark" not in o.data.materials[f.material_index].name: continue
            c = f.calc_center_median()
            far = max((v.co.x * v.co.x + v.co.y * v.co.y) ** 0.5 for v in f.verts)
            if c.z < zc and (far > 0.56 or (c.x * c.x + c.y * c.y) ** 0.5 > 0.5): gone.append(f)   # the pine trunk is under 0.5 m wide at its foot (Pine_4: the branches reach 2 m out up to 0.3 of its height)
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data); bm.free()
    print("cut", share)
def drop_bad_bark():
    """A bark triangle whose smooth normal points to the other side of its own winding (a sliver left by the cut) would face inward: drop it. Twice, as a drop changes its neighbours' smooth normals."""
    import bmesh
    n = 0
    for _ in range(3):
        bad = {}
        for o in objs:
            d = o.data; cn = d.corner_normals
            for p in d.polygons:
                if "Leaves" in d.materials[p.material_index].name: continue
                nn = sum((cn[l].vector for l in p.loop_indices), type(p.normal)())
                if nn.dot(p.normal) <= 0.0: bad.setdefault(o, []).append(p.index)
        if not bad: break
        for o, ids in bad.items():
            bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
            bmesh.ops.delete(bm, geom=[bm.faces[i] for i in ids], context="FACES")
            bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
            bm.to_mesh(o.data); bm.free(); n += len(ids)
        for o in objs:
            for p in o.data.polygons: pass
    print("bad bark triangles dropped", n)
def is_leaf(o, f): return "Leaves" in o.data.materials[f.material_index].name
def tidy_leaf_uvs():
    """A leaf quad whose UVs sit in another tile of the texture (UV 1..2) shows the same leaf: move it back into 0..1 so no card relies on the texture wrapping."""
    import bmesh
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); uv = bm.loops.layers.uv.active
        for f in bm.faces:
            if not is_leaf(o, f): continue
            us = [l[uv].uv.x for l in f.loops]; vs = [l[uv].uv.y for l in f.loops]
            du = -int(min(us) // 1); dv = -int(min(vs) // 1)
            for l in f.loops: l[uv].uv.x = min(1.0, max(0.0, l[uv].uv.x + du)); l[uv].uv.y = min(1.0, max(0.0, l[uv].uv.y + dv))
        bm.to_mesh(o.data); bm.free()
def drop_floating(max_hops=2):
    """Delete leaf cards the wood does not reach. A card is anchored when it lies within 4 % of the tree's height of a bark surface, or touches (within that distance)
    an anchored card, at most `max_hops` cards away: the pack's crowns are clouds of cards round a branch tip, the wood inside the cloud. Collapse decimation shortens thin
    branches, so LOD1 can lose the wood a cloud hung on; those clouds go. tests/vegetation_truth.gd applies the same rule."""
    import bmesh
    from mathutils.bvhtree import BVHTree
    n_drop = 0
    zs = [v.co.z for o in objs for v in o.data.vertices]; tol = 0.04 * (max(zs) - min(zs))
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
        bk = bmesh.new(); m = {}
        for f in bm.faces:
            if is_leaf(o, f): continue
            vs = []
            for v in f.verts:
                if v.index not in m: m[v.index] = bk.verts.new(v.co)
                vs.append(m[v.index])
            try: bk.faces.new(vs)
            except ValueError: pass
        bvh = BVHTree.FromBMesh(bk)
        seen = set(); comps = []
        for f in bm.faces:
            if not is_leaf(o, f) or f.index in seen: continue
            comp = [f]; seen.add(f.index); st = [f]
            while st:
                x = st.pop()
                for e in x.edges:
                    for g in e.link_faces:
                        if g.index not in seen and is_leaf(o, g): seen.add(g.index); comp.append(g); st.append(g)
            comps.append(comp)
        info = []   # per card: distance to wood, centre, radius
        for comp in comps:
            vs = {v for g in comp for v in g.verts}; c = sum((v.co for v in vs), type(next(iter(vs)).co)()) / len(vs)
            d = min((bvh.find_nearest(v.co)[3] or 1e9) for v in vs)
            info.append((d, c, max((v.co - c).length for v in vs)))
        hop = [0 if d <= tol else -1 for d, c, r in info]
        for h in range(1, max_hops + 1):
            for i, (d, c, r) in enumerate(info):
                if hop[i] != -1: continue
                for j, (d2, c2, r2) in enumerate(info):
                    if hop[j] == h - 1 and (c - c2).length <= r + r2 + tol: hop[i] = h; break
        gone = [f for comp, h in zip(comps, hop) if h == -1 for f in comp]; n_drop += sum(1 for h in hop if h == -1)
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data); bm.free(); bk.free()
    print("floating cards dropped", n_drop)
def thin_cards(keep):
    """LOD1 of a card tree: keep every card whose island number passes a deterministic stride, scaled up about its centre so the crown keeps its mass."""
    import bmesh
    for o in objs:
        bm = bmesh.new(); bm.from_mesh(o.data); bm.faces.ensure_lookup_table()
        seen = set(); comps = []
        for f in bm.faces:
            if not is_leaf(o, f) or f.index in seen: continue
            comp = [f]; seen.add(f.index); st = [f]
            while st:
                x = st.pop()
                for e in x.edges:
                    for g in e.link_faces:
                        if g.index not in seen and is_leaf(o, g): seen.add(g.index); comp.append(g); st.append(g)
            comps.append(comp)
        gone = []; k = 0.0; grow = min(1.7, 1.0 / (keep ** 0.5))
        for comp in comps:
            k += keep
            if k >= 1.0:
                k -= 1.0
                vs = {v for g in comp for v in g.verts}; c = sum((v.co for v in vs), type(next(iter(vs)).co)()) / len(vs)
                for v in vs: v.co = c + (v.co - c) * grow
            else: gone.extend(comp)
        bmesh.ops.delete(bm, geom=gone, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data); bm.free()
if cut_below > 0: cut_branches(cut_below)
if mode == "cards": tidy_leaf_uvs()
fix_normals()
if cut_below > 0: drop_bad_bark()
if mode == "cards": drop_floating()
print("LOD0 tris", sum(tri_count(o) for o in objs))
export(f"{outp}_lod0.glb")
def decimate(o, tris):
    t = tri_count(o)
    md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = min(1.0, tris / t); md.use_collapse_triangulate = True; md.delimit = {"UV", "MATERIAL"}
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.scene.objects: x.select_set(x == o)
    bpy.ops.object.modifier_apply(modifier="d")
if mode == "cards":
    # bark and leaves are one object: split them, thin the cards, decimate the bark, join, then drop what the shorter branches no longer reach
    n_cards = sum(1 for o in objs for f in o.data.polygons if "Leaves" in o.data.materials[f.material_index].name) // 1
    leaf_tris = sum(len(f.vertices) - 2 for o in objs for f in o.data.polygons if "Leaves" in o.data.materials[f.material_index].name)
    keep = min(1.0, (0.5 * tris1) / max(1, leaf_tris))
    thin_cards(keep)
    for o in objs:
        bark_t = sum(len(f.vertices) - 2 for f in o.data.polygons if "Leaves" not in o.data.materials[f.material_index].name)
        leaf_t = sum(len(f.vertices) - 2 for f in o.data.polygons if "Leaves" in o.data.materials[f.material_index].name)
        # decimate only the bark: protect the cards by selecting a vertex group
        vg = o.vertex_groups.new(name="bark")
        bark_vs = {v for f in o.data.polygons if "Leaves" not in o.data.materials[f.material_index].name for v in f.vertices}
        vg.add(sorted(bark_vs), 1.0, "REPLACE")
        want = max(100, int(tris1 - leaf_t))
        md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = min(1.0, want / max(1, bark_t)); md.use_collapse_triangulate = True; md.delimit = {"UV", "MATERIAL"}; md.vertex_group = "bark"
        bpy.context.view_layer.objects.active = o
        for x in bpy.context.scene.objects: x.select_set(x == o)
        bpy.ops.object.modifier_apply(modifier="d")
else:
    for o in objs: decimate(o, tris1)
for o in objs:   # collapse can push a UV a hair outside the texture: clamp (the leaf texture must not wrap)
    for d in o.data.uv_layers.active.data:
        d.uv.x = min(1.0, max(0.0, d.uv.x)); d.uv.y = min(1.0, max(0.0, d.uv.y))
fix_normals(4e-3, False)   # far: flat shading all over, so no sliver can disagree with its winding
if mode == "cards": drop_floating()
print("LOD1 tris", sum(tri_count(o) for o in objs))
export(f"{outp}_lod1.glb")
