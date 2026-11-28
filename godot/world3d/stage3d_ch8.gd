class_name Stage8
extends RefCounted
## Chapter 8's six jobs as one 11 kV countryside feeder for Stage3D (which keeps the sky, the camera and the helpers; this file holds what is particular to L31 to L36).
## Display only: every number is the engine's `ch8Study` (and `ch8Kit`, handed over as q.kit), the arithmetic only maps numbers to light, colour, thickness and count.
## One kit: a lane across farmland with wood poles on its north side, three 11 kV conductors, villages and a farm at the nodes (a house is drawn per 40 customers,
## at least three, at most ten), a pole transformer at every node, a zone substation at the head. Each job dresses it from its own numbers:
## L31 the 16 km trunk (N1-N5) drawn compressed: the wire of each section is as thick as its ampacity (and glows with its loading), a pole-mounted regulator of three
##   tanks where one is placed, each village's windows follow its customers' peak voltage (amber under the band), the pole transformers show their off-load tap.
## L32 the trunk T1-T4 and spurs P1-P3: sectionalisers, spur fuses and the tie switch where placed; after the run each section's village is dimmed by its share of the
##   year's customer-minutes and the section most to blame carries a beacon.
## L33 the recloser at the head and a fuse cutout on each spur; after the run a saved fuse hangs closed and green, a blown one drops open and red with its village dark.
## L34 the zone substation: bays and transformers, the bus-section breaker, the survivor's tank glowing with the engine's hot-spot, the tie, a town whose homes dim with demand response.
## L35 the feeder at noon: rooftop panels on the villages (one panel stands for 20 kW), the noon voltage as window and conductor glow, the tap changer's step, the volt-var inverters.
## L36 the exam feeder from the givens: three sections, their devices, the far end's windows after the run.

const IDS := ["l31", "l32", "l33", "l34", "l35", "l36"]
const WINDOW_E := 6.0                # Bench3D.WINDOW_E: a window at brightness 1
const KW_PER_PANEL := 20.0           # L35: one panel drawn stands for this many kW of the connected PV
const HOUSE_CUSTOMERS := 40.0        # one house drawn per this many customers
const POLE_SP := 24.0
const HEAD_X := -166.0               # where the feeder leaves the substation
const SPAN := 370.0                  # the trunk is drawn this long, whatever its km
const SPUR_M := 25.0                 # L32: metres drawn per km of spur
const NAMES := {"l31": "N", "l35": "N"}
const FENCE := Color(0.55, 0.56, 0.58)
const TAPS_PX := 0.45                # a tap pointer moves this far (m) at the end of a +-5 % scale
const BLAME := Color(1.0, 0.25, 0.15)
const SAVED := Color(0.3, 1.0, 0.45)
const OPEN := Color(1.0, 0.18, 0.1)
const IDLE := Color(1.0, 0.7, 0.1)

static var _hm: Dictionary = {}
static var _barn: Array = []

static func sky_minute(scn: String) -> float:
	return 720.0 if scn == "l35" else 1110.0   # L35 is the feeder at noon; the rest stand at dusk, when the windows are what you read

static func zc(x: float) -> float: return 12.0 * sin(x / 75.0) + 5.0 * sin(x / 29.0 + 1.0)   # the lane's centre line
static func houses_for(customers: int) -> int: return clampi(ceili(float(customers) / HOUSE_CUSTOMERS), 3, 10)
static func _pa(p: Node3D, key: String) -> Vector3: return p.position + p.basis * (Stage3D.L10_ATT[key] as Vector3)
static func _pz(x: float) -> float: return zc(x) - 5.5   # the poles stand on the lane's north verge

# --------------------------------------------------------------------------------------------------------------------
# Layout: where everything stands, decided from the engine's lists before the land is made
# --------------------------------------------------------------------------------------------------------------------
static func prepare(s: Stage3D) -> void:
	var d := {"pads": [], "roads": []}
	s.d8 = d
	var q: Dictionary = s.q
	var pads: Array = d.pads
	match s.scn:
		"l31", "l35", "l36":
			var secs: Array = q.tree if s.scn != "l36" else q.givens.sections
			var total := 0.0
			for n in secs: total += float(n.km)
			var xs: Array = []; var cum := 0.0
			for n in secs: cum += float(n.km); xs.append(HEAD_X + SPAN * cum / total)
			d["xs"] = xs; d["total"] = total
			d["play"] = Rect2(-250.0, -90.0, 520.0, 180.0)
			pads.append(Rect2(HEAD_X - 50.0, zc(HEAD_X - 30.0) - 26.0, 52.0, 44.0))
			for x in xs: pads.append(Rect2(float(x) - 36.0, zc(float(x)) - 32.0, 72.0, 62.0))
		"l32":
			var secs: Array = q.sections; var by := {}
			for sc in secs: by[str(sc.id)] = sc
			var tk := 0.0
			for id in ["T1", "T2", "T3", "T4"]: tk += float(by[id].km)
			var b: Array = [HEAD_X]; var x := HEAD_X
			for id in ["T1", "T2", "T3", "T4"]: x += SPAN * float(by[id].km) / tk; b.append(x)
			d["b"] = b; d["by"] = by
			d["play"] = Rect2(-250.0, -80.0, 520.0, 240.0)
			pads.append(Rect2(HEAD_X - 50.0, zc(HEAD_X - 30.0) - 26.0, 52.0, 44.0))
			for k in 4: pads.append(Rect2((float(b[k]) + float(b[k + 1])) * 0.5 - 36.0, zc((float(b[k]) + float(b[k + 1])) * 0.5) - 32.0, 72.0, 62.0))
			for sp in ["P1", "P2", "P3"]:
				var par := int(str(by[sp].parent).trim_prefix("T")); var sx: float = b[par]
				var ln := SPUR_M * float(by[sp].km); var z0 := zc(sx) + 9.0
				d.roads.append([Vector2(sx, z0), Vector2(sx, z0 + ln)])
				pads.append(Rect2(sx - 30.0, z0 + ln - 30.0, 60.0, 58.0))
			pads.append(Rect2(b[4] + 20.0, zc(b[4] + 60.0) - 26.0, 90.0, 44.0))
		"l33":
			d["play"] = Rect2(-250.0, -80.0, 520.0, 230.0)
			d["sx"] = [-60.0, 30.0, 120.0]
			pads.append(Rect2(HEAD_X - 50.0, zc(HEAD_X - 30.0) - 26.0, 52.0, 44.0))
			for k in 3:
				var sx: float = d.sx[k]; var z0 := zc(sx) + 9.0
				d.roads.append([Vector2(sx, z0), Vector2(sx, z0 + 80.0)])
				pads.append(Rect2(sx - 30.0, z0 + 50.0, 60.0, 58.0))
			pads.append(Rect2(196.0 - 36.0, zc(196.0) - 32.0, 72.0, 62.0))
		"l34":
			d["play"] = Rect2(-140.0, -130.0, 330.0, 190.0)
			pads.append(Rect2(-56.0, -44.0, 112.0, 88.0))
			pads.append(Rect2(-120.0, -118.0, 240.0, 56.0))
			pads.append(Rect2(114.0, -40.0, 40.0, 36.0))

static func play(s: Stage3D) -> Rect2: return s.d8.play

# --------------------------------------------------------------------------------------------------------------------
# Land: farmland, hedgerows and woods round the lane; the hills climb to the north
# --------------------------------------------------------------------------------------------------------------------
static func ground(s: Stage3D, x: float, z: float) -> float:
	var d: Dictionary = s.d8
	var h := 0.7 + 2.0 * s._n01(x * 0.45, z * 0.45) + 0.8 * s._n01(x * 0.09 + 40.0, z * 0.09)
	var zl := zc(x) if s.scn != "l34" else 0.0
	var n := z - zl
	h += 24.0 * smoothstep(60.0, 190.0, -n) * (0.45 + 0.55 * s._n01(x * 0.12, z * 0.12)) + 9.0 * smoothstep(120.0, 280.0, n) * s._n01(x * 0.07 + 9.0, z * 0.07) + s._far(x, z)
	if d.has("pads"):
		for r in d.pads: h = lerpf(h, 1.0, s._pad(x, z, r as Rect2, 10.0))
	return h

static func splat(s: Stage3D, x: float, z: float, h: float) -> Array:
	var d: Dictionary = s.d8
	var wood := smoothstep(0.05, 0.35, s._nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))
	var zl := zc(x) if s.scn != "l34" else 0.0
	var n := z - zl
	var f := maxf(wood * 0.55, smoothstep(50.0, 130.0, -n)) * smoothstep(20.0, 50.0, absf(n)) if s.scn != "l34" else maxf(wood * 0.55, smoothstep(50.0, 130.0, -n))
	var r := smoothstep(30.0, 44.0, h)
	var c := Color(1.0 - f - r, f, r, 0.0)
	var paved := 0.0
	if s.scn != "l34": paved = (1.0 - smoothstep(2.2, 3.6, absf(n))) * (1.0 - smoothstep(280.0, 300.0, absf(x)))
	else: paved = maxf(s._pad(x, z, Rect2(-56.0, -44.0, 112.0, 88.0), 3.0), s._pad(x, z, Rect2(-120.0, -118.0, 240.0, 56.0), 3.0) * 0.6)
	for rd in d.get("roads", []):
		paved = maxf(paved, 1.0 - smoothstep(2.2, 3.6, Bench3D._seg_d(Vector2(x, z), rd[0] as Vector2, rd[1] as Vector2)))
	for rc in d.get("pads", []): paved = maxf(paved, s._pad(x, z, (rc as Rect2).grow(-10.0), 6.0) * 0.45)
	return [c, 0.0, paved]

