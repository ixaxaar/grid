import os, shutil
from PIL import Image
D = "/tmp/claude-1000/assets-dl"
T = "/home/ixaxaar/src/ORGS/cobanana/grid/godot/world3d/tex"
os.makedirs(T, exist_ok=True)

def jpg(src, name, size=1024, q=88):
    im = Image.open(src).convert("RGB")
    if im.size != (size, size): im = im.resize((size, size), Image.LANCZOS)
    im.save(f"{T}/{name}.jpg", quality=q, optimize=True)
    return name + ".jpg"

out = []
for acg, nm in [("RoofingTiles006", "roof"), ("Plaster001", "plaster"), ("Gravel023", "gravel"), ("Asphalt031", "asphalt"), ("Concrete034", "concrete")]:
    b = f"{D}/acg/z_{acg}/x/{acg}_1K-JPG"
    out.append(jpg(b + "_Color.jpg", nm + "_albedo"))
    out.append(jpg(b + "_NormalGL.jpg", nm + "_normal"))
    out.append(jpg(b + "_Roughness.jpg", nm + "_rough"))

# tree textures
tx = f"{D}/m_fir_tree_01/textures"
out.append(jpg(f"{tx}/fir_tree_01_trunk_a_diff_1k.jpg", "tree_fir_trunk_a_albedo", 512))
out.append(jpg(f"{tx}/fir_tree_01_trunk_b_diff_1k.jpg", "tree_fir_trunk_b_albedo", 512))
a = Image.open(f"{tx}/fir_tree_01_twig_diff_1k.jpg").convert("RGB"); a.putalpha(Image.open(f"{D}/alpha/fir_tree_01_twig_alpha_1k.jpg").convert("L"))
a.save(f"{T}/tree_fir_twig_albedo.png", optimize=True); out.append("tree_fir_twig_albedo.png")
tb = f"{D}/m_tree_small_02/textures"
out.append(jpg(f"{tb}/tree_small_02_diff_1k.jpg", "tree_broad_trunk_albedo", 512))
b = Image.open(f"{tb}/tree_small_02_leaves_diff_1k.jpg").convert("RGB"); b.putalpha(Image.open(f"{D}/alpha/tree_small_02_leaves_alpha_1k.jpg").convert("L"))
b.save(f"{T}/tree_broad_leaf_albedo.png", optimize=True); out.append("tree_broad_leaf_albedo.png")
# Kenney palette for the house trim (door, frames, chimney)
Image.open(f"{D}/kz/x/Models/GLB format/Textures/colormap.png").convert("RGBA").save(f"{T}/house_palette_albedo.png", optimize=True); out.append("house_palette_albedo.png")

TPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://world3d/tex/%(f)s"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=%(nm)d
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
"""
for f in out:
    open(f"{T}/{f}.import", "w").write(TPL % {"f": f, "nm": 1 if "_normal." in f else 0})
    print(f, os.path.getsize(f"{T}/{f}") // 1024, "KB")
