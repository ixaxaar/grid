class_name WorldModel
extends RefCounted
## Builds the diorama's model from the engine: `world` (geometry, flow sign, shed share), `overlay('voltage')` (bus V, pu), `overlay('loading')`
## (branch loading, fraction of rating), `benchStatus`-style numbers inside `world.bench`, and `clock`. Every visual quantity (window energy,
## pulse speed, ribbon width and colour band) is computed here by WorldMath from those engine values; the drawing only reads this model, and the
## truth tests (godot/tests) read it back and compare it with the raw queries. Pure data out: Dictionaries, Arrays, Vector2, no nodes.

const BENCH_HUT := Vector2(3, 8)
# L01 geometry, 1 tile = 10 m so the drawn cable is as long as the engine's run: beach row y = 12, hamlet 70 m up the rise.
const L01_MAP := Vector2(36, 17)
const L01_HAMLET := Vector2(29, 5)
const L01_BEACH_Y := 12.0
const L01_MANGROVE := Rect2(7, 6, 19, 4)   # tiles; blocked for cables (DESIGN L01), the reason the cable follows the beach

## Where the battery hut stands for a cable run of `d` metres: along the beach west of the corner below the hamlet.
static func l01_hut_pos(d: float) -> Vector2:
	var vertical := (L01_BEACH_Y - L01_HAMLET.y) * 10.0
	return Vector2(L01_HAMLET.x - (d - vertical) / 10.0, L01_BEACH_Y)

## Presentation only (1128c province round 3): a job whose brief is about the evening peak opens its 3D view at that hour, before the player presses Run.
## The engine's day, its clock and every number stay as they are; the dial and the radio read this hour while the job is fresh (instruments.gd, radio_log.gd),
## and the scene returns to the engine's hour with the first block. Returns the minute of the day, or -1 when the job has no preview.
const PREVIEW_MINUTE := {"L16": 1110.0}   # WO-16: the evening peak, drawn at 18:30 (the sunset glow; the brief reads the peak at 19:00)
static func preview_minute(level: String, tick: int, level_start) -> float:
	if not PREVIEW_MINUTE.has(level) or level_start == null: return -1.0
	return float(PREVIEW_MINUTE[level]) if tick <= int(level_start) else -1.0

static func empty() -> Dictionary:
	return {"kind": "none", "level": "", "map": Vector2(26, 16), "minute": 0.0, "night": 1.0, "towns": [], "subs": [], "lines": [], "units": [], "shunts": [], "blackout": false, "terrain": {}, "routes": []}

static func build(b) -> Dictionary:
	var m := empty()
	var clk = b.q("clock")
	if clk is Dictionary and not clk.is_empty():
		m.minute = float(clk.minuteOfDay); m.night = WorldMath.night(m.minute)
	var qa_min := OS.get_environment("CB_WORLD_MINUTE")   # QA screenshots only: L03 starts at 08:00 and ends before dusk
	if qa_min != "": m.minute = float(qa_min); m.night = WorldMath.night(m.minute)
	var w = b.q("world", [_known_terrain]) if _known_terrain != "" else b.q("world")   # the map's tiles travel once per level
	if not (w is Dictionary) or w.is_empty(): return m
	var wt = w.get("terrain")
	if wt is Dictionary and _known_terrain != "" and not _terrain_cache.has(str(wt.id)): _known_terrain = ""; w = b.q("world")   # a stale id: ask again in full
	elif wt is Dictionary: _known_terrain = str(wt.id)
	m.kind = str(w.kind); m.level = str(w.get("level", "")); m.blackout = bool(w.get("blackout", false))
	var pv := -1.0 if qa_min != "" else preview_minute(str(m.level), int(clk.tick) if clk is Dictionary and not clk.is_empty() else 1 << 30, b.g.get("levelStart"))
	if pv >= 0.0: m.minute = pv; m.night = WorldMath.night(pv); m["preview"] = true
	m["solved"] = bool(w.get("solved", true))   # before the first solve nothing is "dark" yet: the grid has not been worked out
	if w.kind == "bench": _bench(m, w)
	elif w.kind == "grid": _grid(m, w, b)
	return m

