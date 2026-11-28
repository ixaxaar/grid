class_name District3D
extends Stage3D
## The Career's district as a night place (the 3D look of ui/career/career_map.gd's data): two primary substations as small fenced yards, every feeder a wood-pole 11 kV
## line leaving its primary through farmland, one lit street of homes per section, the hardware the engine says is there (a recloser at the head, a regulator, sectionalisers
## and fuse cutouts at the section heads, a tie switch between two tips, a battery container, a demand-response mast), and the district's named places (hospital, charging hub,
## wind turbine). It borrows Stage3D / Bench3D for the land, sky, camera and helpers, and chapter 8's feeder kit (stage3d_ch8.gd) for poles, wires, switches and cut-outs.
## Display only: every number is the engine's `career` query. The arithmetic only maps numbers to light and colour: a section's windows follow its loading (or its health) the
## way CareerMap colours its stroke and are dark for a section out of service or on a feeder with an open incident. CareerMap, in the 3D look, draws its strokes, badges and
## labels at the screen positions of this scene's section boundaries (project()) and picks through them. `plan()` is the pure layout both read.

const Z_TOP := -150.0                 # the primaries' yards stand along this line, the feeders run south from them
const Z_BOT := 150.0                  # the tips
const GAP := 24.0                     # feeder heads side by side on a yard's south fence
const HEAD_DZ := 38.0
const HOUSE_SIDE := 14.5              # houses stand this far (m) either side of the line
const VIL_AT := 0.55                  # where on a section its street stands
const NIGHT_MIN := 1260.0              # 21:00: dusk gone, the windows are what you read
const DIST_FAR := 1300.0
const STARVED_COL := Color(0.62, 0.20, 0.04)
const PLACE_KINDS := ["hospital", "hub", "turbine", "villages"]

var dq: Dictionary = {}                # the engine's `career`, as last handed over
var plan_d: Dictionary = {}            # plan() of it
var mode := "load"                     # "load" | "health": what the windows and the wire glow follow
var hot: Array = []                    # feeder ids with an open incident (their streets are dark)
var view_rect := Rect2()               # the screen area the map occupies (canvas px): the district is framed inside it
var dd: Dictionary = {}                # the scene's parts (yards, sections, hardware, places)
var _dkey := ""
var _seed_key := ""
var _touched := false                  # the player has moved the camera: a refit keeps it
var _seg_cells: Dictionary = {}        # 64 m grid of the line segments (roads, tree clearing)
var _pads: Array = []
var _pad_cells: Dictionary = {}        # the same pads by 64 m cell (each in every cell within 10 m of it)
const NO_PADS: Array = []

# --------------------------------------------------------------------------------------------------------------------
# The plan: where everything stands, from the engine's lists alone (pure; tests read it)
# --------------------------------------------------------------------------------------------------------------------
## {order: [feeder id], prim: {id: Vector2 yard centre}, yard_w: {id: float}, head: {fid: Vector2}, pts: {fid: [Vector2 per section boundary]}, ties: [[fid, fid]],
##  places: [{kind, name, feeder, at: Vector2}], width: float}
static func plan(d: Dictionary) -> Dictionary:
	var feeders: Array = d.get("feeders", []); var prims: Array = d.get("primaries", [])
	var by := {}
	for p in prims: by[str(p.id)] = []
	for f in feeders:
		if not by.has(str(f.primaryId)): by[str(f.primaryId)] = []
		(by[str(f.primaryId)] as Array).append(f)
	var n := feeders.size()
	var width := clampf(float(n) * 62.0, 280.0, 760.0)
	var order: Array = []; var ex := {}; var i := 0
	for pid in by:
		for f in by[pid]:
			ex[str(f.id)] = -width * 0.5 + (float(i) + 0.5) / float(maxi(n, 1)) * width
			order.append(str(f.id)); i += 1
	var prim := {}; var yw := {}
	for pid in by:
		var grp: Array = by[pid]; var sx := 0.0
		for f in grp: sx += float(ex[str(f.id)])
		prim[pid] = Vector2(sx / float(grp.size()) if not grp.is_empty() else 0.0, Z_TOP)
		yw[pid] = maxf(64.0, float(grp.size()) * GAP + 30.0)
	var head := {}; var pts := {}
	for f in feeders:
		var fid := str(f.id); var idx := order.find(fid)
		var grp2: Array = by[str(f.primaryId)]; var gi := 0
		for g in grp2:
			if str(g.id) == fid: break
			gi += 1
		var h0: Vector2 = (prim[str(f.primaryId)] as Vector2) + Vector2((float(gi) - float(grp2.size() - 1) * 0.5) * GAP, HEAD_DZ)
		var tip := Vector2(float(ex[fid]), Z_BOT)
		var secs: Array = f.sections; var tot := 0.0
		for s in secs: tot += float(s.km)
		var line: Array = [h0]; var acc := 0.0
		for k in secs.size():
			acc += float(secs[k].km); var t := acc / maxf(tot, 0.01)
			var bend := sin(t * PI) * (6.0 + 2.0 * sin(float(idx) * 1.7) if k < secs.size() - 1 else 0.0)   # every line leans the same way, so neighbours keep their distance
			line.append(h0.lerp(tip, t) + Vector2(bend, 0.0))
		head[fid] = h0; pts[fid] = line
	var ties: Array = []; var done := {}
	for f in feeders:
		if not bool(f.tie): continue
		var a := order.find(str(f.id)); var b := a + 1 if a + 1 < order.size() else a - 1
		if b < 0: continue
		var ky := "%d-%d" % [mini(a, b), maxi(a, b)]
		if done.has(ky): continue
		done[ky] = true; ties.append([str(order[mini(a, b)]), str(order[maxi(a, b)])])
	var places: Array = []
	for pl in d.get("places", []):
		var kind := str(pl.kind)
		if kind == "ducts" or not pts.has(str(pl.feeder)): continue
		var ln: Array = pts[str(pl.feeder)]
		var at: Vector2
		match kind:
			"hospital": at = (ln[mini(2, ln.size() - 1)] as Vector2) + Vector2(27.0, -6.0)
			"villages": at = (ln[ln.size() - 1] as Vector2) + Vector2(0.0, 30.0)
			"turbine": at = (ln[mini(3, ln.size() - 1)] as Vector2) + Vector2(30.0, 8.0)
			_: at = (ln[mini(3, ln.size() - 1)] as Vector2) + Vector2(-27.0, 4.0)
		places.append({"kind": kind, "name": str(pl.name), "feeder": str(pl.feeder), "at": at})
	return {"order": order, "prim": prim, "yard_w": yw, "head": head, "pts": pts, "ties": ties, "places": places, "width": width}

