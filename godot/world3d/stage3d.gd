class_name Stage3D
extends Bench3D
## Chapter 4's four jobs as 3D places (the sibling of Bench3D, which it extends for the land, sky, water, camera and the small helpers):
## L10 Tanner Street at dusk (a pole transformer, six poles with three phase wires and a neutral, 18 houses on service drops),
## L11 the Tanner estate (the motor hall, the capacitor bank, the pump house), L12 Over the Hill (Kestrel Falls, two or three circuits over a ridge to the
## city) and L13 the generator hall (one synchronous machine and its exciter). Display only: every number is the engine's `ch4Status`, handed over by
## WorldView's set_model; the only arithmetic maps numbers to light, colour and count.
##
## L10: each house's service drop starts on the insulator of the phase the engine says it is on (a red, b yellow, c blue: the insulators and a tag on the drop
## carry the colour); the windows follow the voltage at the house's pole, (V / 230)^2, amber under the band; the neutral warms with the neutral current.
## L11: the bank has exactly the engine's can count a leg, wired star or delta; cans warm to red as the can voltage nears its rating; the yard lamps follow the bus.
## L12: one row of towers per circuit (the engine's two or three), a series-capacitor platform on each when the build has them; the circuit the trip
## takes goes dark; the city's windows go out with an unstable swing; the rotor swings by the engine's angle.
## L13: the field glow (air gap, pole shoes, exciter) follows the engine's E.

const STAGES := {"L10": "l10", "L11": "l11", "L12": "l12", "L13": "l13", "L23": "l23", "L24": "l24", "L25": "l25", "L26": "l26", "L27": "l27",
	"L31": "l31", "L32": "l32", "L33": "l33", "L34": "l34", "L35": "l35", "L36": "l36"}
const PH := ["a", "b", "c"]
const PH_COL := {"a": Color("#E5484D"), "b": Color("#F2C94C"), "c": Color("#4FA3FF")}
const HOT := Color(1.0, 0.97, 0.92)
const L10_X0 := -60.0             # the first pole of the street, then every 30 m
const L10_SP := 30.0
const L10_TX := -90.0             # the transformer pole
const L10_H := 10.0               # pole height
const L10_ATT := {"a": Vector3(0, 9.9, -1.05), "b": Vector3(0, 10.45, 0), "c": Vector3(0, 9.9, 1.05), "n": Vector3(0, 7.9, 1.0)}   # insulator tops, local to a pole
const L11_HALL := Vector3(-46.0, 0.0, 0.0)
const L11_BANK := Vector3(12.0, 0.0, 0.0)
const L11_PUMP := Vector3(60.0, 0.0, 4.0)
const BANK_COLS := 14
const LAMP_E := 3.2               # L11: a yard lamp's emission at the nominal bus voltage
const LIP12 := -40.0              # L12: the dam's crest line
const SERIES_AT := 5              # L12: the series capacitor stands between this tower and the next

var scn := ""                     # "l10" .. "l13"
var _pm: Dictionary = {}          # phase colour materials
var _poles: Array = []            # L10: pole nodes, first to last
var _drops: Array = []            # L10: [{node, tag, ph, from}]
var _house_geo: Array = []        # L10: [{pos, w, d, h}]
var _neutral_core: StandardMaterial3D
var _neutral_glow: ShaderMaterial
var _tx_pole: Node3D
var _cans: Array = []             # L11: the three racks' [MultiMeshInstance3D]
var _bank_key := ""
var _can_col := Color.BLACK       # the colour the cans were last given (a headless renderer keeps no instance colours to read back)
var _bank_root: Node3D
var _bank_wire: Node3D
var _burst_fx: Array = []
var _spin: Array = []             # nodes that turn: [{node, w}]
var _lamps: Array = []            # [{mat, light}]
var _pump_blade: Node3D
var _pump_lamp: StandardMaterial3D
var _tower_mesh: Array = []
var _circ: Array = []             # L12: [{root, core, glow, mat, gmat, dark}]
var _plat_key := ""
var _line_nodes: Node3D
var _city_mat: StandardMaterial3D
var _plats := 0
var _swing_t := 0.0
var _exc_mat: ShaderMaterial
var _field := 0.0
var _ph12 := Vector3.ZERO
var d7: Dictionary = {}           # chapter 7's scene state (world3d/stage3d_ch7.gd)
var d8: Dictionary = {}           # chapter 8's scene state (world3d/stage3d_ch8.gd)
var _ft_gpu := 0.0               # CB_FRAMETIME: render time of the viewport, as Province3D measures it
var _ft_cpu := 0.0
var _ft_n := 0
var _ft_ms := 0.0
var _ft_at := 0.0
var _measuring := false

# --------------------------------------------------------------------------------------------------------------------
# Numbers in
# --------------------------------------------------------------------------------------------------------------------
func set_model(m: Dictionary) -> void:
	_setup()
	var r = null
	var lid := str(m.get("level", ""))
	if view != null and view.get("app") != null and view.app.get("b") != null:
		var sid := str(STAGES.get(lid, ""))
		r = view.app.b.q("ch8Study" if Stage8.IDS.has(sid) else ("ch7Study" if Stage7.IDS.has(sid) else "ch4Status"))
		if Stage8.IDS.has(sid) and r is Dictionary: r["kit"] = view.app.b.q("ch8Kit")   # prices and part lists: chapter 8's scenes read a few sizes from it
	set_stage(r if r is Dictionary else {}, float(m.get("minute", 1080.0)))

## The engine's ch4Status and the minute of the day. A query that is not active keeps the last scene.
func set_stage(sq: Dictionary, minute: float) -> void:
	_setup()
	var s := str(sq.get("scenario", "")).to_lower()
	if Stage8.IDS.has(s): minute = Stage8.sky_minute(s)   # chapter 8's places stand at a fixed time of day (L35 at noon, the rest at dusk)
	if absf(minute - _minute) > 0.4: _update_sky(minute)   # first: chapter 7's L26 reads the hour from it
	if sq.get("active", false):
		q = sq
		if s != scn or field == null:
			scn = s; kind = s; _build_stage()
		_apply_stage()

func _build_stage() -> void:
	_clear(_root)
	_water_mats.clear(); _homes.clear(); anchors.clear(); _shoe_mats.clear(); _poles.clear(); _drops.clear(); _house_geo.clear(); _cans.clear(); _burst_fx.clear()
	_spin.clear(); _lamps.clear(); _circ.clear(); _tower_mesh.clear(); _pm.clear(); _fields_on = false
	_alt = null; _rotor = null; _coils = null; _gap_mat = null; _fall_mat = null; _wire_mat = null; _wire_glow = null; _neutral_core = null; _neutral_glow = null
	_rotor_key = ""; _coil_key = ""; _bank_key = ""; _plat_key = ""; _bank_root = null; _bank_wire = null; _pump_blade = null; _pump_lamp = null; _city_mat = null; _exc_mat = null; _line_nodes = null
	_plats = 0
	_grass_tint = Vector3(0.62, 0.92, 0.50) if scn == "l11" else Vector3(0.86, 0.95, 0.70)
	_yard_gravel = 1.0 if scn in ["l23", "l25", "l27"] else 0.0
	real_gravel = scn == "l23"; real_sky = scn == "l23"
	match scn:
		"l10": _play = Rect2(-200.0, -70.0, 400.0, 140.0)
		"l11": _play = Rect2(-100.0, -60.0, 220.0, 120.0)
		"l12":
			_play = Rect2(-130.0, -110.0, 910.0, 230.0)
			_ph12 = Vector3(-1.0, 1.0, _rz12(-1.0) + 40.0)
		"l13": _play = Rect2(-90.0, -70.0, 180.0, 140.0)
		_:
			if Stage8.IDS.has(scn): Stage8.prepare(self); _play = Stage8.play(self); _fields_on = true
			else: _play = Stage7.play(scn)
	_build_terrain()
	match scn:
		"l10": _build_l10()
		"l11": _build_l11()
		"l12": _build_l12()
		"l13": _build_l13()
		_:
			if Stage8.IDS.has(scn): Stage8.build(self)
			else: Stage7.build(self)
	field = self
	if _minute >= 0.0: _update_sky(_minute)
	reset_camera()

# --------------------------------------------------------------------------------------------------------------------
# Land
# --------------------------------------------------------------------------------------------------------------------
func ground(x: float, z: float) -> float:
	match scn:
		"l10": return _h10(x, z)
		"l11": return _h11(x, z)
		"l12": return _h12(x, z)
		"l13": return _h13(x, z)
	if Stage8.IDS.has(scn): return Stage8.ground(self, x, z)
	return Stage7.ground(self, x, z) if Stage7.IDS.has(scn) else 0.0

func _n01(x: float, z: float) -> float: return _nz.get_noise_2d(x, z) * 0.5 + 0.5

