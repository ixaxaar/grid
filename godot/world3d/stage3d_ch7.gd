class_name Stage7
extends RefCounted
## Chapter 7's five jobs as 3D places for Stage3D (which keeps the land, sky, camera and the helpers; this file holds what is particular to L23 to L27 so
## stage3d.gd stays readable). Display only: every number is the engine's `ch7Study`, handed over by Stage3D.set_stage; the arithmetic maps numbers to light,
## colour, count and a replay clock.
## L23 the industrial 33 kV substation (132 kV incomer, two transformers, the board in two sections, coupler or reactor, two captive sets, feeder F1 to the
## estate). L24 a radial 11 kV feeder down a valley with four relay kiosks. L25 a generating unit, its breaker bay and the line with the fault on it. L26 the
## dispatch control room in front of six plants, the corridor and the city. L27 the L23 board with three dispatchable units.

const IDS := ["l23", "l24", "l25", "l26", "l27"]
const RELAY_COL := [Color("#39E1FF"), Color("#FFC56B"), Color("#5BD69A"), Color("#FF4FD8")]   # the TCC chart's relay colours (Ch7Feeder.COLS)
const PCOL := {"coalsub": Color("#8A7F6A"), "coalsc": Color("#E0703A"), "ccgt": Color("#39E1FF"), "ocgt": Color("#FF4FD8"), "hydro": Color("#4C7DFF"), "solar": Color("#FFE066")}
const PLANTS := ["coalsub", "coalsc", "ccgt", "ocgt"]
const FAULT_AT := {"F1": 0.8, "F2": 0.8, "F3": 0.1, "F4": 0.8, "F5": 0.1, "F6": 0.8}   # where along its section each scripted fault stands (src/sim/ch7/scenarios.json l24.faults.at)
const L24_X := [-130.0, -50.0, 10.0, 70.0, 130.0]   # the four substations and the far end, along the valley
const L25_FAULT_AT := 0.4                            # the fault stands this far along the line (scenarios.json l25.faultAtPctOfLine)
const KIOSKS := {"IN1": -40.0, "F1": -20.0, "BC": 0.0, "IN2": 40.0, "G1": -49.0, "G2": 49.0}
const CITY := Rect2(215.0, -12.0, 56.0, 50.0)

static func play(scn: String) -> Rect2:
	match scn:
		"l24": return Rect2(-170.0, -80.0, 340.0, 160.0)
		"l25": return Rect2(-50.0, -60.0, 330.0, 120.0)
		"l26": return Rect2(-170.0, -120.0, 470.0, 250.0)
	return Rect2(-110.0, -75.0, 220.0, 190.0)

static func _zc24(x: float) -> float: return 10.0 * sin(x / 70.0)

# --------------------------------------------------------------------------------------------------------------------
# Land
# --------------------------------------------------------------------------------------------------------------------
static func ground(s: Stage3D, x: float, z: float) -> float:
	var h := 0.6 + 1.8 * s._n01(x * 0.6, z * 0.6)
	match s.scn:
		"l24":
			var w := absf(z - _zc24(x))
			h = 2.0 + 2.0 * s._n01(x * 0.6, z * 0.6) + 20.0 * smoothstep(30.0, 150.0, w) * (0.6 + 0.4 * s._n01(x * 0.2, z * 0.2)) - 2.5 * (1.0 - smoothstep(4.0, 9.0, w))
			h += s._far(x, z)
		"l25":
			h += 22.0 * smoothstep(30.0, 120.0, -z) * (0.4 + 0.6 * s._n01(z, x)) + 10.0 * smoothstep(40.0, 150.0, z) * s._n01(x * 0.5, z) + s._far(x, z)
			h = lerpf(h, 1.0, s._pad(x, z, Rect2(-14.0, -12.0, 60.0, 28.0), 9.0))
			h = lerpf(h, 1.0, s._pad(x, z, Rect2(40.0, -10.0, 26.0, 20.0), 8.0))
		"l26":
			h += 16.0 * smoothstep(100.0, 190.0, -z) * (0.4 + 0.6 * s._n01(z, x)) + s._far(x, z)
			var r := Vector2(x - 100.0, z + 92.0).length()
			h += 14.0 * (1.0 - smoothstep(25.0, 50.0, r)) - 7.0 * (1.0 - smoothstep(0.0, 26.0, r))   # the hydro reservoir on its shelf
			h = lerpf(h, 0.6, s._pad(x, z, Rect2(-150.0, -75.0, 230.0, 150.0), 16.0))
			h = lerpf(h, 1.0, s._pad(x, z, CITY, 25.0))
		_:
			h += 18.0 * smoothstep(40.0, 160.0, -z) * (0.4 + 0.6 * s._n01(z, x)) + 8.0 * smoothstep(120.0, 260.0, z) * s._n01(x * 0.5, z) + s._far(x, z)
			h = lerpf(h, 0.5, s._pad(x, z, Rect2(-95.0, -50.0, 190.0, 140.0), 14.0))
	return h

static func splat(s: Stage3D, x: float, z: float, h: float) -> Array:
	var wood := smoothstep(0.05, 0.35, s._nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))
	var c := Color(1, 0, 0, 0); var paved := 0.0
	match s.scn:
		"l24":
			var w := absf(z - _zc24(x)); var f := maxf(wood * 0.6, smoothstep(20.0, 60.0, w)); var r := smoothstep(32.0, 50.0, h)
			c = Color(1.0 - f - r, f, r, 0.0)
		"l25":
			var f := maxf(wood * 0.5, smoothstep(30.0, 90.0, -z)); c = Color(1.0 - f, f, 0.0, 0.0)
			paved = maxf(s._pad(x, z, Rect2(-14.0, -12.0, 60.0, 28.0), 3.0), s._pad(x, z, Rect2(40.0, -10.0, 26.0, 20.0), 3.0))
		"l26":
			var f := maxf(wood * 0.6, smoothstep(90.0, 160.0, -z)); c = Color(1.0 - f, f, 0.0, 0.0)
			paved = s._pad(x, z, Rect2(-100.0, -22.0, 240.0, 8.0), 4.0) * 0.0 + maxf(s._pad(x, z, Rect2(-80.0, 44.0, 44.0, 24.0), 3.0), s._pad(x, z, Rect2(-150.0, -75.0, 230.0, 80.0), 2.0) * 0.45)
		_:
			var f := maxf(wood * 0.6, smoothstep(40.0, 110.0, -z)); c = Color(1.0 - f, f, 0.0, 0.0)
			paved = maxf(s._pad(x, z, Rect2(-95.0, -48.0, 190.0, 66.0), 3.0), s._pad(x, z, Rect2(-45.0, 14.0, 50.0, 80.0), 2.0) * 0.5)
	return [c, 0.0, paved]

static func tree_ok(s: Stage3D, x: float, z: float) -> float:
	var p := Vector2(x, z)
	match s.scn:
		"l24":
			var w := absf(z - _zc24(x))
			if w < 60.0 or absf(x) > 190.0: return 0.0
			if z > _zc24(x) + 50.0: return 0.0   # 1128c manager: the camera side stays clear (black pines blocked the report frame)
			return clampf(0.05 + 0.4 * smoothstep(60.0, 100.0, w) - 0.5 * smoothstep(36.0, 52.0, s.ground(x, z)), 0.0, 0.4)
		"l25":
			if Rect2(-20.0, -20.0, 300.0, 40.0).has_point(p): return 0.0
			return 0.5 if z < -22.0 else (0.0 if z > 30.0 else 0.08)   # 1128c manager: no foreground pines on the camera side
		"l26":
			if Rect2(-160.0, -80.0, 260.0, 160.0).has_point(p) or CITY.grow(14.0).has_point(p) or Rect2(100.0, -30.0, 120.0, 40.0).has_point(p) or Vector2(x - 100.0, z + 92.0).length() < 52.0: return 0.0
			return 0.45 if z < -86.0 else 0.12
		_:
			if Rect2(-100.0, -52.0, 200.0, 150.0).has_point(p): return 0.0
			return 0.5 if z < -56.0 else 0.15

static func camera(scn: String) -> Array:   # [target, yaw deg, pitch deg, dist m]
	match scn:
		"l24": return [Vector3(-22.0, 0.0, 2.0), -22.0, 27.0, 100.0]   # 1128c manager: the relays were specks; closer and higher   # 11-28 (Sigrid): the four relays were specks under the chart; closer, centred on them
		"l27": return [Vector3(0.0, 0.0, -24.0), 16.0, 25.0, 140.0]   # the three units come down from under the exam card
		"l25": return [Vector3(30.0, 0.0, 0.0), -34.0, 22.0, 100.0]   # 1128c manager: the generator, its bay and the line large
		"l26": return [Vector3(35.0, 0.0, -10.0), -6.0, 21.0, 300.0]
		"l23": return [Vector3(-12.0, 0.0, 57.0), 14.0, 38.0, 150.0]   # CC0 pass: the yard and the estate fill the frame, the houses clear of the tray
	return [Vector3(-6.0, 0.0, 26.0), 16.0, 31.0, 175.0]   # 1128c: higher, so the transformers show over the board, and back, so the lit estate is in the frame