## How a section's street looks: {dark, e (window emission), col}. The load colour of the feeder or the health of the section decide it, as CareerMap's strokes do.
static func window_state(sec: Dictionary, f: Dictionary, out_feeder: bool, md: String) -> Dictionary:
	var out_sec := bool(sec.failed) and float(sec.get("outQ", 0.0)) > 0.0
	if out_feeder or out_sec: return {"dark": true, "e": 0.0, "col": Bench3D.WARM}
	var q := 0.0
	if md == "load": q = 1.0 - clampf((float(f.loadingPct) - 70.0) / 55.0, 0.0, 1.0)
	else: q = clampf((float(sec.health) - 1.0) / 7.0, 0.0, 1.0)
	return {"dark": false, "e": Bench3D.WINDOW_E * (0.45 + 0.55 * q), "col": STARVED_COL.lerp(Bench3D.WARM, pow(q, 0.7)), "q": q}

static func sec_colour(md: String, f: Dictionary, sec: Dictionary) -> Color:
	return CareerKit.load_col(float(f.loadingPct)) if md == "load" else CareerKit.health_col(float(sec.health))

static func houses_of(f: Dictionary) -> int:
	return clampi(roundi(float(f.get("customers", 4000)) / maxf(1.0, float((f.sections as Array).size())) / 200.0), 4, 9)

static func _yaw(dir: Vector2) -> float: return -atan2(dir.y, dir.x)

# --------------------------------------------------------------------------------------------------------------------
# Numbers in
# --------------------------------------------------------------------------------------------------------------------
## The engine's `career` (and what the screen colours by). Structure changes (a new feeder, transformer or device) rebuild the place; nothing else does.
func set_district(q_: Dictionary, md := "load", hot_ids: Array = []) -> void:
	_setup()
	if not q_.get("active", false): return
	dq = q_; mode = md; hot = hot_ids
	if absf(NIGHT_MIN - _minute) > 0.4: _update_sky(NIGHT_MIN)
	var key := _structure_key(q_)
	var sk := "%s|%s" % [str(q_.get("seed", 0)), str(q_.get("charter", ""))]
	if key != _dkey or field == null:
		var fresh := sk != _seed_key or field == null
		_dkey = key; _seed_key = sk
		_build_district()
		if fresh: _touched = false
		if fresh or not _touched: reset_camera()
	_apply_district()

func _structure_key(q_: Dictionary) -> String:
	var parts: Array = [str(q_.get("charter", "")), str(q_.get("seed", 0))]
	for p in q_.get("primaries", []): parts.append("%s:%d" % [str(p.id), (p.units as Array).size()])
	for f in q_.get("feeders", []):
		var s := "%s:%s:%s:%d%d%d%d%d:%d" % [str(f.id), str(f.primaryId), str(f.get("kind", "")), int(bool(f.tie)), int(bool(f.recloser)), int(bool(f.regulator)), int(float(f.batteryKw) > 0.0), int(float(f.drKw) > 0.0), int(f.customers / 400.0)]
		for sc in f.sections: s += "|%s%s%d" % [str(sc.id), str(sc.device), int(float(sc.km) * 10.0)]
		parts.append(s)
	for pl in q_.get("places", []): parts.append("%s@%s" % [str(pl.kind), str(pl.feeder)])
	return "~".join(parts)

# --------------------------------------------------------------------------------------------------------------------
# Land
# --------------------------------------------------------------------------------------------------------------------
func ground(x: float, z: float) -> float:
	var h := 0.7 + 2.0 * _n01(x * 0.45, z * 0.45) + 0.8 * _n01(x * 0.09 + 40.0, z * 0.09)
	var hills := 1.0 if str(dq.get("charter", "")) != "moor" else 1.9
	h += hills * 20.0 * smoothstep(-185.0, -300.0, z) * (0.45 + 0.55 * _n01(x * 0.12, z * 0.12)) + hills * 14.0 * smoothstep(-90.0, 90.0, absf(x) - plan_d.get("width", 600.0) * 0.5 - 40.0) * _n01(x * 0.07 + 9.0, z * 0.07) + _far(x, z)
	for r in _pads_at(x, z): h = lerpf(h, 1.0, _pad(x, z, r as Rect2, 9.0))
	return h

func _splat(x: float, z: float, h: float) -> Array:
	var wood := smoothstep(0.05, 0.35, _nz.get_noise_2d(x * 0.5 + 300.0, z * 0.5))
	var near := _near(x, z)
	var f := maxf(wood * 0.5 * smoothstep(16.0, 40.0, near), smoothstep(-175.0, -255.0, z) * 0.9)
	var r := smoothstep(26.0, 40.0, h)
	var c := Color(1.0 - f - r, f, r, 0.0)
	var paved := 1.0 - smoothstep(2.0, 3.4, near)
	for rc in _pads_at(x, z): paved = maxf(paved, _pad(x, z, (rc as Rect2).grow(-9.0), 5.0) * 0.5)
	return [c, 0.0, paved]

