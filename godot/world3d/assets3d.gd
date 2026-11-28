class_name Assets3D
extends RefCounted
## CC0 asset pass (WO-23 benchmark): houses, trees and props loaded from .glb files under res://world3d/assets (sources in docs/ASSETS.md).
## The electrical kit stays generated; these are the things round it. Materials are built here, by surface name, so the engine-driven
## states (lit windows, blackout dimming, night lamps) stay in the stage code and the .glb files carry geometry and UVs only.

const DIR := "res://world3d/assets/"
const TEX := "res://world3d/tex/"
const PORCH := {"house_a": Vector2(0.0, 3.55), "house_c": Vector2(0.0, 3.6), "house_e": Vector2(0.0, 3.55), "house_g": Vector2(-3.3, 3.7), "house_k": Vector2(1.76, 4.55), "house_t": Vector2(0.0, 4.8)}   # x, z of the door on the front wall
const HOUSES := ["house_a", "house_c", "house_e", "house_g", "house_k", "house_t"]

static var _cache := {}

static func tex(n: String) -> Texture2D:
	var p := TEX + n
	return load(p) if ResourceLoader.exists(p) else null

## Every mesh in a .glb with its transform inside the file: [{mesh, xf, name}]. Cached.
static func meshes(path: String) -> Array:
	if _cache.has(path): return _cache[path]
	var out: Array = []
	var ps = load(DIR + path + ".glb")
	if ps is PackedScene:
		var root: Node = (ps as PackedScene).instantiate()
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children(): stack.append(c)
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var xf := Transform3D.IDENTITY; var p: Node = n
				while p != null and p != root:
					if p is Node3D: xf = (p as Node3D).transform * xf
					p = p.get_parent()
				out.append({"mesh": (n as MeshInstance3D).mesh, "xf": xf, "name": n.name})
		root.free()
	_cache[path] = out
	return out

static func mat_name(m: Mesh, si: int) -> String:
	var mt := m.surface_get_material(si)
	return str(mt.resource_name) if mt != null else ""

## One ArrayMesh with every surface of the .glb (the file may hold several objects), materials taken from `mats` by the source material name.
static func merged(path: String, mats: Dictionary) -> ArrayMesh:
	var key := "merged:" + path
	var am := ArrayMesh.new()
	for e in meshes(path):
		var m: Mesh = e.mesh
		for si in m.get_surface_count():
			var a := m.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns = a[Mesh.ARRAY_NORMAL]
			var xf: Transform3D = e.xf
			if xf != Transform3D.IDENTITY:
				for i in vs.size(): vs[i] = xf * vs[i]
				if ns != null: for i in (ns as PackedVector3Array).size(): ns[i] = xf.basis * ns[i]
				a[Mesh.ARRAY_VERTEX] = vs; a[Mesh.ARRAY_NORMAL] = ns
			a[Mesh.ARRAY_TANGENT] = null
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var mn := mat_name(m, si)
			if mats.has(mn): am.surface_set_material(am.get_surface_count() - 1, mats[mn])
	return am

## A PBR surface from the tex/ folder: <n>_albedo, <n>_normal, <n>_rough; uv1 is in metres already (the house files carry metre UVs).
static func pbr(n: String, tint := Color.WHITE, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(n + "_albedo.jpg"); m.albedo_color = tint
	var nt := tex(n + "_normal.jpg")
	if nt != null: m.normal_enabled = true; m.normal_texture = nt
	var rt := tex(n + "_rough.jpg")
	if rt != null: m.roughness_texture = rt
	m.roughness = rough; m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m

# --------------------------------------------------------------------------------------------------------------------
# Houses (Kenney City Kit Suburban, re-cut: trim / wall / roof / window surfaces, PBR box UVs on wall and roof)
# --------------------------------------------------------------------------------------------------------------------
## Shared materials of an estate. `win` is the one lit-window material the stage drives. `dim` lists [material, lit colour] for the blackout.
static func house_mats(win: Material) -> Dictionary:
	var trim := StandardMaterial3D.new()
	trim.albedo_texture = tex("house_palette_albedo.png"); trim.roughness = 0.8
	trim.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var roof := pbr("roof", Color(0.78, 0.74, 0.72), 1.0)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.05, 0.07, 0.10); dark.roughness = 0.25   # a pane with nobody home: never lit
	var porch := Kit3D._lamp_mat(Color(1.0, 0.78, 0.45))   # one emissive shared by every porch light; Kit3D drives it with the estate group
	Kit3D._reg(null, porch, 0.0, 7.0, "estate")
	return {"trim": trim, "roof": roof, "window": win, "window_dark": dark, "porch": porch, "keep": [], "wall_tints": [Color(0.92, 0.88, 0.80), Color(0.80, 0.84, 0.88), Color(0.90, 0.84, 0.70), Color(0.86, 0.80, 0.78), Color(0.78, 0.86, 0.80), Color(0.94, 0.93, 0.90)],
		"dim": [[trim, Color.WHITE], [roof, Color(0.78, 0.74, 0.72)]]}

