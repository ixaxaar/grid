class_name Kit3D
extends RefCounted
## Audit 1128c: shared site dressing for every 3D place: floodlight masts, street lamps, aviation lamps, chain-link fences, vans.
## Night lights register here; Look3D.grade() turns them up as the night comes, and a stage can switch a group off (a blackout:
## the estate's street lamps go dark with its windows). Real sizes in metres. Everything is cheap: emissive heads everywhere,
## real lights (spots and omnis, no shadows) only above the low tier.

static var _lights: Array = []    # {light: weakref, mat: weakref, e: float, em: float, group: String}
static var _off: Dictionary = {}  # group -> true when switched off
static var _nk := 0.0

static func _reg(light: Light3D, mat: StandardMaterial3D, e: float, em: float, group: String) -> void:
	_lights = _lights.filter(func(d): return (d.mat as WeakRef).get_ref() != null)
	_lights.append({"light": weakref(light) if light != null else null, "mat": weakref(mat), "e": e, "em": em, "group": group})
	_apply_one(_lights[_lights.size() - 1])

static func _apply_one(d: Dictionary) -> void:
	var on := 0.0 if _off.get(d.group, false) else smoothstep(0.05, 0.5, _nk)
	var m = (d.mat as WeakRef).get_ref()
	if m != null: (m as StandardMaterial3D).emission_energy_multiplier = d.em * on
	if d.light != null:
		var l = (d.light as WeakRef).get_ref()
		if l != null: (l as Light3D).light_energy = d.e * on; (l as Light3D).visible = on > 0.01

## Called by Look3D.grade with the night factor.
static func night(nk: float) -> void:
	_nk = nk
	for d in _lights: _apply_one(d)

static func set_group(group: String, on: bool) -> void:
	if bool(_off.get(group, false)) == (not on): return
	_off[group] = not on
	for d in _lights: if d.group == group: _apply_one(d)

static func reset() -> void:
	_lights.clear(); _off.clear()

static func _lamp_mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.9, 0.9, 0.85); m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.0
	m.roughness = 0.3; return m

static func _steel() -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.46, 0.48, 0.50); m.metallic = 0.6; m.roughness = 0.45; return m