## Terrain tile characters of the engine (world.terrain.rows) and the tile kinds the diorama draws.
const TERRAIN_KINDS := {"f": "field", "s": "swamp", "r": "river", "w": "forest", "k": "rock", "a": "sand", "e": "sea", "t": "town", "d": "road"}
static var _terrain_cache := {}
static var _known_terrain := ""

## world.terrain as flat arrays: kinds[j * cols + i] (kind names) and elev[...] in metres. Cached by terrain id (the map never changes inside a level).
static func terrain_of(tr: Dictionary) -> Dictionary:
	var id := str(tr.id)
	if _terrain_cache.has(id): return _terrain_cache[id]
	var cols := int(tr.cols); var nrows := int(tr.nrows)
	var kinds := PackedStringArray(); var elev := PackedFloat32Array()
	for j in nrows:
		var row := str(tr.rows[j])
		for i in cols: kinds.append(str(TERRAIN_KINDS.get(row[i], "field")))
	for e in tr.elev: elev.append(float(e))
	var poll := PackedByteArray(); var ps := str(tr.get("pollution", ""))
	for k in cols * nrows: poll.append(int(ps[k]) if k < ps.length() else 1)   # IEC 60815 class per tile, from the engine's planner
	var t := {"id": id, "cols": cols, "rows": nrows, "tile_m": float(tr.tileM), "kinds": kinds, "elev": elev, "poll": poll}
	_terrain_cache[id] = t
	return t

