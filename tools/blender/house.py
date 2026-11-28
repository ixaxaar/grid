# Blender headless: Kenney suburban house -> 4 materials (trim/wall/roof/window), metric scale, PBR box UVs on wall and roof, base at y=0.
# usage: blender -b -P house.py -- <in.glb> <colormap.png> <out.glb> <target_width_m>
import bpy,bmesh,sys,math
from mathutils import Vector
a=sys.argv[sys.argv.index("--")+1:]
src,cmap,out,wid=a[0],a[1],a[2],float(a[3])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
img=bpy.data.images.load(cmap); W,H=img.size; px=list(img.pixels)
def col(u,v):
    x=min(W-1,max(0,int(u*W))); y=min(H-1,max(0,int(v*H)))
    i=(y*W+x)*4; return [c*255 for c in px[i:i+3]]
o=[o for o in bpy.context.scene.objects if o.type=="MESH"][0]
bpy.context.view_layer.objects.active=o
for x in bpy.context.scene.objects: x.select_set(x==o)
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
md=o.modifiers.new('t','TRIANGULATE'); md.quad_method='BEAUTY'; md.min_vertices=4
bpy.ops.object.modifier_apply(modifier='t')
me=o.data
me.materials.clear()
for nm in ("trim","wall","roof","window","window_dark"): me.materials.append(bpy.data.materials.new(nm))
cn=me.corner_normals; flip=[]
for p in me.polygons:
    m=sum((cn[l].vector for l in range(p.loop_start,p.loop_start+p.loop_total)),Vector((0,0,0)))
    if p.normal.dot(m)<0: flip.append(p.index)
print("FLIP",len(flip))
bm=bmesh.new(); bm.from_mesh(me); uvl=bm.loops.layers.uv.active
bm.faces.ensure_lookup_table()
if flip: bmesh.ops.reverse_faces(bm,faces=[bm.faces[i] for i in flip])
xs=[v.co.x for v in bm.verts]; ys=[v.co.y for v in bm.verts]; zs=[v.co.z for v in bm.verts]
sc=wid/max(max(xs)-min(xs),max(ys)-min(ys))
cx=(max(xs)+min(xs))/2; cy=(max(ys)+min(ys))/2; z0=min(zs)
for v in bm.verts: v.co=Vector(((v.co.x-cx)*sc,(v.co.y-cy)*sc,(v.co.z-z0)*sc))
bmesh.ops.delete(bm,geom=[f for f in bm.faces if f.calc_area()<3e-4],context='FACES')   # zero-area slivers from T-junctions: no normal, no pixels
bm.faces.ensure_lookup_table()
def cls(f):
    u=sum(l[uvl].uv.x for l in f.loops)/len(f.loops); v=sum(l[uvl].uv.y for l in f.loops)/len(f.loops)
    r,g,b=col(u,v)
    if b-r>55 and b>150: return 3
    if g-r>45 and g>=b-10 and g>120: return 2
    if min(r,g,b)>185 and (max(r,g,b)-min(r,g,b))<60: return 1
    return 0
cnt=[0,0,0,0]
TILE=2.0
for f in bm.faces:
    c=cls(f); f.material_index=c; cnt[c]+=1
    if c in (1,2):
        n=f.normal; ax=max(range(3),key=lambda i:abs(n[i]))
        for l in f.loops:
            p=l.vert.co
            if ax==2: l[uvl].uv=(p.x/TILE,p.y/TILE)
            elif ax==0: l[uvl].uv=(p.y/TILE,p.z/TILE)
            else: l[uvl].uv=(p.x/TILE,p.z/TILE)
# about 60 % of the window panes are lit (served estate), the rest stay dark glass: islands of window faces, hashed
seen=set(); isl=0
for f in bm.faces:
    if f.material_index!=3 or f.index in seen: continue
    st=[f]; seen.add(f.index); comp=[]
    while st:
        x=st.pop(); comp.append(x)
        for e in x.edges:
            for g in e.link_faces:
                if g.material_index==3 and g.index not in seen: seen.add(g.index); st.append(g)
    lit=((isl*7+3)*2654435761>>5)%10<6
    for x in comp: x.material_index=3 if lit else 4
    isl+=1
print("WINDOWS",isl)
print("FACES",cnt)
bm.to_mesh(me); bm.free()
exec(open('/tmp/claude-1000/assets-dl/tools/nrm.py').read())
clean_normals(o)
bpy.ops.object.shade_flat()   # Kenney's low-poly look; each face keeps its own normal, which is exactly its winding
bpy.ops.export_scene.gltf(filepath=out,export_format="GLB",use_selection=True,export_apply=True,export_image_format="NONE")
print("TRI",sum(len(p.vertices)-2 for p in me.polygons),"SIZE",tuple(round(x,2) for x in o.dimensions))
