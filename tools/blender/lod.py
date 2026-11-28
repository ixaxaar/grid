# Blender headless: python3-free LOD builder for Poly Haven photogrammetry trees (alpha-card foliage).
# usage: blender -b -P lod.py -- <gltf> <objname-substring> <twig-mat-substr> <out-prefix> <kind fir|broad> <lod0_cards> <lod1_cards> <trunk0_tris> <trunk1_tris> <bark0_tris>
import bpy,bmesh,sys,random,math
import numpy as np
a=sys.argv[sys.argv.index("--")+1:]
src,objsub,twigsub,outp,kind=a[0],a[1],a[2],a[3],a[4]
cards0,cards1,tr0,tr1,bk0=[int(x) for x in a[5:10]]
smax0,smax1=float(a[10]),float(a[11])
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
exec(open('/tmp/claude-1000/assets-dl/tools/nrm.py').read())
def tri_count(o): return sum(len(p.vertices)-2 for p in o.data.polygons)
def decimate(o,target):
    t=tri_count(o)
    if t<=target: return
    md=o.modifiers.new("d","DECIMATE"); md.decimate_type="COLLAPSE"; md.ratio=target/t; md.use_collapse_triangulate=True
    bpy.context.view_layer.objects.active=o
    for x in bpy.context.scene.objects: x.select_set(x==o)
    bpy.ops.object.modifier_apply(modifier="d")
# --- parts
is_twig=lambda n: twigsub in n
tw_bm=sub(is_twig)
tw_bm.faces.ensure_lookup_table()
uvl=tw_bm.loops.layers.uv.active
# islands
seen=set(); islands=[]
for f in tw_bm.faces:
    if f.index in seen: continue
    st=[f]; seen.add(f.index); isl=[]
    while st:
        x=st.pop(); isl.append(x)
        for e in x.edges:
            for g in e.link_faces:
                if g.index not in seen: seen.add(g.index); st.append(g)
    islands.append(isl)
print("ISLANDS",len(islands))
cards=[]
for isl in islands:
    P=[];UV=[]
    for f in isl:
        for l in f.loops: P.append(tuple(l.vert.co)); UV.append(tuple(l[uvl].uv))
    P=np.array(P);UV=np.array(UV)
    c=P.mean(0); C=np.cov((P-c).T)
    w,v=np.linalg.eigh(C); e1=v[:,2]; e2=v[:,1]
    if w[1]<1e-12: continue
    q1=(P-c)@e1; q2=(P-c)@e2
    A,_,_,_=np.linalg.lstsq(np.hstack([P,np.ones((len(P),1))]),UV,rcond=None)
    cards.append((c,e1,e2,q1.min(),q1.max(),q2.min(),q2.max(),A))
