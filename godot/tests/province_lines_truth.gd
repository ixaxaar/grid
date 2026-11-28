extends SceneTree
## Province lines (1128c family rollout): a line ends AT the plant it feeds, on every job, whatever the plant's drawn scale. The pad's near edge
## is the line's end point, and a tower of that line stands on it; the old fixed 260 m offset left a 280 m gap at the 1.5x plants of WO-16..22.

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("PROVINCE-LINES-TRUTH FAILED engine"); quit(1); return
	for lv in ["L16", "L19", "L20", "L21", "L22", "L28"]:
		T.level(lv)
		var m := WorldModel.build(T.b)
		var p := Province3D.new(); root.add_child(p)
		await process_frame
		p.set_model(m)
		var plants := 0; var fed := 0
		for u in m.units:
			if not (str(u.kind) in ["coal", "gas", "biomass", "nuclear", "diesel"]): continue
			plants += 1
			var po: Dictionary = p._plant_pose(u)
			var e: Vector2 = p._plant_edge(u.pos)
			var o: Vector3 = po.origin; var aw: Vector2 = po.away
			var lx := (e - Vector2(o.x, o.z)).dot(aw) / float(po.scale)
			T.check(absf(lx + Province3D.PLANT_EDGE) <= 2.0 / float(po.scale) + 0.01, "%s %s: the line end is the pad's near edge (local x %.1f)" % [lv, str(u.id), lx])
			var ends := 0; var best := 1e9
			for l in m.lines:
				var pts: Array = l.pts
				if pts.size() < 2 or float(l.kv) < 66.0 or str(l.kind) in ["xfmr", "cable"]: continue
				if not ((pts[0] as Vector2).distance_to(u.pos) < 0.6 or (pts[pts.size() - 1] as Vector2).distance_to(u.pos) < 0.6): continue
				ends += 1
				var tb: PackedVector3Array = p._towers.get(str(l.id), PackedVector3Array())
				var d := 1e9
				for v in tb: d = minf(d, Vector2(v.x, v.z).distance_to(e))
				best = minf(best, d)
				T.check(d <= 1.0, "%s %s: line %s has a tower on the pad edge (%.1f m)" % [lv, str(u.id), str(l.id), d])
			fed += ends
		T.check(plants > 0 and (fed > 0 or lv in ["L19", "L20", "L21", "L22"]), "%s: %d plants, %d transmission lines end at one" % [lv, plants, fed])
		p.queue_free()
		await process_frame
	T.finish("PROVINCE-LINES-TRUTH", self)