func _cell(x: float, z: float) -> Vector2i: return Vector2i(floori(x / 64.0), floori(z / 64.0))

## Distance (m) to the nearest feeder line (exact within ~32 m, which is all the land and the trees ask), 999 when none is near: the own 64 m cell and the three nearest to the point.
func _near(x: float, z: float) -> float:
	var c := _cell(x, z); var best := 999.0
	var ox := -1 if fposmod(x, 64.0) < 32.0 else 1; var oz := -1 if fposmod(z, 64.0) < 32.0 else 1
	for ck in [c, Vector2i(c.x + ox, c.y), Vector2i(c.x, c.y + oz), Vector2i(c.x + ox, c.y + oz)]:
		var lst = _seg_cells.get(ck)
		if lst == null: continue
		for sg in lst: best = minf(best, Bench3D._seg_d(Vector2(x, z), sg[0] as Vector2, sg[1] as Vector2))
	return best

func _index_segments() -> void:
	_seg_cells.clear()
	for fid in plan_d.pts:
		var ln: Array = plan_d.pts[fid]
		for k in ln.size() - 1:
			var a: Vector2 = ln[k]; var b: Vector2 = ln[k + 1]
			var steps := int(a.distance_to(b) / 12.0) + 1
			var seen := {}
			for s in steps + 1:
				var p := a.lerp(b, float(s) / float(steps))
				var ck := _cell(p.x, p.y)
				if seen.has(ck): continue
				seen[ck] = true
				if not _seg_cells.has(ck): _seg_cells[ck] = []
				(_seg_cells[ck] as Array).append([a, b])

func _index_pads() -> void:
	_pad_cells.clear()
	for r in _pads:
		var g := (r as Rect2).grow(10.0)
		for cx in range(floori(g.position.x / 64.0), floori(g.end.x / 64.0) + 1):
			for cz in range(floori(g.position.y / 64.0), floori(g.end.y / 64.0) + 1):
				var ck := Vector2i(cx, cz)
				if not _pad_cells.has(ck): _pad_cells[ck] = []
				(_pad_cells[ck] as Array).append(r)

func _pads_at(x: float, z: float) -> Array: return _pad_cells.get(_cell(x, z), NO_PADS)

func _tree_dens(x: float, z: float) -> float:
	for r in _pads_at(x, z): if (r as Rect2).grow(10.0).has_point(Vector2(x, z)): return 0.0
	if _near(x, z) < 22.0: return 0.0
	var hedge := 1.0 - smoothstep(0.0, 3.0, absf(fposmod(z + 40.0, 90.0) - 45.0))
	return clampf(0.08 + 0.55 * smoothstep(-175.0, -265.0, z) + 0.2 * hedge, 0.0, 0.7)

# --------------------------------------------------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------------------------------------------------
func _build_district() -> void:
	_clear(_root)
	_water_mats.clear(); _homes.clear(); anchors.clear(); _shoe_mats.clear(); _poles.clear(); _drops.clear(); _house_geo.clear(); _cans.clear(); _burst_fx.clear()
	_spin.clear(); _lamps.clear(); _circ.clear(); _tower_mesh.clear(); _pm.clear(); _alt = null; _rotor = null
	scn = "career"; kind = "career"; _fields_on = true; _grass_tint = Vector3(0.80, 0.93, 0.66)
	plan_d = plan(dq)
	var w: float = plan_d.width
	_play = Rect2(-w * 0.5 - 90.0, Z_TOP - 80.0, w + 180.0, (Z_BOT - Z_TOP) + 160.0)
	_pads = []
	for pid in plan_d.prim:
		var c: Vector2 = plan_d.prim[pid]; var yw: float = plan_d.yard_w[pid]
		_pads.append(Rect2(c.x - yw * 0.5 - 6.0, c.y - 28.0, yw + 12.0, 56.0))
	_index_segments()
	for f in dq.get("feeders", []):
		var ln: Array = plan_d.pts[str(f.id)]
		for k in (f.sections as Array).size():
			var mid: Vector2 = (ln[k] as Vector2).lerp(ln[k + 1], VIL_AT)
			_pads.append(Rect2(mid.x - 28.0, mid.y - 26.0, 56.0, 52.0))
	for pl in plan_d.places: _pads.append(Rect2((pl.at as Vector2).x - 16.0, (pl.at as Vector2).y - 16.0, 32.0, 32.0))
	_index_pads()
	dd = {"yard": {}, "sec": {}, "fdr": {}, "place": [], "tie": []}
	var t0 := Time.get_ticks_msec()
	_build_terrain()
	var t1 := Time.get_ticks_msec()
	_water(-1.5, Rect2(-FAR_M, -FAR_M, FAR_M * 2.0, FAR_M * 2.0), Vector2(0.0, 0.05))
	for pid in plan_d.prim: _build_yard(str(pid))
	for f in dq.get("feeders", []): _build_feeder(f)
	_build_ties()
	for pl in plan_d.places: _build_place(pl)
	var t2 := Time.get_ticks_msec()
	_trees(_tree_dens, 480.0, 9.0)
	field = self
	if OS.has_environment("CB_D3DEBUG"): print("D3BUILD terrain=%d ms things=%d ms trees=%d ms" % [t1 - t0, t2 - t1, Time.get_ticks_msec() - t2])
	if _minute >= 0.0: _update_sky(_minute)

func _yard_pos(pid: String) -> Vector3:
	var c: Vector2 = plan_d.prim[pid]
	return Vector3(c.x, ground(c.x, c.y), c.y)

