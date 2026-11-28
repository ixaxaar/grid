# Blender headless: Poly Haven prop -> one decimated mesh, 512 px textures embedded as JPEG, base at origin (min z = 0, centred in x/y).
# usage: blender -b -P prop.py -- <in.gltf> <out.glb> <target_tris> <name-substr,...|*> [texsize]
import bpy, sys
a = sys.argv[sys.argv.index("--") + 1:]
src, out, target, subs = a[0], a[1], int(a[2]), a[3].split(",")
texsize = int(a[4]) if len(a) > 4 else 512
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == "MESH" and (subs == ["*"] or any(s in o.name for s in subs))]
for o in bpy.context.scene.objects: o.select_set(o in meshes)
bpy.context.view_layer.objects.active = meshes[0]
for o in meshes:
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.select_all(action="DESELECT")
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1: bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
t = sum(len(p.vertices) - 2 for p in o.data.polygons)
if t > target:
    md = o.modifiers.new("d", "DECIMATE"); md.decimate_type = "COLLAPSE"; md.ratio = target / t; md.use_collapse_triangulate = True
    md.delimit = {"MATERIAL", "UV"}
    bpy.ops.object.modifier_apply(modifier="d")
exec(open('/tmp/claude-1000/assets-dl/tools/nrm.py').read())
clean_normals(o)
# base to the origin
from mathutils import Vector
vs = [v.co for v in o.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs))); mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
for v in o.data.vertices: v.co -= c
for im in bpy.data.images:
    if im.size[0] > texsize: im.scale(texsize, texsize)
print("TRI", sum(len(p.vertices) - 2 for p in o.data.polygons), "SIZE", tuple(round(x, 2) for x in o.dimensions), "MATS", [m.name for m in o.data.materials])
bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_apply=True, export_image_format="JPEG", export_image_quality=82)
