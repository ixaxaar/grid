extends SceneTree
## The Career's district in 3D (world3d/district3d.gd) shows the engine's `career` query, read back from the scene it builds headless: one yard for each primary (a tank for
## each unit), one wood-pole line for each feeder with its sections in order and a street of homes at every one, the streets dark for a feeder with an open incident and for a
## section that is out of service (and a worse loading or health never a brighter window), the hardware where the engine says it is (the devices at the section heads from the real
## query; a recloser, regulator, battery, demand-response mast, tie and the extra unit from the same query with the flag set), the named places. Then the map over it: CareerMap,
## given the district, takes its section boundaries off the camera's projection of the scene, and a pick at a section's projected place picks that section, also after the camera
## has turned; the classic map is untouched when it has no district.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var T := Truth.new()
	if not T.start(root): print("CAREER3D-TRUTH FAILED engine"); quit(1); return
	GridUi.load_strings()
	root.size = Vector2i(1920, 1080)
	await process_frame
	for ch in ["standard", "city", "moor"]:
		var r := T.b.act("careerStart", [7, ch])
		T.check(bool(r.get("ok", true)), "careerStart %s" % ch)
		var d: Dictionary = T.b.q("career")
		var dn := District3D.new(); root.add_child(dn)
		dn.canvas_size = Vector2(1920, 1080)
		dn.set_district(d)
		await process_frame
		_layout(T, d, dn, ch)
		_streets(T, d, dn, ch)
		_hardware(T, d, dn, ch)
		_places(T, d, dn, ch)
		await _map(T, d, dn, ch)
		dn.queue_free()
		await process_frame
	await _incident(T)
	_pure(T)
	T.finish("CAREER3D-TRUTH", self)

func _feeders(d: Dictionary) -> Array: return d.feeders

func _layout(T: Truth, d: Dictionary, dn: District3D, tag: String) -> void:
	var rp := dn.report()
	T.check(int(rp.yards) == (d.primaries as Array).size(), "%s: one yard for each primary (%d of %d)" % [tag, int(rp.yards), (d.primaries as Array).size()])
	T.check(int(rp.lines) == (d.feeders as Array).size(), "%s: one line for each feeder (%d of %d)" % [tag, int(rp.lines), (d.feeders as Array).size()])
	for p in d.primaries: T.check(int(rp.units[str(p.id)]) == (p.units as Array).size(), "%s: %s has a tank for each of its %d units" % [tag, str(p.id), (p.units as Array).size()])
	var pl: Dictionary = dn.plan_d
	T.check((pl.order as Array).size() == (d.feeders as Array).size(), "%s: the plan orders every feeder" % tag)
	var secs: Dictionary = rp.sections
	var want := 0
	for f in d.feeders:
		var fid := str(f.id); var ln: Array = pl.pts[fid]
		T.check(ln.size() == (f.sections as Array).size() + 1, "%s: %s has a boundary for each of its sections and the head" % [tag, fid])
		T.check((pl.head[fid] as Vector2).is_equal_approx(ln[0]), "%s: %s leaves its primary's fence" % [tag, fid])
		var prim: Vector2 = pl.prim[str(f.primaryId)]
		T.check(absf((ln[0] as Vector2).x - prim.x) <= float(pl.yard_w[str(f.primaryId)]) * 0.5 and (ln[0] as Vector2).y > prim.y, "%s: %s's head is on the south side of yard %s" % [tag, fid, str(f.primaryId)])
		for k in (f.sections as Array).size():
			want += 1
			var sid := str(f.sections[k].id)
			T.check(secs.has(sid), "%s: section %s is in the scene" % [tag, sid])
			if not secs.has(sid): continue
			T.check(int(secs[sid].k) == k and str(secs[sid].fid) == fid, "%s: %s is section %d of %s" % [tag, sid, k, fid])
			T.check((ln[k + 1] as Vector2).y > (ln[k] as Vector2).y, "%s: %s runs away from the primary (section %d is further south than %d)" % [tag, fid, k, k - 1])
			T.check(int(secs[sid].homes) >= 4, "%s: %s has a street of homes (%d)" % [tag, sid, int(secs[sid].homes)])
			if str(f.get("kind", "")) != "cable": T.check(int(secs[sid].poles) >= 2, "%s: %s stands on poles (%d)" % [tag, sid, int(secs[sid].poles)])
			else: T.check(bool(secs[sid].cable), "%s: %s is a cable, not poles" % [tag, sid])
	T.check(secs.size() == want, "%s: the scene has exactly the engine's %d sections (%d)" % [tag, want, secs.size()])
	var xs: Array = []
	for pid in pl.prim: xs.append((pl.prim[pid] as Vector2).x)
	if xs.size() == 2: T.check(absf(float(xs[0]) - float(xs[1])) > 150.0, "%s: the two yards stand well apart" % tag)
	var again := dn.dd
	dn.set_district(d)
	T.check(dn.dd == again, "%s: the same data does not rebuild the place" % tag)