static func tree_ok(s: Stage3D, x: float, z: float) -> float:
	var d: Dictionary = s.d8
	var zl := zc(x) if s.scn != "l34" else 0.0
	var n := z - zl
	if s.scn != "l34" and absf(n) < 30.0: return 0.0
	for r in d.get("pads", []): if (r as Rect2).grow(12.0).has_point(Vector2(x, z)): return 0.0
	for rd in d.get("roads", []): if Bench3D._seg_d(Vector2(x, z), rd[0] as Vector2, rd[1] as Vector2) < 12.0: return 0.0
	var hedge := 1.0 - smoothstep(0.0, 3.0, absf(fposmod(z + 40.0, 90.0) - 45.0))
	return clampf(0.1 + 0.5 * smoothstep(40.0, 120.0, -n) + 0.25 * hedge, 0.0, 0.7)

static func camera(scn: String) -> Array:   # [target, yaw deg, pitch deg, dist m]
	match scn:
		"l32": return [Vector3(10.0, 0.0, 40.0), -38.0, 18.0, 365.0]
		"l33": return [Vector3(-5.0, 0.0, 40.0), -38.0, 18.0, 350.0]
		"l34": return [Vector3(-12.0, 0.0, 0.0), -30.0, 14.0, 105.0]   # 11-28: the village comes out from behind the charts
	return [Vector3(-20.0, 0.0, 10.0), -38.0, 17.0, 345.0]

# --------------------------------------------------------------------------------------------------------------------
# Kit: poles, conductors, villages, a farm, the substation, devices
# --------------------------------------------------------------------------------------------------------------------
static func _pole(s: Stage3D, x: float, z: float, nm: String, rot := 0.0) -> Node3D:
	var p: Node3D = s._pole10(x, z, nm, false)
	p.rotation.y = rot
	return p

## Three conductors through `poles` (radius r), one node with the three runs.
static func _wire(s: Stage3D, poles: Array, r: float, mat: Material, nm: String, parent: Node3D = null) -> Node3D:
	var n := Node3D.new(); n.name = nm; (parent if parent != null else s._root).add_child(n)
	for c in 3:
		var pts: Array = []
		for p in poles: pts.append(_pa(p as Node3D, Stage3D.PH[c]))
		s._inst(n, s._run(pts, r, 0.8), mat, "W%d" % c, Vector3.ZERO, false)
	return n

## The glow round the same three runs (a shader tube that keeps its width at distance).
static func _glow(s: Stage3D, poles: Array, r: float, gm: Material, nm: String) -> Node3D:
	var n := Node3D.new(); n.name = nm; s._root.add_child(n)
	for c in 3:
		var pts: Array = []
		for p in poles: pts.append(_pa(p as Node3D, Stage3D.PH[c]))
		s._inst(n, s._run(pts, r * 1.6, 0.8), gm, "G%d" % c, Vector3.ZERO, false)
	return n

## A pale tube round a plain conductor that keeps a few pixels of width at distance, so the line reads from across the farmland.
static func _sheen(s: Stage3D, poles: Array, nm: String) -> void:
	var gm: ShaderMaterial = s._glow_mat(Color(0.8, 0.86, 0.95, 1.0), 0.3); gm.set_shader_parameter("inflate", 0.00018)
	_glow(s, poles, 0.1, gm, nm)

static func _alu(s: Stage3D) -> StandardMaterial3D:
	var m: StandardMaterial3D = s._mat(Color(0.56, 0.58, 0.62), 0.4, 0.55)
	return m

static func _win_mat() -> StandardMaterial3D:
	var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.13, 0.17, 0.25); wm.metallic = 0.3; wm.roughness = 0.2; wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	wm.emission_enabled = true; wm.emission = Bench3D.WARM; wm.emission_energy_multiplier = 0.0
	return wm

static func _house_meshes(variant: int) -> Array:
	if _hm.has(variant): return _hm[variant]
	var v := (float(variant) + 0.5) / 6.0
	var w := 6.0 + 1.6 * v; var dd := 5.0 + 1.0 * v; var h := 3.0 + 0.6 * v
	var cols: Array = Bench3D._house_cols(v)
	var r := [Bay3D.house_mesh(w, dd, h, 2.0, cols[0], cols[1]), Bay3D.windows_mesh(w, dd, h), Vector3(w, dd, h)]
	_hm[variant] = r
	return r

## A village of `n` houses either side of the lane round x = cx. Its windows are one material (or one a house with per_home) and, above the low tier, one light.
static func _village(s: Stage3D, key: String, cx: float, n: int, per_home := false, cz_off := 0.0, lane_z := NAN) -> Dictionary:
	var vn := Node3D.new(); vn.name = "Village_" + key; s._root.add_child(vn)
	var shared := _win_mat(); var mats: Array = [] if per_home else [shared]; var homes: Array = []
	var per := (n + 1) / 2; var seed_ := int(absf(cx) * 3.0) + int(key.unicode_at(0))
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var k := i / 2
		var hx := cx + (float(k) - float(per - 1) * 0.5) * 12.5 + (WorldMath.hash2(i, seed_, 31) - 0.5) * 2.0
		var zl := zc(hx) if is_nan(lane_z) else lane_z
		var hz := zl + side * (14.0 + 3.0 * WorldMath.hash2(i, seed_, 32)) + cz_off
		var hm: Array = _house_meshes(int(WorldMath.hash2(i, seed_, 33) * 6.0) % 6)
		var hn := Node3D.new(); hn.name = "Home%d" % i; hn.position = Vector3(hx, s.ground(hx, hz) - 0.1, hz); hn.rotation.y = PI if side > 0.0 else 0.0; vn.add_child(hn)
		var wm: StandardMaterial3D = shared
		if per_home: wm = _win_mat(); mats.append(wm)
		s._inst(hn, hm[0], s._vc_mat(0.9), "Body")
		s._inst(hn, hm[1], wm, "Windows", Vector3.ZERO, false)
		homes.append({"node": hn, "mat": wm, "dim": (hm[2] as Vector3)})
	var lt: OmniLight3D = null
	var lz := zc(cx) if is_nan(lane_z) else lane_z
	if s.quality != "low":
		lt = OmniLight3D.new(); lt.omni_range = 46.0; lt.omni_attenuation = 1.2; lt.light_specular = 0.2; lt.position = Vector3(cx, s.ground(cx, lz) + 7.0, lz + cz_off); lt.light_energy = 0.0; vn.add_child(lt)
	var grp := "v8_%s_%d" % [key, int(cx)]   # 1128c: street lamps on the lane, on and off with the village
	for sx in [-1.0, 1.0]:
		var lx: float = cx + float(sx) * float(per) * 3.2
		var lzz: float = (zc(lx) if is_nan(lane_z) else lane_z) + 6.0 + cz_off
		Kit3D.street_lamp(vn, Vector3(lx, s.ground(lx, lzz) - 0.1, lzz), PI, s.quality, grp)
	return {"node": vn, "mats": mats, "homes": homes, "light": lt, "cx": cx, "cz": lz + cz_off, "group": grp}

static func _set_village(vg: Dictionary, e: float, col: Color) -> void:
	for m in vg.mats: (m as StandardMaterial3D).emission = col; (m as StandardMaterial3D).emission_energy_multiplier = e
	var lt: OmniLight3D = vg.light
	if lt != null: lt.light_energy = e / WINDOW_E * Bench3D.HOME_LIGHT_E * 1.6; lt.light_color = col; lt.visible = e > 0.02
	if vg.has("group"): Kit3D.set_group(str(vg.group), e > 0.02); Kit3D.set_level(str(vg.group), e / WINDOW_E)

## The lamp a customer voltage makes: [window emission, colour].
static func _lamp(v: float, nom: float, lo: float) -> Array:
	var b := Bench3D.bulb_brightness(v, nom)
	return [b * WINDOW_E, Bench3D.lamp_colour(b, v < lo)]

