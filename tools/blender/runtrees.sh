#!/bin/zsh
cd /tmp/claude-1000/assets-dl
timeout 900 blender -b -P tools/lod.py -- m_fir_tree_01/fir_tree_01_1k.gltf fir_tree_01_b_LOD0 twig out/fir_b fir 3400 300 800 250 0 5.0 6.5 > out/fir_b.log 2>&1
timeout 900 blender -b -P tools/lod.py -- m_fir_tree_01/fir_tree_01_1k.gltf fir_tree_01_a_LOD0 twig out/fir_a fir 3400 300 800 250 0 5.0 6.5 > out/fir_a.log 2>&1
timeout 900 blender -b -P tools/lod.py -- m_tree_small_02/tree_small_02_1k.gltf tree_small_02_LOD0 leaves out/broad broad 2800 260 700 160 0 5.5 8.0 > out/broad.log 2>&1
echo finished > out/trees.done
