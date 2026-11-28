extends SceneTree
## Province shed truth (1128c P01, round 3): (1) no healthy roof tint is a neutral grey (a saturation floor on every tint, the near ones taken
## on the tile texture's mean colour), so the cool shadow of a shed sector is a cue no healthy house can show; (2) on WO-17 after the 15:00 trip
## the engine has shed part of the city: every house of a shed sector carries the shed flag (INSTANCE_CUSTOM.b = 1), every house of a served
## sector does not, and the shadow fan marks exactly the shed wedges; (3) WO-16 previews the evening peak in the scene only: the model's minute
## changes before Run, the engine's clock and its numbers do not.

func _sat(c: Vector3) -> float:
	var mx := maxf(c.x, maxf(c.y, c.z)); var mn := minf(c.x, minf(c.y, c.z))
	return 0.0 if mx <= 0.0 else (mx - mn) / mx

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("PROVINCE-SHED-TRUTH FAILED engine"); quit(1); return
	# 1. roof tints
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://world3d/tex/roof_albedo.jpg"))
	T.check(img != null, "the roof tile texture loads")
	var mean := Vector3(0.46, 0.27, 0.18)
	if img != null:
		img.resize(1, 1, Image.INTERPOLATE_LANCZOS); var mc := img.get_pixel(0, 0); mean = Vector3(mc.r, mc.g, mc.b)
	var tint_i := 0
	for t in Assets3D.ROOF_TINTS_NEAR:
		var eff := Vector3(mean.x * t.x, mean.y * t.y, mean.z * t.z)
		T.check(_sat(eff) >= Assets3D.ROOF_SAT_MIN, "near roof tint %d (on the tile texture) is not grey: saturation %.2f >= %.2f" % [tint_i, _sat(eff), Assets3D.ROOF_SAT_MIN]); tint_i += 1
	tint_i = 0
	for t in Assets3D.ROOF_TINTS_FAR:
		T.check(_sat(t) >= Assets3D.ROOF_SAT_MIN, "far roof tint %d is not grey: saturation %.2f >= %.2f" % [tint_i, _sat(t), Assets3D.ROOF_SAT_MIN]); tint_i += 1
	for f in ["res://world3d/shaders/house.gdshader", "res://world3d/shaders/house_kit.gdshader"]:   # the old grey literals must not come back
		var src := FileAccess.get_file_as_string(f)
		T.check(not src.contains("vec3(0.38, 0.39, 0.43)") and not src.contains("vec3(0.55, 0.57, 0.62)"), "%s carries no grey roof literal" % f)
		T.check(src.contains("roof_far[") or src.contains("roof_tint["), "%s takes its roof tints from Assets3D" % f)
	# 2. WO-17 after the trip: the shed sectors
	T.level("L17")
	var e0 := WorldModel.build(T.b)
	for i in 80: if str(T.b.g.status) == "playing": T.b.act("tick", [1])
	var m := WorldModel.build(T.b)
	var shed_n := 0; var live_n := 0; var city := {}
	for t in m.towns:
		if str(t.id) == "B3": city = t
	T.check(not city.is_empty() and float(city.v) > 0.0, "L17: the city bus is live after the trip")
	for e in city.energies: if float(e) <= 0.0: shed_n += 1
	for e in city.energies: if float(e) > 0.0: live_n += 1
	T.check(shed_n > 0 and live_n > 0, "L17 after the trip: part of the city is shed (%d sectors) and part served (%d)" % [shed_n, live_n])
	var p := Province3D.new(); root.add_child(p)
	await process_frame   # _ready (the environment) runs on the next frame
	p.set_model(m)
	T.check(p._town_geo.has("B3") and int(p._town_geo.B3.cnt) == city.energies.size(), "the city has its centre, main-street angle and %d energy sectors" % city.energies.size())
	T.check(p._subst.has("B3"), "the city bus has a substation yard where the transmission line ends")
	p._t = 100.0; p._run_waves()
	var want_shed := 0; var seen := 0
	var en: PackedFloat32Array = city.energies
	for it in p._town_inst.get("B3", []):
		seen += 1
		if float(en[int(it[2]) % en.size()]) <= 0.0: want_shed += 1
	var w: Dictionary = p._wave["B3"]
	T.check(seen > 100 and want_shed > 0 and want_shed < seen, "the city has served and shed houses to check (%d of %d shed)" % [want_shed, seen])
	T.check(int(w.get("written", 0)) == seen, "the wave wrote every house of the city (%d of %d)" % [int(w.get("written", 0)), seen])
	T.check(int(w.get("shed_n", 0)) == want_shed, "exactly the houses of the shed sectors carry the shed flag (%d marked, %d in zero-energy sectors)" % [int(w.get("shed_n", 0)), want_shed])
	# the failed WO-17 report holds the night when part of a live city is shed (r4), as every other failed report holds it after a night run
	T.check(ShiftReport.held_minute(720.0, true, true, false, true) == 1350.0, "a failed report with a shed city holds the night over a noon run")
	T.check(ShiftReport.held_minute(720.0, true, true, false, false) == 720.0, "a failed report without a night run or a shed keeps its hour")
	T.check(ShiftReport.held_minute(720.0, true, false, false, true) == 720.0, "a passed report never holds the night")
	T.check(ShiftReport.held_minute(720.0, false, true, true, true) == 720.0, "no report open: no hold")
	T.check(ShiftReport.held_minute(1400.0, true, true, false, true) == 1400.0, "the night itself is left alone")
	T.check(p.report_focus(), "the report frames the shed city")
	p.queue_free()
	# 3. WO-16: the evening-peak preview changes the scene's minute only
	T.level("L16")
	var c16: Dictionary = T.b.q("clock")
	var m16 := WorldModel.build(T.b)
	T.check(bool(m16.get("preview", false)) and absf(float(m16.minute) - 1110.0) < 0.1, "L16 before Run: the scene stands at the evening peak (%.0f)" % float(m16.minute))
	T.check(int(c16.minuteOfDay) == (int(T.b.g.get("levelStart", 0)) * 15) % 1440 and float(m16.minute) != float(c16.minuteOfDay), "the engine's clock stays at the level's start (%d), only the scene's minute differs" % int(c16.minuteOfDay))
	for tw in m16.towns: T.check(float(tw.v) > 0.0, "L16 before Run: the towns are drawn lit (%s)" % str(tw.id))
	T.b.act("tick", [1])
	var m16b := WorldModel.build(T.b)
	T.check(not bool(m16b.get("preview", false)) and absf(float(m16b.minute) - float(T.b.q("clock").minuteOfDay)) < 0.1, "L16 after the first block: the scene follows the engine's clock")
	T.check(WorldModel.preview_minute("L17", 0, 0) < 0.0 and WorldModel.preview_minute("L16", 5, 4) < 0.0 and WorldModel.preview_minute("L16", 4, 4) > 0.0, "preview_minute: only L16, only while fresh")
	T.finish("PROVINCE-SHED-TRUTH", self)
