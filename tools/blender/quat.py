# Blender headless: a Quaternius pine (CC0, poly.pizza) -> LOD0 (as it is) and LOD1 (collapse-decimated), textures taken out to PNG so both share them.
# usage: blender -b -P quat.py -- <in.glb> <out-prefix> <lod1_tris> [tex-dir]
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, outp, tris1 = a[0], a[1], int(a[2])
texdir = a[3] if len(a) > 3 else None
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
fix_normals()
print("LOD0 tris", sum(tri_count(o) for o in objs))
export(f"{outp}_lod0.glb")
for o in objs:
    t = tri_count(o)
    md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = min(1.0, tris1 / t); md.use_collapse_triangulate = True; md.delimit = {"UV", "MATERIAL"}
    bpy.context.view_layer.objects.active = o
    for x in bpy.context.scene.objects: x.select_set(x == o)
    bpy.ops.object.modifier_apply(modifier="d")
for o in objs:   # collapse can push a UV a hair outside the texture: clamp (the leaf texture must not wrap)
    for d in o.data.uv_layers.active.data:
        d.uv.x = min(1.0, max(0.0, d.uv.x)); d.uv.y = min(1.0, max(0.0, d.uv.y))
fix_normals(4e-3, False)   # far: flat shading all over, so no sliver can disagree with its winding
print("LOD1 tris", sum(tri_count(o) for o in objs))
export(f"{outp}_lod1.glb")
