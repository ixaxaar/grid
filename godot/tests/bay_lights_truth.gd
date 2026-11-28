extends SceneTree
## The bay's lights are the engine's voltages (DECISIONS 23): on L01 every home's lamp has brightness (V / V0)^2 from the bench's own vLoadV and
## sourceV, warm at the level's limit (43.2 V) or more and amber below; the porch bulb at the hut sits on the source, so (V0 / V0)^2 = 1, white.
## The bench lumps the ten homes on one node: all ten lamps carry the same number, no gradient along the row. Read back from the Light3D nodes the
## scene builds, and from the raw `world` query, not from WorldModel. Also: the Classic chip belongs to the levels the 3D look does not draw.

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("BAY-LIGHTS-TRUTH FAILED engine"); quit(1); return
	for design in [["naive", 300, 2.5], ["lesson", 300, 35.0], ["short thick", 120, 25.0]]:
		T.level("L01")
		T.check(bool(T.b.act("placeHut", [design[1]]).get("ok", false)) and bool(T.b.act("layCable", ["main", design[2]]).get("ok", false)), "%s accepted" % design[0])
		_check(T, str(design[0]))
	# nothing laid: the hamlet is dark and the porch has no hut to hang on
	T.level("L01")
	var bay := _scene(T)
	T.check(bay.lamp_report().homes.size() == 10, "ten homes stand before anything is placed")
	for h in bay.lamp_report().homes: T.check(float(h.b) == 0.0 and not bool(h.lamp_on), "dark hamlet: brightness 0 and the street lamp dark")
	T.check(not bay.lamp_report().has("porch"), "no hut, no porch bulb")
	bay.free()
	# the Classic chip: only the levels the bay draws lose it
	for id in Bay3D.LEVELS: T.check(WorldView.LOOK2_LEVELS.has(id), "%s is in LOOK2_LEVELS (no Classic chip)" % id)
	for id in ["L04", "L06"]: T.check(not WorldView.LOOK2_LEVELS.has(id), "%s is not a province level" % id)   # 1.18: L05 and L29 are drawn in 3D (DECISIONS 25)
	T.check(WorldView.LOOK2_LEVELS.has("P0"), "P0, the prologue, is drawn by the 3D province (1.19, DECISIONS 27)")
	for id in ["L04", "L06"]: T.check(Bench3D.LEVELS.has(id) and not Jobs.is_classic(id), "%s is drawn by the 3D bench: no Classic chip (1.19)" % id)   # was: L04 and L06 keep the Classic chip
	for id in WorldView.LOOK2_LEVELS: T.check(not Jobs.is_classic(id), "%s has no Classic chip" % id)
	# Every job from P0 to L36 has a 3D place now (chapters 4, 7 and 8 through Stage3D), so no real level id is left to stand for "a job no 3D layer draws". The rule is the
	# predicate's: an id that no 3D layer lists keeps the Classic chip. L99 is such an id (it is in no list; checked here so the example cannot become a real job unnoticed).
	T.check(not WorldView.LOOK2_LEVELS.has("L99") and not Bench3D.LEVELS.has("L99") and not Stage3D.STAGES.has("L99"), "L99 is listed by no 3D layer")
	T.check(Jobs.is_classic("L99"), "a job no 3D layer draws (L99) keeps the Classic chip")   # was L10, then L23, then L31, until every chapter got its 3D place
	for id in ["L05", "L29", "L30"]: T.check(WorldView.LOOK2_LEVELS.has(id), "%s, a chapter 2 map level, is in the 3D look" % id)
	T.check(Bay3D.LEVELS.has("L01"), "L01 is drawn in 3D")
	T.finish("BAY-LIGHTS-TRUTH", self)

func _scene(T: Truth) -> Bay3D:
	var m := WorldModel.build(T.b)
	var view := WorldView.new(); view.size = Vector2(1200, 700); view.set_model(m)
	var bay := Bay3D.new(); root.add_child(bay)
	bay.set_model(m, view._tiles, view._zgrid, view._objs)
	view.free()
	return bay

func _check(T: Truth, tag: String) -> void:
	var raw: Dictionary = (T.b.q("world") as Dictionary).bench
	var v0 := float(raw.sourceV); var vs: Array = raw.vLoadV
	var want := (float(vs[0]) / v0) * (float(vs[0]) / v0)
	var lim := float(raw.vMinLimitV)
	var bay := _scene(T)
	var rep := bay.lamp_report()
	T.check(rep.homes.size() == 10, "%s: ten homes" % tag)
	for h in rep.homes:
		T.near(float(h.b), want, 1e-4, "%s: home brightness is (V/V0)^2" % tag)
		T.near(float(h.light) / Bay3D.HOME_LIGHT_E, want, 1e-4, "%s: the Light3D energy follows" % tag)
		T.check(bool(h.lamp_on) == (want > 0.003), "%s: the street lamp by a home is on exactly when the home is lit" % tag)
		T.check(bool(h.warm) == (float(vs[0]) >= lim), "%s: warm iff V >= %.1f (V = %.2f)" % [tag, lim, float(vs[0])])
	T.check(rep.has("porch"), "%s: the hut has a porch bulb" % tag)
	T.near(float(rep.porch.b), (v0 / v0) * (v0 / v0), 1e-4, "%s: porch (V0/V0)^2 = 1" % tag)
	T.check(not bool(rep.porch.amber), "%s: the porch is white" % tag)
	print("%s: V=%.2f of %.0f -> b=%.3f warm=%s" % [tag, float(vs[0]), v0, want, str(rep.homes[0].warm)])
	bay.free()
