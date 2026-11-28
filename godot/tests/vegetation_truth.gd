extends SceneTree
## Vegetation truth (1128c C17, owner: "why do the trees have leaves in the air?"). Every vegetation mesh must hold at the closest zoom: every foliage
## island (a connected component of the welded foliage triangles) is either a SOLID crown (closed surface) that touches wood, or lies within a small
## distance of trunk/branch geometry, or inside such a solid crown. No island floats free. Covers the CC0 tree LODs (Assets3D.tree_mesh: fir a, fir b,
## broadleaf, LOD0 and LOD1), the generated trees and palms (Props3D.conifer, Props3D.broadleaf, Bay3D.palm_mesh). Wood = the objects tr / bk of the glb,
## or the brownish triangles of a vertex-coloured mesh; foliage = the rest / the greenish triangles. A control mesh (a ball hovering over a trunk and a card
## hanging in the air) must FAIL the same check, so the check cannot pass by being blind.

const WELD := 10000.0

func _key(v: Vector3) -> Vector3i: return Vector3i(roundi(v.x * WELD), roundi(v.y * WELD), roundi(v.z * WELD))

## parts: [{tris: Array of [Vector3 x3], wood: bool}] -> flat lists
func _split(parts: Array) -> Dictionary:
	var wood: Array = []; var fol: Array = []
	for p in parts:
		for t in p.tris: (wood if p.wood else fol).append(t)
	return {"wood": wood, "fol": fol}

func _mesh_tris(m: Mesh, xf: Transform3D, wood_of: Callable, branch := false) -> Array:   # [{tris, wood}] per triangle class
	var wood_t: Array = []; var fol_t: Array = []
	for si in m.get_surface_count():
		var a := m.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var cols = a[Mesh.ARRAY_COLOR]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			for k in vs.size(): ix.append(k)
		for t in range(0, ix.size() - 2, 3):
			var tri := [xf * vs[ix[t]], xf * vs[ix[t + 1]], xf * vs[ix[t + 2]]]
			var col := Color.WHITE if cols == null else (cols as PackedColorArray)[ix[t]]
			if wood_of.call(si, col): wood_t.append(tri)
			else: fol_t.append(tri)
	return [{"tris": wood_t, "wood": true, "branch": branch}, {"tris": fol_t, "wood": false}]

static func _is_green(c: Color) -> bool: return c.g > c.r * 1.12 and c.g > c.b * 1.12

func _components(tris: Array) -> Array:   # Array of Array of tri indices
	var parent: Array = []
	for i in tris.size(): parent.append(i)
	var find := func(x: int) -> int:
		var r := x
		while parent[r] != r: r = parent[r]
		while parent[x] != r: var nx: int = parent[x]; parent[x] = r; x = nx
		return r
	var owner := {}
	for i in tris.size():
		for v in tris[i]:
			var k := _key(v)
			if owner.has(k):
				var ra: int = find.call(i); var rb: int = find.call(owner[k])
				if ra != rb: parent[ra] = rb
			else: owner[k] = i
	var comps := {}
	for i in tris.size():
		var r: int = find.call(i)
		if not comps.has(r): comps[r] = []
		comps[r].append(i)
	return comps.values()

func _solid(tris: Array, ids: Array) -> bool:
	if ids.size() < 12: return false
	var edges := {}
	for i in ids:
		var t: Array = tris[i]
		if ((t[1] as Vector3) - t[0]).cross((t[2] as Vector3) - t[0]).length() < 1e-9: continue   # a pole of a sphere: no area
		for e in 3:
			var a := _key(t[e]); var b := _key(t[(e + 1) % 3])
			var ek := [a, b] if (a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))) else [b, a]
			edges[ek] = int(edges.get(ek, 0)) + 1
	for k in edges: if int(edges[k]) != 2: return false
	return true

func _inside(p: Vector3, tris: Array, ids: Array) -> bool:   # ray parity along +X over a closed component
	var n := 0
	for i in ids:
		var t: Array = tris[i]
		var e1: Vector3 = t[1] - t[0]; var e2: Vector3 = t[2] - t[0]
		var h := Vector3(1, 0, 0).cross(e2); var det := e1.dot(h)
		if absf(det) < 1e-9: continue
		var f := 1.0 / det; var s: Vector3 = p - t[0]; var u := f * s.dot(h)
		if u < 0.0 or u > 1.0: continue
		var q := s.cross(e1); var v := f * Vector3(1, 0, 0).dot(q)
		if v < 0.0 or u + v > 1.0: continue
		if f * e2.dot(q) > 1e-7: n += 1
	return n % 2 == 1