func _h10(x: float, z: float) -> float:
	var h := 0.5 + 1.8 * _n01(x * 0.6, z * 0.6)
	h += 16.0 * smoothstep(10.0, 120.0, -z) * (0.4 + 0.6 * _n01(z, x))   # the hill behind the poles
	h += 7.0 * smoothstep(60.0, 190.0, z) * (0.4 + 0.6 * _n01(x * 0.5, z))
	h += _far(x, z)
	return lerpf(h, 0.5, _pad(x, z, Rect2(-130.0, -6.0, 290.0, 30.0), 14.0))

func _h11(x: float, z: float) -> float:
	var h := 0.8 + 2.2 * _n01(x * 0.6, z * 0.6)
	h += 18.0 * smoothstep(20.0, 120.0, -z) * (0.4 + 0.6 * _n01(z, x))
	h += 9.0 * smoothstep(50.0, 180.0, z) * (0.4 + 0.6 * _n01(x * 0.5, z))
	h += _far(x, z)
	h = lerpf(h, 0.5, _pad(x, z, Rect2(-82.0, -26.0, 134.0, 52.0), 12.0))
	var px := x - 86.0; var pz := z - 6.0
	h += -3.2 * exp(-(px * px + pz * pz) / 260.0)   # the pond the pump draws from
	return h

func _rz12(x: float) -> float: return 4.0 * sin(x / 55.0)
func _lip12(z: float) -> float: return LIP12 + 3.0 * _nz.get_noise_2d(7.0, z * 3.0)

func _h12(x: float, z: float) -> float:
	var d := z - _rz12(x); var w := absf(d)
	var lip := _lip12(z)
	var step := LIP_H * (1.0 - smoothstep(lip - 2.5, lip + 2.5, x))
	var walls := (44.0 * smoothstep(22.0, 190.0, w)) if d < 0.0 else (42.0 * smoothstep(90.0, 300.0, w))
	walls *= 1.0 - smoothstep(40.0, 190.0, x)
	var bumps := (_n01(x, z)) * (1.5 + 0.1 * w) * smoothstep(10.0, 40.0, w) * (1.0 - 0.5 * smoothstep(100.0, 300.0, x))
	var ridge := 78.0 * exp(-pow((x - 345.0) / 100.0, 2.0)) * (0.82 + 0.18 * _nz.get_noise_2d(x * 0.3, z * 0.3 + 40.0))
	var lake := (1.0 - smoothstep(30.0, 60.0, w)) * (1.0 - smoothstep(lip - 12.0, lip - 2.0, x)) * -7.0
	var ch := -3.0 * (1.0 - smoothstep(5.0, 10.0, w)) * smoothstep(lip, lip + 10.0, x) * (1.0 - smoothstep(120.0, 220.0, x))
	var px := x - (lip + 9.0); var pool := -3.5 * exp(-(px * px + d * d) / 140.0)
	var h := 1.0 + step + walls + bumps + ridge + lake + ch + pool + _far(x, z)
	h = lerpf(h, 1.0, _pad(x, z, Rect2(_ph12.x - 10.0, _ph12.z - 8.0, 20.0, 16.0), 9.0))
	h = lerpf(h, 1.2, _pad(x, z, Rect2(_ph12.x + 12.0, _ph12.z - 30.0, 36.0, 46.0), 10.0) * 0.8)
	h = lerpf(h, 3.0, _pad(x, z, _city_rect(), 40.0))
	return h

func _city_rect() -> Rect2: return Rect2(655.0, -10.0, 90.0, 80.0)

func _h13(x: float, z: float) -> float:
	var h := 0.8 + 2.4 * _n01(x * 0.6, z * 0.6)
	h += 40.0 * smoothstep(70.0, 260.0, -z) * (0.5 + 0.5 * _n01(z, x))
	h += 12.0 * smoothstep(120.0, 320.0, absf(x)) * _n01(x * 0.4, z * 0.4)
	h += _far(x, z)
	h = lerpf(h, 1.0, _pad(x, z, Rect2(-34.0, -14.0, 100.0, 36.0), 10.0))
	return h

func _splat(x: float, z: float, h: float) -> Array:
	if Stage8.IDS.has(scn): return Stage8.splat(self, x, z, h)
	if Stage7.IDS.has(scn): return Stage7.splat(self, x, z, h)
	var wood := smoothstep(0.05, 0.35, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))
	var c := Color(1, 0, 0, 0); var mud := 0.0; var paved := 0.0
	match scn:
		"l10":
			var f := maxf(wood * 0.6, smoothstep(14.0, 50.0, -z))
			c = Color(1.0 - f, f, 0.0, 0.0)
			paved = (1.0 - smoothstep(2.6, 4.2, absf(z - 5.0))) * (1.0 - smoothstep(150.0, 170.0, absf(x - 15.0)))
			mud = (1.0 - smoothstep(6.0, 14.0, Vector2(x - 10.0, z - 5.0).length())) * 0.0
		"l11":
			var f := maxf(wood * 0.6, smoothstep(24.0, 60.0, -z))
			c = Color(1.0 - f, f, 0.0, 0.0)
			paved = maxf(maxf(_pad(x, z, Rect2(-66.0, -12.0, 40.0, 26.0), 3.0), _pad(x, z, Rect2(-6.0, -9.0, 36.0, 19.0), 3.0)), maxf(_pad(x, z, Rect2(50.0, -3.0, 22.0, 17.0), 3.0), _pad(x, z, Rect2(-70.0, 12.0, 130.0, 5.0), 2.0) * 0.6))
			c = c.lerp(Color(0, 0, 0, 1), 1.0 - smoothstep(14.0, 22.0, Vector2(x - 86.0, z - 6.0).length()))
		"l12":
			var f := maxf(wood, smoothstep(20.0, 60.0, absf(z - _rz12(x)) - 20.0 * (1.0 - smoothstep(60.0, 220.0, x)))) * (1.0 - smoothstep(0.0, 8.0, h - 55.0))
			var r := smoothstep(34.0, 66.0, h) * (1.0 if x > -30.0 else 0.0)
			c = Color(1.0 - f - r, f, r, 0.0)
			var w := absf(z - _rz12(x))
			c = c.lerp(Color(0, 0, 0, 1), (1.0 - smoothstep(7.0, 12.0, w)) * smoothstep(LIP12, LIP12 + 10.0, x) * (1.0 - smoothstep(120.0, 220.0, x)))
			paved = maxf(_pad(x, z, Rect2(_ph12.x - 10.0, _ph12.z - 8.0, 20.0, 16.0), 3.0), maxf(_pad(x, z, Rect2(_ph12.x + 12.0, _ph12.z - 30.0, 36.0, 46.0), 3.0) * 0.7, _pad(x, z, _city_rect().grow(-8.0), 6.0) * 0.6))
		_:
			var f := maxf(wood * 0.7, smoothstep(30.0, 90.0, -z))
			c = Color(1.0 - f, f, 0.0, 0.0)
			paved = maxf(_pad(x, z, Rect2(-32.0, -12.0, 96.0, 32.0), 3.0), 0.0)
	return [c, mud, paved]

# --------------------------------------------------------------------------------------------------------------------
# Small builders
# --------------------------------------------------------------------------------------------------------------------
func _phase_mat(ph: String) -> StandardMaterial3D:
	if _pm.has(ph): return _pm[ph]
	var c: Color = PH_COL[ph]
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 0.5; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.55
	_pm[ph] = m; return m

func _inst(parent: Node3D, mesh: Mesh, mat: Material, nm := "", at := Vector3.ZERO, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = at
	if nm != "": mi.name = nm
	if not shadow: mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi); return mi

## A conductor tinted a little in its phase colour, so a run reads as a, b or c from a distance.
func _phase_wire(ph: String) -> StandardMaterial3D:
	var k := "w" + ph
	if _pm.has(k): return _pm[k]
	var c: Color = PH_COL[ph]
	var m := StandardMaterial3D.new(); m.albedo_color = c.darkened(0.45); m.metallic = 0.3; m.roughness = 0.4; m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 0.5
	_pm[k] = m; return m

## A conductor through `pts` with a light sag per span.
func _run(pts: Array, r: float, sag: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]; var b: Vector3 = pts[k + 1]
		Props3D.add_wire(st, a, b, sag * clampf(a.distance_to(b) / 28.0, 0.1, 1.2), r, run, 12)
		run += a.distance_to(b)
	return st.commit()

func _cyl_mesh(a: Vector3, b: Vector3, r: float, col: Color, seg := 12) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Props3D._cyl(st, a, b, r, r, seg, col, true)
	return st.commit()

func _hot_mat(power: float) -> ShaderMaterial:
	var g := _glow_mat(Color(1.0, 0.4, 0.1, 1.0), power); g.set_shader_parameter("inflate", 0.0009); return g

func _emit_mat(c: Color, e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.12, 0.12, 0.13); m.roughness = 0.4
	m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = e; return m