## A primary substation: a fenced gravel pad, the incoming 33 kV on a lattice tower to a bus, one transformer for each unit the engine has, the switchgear shed, one breaker for
## each feeder at the south fence, lamp posts.
func _build_yard(pid: String) -> void:
	var c: Vector2 = plan_d.prim[pid]; var yw: float = plan_d.yard_w[pid]
	var pi := CareerKit.find_id(dq.primaries, pid)
	var units := (dq.primaries[pi].units as Array).size() if pi >= 0 else 2
	var gy := ground(c.x, c.y)
	var n := Node3D.new(); n.name = "Yard_" + pid; n.position = Vector3(c.x, gy, c.y); _root.add_child(n)
	_box(n, Vector3(0, 0.12, 0), Vector3(yw, 0.3, 40.0), _soft_mat("sand", Color(0.52, 0.46, 0.38), 0.3, 0.3, 0.0, 0.2), "Pad")
	var fm := _mat(Stage8.FENCE, 0.5, 0.3)
	var hw := yw * 0.5
	var nposts := int(yw / 6.0) + 1
	for k in nposts:
		var px := -hw + yw * float(k) / float(nposts - 1)
		for sz in [-20.0, 20.0]: _box(n, Vector3(px, 1.1, sz), Vector3(0.1, 2.2, 0.1), fm, "Post")
	for sx in [-hw, hw]: for k in 5: _box(n, Vector3(sx, 1.1, -20.0 + 10.0 * float(k)), Vector3(0.1, 2.2, 0.1), fm, "Post")
	for sz in [-20.0, 20.0]: _box(n, Vector3(0, 2.0, sz), Vector3(yw, 0.06, 0.06), fm, "Rail")
	for sx in [-hw, hw]: _box(n, Vector3(sx, 2.0, 0), Vector3(0.06, 0.06, 40.0), fm, "Rail")
	var txs: Array = []
	for u in units:
		var ux := -hw + 14.0 + (yw - 56.0) * (float(u) + 0.5) / float(maxi(units, 1)) + 14.0
		var tk := _inst(n, Props3D.transformer(), _vc_mat(0.55), "Tank%d" % u, Vector3(ux, 0.3, -6.0)); tk.scale = Vector3.ONE * 3.0
		txs.append(tk)
	var shed := Node3D.new(); shed.name = "Switchgear"; shed.position = Vector3(hw - 14.0, 0, -12.0); n.add_child(shed)
	_box(shed, Vector3(0, 2.3, 0), Vector3(14.0, 4.6, 7.0), _soft_mat("rock", Color(0.66, 0.64, 0.60), 0.3, 0.16, 0.5, 0.4), "Walls")
	_box(shed, Vector3(0, 4.8, 0), Vector3(14.8, 0.4, 7.8), _mat(Color(0.30, 0.31, 0.34), 0.6, 0.2), "Roof")
	var wm := Stage8._win_mat(); wm.emission_energy_multiplier = 2.4; wm.emission = Bench3D.WARM
	for k in 4: _box(shed, Vector3(-5.0 + 3.3 * float(k), 2.5, 3.55), Vector3(1.6, 1.2, 0.1), wm, "Window")
	# the incoming line: one lattice tower north of the yard, three wires to a bus beam
	var sp: Array = Props3D.support("lattice", 24.0, 21.0)
	var tz := c.y - 60.0
	var tw := _inst(_root, sp[0], _vc_mat(0.6), "Incomer_" + pid, Vector3(c.x, ground(c.x, tz) - 0.3, tz))
	var hv := _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for k in 3:
		_box(n, Vector3(0, 9.4, -14.0 + 1.0 * float(k)), Vector3(yw - 20.0, 0.12, 0.12), hv, "Bus%d" % k)
		_inst(_root, _run([tw.position + (sp[1][k] as Vector3), Vector3(c.x, gy + 9.4, c.y - 14.0 + 1.0 * float(k))], 0.07, 1.2), hv, "Incomer%d_%d" % [k, int(c.x)], Vector3.ZERO, false)
	for sx in [-hw - 6.0, hw + 6.0]: _lamp_post(Vector2(c.x + sx, c.y + 22.0))
	for k in 2: Kit3D.flood_mast(n, Vector3((-hw + 1.0) if k == 0 else (hw - 1.0), 0.0, 19.0 if k == 0 else -19.0), Vector3.ZERO, quality, 14.0)   # 1128c
	Kit3D.aviation(_root, tw.position + Vector3(0, 24.6, 0), quality)
	dd.yard[pid] = {"node": n, "tanks": txs, "units": units, "pos": n.position, "shed_win": wm}
	anchors["yard_" + pid] = Vector3(c.x, gy + 14.0, c.y)

func _jumper(from: Vector3, hp: Node3D) -> void:
	var hvm := _mat(Color(0.14, 0.14, 0.15), 0.5, 0.6)
	for c in 3: _inst(_root, _run([from + Vector3(0, 0, (c - 1) * 0.5), Stage8._pa(hp, Stage3D.PH[c])], 0.05, 0.9), hvm, "Lead%d" % c, Vector3.ZERO, false)

## Poles from `prev` (already standing at a) to b, one every ~POLE_SP, the cross-arms square to the line.
func _chain2(prev: Node3D, a: Vector2, b: Vector2, nm: String) -> Array:
	var n := maxi(1, ceili(a.distance_to(b) / Stage8.POLE_SP))
	var yaw := _yaw(b - a)
	var out: Array = [prev]
	for j in range(1, n + 1):
		var p := a.lerp(b, float(j) / float(n))
		out.append(Stage8._pole(self, p.x, p.y, "%s_%d" % [nm, j], yaw))
	return out