## One house of kind `kind` (HOUSES[i]) at `at`, turned `yaw`. Returns its node; its wall material is added to mats.dim.
static func house(parent: Node3D, kind: int, at: Vector3, yaw: float, mats: Dictionary, quality: String) -> Node3D:
	var id: String = HOUSES[kind % HOUSES.size()]
	var tint: Color = (mats.wall_tints as Array)[kind % (mats.wall_tints as Array).size()]
	var wall := pbr("plaster", tint, 1.0)
	(mats.dim as Array).append([wall, tint])
	var sm := {"trim": mats.trim, "wall": wall, "roof": mats.roof, "window": mats.window, "window_dark": mats.window_dark}
	var n := Node3D.new(); n.name = "House"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	for e in meshes("houses/" + id):
		var mi := MeshInstance3D.new(); mi.mesh = e.mesh; mi.transform = e.xf; mi.name = "Body"
		for si in (e.mesh as Mesh).get_surface_count():
			var k := mat_name(e.mesh, si)
			if sm.has(k): mi.set_surface_override_material(si, sm[k])
		n.add_child(mi)
	# the porch light over the door (door positions read off the Kenney models), and its pool; all on the estate supply
	var pp: Vector2 = PORCH.get(id, Vector2(0.0, 3.6))
	var pl := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.3, 0.22, 0.14); pl.mesh = bm; pl.material_override = mats.porch
	pl.position = Vector3(pp.x, 2.5, pp.y + 0.08); pl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(pl)
	if quality != "low":
		for spec in [[Vector3(pp.x, 2.1, pp.y + 1.0), 7.0, 1.5], [Vector3(pp.x * 0.5, 2.4, pp.y + 3.5), 11.0, 1.8]]:   # the doorstep, and the light of the rooms on the lawn
			var wl := OmniLight3D.new(); wl.light_color = Color(1.0, 0.78, 0.48); wl.omni_range = spec[1]; wl.omni_attenuation = 1.2; wl.shadow_enabled = false
			wl.position = spec[0]; n.add_child(wl)
			var km := Kit3D._lamp_mat(Color.BLACK); (mats.keep as Array).append(km)   # Kit3D holds materials weakly: keep one alive per light
			Kit3D._reg(wl, km, spec[2], 0.0, "estate")
	return n

## The blackout: every house material takes the cold dark tone (a multiplier on its lit colour).
static func dim_mats(mats: Dictionary, dark: bool) -> void:
	for p in mats.dim:
		(p[0] as StandardMaterial3D).albedo_color = (p[1] as Color) * (Color(0.42, 0.44, 0.52) if dark else Color.WHITE)

# --------------------------------------------------------------------------------------------------------------------
# Province houses (near LOD of the MultiMesh towns; the far LOD stays the generated box, Props3D.house)
# --------------------------------------------------------------------------------------------------------------------
static var _pv := {}
const KIT_SURFACES := ["trim", "wall", "roof", "window"]

## House `kind` (HOUSES) as one ArrayMesh with the surfaces KIT_SURFACES in that order. The lit and the dark panes of the file are one surface, each
## pane's hash in UV2.x so the shader can switch panes one by one against the building's energy.
static func province_house(kind: int) -> ArrayMesh:
	return province_mesh("houses/" + HOUSES[kind % HOUSES.size()])