## A pole transformer on `pole`: the can, three bushings, and a tap plate with a pointer that stands left of centre for a negative tap and right for a positive one.
static func _can(s: Stage3D, pole: Node3D) -> Dictionary:
	var can := s._inst(pole, s._cyl_mesh(Vector3.ZERO, Vector3(0, 1.8, 0), 0.8, Color(0.46, 0.5, 0.48), 16), s._vc_mat(0.55), "TxCan", Vector3(1.1, Stage3D.L10_H - 5.6, 0.0))
	for c in 3: s._inst(can, s._cyl_mesh(Vector3(0, 1.8, (c - 1) * 0.4), Vector3(0, 2.5, (c - 1) * 0.4), 0.09, Color(0.78, 0.5, 0.36), 6), s._vc_mat(0.5), "Bushing%d" % c)
	s._box(can, Vector3(0.82, 0.9, 0.0), Vector3(0.06, 0.55, 1.1), s._mat(Color(0.82, 0.84, 0.86), 0.5, 0.3), "TapPlate")
	var ptr := s._box(can, Vector3(0.87, 0.9, 0.0), Vector3(0.07, 0.42, 0.14), s._emit_mat(Color(1.0, 0.7, 0.1), 3.0), "TapPointer")
	return {"can": can, "ptr": ptr}

static func _set_tap(c: Dictionary, tap_pct: float) -> void:
	var ptr: MeshInstance3D = c.ptr
	ptr.position.z = clampf(tap_pct / 5.0, -1.0, 1.0) * TAPS_PX
	(ptr.material_override as StandardMaterial3D).emission = Color(1.0, 0.7, 0.1) if tap_pct == 0.0 else (Color(0.85, 0.42, 0.2) if tap_pct > 0.0 else Color(0.3, 0.6, 1.0))

## A barn, a silo and a haystack off the lane, so the land is lived in between the villages.
static func _farm(s: Stage3D, x: float, z: float, rot: float, nm: String) -> void:
	if _barn.is_empty():
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		Props3D._box(st, Vector3(0, 3.0, 0), Vector3(14.0, 6.0, 8.0), Color(0.62, 0.22, 0.16))
		var a := Vector3(-7.4, 6.0, -4.4); var b := Vector3(7.4, 6.0, -4.4); var c := Vector3(7.4, 6.0, 4.4); var dd := Vector3(-7.4, 6.0, 4.4)
		var t0 := Vector3(-7.4, 9.0, 0); var t1 := Vector3(7.4, 9.0, 0)
		st.set_color(Color(0.34, 0.34, 0.37))
		Props3D._tri(st, a, t1, b); Props3D._tri(st, a, t0, t1); Props3D._tri(st, dd, c, t1); Props3D._tri(st, dd, t1, t0)
		st.set_color(Color(0.62, 0.22, 0.16))
		Props3D._tri(st, Vector3(-7.0, 6.0, -4.0), Vector3(-7.0, 6.0, 4.0), Vector3(-7.0, 8.8, 0)); Props3D._tri(st, Vector3(7.0, 6.0, 4.0), Vector3(7.0, 6.0, -4.0), Vector3(7.0, 8.8, 0))
		Props3D._box(st, Vector3(0, 2.2, 4.05), Vector3(4.0, 4.4, 0.1), Color(0.86, 0.82, 0.74))
		_barn = [Props3D._commit(st), s._cyl_mesh(Vector3.ZERO, Vector3(0, 11.0, 0), 2.2, Color(0.74, 0.76, 0.78), 14), s._cyl_mesh(Vector3.ZERO, Vector3(0, 2.6, 0), 2.6, Color(0.82, 0.7, 0.34), 10)]
	var n := Node3D.new(); n.name = nm; n.position = Vector3(x, s.ground(x, z) - 0.1, z); n.rotation.y = rot; s._root.add_child(n)
	s._inst(n, _barn[0], s._vc_mat(0.85), "Barn")
	s._inst(n, _barn[1], s._vc_mat(0.5), "Silo", Vector3(10.0, 0, -2.0))
	s._inst(n, _barn[2], s._vc_mat(0.95), "Haystack", Vector3(-11.0, 0, 5.0))

## The zone substation at the head of a feeder: a fenced pad, a lattice tower with the incoming line, a gantry, a breaker and the transformer. Returns its parts.
static func _head(s: Stage3D, nm: String) -> Dictionary:
	var cx := HEAD_X - 26.0; var cz := zc(HEAD_X - 30.0) - 2.0
	var n := Node3D.new(); n.name = nm; n.position = Vector3(cx, s.ground(cx, cz), cz); s._root.add_child(n)
	s._box(n, Vector3(0, 0.12, 0), Vector3(34.0, 0.3, 26.0), s._soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2), "Pad")
	var fm := s._mat(FENCE, 0.5, 0.3)
	for sx in [-17.0, 17.0]: for k in 5: s._box(n, Vector3(sx, 1.1, -13.0 + 6.5 * k), Vector3(0.1, 2.2, 0.1), fm, "Post")
	for sz in [-13.0, 13.0]: for k in 4: s._box(n, Vector3(-17.0 + 11.3 * k, 1.1, sz), Vector3(0.1, 2.2, 0.1), fm, "Post")
	for sx in [-17.0, 17.0]: s._box(n, Vector3(sx, 2.0, 0.0), Vector3(0.06, 0.06, 26.0), fm, "Rail")
	for sz in [-13.0, 13.0]: s._box(n, Vector3(0, 2.0, sz), Vector3(34.0, 0.06, 0.06), fm, "Rail")
	var tk := s._inst(n, Props3D.transformer(), s._vc_mat(0.55), "Tank", Vector3(4.0, 0.3, 1.0)); tk.scale = Vector3.ONE * 2.6
	var gt := s._inst(n, Props3D.gantry(), s._vc_mat(0.5), "Gantry", Vector3(-8.0, 0.3, -6.0)); gt.scale = Vector3.ONE * 1.1
	var bk := s._inst(n, Props3D.breaker(), s._vc_mat(0.55), "Breaker", Vector3(11.0, 0.3, 3.0)); bk.scale = Vector3.ONE * 1.1
	# the incoming line: one lattice tower behind the pad, three wires to the gantry
	var sp: Array = Props3D.support("lattice", 24.0, 21.0)
	var tx := cx - 52.0; var tz := cz
	var tw := s._inst(s._root, sp[0], s._vc_mat(0.6), "IncomerTower", Vector3(tx, s.ground(tx, tz) - 0.3, tz))
	var hv := s._mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for c in 3:
		var a: Vector3 = tw.position + (sp[1][c] as Vector3)
		var b := n.position + Vector3(-8.0 + 2.5 * (c - 1), 6.8, -6.0)
		s._inst(s._root, s._run([a, b], 0.07, 1.2), hv, "Incomer%d" % c, Vector3.ZERO, false)
	Kit3D.flood_mast(n, Vector3(-17.5, 0.0, 13.5), Vector3(0, 0, -2.0), s.quality, 12.0)   # 1128c
	Kit3D.flood_mast(n, Vector3(17.5, 0.0, -13.5), Vector3(0, 0, 2.0), s.quality, 12.0)
	Kit3D.aviation(s._root, tw.position + Vector3(0, 24.6, 0), s.quality)
	# the feeder breaker's lead out to the first pole
	return {"node": n, "tank": tk, "gantry": gt, "breaker": bk, "pos": n.position}

## The first pole of the feeder, with a jumper from the substation's breaker.
static func _head_pole(s: Stage3D, hd: Dictionary) -> Node3D:
	var p := _pole(s, HEAD_X, _pz(HEAD_X), "HeadPole")
	var from: Vector3 = (hd.pos as Vector3) + Vector3(11.0, 5.4, 3.0)
	var hv: Material = s._mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for c in 3: s._inst(s._root, s._run([from + Vector3(0, 0, (c - 1) * 0.5), _pa(p, Stage3D.PH[c])], 0.05, 0.9), hv, "Lead%d" % c, Vector3.ZERO, false)
	return p

## Poles from `prev` (an existing pole) to x_to, one every ~POLE_SP: returns [prev, ..., last].
static func _chain(s: Stage3D, prev: Node3D, x_to: float, nm: String) -> Array:
	var x0 := prev.position.x
	var n := maxi(1, ceili(absf(x_to - x0) / POLE_SP))
	var out: Array = [prev]
	for k in range(1, n + 1):
		var x := lerpf(x0, x_to, float(k) / float(n))
		out.append(_pole(s, x, _pz(x), "%s_%d" % [nm, k]))
	return out

## Three tanks on a platform between two stub poles, a copper top on each: the regulator hangs in the line at the middle of its section.
static func _regulator(s: Stage3D, x: float, nm: String) -> Node3D:
	var n := Node3D.new(); n.name = nm; n.position = Vector3(x, 0, _pz(x) + 2.8); s._root.add_child(n)
	n.position.y = s.ground(x, _pz(x) + 2.8)
	for sx in [-3.0, 3.0]: s._inst(n, s._cyl_mesh(Vector3.ZERO, Vector3(0, 7.0, 0), 0.17, Color(0.36, 0.27, 0.18), 8), s._vc_mat(0.85), "StubPole", Vector3(sx, -0.2, 0))
	s._box(n, Vector3(0, 6.6, 0), Vector3(7.0, 0.3, 1.6), s._mat(Color(0.4, 0.42, 0.45), 0.5, 0.4), "Platform")
	var tank := s._mat(Color(0.52, 0.56, 0.52), 0.5, 0.35); var cu := s._mat(Color(0.8, 0.45, 0.25), 0.35, 0.5)
	for k in 3:
		var tx := -2.0 + 2.0 * float(k)
		s._inst(n, s._cyl_mesh(Vector3.ZERO, Vector3(0, 2.2, 0), 0.8, Color(0.52, 0.56, 0.52), 14), tank, "Tank%d" % k, Vector3(tx, 6.75, 0))
		s._inst(n, s._cyl_mesh(Vector3.ZERO, Vector3(0, 0.45, 0), 0.5, Color(0.8, 0.45, 0.25), 12), cu, "Top%d" % k, Vector3(tx, 8.95, 0))
	n.visible = false
	return n