func _build_feeder(f: Dictionary) -> void:
	var fid := str(f.id); var ln: Array = plan_d.pts[fid]; var secs: Array = f.sections
	var cable := str(f.get("kind", "")) == "cable"
	var alu := Stage8._alu(self)
	var rec := {"poles": [], "secs": []}
	var h0: Vector2 = ln[0]
	var prev: Node3D = Stage8._pole(self, h0.x, h0.y, "Head_" + fid, _yaw((ln[1] as Vector2) - h0))
	var yp: Vector3 = _yard_pos(str(f.primaryId)); var yc: Vector2 = plan_d.prim[str(f.primaryId)]
	var bk := _inst(_root, Props3D.breaker(), _vc_mat(0.55), "Breaker_" + fid, Vector3(h0.x, ground(h0.x, yc.y + 14.0) + 0.3, yc.y + 14.0)); bk.scale = Vector3.ONE * 1.0
	if not cable: _jumper(Vector3(h0.x, bk.position.y + 5.0, yc.y + 14.0), prev)
	rec["head"] = prev
	var per := houses_of(f)
	for k in secs.size():
		var sec: Dictionary = secs[k]; var sid := str(sec.id)
		var a: Vector2 = ln[k]; var b: Vector2 = ln[k + 1]
		var sr := {"id": sid, "fid": fid, "k": k, "a": a, "b": b, "poles": [], "glow": null, "cable_mat": null, "sw": null, "fuse": null}
		if cable:
			var len := a.distance_to(b); var mid := a.lerp(b, 0.5)
			var cm := StandardMaterial3D.new(); cm.albedo_color = Color(0.1, 0.1, 0.12); cm.emission_enabled = true; cm.emission = Color(0.4, 0.8, 0.4); cm.emission_energy_multiplier = 0.9
			var strip := _box(_root, Vector3(mid.x, ground(mid.x, mid.y) + 0.2, mid.y), Vector3(len, 0.12, 0.9), cm, "Cable_" + sid); strip.rotation.y = _yaw(b - a)
			var jb := _box(_root, Vector3(b.x, ground(b.x, b.y) + 0.25, b.y), Vector3(2.6, 0.3, 2.6), _mat(Color(0.35, 0.37, 0.42), 0.6, 0.3), "Joint_" + sid); jb.rotation.y = _yaw(b - a)
			sr["cable_mat"] = cm
		else:
			var poles := _chain2(prev, a, b, "%s_%d" % [fid, k + 1])
			Stage8._wire(self, poles, 0.1, alu, "Section_" + sid)
			var gm: ShaderMaterial = _hot_mat(0.0); gm.set_shader_parameter("inflate", 0.00022)
			Stage8._glow(self, poles, 0.1, gm, "Glow_" + sid)
			sr["glow"] = gm; sr["poles"] = poles
			var dev := str(sec.device)
			if k > 0 and dev == "manual" or k > 0 and dev == "remote":
				var sw := Stage8._switch(self, poles[0], "Switch_" + sid); Stage8._set_switch(sw, dev); sr["sw"] = sw
			elif k > 0 and dev == "fuse":
				sr["fuse"] = Stage8._cutouts(self, poles[0], "Cutouts_" + sid)
			prev = poles[poles.size() - 1]
		sr["village"] = _hamlet(sid, a, b, per, absi(k + 17 * fid.hash()) % 97)
		dd.sec[sid] = sr; (rec.secs as Array).append(sid)
		anchors[sid] = Vector3((a.x + b.x) * 0.5, ground((a.x + b.x) * 0.5, (a.y + b.y) * 0.5) + 14.0, (a.y + b.y) * 0.5)
	rec["tip"] = prev
	# hardware the engine says is there
	var head_pole: Node3D = rec.head
	if bool(f.recloser) and not cable: rec["recloser"] = Stage8._recloser(self, head_pole)
	if bool(f.regulator) and not cable:
		var rp := (ln[1] as Vector2).lerp(ln[mini(2, ln.size() - 1)], 0.5)
		var dir := ((ln[mini(2, ln.size() - 1)] as Vector2) - (ln[1] as Vector2)).normalized()
		var rg := Stage8._regulator(self, rp.x, "Regulator_" + fid)
		var side := Vector2(-dir.y, dir.x) * 4.0
		rg.position = Vector3(rp.x + side.x, ground(rp.x + side.x, rp.y + side.y), rp.y + side.y); rg.rotation.y = _yaw(dir); rg.visible = true
		rec["reg"] = rg
	var tipv: Vector2 = ln[ln.size() - 1]
	var tdir := (tipv - (ln[ln.size() - 2] as Vector2)).normalized()
	if float(f.batteryKw) > 0.0: rec["battery"] = _battery(fid, tipv + tdir * 16.0 + Vector2(-tdir.y, tdir.x) * 8.0, _yaw(tdir))
	if float(f.drKw) > 0.0: rec["dr"] = _dr_mast(fid, tipv + tdir * 14.0 - Vector2(-tdir.y, tdir.x) * 9.0)
	dd.fdr[fid] = rec