static func _grid(m: Dictionary, w: Dictionary, b) -> void:
	m.map = Vector2(float(w.map.w), float(w.map.h))
	var has_terrain: bool = w.get("terrain") is Dictionary and not (w.terrain as Dictionary).is_empty()
	if has_terrain:
		m["terrain"] = terrain_of(w.terrain); m["tile_m"] = float(w.terrain.tileM)
		var isl := Vector2.ZERO; var n_off := 0   # an offshore island (L30): the map grows south with open sea to the island's buses
		for bus in w.buses: if bool(bus.get("offshore", false)): isl += Vector2(float(bus.x), float(bus.y)); n_off += 1
		if n_off > 0:
			isl /= float(n_off); m["island_c"] = isl + Vector2(0.5, 0.5)
			m.map = Vector2(m.map.x, maxf(m.map.y, isl.y + 4.0))
		var lif = b.q("levelInfo")   # a sea-fog job: the salt is drawn on the coast and the fog rolls in around its hour
		if lif is Dictionary and lif.get("cableCutBlock") != null: m["cut_min"] = float(lif.cableCutBlock) * 15.0   # L30: the trawler's anchor
		if lif is Dictionary and lif.get("fogBlock") != null and str(lif.get("fogTime", "")) != "":
			var hm := str(lif.fogTime).split(":"); m["fog_min"] = float(int(hm[0]) * 60 + (int(hm[1]) if hm.size() > 1 else 0))
		for r in w.get("routes", []): m.routes.append(RouteDraw.plan_to_route(r, str(r.branchId), float(w.terrain.tileM)))
	var live := {}   # bus id -> energised: a line between dead buses carries no flow, so it shows no pulses
	var vv: Dictionary = (b.q("overlay", ["voltage"]) as Dictionary).get("values", {})
	var ll: Dictionary = (b.q("overlay", ["loading"]) as Dictionary).get("values", {})
	var pos := {}; var kvs := {}
	for bus in w.buses:
		var p := Vector2(float(bus.x), float(bus.y)); pos[bus.id] = p; kvs[bus.id] = float(bus.kv); live[bus.id] = bool(bus.get("energised", true))
		var v: float = float(vv[bus.id]) if vv.has(bus.id) else 0.0
		if not vv.has(bus.id) and (str(m.level) == "P0" or PREVIEW_MINUTE.has(str(m.level))) and not bool(m.solved): v = 1.0   # 1.19: the prologue opens on a running grid at 02:00; the engine solves at the first block. Until then the city shows lit (labels give names only, as on any unsolved grid)
		if float(bus.demandMW) > 0.0 or float(bus.peakMW) > 0.0 or bus.kind == "load":
			var n := clampi(6 + int((float(bus.peakMW) if float(bus.peakMW) > 0.0 else float(bus.demandMW)) / 4.0), 6, 40) if not has_terrain else 14   # 1.8: from the stable peak, not live demand (a heatwave above the peak changed the house count every tick, and every change rebuilt the whole map)   # a market town on the 50 m map: more roofs
			m.towns.append(_town(str(bus.id), str(bus.name), p, n, v, float(bus.shed), "town", 0))
			if has_terrain:   # chapter 2: the market gets the bulb mascot; its face is the voltage band (the level's band floor from levelInfo, worried within 0.02 pu)
				var tw: Dictionary = m.towns[-1]
				tw["mascot"] = true; tw["volts"] = v * float(bus.kv) * 1000.0
				var li = b.q("levelInfo"); var lo := 0.94
				if li is Dictionary and li.get("thresholds") is Dictionary: lo = float((li.thresholds as Dictionary).get("villageBandLoPu", 0.94))   # the engine's band, per pack
				tw["mood"] = "asleep" if v <= 0.0 else ("sad" if v < lo else ("worried" if v < lo + 0.02 else "happy"))
		else:
			m.subs.append({"id": str(bus.id), "name": str(bus.get("name", bus.id)), "pos": p, "kv": float(bus.kv), "v": v, "energised": v > 0.0})
	for br in w.branches:
		var a: Vector2 = pos.get(br["from"], Vector2.ZERO); var c: Vector2 = pos.get(br.to, Vector2.ZERO)
		var pts: Array = [a]
		for wp in br.waypoints: pts.append(Vector2(float(wp[0]), float(wp[1])))
		pts.append(c)
		var load_f: float = float(ll.get(br.id, 0.0))
		var fdir := WorldMath.flow_dir(float(br.pFromMW))
		if m.blackout or not (bool(live.get(br["from"], true)) and bool(live.get(br.to, true))): fdir = 0   # pulses only where the engine reports flow on an energised line
		m.lines.append(_line(str(br.id), pts, load_f, fdir, bool(br.inService), int(br.circuits), float(kvs.get(br["from"], 11.0)), float(br.overloadFrac), str(br.kind)))
	for u in w.units:
		m.units.append({"id": str(u.id), "pos": pos.get(u.bus, Vector2.ZERO), "kind": str(u.kind), "online": bool(u.online), "level": 0.0 if float(u.pMax) <= 0.0 else clampf(float(u.P) / float(u.pMax), 0.0, 1.0), "rotor": WorldMath.rotor_speed(float(u.availMW), float(u.pMax))})
	m["batteries"] = []   # batteries (L30 island): position, charge and output, drawn as a hut whose fill is the charge
	for x in w.get("storage", []): m.batteries.append({"id": str(x.id), "pos": pos.get(x.bus, Vector2.ZERO), "soc": float(x.soc), "p": float(x.pMW), "mwh": float(x.mwh)})
	for h in w.shunts: m.shunts.append({"id": str(h.id), "pos": pos.get(h.bus, Vector2.ZERO), "on": int(h.on), "steps": int(h.steps), "kind": str(h.kind)})