## A sectionaliser / switch on a pole: a box with a hook-stick handle (manual) or an antenna and a green lamp (remote); `kind` shows one of them.
static func _switch(s: Stage3D, pole: Node3D, nm: String) -> Node3D:
	var n := Node3D.new(); n.name = nm; n.position = Vector3(0.0, Stage3D.L10_H - 3.4, 1.9); pole.add_child(n)
	var m := Node3D.new(); m.name = "manual"; n.add_child(m)
	s._box(m, Vector3.ZERO, Vector3(1.0, 1.5, 0.9), s._mat(Color(0.8, 0.45, 0.25), 0.4, 0.4), "Box")
	s._box(m, Vector3(0.0, -1.5, 0.0), Vector3(0.1, 1.6, 0.1), s._mat(Color(0.7, 0.7, 0.72), 0.4, 0.5), "Handle")
	var r := Node3D.new(); r.name = "remote"; n.add_child(r)
	s._box(r, Vector3.ZERO, Vector3(1.0, 1.5, 0.9), s._mat(Color(0.2, 0.6, 0.95), 0.4, 0.4), "Box")
	s._box(r, Vector3(0.3, 1.5, 0.0), Vector3(0.06, 1.5, 0.06), s._mat(Color(0.7, 0.7, 0.72), 0.4, 0.5), "Antenna")
	s._inst(r, SphereMesh.new(), s._emit_mat(SAVED, 3.0), "Lamp", Vector3(0.0, 0.95, 0.0), false).scale = Vector3.ONE * 0.5
	m.visible = false; r.visible = false
	return n

static func _set_switch(sw: Node3D, kind: String) -> void:
	(sw.get_node("manual") as Node3D).visible = kind == "manual"
	(sw.get_node("remote") as Node3D).visible = kind == "remote"

static func _switch_kind(sw: Node3D) -> String:
	if (sw.get_node("manual") as Node3D).visible: return "manual"
	if (sw.get_node("remote") as Node3D).visible: return "remote"
	return "none"

## A fuse cutout set on a pole: three porcelain tubes hanging at an angle from the crossarm (closed), each with a lamp; `open` swings them down and red.
static func _cutouts(s: Stage3D, pole: Node3D, nm: String) -> Dictionary:
	var n := Node3D.new(); n.name = nm; n.position = Vector3(0.0, Stage3D.L10_H - 2.6, 0.0); pole.add_child(n)
	var tubes: Array = []; var lamp := s._emit_mat(IDLE, 3.0)
	for c in 3:
		var t := Node3D.new(); t.name = "Cutout%d" % c; t.position = Vector3(0.0, 0.0, (c - 1) * 1.05); n.add_child(t)
		s._inst(t, s._cyl_mesh(Vector3.ZERO, Vector3(0, -1.5, 0), 0.14, Color(0.82, 0.8, 0.74), 8), s._vc_mat(0.4), "Tube")
		t.rotation.x = 0.0; tubes.append(t)
	var sm := SphereMesh.new(); sm.radius = 0.3; sm.height = 0.6
	s._inst(n, sm, lamp, "Lamp", Vector3(1.0, 0.6, 0.0), false)
	return {"node": n, "tubes": tubes, "lamp": lamp}

static func _set_cutouts(c: Dictionary, state: String) -> void:   # "idle" and "saved": closed; "open": a blown fuse's tube drops
	var open := state == "open"
	for k in (c.tubes as Array).size(): ((c.tubes as Array)[k] as Node3D).rotation.x = (1.1 if k % 2 == 0 else -1.1) if open else 0.0
	(c.node as Node3D).set_meta("state", state)
	(c.lamp as StandardMaterial3D).emission = OPEN if open else (SAVED if state == "saved" else IDLE)

## The recloser at the head: a grey tank on a platform, a controller box, a lamp.
static func _recloser(s: Stage3D, pole: Node3D) -> Dictionary:
	var n := Node3D.new(); n.name = "Recloser"; n.position = Vector3(1.0, Stage3D.L10_H - 4.0, 0.0); pole.add_child(n)
	s._inst(n, s._cyl_mesh(Vector3.ZERO, Vector3(0, 1.7, 0), 0.85, Color(0.6, 0.62, 0.66), 14), s._vc_mat(0.45), "Tank", Vector3(0.9, 0.0, 0.0))
	s._box(n, Vector3(0.95, 2.0, 0.0), Vector3(1.9, 0.3, 1.9), s._mat(Color(0.4, 0.42, 0.45), 0.5, 0.4), "Cap")
	for c in 3: s._inst(n, s._cyl_mesh(Vector3(0, 0, 0), Vector3(0, 0.9, 0), 0.08, Color(0.78, 0.5, 0.36), 6), s._vc_mat(0.5), "Bushing%d" % c, Vector3(0.9, 2.1, (c - 1) * 0.55))
	s._box(n, Vector3(0.0, -2.0, 0.7), Vector3(1.0, 1.6, 0.8), s._mat(Color(0.28, 0.3, 0.33), 0.5, 0.3), "Controller")
	var lamp := s._emit_mat(IDLE, 3.5); var sm := SphereMesh.new(); sm.radius = 0.28; sm.height = 0.56
	s._inst(n, sm, lamp, "Lamp", Vector3(0.9, 3.1, 0.0), false)
	return {"node": n, "lamp": lamp}

# --------------------------------------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------------------------------------
static func build(s: Stage3D) -> void:
	var d: Dictionary = s.d8
	s._water(-1.5, Rect2(-Bench3D.FAR_M, -Bench3D.FAR_M, Bench3D.FAR_M * 2.0, Bench3D.FAR_M * 2.0), Vector2(0.0, 0.05))
	match s.scn:
		"l31", "l35", "l36": _build_trunk(s)
		"l32": _build_l32(s)
		"l33": _build_l33(s)
		"l34": _build_l34(s)
	s._trees(func(x: float, z: float) -> float: return tree_ok(s, x, z), 330.0, 8.0)
	d["built"] = true

## L31, L35 and L36: the head, the trunk section by section (its own thickness), a village and a pole transformer at every node.
static func _build_trunk(s: Stage3D) -> void:
	var d: Dictionary = s.d8; var q: Dictionary = s.q
	var is36 := s.scn == "l36"
	var secs: Array = q.givens.sections if is36 else q.tree
	var xs: Array = d.xs
	var hd := _head(s, "Substation"); d["head"] = hd
	var prev := _head_pole(s, hd)
	d["sec"] = []; d["village"] = []; d["can"] = []; d["reg"] = []; d["glow"] = []; d["sw"] = []; d["node_pole"] = []
	var alu := _alu(s)
	for i in secs.size():
		var poles := _chain(s, prev, float(xs[i]), "S%d" % (i + 1))
		var np: Node3D = poles[poles.size() - 1]
		var node := _wire(s, poles, 0.1, alu, "Section%d" % (i + 1))
		d.sec.append({"node": node, "poles": poles, "mat": alu})
		d.node_pole.append(np)
		var gm: ShaderMaterial = s._hot_mat(0.0); gm.set_shader_parameter("inflate", 0.00022)
		_glow(s, poles, 0.1, gm, "Glow%d" % (i + 1))
		d.glow.append(gm)
		var cust := int(secs[i].customers)
		var vg := _village(s, str(secs[i].id), float(xs[i]), houses_for(cust))
		d.village.append(vg)
		d.can.append(_can(s, np))
		var mid: Node3D = poles[maxi(1, poles.size() / 2)]
		d.reg.append(_regulator(s, mid.position.x, "Regulator%d" % (i + 1)) if s.scn == "l31" else null)
		if is36:
			d.sw.append(_switch(s, poles[0], "Switch%d" % (i + 1)))
		prev = np
		s.anchors[str(secs[i].id)] = Vector3(float(xs[i]), s.ground(float(xs[i]), zc(float(xs[i]))) + 15.0, zc(float(xs[i])))
	for k in secs.size():   # farms between the villages
		var fx := (float(xs[k]) + (float(xs[k - 1]) if k > 0 else HEAD_X)) * 0.5 + 8.0
		_farm(s, fx, zc(fx) + (34.0 if k % 2 == 0 else -38.0), PI if k % 2 == 0 else 0.0, "Farm%d" % (k + 1))
	s.anchors["sub"] = (hd.pos as Vector3) + Vector3(2.0, 12.0, 0.0)
	if s.scn == "l35":
		_build_pv(s)
		s._box(hd.node, Vector3(3.2, 3.4, 2.9), Vector3(0.14, 3.0, 0.1), s._mat(Color(0.2, 0.2, 0.22)), "OltcScale")
		var ptr := s._box(hd.node, Vector3(3.2, 3.4, 2.95), Vector3(0.5, 0.18, 0.12), s._emit_mat(Color(1.0, 0.7, 0.1), 3.0), "OltcPointer")
		d["oltc_ptr"] = ptr
		var ldc := s._inst(hd.node, SphereMesh.new(), s._emit_mat(Color(0.3, 1.0, 0.45), 0.0), "LdcLamp", Vector3(4.0, 7.2, 1.0), false); ldc.scale = Vector3.ONE * 0.7
		d["ldc_lamp"] = ldc
		s.anchors["oltc"] = (hd.pos as Vector3) + Vector3(4.0, 10.0, 1.0)
	for k in secs.size(): if d.reg[k] != null: s.anchors["reg%d" % (k + 1)] = (d.reg[k] as Node3D).position + Vector3(0, 11.0, 0)