func _streets(T: Truth, d: Dictionary, dn: District3D, tag: String) -> void:
	dn.set_district(d, "load", [])
	var rp := dn.report(); var secs: Dictionary = rp.sections
	for f in d.feeders:
		for sc in f.sections:
			var s: Dictionary = secs[str(sc.id)]
			var out := bool(sc.failed) and float(sc.outQ) > 0.0
			T.check(bool(s.dark) == out and (float(s.e) <= 0.0) == out, "%s: %s's windows %s as the engine's section says" % [tag, str(sc.id), "are dark" if out else "are lit"])
			T.check(bool(s.lamp_on) == not out, "%s: %s's street lamps %s with its windows" % [tag, str(sc.id), "are dark" if out else "are on"])
	var f0: Dictionary = d.feeders[1]
	dn.set_district(d, "load", [str(f0.id)])
	secs = dn.report().sections
	for sc in f0.sections: T.check(not bool(secs[str(sc.id)].lamp_on), "%s: %s's lamps are dark with the open incident" % [tag, str(sc.id)])
	for sc in f0.sections: T.check(bool(secs[str(sc.id)].dark) and float(secs[str(sc.id)].e) == 0.0, "%s: %s is dark while %s has an open incident" % [tag, str(sc.id), str(f0.id)])
	for sc in (d.feeders[0] as Dictionary).sections: T.check(float(secs[str(sc.id)].e) > 0.0, "%s: %s on the other feeder stays lit" % [tag, str(sc.id)])
	# the colour mode: load follows the feeder, health follows the section
	dn.set_district(d, "load", []); var by_load: Dictionary = dn.report().sections
	dn.set_district(d, "health", []); var by_health: Dictionary = dn.report().sections
	var differ := 0
	for sid in by_load: if not is_equal_approx(float(by_load[sid].e), float(by_health[sid].e)): differ += 1
	T.check(differ > 0, "%s: the windows follow the colour mode (%d sections differ between load and health)" % [tag, differ])
	dn.set_district(d, "load", [])

func _hardware(T: Truth, d: Dictionary, dn: District3D, tag: String) -> void:
	var rp := dn.report(); var secs: Dictionary = rp.sections
	for f in d.feeders:
		for k in (f.sections as Array).size():
			var sc: Dictionary = f.sections[k]
			if str(f.get("kind", "")) == "cable": continue
			var want := str(sc.device) if k > 0 else "none"
			T.check(str(secs[str(sc.id)].sw) == want, "%s: %s carries its %s device (%s)" % [tag, str(sc.id), str(sc.device), str(secs[str(sc.id)].sw)])
	for f in d.feeders:
		var h: Dictionary = rp.hardware[str(f.id)]
		T.check(bool(h.recloser) == bool(f.recloser) and bool(h.reg) == bool(f.regulator) and bool(h.battery) == (float(f.batteryKw) > 0.0) and bool(h.dr) == (float(f.drKw) > 0.0), "%s: %s has the hardware the engine lists" % [tag, str(f.id)])
	var ties := 0
	for f in d.feeders: if bool(f.tie): ties += 1
	T.check(int(rp.ties) >= (ties + 1) / 2 and int(rp.ties) <= ties, "%s: a tie line for each tied pair (%d for %d flagged feeders)" % [tag, int(rp.ties), ties])
	# the same query with devices set: they appear
	var dc: Dictionary = d.duplicate(true)
	var f1: Dictionary = dc.feeders[0]; var f2: Dictionary = dc.feeders[2]
	f1["recloser"] = true; f1["regulator"] = true; f1["batteryKw"] = 600.0; f1["drKw"] = 300.0
	f2["tie"] = true
	(dc.primaries[0].units as Array).append((dc.primaries[0].units as Array)[0].duplicate(true))
	dn.set_district(dc)
	var rp2 := dn.report()
	var h1: Dictionary = rp2.hardware[str(f1.id)]
	var overhead := str(f1.get("kind", "")) != "cable"
	T.check(bool(h1.battery) and bool(h1.dr), "%s: %s shows its battery and its demand-response mast" % [tag, str(f1.id)])
	if overhead: T.check(bool(h1.recloser) and bool(h1.reg), "%s: %s shows its recloser and its regulator" % [tag, str(f1.id)])
	T.check(int(rp2.units[str(dc.primaries[0].id)]) == (d.primaries[0].units as Array).size() + 1, "%s: a third unit is a third tank in the yard" % tag)
	T.check(int(rp2.ties) >= int(rp.ties), "%s: a flagged tie is not lost" % tag)
	var plain: Dictionary = rp.hardware[str(f1.id)]
	T.check(not bool(plain.battery) or bool(d.feeders[0].batteryKw > 0.0), "%s: without the flag %s has no battery" % [tag, str(f1.id)])
	dn.set_district(d)