static func _bench(m: Dictionary, w: Dictionary) -> void:
	var bn: Dictionary = w.bench
	m.map = Vector2(26, 16)
	var sc := str(bn.scenario)
	var hut = bn.hutM
	var vs: Array = bn.vLoadV
	var vsrc := float(bn.sourceV)
	var amp := float(bn.ampFracMax)
	var powered := bool(bn.powered)
	var hut_p := BENCH_HUT
	var targets: Array = []   # [pos, count, label kind]
	var runs: Array = []      # [line id, polyline in tiles, mm2 or null]: every cable of the level as laid, drawn length x tile metres = the engine's runLength
	var routes: Array = []    # every route any design may take (terrain keeps them dry land, whatever is laid)
	m["tile_m"] = 10.0
	if sc == "l01":   # Saltmarsh Island at 10 m per tile: the hamlet sits on the rise, the hut on the south beach, the cable runs along the beach
		m.map = L01_MAP
		hut_p = l01_hut_pos(float(hut) if hut != null else 300.0); targets.append([L01_HAMLET, 10, "hamlet"])
		var r1: Array = [hut_p, Vector2(L01_HAMLET.x, L01_BEACH_Y), L01_HAMLET]
		if hut != null: runs.append(["main", r1, bn.mainMm2])
		routes.append([l01_hut_pos(300.0), Vector2(L01_HAMLET.x, L01_BEACH_Y), L01_HAMLET])
		m["island"] = {"beach_y": L01_BEACH_Y, "mangrove": L01_MANGROVE, "routes": routes}
	elif sc == "l02":   # Two Hamlets, 10 m per tile; the hut is fixed on the west beach, hamlet 2 lies across a lagoon so every cable goes round it
		m.map = L02_MAP; hut_p = L02_HUT
		targets.append([L02_H1, 10, "hamlet"]); targets.append([L02_H2, 14, "hamlet"])
		var trunk := str(bn.topology) == "trunk"
		if trunk:
			runs.append(["main", [L02_HUT, L02_J], bn.mainMm2]); runs.append(["b", [L02_J, L02_H1], bn.branchMm2]); runs.append(["b2", l02_route_b2(), bn.branchMm2])
		else:
			runs.append(["main", l02_route_radial(0), bn.mainMm2]); runs.append(["b", l02_route_radial(1), bn.branchMm2])
		routes = [l02_route_radial(0), l02_route_radial(1), [L02_HUT, L02_J, L02_H1], l02_route_b2()]
		m["island"] = {"beach_y": L02_BEACH_Y, "mangrove": L02_MANGROVE, "lagoon": L02_LAGOON, "routes": routes}
	else:   # The Price of Distance: 1 tile = 25 m (not 10: 1 km would be 100 tiles); drawn length x 25 m = the 1000 m run, honest per tile scale
		m.map = L03_MAP; hut_p = L03_HUT; m["tile_m"] = L03_TILE_M
		targets.append([L03_SCHOOL, 2, "school"])
		runs.append(["main", l03_route(), bn.mainMm2]); routes.append(l03_route())
		m["island"] = {"beach_y": L03_BEACH_Y, "mangrove": L03_MANGROVE, "hill": {"pos": L03_SCHOOL, "r": 13.0, "h": 48.0}, "routes": routes}
	m.units.append({"id": "hut", "pos": hut_p, "kind": "hut", "online": powered, "level": 1.0 if powered else 0.0, "rotor": 0.0})
	if sc == "l01" and hut == null: m.units.clear()
	for i in targets.size():
		var t: Array = targets[i]
		var v := 0.0
		if powered and i < vs.size(): v = float(vs[i]) / vsrc
		var tw := _town("h%d" % (i + 1), "", t[0], int(t[1]), v, 0.0, str(t[2]), i); tw["volts"] = v * vsrc
		var lim = bn.get("vMinLimitV")
		tw["limit"] = float(lim) if lim != null else 0.0
		tw["mood"] = WorldMath.mood(v * vsrc, tw.limit, powered)
		if sc == "l03":   # the school is judged on line losses, not on a home voltage: the label and the face follow the losses
			var lm = bn.get("lossMaxPct")
			tw["loss"] = float(bn.get("lossPct", 100.0)); tw["loss_max"] = float(lm) if lm != null else 5.0
			tw["mood"] = WorldMath.mood_loss(tw.loss, tw.loss_max, powered)
		m.towns.append(tw)
	if sc == "l02" and str(bn.topology) == "trunk": m.subs.append({"id": "j", "pos": L02_J, "kv": 0.048, "v": 1.0, "energised": powered})
	if sc == "l03" and bool(bn.converters):
		m.subs.append({"id": "c0", "pos": hut_p + Vector2(1.6, -0.9), "kv": 0.38, "v": 1.0, "energised": powered})
		m.subs.append({"id": "c1", "pos": L03_SCHOOL + Vector2(-2.2, 1.4), "kv": 0.38, "v": 1.0, "energised": powered})
	var dirp := 1 if powered else 0
	m["ghosts"] = []; m["ghost_ids"] = []   # ghost_ids[k] = the run id (main / b / b2) of ghosts[k]: the tray and tags pick surveyed routes by it
	for r in runs:
		if r[2] == null: m.ghosts.append(r[1]); m.ghost_ids.append(str(r[0])); continue   # surveyed but not yet laid: a dashed route
		m.lines.append(_line(str(r[0]), r[1], amp, dirp, true, 1, 0.048, 0.0, "cable")); m.lines[-1]["mm2"] = r[2]