## A cut-away hall: floor, back wall, side walls, a pitched roof slab and front columns. `size` is (x, eaves, z) in metres.
func _hall(at: Vector3, size: Vector3, nm: String, wall: Color) -> Node3D:
	var n := Node3D.new(); n.name = nm; n.position = at; _root.add_child(n)
	var stone := _soft_mat("rock", wall, 0.32, 0.16, 0.62, 0.45)
	var conc := _soft_mat("sand", Color(0.60, 0.59, 0.56), 0.22, 0.22, 0.0, 0.15)
	var steel := _mat(Color(0.24, 0.27, 0.30), 0.5, 0.3)
	var hx := size.x * 0.5; var hz := size.z * 0.5; var e := size.y
	_box(n, Vector3(0, -0.6, 0), Vector3(size.x + 0.4, 1.6, size.z + 0.4), conc, "Floor")
	_box(n, Vector3(0, e * 0.5, -hz + 0.4), Vector3(size.x, e, 0.8), stone, "BackWall")
	for sx in [-1.0, 1.0]: _box(n, Vector3(sx * (hx - 0.4), e * 0.5, 0), Vector3(0.8, e, size.z), stone, "SideWall")
	for sx in [-1.0, 1.0, -0.33, 0.33]: _box(n, Vector3(sx * (hx - 0.4), e * 0.5, hz - 0.3), Vector3(0.6, e, 0.6), steel, "Column")
	_box(n, Vector3(0, e - 0.3, hz - 0.3), Vector3(size.x, 0.6, 0.6), steel, "FrontBeam")
	var roof := _box(n, Vector3(0, e + 0.55, -0.4), Vector3(size.x + 1.2, 0.3, size.z + 1.2), _mat(Color(0.34, 0.24, 0.20), 0.65, 0.2), "Roof")
	roof.rotation.x = deg_to_rad(5.0)
	return n

func _lamp_post(p: Vector2, h := 7.0) -> Dictionary:
	var gy := ground(p.x, p.y)
	var mi := _inst(_root, _cyl_mesh(Vector3.ZERO, Vector3(0, h, 0), 0.12, Color(0.35, 0.36, 0.38), 8), _vc_mat(0.5), "LampPost", Vector3(p.x, gy - 0.1, p.y))
	var arm := _cyl_mesh(Vector3(0, h, 0), Vector3(1.4, h + 0.1, 0), 0.07, Color(0.35, 0.36, 0.38), 6)
	_inst(mi, arm, _vc_mat(0.5), "Arm")
	var bm := _emit_mat(Color(1.0, 0.86, 0.62), 0.0)
	var bulb := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.35; sm.height = 0.5; bulb.mesh = sm; bulb.material_override = bm
	bulb.position = Vector3(1.5, h - 0.1, 0); bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; mi.add_child(bulb)
	var lt: OmniLight3D = null
	if quality != "low":
		lt = OmniLight3D.new(); lt.omni_range = 26.0; lt.omni_attenuation = 0.55;   # 1128c: a visible pool
		lt.light_energy = 0.0; lt.light_color = Color(1.0, 0.86, 0.62); lt.position = Vector3(1.5, h - 0.6, 0); lt.light_energy = 0.0; mi.add_child(lt)
	Kit3D.glow(mi, Vector3(1.5, h - 0.1, 0), "yard_lamps", quality, h - 0.1)   # the province's halo and pool; its level is the bus voltage's brightness (_apply_l11)
	var d := {"mat": bm, "light": lt}
	_lamps.append(d); return d

## A wood pole with a crossarm at the top, for L10 (the phases sit on pins, the neutral on a spool lower down).
func _pole10(x: float, z: float, nm: String, phase_tags := true) -> Node3D:
	var n := Node3D.new(); n.name = nm; n.position = Vector3(x, ground(x, z) - 0.2, z); _root.add_child(n)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := Color(0.36, 0.27, 0.18)
	Props3D._cyl(st, Vector3.ZERO, Vector3(0, L10_H, 0), 0.19, 0.12, 8, wood, true)
	Props3D._cyl(st, Vector3(0, L10_H - 0.55, -1.4), Vector3(0, L10_H - 0.55, 1.4), 0.07, 0.07, 5, Color(0.42, 0.32, 0.22))
	Props3D._cyl(st, Vector3(0, L10_H - 2.1, 0.0), Vector3(0, L10_H - 2.1, 1.0), 0.05, 0.05, 5, Color(0.4, 0.42, 0.45))
	_inst(n, st.commit(), _vc_mat(0.85), "Pole")
	if phase_tags:
		for ph in PH:
			var a: Vector3 = L10_ATT[ph]
			_inst(n, _cyl_mesh(a - Vector3(0, 0.42, 0), a, 0.085, Color.WHITE, 8), _phase_mat(ph), "Insulator_" + ph, Vector3.ZERO, false)
		var an: Vector3 = L10_ATT["n"]
		_inst(n, _cyl_mesh(an - Vector3(0, 0.0, 0.1), an + Vector3(0, 0.0, 0.0), 0.11, Color(0.72, 0.74, 0.76), 8), _mat(Color(0.72, 0.74, 0.76), 0.4), "Insulator_n")
	return n

func _att(pole: Node3D, key: String) -> Vector3: return pole.position + (L10_ATT[key] as Vector3)

# --------------------------------------------------------------------------------------------------------------------
# L10: Tanner Street
# --------------------------------------------------------------------------------------------------------------------
func _build_l10() -> void:
	_water(-1.5, Rect2(-FAR_M, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.0, 0.05))
	# the transformer pole and the three plain poles that carry the 11 kV line away to the west
	_tx_pole = _pole10(L10_TX, 0.0, "TxPole", false)
	var hv_pts: Array = [[], [], []]
	var tops: Array = []
	for k in 4:
		var px := L10_TX - 30.0 * k
		var p: Node3D = _tx_pole if k == 0 else _pole10(px, 0.0, "HvPole%d" % k, false)
		tops.append(p)
		for c in 3: hv_pts[c].append(p.position + Vector3(0, L10_H - 0.1, (c - 1) * 1.05))
	var hv_mat := _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for c in 3: _inst(_root, _run(hv_pts[c], 0.035, 0.8), hv_mat, "HvWire%d" % c, Vector3.ZERO, false)
	var can := _inst(_tx_pole, _cyl_mesh(Vector3(0, 0, 0), Vector3(0, 1.5, 0), 0.62, Color(0.46, 0.5, 0.48), 16), _vc_mat(0.55), "TxCan", Vector3(0.9, L10_H - 4.6, 0.0))
	for c in 3: _inst(can, _cyl_mesh(Vector3(0, 1.5, (c - 1) * 0.3), Vector3(0, 2.1, (c - 1) * 0.3), 0.07, Color(0.78, 0.5, 0.36), 6), _vc_mat(0.5), "HvBushing%d" % c)
	for c in 4: _inst(can, _cyl_mesh(Vector3(0.45, 0.9, (c - 1.5) * 0.28), Vector3(0.75, 1.1, (c - 1.5) * 0.28), 0.045, Color(0.66, 0.68, 0.7), 6), _vc_mat(0.5), "LvBushing%d" % c)
	anchors["tx"] = _tx_pole.position + Vector3(0, L10_H + 2.2, 0)
	# the street's six poles
	for k in 6: _poles.append(_pole10(L10_X0 + L10_SP * k, 0.0, "Pole%d" % (k + 1)))
	# the four conductors from the transformer's low side along the street
	var lv0 := _tx_pole.position + Vector3(1.4, L10_H - 3.7, 0.0)
	var cond := _mat(Color(0.20, 0.20, 0.22), 0.45, 0.6)
	for ph in PH:
		var pts: Array = [lv0 + Vector3(0, 0, (PH.find(ph) - 1) * 0.35)]
		for p in _poles: pts.append(_att(p, ph))
		_inst(_root, _run(pts, 0.07, 0.55), _phase_wire(ph), "Phase_" + ph, Vector3.ZERO, false)
	var npts: Array = [lv0 + Vector3(0, -0.4, 0.5)]
	for p in _poles: npts.append(_att(p, "n"))
	var nm: ArrayMesh = _run(npts, 0.07, 0.55)
	_neutral_core = StandardMaterial3D.new(); _neutral_core.albedo_color = Color(0.62, 0.62, 0.64); _neutral_core.metallic = 0.35; _neutral_core.roughness = 0.35
	_neutral_core.emission_enabled = true; _neutral_core.emission = Color.BLACK; _neutral_core.emission_energy_multiplier = 0.0
	_inst(_root, nm, _neutral_core, "Neutral", Vector3.ZERO, false)
	_neutral_glow = _hot_mat(0.0)
	var gs := SurfaceTool.new(); gs.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run := 0.0
	for k in npts.size() - 1:
		var a: Vector3 = npts[k]; var b: Vector3 = npts[k + 1]
		Props3D.add_wire(gs, a, b, 0.55 * clampf(a.distance_to(b) / 28.0, 0.1, 1.2), 0.1, run, 12); run += a.distance_to(b)
	_inst(_root, gs.commit(), _neutral_glow, "NeutralGlow", Vector3.ZERO, false)
	anchors["neutral"] = _att(_poles[2], "n").lerp(_att(_poles[3], "n"), 0.5) + Vector3(0, -0.5, 0)
	anchors["street"] = _att(_poles[5], "b") + Vector3(0, 3.0, 0)
	# the houses: three under each pole, their service drops hung in _apply from the phase each is on
	var drop_mat := _mat(Color(0.12, 0.12, 0.12), 0.5, 0.4)
	for i in 18:
		var pole := i / 3; var j := i % 3
		var px: float = (_poles[pole] as Node3D).position.x
		var hp := Vector2(px + (float(j) - 1.0) * 9.5, 13.5)
		var v := WorldMath.hash2(i, 3, 17)
		var w := 6.0 + 1.6 * v; var d := 5.0 + 1.0 * v; var h := 3.0 + 0.6 * v
		_home(hp, PI, v)
		if quality == "low":
			var hm: Dictionary = _homes[i]; (hm.light as OmniLight3D).queue_free(); hm["light"] = null
		_house_geo.append({"pos": hp, "w": w, "d": d, "h": h})
		var node := MeshInstance3D.new(); node.name = "Drop%d" % i; node.material_override = drop_mat; node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root.add_child(node)
		var tag := MeshInstance3D.new(); tag.name = "Tag%d" % i; var sm := SphereMesh.new(); sm.radius = 0.3; sm.height = 0.6; tag.mesh = sm; tag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root.add_child(tag)
		_drops.append({"node": node, "tag": tag, "ph": "", "from": Vector3.ZERO})
	# 1128c rollout: a street lamp by every pole on the road in front of the houses; its halo, pool and light follow that pole's three homes (_apply_l10)
	for k in 6:
		var lx: float = (_poles[k] as Node3D).position.x + 4.7
		Kit3D.street_lamp(_root, Vector3(lx, ground(lx, 8.2) - 0.1, 8.2), 0.0, quality, "l10_lamp%d" % k, 6.0)
	# trees on the hill behind and the lots beyond the road
	_trees(_tree_ok10, 300.0, 8.0)