# --------------------------------------------------------------------------------------------------------------------
# Small shared pieces
# --------------------------------------------------------------------------------------------------------------------
static func _flash(s: Stage3D, parent: Node3D, at: Vector3, r: float, nm: String) -> MeshInstance3D:
	var sm := SphereMesh.new(); sm.radius = r * 0.6; sm.height = r * 1.2; sm.radial_segments = 24; sm.rings = 12
	var am := ShaderMaterial.new(); am.shader = load("res://world3d/shaders/arc.gdshader"); am.set_shader_parameter("power", 0.0)
	var f := s._inst(parent, sm, am, nm, at, false); f.visible = false
	var lt := OmniLight3D.new(); lt.name = "ArcLight"; lt.light_color = Color(0.85, 0.80, 1.0); lt.light_energy = 18.0; lt.omni_range = r * 12.0; lt.omni_attenuation = 1.0
	lt.shadow_enabled = s.quality == "high"; f.add_child(lt)
	return f

## 1128c: a failed clearance burns: orange sparks and a smoke column under the arc (children of the flash: they show with it).
static func _fault_fx(s: Stage3D, f: Node3D) -> void:
	var sp := CPUParticles3D.new(); sp.name = "Sparks"; sp.amount = 60; sp.lifetime = 0.9; sp.explosiveness = 0.15
	sp.direction = Vector3(0, 1, 0); sp.spread = 70.0; sp.initial_velocity_min = 4.0; sp.initial_velocity_max = 9.0; sp.gravity = Vector3(0, -12, 0)
	var sm := SphereMesh.new(); sm.radius = 0.06; sm.height = 0.12; sm.radial_segments = 4; sm.rings = 2; sp.mesh = sm
	var spm := StandardMaterial3D.new(); spm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; spm.albedo_color = Color(1.0, 0.6, 0.2); spm.emission_enabled = true; spm.emission = Color(1.0, 0.55, 0.15); spm.emission_energy_multiplier = 6.0
	sp.material_override = spm; f.add_child(sp)
	var sk := CPUParticles3D.new(); sk.name = "Smoke"; sk.amount = 40; sk.lifetime = 7.0; sk.preprocess = 7.0
	sk.direction = Vector3(0.2, 1, 0); sk.spread = 12.0; sk.initial_velocity_min = 1.5; sk.initial_velocity_max = 2.5; sk.gravity = Vector3(0.4, 0.3, 0)
	sk.scale_amount_min = 2.0; sk.scale_amount_max = 4.0
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.4)); cv.add_point(Vector2(1, 2.2)); sk.scale_amount_curve = cv
	var km := SphereMesh.new(); km.radius = 1.0; km.height = 2.0; km.radial_segments = 8; km.rings = 4; sk.mesh = km
	var kmat := StandardMaterial3D.new(); kmat.albedo_color = Color(0.07, 0.07, 0.08, 0.5); kmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; kmat.roughness = 1.0
	kmat.emission_enabled = true; kmat.emission = Color(0.9, 0.35, 0.1); kmat.emission_energy_multiplier = 0.03   # the fire under it lights its base
	sk.material_override = kmat; sk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; f.add_child(sk)
	var em := Node3D.new(); em.name = "Ember"; f.add_child(em)   # the fire inside the smoke: a glowing core and its light on the cabinets round it
	var emm := StandardMaterial3D.new(); emm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; emm.albedo_color = Color(1.0, 0.45, 0.1); emm.emission_enabled = true; emm.emission = Color(1.0, 0.4, 0.08); emm.emission_energy_multiplier = 5.0
	var es := SphereMesh.new(); es.radius = 0.9; es.height = 1.8; es.radial_segments = 8; es.rings = 4
	var emi := MeshInstance3D.new(); emi.mesh = es; emi.material_override = emm; emi.position = Vector3(0, -0.6, 0); emi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; em.add_child(emi)
	if s.quality != "low":
		var el := OmniLight3D.new(); el.light_color = Color(1.0, 0.5, 0.18); el.light_energy = 12.0; el.omni_range = 16.0; el.omni_attenuation = 1.0; el.shadow_enabled = false; el.position = Vector3(0, -0.4, 0); em.add_child(el)

static func _plume(s: Stage3D, parent: Node3D, at: Vector3, r: float, nm: String) -> MeshInstance3D:
	var sm := SphereMesh.new(); sm.radius = r; sm.height = r * 2.0; sm.radial_segments = 14; sm.rings = 8
	return s._inst(parent, sm, s._glow_mat(Color(0.86, 0.9, 0.95, 0.5), 0.0), nm, at, false)

static func _stack(s: Stage3D, parent: Node3D, at: Vector3, h: float, r: float, col: Color) -> void:
	s._inst(parent, s._cyl_mesh(Vector3.ZERO, Vector3(0, h, 0), r, col, 12), s._vc_mat(0.7), "Stack", at)

static func _gy(s: Stage3D, x: float, z: float) -> float: return s.ground(x, z)

## A breaker cabinet with a lamp and a smoke puff: the lamp says unrun (amber), within its duty (green) or over it (red with smoke).
static func _kiosk(s: Stage3D, id: String, at: Vector3) -> Dictionary:
	var n := Node3D.new(); n.name = "Breaker_" + id; n.position = at; s._root.add_child(n)
	s._box(n, Vector3(0, 1.4, 0), Vector3(2.4, 2.8, 1.5), s._mat(Color(0.55, 0.58, 0.62), 0.5, 0.3), "Cabinet")
	s._box(n, Vector3(0, 1.5, 0.78), Vector3(1.8, 1.9, 0.06), s._mat(Color(0.28, 0.3, 0.33), 0.5, 0.3), "Door")
	var lamp := s._emit_mat(Color(1.0, 0.7, 0.1), 2.5)
	var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44
	s._inst(n, sm, lamp, "Lamp", Vector3(0, 3.1, 0.2), false)
	var puff := MeshInstance3D.new(); var ps := SphereMesh.new(); ps.radius = 1.5; ps.height = 3.0; puff.mesh = ps
	var pm := StandardMaterial3D.new(); pm.albedo_color = Color(0.1, 0.1, 0.1, 0.7); pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material_override = pm; puff.position = Vector3(0, 5.0, 0); puff.visible = false; puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(puff)
	return {"node": n, "lamp": lamp, "puff": puff, "over": false}

static func _set_kiosk(k: Dictionary, revealed: bool, over: bool) -> void:
	var lamp: StandardMaterial3D = k.lamp
	lamp.emission = Color(1.0, 0.18, 0.1) if over else Color(0.3, 1.0, 0.45) if revealed else Color(1.0, 0.7, 0.1)
	lamp.emission_energy_multiplier = 4.0 if over else 2.5
	(k.puff as MeshInstance3D).visible = over; k["over"] = over

static func _patt(p: Node3D, key: String) -> Vector3: return p.position + (Stage3D.L10_ATT[key] as Vector3)

static func _wires3(s: Stage3D, pts: Array, r: float, mat: Material, nm: String) -> void:
	for c in 3: s._inst(s._root, s._run(pts[c], r, 0.8), mat, "%s%d" % [nm, c], Vector3.ZERO, false)

## The city of L26 / L12's kind: blocks with windows that one material lights.
static func _city(s: Stage3D, rc: Rect2, seed_: int) -> StandardMaterial3D:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var win := SurfaceTool.new(); win.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 16:
		var u := WorldMath.hash2(k, 1, seed_); var v := WorldMath.hash2(k, 2, seed_); var hh := 8.0 + 26.0 * pow(WorldMath.hash2(k, 3, seed_), 2.0)
		var cx := rc.position.x + 5.0 + u * (rc.size.x - 10.0); var cz := rc.position.y + 5.0 + v * (rc.size.y - 10.0)
		var w := 6.0 + 6.0 * WorldMath.hash2(k, 4, seed_); var d := 6.0 + 6.0 * WorldMath.hash2(k, 5, seed_)
		var y0 := s.ground(cx, cz) - 0.5; var tone := 0.30 + 0.12 * WorldMath.hash2(k, 6, seed_)
		Props3D._box(st, Vector3(cx, y0 + hh * 0.5, cz), Vector3(w, hh, d), Color(tone, tone + 0.02, tone + 0.06))
		for rr in int(hh / 3.5):
			for cc in int(d / 2.6):
				if WorldMath.hash2(k * 100 + rr, cc, seed_ + 1) < 0.25: continue
				var o := Vector3(cx - w * 0.5 - 0.05, y0 + 2.5 + 3.5 * float(rr), cz - d * 0.5 + 1.3 + 2.6 * float(cc))
				var pp := [o, o + Vector3(0, 0, 1.2), o + Vector3(0, 1.8, 1.2), o + Vector3(0, 1.8, 0)]
				win.set_normal(Vector3.LEFT)
				for t in [0, 2, 1, 0, 3, 2]: win.add_vertex(pp[t])   # 1128c: front faces out (-X)
	s._inst(s._root, st.commit(), s._vc_mat(0.8), "CityBlocks")
	var m := s._emit_mat(Color(1.0, 0.82, 0.5), 3.5); m.cull_mode = BaseMaterial3D.CULL_DISABLED
	s._inst(s._root, win.commit(), m, "CityWindows", Vector3.ZERO, false)
	return m