print("CARDS",len(cards))
tw_bm.free()
H=max(c[0][2] for c in cards); zmin=min(c[0][2] for c in cards)
def make_cards(n,seed,smax):
    rnd=random.Random(seed); idx=list(range(len(cards))); rnd.shuffle(idx); idx=idx[:n]
    s=min(math.sqrt(len(cards)/max(n,1))*0.62,smax)
    V=[];UVs=[];N=[];T=[]
    for i in idx:
        c,e1,e2,a0,a1,b0,b1,A=cards[i]
        if (a1-a0)<2e-3 or (b1-b0)<2e-3 or math.hypot(c[0],c[1])<0.4: continue   # degenerate, or on the trunk axis (no outward direction)
        # pivot: card end nearest the trunk axis
        ends=[c+e1*a0+e2*(b0+b1)/2, c+e1*a1+e2*(b0+b1)/2]
        piv=min(ends,key=lambda p:p[0]**2+p[1]**2)
        for (u,vv) in ((a0,b0),(a1,b0),(a1,b1),(a0,b1)):
            vm=(b0+b1)/2; p=c+e1*u+e2*(vm+(vv-vm)*(1.8 if kind=='fir' else 1.0)); p=piv+(p-piv)*s
            uv=np.append(p,1.0)  # placeholder
            # uv from the ORIGINAL position of the corner
            p0=c+e1*u+e2*vv
            UVs.append(tuple(np.append(p0,1.0)@A)); V.append(tuple(p))
            r=np.array([p[0],p[1],0.0]); nn=r/(np.linalg.norm(r)+1e-6)+np.array([0,0,0.4 if kind=="fir" else 0.3])   # never steeper than ~22 degrees up: a card is not a roof
            N.append(tuple(nn/np.linalg.norm(nn)))
        b=len(V)-4
        g1=np.cross(np.array(V[b+1])-np.array(V[b]),np.array(V[b+2])-np.array(V[b])); g2=np.cross(np.array(V[b+2])-np.array(V[b]),np.array(V[b+3])-np.array(V[b]))
        if np.dot(g1,g2)<=0.5*np.linalg.norm(g1)*np.linalg.norm(g2):   # a twisted quad: its two triangles would disagree about 'outward'
            del V[b:],UVs[b:],N[b:]; continue
        edge_on=False
        for tri in ((b,b+1,b+2),(b,b+2,b+3)):
            pa,pb,pc=[np.array(V[k]) for k in tri]
            gn=np.cross(pb-pa,pc-pa); nm=sum(np.array(N[k]) for k in tri)
            if abs(float(gn@nm))<0.2*np.linalg.norm(gn)*np.linalg.norm(nm): edge_on=True   # nearly edge-on to its own normal: the sign is not safe after Godot's normal compression
        if edge_on:
            del V[b:],UVs[b:],N[b:]; continue
        for tri in ((b,b+1,b+2),(b,b+2,b+3)):
            pa,pb,pc=[np.array(V[k]) for k in tri]
            gn=np.cross(pb-pa,pc-pa); nm=sum(np.array(N[k]) for k in tri)
            T.append(tri if float(gn@nm)>=0 else (tri[0],tri[2],tri[1]))
    return V,UVs,N,T
def cards_obj(n,seed,name,matname,smax):
    V,UVs,N,T=make_cards(n,seed,smax)
    m=bpy.data.meshes.new(name); m.from_pydata(V,[],T)
    uv=m.uv_layers.new(name="UVMap")
    for li,l in enumerate(m.loops): uv.data[li].uv=UVs[l.vertex_index]
    try: m.normals_split_custom_set_from_vertices(N)
    except Exception as ex: print("NOCUSTOMN",ex)
    m.materials.append(bpy.data.materials.get(matname) or bpy.data.materials.new(matname))
    o=bpy.data.objects.new(name,m); bpy.context.scene.collection.objects.link(o); return o
trunk_names=[n for n in mats if ("trunk" in n or n.endswith("_trunk")) ]
bark_names=[n for n in mats if ("bark" in n or "branches" in n) and "dead" not in n]
def build(lod):
    parts=[]
    t=to_obj(sub(lambda n:n in trunk_names),"tr","trunk"); decimate(t,tr0 if lod==0 else tr1); parts.append(t)
    clean_normals(t)
    if lod==0 and bk0>0:
        b=to_obj(sub(lambda n:n in bark_names),"bk","bark"); decimate(b,bk0); parts.append(b)
    parts.append(cards_obj(cards0 if lod==0 else cards1,7+lod,"cd","twig",smax0 if lod==0 else smax1))
    # base to z=0, set the trunk base at the origin
    allv=[v.co.z for p in parts for v in p.data.vertices]
    zb=min(v.co.z for v in parts[0].data.vertices)
    for p in parts:
        for v in p.data.vertices: v.co.z-=zb
    return parts
for lod in (0,1):
    parts=build(lod)
    for o in bpy.context.scene.objects: o.select_set(o in parts)
    print("LOD",lod,[(p.name,tri_count(p)) for p in parts],"TOTAL",sum(tri_count(p) for p in parts))
    bpy.ops.export_scene.gltf(filepath=f"{outp}_lod{lod}.glb",export_format="GLB",use_selection=True,export_apply=True,export_materials="EXPORT",export_image_format="NONE")
    for p in parts: bpy.data.objects.remove(p)
print("DONE")