## Returns the number of floating foliage islands and the number of islands checked.
func floating(name: String, parts: Array) -> Array:
	var sp := _split(parts)
	var wood: Array = sp.wood; var fol: Array = sp.fol
	var lo := Vector3(INF, INF, INF); var hi := Vector3(-INF, -INF, -INF)
	for t in wood + fol: for v in t: lo = lo.min(v); hi = hi.max(v)
	var tol := maxf(0.04 * (hi.y - lo.y), 0.02)
	var cell := tol * 2.0; var grid := {}
	for t in wood:
		for e in 3:
			for w in [0.0, 0.5]:   # a vertex and the midpoint of each edge
				var p: Vector3 = (t[e] as Vector3).lerp(t[(e + 1) % 3], w)
				var gk := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
				if not grid.has(gk): grid[gk] = []
				grid[gk].append(p)
	var near_wood := func(p: Vector3) -> bool:
		var g0 := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		for dx in range(-1, 2): for dy in range(-1, 2): for dz in range(-1, 2):
			var gk := g0 + Vector3i(dx, dy, dz)
			if grid.has(gk): for q in grid[gk]: if (q as Vector3).distance_to(p) <= tol: return true
		return false
	var comps := _components(fol)
	var solids: Array = []; var anchored: Array = []
	for ci in comps.size():
		if _solid(fol, comps[ci]): solids.append(ci)
	var is_anchored := {}
	var wood_pts: Array = []
	for t in wood: for e in 3: wood_pts.append(t[e]); wood_pts.append((t[e] as Vector3).lerp(t[(e + 1) % 3], 0.5))
	for ci in solids:   # a solid crown must hold wood (the trunk or a branch runs into it), touch it, or touch another anchored crown (a hedge of clumps)
		for i in comps[ci]:
			var hit := false
			for v in fol[i]: if near_wood.call(v): hit = true; break
			if hit: is_anchored[ci] = true; break
		if not is_anchored.has(ci):
			var lo2 := Vector3(INF, INF, INF); var hi2 := Vector3(-INF, -INF, -INF)
			for i in comps[ci]: for v in fol[i]: lo2 = lo2.min(v); hi2 = hi2.max(v)
			var tried := 0
			for q in wood_pts:
				var wp: Vector3 = q
				if wp.x < lo2.x or wp.y < lo2.y or wp.z < lo2.z or wp.x > hi2.x or wp.y > hi2.y or wp.z > hi2.z: continue
				tried += 1
				if _inside(wp, fol, comps[ci]): is_anchored[ci] = true; break
				if tried > 40: break
	var grew := true
	while grew:
		grew = false
		for ci in solids:
			if is_anchored.has(ci): continue
			for cj in is_anchored.keys():
				if _boxes_touch(fol, comps[ci], comps[cj], tol): is_anchored[ci] = true; grew = true; break
	var bad := 0; var seen := 0
	# branch pieces (objects bk): every vertex lies inside an anchored crown or hugs the trunk; a twig that ends outside the crown pokes out of it
	var trunk_pts: Array = []
	for p in parts:
		if p.wood and not p.get("branch", false):
			for t in p.tris: for e in 3: trunk_pts.append(t[e]); trunk_pts.append((t[e] as Vector3).lerp(t[(e + 1) % 3], 0.5))
	var tgrid := {}
	for q in trunk_pts:
		var gk := Vector3i(floori(q.x / cell), floori(q.y / cell), floori(q.z / cell))
		if not tgrid.has(gk): tgrid[gk] = []
		tgrid[gk].append(q)
	var near_trunk := func(p: Vector3) -> bool:
		var g0 := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		for dx in range(-1, 2): for dy in range(-1, 2): for dz in range(-1, 2):
			var gk := g0 + Vector3i(dx, dy, dz)
			if tgrid.has(gk): for q in tgrid[gk]: if (q as Vector3).distance_to(p) <= tol: return true
		return false
	var stray := 0; var bverts := 0
	for p in parts:
		if not (p.wood and p.get("branch", false)): continue
		for t in p.tris:
			for v in t:
				bverts += 1
				var ok: bool = near_trunk.call(v)
				if not ok:   # a branch tip that ends inside a foliage card's box is in the foliage
					for ci2 in comps.size():
						if _in_box(v, fol, comps[ci2], tol): ok = true; break
				if not ok:
					for cj in is_anchored.keys(): if _inside(v, fol, comps[cj]): ok = true; break
				if not ok: stray += 1
	if stray > 0: bad += 1; print("  %s: %d of %d branch vertices end outside the crown and away from the trunk" % [name, stray, bverts])
	for ci in comps.size():
		seen += 1
		if solids.has(ci):
			if not is_anchored.has(ci): bad += 1; print("  floating solid crown in %s: %d triangles" % [name, comps[ci].size()])
			continue
		var ids: Array = comps[ci]
		var c := Vector3.ZERO; var cnt := 0; var ok := false
		for i in ids:
			for v in fol[i]:
				c += v; cnt += 1
				if not ok and near_wood.call(v): ok = true
		c /= float(maxi(cnt, 1))
		if not ok:
			for cj in is_anchored.keys():
				if _inside(c, fol, comps[cj]): ok = true; break
		if not ok:   # a card sitting on a twig: a wood sample lies inside the card's box (the twig end passes through or behind it)
			var clo := Vector3(INF, INF, INF); var chi := Vector3(-INF, -INF, -INF)
			for i in ids: for v in fol[i]: clo = clo.min(v); chi = chi.max(v)
			var pad := tol * 0.5
			for gx in range(floori((clo.x - pad) / cell), floori((chi.x + pad) / cell) + 1):
				for gy in range(floori((clo.y - pad) / cell), floori((chi.y + pad) / cell) + 1):
					for gz in range(floori((clo.z - pad) / cell), floori((chi.z + pad) / cell) + 1):
						var gk2 := Vector3i(gx, gy, gz)
						if grid.has(gk2):
							for q in grid[gk2]:
								var qq: Vector3 = q
								if qq.x >= clo.x - pad and qq.y >= clo.y - pad and qq.z >= clo.z - pad and qq.x <= chi.x + pad and qq.y <= chi.y + pad and qq.z <= chi.z + pad: ok = true; break
						if ok: break
					if ok: break
				if ok: break
		if not ok: bad += 1
	if bad > 0: print("  %s: %d of %d foliage islands float (tolerance %.2f m)" % [name, bad, seen, tol])
	return [bad, seen]