## Low-rise blocks and towers of the Kenney Commercial kit (assets/blocks), in the same four surfaces. `i` indexes BLOCKS or TOWERS.
const BLOCKS := ["building-a", "building-c", "building-f", "building-h"]
const TOWERS := ["building-skyscraper-a", "building-skyscraper-b", "building-skyscraper-c", "building-skyscraper-e"]
const BLOCK_HEIGHT := [19.3, 11.5, 24.7, 20.5, 33.9, 52.7, 52.9, 50.4]   # the files' heights (m): BLOCKS then TOWERS
static func province_block(tower: bool, i: int) -> ArrayMesh:
	var l: Array = TOWERS if tower else BLOCKS
	return province_mesh("blocks/" + l[i % l.size()])

static func province_mesh(id: String) -> ArrayMesh:
	if _pv.has(id): return _pv[id]
	var by := {"trim": [], "wall": [], "roof": [], "window": []}
	for e in meshes(id):
		var m: Mesh = e.mesh; var xf: Transform3D = e.xf
		for si in m.get_surface_count():
			var mn := mat_name(m, si)
			if mn == "window_dark": mn = "window"
			if by.has(mn): (by[mn] as Array).append([m.surface_get_arrays(si), xf])
	var am := ArrayMesh.new(); var names := []
	for name in KIT_SURFACES:
		var vs := PackedVector3Array(); var ns := PackedVector3Array(); var uv := PackedVector2Array(); var ix := PackedInt32Array()
		for part in by[name]:
			var a: Array = part[0]; var xf: Transform3D = part[1]
			var base := vs.size()
			var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]; var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]; var pu: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			for i in pv.size():
				vs.append(xf * pv[i]); ns.append((xf.basis * pn[i]).normalized()); uv.append(pu[i] if pu.size() > i else Vector2.ZERO)
			for j in (a[Mesh.ARRAY_INDEX] as PackedInt32Array): ix.append(base + j)
		if vs.is_empty(): continue
		var arr := []; arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs; arr[Mesh.ARRAY_NORMAL] = ns; arr[Mesh.ARRAY_TEX_UV] = uv; arr[Mesh.ARRAY_INDEX] = ix
		if name == "window": arr[Mesh.ARRAY_TEX_UV2] = _pane_hash(vs, ix)
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr); names.append(name)
	am.set_meta("names", names)   # a file may have no roof or no window: the surface order is these names, not KIT_SURFACES
	_pv[id] = am
	return am

## UV2.x per vertex: a hash in 0..1 of the pane (the connected set of triangles, vertices welded to 1 cm) the vertex belongs to.
static func _pane_hash(vs: PackedVector3Array, ix: PackedInt32Array) -> PackedVector2Array:
	var par := PackedInt32Array(); par.resize(vs.size())
	for i in vs.size(): par[i] = i
	var key := {}
	for i in vs.size():
		var k := Vector3i(roundi(vs[i].x * 100.0), roundi(vs[i].y * 100.0), roundi(vs[i].z * 100.0))
		if key.has(k): par[i] = key[k]
		else: key[k] = i
	var find := func(x: int) -> int:
		while par[x] != x: par[x] = par[par[x]]; x = par[x]
		return x
	for t in ix.size() / 3:
		var r0: int = find.call(ix[t * 3])
		for c in [1, 2]:
			var r1: int = find.call(ix[t * 3 + c])
			if r1 != r0: par[r1] = r0
	var out := PackedVector2Array(); out.resize(vs.size())
	for i in vs.size():
		var r: int = find.call(i)
		out[i] = Vector2(WorldMath.hash2(r, 17, 4242), 0.0)
	return out

## Roof tints of healthy houses. None is a neutral grey: a shed sector is drawn in a cool dark shadow (house_kit and house shaders, shed_cast) and no healthy
## roof may look like it (1128c P01). Near: multiplied on the tile texture (mean colour about 0.46, 0.27, 0.18); far: the colour itself.
const ROOF_TINTS_NEAR := [Vector3(1.05, 0.62, 0.45), Vector3(0.42, 0.80, 1.55), Vector3(0.75, 0.60, 0.48)]   # terracotta, slate-blue, brown
const ROOF_TINTS_FAR := [Vector3(0.50, 0.17, 0.11), Vector3(0.29, 0.34, 0.47), Vector3(0.42, 0.34, 0.26), Vector3(0.62, 0.55, 0.45)]   # terracotta, slate-blue, brown, tan
const ROOF_SAT_MIN := 0.2   ## tests/province_shed_truth.gd: the least HSV saturation any healthy roof tint may have