## L35: roof panels on the PV nodes' houses (a multimesh per village; the engine's count shows), an inverter box and its lamp at each.
static func _build_pv(s: Stage3D) -> void:
	var d: Dictionary = s.d8; var q: Dictionary = s.q
	d["pv"] = {}
	var bm := BoxMesh.new(); bm.size = Vector3(1.8, 0.07, 1.2)
	var pm := StandardMaterial3D.new(); pm.albedo_color = Color(0.08, 0.14, 0.30); pm.metallic = 0.55; pm.roughness = 0.22; pm.emission_enabled = true; pm.emission = Color(0.3, 0.5, 1.0); pm.emission_energy_multiplier = 0.0
	d["pv_mat"] = pm
	for i in (q.tree as Array).size():
		var id := str(q.tree[i].id)
		if not (q.pvNodes as Array).has(id): continue
		var vg: Dictionary = d.village[i]
		var homes: Array = vg.homes; var slots: Array = []
		for hm in homes:
			var hn: Node3D = hm.node; var dim: Vector3 = hm.dim; var zz := dim.y * 0.5 + 0.4
			for row in 2: for col in 3:
				var t := 0.3 + 0.4 * float(row)
				slots.append(Transform3D(Basis(Vector3.RIGHT, atan2(2.0, zz)), hn.position + Vector3((float(col) - 1.0) * 1.95, dim.z + 2.0 * (1.0 - t) + 0.14, zz * t)))
		var order: Array = []   # one panel to each house first, then a second to each, and so on
		for j in 6: for h in homes.size(): order.append(slots[h * 6 + j])
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = bm; mm.instance_count = order.size()
		for j in order.size(): mm.set_instance_transform(j, order[j])
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new(); mi.name = "Panels_" + id; mi.multimesh = mm; mi.material_override = pm; s._root.add_child(mi)
		# the inverter: a box on its own post by the village, with a lamp (cyan with volt-var, amber without)
		var cx := float(vg.cx); var ix := cx + 24.0; var iz := zc(ix) - 8.0
		var ib := Node3D.new(); ib.name = "Inverter_" + id; ib.position = Vector3(ix, s.ground(ix, iz), iz); s._root.add_child(ib)
		s._box(ib, Vector3(0, 1.0, 0), Vector3(1.6, 2.0, 0.9), s._mat(Color(0.88, 0.88, 0.9), 0.4, 0.2), "Box")
		var lm := s._emit_mat(Color(1.0, 0.7, 0.1), 3.0); var sm := SphereMesh.new(); sm.radius = 0.2; sm.height = 0.4
		s._inst(ib, sm, lm, "Lamp", Vector3(0.0, 2.3, 0.0), false)
		d.pv[id] = {"mm": mm, "lamp": lm, "node": ib, "i": i}

static func _build_l32(s: Stage3D) -> void:
	var d: Dictionary = s.d8
	var b: Array = d.b; var by: Dictionary = d.by
	var hd := _head(s, "Substation"); d["head"] = hd
	var prev := _head_pole(s, hd)
	var alu := _alu(s)
	d["village"] = {}; d["gm"] = {}; d["sw"] = {}; d["fuse"] = {}; d["sec_poles"] = {}; d["junction"] = {}
	var tk := ["T1", "T2", "T3", "T4"]
	for k in 4:
		var poles := _chain(s, prev, float(b[k + 1]), tk[k])
		_wire(s, poles, 0.09, alu, "Section_" + tk[k]); _sheen(s, poles, "Sheen_" + tk[k])
		d.sec_poles[tk[k]] = poles
		d.junction[tk[k]] = poles[0]
		if k > 0: d.sw[tk[k]] = _switch(s, poles[0], "Switch_" + tk[k])
		var mx := (float(b[k]) + float(b[k + 1])) * 0.5
		d.village[tk[k]] = _village(s, tk[k], mx, houses_for(int(by[tk[k]].customers)))
		s.anchors[tk[k]] = Vector3(mx, s.ground(mx, zc(mx)) + 15.0, zc(mx))
		_can(s, poles[poles.size() / 2])
		prev = poles[poles.size() - 1]
	d["end_pole"] = prev
	# the spurs hang from the downstream end of their parent: poles south along their own lane, a village at the end, a fuse set on the first pole
	for sp in ["P1", "P2", "P3"]:
		var par := int(str(by[sp].parent).trim_prefix("T")); var sx: float = b[par]
		var tp: Node3D = d.junction["T%d" % (par + 1)]
		var ln := SPUR_M * float(by[sp].km); var z0 := zc(sx) + 9.0
		var poles: Array = [tp]
		var n := maxi(2, ceili(ln / POLE_SP))
		for k in range(1, n + 1): poles.append(_pole(s, sx + 5.5, lerpf(z0 - 12.0, z0 + ln, float(k) / float(n)), "%s_%d" % [sp, k], PI * 0.5))
		_wire(s, poles, 0.07, alu, "Section_" + sp); _sheen(s, poles, "Sheen_" + sp)
		d.fuse[sp] = _cutouts(s, poles[1], "Cutouts_" + sp)
		var vg := _village(s, sp, sx, houses_for(int(by[sp].customers)), false, 0.0, z0 + ln)
		d.village[sp] = vg
		s.anchors[sp] = Vector3(sx, s.ground(sx, z0 + ln) + 13.0, z0 + ln)
	# the tie: poles on past T4 to the next feeder's substation stub; the conductors and the tie switch only when the player buys it
	var ex: float = b[4]; var np: Node3D = prev
	var tie_poles: Array = [np]
	var nx := ex + 62.0
	tie_poles.append_array(_chain(s, np, nx, "Tie").slice(1))
	var tmat := s._mat(Color(0.56, 0.58, 0.62), 0.4, 0.55); tmat.emission_enabled = true; tmat.emission = SAVED; tmat.emission_energy_multiplier = 0.4
	d["tie_wire"] = _wire(s, tie_poles, 0.07, tmat, "TieLine")
	d["tie_sw"] = _switch(s, tie_poles[1], "TieSwitch")
	var nb := Node3D.new(); nb.name = "NextFeeder"; nb.position = Vector3(nx + 18.0, s.ground(nx + 18.0, zc(nx) - 6.0), zc(nx) - 6.0); s._root.add_child(nb)
	s._box(nb, Vector3(0, 0.12, 0), Vector3(14.0, 0.3, 12.0), s._soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2), "Pad")
	var ntk := s._inst(nb, Props3D.transformer(), s._vc_mat(0.55), "Tank", Vector3(0, 0.3, 0)); ntk.scale = Vector3.ONE * 2.0
	s.anchors["tie"] = Vector3(nx, s.ground(nx, zc(nx)) + 14.0, zc(nx))
	s.anchors["sub"] = (hd.pos as Vector3) + Vector3(2.0, 12.0, 0.0)
	# the beacon: a red banded post with a pulsing glow, standing over the village most to blame once the engine says which
	var bn := Node3D.new(); bn.name = "Blame"; s._root.add_child(bn)
	s._box(bn, Vector3(0, 4.0, 0), Vector3(0.3, 8.0, 0.3), s._mat(Color(0.9, 0.9, 0.9), 0.6), "Post")
	for k in 2: s._box(bn, Vector3(0, 1.0 + 2.8 * float(k), 0), Vector3(0.36, 0.9, 0.36), s._mat(Color(0.85, 0.15, 0.12), 0.6), "Band")
	var bs := SphereMesh.new(); bs.radius = 2.4; bs.height = 4.8
	d["beacon"] = s._inst(bn, bs, s._glow_mat(Color(1.0, 0.25, 0.15, 1.0), 0.0), "Glow", Vector3(0, 9.5, 0), false)
	bn.visible = false; d["blame"] = bn
	_farm(s, -40.0, zc(-40.0) - 40.0, 0.0, "Farm1"); _farm(s, 160.0, zc(160.0) - 40.0, 0.0, "Farm2")