# --------------------------------------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------------------------------------
static func build(s: Stage3D) -> void:
	s.d7 = {}
	s._water(-1.5, Rect2(-Bench3D.FAR_M, -Bench3D.FAR_M, Bench3D.FAR_M * 2.0, Bench3D.FAR_M * 2.0), Vector2(0.0, 0.05))
	match s.scn:
		"l23", "l27": _build_board(s)
		"l24": _build_l24(s)
		"l25": _build_l25(s)
		"l26": _build_l26(s)
	s.real_trees = s.scn == "l23"   # CC0 asset pass benchmark (WO-23)
	s._trees(func(x: float, z: float) -> float: return Stage7.tree_ok(s, x, z), 320.0, 8.0)
	if s.scn in ["l24", "l25", "l26"]: _site_lights(s)

## 1128c (audit sweep: the night subjects of WO-24 to WO-26 were specks on a dark hill): a floodlight mast beside each named
## piece of equipment, aimed at it, so the subject is lit at night and the far woods are not.
const SITE_LIT := ["R1", "R2", "R3", "R4", "gen", "breaker", "hydro", "solar", "control"]
static func _site_lights(s: Stage3D) -> void:
	var keys: Array = SITE_LIT.duplicate()
	if s.d7.has("plants"): for id in s.d7.plants: if not keys.has(id): keys.append(id)
	for k in keys:
		if not s.anchors.has(k): continue
		var a: Vector3 = s.anchors[k]
		var m := Vector3(a.x + 7.0, 0.0, a.z + 7.0); m.y = s.ground(m.x, m.z)
		Kit3D.flood_mast(s._root, m, Vector3(a.x, s.ground(a.x, a.z), a.z), s.quality, 11.0, "site", 9.0 if s.scn == "l26" else 16.0)