## The four materials of the near house LOD, in KIT_SURFACES order (shaders/house_kit.gdshader). Province3D drives `night` on all of them.
static func kit_house_mats(palette := "house_palette_albedo.png", grid := false) -> Array:
	var sh: Shader = load("res://world3d/shaders/house_kit.gdshader")
	var out: Array = []
	var sets := [[palette, "", ""], ["plaster_albedo.jpg", "plaster_normal.jpg", "plaster_rough.jpg"], ["roof_albedo.jpg", "roof_normal.jpg", "roof_rough.jpg"], ["", "", ""]]
	for mode in 4:
		var m := ShaderMaterial.new(); m.shader = sh; m.set_shader_parameter("mode", mode); m.set_shader_parameter("grid", grid)
		var set: Array = sets[mode]
		if set[0] != "": m.set_shader_parameter("alb", tex(set[0]))
		if set[1] != "": m.set_shader_parameter("nrm", tex(set[1]))
		if set[2] != "": m.set_shader_parameter("rgh", tex(set[2]))
		m.set_shader_parameter("roof_tint", PackedVector3Array(ROOF_TINTS_NEAR))
		out.append(m)
	return out

# --------------------------------------------------------------------------------------------------------------------
# Trees (Poly Haven fir_tree_01 and tree_small_02, alpha-card LODs cut in Blender, see docs/ASSETS.md)
# --------------------------------------------------------------------------------------------------------------------
static var _tree_mats := {}
static func _tree_mat(kind: String, lod: int) -> Dictionary:
	var mkey := "%s%d" % [kind, lod]
	if _tree_mats.has(mkey): return _tree_mats[mkey]
	var d := {}
	if kind.begins_with("fir"):   # Quaternius pines (CC0, poly.pizza): their leaf cards, the scan's bark on the trunk so it sits beside the scanned broadleaf
		var lf := StandardMaterial3D.new()
		lf.albedo_texture = tex("tree_pine_leaf.png"); lf.vertex_color_use_as_albedo = true; lf.albedo_color = Color(0.62, 0.86, 0.80)
		lf.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; lf.alpha_scissor_threshold = 0.4; lf.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
		lf.cull_mode = BaseMaterial3D.CULL_DISABLED; lf.roughness = 0.85; lf.backlight_enabled = true; lf.backlight = Color(0.12, 0.2, 0.14)
		lf.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		var bk := StandardMaterial3D.new()
		bk.albedo_texture = tex("tree_fir_trunk_a_albedo.jpg" if kind == "fir_a" else "tree_fir_trunk_b_albedo.jpg"); bk.uv1_triplanar = true; bk.uv1_scale = Vector3.ONE * 0.45
		bk.albedo_color = Color(0.85, 0.8, 0.76); bk.roughness = 0.92; bk.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		d = {"Bark_NormalTree": bk, "Leaves_Pine": lf}
		_tree_mats[mkey] = d; return d
	var tw := StandardMaterial3D.new()
	tw.albedo_texture = tex("tree_%s_atlas%d.png" % [kind, lod])   # baked from the scan's own leaves, cluster by cluster (tools/blender/recut.py)
	tw.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR; tw.alpha_scissor_threshold = 0.32
	tw.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	tw.cull_mode = BaseMaterial3D.CULL_DISABLED; tw.vertex_color_use_as_albedo = true; tw.roughness = 0.85; tw.albedo_color = Color(1.0, 1.0, 0.95)
	tw.backlight_enabled = true; tw.backlight = Color(0.30, 0.34, 0.22)
	tw.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var tr := StandardMaterial3D.new()
	tr.albedo_texture = tex("tree_broad_trunk_albedo.jpg")
	tr.vertex_color_use_as_albedo = true; tr.roughness = 0.9
	tr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	d = {"trunk": tr, "bark": tr, "twig": tw}
	_tree_mats[mkey] = d; return d

static var _tree_meshes := {}
static func tree_mesh(kind: String, lod: int) -> ArrayMesh:
	var key := "%s%d" % [kind, lod]
	if _tree_meshes.has(key): return _tree_meshes[key]
	var am := merged("trees/%s_lod%d" % [kind, lod], _tree_mat(kind, lod))
	_tree_meshes[key] = am
	return am