static func _build_l33(s: Stage3D) -> void:
	var d: Dictionary = s.d8
	var hd := _head(s, "Substation"); d["head"] = hd
	var hp := _head_pole(s, hd)
	d["rc"] = _recloser(s, hp)
	var alu := _alu(s)
	var sx: Array = d.sx
	var prev := hp; var junction: Array = []
	d["village"] = {}; d["fuse"] = {}
	for k in 3:
		var poles := _chain(s, prev, float(sx[k]), "T%d" % (k + 1))
		_wire(s, poles, 0.09, alu, "Trunk%d" % (k + 1)); _sheen(s, poles, "Sheen%d" % (k + 1))
		prev = poles[poles.size() - 1]; junction.append(prev)
		_can(s, poles[poles.size() / 2])
	var last := _chain(s, prev, 196.0, "T4")
	_wire(s, last, 0.09, alu, "Trunk4"); _sheen(s, last, "Sheen4")
	d["end_village"] = _village(s, "E", 196.0, 8)
	s.anchors["end"] = Vector3(196.0, s.ground(196.0, zc(196.0)) + 15.0, zc(196.0))
	var spurs: Array = s.q.spurs
	for k in 3:
		var spid := str(spurs[k].id); var x: float = sx[k]; var z0 := zc(x) + 9.0; var ln := 80.0
		var poles: Array = [junction[k]]
		var n := 4
		for j in range(1, n + 1): poles.append(_pole(s, x + 5.5, lerpf(z0 - 12.0, z0 + ln, float(j) / float(n)), "%s_%d" % [spid, j], PI * 0.5))
		_wire(s, poles, 0.07, alu, "Spur_" + spid); _sheen(s, poles, "Sheen_" + spid)
		d.fuse[spid] = _cutouts(s, poles[1], "Cutouts_" + spid)
		d.village[spid] = _village(s, spid, x, houses_for(int(spurs[k].customers)), false, 0.0, z0 + ln)
		s.anchors[spid] = Vector3(x, s.ground(x, z0 + ln) + 13.0, z0 + ln)
		s.anchors["fuse_" + spid] = poles[1].position + Vector3(1.0, 10.0, 0.0)
	s.anchors["sub"] = (hd.pos as Vector3) + Vector3(2.0, 12.0, 0.0)
	s.anchors["recloser"] = hp.position + Vector3(1.8, 13.0, 0.0)
	_farm(s, -130.0, zc(-130.0) - 40.0, 0.0, "Farm1"); _farm(s, 70.0, zc(70.0) - 40.0, 0.0, "Farm2")

## L34: the zone substation close up, seen from the incoming side. Three bays are built (the third shows only when bought): gantry, breaker, transformer, a duct back to the
## switchgear building with the bus-section breaker between its halves; the tie out to the next feeder; a town beyond the building for the demand response.
static func _build_l34(s: Stage3D) -> void:
	var d: Dictionary = s.d8
	var conc := Color(0.70, 0.68, 0.62); var cu := s._mat(Color(0.80, 0.45, 0.25), 0.35, 0.5); var dark := s._mat(Color(0.28, 0.3, 0.33), 0.5, 0.3)
	var wall: ShaderMaterial = s._soft_mat("rock", conc, 0.32, 0.16, 0.62, 0.45)
	var gy := s.ground(0, 0)
	var fm := s._mat(FENCE, 0.5, 0.3)
	for k in 11: for sz in [-40.0, 40.0]: s._box(s._root, Vector3(-50.0 + 10.0 * float(k), s.ground(-50.0 + 10.0 * float(k), sz) + 1.1, sz), Vector3(0.1, 2.2, 0.1), fm, "Post")
	for sx in [-50.0, 50.0]: for k in 9: s._box(s._root, Vector3(sx, s.ground(sx, -40.0 + 10.0 * float(k)) + 1.1, -40.0 + 10.0 * float(k)), Vector3(0.1, 2.2, 0.1), fm, "Post")
	# the incoming 33 kV: a lattice tower west of the yard, a gantry bus along its front, three wires between
	var sp: Array = Props3D.support("lattice", 24.0, 21.0)
	var tw := s._inst(s._root, sp[0], s._vc_mat(0.6), "IncomerTower", Vector3(-70.0, s.ground(-70.0, 28.0) - 0.3, 28.0))
	var hv := s._mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for c in 3:
		s._box(s._root, Vector3(0, gy + 9.4, 27.0 + 1.0 * float(c)), Vector3(70.0, 0.12, 0.12), hv, "Bus%d" % c)
		s._inst(s._root, s._run([tw.position + (sp[1][c] as Vector3), Vector3(-35.0, gy + 9.4, 27.0 + 1.0 * float(c))], 0.07, 1.2), hv, "Incomer%d" % c, Vector3.ZERO, false)
	d["bays"] = []; d["tx"] = []
	for i in 3:
		var bay := Node3D.new(); bay.name = "Bay%d" % (i + 1); s._root.add_child(bay)
		var gt := s._inst(bay, Props3D.gantry(), s._vc_mat(0.5), "Gantry", Vector3(0, 0, 24.0)); gt.scale = Vector3(1.2, 1.2, 1.2)
		var bk := s._inst(bay, Props3D.breaker(), s._vc_mat(0.55), "Breaker", Vector3(0, 0, 14.0)); bk.scale = Vector3.ONE * 1.3
		s._box(bay, Vector3(0.0, 4.6, 19.0), Vector3(0.12, 0.12, 10.0), hv, "Drop")
		var tn := Node3D.new(); tn.name = "Transformer"; tn.position = Vector3(0, 0, 0.0); bay.add_child(tn)
		s._box(tn, Vector3(0, 0.1, 0), Vector3(11.0, 0.3, 10.0), s._soft_mat("sand", Color(0.56, 0.54, 0.50), 0.3, 0.3, 0.0, 0.2), "Plinth")
		var tmat: StandardMaterial3D = s._vc_mat(0.55); tmat.emission_enabled = true; tmat.emission = Color.BLACK; tmat.emission_energy_multiplier = 0.0
		var tk := s._inst(tn, Props3D.transformer(), tmat, "Tank"); tk.scale = Vector3.ONE * 2.8
		var gm: ShaderMaterial = s._hot_mat(0.0); gm.set_shader_parameter("inflate", 0.0010)
		var halo := s._inst(tn, Props3D.transformer(), gm, "Halo", Vector3.ZERO, false); halo.scale = Vector3.ONE * 2.8
		var lamp := s._emit_mat(SAVED, 3.0); var sm := SphereMesh.new(); sm.radius = 0.4; sm.height = 0.8
		s._inst(tn, sm, lamp, "Lamp", Vector3(0, 8.6, 0.0), false)
		s._box(bay, Vector3(0.0, 2.4, -17.0), Vector3(0.7, 0.7, 24.0), cu, "LvDuct")
		d.bays.append(bay); d.tx.append({"node": bay, "tank": tk, "mat": tmat, "gm": gm, "lamp": lamp})
	# the switchgear building along the back of the yard, two halves, the bus-section breaker between them
	var sw := Node3D.new(); sw.name = "Switchgear"; sw.position = Vector3(0, gy, -30.0); s._root.add_child(sw)
	for h in 2:
		var hx := -18.5 if h == 0 else 18.5
		s._box(sw, Vector3(hx, 3.0, 0.0), Vector3(33.0, 6.0, 8.0), wall, "Half%d" % (h + 1))
		for k in 7: s._box(sw, Vector3(hx - 13.5 + 4.4 * float(k), 2.6, 4.05), Vector3(3.0, 3.6, 0.1), dark, "Panel")
		s._box(sw, Vector3(hx, 6.3, 0.0), Vector3(34.0, 0.4, 9.0), s._mat(Color(0.30, 0.31, 0.33), 0.6, 0.3), "Roof")
	var bus := Node3D.new(); bus.name = "BusSection"; bus.position = Vector3(0, 0, 5.2); sw.add_child(bus)
	s._box(bus, Vector3(0, 2.4, 0.0), Vector3(3.2, 4.4, 1.6), s._mat(Color(0.8, 0.82, 0.85), 0.4, 0.4), "Cabinet")
	var hand := s._inst(bus, s._cyl_mesh(Vector3.ZERO, Vector3(0, 0, 0.2), 0.8, Color(0.85, 0.15, 0.12), 14), s._vc_mat(0.5), "Handwheel", Vector3(0, 2.8, 0.9))
	var motor := s._box(bus, Vector3(0.9, 1.0, 0.9), Vector3(1.0, 1.0, 0.4), s._mat(Color(0.2, 0.6, 0.95), 0.4, 0.4), "Motor")
	var blamp := s._emit_mat(SAVED, 3.0); var bsm := SphereMesh.new(); bsm.radius = 0.3; bsm.height = 0.6
	s._inst(bus, bsm, blamp, "Lamp", Vector3(0.0, 5.0, 0.0), false)
	d["bus"] = {"node": bus, "hand": hand, "motor": motor, "lamp": blamp}
	# the tie: poles from the building's east end to the next feeder; the line and the switch when it is bought
	var tp: Array = []
	for k in 4: tp.append(_pole(s, 40.0 + 26.0 * float(k), -30.0 + 3.0 * float(k), "TiePole%d" % (k + 1)))
	d["tie_wire"] = _wire(s, tp, 0.08, _alu(s), "TieLine")
	_sheen(s, tp, "TieSheen")
	d["tie_sw"] = _switch(s, tp[1], "TieSwitch")
	var nb := Node3D.new(); nb.name = "NextFeeder"; nb.position = Vector3(134.0, s.ground(134.0, -22.0), -22.0); s._root.add_child(nb)
	s._box(nb, Vector3(0, 0.12, 0), Vector3(16.0, 0.3, 14.0), s._soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2), "Pad")
	var ntk := s._inst(nb, Props3D.transformer(), s._vc_mat(0.55), "Tank", Vector3(0, 0.3, 0)); ntk.scale = Vector3.ONE * 2.2
	# the town beyond the building: homes of one window material each so the demand response can dim some
	var homes: Array = []
	d["town"] = []
	for r in 3:
		var vg := _village(s, "town%d" % r, -70.0 + 70.0 * float(r), 10, true, 0.0, -88.0)
		d.town.append(vg)
		for h in vg.homes: homes.append(h)
	d["homes"] = homes
	s.anchors["tx1"] = (d.bays[0] as Node3D).position + Vector3(0, 12.0, 0.0)
	s.anchors["tx2"] = (d.bays[1] as Node3D).position + Vector3(0, 12.0, 0.0)
	s.anchors["bus"] = Vector3(0, 12.0, -24.0)
	s.anchors["tie"] = Vector3(92.0, s.ground(92.0, -26.0) + 14.0, -26.0)
	s.anchors["town"] = Vector3(0, 16.0, -88.0)
	s.anchors["gantry"] = Vector3(0, 12.0, 24.0)