## A street of `n` homes round the point `t` of the section a-b, either side of the line. One body mesh and one window mesh for the whole street; its windows are one material.
func _hamlet(sid: String, a: Vector2, b: Vector2, n: int, seed_: int) -> Dictionary:
	var vn := Node3D.new(); vn.name = "Village_" + sid; _root.add_child(vn)
	var dir := (b - a).normalized(); var nrm := Vector2(-dir.y, dir.x)
	var c := a.lerp(b, VIL_AT)
	var stb := SurfaceTool.new(); stb.begin(Mesh.PRIMITIVE_TRIANGLES); var stw := SurfaceTool.new(); stw.begin(Mesh.PRIMITIVE_TRIANGLES)
	var per := (n + 1) / 2; var pts: Array = []
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0; var kk := i / 2
		var along := (float(kk) - float(per - 1) * 0.5) * 12.5 + (WorldMath.hash2(i, seed_, 31) - 0.5) * 2.0
		var hp := c + dir * along + nrm * side * (HOUSE_SIDE + 2.5 * WorldMath.hash2(i, seed_, 32))
		var hm: Array = Stage8._house_meshes(int(WorldMath.hash2(i, seed_, 33) * 6.0) % 6)
		var rot := atan2(-side * nrm.x, -side * nrm.y)
		var xf := Transform3D(Basis(Vector3.UP, rot), Vector3(hp.x, ground(hp.x, hp.y) - 0.1, hp.y))
		stb.append_from(hm[0], 0, xf); stw.append_from(hm[1], 0, xf)
		pts.append(hp)
	var body := MeshInstance3D.new(); body.name = "Homes"; body.mesh = stb.commit(); body.material_override = _vc_mat(0.9); vn.add_child(body)
	var wm := Stage8._win_mat()
	var win := MeshInstance3D.new(); win.name = "Windows"; win.mesh = stw.commit(); win.material_override = wm; win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; vn.add_child(win)
	var lt: OmniLight3D = null
	if quality != "low":
		lt = OmniLight3D.new(); lt.omni_range = 40.0; lt.omni_attenuation = 1.2; lt.light_specular = 0.2; lt.position = Vector3(c.x, ground(c.x, c.y) + 7.0, c.y); lt.light_energy = 0.0; vn.add_child(lt)
	# 1128c rollout: a lamp at each end of the street, off the lane, with the province's halo and pool; dark with the street's windows (_set_street)
	var grp := "dv_%s_%d" % [sid, seed_]
	for sg in [-1.0, 1.0]:
		var lp := c + dir * float(sg) * (float(per) * 6.25 + 3.0) + nrm * 3.0
		Kit3D.street_lamp(vn, Vector3(lp.x, ground(lp.x, lp.y) - 0.1, lp.y), atan2(-nrm.x, -nrm.y), quality, grp, 6.0)
	return {"node": vn, "mat": wm, "light": lt, "homes": n, "at": c, "pts": pts, "group": grp}

func _battery(fid: String, at: Vector2, yaw: float) -> Node3D:
	var n := Node3D.new(); n.name = "Battery_" + fid; n.position = Vector3(at.x, ground(at.x, at.y), at.y); n.rotation.y = yaw; _root.add_child(n)
	_box(n, Vector3(0, 0.1, 0), Vector3(16.0, 0.2, 7.0), _soft_mat("sand", Color(0.52, 0.50, 0.46), 0.3, 0.3, 0.0, 0.2), "Pad")
	var shell := _mat(Color(0.86, 0.88, 0.9), 0.5, 0.2)
	for k in 2:
		_box(n, Vector3(-3.3 + 6.6 * float(k), 1.6, 0), Vector3(6.0, 2.9, 2.5), shell, "Container%d" % k)
		_box(n, Vector3(-3.3 + 6.6 * float(k), 1.6, 1.27), Vector3(5.0, 0.35, 0.06), _emit_mat(Stage8.SAVED, 2.4), "Lamp%d" % k)
	return n

func _dr_mast(fid: String, at: Vector2) -> Node3D:
	var n := Node3D.new(); n.name = "DrMast_" + fid; n.position = Vector3(at.x, ground(at.x, at.y), at.y); _root.add_child(n)
	_inst(n, _cyl_mesh(Vector3.ZERO, Vector3(0, 9.0, 0), 0.16, Color(0.6, 0.62, 0.66), 8), _vc_mat(0.5), "Mast")
	_box(n, Vector3(0, 4.0, 0.3), Vector3(0.9, 0.7, 0.5), _mat(Color(0.28, 0.3, 0.33), 0.5, 0.3), "Box")
	var sm := SphereMesh.new(); sm.radius = 0.3; sm.height = 0.6
	_inst(n, sm, _emit_mat(Color("#E6A0FF"), 3.4), "Lamp", Vector3(0, 9.2, 0), false)
	return n

func _build_ties() -> void:
	var alu := _mat(Color(0.56, 0.58, 0.62), 0.4, 0.55)
	for t in plan_d.ties:
		var ra: Dictionary = dd.fdr[str(t[0])]; var rb: Dictionary = dd.fdr[str(t[1])]
		var pa: Node3D = ra.tip; var pb: Node3D = rb.tip
		var a := Vector2(pa.position.x, pa.position.z); var b := Vector2(pb.position.x, pb.position.z)
		var dir := (b - a).normalized(); var m := (a + b) * 0.5
		var yaw := _yaw(dir)
		var m1 := Stage8._pole(self, m.x - dir.x * 3.0, m.y - dir.y * 3.0, "TieA_%s" % str(t[0]), yaw)
		var m2 := Stage8._pole(self, m.x + dir.x * 3.0, m.y + dir.y * 3.0, "TieB_%s" % str(t[1]), yaw)
		Stage8._wire(self, [pa, m1], 0.08, alu, "TieWire_%s" % str(t[0])); Stage8._wire(self, [pb, m2], 0.08, alu, "TieWire_%s" % str(t[1]))
		var sw := Stage8._switch(self, m1, "TieSwitch_%s_%s" % [str(t[0]), str(t[1])]); Stage8._set_switch(sw, "remote")
		dd.tie.append({"a": str(t[0]), "b": str(t[1]), "switch": sw, "poles": [m1, m2]})
		anchors["tie_%s_%s" % [str(t[0]), str(t[1])]] = Vector3(m.x, ground(m.x, m.y) + 14.0, m.y)