func _places(T: Truth, d: Dictionary, dn: District3D, tag: String) -> void:
	var kinds: Array = dn.report().place_kinds
	var want: Array = []
	for pl in d.get("places", []): if str(pl.kind) != "ducts": want.append(str(pl.kind))
	want.sort(); kinds = kinds.duplicate(); kinds.sort()
	T.check(kinds == want, "%s: the story's places stand in the district %s vs %s" % [tag, str(kinds), str(want)])
	for p in dn.plan_d.places: T.check(str(p.name) != "" and dn.plan_d.pts.has(str(p.feeder)), "%s: place '%s' is on its feeder" % [tag, str(p.name)])

func _map(T: Truth, d: Dictionary, dn: District3D, tag: String) -> void:
	var m := CareerMap.new(); m.d3 = dn; dn.visible = true
	root.add_child(m); m.position = Vector2.ZERO; m.size = Vector2(1340, 720)
	m.mode = "load"; m.set_data(d)
	await process_frame; await process_frame
	T.check(m._d3_mode(), "%s: the map reads the district" % tag)
	for turn in ["", "yaw=28,pitch=32", "yaw=-35,pitch=50,zoom=1.6"]:
		if turn != "": dn.set_camera_spec(turn); m._layout(true)
		var seen := 0; var hit := 0
		for f in d.feeders:
			for sc in f.sections:
				var s := {"type": "section", "id": str(sc.id), "feeder": str(f.id)}
				var p := m.point_of(s)
				if p.x < 0.0 or p.x > m.size.x or p.y < 0.0 or p.y > m.size.y: continue
				seen += 1
				var got := m.pick_at(p)
				if str(got.get("id", "")) == str(sc.id): hit += 1
				else: print("MISS %s %s at %s got %s" % [tag, str(sc.id), str(p), str(got)])
		T.check(seen > 0 and hit == seen, "%s [%s]: a pick at a section's projected place picks it (%d of %d)" % [tag, turn, hit, seen])
		for pid in m._prim:
			var c: Vector2 = m._prim[pid]
			if c.x < 0.0 or c.x > m.size.x or c.y < 0.0 or c.y > m.size.y: continue
			T.check(str(m.pick_at(c).get("id", "")) == str(pid), "%s [%s]: a pick at primary %s picks it" % [tag, turn, str(pid)])
	# the projection is the camera's: turning the camera moves the points
	dn.set_camera_spec("yaw=0,pitch=38"); m._layout(true); var p0 := m.point_of({"type": "section", "id": str(d.feeders[0].sections[0].id)})
	dn.set_camera_spec("yaw=40,pitch=38"); m._layout(true); var p1 := m.point_of({"type": "section", "id": str(d.feeders[0].sections[0].id)})
	T.check(p0.distance_to(p1) > 20.0, "%s: turning the camera moves the section on the map (%.0f px)" % [tag, p0.distance_to(p1)])
	# the sections' order down a feeder is preserved on screen at the opening view
	dn.reset_camera(); m._layout(true)
	var f0: Dictionary = d.feeders[0]; var ys: Array = []
	for sc in f0.sections: ys.append(m.point_of({"type": "section", "id": str(sc.id)}).y)
	var asc := true
	for i in range(1, ys.size()): if float(ys[i]) <= float(ys[i - 1]): asc = false
	T.check(asc, "%s: %s's sections run down the screen in order" % [tag, str(f0.id)])
	m.queue_free()
	dn.visible = true
	# a map without a district is the classic map
	var c := CareerMap.new(); root.add_child(c); c.size = Vector2(1340, 720); c.set_data(d)
	await process_frame
	T.check(not c._d3_mode(), "%s: no district, the classic map" % tag)
	c.queue_free()