static func _build_board(s: Stage3D) -> void:
	var d: Dictionary = s.d7
	var steel := s._mat(Color(0.62, 0.66, 0.70), 0.6, 0.2); var cu := s._mat(Color(0.80, 0.45, 0.25), 0.35, 0.5); var dark := s._mat(Color(0.28, 0.3, 0.33), 0.5, 0.3)
	var hv := s._mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	# the 132 kV incomer: a lattice tower, a gantry bus on two portals, a drop to each transformer
	var sp: Array = Props3D.support("lattice", 24.0, 21.0)
	var tw := s._inst(s._root, sp[0], s._vc_mat(0.6), "IncomerTower", Vector3(-100.0, s.ground(-100.0, -38.0) - 0.3, -38.0))
	var bus: Array = [[], [], []]
	for c in 3: bus[c].append(tw.position + (sp[1][c] as Vector3))
	for px in [-44.0, 44.0]:
		for pz in [-41.0, -31.0]: s._box(s._root, Vector3(px, 7.0, pz), Vector3(0.5, 14.0, 0.5), dark, "Portal")
		s._box(s._root, Vector3(px, 14.0, -36.0), Vector3(0.5, 0.5, 10.4), dark, "PortalBeam")
	for c in 3:
		bus[c].append(Vector3(-44.0, 13.6, -39.0 + 3.0 * c)); bus[c].append(Vector3(44.0, 13.6, -39.0 + 3.0 * c))
	_wires3(s, bus, 0.09, hv, "Hv")
	d["tx"] = []
	for i in 2:
		var tx := -28.0 if i == 0 else 28.0
		var n := Node3D.new(); n.name = "Transformer%d" % (i + 1); n.position = Vector3(tx, s.ground(tx, -20.0), -20.0); s._root.add_child(n)
		s._box(n, Vector3(0, 0.1, 0), Vector3(10.0, 0.3, 9.0), s._soft_mat("concrete" if s.scn == "l23" else "sand", Color(0.60, 0.60, 0.58) if s.scn == "l23" else Color(0.52, 0.50, 0.46), 0.3, 0.3 if s.scn != "l23" else 0.25, 0.0, 0.2))
		Kit3D.power_transformer(n, Vector3(0, 0.2, 0), 0.0, 1.0)   # 1128c: a ribbed tank with radiators, bushings and a conservator (was a toy box)
		for c in 3: s._inst(s._root, s._run([Vector3(tx - 0.0, 13.6, -39.0 + 3.0 * c), n.position + Vector3(-1.6 + 1.6 * c, 7.95, -0.6)], 0.07, 0.4), hv, "Drop%d_%d" % [i, c], Vector3.ZERO, false)
		s._box(n, Vector3(-2.4, 2.6, 0.5), Vector3(0.7, 5.0, 0.7), cu, "LvBus")   # the secondary leads down to the board
		s._box(s._root, Vector3(tx - 2.4, 2.2, -10.0), Vector3(0.7, 0.7, 12.0), cu, "LvDuct%d" % i)
		d.tx.append(n)
	# the 33 kV board: two sections of switchgear panels
	for i in 2:
		var bx := -30.0 if i == 0 else 30.0
		s._box(s._root, Vector3(bx, 2.6, 0.0), Vector3(42.0, 5.2, 8.0), s._clad_mat(Color(0.56, 0.58, 0.58), 0.5, 3.0), "Section" + ("A" if i == 0 else "B"))   # 11-28b: cladding, not a mirror-steel box
		for k in 14: s._box(s._root, Vector3(bx - 19.5 + 3.0 * k, 2.4, 4.05), Vector3(2.4, 3.6, 0.1), dark, "Panel")
		s._box(s._root, Vector3(bx, 5.4, 0.0), Vector3(40.0, 0.3, 7.0), s._mat(Color(0.4, 0.42, 0.45), 0.6, 0.3), "Roof")
		Kit3D.dress_hall(s._root, Vector3(bx, 0.0, 0.0), Vector3(42.0, 5.2, 8.0))
	d["coupler"] = Node3D.new(); (d.coupler as Node3D).name = "Coupler"; s._root.add_child(d.coupler); (d.coupler as Node3D).position = Vector3(0.0, 0.0, 0.0)
	d["ckey"] = ""
	# the breakers' cabinets along the board's front
	d["kiosk"] = {}
	for id in KIOSKS: d.kiosk[id] = _kiosk(s, id, Vector3(float(KIOSKS[id]), s.ground(float(KIOSKS[id]), 5.6), 5.6))
	# the two captive sets west and east, each a small hall with a generator and an exhaust stack
	for i in 2:
		var gx := -72.0 if i == 0 else 72.0
		var hall := s._hall(Vector3(gx, s.ground(gx, 0.0), 0.0), Vector3(14.0, 6.0, 10.0), "CaptiveSet%d" % (i + 1), Color(0.60, 0.58, 0.54))
		var gm := CylinderMesh.new(); gm.top_radius = 1.4; gm.bottom_radius = 1.4; gm.height = 5.0
		var gen := s._inst(hall, gm, s._mat(Color(0.2, 0.42, 0.34), 0.4, 0.3), "Generator", Vector3(0, 1.9, -0.5)); gen.rotation.z = PI * 0.5
		s._box(hall, Vector3(-3.2 * (1.0 if i == 0 else -1.0), 1.0, -0.5), Vector3(2.0, 1.8, 2.0), dark, "Engine")
		_stack(s, hall, Vector3(0, 6.0, -3.0), 5.0, 0.4, Color(0.3, 0.3, 0.32))
		s._box(s._root, Vector3(gx + (7.0 if i == 0 else -7.0) * 0.0 + (11.0 if i == 0 else -11.0), 2.6, 0.0), Vector3(8.0, 0.7, 0.7), cu, "SetDuct%d" % i)
	# feeder F1: overhead from its breaker down the road to the estate
	var poles: Array = []
	for k in 4: poles.append(s._pole10(-20.0, 16.0 + 18.0 * k, "FeederPole%d" % (k + 1), false))
	var pts: Array = [[], [], []]
	for c in 3:
		pts[c].append(Vector3(-20.0 + (c - 1) * 0.6, s.ground(-20.0, 5.6) + 3.2, 5.6))
		for p in poles: pts[c].append(_patt(p, ["a", "b", "c"][c]))
	_wires3(s, pts, 0.05, hv, "Feeder")
	d["fault_at"] = Vector3(-20.0, s.ground(-20.0, 11.0) + 1.5, 11.0)
	d["flash"] = _flash(s, s._root, d.fault_at, 3.0, "FaultFlash")
	_fault_fx(s, d.flash as Node3D)
	# the estate: sheds in two rows, their windows lit by one material
	var win := StandardMaterial3D.new(); win.albedo_color = Color(0.13, 0.17, 0.25); win.metallic = 0.3; win.roughness = 0.2; win.cull_mode = BaseMaterial3D.CULL_DISABLED; win.emission_enabled = true; win.emission = Color(1.0, 0.70, 0.36) if s.scn == "l23" else Bench3D.WARM; win.emission_energy_multiplier = 0.0
	d["estate"] = win
	var body := s._vc_mat(0.9); d["estate_body"] = body   # 1128c: one material for the estate walls, darkened in a blackout
	var real := s.scn == "l23"   # CC0 asset pass: Kenney suburban houses with PBR walls and roofs; the lit/dark contract is unchanged
	var hm: Dictionary = Assets3D.house_mats(win) if real else {}
	d["estate_mats"] = hm
	for k in 6:
		var ex := -34.0 + 14.0 * float(k % 3); var ez := 74.0 + 18.0 * float(k / 3)
		if real:
			var hn := Assets3D.house(s._root, k, Vector3(ex, s.ground(ex, ez) - 0.1, ez), PI if k < 3 else 0.0, hm, s.quality)
			hn.name = "Shed%d" % k
			continue
		var w := 11.0; var dd := 8.0; var h := 4.5
		var n := Node3D.new(); n.name = "Shed%d" % k; n.position = Vector3(ex, s.ground(ex, ez) - 0.1, ez); n.rotation.y = PI if k < 3 else 0.0; s._root.add_child(n)
		s._inst(n, Bay3D.house_mesh(w, dd, h, 2.0, Color(0.56, 0.53, 0.48), Color(0.30, 0.31, 0.34)), body, "Body")
		s._inst(n, Bay3D.windows_mesh(w, dd, h), win, "Windows", Vector3.ZERO, false)
	d["flash_t"] = 0.0
	# L27: three dispatchable units behind the transformers, a stack and a steam puff each
	d["units"] = []
	if s.scn == "l27":
		for k in 3:
			var ux := -45.0 + 45.0 * float(k)
			var hall := s._hall(Vector3(ux, s.ground(ux, -62.0), -62.0), Vector3(14.0, 7.0, 11.0), "Unit%d" % (k + 1), Color(0.60, 0.58, 0.54))
			var gm := CylinderMesh.new(); gm.top_radius = 1.5; gm.bottom_radius = 1.5; gm.height = 7.0
			var gen := s._inst(hall, gm, s._mat(Color(0.2, 0.34, 0.5), 0.4, 0.3), "Generator", Vector3(0, 2.0, 0)); gen.rotation.z = PI * 0.5
			_stack(s, hall, Vector3(4.0, 7.0, -2.0), 12.0, 0.7, Color(0.34, 0.34, 0.36))
			var pl := _plume(s, hall, Vector3(4.0, 21.0, -2.0), 3.0, "Steam"); d.units.append({"plume": pl, "share": 0.0})
	# 1128c: site dressing: the yard fence with a gate on the road, floodlight masts, the tower's aviation lamp, street lamps down
	# the estate road (they go dark with the estate), two crew vans
	var gyf := func(x: float, z: float) -> float: return s.ground(x, z)
	Kit3D.fence(s._root, Rect2(-92.0, -46.0, 184.0, 60.0), gyf, [Vector2(-20.0, 14.0)])
	for mp in [Vector2(-90.0, -44.0), Vector2(90.0, -44.0), Vector2(-90.0, 12.0), Vector2(90.0, 12.0), Vector2(0.0, -44.0)]:
		Kit3D.flood_mast(s._root, Vector3(mp.x, s.ground(mp.x, mp.y), mp.y), Vector3(mp.x * 0.55, 0.0, mp.y * 0.4 - 12.0), s.quality, 16.0, "site", 55.0, s.scn == "l23")
	Kit3D.aviation(s._root, tw.position + Vector3(0, 24.6, 0), s.quality)
	for k in 6:
		var lz := 22.0 + 14.0 * float(k); var lx := -26.0 if k % 2 == 0 else -14.0
		var lyaw := PI * 0.5 if k % 2 == 0 else -PI * 0.5
		if s.scn == "l23": Assets3D.street_lamp(s._root, Vector3(lx, s.ground(lx, lz) - 0.1, lz), lyaw, s.quality, "estate")
		else: Kit3D.street_lamp(s._root, Vector3(lx, s.ground(lx, lz) - 0.1, lz), lyaw, s.quality, "estate")
	Kit3D.van(s._root, Vector3(-8.0, s.ground(-8.0, 9.0), 9.0), 0.3)
	Kit3D.van(s._root, Vector3(52.0, s.ground(52.0, 10.0), 10.0), -1.4, Color(0.92, 0.55, 0.12))
	if s.scn == "l23": _dress_l23(s)
	s.anchors["incomer"] = tw.position + Vector3(0, 26.0, 0)
	s.anchors["xfmr"] = (d.tx[0] as Node3D).position + Vector3(0, 11.0, 0)
	s.anchors["board"] = Vector3(-30.0, 8.5, 0.0)
	s.anchors["coupler"] = Vector3(0.0, 8.0, 0.0)
	s.anchors["gens"] = Vector3(-72.0, 10.0, 0.0)
	s.anchors["feeder"] = Vector3(-20.0, 7.0, 5.6)
	s.anchors["estate"] = Vector3(-20.0, 11.0, 82.0)
	if s.scn == "l27": s.anchors["units"] = Vector3(0.0, 24.0, -62.0)

## CC0 pass (WO-23): the estate's asphalt street, utility boxes and security lights round the switchgear, a covered car by the houses.
static func _dress_l23(s: Stage3D) -> void:
	var rd := Assets3D.pbr("asphalt", Color(0.62, 0.62, 0.64), 1.0); rd.uv1_triplanar = true; rd.uv1_world_triplanar = true; rd.uv1_scale = Vector3.ONE * 0.25
	rd.texture_repeat = true; rd.vertex_color_use_as_albedo = true; rd.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# the feeder road runs from inside the yard gate to the forecourt, the estate street across the houses; both fade out at their ends into gravel and grass
	for seg in [[Vector2(-20.0, 2.0), Vector2(-20.0, 68.0), 6.0, 12.0], [Vector2(-48.0, 83.0), Vector2(8.0, 83.0), 6.0, 10.0]]:
		var a: Vector2 = seg[0]; var b: Vector2 = seg[1]; var hw: float = float(seg[2]) * 0.5; var fade: float = seg[3]
		var dir := (b - a).normalized(); var nr := Vector2(-dir.y, dir.x)
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var L := a.distance_to(b); var nseg := int(L / 3.0)
		for i in nseg:
			var u0 := L * float(i) / nseg; var u1 := L * float(i + 1) / nseg
			var al0 := minf(smoothstep(0.0, fade, u0), smoothstep(0.0, fade, L - u0)); var al1 := minf(smoothstep(0.0, fade, u1), smoothstep(0.0, fade, L - u1))
			var p0 := a + dir * u0; var p1 := a + dir * u1
			var q := [p0 + nr * hw, p0 - nr * hw, p1 - nr * hw, p1 + nr * hw]; var al := [al0, al0, al1, al1]
			var v: Array = []
			for pt in q: v.append(Vector3(pt.x, s.ground(pt.x, pt.y) + 0.06, pt.y))
			st.set_normal(Vector3.UP)
			for k in [0, 1, 2, 0, 2, 3]: st.set_color(Color(1, 1, 1, al[k])); st.add_vertex(v[k])
		s._inst(s._root, st.commit(), rd, "Street", Vector3.ZERO, false)
	# people under the estate lamps, a car with its headlights on, the car cover by the houses
	for pr in [["char_a", Vector2(-23.6, 50.8), 2.4], ["char_e", Vector2(-24.6, 49.6), 0.6], ["char_h", Vector2(-16.2, 63.4), -2.2], ["char_a", Vector2(-15.2, 36.6), 1.0]]:
		var pp: Vector2 = pr[1]; Assets3D.person(s._root, pr[0], Vector3(pp.x, s.ground(pp.x, pp.y), pp.y), pr[2])
	Assets3D.car(s._root, Vector3(-21.4, s.ground(-21.4, 30.0) + 0.06, 30.0), 0.0, s.quality)
	# the captive-set halls: a lit window on each (the control building's)
	for hx in [-72.0, 72.0]:
		var wm := Kit3D._lamp_mat(Color(1.0, 0.82, 0.55)); wm.albedo_color = Color(0.1, 0.1, 0.1)
		var wb := s._box(s._root, Vector3(hx, s.ground(hx, 0.0) + 3.3, 5.06), Vector3(4.4, 1.3, 0.06), wm, "ControlWindow"); wb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Kit3D._reg(null, wm, 0.0, 4.0, "site")
	for k in 4:   # utility boxes behind the switchgear sections and by the gate
		var p := [Vector2(-52.0, -5.0), Vector2(-8.0, -5.0), Vector2(8.0, -5.0), Vector2(52.0, -5.0)][k] as Vector2
		Assets3D.prop(s._root, "utility_box_01", Vector3(p.x, s.ground(p.x, p.y), p.y), 0.0, 1.6)
	for sx: float in [-1.0, 1.0]:   # a security light on the end wall of each section
		var x := 30.0 * sx + 21.4 * sx; var lm := Kit3D._lamp_mat(Color(1.0, 0.9, 0.7))
		var n := Assets3D.prop(s._root, "security_light", Vector3(x, 3.9, 0.0), PI * 0.5 * sx, 2.2, false)
		Kit3D._reg(null, lm, 0.0, 6.0, "site")
		for e in Assets3D.meshes("props/security_light"):
			for mi in n.get_children():
				for si in (e.mesh as Mesh).get_surface_count():
					if Assets3D.mat_name(e.mesh, si).ends_with("_bulb") or Assets3D.mat_name(e.mesh, si).ends_with("_glass"): (mi as MeshInstance3D).set_surface_override_material(si, lm)
	Assets3D.prop_matte(s._root, "covered_car", Vector3(-3.0, s.ground(-3.0, 62.0), 62.0), 0.4, 1.0)

