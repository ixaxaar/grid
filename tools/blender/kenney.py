# Blender headless: Kenney model -> one static mesh (armature modifiers applied), scaled so its longest side (character: height) is <size> m, base at origin, textures embedded.
# usage: blender -b -P kenney.py -- <in.glb> <out.glb> <size_m> <axis x|y|z>
import bpy,sys
exec(open('/tmp/claude-1000/assets-dl/tools/nrm.py').read())
a=sys.argv[sys.argv.index("--")+1:]
src,out,size,axis=a[0],a[1],float(a[2]),a[3]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes=[o for o in bpy.context.scene.objects if o.type=="MESH"]
print('NMESH',len(meshes),[o.name for o in meshes][:12])
for o in meshes:
    bpy.context.view_layer.objects.active=o
    for m in list(o.modifiers):
        if m.type=="ARMATURE":
            try: bpy.ops.object.modifier_apply(modifier=m.name)
            except Exception as e: print("NOAPPLY",e)
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
for o in list(bpy.context.scene.objects):
    if o.type!="MESH": bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes: o.select_set(True)
bpy.context.view_layer.objects.active=meshes[0]
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
if len(meshes)>1: bpy.ops.object.join()
o=bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
from mathutils import Vector
md=o.modifiers.new('t','TRIANGULATE'); md.quad_method='BEAUTY'; md.min_vertices=4
bpy.ops.object.modifier_apply(modifier='t')
me=o.data
try:
    cn=me.corner_normals; flip=[]
    for p in me.polygons:
        m=sum((cn[l].vector for l in range(p.loop_start,p.loop_start+p.loop_total)),Vector((0,0,0)))
        if p.normal.dot(m)<0: flip.append(p.index)
    import bmesh
    bm=bmesh.new(); bm.from_mesh(me); bm.faces.ensure_lookup_table()
    if flip: bmesh.ops.reverse_faces(bm,faces=[bm.faces[i] for i in flip])
    bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<1e-6],context='FACES')
    bm.to_mesh(me); bm.free()
    print("FLIP",len(flip))
except Exception as e: print("NOFLIP",e)
clean_normals(o)
bpy.ops.object.shade_flat()
vs=[v.co.copy() for v in o.data.vertices]
mn=Vector((min(v.x for v in vs),min(v.y for v in vs),min(v.z for v in vs))); mx=Vector((max(v.x for v in vs),max(v.y for v in vs),max(v.z for v in vs)))
dim={"x":mx.x-mn.x,"y":mx.y-mn.y,"z":mx.z-mn.z}[axis]; k=size/dim
c=Vector(((mn.x+mx.x)/2,(mn.y+mx.y)/2,mn.z))
for v in o.data.vertices: v.co=(v.co-c)*k
o.location=(0,0,0)
print("TRI",sum(len(p.vertices)-2 for p in o.data.polygons),"SIZE",tuple(round(x,2) for x in o.dimensions),"MATS",[m.name for m in o.data.materials])
bpy.ops.object.select_all(action="DESELECT"); o.select_set(True)
bpy.ops.export_scene.gltf(filepath=out,export_format="GLB",use_selection=True,export_apply=True,export_image_format="JPEG",export_image_quality=85)
