# Blender headless: SOLID-CROWN LOD builder for Poly Haven photogrammetry trees (1128c C17: the alpha-card LODs of lod.py left foliage cards floating in the air).
# The crown is a lathe of the real foliage cloud (a radius per ring and sector = the 94th percentile of the twig points there), so it matches the species
# silhouette; the trunk and the branches are kept (decimated) and reach into it. No card hangs free of wood.
# usage: blender -b -P crown.py -- <gltf> <objname-substring> <foliage-mat-substr> <out-prefix> <kind fir|broad> <rings0> <rings1> <trunk0_tris> <trunk1_tris> <bark0_tris> <sectors0> <sectors1>
import bpy,bmesh,sys,random,math
import numpy as np
a=sys.argv[sys.argv.index("--")+1:]
src,objsub,twigsub,outp,kind=a[0],a[1],a[2],a[3],a[4]
rings0,rings1,tr0,tr1,bk0=[int(x) for x in a[5:10]]
sec0,sec1=int(a[10]),int(a[11])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
obj=[o for o in bpy.context.scene.objects if o.type=="MESH" and objsub in o.name][0]
me=obj.data
mats=[m.name for m in me.materials]
print("MATS",mats)
def sub(pred):
    bm=bmesh.new(); bm.from_mesh(me)
    bad=[f for f in bm.faces if not pred(mats[f.material_index])]
    bmesh.ops.delete(bm,geom=bad,context="FACES")
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context="VERTS")
    return bm
def to_obj(bm,name,matname):
    m=bpy.data.meshes.new(name); bm.to_mesh(m); bm.free()
    m.materials.clear(); mt=bpy.data.materials.get(matname) or bpy.data.materials.new(matname); m.materials.append(mt)
    o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o); return o
exec(open('tools/nrm.py').read())
def tri_count(o): return sum(len(p.vertices)-2 for p in o.data.polygons)
def decimate(o,target):
    t=tri_count(o)
    if t<=target: return
    md=o.modifiers.new("d","DECIMATE"); md.decimate_type="COLLAPSE"; md.ratio=target/t; md.use_collapse_triangulate=True
    bpy.context.view_layer.objects.active=o
    for x in bpy.context.scene.objects: x.select_set(x==o)
    bpy.ops.object.modifier_apply(modifier="d")
# --- parts
is_foliage=lambda n: twigsub in n
fb=sub(is_foliage)
P=np.array([tuple(v.co) for v in fb.verts]); fb.free()
print("FOLIAGE POINTS",len(P))
trunk_names=[n for n in mats if ("trunk" in n or n.endswith("_trunk"))]
bark_names=[n for n in mats if ("bark" in n or "branches" in n) and "dead" not in n]
zb=None
def crown_arrays(rings,sectors):
    """Lathe of the foliage cloud: radius[ring][sector] = 94th percentile of the radial distance of the points in that slab and wedge."""
    zlo=float(np.percentile(P[:,2],1.5)); zhi=float(P[:,2].max())
    H=zhi-zlo; dz=H/rings
    ang=np.arctan2(P[:,1],P[:,0]); rad=np.hypot(P[:,0],P[:,1])
    R=np.zeros((rings+1,sectors)); zs=[]
    for k in range(rings+1):
        zk=zlo+H*k/rings; zs.append(zk)
        slab=np.abs(P[:,2]-zk)<=dz*0.9
        for j in range(sectors):
            a0=-math.pi+2*math.pi*j/sectors; a1=a0+2*math.pi/sectors
            m=slab&(ang>=a0-0.2)&(ang<a1+0.2)
            R[k,j]=np.percentile(rad[m],94 if kind=='fir' else 82) if m.sum()>=8 else 0.0
    ring_mean=np.array([R[k][R[k]>0].mean() if (R[k]>0).any() else 0.0 for k in range(rings+1)])
    for k in range(rings+1):
        for j in range(sectors):
            if R[k,j]<=0: R[k,j]=ring_mean[k]*0.7
    for _ in range(1):   # smooth round the ring, lightly up the stem
        R=0.25*np.roll(R,1,1)+0.5*R+0.25*np.roll(R,-1,1)
    R2=R.copy()
    for k in range(1,rings): R2[k]=0.2*R[k-1]+0.6*R[k]+0.2*R[k+1]
    R=R2
    if kind=="fir":   # whorls: every other ring is the tier tip, the ring between is pulled in, so the crown has tiers and a ragged skirt, not a smooth sausage
        rnd=np.random.RandomState(11)
        for k in range(rings+1): R[k]*=(1.05 if k%2==0 else 0.72)*(1.0-0.45*(k/rings)**2.2)*rnd.uniform(0.9,1.1,sectors)
    else:
        rnd=np.random.RandomState(5)
        for k in range(rings+1): R[k]*=rnd.uniform(0.88,1.1,sectors)
    R=np.maximum(R,0.03*H)
    return zs,R,H