## A named place of the story: the hospital, the charging hub, the wind turbine, the villages at the end of the feeder.
func _build_place(pl: Dictionary) -> void:
	var at: Vector2 = pl.at; var kind_ := str(pl.kind); var gy := ground(at.x, at.y)
	var n := Node3D.new(); n.name = "Place_%s_%s" % [kind_, str(pl.feeder)]; n.position = Vector3(at.x, gy, at.y); _root.add_child(n)
	var wm := Stage8._win_mat(); wm.emission_energy_multiplier = 0.0
	var rec := {"kind": kind_, "feeder": str(pl.feeder), "node": n, "mat": wm, "blades": null}
	match kind_:
		"hospital":
			_box(n, Vector3(0, 3.5, 0), Vector3(16.0, 7.0, 9.0), _soft_mat("rock", Color(0.80, 0.80, 0.82), 0.3, 0.16, 0.0, 0.3), "Block")
			_box(n, Vector3(0, 7.3, 0), Vector3(16.6, 0.5, 9.6), _mat(Color(0.5, 0.52, 0.56), 0.6, 0.2), "Roof")
			for r in 2: for k in 4: _box(n, Vector3(-6.0 + 4.0 * float(k), 2.2 + 2.8 * float(r), 4.55), Vector3(1.8, 1.3, 0.1), wm, "Window")
			var red := _emit_mat(Color(1.0, 0.15, 0.1), 1.6)
			_box(n, Vector3(0, 5.9, 4.6), Vector3(2.2, 0.6, 0.1), red, "CrossH"); _box(n, Vector3(0, 5.9, 4.6), Vector3(0.6, 2.2, 0.1), red, "CrossV")
		"hub":
			var cm := _emit_mat(Color(0.25, 0.65, 1.0), 2.6)
			_box(n, Vector3(0, 3.6, 0), Vector3(22.0, 0.4, 9.0), _mat(Color(0.82, 0.84, 0.88), 0.5, 0.3), "Canopy")
			for sx in [-10.0, 10.0]: for sz in [-3.5, 3.5]: _box(n, Vector3(sx, 1.8, sz), Vector3(0.3, 3.6, 0.3), _mat(Color(0.5, 0.52, 0.56), 0.5, 0.4), "Post")
			for k in 4: _box(n, Vector3(-7.5 + 5.0 * float(k), 1.0, 0), Vector3(0.7, 2.0, 0.5), cm, "Charger")
			_box(n, Vector3(0, 3.35, 4.35), Vector3(20.0, 0.12, 0.12), cm, "Edge")
			rec["mat"] = cm
		"turbine":
			_inst(n, _cyl_mesh(Vector3.ZERO, Vector3(0, 44.0, 0), 1.2, Color(0.9, 0.92, 0.94), 12), _vc_mat(0.5), "Tower")
			var rot := Node3D.new(); rot.name = "Rotor"; rot.position = Vector3(0, 44.0, 2.2); n.add_child(rot)
			var bm := _mat(Color(0.92, 0.94, 0.96), 0.4, 0.2)
			for b in 3:
				var piv := Node3D.new(); piv.rotation.z = TAU * float(b) / 3.0; rot.add_child(piv)
				_box(piv, Vector3(0, 11.0, 0), Vector3(0.9, 22.0, 0.3), bm, "Blade%d" % b)
			var lamp := _emit_mat(Color(1.0, 0.2, 0.15), 3.0); var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0
			_inst(n, sm, lamp, "Beacon", Vector3(0, 45.4, 0), false)
			rec["blades"] = rot; _spin.append({"node": rot, "w": 1.2, "axis": 2})
		_:   # "villages": the far end of the feeder: a few more homes on the road to the next place
			var ln: Array = plan_d.pts[str(pl.feeder)]
			var tip: Vector2 = ln[ln.size() - 1]
			var hs := _hamlet("pl_" + str(pl.feeder), tip, tip + Vector2(0.0, 60.0), 6, 77)
			rec["village"] = hs
	dd.place.append(rec)

# --------------------------------------------------------------------------------------------------------------------
# The engine's numbers onto the scene
# --------------------------------------------------------------------------------------------------------------------
func _set_street(vg: Dictionary, ws: Dictionary) -> void:
	var m: StandardMaterial3D = vg.mat
	m.emission = ws.col; m.emission_energy_multiplier = ws.e
	var lt = vg.light
	if lt != null: (lt as OmniLight3D).light_energy = float(ws.e) / Bench3D.WINDOW_E * Bench3D.HOME_LIGHT_E * 1.4; (lt as OmniLight3D).light_color = ws.col; (lt as OmniLight3D).visible = float(ws.e) > 0.02
	if vg.has("group"): Kit3D.set_group(str(vg.group), float(ws.e) > 0.02); Kit3D.set_level(str(vg.group), float(ws.e) / Bench3D.WINDOW_E)

func _apply_district() -> void:
	for f in dq.get("feeders", []):
		var fid := str(f.id); var out_f := hot.has(fid)
		for sec in f.sections:
			var sr: Dictionary = dd.sec[str(sec.id)]
			var ws := window_state(sec, f, out_f, mode)
			_set_street(sr.village, ws)
			sr["ws"] = ws
			var col := sec_colour(mode, f, sec)
			var dark: bool = ws.dark
			if sr.glow != null:
				(sr.glow as ShaderMaterial).set_shader_parameter("tint", Color(col, 1.0)); (sr.glow as ShaderMaterial).set_shader_parameter("power", 0.12 if dark else 0.55)
			if sr.cable_mat != null:
				(sr.cable_mat as StandardMaterial3D).emission = col; (sr.cable_mat as StandardMaterial3D).emission_energy_multiplier = 0.2 if dark else 1.1
	for pl in dd.place:
		var out_p := hot.has(str(pl.feeder))
		var m = pl.mat
		if m is StandardMaterial3D:
			if str(pl.kind) == "hospital": (m as StandardMaterial3D).emission_energy_multiplier = 0.0 if out_p else 2.6
			else: (m as StandardMaterial3D).emission_energy_multiplier = 0.3 if out_p else 2.6
		if pl.has("village"): _set_street(pl.village, {"dark": out_p, "e": 0.0 if out_p else Bench3D.WINDOW_E * 0.8, "col": Bench3D.WARM})
	for pid in dd.yard:
		var y: Dictionary = dd.yard[pid]
		(y.shed_win as StandardMaterial3D).emission_energy_multiplier = 2.4
	for l in _lamps:
		(l.mat as StandardMaterial3D).emission_energy_multiplier = Stage3D.LAMP_E
		if l.light != null: (l.light as OmniLight3D).light_energy = 1.4

