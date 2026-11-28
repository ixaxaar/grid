import json,sys,os,subprocess
s=sys.argv[1]; res=sys.argv[2] if len(sys.argv)>2 else "1k"
j=json.load(open(f"/tmp/claude-1000/assets-dl/api/f_{s}.json"))
e=j["gltf"][res]["gltf"]
d=f"/tmp/claude-1000/assets-dl/m_{s}"
os.makedirs(d+"/textures",exist_ok=True)
items=[(e["url"],f"{d}/{s}_{res}.gltf")]+[(v["url"],f"{d}/{p}") for p,v in e["include"].items()]
for u,o in items:
    if os.path.exists(o) and os.path.getsize(o)>1000: continue
    subprocess.run(["timeout","600","curl","-sSL","-A","Mozilla/5.0 (asset fetch)","-o",o,u],check=False)
print(s,"ok",len(items))