PROFILE={}
def crown_obj(rings,sectors,name):
    zs,R,H=crown_arrays(rings,sectors)
    PROFILE['zs']=zs; PROFILE['R']=R; PROFILE['sectors']=sectors
    V=[];UV=[];F=[]
    for k in range(rings+1):
        for j in range(sectors):
            a=-math.pi+2*math.pi*j/sectors
            V.append((R[k,j]*math.cos(a),R[k,j]*math.sin(a),zs[k])); UV.append((j/sectors*4.0, zs[k]/H*5.0))
    tip=len(V); V.append((0.0,0.0,zs[-1]+(0.06*H if kind=="fir" else -0.0))); UV.append((0.5,5.2))
    base=len(V); V.append((0.0,0.0,zs[0])); UV.append((0.5,0.0))
    for k in range(rings):
        for j in range(sectors):
            a=k*sectors+j; b=k*sectors+(j+1)%sectors; c=(k+1)*sectors+(j+1)%sectors; d=(k+1)*sectors+j
            F.append((a,b,c)); F.append((a,c,d))   # counter-clockwise seen from outside (Blender); the exporter flips for glTF
    for j in range(sectors):
        a=rings*sectors+j; b=rings*sectors+(j+1)%sectors
        F.append((a,b,tip))
        F.append((j,base,(j+1)%sectors))
    m=bpy.data.meshes.new(name); m.from_pydata(V,[],F); m.update()
    uv=m.uv_layers.new(name="UVMap")
    for li,l in enumerate(m.loops): uv.data[li].uv=UV[l.vertex_index]
    m.materials.append(bpy.data.materials.get("crown") or bpy.data.materials.new("crown"))
    o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o)
    # make the faces point outward (recalculate), then smooth
    bpy.context.view_layer.objects.active=o
    for x in bpy.context.scene.objects: x.select_set(x==o)
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT"); bpy.ops.mesh.normals_make_consistent(inside=False); bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    return o
def trim_branches(o):
    """Cut every piece of branch that is not inside the crown (or hugging the trunk): loose twigs poking out of the crown or hanging under it read as detached bits (1128c C17)."""
    zs=PROFILE['zs']; R=PROFILE['R']; S=PROFILE['sectors']
    def inside(co):
        if co.z<zs[0] or co.z>zs[-1]: return False
        k=min(len(zs)-2,max(0,int((co.z-zs[0])/(zs[-1]-zs[0])*(len(zs)-1))))
        a=(math.atan2(co.y,co.x)+math.pi)/(2*math.pi)*S; j=int(a)%S
        j2=(j+1)%S
        return math.hypot(co.x,co.y)<0.8*min(R[k,j],R[k+1,j],R[k,j2],R[k+1,j2])
    bm=bmesh.new(); bm.from_mesh(o.data)
    bad=[f for f in bm.faces if not all(inside(v.co) or math.hypot(v.co.x,v.co.y)<0.28 for v in f.verts)]
    bmesh.ops.delete(bm,geom=bad,context="FACES")
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if not v.link_faces],context="VERTS")
    bm.to_mesh(o.data); bm.free()
def build(lod):
    parts=[]
    t=to_obj(sub(lambda n:n in trunk_names),"tr","trunk"); decimate(t,tr0 if lod==0 else tr1); parts.append(t)
    clean_normals(t)
    if lod==0 and bk0>0:
        b=to_obj(sub(lambda n:n in bark_names),"bk","bark"); decimate(b,bk0); parts.append(b); clean_normals(b)
    parts.append(crown_obj(rings0 if lod==0 else rings1, sec0 if lod==0 else sec1, "cd"))
    if lod==0 and bk0>0: trim_branches(parts[1])
    zbase=min(v.co.z for v in parts[0].data.vertices)
    for p in parts:
        for v in p.data.vertices: v.co.z-=zbase
    return parts
for lod in (0,1):
    parts=build(lod)
    for o in bpy.context.scene.objects: o.select_set(o in parts)
    print("LOD",lod,[(p.name,tri_count(p)) for p in parts],"TOTAL",sum(tri_count(p) for p in parts))
    bpy.ops.export_scene.gltf(filepath=f"{outp}_lod{lod}.glb",export_format="GLB",use_selection=True,export_apply=True,export_materials="EXPORT",export_image_format="NONE")
    for p in parts: bpy.data.objects.remove(p)
print("DONE")