## The coupler between the sections: a closed bus duct, a reactor coil when there is one, or an open gap.
static func _coupler_set(s: Stage3D, open: bool, reactor: float) -> void:
	var d: Dictionary = s.d7
	var key := "%s|%.2f" % [str(open), reactor]
	if key == str(d.ckey): return
	d["ckey"] = key
	var cn: Node3D = d.coupler; s._clear(cn)
	var cu := s._mat(Color(0.80, 0.45, 0.25), 0.35, 0.5)
	if open:
		s._box(cn, Vector3(-6.0, 5.9, 0.0), Vector3(6.0, 0.8, 0.8), cu, "DuctA"); s._box(cn, Vector3(6.0, 5.9, 0.0), Vector3(6.0, 0.8, 0.8), cu, "DuctB")
		s._box(cn, Vector3(0.0, 5.9, 0.0), Vector3(0.3, 2.4, 1.2), s._emit_mat(Color(1.0, 0.7, 0.1), 2.0), "OpenMark")
	elif reactor > 0.0:
		s._box(cn, Vector3(-6.0, 5.9, 0.0), Vector3(6.0, 0.8, 0.8), cu, "DuctA"); s._box(cn, Vector3(6.0, 5.9, 0.0), Vector3(6.0, 0.8, 0.8), cu, "DuctB")
		var rings := 2 + int(roundf(reactor * 20.0))
		var cm := CylinderMesh.new(); cm.top_radius = 1.9; cm.bottom_radius = 1.9; cm.height = 0.34
		for k in rings:
			var rg := s._inst(cn, cm, cu, "Coil", Vector3(0.0, 6.9 + 0.5 * float(k) - 0.25 * float(rings) * 0.0, 0.0)); rg.name = "Coil%d" % k
		s._box(cn, Vector3(0.0, 6.9 + 0.25 * float(rings), 0.0), Vector3(0.5, 0.5 * float(rings) + 0.8, 0.5), s._mat(Color(0.45, 0.47, 0.5), 0.5, 0.4), "Core")
	else:
		s._box(cn, Vector3(0.0, 5.9, 0.0), Vector3(18.0, 0.8, 0.8), cu, "Duct")

static func _build_l24(s: Stage3D) -> void:
	var d: Dictionary = s.d7
	var steel := s._mat(Color(0.55, 0.58, 0.62), 0.5, 0.3); var fence := s._mat(Color(0.55, 0.56, 0.58), 0.5, 0.3)
	var mats: Array = []
	for k in 4:
		var m := s._mat(Color(0.62, 0.62, 0.64), 0.35, 0.5); m.emission_enabled = true; m.emission = Color(1.0, 0.3, 0.1); m.emission_energy_multiplier = 0.0; mats.append(m)
	d["cond"] = mats
	# the poles along the valley, every ~16 m; the four sections' conductors (a, b, c)
	d["poles"] = []
	var xs: Array = []
	var x := L24_X[0]
	while x <= L24_X[4] + 0.1: xs.append(x); x += 16.0
	var pl: Array = []
	for px in xs: pl.append(s._pole10(px, _zc24(px), "Pole", false))
	d["pole_nodes"] = pl
	d["sec_mesh"] = []
	d["fault_pos"] = {}
	d["kiosk"] = []
	for k in 4:
		var x0: float = L24_X[k]; var x1: float = L24_X[k + 1]
		var segs: Array = [[], [], []]
		for pi in pl.size():
			var p := pl[pi] as Node3D
			if p.position.x >= x0 - 0.1 and p.position.x <= x1 + 0.1:
				for c in 3: segs[c].append(_patt(p, ["a", "b", "c"][c]))
		var node := Node3D.new(); node.name = "Section%d" % (k + 1); s._root.add_child(node)
		var mm2 := float(((s.q.limits as Array)[k] as Dictionary).mm2)   # a thicker conductor for the bigger section
		for c in 3: s._inst(node, s._run(segs[c], 0.025 + 0.0006 * mm2, 0.5), mats[k], "Cond%d" % c, Vector3.ZERO, false)
		d.sec_mesh.append(node)
		# the substation at the head of the section: a fenced pad, a breaker and a relay kiosk in the relay's colour
		var gy := s.ground(x0, _zc24(x0) + 10.0)
		var kn := Node3D.new(); kn.name = "Substation%d" % (k + 1); kn.position = Vector3(x0, gy, _zc24(x0) + 10.0); s._root.add_child(kn)
		s._box(kn, Vector3(0, 0.1, 0), Vector3(10.0, 0.25, 7.0), s._soft_mat("sand", Color(0.50, 0.49, 0.46), 0.3, 0.3, 0.0, 0.2))
		for fx in [-5.0, 5.0]: for fz in [-3.5, 3.5]: s._box(kn, Vector3(fx, 1.0, fz), Vector3(0.1, 2.0, 0.1), fence)
		var br := s._inst(kn, Props3D.breaker(), s._vc_mat(0.55), "Breaker", Vector3(-2.0, 0.0, 0.0))
		var blade := s._box(kn, Vector3(-2.0, 4.6, 0.0), Vector3(1.6, 0.18, 0.18), s._mat(Color(0.8, 0.82, 0.85), 0.35, 0.5), "Blade")
		var rk := Node3D.new(); rk.name = "Relay%d" % (k + 1); rk.position = Vector3(2.6, 0.0, 0.5); kn.add_child(rk)
		s._box(rk, Vector3(0, 1.1, 0), Vector3(1.6, 2.2, 1.2), steel, "Kiosk")
		s._box(rk, Vector3(0, 2.3, 0), Vector3(1.8, 0.3, 1.4), s._mat(RELAY_COL[k], 0.5, 0.1), "Cap")
		s._box(rk, Vector3(0, 1.3, 0.62), Vector3(1.0, 0.6, 0.06), s._emit_mat(RELAY_COL[k], 1.8), "Display")
		var lamp := s._emit_mat(Color(1.0, 0.7, 0.1), 2.5)
		var sm := SphereMesh.new(); sm.radius = 0.2; sm.height = 0.4
		s._inst(rk, sm, lamp, "Lamp", Vector3(0.5, 2.7, 0), false)
		# a lead from the breaker to the line
		d.kiosk.append({"node": kn, "lamp": lamp, "blade": blade})
		s.anchors["R%d" % (k + 1)] = kn.position + Vector3(2.6, 5.5, 0.5)
	# the faults: a striped post where each stands, a flash on it when it is the one being shown
	for f in FAULT_AT:
		var sect := 0
		match str(f):
			"F1": sect = 0
			"F2": sect = 1
			"F3", "F4": sect = 2
			_: sect = 3
		var x0: float = L24_X[sect]; var x1: float = L24_X[sect + 1]
		var fx := lerpf(x0, x1, float(FAULT_AT[f])); var fz := _zc24(fx) - 5.0
		var fn := Node3D.new(); fn.name = "Fault" + str(f); fn.position = Vector3(fx, s.ground(fx, fz), fz); s._root.add_child(fn)
		s._box(fn, Vector3(0, 2.0, 0), Vector3(0.25, 4.0, 0.25), s._mat(Color(0.9, 0.9, 0.9), 0.6), "Post")
		for b in 2: s._box(fn, Vector3(0, 0.7 + 1.4 * float(b), 0), Vector3(0.3, 0.5, 0.3), s._mat(Color(0.85, 0.15, 0.12), 0.6), "Band")
		var fl := _flash(s, fn, Vector3(0, 6.0, 5.0), 2.6, "Flash")
		d.fault_pos[str(f)] = {"node": fn, "flash": fl}
	d["order"] = []
	d["cur"] = -1
	s.anchors["fault"] = s.anchors.get("R1", Vector3.ZERO)