## Draws the forest as MultiMeshes in 96 m cells: LOD0 within `near` m of a cell's centre (high tier), LOD1 beyond (and everywhere on low).
## `conifer` and `broad` are [Transform3D] / [Color] lists as Bench3D._trees builds them for the procedural trees (unit-height scale in y).
static func trees(root: Node3D, cx: Array, cc: Array, bx: Array, bc: Array, quality: String, gy: Callable = Callable()) -> void:
	var near := 0.0 if quality == "low" else (110.0 if quality == "medium" else 150.0)
	var groups := {}
	for pass_i in 2:
		var xf: Array = cx if pass_i == 0 else bx; var cols: Array = cc if pass_i == 0 else bc
		for i in xf.size():
			var t: Transform3D = xf[i]
			var kind := "broad"
			if pass_i == 0: kind = "fir_a" if (int(absf(t.origin.x * 7.3 + t.origin.z * 3.1)) % 3) == 0 else "fir_b"
			var kt := [[t, cols[i]]]
			if quality != "low" and gy.is_valid():   # a second tree beside it: the wood is massed, not a scatter
				var h := absf(sin(t.origin.x * 12.9898 + t.origin.z * 78.233)) * TAU
				var o := t.origin + Vector3(cos(h), 0, sin(h)) * (2.6 + 1.6 * absf(cos(h * 3.1)))
				o.y = gy.call(o.x, o.z) - 0.3
				kt.append([Transform3D(t.basis.rotated(Vector3.UP, 1.7).scaled_local(Vector3(0.88, 0.88, 0.88)), o), cols[i]])
			for kk in kt:
				var tt: Transform3D = kk[0]
				var key2 := "%s|%d|%d" % [kind, floori(tt.origin.x / 96.0), floori(tt.origin.z / 96.0)]
				if not groups.has(key2): groups[key2] = {"kind": kind, "xf": [], "col": [], "c": Vector3.ZERO}
				var g2: Dictionary = groups[key2]
				(g2.xf as Array).append(tt); (g2.col as Array).append(kk[1]); g2.c += tt.origin
	var heights := {}
	for k in ["fir_a", "fir_b", "broad"]:
		heights[k] = _trunk_h(k)
	for key in groups:
		var g: Dictionary = groups[key]; var n: int = (g.xf as Array).size(); var c: Vector3 = g.c / float(n)
		var kind: String = g.kind
		var lods := [1] if near <= 0.0 else [0, 1]
		for lod in lods:
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
			mm.mesh = tree_mesh(kind, lod); mm.instance_count = n
			var h: float = heights[kind]
			for i in n:
				var t: Transform3D = (g.xf as Array)[i]
				var s: float = 1.0 / h
				mm.set_instance_transform(i, Transform3D(t.basis.scaled_local(Vector3(s, s, s)), t.origin))
				var col: Color = (g.col as Array)[i]
				mm.set_instance_color(i, Color(clampf(col.r / 1.2, 0.0, 1.0), clampf(col.g / 1.2, 0.0, 1.0), clampf(col.b / 1.2, 0.0, 1.0)))
			var mi := MultiMeshInstance3D.new(); mi.name = "Forest_%s_L%d" % [kind, lod]; mi.multimesh = mm; root.add_child(mi)
			if near > 0.0:
				if lod == 0: mi.visibility_range_end = near + 40.0; mi.visibility_range_end_margin = 20.0; mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				else: mi.visibility_range_begin = near + 20.0; mi.visibility_range_begin_margin = 20.0; mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if (lod == 0 and quality == "high") else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## One LOD of a province wood as MultiMeshes in `cell` m cells, drawn between `vmin` and `vmax` m from the camera (dithered at both ends).