func _tree_ok10(x: float, z: float) -> float:
	if z > -16.0 and z < 30.0 and x > -190.0 and x < 190.0: return 0.0
	if z < -16.0: return 0.55
	return 0.25 * smoothstep(0.0, 0.3, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))

## The drop to house i: from the insulator of phase `ph` on its pole to the house's eave, with a tag in the phase colour at the house end.
func _set_drop(i: int, ph: String) -> void:
	var dr: Dictionary = _drops[i]; var g: Dictionary = _house_geo[i]
	var from := _att(_poles[i / 3], ph)
	var hp: Vector2 = g.pos
	var to := Vector3(hp.x + 1.0, ground(hp.x, hp.y) + float(g.h) + 0.4, hp.y - float(g.d) * 0.5 - 0.1)
	(dr.node as MeshInstance3D).mesh = _run([from, to], 0.055, 0.35); (dr.node as MeshInstance3D).material_override = _phase_wire(ph)
	var tag := dr.tag as MeshInstance3D
	tag.material_override = _phase_mat(ph); tag.position = to + Vector3(0, -0.1, -0.3)
	dr["ph"] = ph; dr["from"] = from

# --------------------------------------------------------------------------------------------------------------------
# L11: the estate
# --------------------------------------------------------------------------------------------------------------------
func _build_l11() -> void:
	_water(-1.5, Rect2(-FAR_M, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.0, 0.05))
	# the motor hall: five motors in a row, each a blue frame with a fan, coupled to its load
	var hall := _hall(L11_HALL + Vector3(0, ground(L11_HALL.x, L11_HALL.z), 0), Vector3(34.0, 8.5, 20.0), "MotorHall", Color(0.60, 0.58, 0.54))
	var steel := _mat(Color(0.24, 0.27, 0.30), 0.5, 0.3)
	var blue := _mat(Color(0.16, 0.30, 0.52), 0.4, 0.25)
	var grey := _mat(Color(0.55, 0.57, 0.58), 0.5, 0.3)
	for k in 5:
		var m := Node3D.new(); m.name = "Motor%d" % k; m.position = Vector3(-12.0 + 6.0 * k, 0.4, -1.0); hall.add_child(m)
		_box(m, Vector3(0, 0.1, 0), Vector3(5.4, 0.3, 2.6), steel, "Skid")
		var cm := CylinderMesh.new(); cm.top_radius = 0.95; cm.bottom_radius = 0.95; cm.height = 3.0
		var body := _inst(m, cm, blue, "Frame", Vector3(-0.3, 1.2, 0)); body.rotation.z = PI * 0.5
		_box(m, Vector3(-0.3, 2.35, 0), Vector3(0.9, 0.5, 0.8), grey, "TerminalBox")
		var cm2 := CylinderMesh.new(); cm2.top_radius = 0.28; cm2.bottom_radius = 0.28; cm2.height = 0.9
		var shaft := _inst(m, cm2, grey, "Coupling", Vector3(1.6, 1.2, 0)); shaft.rotation.z = PI * 0.5
		_box(m, Vector3(2.5, 1.0, 0), Vector3(1.7, 1.5, 1.7), grey, "Load")
		var fan := Node3D.new(); fan.name = "Fan"; fan.position = Vector3(-2.0, 1.2, 0); m.add_child(fan)
		for b in 6:
			var bl := _box(fan, Vector3(0, 0, 0), Vector3(0.08, 1.5, 0.22), _mat(Color(0.78, 0.8, 0.82), 0.4, 0.3)); bl.rotation.x = TAU * float(b) / 6.0 * 0.5
		_spin.append({"node": fan, "w": 5.0 + 0.4 * k, "axis": 0})
	if quality != "low":   # a work lamp under each roof: the halls are open at the front and would read black
		for hh in [hall, null]:
			if hh == null: continue
			var wl := OmniLight3D.new(); wl.position = Vector3(0, 6.0, 3.0); wl.omni_range = 26.0; wl.light_energy = 2.6; wl.light_color = Color(1.0, 0.86, 0.66); hh.add_child(wl)
	anchors["motors"] = L11_HALL + Vector3(0, 13.0, 0.0)
	# the capacitor bank: a fenced compound, three racks (one a leg), wired in _apply
	var by := ground(L11_BANK.x, L11_BANK.z)
	var comp := Node3D.new(); comp.name = "BankYard"; comp.position = Vector3(L11_BANK.x, by, L11_BANK.z); _root.add_child(comp)
	_bank_root = Node3D.new(); _bank_root.name = "Bank"; comp.add_child(_bank_root)
	_bank_wire = Node3D.new(); _bank_wire.name = "BankWire"; comp.add_child(_bank_wire)
	var gravel := _soft_mat("sand", Color(0.50, 0.49, 0.46), 0.3, 0.3, 0.0, 0.2)
	_box(comp, Vector3(0, 0.05, 0), Vector3(36.0, 0.25, 15.0), gravel, "Pad")
	var fence := _mat(Color(0.55, 0.56, 0.58), 0.5, 0.3)
	for k in 19:   # posts and rails of the fence round the pad
		var fx := -18.0 + 2.0 * k
		_box(comp, Vector3(fx, 1.0, 7.5), Vector3(0.08, 2.0, 0.08), fence); _box(comp, Vector3(fx, 1.0, -7.5), Vector3(0.08, 2.0, 0.08), fence)
	for k in 8:
		var fz := -7.5 + 2.14 * k
		_box(comp, Vector3(-18.0, 1.0, fz), Vector3(0.08, 2.0, 0.08), fence); _box(comp, Vector3(18.0, 1.0, fz), Vector3(0.08, 2.0, 0.08), fence)
	for sz in [-7.5, 7.5]: _box(comp, Vector3(0, 1.9, sz), Vector3(36.0, 0.06, 0.06), fence)
	for sx in [-18.0, 18.0]: _box(comp, Vector3(sx, 1.9, 0), Vector3(0.06, 0.06, 15.0), fence)
	for r in 3:
		var rack := Node3D.new(); rack.name = "Rack%d" % r; rack.position = Vector3((r - 1) * 11.0, 0, 0); _bank_root.add_child(rack)
		_box(rack, Vector3(0, 0.45, 0), Vector3(7.4, 0.2, 5.6), steel, "Deck")
		for px in [-3.5, 3.5]: for pz in [-2.6, 2.6]: _box(rack, Vector3(px, 0.2, pz), Vector3(0.2, 0.4, 0.2), steel)
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true
		var cyl := CylinderMesh.new(); cyl.top_radius = 0.2; cyl.bottom_radius = 0.2; cyl.height = 0.62; cyl.radial_segments = 10; cyl.rings = 1
		mm.mesh = cyl; mm.instance_count = 0
		var cm3 := StandardMaterial3D.new(); cm3.vertex_color_use_as_albedo = true; cm3.roughness = 0.35; cm3.metallic = 0.35
		var mmi := MultiMeshInstance3D.new(); mmi.name = "Cans"; mmi.multimesh = mm; mmi.material_override = cm3; rack.add_child(mmi)
		_cans.append(mmi)
		var fx := MeshInstance3D.new(); fx.name = "Burst%d" % r; var sp := SphereMesh.new(); sp.radius = 1.7; sp.height = 3.4; fx.mesh = sp
		fx.material_override = _glow_mat(Color(1.0, 0.45, 0.1, 0.5), 0.0); fx.position = Vector3(0, 2.2, 0); fx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; rack.add_child(fx)
		_burst_fx.append(fx)
	anchors["bank"] = Vector3(L11_BANK.x, by + 5.0, L11_BANK.z)
	# the pump house, its pump, the suction pipe to the pond and the delivery to a tank
	var pg := ground(L11_PUMP.x, L11_PUMP.z)
	var ph := _hall(Vector3(L11_PUMP.x, pg, L11_PUMP.z), Vector3(16.0, 5.6, 10.0), "PumpHouse", Color(0.66, 0.50, 0.40))
	_box(ph, Vector3(0, 0.3, -0.5), Vector3(7.0, 0.5, 3.0), steel, "Base")
	var pm := CylinderMesh.new(); pm.top_radius = 0.85; pm.bottom_radius = 0.85; pm.height = 2.6
	var pmot := _inst(ph, pm, blue, "PumpMotor", Vector3(-1.6, 1.5, -0.5)); pmot.rotation.z = PI * 0.5
	var vol := CylinderMesh.new(); vol.top_radius = 1.2; vol.bottom_radius = 1.2; vol.height = 0.9
	var volute := _inst(ph, vol, _mat(Color(0.18, 0.34, 0.45), 0.4, 0.3), "Volute", Vector3(1.8, 1.5, -0.5)); volute.rotation.x = PI * 0.5
	_pump_blade = Node3D.new(); _pump_blade.name = "Impeller"; _pump_blade.position = Vector3(1.8, 1.5, 0.0); ph.add_child(_pump_blade)
	for b in 5:
		var bl := _box(_pump_blade, Vector3(0, 0, 0), Vector3(1.9, 0.14, 0.1), _mat(Color(0.8, 0.9, 0.95), 0.35, 0.4)); bl.rotation.z = TAU * float(b) / 10.0
	_spin.append({"node": _pump_blade, "w": 0.0, "axis": 2, "pump": true})
	var pipe := _mat(Color(0.35, 0.38, 0.40), 0.5, 0.5)
	_beam(ph, Vector3(3.0, 1.0, -0.5), Vector3(11.5, 0.5, -0.5), 0.5, pipe)   # suction to the pond
	_beam(ph, Vector3(1.8, 2.3, -0.5), Vector3(1.8, 6.4, -0.5), 0.4, pipe)   # delivery up and out through the roof
	_box(ph, Vector3(-6.2, 1.2, 3.2), Vector3(1.2, 2.2, 0.8), _mat(Color(0.5, 0.52, 0.5), 0.5, 0.2), "StarterCabinet")
	var lamp := _emit_mat(Color(0.3, 1.0, 0.45), 0.0)
	var sm := SphereMesh.new(); sm.radius = 0.12; sm.height = 0.24
	_inst(ph, sm, lamp, "StarterLamp", Vector3(-6.2, 2.0, 3.65), false); _pump_lamp = lamp
	if quality != "low":
		var pl := OmniLight3D.new(); pl.position = Vector3(0, 4.0, 2.0); pl.omni_range = 14.0; pl.light_energy = 2.0; pl.light_color = Color(1.0, 0.86, 0.66); ph.add_child(pl)
	anchors["pump"] = Vector3(L11_PUMP.x, pg + 8.0, L11_PUMP.z)
	_water(-0.5, Rect2(70.0, -6.0, 36.0, 24.0), Vector2(0.0, 0.0))
	# the bus: three wires on poles behind the buildings, and the yard's lamps
	var bpoles: Array = []
	for k in 7: bpoles.append(_pole10(-62.0 + 22.0 * k, -14.0, "BusPole%d" % k, false))
	for c in 3:
		var pts: Array = []
		for p in bpoles: pts.append((p as Node3D).position + Vector3(0, L10_H - 0.1, (c - 1) * 1.05))
		_inst(_root, _run(pts, 0.04, 0.6), _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6), "BusWire%d" % c, Vector3.ZERO, false)
	anchors["bus"] = (bpoles[2] as Node3D).position + Vector3(0, L10_H + 2.0, 0)
	for p in [Vector2(-66.0, 14.0), Vector2(-24.0, 14.0), Vector2(30.0, 14.0), Vector2(46.0, 14.0)]: _lamp_post(p)
	_trees(_tree_ok11, 300.0, 8.0)