static func _build_l25(s: Stage3D) -> void:
	var d: Dictionary = s.d7
	s._ph = Vector3(0.0, 1.0, 0.0)
	var ph := s._build_powerhouse(Vector3(0.0, 1.0, 0.0))
	s._build_alternator(ph, Vector3(1.5, 3.4, 0.6))
	s._build_rotor(6, 0.5)
	# the step-up transformer, then the breaker bay (a gantry, a breaker with a visible link) and the line
	var tn := Node3D.new(); tn.name = "Transformer"; tn.position = Vector3(26.0, s.ground(26.0, 2.0), 2.0); s._root.add_child(tn)
	s._box(tn, Vector3(0, 0.1, 0), Vector3(9.0, 0.3, 9.0), s._soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2))
	var tk := s._inst(tn, Props3D.transformer(), s._vc_mat(0.55), "Tank"); tk.scale = Vector3.ONE * 1.9
	var bay := Node3D.new(); bay.name = "BreakerBay"; bay.position = Vector3(46.0, s.ground(46.0, 2.0), 2.0); s._root.add_child(bay)
	s._box(bay, Vector3(0, 0.1, 0), Vector3(16.0, 0.3, 10.0), s._soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2))
	var gt := s._inst(bay, Props3D.gantry(), s._vc_mat(0.5), "Gantry", Vector3(0, 0, -3.5)); gt.scale = Vector3(1.2, 1.2, 1.2)
	var bk := s._inst(bay, Props3D.breaker(), s._vc_mat(0.55), "Breaker", Vector3(0, 0, 1.5)); bk.scale = Vector3.ONE * 1.4
	var link := s._box(bay, Vector3(0, 5.6, 1.5), Vector3(2.4, 0.4, 0.4), s._mat(Color(0.80, 0.45, 0.25), 0.35, 0.5), "Link")
	var lamp := s._emit_mat(Color(0.3, 1.0, 0.45), 3.0)
	var sm := SphereMesh.new(); sm.radius = 0.3; sm.height = 0.6
	s._inst(bay, sm, lamp, "Lamp", Vector3(0, 7.2, 1.5), false)
	d["bay"] = {"link": link, "lamp": lamp}
	# the line: lattice towers east, the fault 40 % along
	var sp: Array = Props3D.support("lattice", 24.0, 21.0)
	var att: Array = []
	var x0 := 64.0; var x1 := 264.0
	for k in 7:
		var tx := lerpf(x0, x1, float(k) / 6.0)
		var tw := s._inst(s._root, sp[0], s._vc_mat(0.6), "Tower%d" % k, Vector3(tx, s.ground(tx, 2.0) - 0.3, 2.0))
		var a: Array = []
		for p in sp[1]: a.append(tw.position + (p as Vector3))
		att.append(a)
	var pts: Array = [[], [], []]
	for c in 3:
		pts[c].append(bay.position + Vector3(0.0, 7.0, 1.5 + (c - 1) * 1.6))
		for a in att: pts[c].append((a as Array)[c])
	for c in 3: s._inst(s._root, s._run(pts[c], 0.1, 1.8), s._mat(Color(0.5, 0.5, 0.52), 0.4, 0.5), "Line%d" % c, Vector3.ZERO, false)
	var fx := lerpf(x0, x1, L25_FAULT_AT)
	d["fault_at"] = Vector3(fx, s.ground(fx, 2.0) + 18.0, 2.0)
	d["flash"] = _flash(s, s._root, d.fault_at, 5.0, "FaultFlash")
	d["clear_s"] = 0.0; d["tmax"] = 1.0; d["marker"] = 0.0; d["bk_open"] = false
	s.anchors["gen"] = Vector3(0.0, 12.5, 2.0)
	s.anchors["breaker"] = bay.position + Vector3(0, 9.0, 1.5)
	s.anchors["fault"] = d.fault_at + Vector3(0, 4.0, 0)
	s.anchors["line"] = Vector3(lerpf(x0, x1, 0.75), s.ground(lerpf(x0, x1, 0.75), 2.0) + 28.0, 2.0)

