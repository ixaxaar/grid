import sys,subprocess,json,re
slug,out=sys.argv[1],sys.argv[2]
UA="Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0"
def sh(*a): return subprocess.run(["timeout","90","curl","-sSL","-A",UA,*a],capture_output=True,text=True).stdout
html=sh("-c","/tmp/claude-1000/assets-dl/kz2/cj.txt",f"https://kenney.nl/assets/{slug}")
t=re.sub(r"<script.*?</script>","",html,flags=re.S); t=re.sub(r"<[^>]+>"," ",t); t=re.sub(r"\s+"," ",t)
m=re.search(r"License\s+(.{0,40})",t); print("PAGE",slug,"|",t[:40],"| LICENSE:",m.group(1) if m else None)
did=re.search(r"data-download-id='([0-9a-f]+)'",html)
if not did: print("no id"); sys.exit(1)
j=sh("-b","/tmp/claude-1000/assets-dl/kz2/cj.txt","-H",f"Referer: https://kenney.nl/assets/{slug}",f"https://kenney.nl/download-link/{did.group(1)}")
u=json.loads(j)["url"]
subprocess.run(["timeout","120","curl","-sSL","-A",UA,"-o",out,u]); print("saved",out)