func _tree_ok11(x: float, z: float) -> float:
	if Rect2(-92.0, -32.0, 150.0, 70.0).has_point(Vector2(x, z)) or Rect2(66.0, -12.0, 44.0, 36.0).has_point(Vector2(x, z)): return 0.0
	if z < -26.0: return 0.32
	return 0.1 * smoothstep(0.0, 0.3, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))

## Rebuild the bank's cans and wiring when the count, connection or voltage state changes.
func _bank_set(count: int, conn: String, ratio: float, burst: bool) -> void:
	var key := "%d|%s|%.2f|%s" % [count, conn, ratio, str(burst)]
	if key == _bank_key: return
	_bank_key = key
	var col := Color(0.62, 0.72, 0.90)
	if burst: col = Color(0.62, 0.12, 0.08)
	else: col = col.lerp(Color(1.0, 0.45, 0.12), smoothstep(0.7, 1.0, ratio))
	_can_col = col
	for r in 3:
		var mm: MultiMesh = (_cans[r] as MultiMeshInstance3D).multimesh
		mm.instance_count = count
		for i in count:
			var c := i % BANK_COLS; var row := i / BANK_COLS
			var tf := Transform3D(Basis(), Vector3((float(c) - 6.5) * 0.5, 0.55 + 0.31, (float(row) - 4.5) * 0.5))
			mm.set_instance_transform(i, tf); mm.set_instance_color(i, col.lightened(0.08 * float((i * 7) % 3)))
		var fx := _burst_fx[r] as MeshInstance3D
		fx.visible = burst and count > 0
		if burst and count > 0: (fx.material_override as ShaderMaterial).set_shader_parameter("power", 0.7)
	_clear(_bank_wire)
	var cu := _mat(Color(0.80, 0.45, 0.25), 0.35, 0.5)
	for r in 3:   # the supply lands on each rack's back end
		var x := (r - 1) * 11.0
		_box(_bank_wire, Vector3(x, 1.5, -3.2), Vector3(0.3, 1.6, 0.3), cu, "Feed%d" % r)
		_beam(_bank_wire, Vector3(x, 2.3, -3.2), Vector3(x, 8.0 + float(r), -17.5), 0.08, _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6))
	if conn == "Y":   # a star bar across the front ends and the star point
		_box(_bank_wire, Vector3(0, 1.2, 3.4), Vector3(28.0, 0.25, 0.25), cu, "StarBar")
		var sm := SphereMesh.new(); sm.radius = 0.45; sm.height = 0.9
		_inst(_bank_wire, sm, cu, "StarPoint", Vector3(0, 1.2, 3.4))
	else:   # a ring: each rack's front end joins the next rack's, the last returns over the top
		_beam(_bank_wire, Vector3(-8.0, 1.2, 3.4), Vector3(-3.0, 1.2, 3.4), 0.12, cu)
		_beam(_bank_wire, Vector3(3.0, 1.2, 3.4), Vector3(8.0, 1.2, 3.4), 0.12, cu)
		_beam(_bank_wire, Vector3(-14.0, 1.2, 3.4), Vector3(-14.0, 3.6, 4.4), 0.12, cu); _beam(_bank_wire, Vector3(-14.0, 3.6, 4.4), Vector3(14.0, 3.6, 4.4), 0.12, cu); _beam(_bank_wire, Vector3(14.0, 3.6, 4.4), Vector3(14.0, 1.2, 3.4), 0.12, cu)
	for r in 3:
		for sx in [-3.0, 3.0]: _box(_bank_wire, Vector3((r - 1) * 11.0 + sx, 0.9, 3.0), Vector3(0.2, 1.0, 0.2), cu)

# --------------------------------------------------------------------------------------------------------------------
# L12: Over the Hill
# --------------------------------------------------------------------------------------------------------------------
func _circuit_z(c: int) -> float: return _ph12.z + 12.0 - 17.0 * float(c)
func _tower_x(k: int) -> float: return 46.0 + 50.0 * float(k)

