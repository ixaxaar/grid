import bpy,bmesh,sys
from mathutils import Vector
a=sys.argv[sys.argv.index("--")+1:]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=a[0])
img=bpy.data.images.load(a[1]); W,H=img.size; px=list(img.pixels)
def col(u,v):
    x=min(W-1,max(0,int(u*W))); y=min(H-1,max(0,int(v*H))); i=(y*W+x)*4; return [c*255 for c in px[i:i+3]]
o=[o for o in bpy.context.scene.objects if o.type=="MESH"][0]
bpy.context.view_layer.objects.active=o
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM"); bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
bm=bmesh.new(); bm.from_mesh(o.data); uv=bm.loops.layers.uv.active
xs=[v.co.x for v in bm.verts]; ys=[v.co.y for v in bm.verts]; zs=[v.co.z for v in bm.verts]
sc=10/max(max(xs)-min(xs),max(ys)-min(ys)); cx=(max(xs)+min(xs))/2; cy=(max(ys)+min(ys))/2; z0=min(zs)
res=[]
for f in bm.faces:
    c=f.calc_center_median(); n=f.normal
    if abs(n.y)<0.9: continue
    zc=(c.z-z0)*sc
    if zc>1.6: continue
    u=sum(l[uv].uv.x for l in f.loops)/len(f.loops); v=sum(l[uv].uv.y for l in f.loops)/len(f.loops)
    r,g,b=col(u,v)
    if (r+g+b)/3>100: continue
    res.append(((c.x-cx)*sc,(c.y-cy)*sc,zc,n.y,f.calc_area()*sc*sc))
res.sort(key=lambda r:-r[4])
print("DOOR",[tuple(round(x,2) for x in r) for r in res[:3]])
