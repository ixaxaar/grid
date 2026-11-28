#!/bin/zsh
# The five Quaternius trees (CC0, poly.pizza, Stylized Nature MegaKit). Download each model's .glb from its page (the page JSON says "Licence":"CC0 1.0"):
#   Pine_4 79gmlLnweB   Pine_5 igSu0cPoBz   CommonTree_3 QVOop92WmG   CommonTree_4 YWjGDJ9F7g   CommonTree_5 t9KbsfYdXz   (https://poly.pizza/m/<id>)
# usage: tools/blender/runquat.sh <dir with <id>.glb> <out dir>   then copy <out>/*.glb to godot/world3d/assets/trees/ and the leaf textures to godot/world3d/tex/
# args of quat.py: in.glb out-prefix lod1_tris [tex-dir|-] [cut_below] [sheets|cards]
S=${0:A:h}/quat.py; I=${1:?in dir}; O=${2:?out dir}; mkdir -p $O
timeout 250 blender -b -P $S -- $I/79gmlLnweB.glb $O/fir_a 1000 - 0.36
timeout 250 blender -b -P $S -- $I/igSu0cPoBz.glb $O/fir_b 1000
timeout 250 blender -b -P $S -- $I/QVOop92WmG.glb $O/broad_a 1500 - 0 cards
timeout 250 blender -b -P $S -- $I/YWjGDJ9F7g.glb $O/broad_b 1500 - 0 cards
timeout 250 blender -b -P $S -- $I/t9KbsfYdXz.glb $O/broad_c 1500 - 0 cards