func _build_l12() -> void:
	var lip := LIP12; var zr := _rz12(lip)
	_water(LIP_H - 1.6, Rect2(lip - 2.0 - FAR_M * 2.0, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.05, 0.0))   # the reservoir
	_water(-1.2, Rect2(lip + 1.0, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.05, 0.0))   # the river below the dam
	_build_fall(lip, zr - 5.0)
	anchors["dam"] = Vector3(lip, LIP_H + 6.0, zr - 5.0)
	var conc := _soft_mat("sand", Color(0.60, 0.59, 0.56), 0.22, 0.22, 0.0, 0.15)
	for seg in [[zr - 40.0, zr - 12.0], [zr + 2.0, zr + 30.0]]:   # the dam wall either side of the spillway
		var len: float = seg[1] - seg[0]
		_box(_root, Vector3(lip + 0.5, LIP_H * 0.5 + 1.0, (seg[0] + seg[1]) * 0.5), Vector3(6.0, LIP_H + 3.0, len), conc, "DamWall")
		_box(_root, Vector3(lip + 0.5, LIP_H + 2.6, (seg[0] + seg[1]) * 0.5), Vector3(6.4, 0.4, len + 0.4), _mat(Color(0.4, 0.4, 0.4), 0.7), "Crest")
	var ph := _build_powerhouse(_ph12)
	_build_alternator(ph, Vector3(1.5, 3.4, 0.6))
	_build_rotor(6, 0.5)
	anchors["plant"] = _ph12 + Vector3(0, 13.0, 2.0)
	_pen_a = Vector2(lip - 34.0, _rz12(lip - 34.0) + 9.0); _pen_b = Vector2(_ph12.x - 10.5, _ph12.z - 2.5)
	_build_penstock()
	# the switchyard: two step-up transformers and a gantry before the towers
	var sy := Vector3(_ph12.x + 26.0, 0.0, _ph12.z - 8.0); sy.y = ground(sy.x, sy.z)
	for k in 2:
		var tn := Node3D.new(); tn.name = "Transformer%d" % k; tn.position = sy + Vector3(0, 0, -6.0 * k); _root.add_child(tn)
		_box(tn, Vector3(0, 0.1, 0), Vector3(6.0, 0.3, 6.0), _soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2))
		var tm := _inst(tn, Props3D.transformer(), _vc_mat(0.55), "Tank"); tm.scale = Vector3.ONE * 1.6
	# the city, flattened onto the plain beyond the ridge
	_build_city()
	anchors["city"] = Vector3(_city_rect().get_center().x, ground(_city_rect().get_center().x, _city_rect().get_center().y) + 55.0, _city_rect().get_center().y)
	_line_nodes = Node3D.new(); _line_nodes.name = "Lines"; _root.add_child(_line_nodes)
	var sp: Array = Props3D.support("lattice", 30.0, 27.0)
	_tower_mesh = sp
	_trees(_tree_ok12, 700.0, 10.0)

func _tree_ok12(x: float, z: float) -> float:
	if _ph12.x - 14.0 < x and x < _ph12.x + 50.0 and absf(z - _ph12.z) < 40.0: return 0.0
	if absf(x - LIP12) < 8.0 or absf(z - _rz12(x)) < 11.0 and x < 140.0: return 0.0
	if x > _city_rect().position.x - 20.0: return 0.0
	if absf(z - (_ph12.z - 5.0)) < 28.0 and x > 20.0 and x < 660.0: return 0.0   # the lines' corridor
	var h := ground(x, z)
	return clampf(0.1 + 0.5 * smoothstep(0.0, 0.3, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5)) - 0.4 * smoothstep(60.0, 80.0, h), 0.0, 0.6)

func _build_city() -> void:
	var rc := _city_rect()
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var win := SurfaceTool.new(); win.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 22:
		var u := WorldMath.hash2(k, 1, 81); var v := WorldMath.hash2(k, 2, 81); var hh := 12.0 + 40.0 * pow(WorldMath.hash2(k, 3, 81), 2.0)
		var cx := rc.position.x + 6.0 + u * (rc.size.x - 12.0); var cz := rc.position.y + 6.0 + v * (rc.size.y - 12.0)
		var w := 8.0 + 8.0 * WorldMath.hash2(k, 4, 81); var d := 8.0 + 8.0 * WorldMath.hash2(k, 5, 81)
		var y0 := ground(cx, cz) - 0.5
		var tone := 0.30 + 0.12 * WorldMath.hash2(k, 6, 81)
		Props3D._box(st, Vector3(cx, y0 + hh * 0.5, cz), Vector3(w, hh, d), Color(tone, tone + 0.02, tone + 0.06))
		var rows := int(hh / 4.0); var cols := int(d / 3.0)
		for rr in rows:   # windows on the face towards the ridge (the camera's side)
			for cc in cols:
				if WorldMath.hash2(k * 100 + rr, cc, 82) < 0.25: continue
				var wy := y0 + 3.0 + 4.0 * float(rr); var wz := cz - d * 0.5 + 1.5 + 3.0 * float(cc)
				var o := Vector3(cx - w * 0.5 - 0.05, wy, wz)
				for tri in [[0, 2, 1], [0, 3, 2]]:   # 1128c: front faces out (-X), was into the wall
					var pp := [o, o + Vector3(0, 0, 1.4), o + Vector3(0, 2.0, 1.4), o + Vector3(0, 2.0, 0)]
					win.set_normal(Vector3.LEFT)
					for t in tri: win.add_vertex(pp[t])
	var mat := _vc_mat(0.8)
	_inst(_root, st.commit(), mat, "CityBlocks")
	_city_mat = _emit_mat(Color(1.0, 0.82, 0.5), 3.5); _city_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_inst(_root, win.commit(), _city_mat, "CityWindows", Vector3.ZERO, false)

## The circuits' towers, conductors and series platforms for `n` circuits and a series compensation of `pct` %.
func _lines_set(n: int, pct: int) -> void:
	var key := "%d|%d" % [n, pct]
	if key == _plat_key: return
	_plat_key = key
	_clear(_line_nodes); _circ.clear(); _plats = 0
	var tmat := _vc_mat(0.6); var capm := _mat(Color(0.55, 0.62, 0.75), 0.45, 0.3); var steel := _mat(Color(0.28, 0.30, 0.33), 0.5, 0.3)
	for c in n:
		var zc := _circuit_z(c)
		var root := Node3D.new(); root.name = "Circuit%d" % c; _line_nodes.add_child(root)
		var att: Array = []
		for k in 13:
			var tx := _tower_x(k)
			var tw := _inst(root, _tower_mesh[0], tmat, "Tower%d" % k, Vector3(tx, ground(tx, zc) - 0.3, zc))
			var a: Array = []
			for p in _tower_mesh[1]: a.append(tw.position + (p as Vector3))
			att.append(a)   # three points, z -2.3 / 0 / 2.3
		var plat := pct > 0
		var wires: Array = [[], [], []]
		for k in att.size():
			for w in 3: wires[w].append((att[k] as Array)[w])
			if plat and k == SERIES_AT:
				var xm := (_tower_x(k) + _tower_x(k + 1)) * 0.5; var gy := ground(xm, zc)
				for w in 3:
					var zo := (w - 1) * 2.3
					wires[w].append(Vector3(xm - 8.0, gy + 7.0, zc + zo)); wires[w].append(Vector3(xm + 8.0, gy + 7.0, zc + zo))
		var core := _mat(Color(0.55, 0.56, 0.58), 0.35, 0.5); core.emission_enabled = true; core.emission = Color(1.0, 0.55, 0.2); core.emission_energy_multiplier = 0.0
		var gmat := _hot_mat(0.0); gmat.set_shader_parameter("inflate", 0.0003)
		var cs := SurfaceTool.new(); cs.begin(Mesh.PRIMITIVE_TRIANGLES); var gs := SurfaceTool.new(); gs.begin(Mesh.PRIMITIVE_TRIANGLES)
		for w in 3:
			var run := 0.0; var pts: Array = wires[w]
			for k in pts.size() - 1:
				var a: Vector3 = pts[k]; var b: Vector3 = pts[k + 1]
				var sg := 1.8 * clampf(a.distance_to(b) / 50.0, 0.05, 1.2)
				Props3D.add_wire(cs, a, b, sg, 0.1, run, 12); Props3D.add_wire(gs, a, b, sg, 0.17, run, 12); run += a.distance_to(b)
		_inst(root, cs.commit(), core, "Conductors", Vector3.ZERO, false)
		_inst(root, gs.commit(), gmat, "Glow", Vector3.ZERO, false)
		if plat:   # the series capacitor: a deck on stilts with a block of cans per step of compensation, between two towers
			_plats += 1
			var xm := (_tower_x(SERIES_AT) + _tower_x(SERIES_AT + 1)) * 0.5; var gy := ground(xm, zc)
			var pl := Node3D.new(); pl.name = "SeriesPlatform"; pl.position = Vector3(xm, gy, zc); root.add_child(pl)
			_box(pl, Vector3(0, 5.5, 0), Vector3(18.0, 0.4, 9.0), steel, "Deck")
			for px in [-8.0, 8.0]: for pz in [-4.0, 4.0]: _box(pl, Vector3(px, 2.7, pz), Vector3(0.35, 5.4, 0.35), steel)
			var blocks := clampi(pct / 10, 1, 6)
			for b in blocks: for w in 3: _box(pl, Vector3(-6.0 + 12.0 * float(b) / float(maxi(blocks - 1, 1)), 6.5, (w - 1) * 2.6), Vector3(1.4, 1.8, 1.4), capm, "CapBlock")
		_circ.append({"root": root, "core": core, "glow": gmat, "dark": false})
	if n > 0: anchors["line"] = Vector3(_tower_x(6), ground(_tower_x(6), _circuit_z(0)) + 38.0, _circuit_z(0))
	if _plats > 0: anchors["series"] = Vector3(0.5 * (_tower_x(SERIES_AT) + _tower_x(SERIES_AT + 1)), ground(_tower_x(SERIES_AT), _circuit_z(0)) + 12.0, _circuit_z(0))
	else: anchors.erase("series")