# --------------------------------------------------------------------------------------------------------------------
# The engine's numbers onto the scene
# --------------------------------------------------------------------------------------------------------------------
static func apply(s: Stage3D) -> void:
	var q: Dictionary = s.q; var d: Dictionary = s.d8
	match s.scn:
		"l31": _apply_l31(s, q, d)
		"l32": _apply_l32(s, q, d)
		"l33": _apply_l33(s, q, d)
		"l34": _apply_l34(s, q, d)
		"l35": _apply_l35(s, q, d)
		"l36": _apply_l36(s, q, d)

static func _apply_l31(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var band: Dictionary = q.band; var tree: Array = q.tree
	var reg_id := "" if q.get("regulator") == null else str(q.regulator.nodeId)
	for i in tree.size():
		var n: Dictionary = tree[i]
		var r := 0.03 + 0.00045 * float(n.ampacityA)   # thicker for a bigger wire
		_rewire(s, d.sec[i], r, str(n.conductor))
		var l := _lamp(float(n.vPeakV), float(band.nominalV), float(band.loV))
		_set_village(d.village[i], l[0], l[1])
		_set_tap(d.can[i], float(n.tap))
		var ld := clampf(float(n.loading), 0.0, 1.2)
		var gm: ShaderMaterial = d.glow[i]
		gm.set_shader_parameter("tint", Color(Bench3D.heat_colour(clampf(ld, 0.0, 1.0)), 1.0)); gm.set_shader_parameter("power", 1.1 * pow(ld, 2.0))
		if d.reg[i] != null: (d.reg[i] as Node3D).visible = str(n.id) == reg_id
	d["reg_id"] = reg_id

## Rebuild a section's three runs at radius r when the radius changed (a wire chosen); the node keeps its name and carries the wire's id and radius for the truth test.
static func _rewire(s: Stage3D, sec: Dictionary, r: float, wire_id: String) -> void:
	var node: Node3D = sec.node
	if node.has_meta("r") and is_equal_approx(float(node.get_meta("r")), r):
		node.set_meta("wire", wire_id); return
	for c in 3:
		var pts: Array = []
		for p in sec.poles: pts.append(_pa(p as Node3D, Stage3D.PH[c]))
		(node.get_node("W%d" % c) as MeshInstance3D).mesh = s._run(pts, r, 0.8)
	node.set_meta("r", r); node.set_meta("wire", wire_id)

static func _apply_l32(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var dz: Dictionary = q.design; var rev := bool(q.get("revealed", false))
	for id in ["T2", "T3", "T4"]: _set_switch(d.sw[id], str(dz.sect[id]))
	for sp in ["P1", "P2", "P3"]:
		var fused := bool(dz.fuse[sp])
		(d.fuse[sp].node as Node3D).visible = fused
	d.tie_wire.visible = bool(dz.tie); (d.tie_sw as Node3D).visible = bool(dz.tie)
	if bool(dz.tie): _set_switch(d.tie_sw, "remote")
	var hmax := 1.0; var worst := ""
	for sc in q.sections: if float(sc.saidiMin) > hmax: hmax = float(sc.saidiMin); worst = str(sc.id)
	var by: Dictionary = {}
	for sc in q.sections: by[str(sc.id)] = sc
	for id in d.village:
		var share := float(by[id].saidiMin) / hmax if rev else 0.0
		_set_village(d.village[id], WINDOW_E * (1.0 - 0.92 * share), Bench3D.WARM)
		d.village[id]["lit"] = 1.0 - 0.92 * share
	var bn: Node3D = d.blame
	bn.visible = rev and worst != ""
	if bn.visible:
		var vg: Dictionary = d.village[worst]
		bn.position = Vector3(float(vg.cx) + 20.0, s.ground(float(vg.cx) + 20.0, float(vg.cz) - 8.0), float(vg.cz) - 8.0)
		s.anchors["blame"] = bn.position + Vector3(0, 14.0, 0)
	else: s.anchors.erase("blame")
	d["worst"] = worst if rev else ""

static func _apply_l33(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var rev := bool(q.get("revealed", false)); var kind := "ok" if q.get("kind") == null else str(q.kind)
	var shots := int(q.design.fastShots)
	d["state"] = {}
	for sp in q.spurs:
		var id := str(sp.id)
		var saved := shots > 0 and float(sp.fastMarginS) >= 0.0
		var st := "idle" if not rev else ("saved" if saved else "open")
		_set_cutouts(d.fuse[id], "closed" if st != "open" else "open")
		(d.fuse[id].lamp as StandardMaterial3D).emission = SAVED if st == "saved" else (OPEN if st == "open" else IDLE)
		d.state[id] = st
		var e := WINDOW_E * (0.04 if (st == "open" or (rev and kind == "miscoordination")) else 1.0)
		_set_village(d.village[id], e, Bench3D.WARM)
	var out := rev and kind == "miscoordination"
	_set_village(d.end_village, WINDOW_E * (0.04 if out else 1.0), Bench3D.WARM)
	var lamp: StandardMaterial3D = d.rc.lamp
	lamp.emission = IDLE if not rev else (OPEN if kind in ["miscoordination", "nuisance"] else SAVED)
	d["kind"] = kind

static func _apply_l34(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var n := int(q.n)
	var xs: Array = [-28.0, 0.0, 28.0] if n == 3 else [-16.0, 16.0, 0.0]
	var ambient := float(q.ambientC); var lim := float(q.hotLimitC)
	var frac := clampf((float(q.hotPeakC) - ambient) / maxf(lim - ambient, 1.0), 0.0, 1.4)
	for i in 3:
		var bay: Node3D = d.bays[i]
		bay.visible = i < n
		bay.position = Vector3(float(xs[i]), s.ground(float(xs[i]), 0.0), 0.0)
		var t: Dictionary = d.tx[i]
		var survivor := i > 0   # the largest unit (bay 1) is the one that trips; the others carry on
		var mat: StandardMaterial3D = t.mat; var gm: ShaderMaterial = t.gm
		if survivor:
			var hc := Bench3D.heat_colour(clampf(frac, 0.0, 1.0))
			var gf := clampf(frac, 0.0, 1.25)
			mat.emission = hc; mat.emission_energy_multiplier = 2.0 * pow(gf, 1.5)
			gm.set_shader_parameter("tint", Color(hc, 1.0)); gm.set_shader_parameter("power", 0.9 * pow(gf, 1.4))
			(t.lamp as StandardMaterial3D).emission = OPEN if bool(q.overheat) else SAVED
		else:
			mat.emission_energy_multiplier = 0.0; gm.set_shader_parameter("power", 0.0)
			(t.lamp as StandardMaterial3D).emission = OPEN
	var bus: Dictionary = d.bus
	var auto := str(q.design.bus) == "auto"
	(bus.hand as Node3D).visible = not auto; (bus.motor as Node3D).visible = auto
	(bus.lamp as StandardMaterial3D).emission = SAVED if auto else IDLE
	var tie := str(q.design.tie)
	d.tie_wire.visible = tie != "none"; (d.tie_sw as Node3D).visible = tie != "none"
	_set_switch(d.tie_sw, tie)
	var kit: Dictionary = q.get("kit", {})
	var dr_mva := 0.0
	for x in kit.get("dr", []): if str(x.id) == str(q.design.dr): dr_mva = float(x.mva)
	var homes: Array = d.homes; var dim_n := 0
	var dark := bool(q.get("revealed", false)) and (bool(q.get("overheat", false)) or bool(q.get("notRestored", false)))   # 1128c C08: the survivor tripped and the whole substation went dark: so does the town
	if dr_mva > 0.0: dim_n = maxi(1, int(roundf(float(homes.size()) * dr_mva / float(q.peakMva))))
	for i in homes.size():
		var dimmed := i < dim_n
		var mat: StandardMaterial3D = homes[i].mat
		mat.emission = Color(0.50, 0.19, 0.04) if dimmed else Bench3D.WARM; mat.emission_energy_multiplier = 0.0 if dark else WINDOW_E * (0.25 if dimmed else 1.0)
		homes[i]["dimmed"] = dimmed
	for vg in d.town: if vg.light != null: (vg.light as OmniLight3D).light_energy = 0.0 if dark else 3.0; (vg.light as OmniLight3D).light_color = Bench3D.WARM
	d["frac"] = frac; d["dim_n"] = dim_n

static func _apply_l35(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var band: Dictionary = q.band; var noon: Dictionary = q.noon; var tree: Array = q.tree
	var pv_each := float(q.design.pvLimitKw) / maxf(float((q.pvNodes as Array).size()), 1.0)
	var nom := float(band.nominalV); var hi := float(band.hiV)
	for i in tree.size():
		var n: Dictionary = tree[i]
		_rewire(s, d.sec[i], 0.03 + 0.00045 * float(n.ampacityA), str(n.conductor))
		var v := float(noon.vV[i])
		var l := _lamp(v, nom, float(band.loV))
		_set_village(d.village[i], l[0], l[1])
		_set_tap(d.can[i], float(n.tap))
		var fr := clampf((v - nom) / maxf(hi - nom, 1.0), 0.0, 1.4)   # how far toward the ceiling the noon voltage has climbed
		var gm: ShaderMaterial = d.glow[i]
		gm.set_shader_parameter("tint", Color(Bench3D.heat_colour(clampf(fr, 0.0, 1.0)), 1.0)); gm.set_shader_parameter("power", 1.6 * pow(fr, 1.2))
	var cnt := int(roundf(pv_each / KW_PER_PANEL))
	for id in d.pv:
		var p: Dictionary = d.pv[id]; var mm: MultiMesh = p.mm
		mm.visible_instance_count = mini(cnt, mm.instance_count)
		(p.lamp as StandardMaterial3D).emission = Color(0.9, 0.3, 0.85) if bool(q.design.voltVar) else IDLE
	(d.pv_mat as StandardMaterial3D).emission_energy_multiplier = 0.15
	# the tap changer's step on the substation's transformer, and the line-drop compensation lamp
	(d.oltc_ptr as Node3D).position.y = 3.4 + clampf(0.1 * float(noon.oltcStep), -1.4, 1.4)   # up a step, up a tenth of a metre
	d.oltc_ptr.set_meta("step", int(noon.oltcStep))
	((d.ldc_lamp as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier = 3.0 if bool(q.design.ldc) else 0.0
	d["cnt"] = cnt

static func _apply_l36(s: Stage3D, q: Dictionary, d: Dictionary) -> void:
	var rev := bool(q.get("revealed", false)); var secs: Array = q.givens.sections
	var far := 230.0
	if rev and q.get("answers") != null: far = 230.0 * (1.0 - float(q.answers.dropPct) / 100.0)
	for i in secs.size():
		_set_switch(d.sw[i], "manual" if str(secs[i].device) == "manual" else "none")
		var e := WINDOW_E * 1.0
		var col := Bench3D.WARM
		if i == secs.size() - 1:
			var l := _lamp(far, 230.0, 0.94 * 230.0)
			e = l[0]; col = l[1]
		_set_village(d.village[i], e, col)
		_rewire(s, d.sec[i], 0.03 + 0.00045 * 190.0, str(q.givens.conductor))
		_set_tap(d.can[i], 0.0)
		d.glow[i].set_shader_parameter("power", 0.0)
		var dev := str(secs[i].device)
		d.sw[i].set_meta("dev", dev)
	d["far"] = far

# --------------------------------------------------------------------------------------------------------------------
# Motion: beacons and lamps pulse; the engine's states stay as they are
# --------------------------------------------------------------------------------------------------------------------
static func process(s: Stage3D, _dt: float) -> void:
	var d: Dictionary = s.d8
	if d.is_empty() or s.q.is_empty(): return
	var pulse := 0.6 + 0.4 * sin(s._t * 5.0)
	if s.scn == "l32" and d.has("beacon") and (d.blame as Node3D).visible:
		((d.beacon as MeshInstance3D).material_override as ShaderMaterial).set_shader_parameter("power", 2.4 * pulse)

static func report(s: Stage3D) -> Dictionary:
	var d: Dictionary = s.d8; var r := {"kind": s.scn}
	if d.is_empty(): return r
	match s.scn:
		"l31", "l35", "l36":
			r["wire"] = (d.sec as Array).map(func(x): return str((x.node as Node3D).get_meta("wire", "")))
			r["wire_r"] = (d.sec as Array).map(func(x): return float((x.node as Node3D).get_meta("r", 0.0)))
			r["win_e"] = (d.village as Array).map(func(v): return float(((v.mats as Array)[0] as StandardMaterial3D).emission_energy_multiplier))
			r["lamp_on"] = (d.village as Array).map(func(v): return Kit3D.group_on(str(v.group)))
			r["win_col"] = (d.village as Array).map(func(v): return ((v.mats as Array)[0] as StandardMaterial3D).emission)
			r["houses"] = (d.village as Array).map(func(v): return (v.homes as Array).size())
			r["tap_ptr"] = (d.can as Array).map(func(c): return float((c.ptr as Node3D).position.z))
			r["glow"] = (d.glow as Array).map(func(g): return float((g as ShaderMaterial).get_shader_parameter("power")))
			if s.scn == "l31":
				var at := ""; var tanks := 0
				for i in (d.reg as Array).size():
					var rg = d.reg[i]
					if rg != null and (rg as Node3D).visible: at = str(s.q.tree[i].id); tanks = 0; for c in (rg as Node3D).get_children(): if str(c.name).begins_with("Tank"): tanks += 1
				r["reg_at"] = at; r["reg_tanks"] = tanks
			if s.scn == "l35":
				var pn := {}
				for id in d.pv: pn[id] = (d.pv[id].mm as MultiMesh).visible_instance_count
				r["panels"] = pn
				r["vv"] = d.pv.values().map(func(p): return (p.lamp as StandardMaterial3D).emission.r > 0.8 and (p.lamp as StandardMaterial3D).emission.g < 0.5)
				r["oltc"] = int(d.oltc_ptr.get_meta("step", 0)); r["ldc"] = ((d.ldc_lamp as MeshInstance3D).material_override as StandardMaterial3D).emission_energy_multiplier > 0.5
			if s.scn == "l36":
				r["dev"] = (d.sw as Array).map(func(sw): return _switch_kind(sw as Node3D))
		"l32":
			var kinds := {}
			for id in d.sw: kinds[id] = _switch_kind(d.sw[id])
			r["sect"] = kinds
			var fz := {}
			for sp in d.fuse: fz[sp] = (d.fuse[sp].node as Node3D).visible
			r["fuse"] = fz
			r["tie"] = (d.tie_wire as Node3D).visible
			var lit := {}
			for id in d.village: lit[id] = float(((d.village[id].mats as Array)[0] as StandardMaterial3D).emission_energy_multiplier)
			r["lit"] = lit
			r["worst"] = str(d.get("worst", "")); r["beacon"] = (d.blame as Node3D).visible
		"l33":
			r["recloser"] = d.rc != null
			r["state"] = d.get("state", {}).duplicate()
			var e := {}
			for id in d.village: e[id] = float(((d.village[id].mats as Array)[0] as StandardMaterial3D).emission_energy_multiplier)
			r["village_e"] = e; r["end_e"] = float(((d.end_village.mats as Array)[0] as StandardMaterial3D).emission_energy_multiplier)
			r["cut"] = d.fuse.keys().map(func(id): return str((d.fuse[id].node as Node3D).get_meta("state", "")))
		"l34":
			var vis := 0
			for b in d.bays: if (b as Node3D).visible: vis += 1
			r["tx"] = vis
			r["hot"] = (d.tx as Array).map(func(t): return float((t.gm as ShaderMaterial).get_shader_parameter("power")))
			r["hot_e"] = (d.tx as Array).map(func(t): return float((t.mat as StandardMaterial3D).emission_energy_multiplier))
			r["bus_auto"] = (d.bus.motor as Node3D).visible; r["bus_hand"] = (d.bus.hand as Node3D).visible
			r["tie"] = _switch_kind(d.tie_sw) if (d.tie_wire as Node3D).visible else "none"
			r["dimmed"] = (d.homes as Array).filter(func(h): return bool(h.get("dimmed", false))).size(); r["homes"] = (d.homes as Array).size()
	return r