func _in_box(p: Vector3, fol: Array, ids: Array, pad: float) -> bool:
	var lo := Vector3(INF, INF, INF); var hi := Vector3(-INF, -INF, -INF)
	for i in ids: for v in fol[i]: lo = lo.min(v); hi = hi.max(v)
	return p.x >= lo.x - pad and p.y >= lo.y - pad and p.z >= lo.z - pad and p.x <= hi.x + pad and p.y <= hi.y + pad and p.z <= hi.z + pad

func _boxes_touch(fol: Array, a: Array, b: Array, tol: float) -> bool:
	var la := Vector3(INF, INF, INF); var ha := Vector3(-INF, -INF, -INF); var lb := la; var hb := ha
	for i in a: for v in fol[i]: la = la.min(v); ha = ha.max(v)
	for i in b: for v in fol[i]: lb = lb.min(v); hb = hb.max(v)
	return la.x <= hb.x + tol and ha.x >= lb.x - tol and la.y <= hb.y + tol and ha.y >= lb.y - tol and la.z <= hb.z + tol and ha.z >= lb.z - tol

func _initialize() -> void:
	var checks := 0; var fails := 0; var islands := 0
	var subjects: Array = []   # [name, parts]
	for kind in ["fir_a", "fir_b", "broad"]:
		for lod in 2:
			var parts: Array = []
			for e in Assets3D.meshes("trees/%s_lod%d" % [kind, lod]):
				var nm := str(e.name)
				var obj_wood: bool = nm.begins_with("tr") or nm.begins_with("bk") or nm.begins_with("bs")
				var em: Mesh = e.mesh
				var tr := _mesh_tris(em, e.xf, func(si, _c): return obj_wood or Assets3D.mat_name(em, si).begins_with("Bark"), nm.begins_with("bk"))   # recut trees: objects tr/bk/bs; the Quaternius pines: material Bark_*
				parts.append_array(tr)
			subjects.append(["tree %s lod%d" % [kind, lod], parts])
	var by_colour := func(_si, c: Color) -> bool: return not _is_green(c)
	subjects.append(["Props3D.conifer", _mesh_tris(Props3D.conifer(), Transform3D.IDENTITY, by_colour)])
	subjects.append(["Props3D.broadleaf", _mesh_tris(Props3D.broadleaf(), Transform3D.IDENTITY, by_colour)])
	subjects.append(["Bay3D.palm_mesh", _mesh_tris(Bay3D.palm_mesh(), Transform3D.IDENTITY, by_colour)])
	for s in subjects:
		var r := floating(s[0], s[1])
		checks += 1; islands += int(r[1])
		if int(r[0]) > 0: fails += 1; print("FAIL: %s has %d floating foliage islands of %d" % [s[0], r[0], r[1]])
		var fol_n := 0
		for p in s[1]: if not p.wood: fol_n += (p.tris as Array).size()
		checks += 1
		if fol_n == 0: fails += 1; print("FAIL: %s has no foliage triangles (classification broke)" % s[0])
	# every kind and LOD carries its baked atlas, wood, stubs and cards, and the cards' UVs lie inside the atlas
	for kind in ["fir_a", "fir_b", "broad"]:
		for lod in 2:
			checks += 1
			var names := []; var uv_ok := true; var card_tris := 0; var mats_ok := true
			for e in Assets3D.meshes("trees/%s_lod%d" % [kind, lod]):
				names.append(str(e.name))
				for si in (e.mesh as Mesh).get_surface_count():
					var arr := (e.mesh as Mesh).surface_get_arrays(si)
					var mn := Assets3D.mat_name(e.mesh, si)
					if kind.begins_with("fir"): mats_ok = mats_ok and (mn == "Bark_NormalTree" or mn == "Leaves_Pine")
					if str(e.name).begins_with("cd") or mn == "Leaves_Pine":
						for uv in (arr[Mesh.ARRAY_TEX_UV] as PackedVector2Array): if uv.x < -0.001 or uv.x > 1.001 or uv.y < -0.001 or uv.y > 1.001: uv_ok = false
						card_tris += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			var tex_ok := FileAccess.file_exists("res://world3d/tex/tree_pine_leaf.png") if kind.begins_with("fir") else FileAccess.file_exists("res://world3d/tex/tree_%s_atlas%d.png" % [kind, lod])
			var structure_ok: bool = (mats_ok and card_tris >= 100) if kind.begins_with("fir") else (names.has("tr") and names.has("bs") and names.has("cd") and card_tris >= 100)
			if not (structure_ok and uv_ok and tex_ok): fails += 1; print("FAIL: tree %s lod%d: objects %s, materials ok %s, uv inside the atlas %s, texture %s, card triangles %d" % [kind, lod, str(names), str(mats_ok), str(uv_ok), str(tex_ok), card_tris])
	# the far model is what the low tier draws everywhere: a triangle budget per tree
	for kind in ["fir_a", "fir_b", "broad"]:
		checks += 1
		var tris := 0
		for e in Assets3D.meshes("trees/%s_lod1" % kind): for si in (e.mesh as Mesh).get_surface_count(): tris += (e.mesh as Mesh).surface_get_arrays(si)[Mesh.ARRAY_INDEX].size() / 3
		if tris > 1500: fails += 1; print("FAIL: tree %s lod1 has %d triangles (budget 1500)" % [kind, tris])
	# the control: a trunk with a hovering ball and a card in the air must be caught
	var trunk := [[Vector3(-0.05, 0, 0), Vector3(0.05, 0, 0), Vector3(0, 3, 0)], [Vector3(0, 0, -0.05), Vector3(0, 0, 0.05), Vector3(0, 3, 0)]]
	var sm := SphereMesh.new(); sm.radius = 0.6; sm.height = 1.2; sm.radial_segments = 8; sm.rings = 4
	var sa := sm.get_mesh_arrays(); var sv: PackedVector3Array = sa[Mesh.ARRAY_VERTEX]; var six: PackedInt32Array = sa[Mesh.ARRAY_INDEX]
	var ball: Array = []
	for t in range(0, six.size() - 2, 3): ball.append([sv[six[t]] + Vector3(4, 6, 0), sv[six[t + 1]] + Vector3(4, 6, 0), sv[six[t + 2]] + Vector3(4, 6, 0)])
	var card := [[Vector3(-3, 5, 0), Vector3(-2, 5, 0), Vector3(-2.5, 6, 0)]]
	var ctl := floating("control", [{"tris": trunk, "wood": true}, {"tris": ball + card, "wood": false}])
	checks += 1
	if int(ctl[0]) != 2: fails += 1; print("FAIL: the control (a hovering ball and a hanging card) must give 2 floating islands, got %d" % int(ctl[0]))
	var anchored_ball: Array = []
	for t in ball: anchored_ball.append([t[0] - Vector3(4, 3.4, 0), t[1] - Vector3(4, 3.4, 0), t[2] - Vector3(4, 3.4, 0)])   # the same ball sitting on the trunk top
	var ctl2 := floating("control2", [{"tris": trunk, "wood": true}, {"tris": anchored_ball, "wood": false}])
	checks += 1
	if int(ctl2[0]) != 0: fails += 1; print("FAIL: the control crown sitting on the trunk must pass, got %d floating" % int(ctl2[0]))
	var twig := [[Vector3(0.2, 3.0, 0), Vector3(0.9, 3.3, 0), Vector3(0.9, 3.35, 0.02)]]   # a branch sticking out of the crown ball (radius 0.6 at y 2.6)
	var ctl3 := floating("control3", [{"tris": trunk, "wood": true}, {"tris": twig, "wood": true, "branch": true}, {"tris": anchored_ball, "wood": false}])
	checks += 1
	if int(ctl3[0]) != 1: fails += 1; print("FAIL: a branch that ends outside the crown must be caught, got %d" % int(ctl3[0]))
	print("VEGETATION-TRUTH checks=%d islands=%d" % [checks, islands])
	print("VEGETATION-TRUTH OK" if fails == 0 else "VEGETATION-TRUTH FAILED %d" % fails)
	quit(0 if fails == 0 else 1)
