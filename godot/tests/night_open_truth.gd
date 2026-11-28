extends SceneTree
## Night openings (1128c, province family): before Run the engine has not solved the grid, so a town must not be drawn dark for it. On every
## province job that does not open in a blackout, every town is lit before the first block (presentation); once the engine has run, a town's
## light is the engine's voltage, and an unserved town is dark. Dark always means the engine says unserved.

const JOBS := ["L07", "L08", "L09", "L14", "L15", "L16", "L17", "L18", "L19", "L20", "L21", "L22", "L28"]

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("NIGHT-OPEN-TRUTH FAILED engine"); quit(1); return
	for lv in JOBS:
		T.level(lv)
		var m0 := WorldModel.build(T.b)
		T.check(not bool(m0.solved), "%s: the engine has not solved before Run" % lv)
		var n_t := 0
		for tw in m0.towns:
			n_t += 1
			if not bool(m0.blackout): T.check(float(tw.v) > 0.0, "%s before Run: town %s is drawn lit (v %.2f)" % [lv, str(tw.id), float(tw.v)])
		T.check(n_t > 0 or lv in ["L19", "L20", "L21", "L22"], "%s has towns to check (%d)" % [lv, n_t])
		T.b.act("tick", [1])
		var m1 := WorldModel.build(T.b)
		var vv: Dictionary = (T.b.q("overlay", ["voltage"]) as Dictionary).get("values", {})
		for tw in m1.towns:
			var want: float = float(vv[tw.id]) if vv.has(tw.id) else 0.0
			T.near(float(tw.v), want, 1e-6, "%s after the first block: town %s shows the engine's voltage" % [lv, str(tw.id)])
	T.finish("NIGHT-OPEN-TRUTH", self)
