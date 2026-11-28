extends SceneTree
## Mesh winding truth (audit 1128c, owner bug "roofs slashed from the top"): every generated building and prop mesh draws its
## faces front-side out. Godot's front face is clockwise seen from outside, so for each triangle the geometric outward direction
## is -(v1 - v0) x (v2 - v0); it must agree with the stored vertex normal (positive dot), and every roof face (normal mostly up)
## must face up. No house instance is mirrored: the province scales houses by positive sizes only (province3d.gd, _build_layout).

func _check_mesh(nm: String, mesh: Mesh, fails: Array) -> int:
	var tris := 0
	for si in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(si)
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]; var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if ix.is_empty():
			for k in vs.size(): ix.append(k)
		for t in range(0, ix.size() - 2, 3):
			var p0 := vs[ix[t]]; var p1 := vs[ix[t + 1]]; var p2 := vs[ix[t + 2]]
			var g := -(p1 - p0).cross(p2 - p0)
			if g.length() < 1e-9: continue
			g = g.normalized()
			var n := (ns[ix[t]] + ns[ix[t + 1]] + ns[ix[t + 2]]).normalized()
			tris += 1
			if g.dot(n) <= 0.0: fails.append("%s tri %d: front side faces inward (g %s, n %s)" % [nm, t / 3, g, n])
			elif n.y > 0.5 and g.y <= 0.0: fails.append("%s tri %d: roof face points down" % [nm, t / 3])
	return tris

func _glb_files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir): if f.ends_with(".glb"): out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir): _glb_files(dir + "/" + d, out)

func _initialize() -> void:
	var fails: Array = []
	var meshes := {"Props3D.house": Props3D.house(), "Props3D.block": Props3D.block(), "Props3D.transformer": Props3D.transformer(), "Province3D.lamp_pole": Province3D._lamp_pole_mesh(),
		"Bay3D.house_mesh": Bay3D.house_mesh(7.0, 6.0, 3.2, 2.0, Color.WHITE, Color.RED), "Bay3D.house_mesh_small": Bay3D.house_mesh(5.0, 4.0, 2.6, 1.6, Color.WHITE, Color.RED)}
	# the bare triangle helper itself, on a known outward face (a roof slope facing up and north)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Props3D._tri(st, Vector3(-1, 0, -1), Vector3(1, 1, 0), Vector3(1, 0, -1)); Props3D._tri(st, Vector3(-1, 0, -1), Vector3(-1, 1, 0), Vector3(1, 1, 0))
	meshes["Props3D._tri"] = st.commit()
	for ax in [Vector3.UP, Vector3.RIGHT, Vector3(0.3, 0.2, -1.0)]:   # cylinders along several axes, capped
		var sc := SurfaceTool.new(); sc.begin(Mesh.PRIMITIVE_TRIANGLES); Props3D._cyl(sc, Vector3.ZERO, ax * 3.0, 0.5, 0.3, 10, Color.WHITE, true)
		meshes["Props3D._cyl %s" % ax] = sc.commit()
	var sb := SurfaceTool.new(); sb.begin(Mesh.PRIMITIVE_TRIANGLES); Props3D._box(sb, Vector3(1, 2, 3), Vector3(2, 1, 4), Color.WHITE)
	meshes["Props3D._box"] = sb.commit()
	# CC0 asset pass: every imported .glb under world3d/assets (houses, trees, props) front faces outward too
	var glbs: Array = []; _glb_files("res://world3d/assets", glbs); glbs.sort()
	for gp in glbs:
		var rel: String = (gp as String).trim_prefix("res://world3d/assets/").trim_suffix(".glb")
		var es := Assets3D.meshes(rel)
		if es.is_empty(): fails.append("%s: no meshes (not imported?)" % rel)
		for e in es: meshes["%s/%s" % [rel, e.name]] = e.mesh
	for tk in Assets3D.TREE_KINDS:   # the procedural dark cores added to each tree LOD
		for lod in 2: meshes["tree %s lod%d (with core)" % [tk, lod]] = Assets3D.tree_mesh(tk, lod)
	var total := 0
	for k in meshes: total += _check_mesh(k, meshes[k], fails)
	# the roof slopes of the province house must exist from outside: at least two up-facing front faces on each side of the ridge
	var a := (meshes["Props3D.house"] as Mesh).surface_get_arrays(0)
	var up_n := 0; var up_s := 0
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]; var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	for t in range(0, ix.size() - 2, 3):
		var p0 := vs[ix[t]]; var p1 := vs[ix[t + 1]]; var p2 := vs[ix[t + 2]]
		var g := -(p1 - p0).cross(p2 - p0)
		if g.y > 0.0 and (p0.y + p1.y + p2.y) / 3.0 > 1.05:
			if (p0.z + p1.z + p2.z) < 0.0: up_n += 1
			else: up_s += 1
	if up_n < 2 or up_s < 2: fails.append("Props3D.house: roof slopes north %d / south %d front faces (want 2 each)" % [up_n, up_s])
	for f in fails.slice(0, 20000): print("  FAIL ", f)
	if fails.is_empty(): print("MESH-WINDING-TRUTH OK meshes=%d triangles=%d" % [meshes.size(), total]); quit(0)
	else: print("MESH-WINDING-TRUTH FAILED %d faults" % fails.size()); quit(1)