## An incident opened by the engine itself: the feeder it names goes dark in the scene.
func _incident(T: Truth) -> void:
	T.b.act("careerStart", [7, "standard"])
	var d: Dictionary = T.b.q("career")
	var tries := 0
	while str(d.phase) != "incident" and tries < 12:
		T.b.act("careerEndQuarter", [true]); d = T.b.q("career"); tries += 1
		if str(d.phase) == "incident": break
		if d.get("ending") != null: break
	T.check(str(d.phase) == "incident", "the engine opens an incident within %d quarters (phase %s)" % [tries, str(d.phase)])
	if str(d.phase) != "incident": return
	var dn := District3D.new(); root.add_child(dn); dn.canvas_size = Vector2(1920, 1080)
	var hot: Array = []
	for inc in d.incidents: if inc.feederId != null: hot.append(str(inc.feederId))
	dn.set_district(d, "load", hot)
	var secs: Dictionary = dn.report().sections
	T.check(not hot.is_empty() or not (d.incidents as Array).is_empty(), "the incident names a feeder or a primary (%s)" % str(d.incidents.map(func(x): return [x.kind, x.feederId, x.primaryId])))
	for f in d.feeders:
		for sc in f.sections:
			var out := hot.has(str(f.id)) or (bool(sc.failed) and float(sc.outQ) > 0.0)
			T.check(bool(secs[str(sc.id)].dark) == out, "incident: %s %s" % [str(sc.id), "dark" if out else "lit"])
	print("INCIDENT hot=%s kinds=%s" % [str(hot), str(d.incidents.map(func(x): return x.kind))])
	dn.queue_free()

func _pure(T: Truth) -> void:
	var f := {"loadingPct": 60.0}; var g := {"loadingPct": 105.0}
	var sec := {"failed": false, "outQ": 0.0, "health": 6.0}
	var a := District3D.window_state(sec, f, false, "load"); var b := District3D.window_state(sec, g, false, "load")
	T.check(float(a.e) > float(b.e), "a heavier feeder's windows are never brighter (%.2f vs %.2f)" % [float(a.e), float(b.e)])
	var w1 := District3D.window_state({"failed": false, "outQ": 0.0, "health": 3.0}, f, false, "health"); var w2 := District3D.window_state({"failed": false, "outQ": 0.0, "health": 8.0}, f, false, "health")
	T.check(float(w2.e) > float(w1.e), "a healthier section's windows are brighter (%.2f vs %.2f)" % [float(w2.e), float(w1.e)])
	var out := District3D.window_state({"failed": true, "outQ": 2.0, "health": 6.0}, f, false, "load")
	T.check(bool(out.dark) and float(out.e) == 0.0, "a failed section out of service is dark")
	var patched := District3D.window_state({"failed": true, "outQ": 0.0, "health": 3.0}, f, false, "load")
	T.check(not bool(patched.dark), "a patched section is still in service: lit")
	T.check(bool(District3D.window_state(sec, f, true, "load").dark), "an open incident on the feeder darkens it")
	for pct in [0.0, 40.0, 70.0, 100.0, 125.0, 200.0]:
		var ws := District3D.window_state(sec, {"loadingPct": pct}, false, "load")
		T.check(float(ws.e) > 0.0 and float(ws.e) <= Bench3D.WINDOW_E, "loading %.0f %% keeps a lit window inside the emission range (%.2f)" % [pct, float(ws.e)])