static func _build_l26(s: Stage3D) -> void:
	var d: Dictionary = s.d7
	var steel := s._mat(Color(0.55, 0.58, 0.62), 0.5, 0.3); var dark := s._mat(Color(0.28, 0.3, 0.33), 0.5, 0.3)
	# the control room, cut away to the camera: desks, chairs, a wall of lit tiles one per plant
	var cr := s._hall(Vector3(-52.0, s.ground(-52.0, 56.0), 56.0), Vector3(30.0, 6.0, 16.0), "ControlRoom", Color(0.66, 0.64, 0.60))
	for row in 2: for k in 5:
		s._box(cr, Vector3(-9.0 + 4.5 * float(k), 0.9, -1.0 + 4.0 * float(row)), Vector3(3.2, 0.12, 1.4), s._mat(Color(0.5, 0.36, 0.24), 0.6), "Desk")
		s._box(cr, Vector3(-9.0 + 4.5 * float(k), 1.5, -1.5 + 4.0 * float(row)), Vector3(1.0, 0.7, 0.1), s._emit_mat(Color(0.5, 0.85, 1.0), 1.2), "Screen")
	d["tiles"] = {}
	var order := ["coalsub", "coalsc", "ccgt", "ocgt", "hydro", "solar"]
	for k in order.size():
		var tm := s._emit_mat(PCOL[order[k]], 0.2)
		s._box(cr, Vector3(-10.0 + 4.0 * float(k), 3.6, -6.9), Vector3(3.2, 2.2, 0.12), tm, "Tile_" + order[k]); d.tiles[order[k]] = tm
	var rl := OmniLight3D.new(); rl.position = Vector3(0, 5.0, 2.0); rl.omni_range = 26.0; rl.light_energy = 1.2; rl.light_color = Color(0.9, 0.95, 1.0)
	if s.quality != "low": cr.add_child(rl)
	d["plants"] = {}
	# the four thermal plants in a row behind it, each a house, stacks and a steam puff
	var spec := {"coalsub": [Vector3(-130.0, 0, -40.0), 1, 30.0, 1.3], "coalsc": [Vector3(-84.0, 0, -52.0), 1, 42.0, 1.5], "ccgt": [Vector3(-30.0, 0, -52.0), 2, 24.0, 1.0], "ocgt": [Vector3(20.0, 0, -42.0), 1, 12.0, 0.7]}
	for id in PLANTS:
		var sd: Array = spec[id]; var p: Vector3 = sd[0]
		var n := Node3D.new(); n.name = "Plant_" + id; n.position = Vector3(p.x, s.ground(p.x, p.z), p.z); s._root.add_child(n)
		var w := 16.0 if id != "ocgt" else 9.0; var dd := 12.0; var h := 14.0 if id.begins_with("coal") else 9.0
		s._box(n, Vector3(0, h * 0.5, 0), Vector3(w, h, dd), s._clad_mat(Color(0.58, 0.60, 0.60), 0.9, 7.5), "Hall")
		var wm := s._emit_mat(Color(1.0, 0.85, 0.55), 0.0); wm.cull_mode = BaseMaterial3D.CULL_DISABLED
		for k in 4: s._box(n, Vector3(-w * 0.35 + w * 0.23 * float(k), h * 0.6, dd * 0.5 + 0.05), Vector3(2.0, 2.4, 0.1), wm, "Window")
		var puffs: Array = []
		for k in int(sd[1]):
			var sx := (-3.0 + 6.0 * float(k)) if int(sd[1]) > 1 else 2.0
			_stack(s, n, Vector3(sx, h, -2.0), float(sd[2]) - h, float(sd[3]), Color(0.4, 0.4, 0.42))
			puffs.append(_plume(s, n, Vector3(sx, float(sd[2]) + 3.0, -2.0), 4.0, "Steam%d" % k))
		if id.begins_with("coal"):   # a cooling tower beside it
			var ct := CylinderMesh.new(); ct.top_radius = 5.0; ct.bottom_radius = 7.5; ct.height = 20.0
			s._inst(n, ct, s._mat(Color(0.72, 0.72, 0.70), 0.8), "CoolingTower", Vector3(14.0, 10.0, -4.0))
			puffs.append(_plume(s, n, Vector3(14.0, 24.0, -4.0), 6.0, "TowerSteam"))
		d.plants[id] = {"node": n, "win": wm, "puffs": puffs, "share": 0.0}
		s.anchors[id] = n.position + Vector3(0, float(sd[2]) + 10.0, 0)
	# hydro on its shelf: a reservoir, a penstock and a powerhouse at the foot
	s._water(13.2, Rect2(74.0, -118.0, 52.0, 52.0), Vector2(0, 0))
	var hn := Node3D.new(); hn.name = "Plant_hydro"; hn.position = Vector3(100.0, s.ground(100.0, -58.0), -58.0); s._root.add_child(hn)
	s._box(hn, Vector3(0, 2.5, 0), Vector3(14.0, 5.0, 9.0), s._clad_mat(Color(0.62, 0.58, 0.52), 0.7, 4.0), "Powerhouse")
	var hwm := s._emit_mat(Color(1.0, 0.85, 0.55), 0.0); hwm.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3: s._box(hn, Vector3(-4.0 + 4.0 * float(k), 3.0, 4.55), Vector3(1.8, 1.6, 0.1), hwm, "Window")
	var pen := s._emit_mat(Color(0.4, 0.7, 1.0), 0.0); pen.albedo_color = Color(0.3, 0.33, 0.35)
	s._beam(s._root, Vector3(100.0, 13.0, -80.0), Vector3(100.0, 4.5, -62.0), 0.9, pen)
	d.plants["hydro"] = {"node": hn, "win": hwm, "pen": pen, "puffs": [], "share": 0.0}
	s.anchors["hydro"] = hn.position + Vector3(0, 12.0, 0)
	# the solar field: rows of tilted panels, one material
	var sol := s._emit_mat(Color(0.5, 0.7, 1.0), 0.0); sol.albedo_color = Color(0.1, 0.16, 0.3); sol.metallic = 0.4
	for r in 5: for c in 8:
		var pn := s._box(s._root, Vector3(135.0 + 6.0 * float(c), 1.4, -24.0 + 7.0 * float(r)), Vector3(5.0, 0.12, 3.2), sol, "Panel"); pn.rotation.x = deg_to_rad(-25.0)
		pn.position.y = s.ground(pn.position.x, pn.position.z) + 1.4
	d.plants["solar"] = {"mat": sol, "share": 0.0}
	s.anchors["solar"] = Vector3(160.0, s.ground(160.0, -10.0) + 8.0, -10.0)
	# the corridor: towers from the plants' edge to the city
	var sp: Array = Props3D.support("lattice", 22.0, 19.0)
	var att: Array = []
	for k in 6:
		var tx := lerpf(60.0, 205.0, float(k) / 5.0)
		var tw := s._inst(s._root, sp[0], s._vc_mat(0.6), "Tower%d" % k, Vector3(tx, s.ground(tx, 4.0) - 0.3, 4.0))
		var a: Array = []
		for p in sp[1]: a.append(tw.position + (p as Vector3))
		att.append(a)
	var core := s._mat(Color(0.55, 0.56, 0.58), 0.35, 0.5); core.emission_enabled = true; core.emission = Color(1.0, 0.55, 0.2); core.emission_energy_multiplier = 0.0
	var gm := s._hot_mat(0.0); gm.set_shader_parameter("inflate", 0.0004)
	var cs := SurfaceTool.new(); cs.begin(Mesh.PRIMITIVE_TRIANGLES); var gs := SurfaceTool.new(); gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	for c in 3:
		var pts: Array = []
		for a in att: pts.append((a as Array)[c])
		var run := 0.0
		for k in pts.size() - 1:
			var a0: Vector3 = pts[k]; var b0: Vector3 = pts[k + 1]
			Props3D.add_wire(cs, a0, b0, 1.4, 0.1, run, 12); Props3D.add_wire(gs, a0, b0, 1.4, 0.17, run, 12); run += a0.distance_to(b0)
	s._inst(s._root, cs.commit(), core, "Corridor", Vector3.ZERO, false); s._inst(s._root, gs.commit(), gm, "CorridorGlow", Vector3.ZERO, false)
	d["corr"] = {"core": core, "glow": gm}
	d["city"] = _city(s, CITY, 91)
	s.anchors["corridor"] = Vector3(130.0, s.ground(130.0, 4.0) + 30.0, 4.0)
	s.anchors["control"] = Vector3(-52.0, 12.0, 56.0)

# --------------------------------------------------------------------------------------------------------------------
# The engine's numbers onto the scene
# --------------------------------------------------------------------------------------------------------------------
static func _hour(s: Stage3D) -> int: return clampi(int(maxf(s._minute, 0.0) / 60.0), 0, 23)