## `xf` carries the tree's height in its basis scale, as Province3D's procedural trees do; `kind` is "fir_a", "fir_b" or "broad".
static func forest_lod(root: Node3D, kind: String, xf: Array, cols: Array, lod: int, cell: float, vmin: float, vmax: float, shadow: bool) -> void:
	var groups := {}
	for i in xf.size():
		var o: Vector3 = (xf[i] as Transform3D).origin
		var key := Vector2i(floori(o.x / cell), floori(o.z / cell))
		if not groups.has(key): groups[key] = []
		(groups[key] as Array).append(i)
	var h := _trunk_h(kind)
	var mesh := tree_mesh(kind, lod)
	for key in groups:
		var ids: Array = groups[key]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh; mm.instance_count = ids.size()
		for q in ids.size():
			var t: Transform3D = xf[ids[q]]
			mm.set_instance_transform(q, Transform3D(t.basis.scaled_local(Vector3.ONE / h), t.origin))
			var c: Color = cols[ids[q]]
			mm.set_instance_color(q, Color(clampf(c.r / 1.2, 0.0, 1.0), clampf(c.g / 1.2, 0.0, 1.0), clampf(c.b / 1.2, 0.0, 1.0)))
		var mi := MultiMeshInstance3D.new(); mi.name = "Wood_%s_L%d_%d_%d" % [kind, lod, key.x, key.y]; mi.multimesh = mm; root.add_child(mi)
		if vmin > 0.0: mi.visibility_range_begin = vmin; mi.visibility_range_begin_margin = vmin * 0.1
		if vmax > 0.0: mi.visibility_range_end = vmax; mi.visibility_range_end_margin = vmax * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Trunk height of a tree file (the cards reach a little beyond it): the unit the scene's tree scale is given in.
static func _trunk_h(kind: String) -> float:   # the model's height (the scan's wood, or the whole pine)
	var h := 1.0
	for e in meshes("trees/%s_lod1" % kind):
		if kind.begins_with("fir") or str(e.name) == "tr": h = maxf(h, (e.mesh as Mesh).get_aabb().size.y)
	return h

# --------------------------------------------------------------------------------------------------------------------
# Props
# --------------------------------------------------------------------------------------------------------------------
## The lowest vertices of a mesh: where a pole stands (the files are centred on their bounding box, the lamp's pole is at one end).
static func foot(m: Mesh) -> Vector3:
	var s := Vector3.ZERO; var c := 0
	for si in m.get_surface_count():
		var vs: PackedVector3Array = m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
		for v in vs: if v.y < 0.15: s += Vector3(v.x, 0.0, v.z); c += 1
	return s / float(maxi(c, 1))