# L02 geometry, 1 tile = 10 m. Hut on the west beach, hamlet 1 on the rise (15,10), hamlet 2 (28,10) across a lagoon: the straight line
# hut -> hamlet 2 would cross the water, so cables follow the beach (row 14) and turn up on the far shore. Engine runs: radial 120 m and
# 250 m; trunk 100 m, then 40 m and 160 m from the junction box.
const L02_MAP := Vector2(36, 19)
const L02_BEACH_Y := 14.0
const L02_HUT := Vector2(5, 14)
const L02_J := Vector2(15, 14)
const L02_H1 := Vector2(15, 10)
const L02_H2 := Vector2(28, 10)
const L02_LAGOON := Rect2(19, 6, 5, 6)      # tiles; water, cables never cross it
const L02_MANGROVE := Rect2(17, 3, 9, 3)
## Radial cable to hamlet `k` (0, 1): 7 + 5 = 12 tiles; 20 + 5 = 25 tiles.
static func l02_route_radial(k: int) -> Array:
	return [L02_HUT, Vector2(12, 14), L02_H1] if k == 0 else [L02_HUT, Vector2(25, 14), L02_H2]
## Trunk branch junction -> hamlet 2: along the beach to x = 15 + 71/6, then up to the hamlet: 11.833 + 4.167 = 16 tiles.
static func l02_route_b2() -> Array:
	return [L02_J, Vector2(15.0 + 71.0 / 6.0, 14), L02_H2]

# L03 geometry, 1 tile = 25 m (NOT 10 m: 1 km would be 100 tiles). The drawn cable is 23 + 17 = 40 tiles = 1000 m at that scale: along the
# beach (23 tiles), then 17 tiles (8 across, 15 up) climbing the hill to the school and health post.
const L03_TILE_M := 25.0
const L03_MAP := Vector2(56, 27)
const L03_BEACH_Y := 21.0
const L03_HUT := Vector2(6, 21)
const L03_SCHOOL := Vector2(37, 6)
const L03_MANGROVE := Rect2(14, 13, 12, 5)
static func l03_route() -> Array:
	return [L03_HUT, Vector2(29, 21), L03_SCHOOL]

static func _town(id: String, nm: String, p: Vector2, count: int, v: float, shed: float, kind: String, idx: int) -> Dictionary:
	var en := PackedFloat32Array(); var sum := 0.0
	for i in count:
		var e := WorldMath.building_energy(v, shed, i, count); en.append(e); sum += e
	return {"id": id, "name": nm, "pos": p, "count": count, "v": v, "shed": shed, "kind": kind, "idx": idx, "energies": en, "energy": sum / float(maxi(count, 1))}

static func _line(id: String, pts: Array, loading: float, dir: int, in_service: bool, circuits: int, kv: float, overload: float, kind: String) -> Dictionary:
	var bd := WorldMath.BAND_OFF
	var spd := 0.0; var wd := 2.0; var col := WorldMath.GREY
	if in_service:
		bd = WorldMath.band(loading); col = WorldMath.band_color(bd)
		spd = WorldMath.pulse_speed(loading) if dir != 0 else 0.0; wd = WorldMath.ribbon_width(loading)
	return {"id": id, "pts": pts, "loading": loading, "dir": dir, "speed": spd, "width": wd, "band": bd, "color": col, "in_service": in_service, "circuits": circuits, "kv": kv, "overload": overload, "kind": kind}