# --------------------------------------------------------------------------------------------------------------------
# L13: the generator hall
# --------------------------------------------------------------------------------------------------------------------
const L13_PH := Vector3(0.0, 1.0, 0.0)

func _build_l13() -> void:
	_water(-1.5, Rect2(-FAR_M, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.0, 0.05))
	_ph = L13_PH
	var ph := _build_powerhouse(L13_PH)
	_build_alternator(ph, Vector3(1.5, 3.4, 0.6))
	_alt.scale = Vector3.ONE * 1.18
	_build_rotor(4, 0.7)
	# the exciter on the shaft's near end: a drum with a glowing field ring and slip rings
	var ex := Node3D.new(); ex.name = "Exciter"; ex.position = Vector3(0, 0, 1.5); _alt.add_child(ex)
	var cm := CylinderMesh.new(); cm.top_radius = 0.85; cm.bottom_radius = 0.85; cm.height = 1.5
	var drum := _inst(ex, cm, _mat(Color(0.74, 0.40, 0.22), 0.4, 0.4), "Drum", Vector3(0, 0, 0.9)); drum.rotation.x = PI * 0.5
	var shaft := CylinderMesh.new(); shaft.top_radius = 0.3; shaft.bottom_radius = 0.3; shaft.height = 0.7
	var sh := _inst(ex, shaft, _mat(Color(0.62, 0.64, 0.66), 0.3, 0.5), "Shaft", Vector3(0, 0, 0.35)); sh.rotation.x = PI * 0.5
	var ring := SurfaceTool.new(); ring.begin(Mesh.PRIMITIVE_TRIANGLES); Bench3D._ring(ring, 0.86, 1.02, 0.35, 1.45, 40, Color.WHITE)
	_exc_mat = _glow_mat(Color(1.0, 0.72, 0.32, 1.0), 0.3)
	_inst(ex, ring.commit(), _exc_mat, "FieldRing", Vector3.ZERO, false)
	_box(ph, Vector3(-6.4, 1.2, 5.0), Vector3(1.4, 2.2, 0.9), _mat(Color(0.5, 0.52, 0.5), 0.5, 0.2), "RegulatorCabinet")
	anchors["gen"] = L13_PH + Vector3(1.5, 12.8, 0.6)
	anchors["exciter"] = L13_PH + Vector3(1.5, 3.4, 3.4)
	# the step-up transformer and the pole that takes the machine's power away
	var tp := Vector3(24.0, 0.0, 2.0); tp.y = ground(tp.x, tp.z)
	var tn := Node3D.new(); tn.name = "Transformer"; tn.position = tp; _root.add_child(tn)
	_box(tn, Vector3(0, 0.1, 0), Vector3(9.0, 0.3, 9.0), _soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2))
	var tk := _inst(tn, Props3D.transformer(), _vc_mat(0.55), "Tank"); tk.scale = Vector3.ONE * 1.8
	var poles: Array = []
	for k in 4: poles.append(_pole10(40.0 + 30.0 * k, 2.0, "OutPole%d" % k, false))
	for c in 3:
		var pts: Array = []
		for p in poles: pts.append((p as Node3D).position + Vector3(0, L10_H - 0.1, (c - 1) * 1.05))
		_inst(_root, _run(pts, 0.04, 0.8), _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6), "Out%d" % c, Vector3.ZERO, false)
	_trees(_tree_ok13, 300.0, 8.0)

func _tree_ok13(x: float, z: float) -> float:
	if Rect2(-40.0, -20.0, 220.0, 40.0).has_point(Vector2(x, z)): return 0.0
	if z < -22.0: return 0.55
	return 0.2 * smoothstep(0.0, 0.3, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))

# --------------------------------------------------------------------------------------------------------------------
# The engine's numbers onto the scene
# --------------------------------------------------------------------------------------------------------------------
## The share of the neutral's heat (0..1) from the neutral current as a percentage of the phase current; a neutral past its rating is full heat.
static func neutral_heat(i_n_pct: float, load_pct: float) -> float:
	if load_pct > 100.0: return 1.0
	return pow(clampf(i_n_pct / 50.0, 0.0, 1.0), 0.8)

## The field glow (0..1) of the L13 machine from E (0.5 to 2.0 pu); no excitation set is a dark field.
static func field_glow(e_pu: float, has_e: bool) -> float:
	if not has_e: return 0.0
	return clampf((e_pu - 0.5) / 1.5, 0.0, 1.0)

func _apply_stage() -> void:
	match scn:
		"l10": _apply_l10()
		"l11": _apply_l11()
		"l12": _apply_l12()
		"l13": _apply_l13()
		_:
			if Stage8.IDS.has(scn): Stage8.apply(self)
			else: Stage7.apply(self)

func _apply_l10() -> void:
	var hs: Array = q.houses; var vlv: Dictionary = q.vLevels
	var lo := float(q.loV); var hi := float(q.hiV); var nom := float(q.nominalV)
	_house_state.clear()
	for i in 18:
		var ph := str(hs[i].phase)
		if ph != str((_drops[i] as Dictionary).ph): _set_drop(i, ph)
		var v := float((vlv[ph] as Array)[2 + i / 3])   # the voltage at this house's pole (level k + 2), as the 2D stage reads it
		var b := bulb_brightness(v, nom)
		var hm: Dictionary = _homes[i]
		var col := HOT if v > hi else lamp_colour(b, v < lo)
		(hm.mat as StandardMaterial3D).emission = col; (hm.mat as StandardMaterial3D).emission_energy_multiplier = b * WINDOW_E
		var pm: ShaderMaterial = hm.pool; pm.set_shader_parameter("tint", Color(col, 1.0)); pm.set_shader_parameter("power", b * 1.4)
		var lt = hm.light
		if lt != null: (lt as OmniLight3D).light_energy = b * HOME_LIGHT_E * 0.7; (lt as OmniLight3D).light_color = col; (lt as OmniLight3D).visible = b > 0.003
		_house_state.append({"v": v, "b": b})
		if i % 3 == 2:   # the lamp by pole k is as bright as the mean of its three homes; with none lit it is off
			var lo_b := (b + float(_house_state[i - 1].b) + float(_house_state[i - 2].b)) / 3.0
			Kit3D.set_group("l10_lamp%d" % (i / 3), lo_b > 0.003); Kit3D.set_level("l10_lamp%d" % (i / 3), lo_b)
	var h := neutral_heat(float(q.iNpct), float(q.neutral.loadPct)); var hc := heat_colour(h)
	_neutral_core.emission = hc; _neutral_core.emission_energy_multiplier = 7.0 * pow(h, 1.3)
	_neutral_core.albedo_color = Color(0.62, 0.62, 0.64).lerp(Color(0.35, 0.12, 0.08), h * 0.8)
	_neutral_glow.set_shader_parameter("tint", Color(hc, 1.0)); _neutral_glow.set_shader_parameter("power", 1.4 * pow(h, 1.2))

var _house_state: Array = []

func _apply_l11() -> void:
	var b = q.get("bank")
	var count := 0; var conn := "Y"; var ratio := 0.0; var burst := false
	if b is Dictionary:
		count = int(b.count); conn = str(b.conn); ratio = float(b.canV) / maxf(float(b.ratedV), 1.0); burst = bool(b.burst)
	_bank_set(count, conn, snappedf(ratio, 0.05), burst)
	var bus := clampf(float(q.vBusPu), 0.0, 1.3)
	var lb := bulb_brightness(bus, 1.0)
	Kit3D.set_level("yard_lamps", lb)
	for l in _lamps:
		(l.mat as StandardMaterial3D).emission_energy_multiplier = lb * LAMP_E
		if l.light != null: (l.light as OmniLight3D).light_energy = lb * 1.4
	for s in _spin:
		if bool(s.get("pump", false)): s["w"] = 7.0 if bool(q.started) else 0.0
	if _pump_lamp != null: _pump_lamp.emission_energy_multiplier = 3.0 if bool(q.started) else 0.0

func _apply_l12() -> void:
	var n := int(q.circuits); var pct := int((q.build as Dictionary).seriesPct)
	_lines_set(n, pct)
	var fired := bool(q.fired)
	for c in _circ.size():
		var ci: Dictionary = _circ[c]
		var gone := fired and c == n - 1
		ci["dark"] = gone
		var load_g := clampf(float(q.pm) / 3.0, 0.0, 1.0)
		var core: StandardMaterial3D = ci.core; var g: ShaderMaterial = ci.glow
		core.emission_energy_multiplier = 0.0 if gone else 0.4 + 1.8 * load_g
		core.albedo_color = Color(0.22, 0.22, 0.24) if gone else Color(0.62, 0.62, 0.64)
		g.set_shader_parameter("power", 0.0 if gone else 0.1 + 0.3 * load_g)
		g.set_shader_parameter("tint", Color(1.0, 0.55, 0.2, 1.0))
	var blackout := fired and not bool((q.swing as Dictionary).stable)
	_city_mat.emission_energy_multiplier = 0.15 if blackout else 3.5
	_swing_t = 0.0