## What the scene shows now (tests/career3d_truth.gd): the parts and what the engine's numbers became.
func report() -> Dictionary:
	var r := {"kind": "career", "yards": dd.yard.size(), "lines": dd.fdr.size(), "ties": dd.tie.size(), "places": dd.place.size()}
	var secs := {}
	for sid in dd.sec:
		var s: Dictionary = dd.sec[sid]
		var ws: Dictionary = s.get("ws", {})
		secs[sid] = {"fid": s.fid, "k": int(s.k), "homes": int(s.village.homes), "e": float((s.village.mat as StandardMaterial3D).emission_energy_multiplier), "dark": bool(ws.get("dark", false)),
			"lamp_on": Kit3D.group_on(str(s.village.group)), "col": (s.village.mat as StandardMaterial3D).emission, "sw": _sw_kind(s), "poles": (s.poles as Array).size(), "cable": s.cable_mat != null}
	r["sections"] = secs
	var hw := {}
	for fid in dd.fdr:
		var fr: Dictionary = dd.fdr[fid]
		hw[fid] = {"recloser": fr.has("recloser"), "reg": fr.has("reg") and (fr.reg as Node3D).visible, "battery": fr.has("battery"), "dr": fr.has("dr")}
	r["hardware"] = hw
	var units := {}
	for pid in dd.yard: units[pid] = (dd.yard[pid].tanks as Array).size()
	r["units"] = units
	r["tie_pairs"] = dd.tie.map(func(t): return [t.a, t.b])
	r["place_kinds"] = dd.place.map(func(p): return str(p.kind))
	return r

func _sw_kind(s: Dictionary) -> String:
	if s.sw != null: return Stage8._switch_kind(s.sw)
	if s.fuse != null: return "fuse"
	return "none"

# --------------------------------------------------------------------------------------------------------------------
# Camera: the whole district, from the south, inside the map's area of the screen
# --------------------------------------------------------------------------------------------------------------------
func reset_camera() -> void:
	var w := float(plan_d.get("width", 600.0))
	_g_target = Vector3(0.0, 0.0, 4.0); _g_yaw = 0.0; _g_pitch = deg_to_rad(38.0)
	_g_dist = clampf(w * 1.0 + 60.0, 380.0, DIST_FAR)
	var vp := get_viewport()
	var aspect := 16.0 / 9.0
	if vp != null:
		var vs := vp.get_visible_rect().size
		if vs.y > 0.0: aspect = vs.x / vs.y
	if view_rect.size.x > 1.0 and canvas_size.x > 1.0 and cam != null:   # the visible width is the map's share of the screen: back off until the whole district fits it
		_g_dist = clampf((w + 190.0) * canvas_size.y / (view_rect.size.x * 2.0 * tan(deg_to_rad(cam.fov * 0.5))), 300.0, DIST_FAR)
	else: _g_dist *= clampf((16.0 / 9.0) / aspect, 1.0, 1.4)
	_dist_default = _g_dist
	_g_target.y = ground(_g_target.x, _g_target.z) + 4.0
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist
	if view_rect.size.x > 1.0 and canvas_size.x > 1.0 and cam != null and cam.is_inside_tree():   # slide the target until the district's centre lands on the middle of the map's rect
		var mpp := 2.0 * _g_dist * tan(deg_to_rad(cam.fov * 0.5)) / canvas_size.y
		var right := Vector3(cos(_g_yaw), 0.0, -sin(_g_yaw)); var fwd := Vector3(-sin(_g_yaw), 0.0, -cos(_g_yaw))
		for _i in 3:
			_apply_camera()
			var pc := project(Vector3(0.0, 6.0, (Z_TOP + Z_BOT) * 0.5 + 4.0))
			if pc.x < -9000.0: break
			var err := view_rect.get_center() - pc
			_g_target += right * (-err.x * mpp) + fwd * (err.y * mpp / maxf(sin(_g_pitch), 0.3))
			_g_target.y = ground(_g_target.x, _g_target.z) + 4.0
			target = _g_target
	_apply_camera()

## The screen area the map takes: the camera frames the district inside it (until the player moves the camera).
func fit_to(r: Rect2) -> void:
	if r.is_equal_approx(view_rect): return
	view_rect = r
	if field != null and not _touched: reset_camera()

func _clamp_goal() -> void:
	var b := _play.grow(40.0)
	_g_target.x = clampf(_g_target.x, b.position.x, b.end.x); _g_target.z = clampf(_g_target.z, b.position.y, b.end.y)
	_g_target.y = ground(_g_target.x, _g_target.z) + 4.0
	_g_pitch = clampf(_g_pitch, PITCH_MIN, PITCH_MAX)
	_g_dist = clampf(_g_dist, 30.0, DIST_FAR)

func pan_px(rel: Vector2) -> void: _touched = true; super.pan_px(rel)
func orbit_px(rel: Vector2) -> void: _touched = true; super.orbit_px(rel)
func zoom_at(sp: Vector2, f: float) -> void: _touched = true; super.zoom_at(sp, f)
func set_camera_spec(spec: String) -> bool:
	_touched = true
	return super.set_camera_spec(spec)

## The wire's height over a plan point: what CareerMap projects for a section boundary.
func wire_point(p: Vector2) -> Vector3: return Vector3(p.x, ground(p.x, p.y) + Stage3D.L10_H - 0.5, p.y)
func yard_point(pid: String) -> Vector3:
	var c: Vector2 = plan_d.prim[pid]
	return Vector3(c.x, ground(c.x, c.y) + 24.0, c.y - 30.0)   # the plate hangs over the incoming tower, clear of the yard
func place_point(i: int) -> Vector3:
	var at: Vector2 = plan_d.places[i].at
	return Vector3(at.x, ground(at.x, at.y) + 12.0, at.y)
