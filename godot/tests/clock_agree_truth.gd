extends SceneTree
## One clock (1128c C18): on every province job (L14-L18) the scene's minute, the dial's minute and the radio's stamp are the same number. Before Run a
## job with a preview hour (WorldModel.PREVIEW_MINUTE) shows that hour on all three; from the first block on, all three follow the engine's clock. No job
## shows the engine's hour over a different sky, and no job shows a preview hour once its first block has run.

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("CLOCK-AGREE-TRUTH FAILED engine"); quit(1); return
	for lv in ["L14", "L15", "L16", "L17", "L18"]:
		T.level(lv)
		for step in 4:
			var c: Dictionary = T.b.q("clock")
			var m := WorldModel.build(T.b)
			var pm := WorldModel.preview_minute(lv, int(c.tick), T.b.g.get("levelStart"))   # what the dial and the radio read (instruments.gd, radio_log.gd)
			var dial := pm if pm >= 0.0 else float(c.minuteOfDay)
			T.near(float(m.minute), dial, 1e-6, "%s tick %d: the scene's minute equals the dial's (%s vs %s)" % [lv, int(c.tick), str(m.minute), str(dial)])
			T.check(bool(m.get("preview", false)) == (pm >= 0.0), "%s tick %d: the model says preview exactly when the dial does" % [lv, int(c.tick)])
			if step > 0: T.check(pm < 0.0 and not bool(m.get("preview", false)), "%s: after the first block the preview is over" % lv)
			T.b.act("tick", [1])
	# the preview is only L16's, and only before the first block
	T.check(WorldModel.PREVIEW_MINUTE.keys() == ["L16"], "only WO-16 previews a peak hour")
	T.finish("CLOCK-AGREE-TRUTH", self)