func _apply_l13() -> void:
	var n: Dictionary = q.night
	var has_e: bool = n.excitation != null
	_field = field_glow(float(n.excitation) if has_e else 1.0, has_e)
	_gap_mat.set_shader_parameter("power", 0.1 + 2.3 * _field)
	for sm in _shoe_mats: sm.emission_energy_multiplier = 0.05 + 1.0 * _field
	_exc_mat.set_shader_parameter("power", 0.1 + 2.0 * _field)

## What the scene shows now (tests/stage3d_truth.gd): what each job's engine numbers became.
func report() -> Dictionary:
	if Stage8.IDS.has(scn): return Stage8.report(self)
	if Stage7.IDS.has(scn): return Stage7.report(self)
	var r := {"kind": scn}
	match scn:
		"l10":
			var dp: Array = []; var we: Array = []
			for i in _drops.size():
				var from: Vector3 = (_drops[i] as Dictionary).from; var best := ""; var bd := 1e9
				for ph in PH:
					var d := from.distance_to(_att(_poles[i / 3], ph))
					if d < bd: bd = d; best = ph
				dp.append(best if bd < 0.01 else "?")
				we.append((_homes[i].mat as StandardMaterial3D).emission_energy_multiplier)
			r["lamp_on"] = range(6).map(func(k): return Kit3D.group_on("l10_lamp%d" % k))
			r["lamp_lvl"] = range(6).map(func(k): return float(Kit3D._lvl.get("l10_lamp%d" % k, 1.0)))
			r["drop_phase"] = dp; r["window_e"] = we; r["poles"] = _poles.size(); r["homes"] = _homes.size()
			r["neutral_glow"] = _neutral_core.emission_energy_multiplier if _neutral_core != null else 0.0
			r["tags"] = _drops.map(func(d): return ((d.tag as MeshInstance3D).material_override == _pm.get(d.ph)))
		"l11":
			var cn: Array = []
			for c in _cans: cn.append((c as MultiMeshInstance3D).multimesh.instance_count)
			r["cans"] = cn; r["star"] = _bank_wire != null and _bank_wire.find_child("StarBar", false, false) != null
			r["burst"] = _burst_fx.size() > 0 and (_burst_fx[0] as MeshInstance3D).visible
			r["lamp_e"] = (_lamps[0].mat as StandardMaterial3D).emission_energy_multiplier if not _lamps.is_empty() else 0.0
			r["can_col"] = _can_col
		"l12":
			var dk: Array = []
			for c in _circ: dk.append(bool(c.dark))
			r["circuits"] = _circ.size(); r["dark"] = dk; r["platforms"] = _plats
			r["city_e"] = _city_mat.emission_energy_multiplier if _city_mat != null else 0.0
			r["glows"] = _circ.map(func(c): return (c.core as StandardMaterial3D).emission_energy_multiplier)
		"l13":
			r["field"] = _field; r["gap_glow"] = float(_gap_mat.get_shader_parameter("power")) if _gap_mat != null else 0.0
			r["exciter_glow"] = float(_exc_mat.get_shader_parameter("power")) if _exc_mat != null else 0.0
			r["shoe_e"] = _shoe_mats[0].emission_energy_multiplier if not _shoe_mats.is_empty() else 0.0
	return r

## Where a house sits on the screen (the hit rect of its tap): the eaves and the ground line, as a rect round the body.
func house_rect(i: int) -> Rect2:
	var g: Dictionary = _house_geo[i]; var hp: Vector2 = g.pos
	var gy := ground(hp.x, hp.y)
	var a := project(Vector3(hp.x - float(g.w) * 0.5, gy, hp.y)); var b := project(Vector3(hp.x + float(g.w) * 0.5, gy + float(g.h) + 2.0, hp.y))
	if a.x < -9000.0 or b.x < -9000.0: return Rect2()
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow(6.0)

# --------------------------------------------------------------------------------------------------------------------
# Camera and motion
# --------------------------------------------------------------------------------------------------------------------
## 1128c: the report frames the consequence: for a stage that names one, the camera moves to it (keeping its angle).
const REPORT_FOCUS := {"l23": ["feeder", "estate"], "l27": ["board", "estate"], "l24": ["R1", "R2", "R3", "R4"], "l25": ["gen", "breaker", "fault"], "l26": ["corridor", "control"]}
func report_focus() -> bool:
	var keys: Array = REPORT_FOCUS.get(scn, [])
	var pts: Array = []
	for k in keys: if anchors.has(k): pts.append(anchors[k])
	if pts.is_empty(): return false
	var c := Vector3.ZERO
	for p in pts: c += p
	c /= float(pts.size())
	_g_target = Vector3(c.x, ground(c.x, c.z), c.z)
	_clamp_goal()
	return true

func reset_camera() -> void:
	match scn:
		"l10": _g_target = Vector3(-8.0, 0.0, 6.0); _g_yaw = deg_to_rad(-42.0); _g_pitch = deg_to_rad(11.0); _g_dist = 82.0
		"l11": _g_target = Vector3(4.0, 0.0, 4.0); _g_yaw = deg_to_rad(-14.0); _g_pitch = deg_to_rad(20.0); _g_dist = 96.0
		"l12": _g_target = Vector3(95.0, 0.0, 28.0); _g_yaw = deg_to_rad(-56.0); _g_pitch = deg_to_rad(14.0); _g_dist = 215.0
		"l13": _g_target = Vector3(6.0, 0.0, 2.0); _g_yaw = deg_to_rad(-16.0); _g_pitch = deg_to_rad(10.0); _g_dist = 50.0
		_:
			var cm: Array = Stage8.camera(scn) if Stage8.IDS.has(scn) else Stage7.camera(scn)
			_g_target = cm[0]; _g_yaw = deg_to_rad(float(cm[1])); _g_pitch = deg_to_rad(float(cm[2])); _g_dist = float(cm[3])
	var vp := get_viewport()
	if vp != null:
		var vs := vp.get_visible_rect().size
		if vs.y > 0.0: _g_dist *= clampf((16.0 / 9.0) / (vs.x / vs.y), 1.0, 1.4)
	_dist_default = _g_dist
	_g_target.y = ground(_g_target.x, _g_target.z) + 4.0
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist
	_apply_camera()

func _process(dt: float) -> void:
	super._process(dt)
	if not visible or field == null: return
	if Stage7.IDS.has(scn): Stage7.process(self, dt)
	if Stage8.IDS.has(scn): Stage8.process(self, dt)
	if OS.has_environment("CB_FRAMETIME"):
		var vp := get_viewport().get_viewport_rid()
		if not _measuring: RenderingServer.viewport_set_measure_render_time(vp, true); _measuring = true
		_ft_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp); _ft_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(); _ft_n += 1; _ft_ms += dt * 1000.0
		if _t - _ft_at > 2.0 and _t > 6.0:
			print("FRAMETIME res=%dx%d gpu_ms=%.2f cpu_render_ms=%.2f frame_ms=%.2f adapter=%s quality=%s level=%s" % [get_viewport().size.x, get_viewport().size.y, _ft_gpu / _ft_n, _ft_cpu / _ft_n, _ft_ms / _ft_n, RenderingServer.get_video_adapter_name(), quality, scn])
			_ft_at = _t; _ft_gpu = 0.0; _ft_cpu = 0.0; _ft_n = 0; _ft_ms = 0.0
	for s in _spin:
		var n: Node3D = s.node
		var a := 0.0 if CbSettings.reduced_motion else _t * float(s.w)
		if int(s.axis) == 0: n.rotation.x = a
		else: n.rotation.z = a
	if scn == "l13" and _rotor != null: _rotor.rotation.z = -(_t * 500.0 / 60.0 * TAU / SLOWMO) if not CbSettings.reduced_motion else 0.3
	if scn == "l12" and _rotor != null and not q.is_empty():
		var ang := float(q.delta0)
		var sw: Dictionary = q.swing; var tS: Array = sw.tS; var dd: Array = sw.deltaDeg
		if bool(q.fired) and not tS.is_empty():   # the swing replays once the trip has happened, then rests at its last angle
			var t := fmod(_t, float(tS[tS.size() - 1]) + 1.0); var idx := 0
			for i in tS.size(): if float(tS[i]) <= t: idx = i
			ang = float(dd[idx]) if t < float(tS[tS.size() - 1]) else float(dd[dd.size() - 1])
		_rotor.rotation.z = -deg_to_rad(ang) / 3.0 - (0.0 if CbSettings.reduced_motion else _t * 0.6)
	if scn == "l11" and not _burst_fx.is_empty() and (_burst_fx[0] as MeshInstance3D).visible:
		for fx in _burst_fx: ((fx as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("power", 0.45 + 0.35 * sin(_t * 9.0))