static func apply(s: Stage3D) -> void:
	var q: Dictionary = s.q; var d: Dictionary = s.d7
	var rev := bool(q.get("revealed", false))
	match s.scn:
		"l23", "l27":
			var is23 := s.scn == "l23"
			var des: Dictionary = q.design
			_coupler_set(s, (str(des.coupler) == "open") if is23 else false, float(des.reactor) if is23 else 0.0)
			var over: Dictionary = {}
			if is23 and rev: for x in q.duty: over[str(x.id)] = bool(x.over)
			var ok := true
			if rev: ok = bool(q.get("ok", true)) if is23 else bool(q.get("ratingOk", true))
			for id in d.kiosk:
				var ov: bool = bool(over.get(id, false)) if is23 else (rev and not ok)
				_set_kiosk(d.kiosk[id], rev, ov)
			(d.estate as StandardMaterial3D).emission_energy_multiplier = 0.0 if (rev and not ok) else 4.0
			Kit3D.set_group("estate", not (rev and not ok))
			d["failed"] = rev and not ok
			(d.estate_body as StandardMaterial3D).albedo_color = Color(0.42, 0.44, 0.52) if (rev and not ok) else Color.WHITE
			if not (d.estate_mats as Dictionary).is_empty(): Assets3D.dim_mats(d.estate_mats, rev and not ok)
			d["dark"] = rev and not ok
			d["rev"] = rev
			if s.scn == "l27":
				var us: Array = q.units; var disp: Array = des.dispatch
				for k in 3:
					var share := clampf(float(disp[k]) / maxf(float(us[k].pMax), 1.0), 0.0, 1.0)
					d.units[k]["share"] = share
					((d.units[k].plume as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("power", 0.35 * share)
					(d.units[k].plume as MeshInstance3D).scale = Vector3.ONE * (0.2 + 0.45 * share)
		"l24":
			var burnt := [false, false, false, false]
			if rev: for f in q.faults: if bool(f.burnt): burnt[int(f.section) - 1] = true
			for k in 4: (d.cond[k] as StandardMaterial3D).emission_energy_multiplier = 5.0 if burnt[k] else 0.0
			d["burnt"] = burnt
			var order: Array = []
			for f in q.faults:
				var op := -1; var best := 1e9
				for j in (f.times as Array).size():
					if f.times[j] != null and float(f.times[j]) < best: best = float(f.times[j]); op = j
				order.append({"id": str(f.id), "opener": op, "amps": int(f.amps)})
			d["order"] = order; d["rev"] = rev
			for k in 4: _lamp24(d, k, -1)
		"l25":
			d["rev"] = rev
			d["clear_s"] = float(q.clearMs) / 1000.0
			if rev and not (q.trace.t as Array).is_empty(): d["tmax"] = maxf(float((q.trace.t as Array)[(q.trace.t as Array).size() - 1]), 1.0)
		"l26":
			var h := _hour(s); d["h"] = h
			var mx := func(a: Array) -> float:
				var m := 1.0
				for v in a: m = maxf(m, float(v))
				return m
			for id in PLANTS:
				var share := 0.0
				if rev: share = clampf(float(q.hourly.p[id][h]) / maxf(float(_plant_max(q, id)), 1.0), 0.0, 1.0)
				_plant_set(d.plants[id], share)
			var hy := clampf(float((q.hydroMW as Array)[h]) / 200.0, 0.0, 1.0)
			(d.plants.hydro.win as StandardMaterial3D).emission_energy_multiplier = 3.0 * hy
			(d.plants.hydro.pen as StandardMaterial3D).emission_energy_multiplier = 3.0 * hy
			d.plants.hydro["share"] = hy
			var so := clampf(float((q.solarMW as Array)[h]) / maxf(mx.call(q.solarMW), 1.0), 0.0, 1.0)
			(d.plants.solar.mat as StandardMaterial3D).emission_energy_multiplier = 2.2 * so; d.plants.solar["share"] = so
			for id in d.tiles: (d.tiles[id] as StandardMaterial3D).emission_energy_multiplier = 0.2 + 2.6 * float(d.plants[id].share)
			var dem := clampf(float((q.demandMW as Array)[h]) / maxf(mx.call(q.demandMW), 1.0), 0.0, 1.0)
			(d.city as StandardMaterial3D).emission_energy_multiplier = 0.3 + 3.2 * dem; d["dem"] = dem
			var fl := 0.0; var tripped := false
			if rev:
				fl = clampf(absf(float((q.hourly.flow as Array)[h])) / maxf(float(q.corridorMW), 1.0), 0.0, 1.2)
				if q.get("trip") != null: tripped = h >= int(str(q.trip.time).split(":")[0])
			if tripped: fl = 0.0
			var hc := Bench3D.heat_colour(clampf(fl, 0.0, 1.0))
			(d.corr.core as StandardMaterial3D).emission = hc; (d.corr.core as StandardMaterial3D).emission_energy_multiplier = 6.0 * pow(clampf(fl, 0.0, 1.0), 1.3)
			(d.corr.glow as ShaderMaterial).set_shader_parameter("tint", Color(hc, 1.0)); (d.corr.glow as ShaderMaterial).set_shader_parameter("power", 1.2 * pow(clampf(fl, 0.0, 1.0), 1.2))
			d["flow"] = fl; d["tripped"] = tripped

static func _plant_max(q: Dictionary, id: String) -> float:
	for p in q.plants: if str(p.id) == id: return float(p.pMax)
	return 1.0

static func _plant_set(p: Dictionary, share: float) -> void:
	p["share"] = share
	(p.win as StandardMaterial3D).emission_energy_multiplier = 3.0 if share > 0.02 else 0.0
	for pf in p.puffs:
		(pf as MeshInstance3D).visible = share > 0.02
		((pf as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("power", 0.4 * share)
		(pf as MeshInstance3D).scale = Vector3.ONE * (0.3 + 0.6 * share)

## L24: kiosk k's lamp and blade: unrun amber; when `open` is k, red with the blade swung open; else green.
static func _lamp24(d: Dictionary, k: int, open: int) -> void:
	var kk: Dictionary = d.kiosk[k]; var lamp: StandardMaterial3D = kk.lamp
	var rev := bool(d.get("rev", false))
	lamp.emission = Color(1.0, 0.15, 0.1) if open == k else Color(0.3, 1.0, 0.45) if rev else Color(1.0, 0.7, 0.1)
	(kk.blade as Node3D).rotation.z = deg_to_rad(40.0) if open == k else 0.0

# --------------------------------------------------------------------------------------------------------------------
# Motion: the fault flashes and the replays (the engine's data on a clock)
# --------------------------------------------------------------------------------------------------------------------
static func process(s: Stage3D, dt: float) -> void:
	var d: Dictionary = s.d7
	if d.is_empty() or s.q.is_empty(): return
	var t := s._t
	var pulse := 0.6 + 0.4 * sin(t * 9.0)
	match s.scn:
		"l23", "l27":
			var f: MeshInstance3D = d.flash
			f.visible = bool(d.get("rev", false)) and s.scn == "l23"
			if f.visible: (f.material_override as ShaderMaterial).set_shader_parameter("power", 2.2 * pulse)
			if f.visible:   # sparks and smoke only when the breaker failed to clear; a cleared fault is a short flash
				var bad := bool(d.get("failed", false))
				(f.get_node("Smoke") as CPUParticles3D).emitting = bad; (f.get_node("Sparks") as CPUParticles3D).emitting = bad; (f.get_node("Ember") as Node3D).visible = bad
		"l24":
			if not bool(d.rev) or (d.order as Array).is_empty():
				for f in d.fault_pos: (d.fault_pos[f].flash as MeshInstance3D).visible = false
				return
			var order: Array = d.order; var idx := int(t / 2.5) % order.size()
			var cur: Dictionary = order[idx]
			for f in d.fault_pos:
				var fl: MeshInstance3D = d.fault_pos[f].flash
				fl.visible = str(f) == str(cur.id)
				if fl.visible: (fl.material_override as ShaderMaterial).set_shader_parameter("power", 2.4 * pulse)
			for k in 4: _lamp24(d, k, int(cur.opener))
			d["cur"] = idx
			var fp: Node3D = d.fault_pos[str(cur.id)].node
			s.anchors["fault"] = fp.position + Vector3(0, 7.0, 0)
		"l25":
			var marker := 0.0   # at rest until the run
			var f: MeshInstance3D = d.flash; var bay: Dictionary = d.bay
			if bool(d.rev):
				var tr: Dictionary = s.q.trace; var ts: Array = tr.t; var dd: Array = tr.deltaDeg
				var tm := fmod(t, float(d.tmax) + 1.0)
				if not ts.is_empty():
					var idx := 0
					for i in ts.size(): if float(ts[i]) <= tm: idx = i
					marker = float(dd[idx]) if tm <= float(d.tmax) else float(dd[dd.size() - 1])
				else:   # the query gives no decimated trace: the engine's three angles on the same clock (start, at clearing, the peak a second later)
					var a0 := float(s.q.delta0Deg); var a1 := float(s.q.clearAtDeg); var a2 := float(s.q.peakDeg); var cs := maxf(float(d.clear_s), 0.001)
					marker = lerpf(a0, a1, clampf(tm / cs, 0.0, 1.0)) if tm < cs else lerpf(a1, a2, clampf((tm - cs) / 1.0, 0.0, 1.0))
				var open := tm >= float(d.clear_s)
				f.visible = not open
				(bay.link as MeshInstance3D).visible = not open
				(bay.lamp as StandardMaterial3D).emission = Color(1.0, 0.15, 0.1) if open else Color(0.3, 1.0, 0.45)
				d["bk_open"] = open
			else:
				f.visible = false; (bay.link as MeshInstance3D).visible = true; (bay.lamp as StandardMaterial3D).emission = Color(0.3, 1.0, 0.45); d["bk_open"] = false
			if f.visible: (f.material_override as ShaderMaterial).set_shader_parameter("power", 2.6 * pulse)
			d["marker"] = marker
			if s._rotor != null: s._rotor.rotation.z = -deg_to_rad(marker) / 3.0

static func report(s: Stage3D) -> Dictionary:
	var d: Dictionary = s.d7; var r := {"kind": s.scn}
	if d.is_empty(): return r
	match s.scn:
		"l23", "l27":
			var cn: Node3D = d.coupler
			var rings := 0
			for c in cn.get_children(): if str(c.name).begins_with("Coil"): rings += 1
			r["coupler_open"] = cn.find_child("OpenMark", false, false) != null
			r["reactor_rings"] = rings
			var over := {}
			for id in d.kiosk: over[id] = bool(d.kiosk[id].over)
			r["over"] = over
			r["smoke"] = d.kiosk.keys().filter(func(id): return (d.kiosk[id].puff as MeshInstance3D).visible)
			r["estate_e"] = (d.estate as StandardMaterial3D).emission_energy_multiplier
			r["estate_lamps"] = Kit3D.group_on("estate")
			r["kiosks"] = d.kiosk.size()
			if s.scn == "l27": r["unit_share"] = (d.units as Array).map(func(u): return float(u.share))
		"l24":
			r["relays"] = d.kiosk.size()
			r["cols"] = d.kiosk.map(func(k): return ((k.node as Node3D).find_child("Cap", true, false) as MeshInstance3D).material_override.albedo_color)
			r["opener"] = (d.order as Array).map(func(o): return int(o.opener))
			r["burnt"] = d.get("burnt", [])
			r["posts"] = d.fault_pos.size()
		"l25":
			r["clear_ms"] = int(roundf(float(d.clear_s) * 1000.0)); r["marker"] = float(d.marker); r["breaker_open"] = bool(d.bk_open)
		"l26":
			var sh := {}
			for id in d.plants: sh[id] = float(d.plants[id].share)
			r["share"] = sh; r["flow"] = float(d.get("flow", 0.0)); r["tripped"] = bool(d.get("tripped", false)); r["dem"] = float(d.get("dem", 0.0)); r["hour"] = int(d.get("h", 0))
			r["tiles"] = d.tiles.keys().map(func(id): return (d.tiles[id] as StandardMaterial3D).emission_energy_multiplier)
	return r