static func _box(parent: Node3D, c: Vector3, s: Vector3, m: Material, nm := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = s; mi.mesh = bm; mi.material_override = m; mi.position = c
	if nm != "": mi.name = nm
	parent.add_child(mi); return mi

static func _cyl(parent: Node3D, a: Vector3, h: float, r: float, m: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = r * 0.8; cm.bottom_radius = r; cm.height = h; cm.radial_segments = 10
	mi.mesh = cm; mi.material_override = m; mi.position = a + Vector3(0, h * 0.5, 0); parent.add_child(mi); return mi

## A floodlight mast `h` m tall at `at` (ground level), its heads aimed at `aim` (a ground point). Sodium-white yard light.
static func flood_mast(parent: Node3D, at: Vector3, aim: Vector3, quality: String, h := 14.0, group := "site", energy := 55.0, real := false) -> Node3D:
	var n := Node3D.new(); n.name = "FloodMast"; n.position = at; parent.add_child(n)
	_cyl(n, Vector3.ZERO, h, 0.18, _steel())
	_box(n, Vector3(0, h, 0), Vector3(1.6, 0.12, 0.12), _steel())
	var dir := (aim - (at + Vector3(0, h, 0)))
	var yaw := atan2(dir.x, dir.z)
	var lm := _lamp_mat(Color(1.0, 0.88, 0.70))
	if real:   # CC0 pass: a Poly Haven floodlight head (glass emissive, registered) on the arm
		Assets3D.flood_head(n, Vector3(0, h - 0.1, 0.25), yaw, deg_to_rad(35.0), lm)
		Assets3D.flood_head(n, Vector3(0.7, h - 0.1, 0.25), yaw, deg_to_rad(35.0), lm)
		Assets3D.flood_head(n, Vector3(-0.7, h - 0.1, 0.25), yaw, deg_to_rad(35.0), lm)
	else:
		for sx in [0.0]:
			var head := Node3D.new(); head.position = Vector3(sx, h - 0.1, 0); head.rotation.y = yaw; n.add_child(head)
			_box(head, Vector3(0, 0, 0.1), Vector3(0.7, 0.5, 0.25), _steel())
			var face := _box(head, Vector3(0, -0.05, 0.24), Vector3(0.6, 0.4, 0.04), lm); face.rotation.x = deg_to_rad(-35.0)
			face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sp: SpotLight3D = null
	if quality != "low":
		sp = SpotLight3D.new(); sp.light_color = Color(1.0, 0.93, 0.84); sp.spot_range = h * 5.0; sp.spot_angle = 42.0; sp.spot_attenuation = 1.0
		sp.spot_angle_attenuation = 1.4; sp.shadow_enabled = false; sp.light_specular = 0.4
		n.add_child(sp); sp.position = Vector3(0, h - 0.3, 0)
		if dir.length() > 0.1: sp.look_at_from_position(sp.position, sp.position + dir.normalized(), Vector3.UP)
	_reg(sp, lm, energy, 3.0, group)   # Godot falls off as 1/d: 70 gives a lit yard 30-50 m out
	return n

## A street lamp `h` m tall at `at` with its arm toward `yaw` (radians); a warm pool on the ground below.
static func street_lamp(parent: Node3D, at: Vector3, yaw: float, quality: String, group := "town", h := 7.0) -> Node3D:
	var n := Node3D.new(); n.name = "StreetLamp"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	var st := _steel(); st.albedo_color = Color(0.22, 0.23, 0.24)
	_cyl(n, Vector3.ZERO, h, 0.09, st)
	_box(n, Vector3(0, h, 0.7), Vector3(0.08, 0.08, 1.4), st)
	var lm := _lamp_mat(Color(1.0, 0.74, 0.42))
	var head := _box(n, Vector3(0, h - 0.08, 1.35), Vector3(0.32, 0.1, 0.6), lm); head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var lt: OmniLight3D = null
	if quality != "low":
		lt = OmniLight3D.new(); lt.light_color = Color(1.0, 0.72, 0.42); lt.omni_range = h * 3.2; lt.omni_attenuation = 1.0; lt.shadow_enabled = false
		lt.position = Vector3(0, h - 0.5, 1.35); n.add_child(lt)
	_reg(lt, lm, 16.0, 6.0, group)
	return n

## A red aviation lamp on top of a mast or stack (slow blink is drawn by its emission only; no light).
static func aviation(parent: Node3D, at: Vector3) -> void:
	var m := _lamp_mat(Color(1.0, 0.08, 0.04))
	var mi := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.7; mi.mesh = sm; mi.material_override = m
	mi.position = at; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(mi)
	_reg(null, m, 0.0, 8.0, "aviation")

## A chain-link fence round `rect` (x, z), posts every 3 m, 2.4 m high, gaps in `gates` (centres on the edge, 6 m wide).
## `gy` gives the ground height at (x, z).
static func fence(parent: Node3D, rect: Rect2, gy: Callable, gates: Array = []) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := SurfaceTool.new(); post.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var hgt := 2.4
	var run := 0.0
	for e in 4:
		var a: Vector2 = c[e]; var b: Vector2 = c[(e + 1) % 4]
		var L := a.distance_to(b); var nseg := maxi(1, int(ceil(L / 3.0)))
		for k in nseg:
			var p0 := a.lerp(b, float(k) / nseg); var p1 := a.lerp(b, float(k + 1) / nseg)
			var mid := (p0 + p1) * 0.5
			var gap := false
			for g in gates: if (g as Vector2).distance_to(mid) < 3.0: gap = true
			var y0: float = gy.call(p0.x, p0.y); var y1: float = gy.call(p1.x, p1.y)
			Props3D._box(post, Vector3(p0.x, y0 + hgt * 0.5, p0.y), Vector3(0.08, hgt + 0.2, 0.08), Color(0.42, 0.44, 0.46))
			if gap: run += p0.distance_to(p1); continue
			var u0 := run; run += p0.distance_to(p1); var u1 := run
			var v := [Vector3(p0.x, y0 + 0.05, p0.y), Vector3(p1.x, y1 + 0.05, p1.y), Vector3(p1.x, y1 + hgt, p1.y), Vector3(p0.x, y0 + hgt, p0.y)]
			var uv := [Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, hgt), Vector2(u0, hgt)]
			var nn := Vector3(p1.y - p0.y, 0, p0.x - p1.x).normalized()
			st.set_normal(nn)
			for i in [0, 1, 2, 0, 2, 3]: st.set_uv(uv[i]); st.add_vertex(v[i])
	var fm := ShaderMaterial.new(); fm.shader = load("res://world3d/shaders/fence.gdshader")
	var mi := MeshInstance3D.new(); mi.name = "FenceMesh"; mi.mesh = st.commit(); mi.material_override = fm; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var pm := StandardMaterial3D.new(); pm.vertex_color_use_as_albedo = true; pm.metallic = 0.5; pm.roughness = 0.5
	var pi := MeshInstance3D.new(); pi.name = "FencePosts"; pi.mesh = post.commit(); pi.material_override = pm; parent.add_child(pi)

## A utility van (5.5 x 2.1 x 2.4 m) at `at`, heading `yaw`.
static func van(parent: Node3D, at: Vector3, yaw: float, col := Color(0.86, 0.86, 0.84)) -> Node3D:
	var n := Node3D.new(); n.name = "Van"; n.position = at; n.rotation.y = yaw; parent.add_child(n)
	var body := StandardMaterial3D.new(); body.albedo_color = col; body.metallic = 0.3; body.roughness = 0.35
	var glass := StandardMaterial3D.new(); glass.albedo_color = Color(0.08, 0.10, 0.12); glass.metallic = 0.6; glass.roughness = 0.1
	var tyre := StandardMaterial3D.new(); tyre.albedo_color = Color(0.05, 0.05, 0.05); tyre.roughness = 0.9
	_box(n, Vector3(0, 1.45, -0.5), Vector3(2.0, 1.9, 4.0), body)
	_box(n, Vector3(0, 1.1, 1.95), Vector3(2.0, 1.2, 1.1), body)
	var ws := _box(n, Vector3(0, 1.75, 1.7), Vector3(1.85, 0.6, 0.05), glass); ws.rotation.x = deg_to_rad(-25.0)
	_box(n, Vector3(0, 1.55, -0.5), Vector3(2.02, 0.12, 4.02), _lamp_mat_static(Color(1.0, 0.5, 0.05)))
	for sx in [-0.9, 0.9]:
		for sz in [-1.6, 1.6]:
			var w := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.38; cm.bottom_radius = 0.38; cm.height = 0.25
			w.mesh = cm; w.material_override = tyre; w.rotation.z = PI * 0.5; w.position = Vector3(sx, 0.38, sz); n.add_child(w)
	return n

static func _lamp_mat_static(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 0.5; return m

## A power transformer about `s` x the size of an 80 MVA unit (tank 6 x 3.2 x 4 m at s = 1): ribbed tank, two radiator banks of
## fins, three HV bushings with porcelain sheds, three LV bushings, a conservator on brackets, a plinth in a gravel oil pit.
static func power_transformer(parent: Node3D, at: Vector3, yaw: float, s := 1.0) -> Node3D:
	var n := Node3D.new(); n.name = "PowerTransformer"; n.position = at; n.rotation.y = yaw; n.scale = Vector3.ONE * s; parent.add_child(n)
	var tank := StandardMaterial3D.new(); tank.albedo_color = Color(0.36, 0.40, 0.38); tank.metallic = 0.45; tank.roughness = 0.5
	var fin := StandardMaterial3D.new(); fin.albedo_color = Color(0.33, 0.37, 0.35); fin.metallic = 0.4; fin.roughness = 0.55
	var porc := StandardMaterial3D.new(); porc.albedo_color = Color(0.42, 0.26, 0.18); porc.roughness = 0.25; porc.metallic = 0.0
	var conc := StandardMaterial3D.new(); conc.albedo_color = Color(0.52, 0.51, 0.48); conc.roughness = 0.9
	_box(n, Vector3(0, 0.2, 0), Vector3(9.0, 0.4, 7.0), conc, "Pit")
	_box(n, Vector3(0, 0.5, 0), Vector3(6.4, 0.3, 3.6), conc, "Plinth")
	_box(n, Vector3(0, 2.65, 0), Vector3(6.0, 4.0, 3.2), tank, "Tank")
	for k in 7: _box(n, Vector3(-2.7 + 0.9 * k, 2.65, 1.62), Vector3(0.12, 3.6, 0.08), tank)   # stiffener ribs
	for k in 7: _box(n, Vector3(-2.7 + 0.9 * k, 2.65, -1.62), Vector3(0.12, 3.6, 0.08), tank)
	_box(n, Vector3(0, 4.75, 0), Vector3(6.2, 0.2, 3.4), tank, "Cover")
	for side in [-1.0, 1.0]:   # radiator banks along the long sides
		for k in 12:
			_box(n, Vector3(-2.6 + 0.47 * k, 2.4, side * 2.35), Vector3(0.06, 3.0, 1.2), fin)
		_box(n, Vector3(0, 3.95, side * 2.0), Vector3(5.6, 0.18, 0.18), fin)
		_box(n, Vector3(0, 0.95, side * 2.0), Vector3(5.6, 0.18, 0.18), fin)
	for k in 3:   # HV bushings: a stack of sheds
		var bx := -1.6 + 1.6 * k
		for j in 9:
			var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.26; cm.bottom_radius = 0.26; cm.height = 0.12; cm.radial_segments = 12
			mi.mesh = cm; mi.material_override = porc; mi.position = Vector3(bx, 5.05 + 0.28 * j, -0.6); n.add_child(mi)
		_cyl(n, Vector3(bx, 4.85, -0.6), 2.8, 0.13, porc)
		_box(n, Vector3(bx, 7.75, -0.6), Vector3(0.3, 0.2, 0.3), _steel())
	for k in 3:   # LV bushings
		_cyl(n, Vector3(-1.2 + 1.2 * k, 4.85, 0.9), 1.0, 0.1, porc)
	var cons := MeshInstance3D.new(); var cc := CylinderMesh.new(); cc.top_radius = 0.55; cc.bottom_radius = 0.55; cc.height = 3.2; cc.radial_segments = 16
	cons.mesh = cc; cons.material_override = tank; cons.rotation.z = PI * 0.5; cons.position = Vector3(1.0, 6.3, 1.2); n.add_child(cons)
	for bx in [-0.3, 2.3]: _box(n, Vector3(bx, 5.55, 1.2), Vector3(0.15, 1.4, 0.15), tank)
	return n

## Dressing for a plain hall box (centre `c` at ground, size `sz`): a parapet, louvres, a door with a lamp over it, and lit
## windows along the front (+Z) that come on at night with the site group.
static func dress_hall(parent: Node3D, c: Vector3, sz: Vector3, group := "site") -> void:
	var trim := StandardMaterial3D.new(); trim.albedo_color = Color(0.30, 0.32, 0.34); trim.metallic = 0.5; trim.roughness = 0.45
	var hx := sz.x * 0.5; var hz := sz.z * 0.5
	_box(parent, c + Vector3(0, sz.y + 0.25, hz), Vector3(sz.x + 0.2, 0.5, 0.2), trim)
	_box(parent, c + Vector3(0, sz.y + 0.25, -hz), Vector3(sz.x + 0.2, 0.5, 0.2), trim)
	for sx in [-1.0, 1.0]: _box(parent, c + Vector3(sx * hx, sz.y + 0.25, 0), Vector3(0.2, 0.5, sz.z), trim)
	var win := _lamp_mat(Color(1.0, 0.86, 0.62)); win.albedo_color = Color(0.10, 0.12, 0.14); win.metallic = 0.5; win.roughness = 0.15
	var nwin := maxi(2, int(sz.x / 7.0))
	for k in nwin:
		var x := -hx + (float(k) + 0.5) * sz.x / float(nwin)
		_box(parent, c + Vector3(x, sz.y * 0.88, hz + 0.06), Vector3(2.4, 0.45, 0.06), win)   # a clerestory over the panels
	_reg(null, win, 0.0, 2.2, group)
	var door := StandardMaterial3D.new(); door.albedo_color = Color(0.18, 0.30, 0.42); door.roughness = 0.5; door.metallic = 0.3
	_box(parent, c + Vector3(sz.x * 0.5 + 0.05, 1.25, 0.0), Vector3(0.08, 2.5, 1.6), door)
	var lm := _lamp_mat(Color(1.0, 0.9, 0.7))
	_box(parent, c + Vector3(sz.x * 0.5 + 0.2, 2.85, 0.0), Vector3(0.3, 0.15, 0.5), lm)
	_reg(null, lm, 0.0, 6.0, group)
	for k in maxi(1, int(sz.x / 12.0)):   # louvres on the back
		_box(parent, c + Vector3(-hx + 4.0 + 12.0 * k, sz.y * 0.5, -hz - 0.05), Vector3(2.0, 1.6, 0.06), trim)

## 1128c (manager: "a huge grey slab fills the lower half of the frame"): the camera must not sit inside or right behind a big solid.
## A segment from a little way out from the target to the eye is tested against shadow-casting meshes taller than 4 m (triangles,
## so merged town meshes count) and against multimesh buildings within 60 m of the eye. While blocked the eye swings up 5 degrees
## about the target, at most 30 degrees over the player's pitch (a spring arm was tried: it pulled the eye into the plant).
## The player's goal camera is not changed, so the view returns once the way is clear.
static var _tri_cache := {}
static var _no_eye := OS.has_environment("CB_NOEYE")   # QA: time the scene without the guard
static var _mm_cache := {}
static func clear_eye(world: World3D, target: Vector3, eye: Vector3) -> Vector3:
	if world == null or _no_eye: return eye
	if target.distance_squared_to(_eye_in[0]) < 0.0025 and eye.distance_squared_to(_eye_in[1]) < 0.0025: return _eye_out   # the camera has not moved
	_eye_in = [target, eye]; _eye_out = _clear_eye(world, target, eye)
	return _eye_out

static var _eye_in := [Vector3.INF, Vector3.INF]
static var _eye_out := Vector3.ZERO
static var _mesh_seen := {}   # instance id -> [mesh id, changes]: meshes rebuilt every frame (live lines) are not buildings
static func _clear_eye(world: World3D, target: Vector3, eye: Vector3) -> Vector3:
	var e := eye
	for k in 6:
		if not _blocked(world, target, e): return e
		var d := e - target; var r := d.length()
		var h := Vector2(d.x, d.z); var hl := h.length()
		var p := atan2(d.y, hl) + deg_to_rad(5.0)
		if p > deg_to_rad(80.0): break
		var hd := h / maxf(hl, 0.001)
		e = target + Vector3(hd.x * cos(p), sin(p), hd.y * cos(p)) * r
	return e   # still blocked after 30 degrees: keep the highest view (coming in towards the target only went deeper into the plant)

static func _blocked(world: World3D, target: Vector3, eye: Vector3) -> bool:
	var d := eye - target; var r := d.length()
	if r < 0.5: return false
	var from := target + d / r * minf(12.0, 0.35 * r)   # the target's own building does not count
	var near := eye - d / r * minf(60.0, r * 0.65)
	for id in RenderingServer.instances_cull_ray(from, eye, world.scenario):
		var ob := instance_from_id(id)
		if ob is MultiMeshInstance3D:
			if _mm_hit(ob as MultiMeshInstance3D, near, eye): return true
			continue
		var gi := ob as MeshInstance3D
		if gi == null or gi.mesh == null or not gi.is_visible_in_tree() or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var bb := gi.global_transform * gi.get_aabb()
		if bb.size.y < 4.0 or bb.size.x * bb.size.z > 250000.0: continue
		var key := gi.mesh.get_instance_id()
		var seen: Array = _mesh_seen.get(id, [key, 0])
		if seen[0] != key: seen = [key, int(seen[1]) + 1]
		_mesh_seen[id] = seen
		if int(seen[1]) > 2: continue
		if not _tri_cache.has(key):
			if _tri_cache.size() > 400: _tri_cache.clear()
			_tri_cache[key] = gi.mesh.generate_triangle_mesh()
		var tm: TriangleMesh = _tri_cache[key]
		if tm == null: continue
		var inv := gi.global_transform.affine_inverse()
		if not tm.intersect_segment(inv * from, inv * eye).is_empty(): return true
		if bb.grow(0.5).has_point(eye):   # inside a closed building: straight up meets a face from behind
			var a := inv * eye; var b := inv * (eye + Vector3(0, bb.size.y + 2.0, 0))
			var hit := tm.intersect_segment(a, b)
			if not hit.is_empty() and (hit.normal as Vector3).dot(b - a) > 0.0: return true
			var walls := 0   # inside a hollow (a cooling tower, open at the top): walls all round
			var reach := minf(maxf(bb.size.x, bb.size.z), 160.0)
			for dv in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
				if not tm.intersect_segment(a, inv * (eye + dv * reach)).is_empty(): walls += 1
			if walls == 4: return true
	return false

const MM_CELL := 32.0
static func _mm_hit(mmi: MultiMeshInstance3D, a: Vector3, b: Vector3) -> bool:
	if mmi.multimesh == null or mmi.multimesh.mesh == null or not mmi.is_visible_in_tree() or mmi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: return false
	var mm := mmi.multimesh
	var key := mmi.get_instance_id()
	var g: Dictionary = _mm_cache.get(key, {})
	if g.get("n", -1) != mm.instance_count:   # one grid of building boxes per multimesh, built once
		g = {"n": mm.instance_count, "cells": {}}
		var ma := mm.mesh.get_aabb()
		for i in mm.instance_count:
			var bb := mmi.global_transform * mm.get_instance_transform(i) * ma
			if bb.size.y < 4.0: continue
			for cx in range(floori(bb.position.x / MM_CELL), floori(bb.end.x / MM_CELL) + 1):
				for cz in range(floori(bb.position.z / MM_CELL), floori(bb.end.z / MM_CELL) + 1):
					var ck := Vector2i(cx, cz)
					if not g.cells.has(ck): g.cells[ck] = []
					g.cells[ck].append(bb)
		_mm_cache[key] = g
	for cx in range(floori(minf(a.x, b.x) / MM_CELL), floori(maxf(a.x, b.x) / MM_CELL) + 1):
		for cz in range(floori(minf(a.z, b.z) / MM_CELL), floori(maxf(a.z, b.z) / MM_CELL) + 1):
			for bb in g.cells.get(Vector2i(cx, cz), []):
				if _seg_hits((bb as AABB).grow(0.5), a, b): return true
	return false

static func _seg_hits(bb: AABB, a: Vector3, b: Vector3) -> bool:
	var t0 := 0.0; var t1 := 1.0; var d := b - a
	for i in 3:
		if absf(d[i]) < 1e-6:
			if a[i] < bb.position[i] or a[i] > bb.end[i]: return false
		else:
			var u := (bb.position[i] - a[i]) / d[i]; var v := (bb.end[i] - a[i]) / d[i]
			t0 = maxf(t0, minf(u, v)); t1 = minf(t1, maxf(u, v))
			if t0 > t1: return false
	return true