static func surf_centre(m: Mesh, name: String) -> Vector3:
	var lo := Vector3(1e9, 1e9, 1e9); var hi := Vector3(-1e9, -1e9, -1e9); var any := false
	for si in m.get_surface_count():
		if mat_name(m, si) != name: continue
		for v in (m.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
			lo = lo.min(v); hi = hi.max(v); any = true
	return (lo + hi) * 0.5 if any else Vector3.ZERO

## Poly Haven Street Lamp 01 (3.9 m, scaled to `h`): bulb emissive and registered with Kit3D's night/blackout group, a warm omni below it.
static func street_lamp(parent: Node3D, at: Vector3, yaw: float, quality: String, group: String, h := 6.2) -> Node3D:
	var n := Node3D.new(); n.name = "StreetLamp"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	var es := meshes("props/street_lamp_01")
	if es.is_empty(): return n
	var m: Mesh = es[0].mesh; var s := h / 3.87
	var f := foot(m)
	var lm := Kit3D._lamp_mat(Color(1.0, 0.74, 0.42))
	var bc0 := surf_centre(m, "street_lamp_01_bulb") - f
	var phi := atan2(-bc0.x, bc0.z)   # turn the model so its arm points along the stand's +Z, as the generated lamp's did
	var rb := Basis(Vector3.UP, phi)
	var mi := MeshInstance3D.new(); mi.mesh = m; mi.scale = Vector3.ONE * s; mi.rotation.y = phi; mi.position = -(rb * f) * s; n.add_child(mi)
	for si in m.get_surface_count():
		if mat_name(m, si).ends_with("_bulb"): mi.set_surface_override_material(si, lm)
	var bc := (rb * bc0) * s
	var lt: OmniLight3D = null
	if quality != "low":
		lt = OmniLight3D.new(); lt.light_color = Color(1.0, 0.72, 0.42); lt.omni_range = h * 3.2; lt.omni_attenuation = 1.0; lt.shadow_enabled = false
		lt.position = bc - Vector3(0, 0.4, 0); n.add_child(lt)
	Kit3D._reg(lt, lm, 16.0, 6.0, group)
	if Kit3D._halo_here(at, quality): Kit3D.glow(n, bc, group, quality, bc.y)   # the province's halo and road pool, dark with the group
	return n

## A floodlight head (Poly Haven Flood Lights, wall light) on a mast top, aimed along yaw / pitch; its glass is the registered emissive.
static func flood_head(parent: Node3D, at: Vector3, yaw: float, pitch: float, lm: StandardMaterial3D) -> void:
	var es := meshes("props/flood_head")
	if es.is_empty(): return
	var n := Node3D.new(); n.position = at; n.rotation = Vector3(pitch, yaw, 0.0); parent.add_child(n)
	for e in es:
		var mi := MeshInstance3D.new(); mi.mesh = e.mesh; mi.scale = Vector3.ONE * 3.0; mi.position = Vector3(0, -0.2, 0.0); n.add_child(mi)
		for si in (e.mesh as Mesh).get_surface_count():
			if mat_name(e.mesh, si).ends_with("_glass"): mi.set_surface_override_material(si, lm)

## A plain mesh prop from props/<id>.glb at `at`, scaled `s`, turned `yaw`.
static func prop(parent: Node3D, id: String, at: Vector3, yaw: float, s := 1.0, shadow := true) -> Node3D:
	var n := Node3D.new(); n.name = id; n.position = at; n.rotation.y = yaw; n.scale = Vector3.ONE * s; parent.add_child(n)
	for e in meshes("props/" + id):
		var mi := MeshInstance3D.new(); mi.mesh = e.mesh; mi.transform = e.xf; n.add_child(mi)
		if not shadow: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

## A Kenney blocky character (people/char_a|e|h, 1.75 m) standing at `at`, facing `yaw`. The file's node offset is dropped: its mesh is already on the ground.
static func person(parent: Node3D, id: String, at: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new(); n.name = "Person"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	for e in meshes("people/" + id):
		var mi := MeshInstance3D.new(); mi.mesh = e.mesh; n.add_child(mi)
	return n

## The Kenney sedan (3.6 m, front toward +Z) with two headlights: emissive lenses and, above the low tier, two spots; lit whenever it is night.
static func car(parent: Node3D, at: Vector3, yaw: float, quality: String) -> Node3D:
	var n := Node3D.new(); n.name = "Car"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	for e in meshes("people/sedan"):
		var mi := MeshInstance3D.new(); mi.mesh = e.mesh; n.add_child(mi)
	var lm := Kit3D._lamp_mat(Color(1.0, 0.95, 0.80))
	for sx in [-0.62, 0.62]:
		var l := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.34, 0.2, 0.06); l.mesh = bm; l.material_override = lm; l.position = Vector3(sx, 0.62, 1.8)
		l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(l)
	var sp: SpotLight3D = null
	if quality != "low":
		sp = SpotLight3D.new(); sp.light_color = Color(1.0, 0.95, 0.82); sp.spot_range = 26.0; sp.spot_angle = 30.0; sp.shadow_enabled = false
		n.add_child(sp); sp.position = Vector3(0, 0.7, 1.9); sp.look_at_from_position(sp.position, sp.position + Vector3(0, -0.12, 1.0), Vector3.UP)
	Kit3D._reg(sp, lm, 28.0, 7.0, "car")
	return n

## The same mesh prop with its materials made matte (a car cover is cloth, not mirror: with no reflections in the sky a metallic surface is black).
static func prop_matte(parent: Node3D, id: String, at: Vector3, yaw: float, s := 1.0) -> Node3D:
	var n := prop(parent, id, at, yaw, s)
	for mi in n.get_children():
		var m: Mesh = (mi as MeshInstance3D).mesh
		for si in m.get_surface_count():
			var sm := m.surface_get_material(si)
			if sm is StandardMaterial3D:
				var c := (sm as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.metallic = 0.0; c.metallic_texture = null; c.roughness = 0.85; c.roughness_texture = null; c.albedo_color = Color(2.8, 2.9, 3.2)   # the Poly Haven cover is charcoal (albedo 0.2): lifted to a grey tarp, or it is a black box at night
				(mi as MeshInstance3D).set_surface_override_material(si, c)
	return n
