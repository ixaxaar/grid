extends SceneTree
## Retry truth (QA 1128c Q01; the owner: Retry means the same thing on every job). On the jobs whose design is settings (poles and turns,
## line ratio, series cap, phases, the motor bank, conductors and taps, recloser and fuses, transformer size, PV limit and volt-var), the
## design Retry records holds every move the player made, a restarted job replayed from it refuses nothing, holds the same moves, and
## the same run wins again. Moves are the engine solver's (the same ones the QA sweep used).

const MOVES := {
	"L04": [["setPoles", [12]], ["setTurns", [13]], ["setField", [0.8]], ["setArea", [0.1]], ["predict", ["L04.vpeak", 327, "V"]]],
	"L06": [["setLineRatio", [7]], ["setTransformerKva", [1000]], ["predict", ["L06.loss4kv", 600, "kW"]]],
	"L09": [["placeSeriesCap", ["T1", 70]]],
	"L10": [["assignPhase", ["H1", "c"]], ["assignPhase", ["H3", "b"]], ["assignPhase", ["H5", "c"]], ["assignPhase", ["H7", "c"]], ["assignPhase", ["H11", "b"]], ["assignPhase", ["H13", "c"]], ["assignPhase", ["H16", "b"]]],
	"L11": [["setBank", [100, 72, "Y", 250]], ["setStarter", ["yd"]]],
	"L31": [["setConductor", ["N1", "Dog"]], ["setConductor", ["N2", "Dog"]], ["setConductor", ["N3", "Rabbit"]], ["setDtTap", ["N1", 0]], ["setDtTap", ["N2", 2.5]], ["setDtTap", ["N3", 2.5]], ["setDtTap", ["N4", 5]], ["setDtTap", ["N5", 5]]],
	"L33": [["setRecloser", [200, 0.05, 3, 2]], ["setFuseLink", ["S1", 65]], ["setFuseLink", ["S2", 65]], ["setFuseLink", ["S3", 40]]],
	"L34": [["setTransformerSize", [24]], ["setTransfer", ["remote"]], ["setDemandResponse", ["large"]]],
	"L35": [["setPvLimit", [3000]], ["setOltc", [1.04, false]], ["setVoltVar", [true]]],
}

func _moves(T: Truth) -> Array:
	var out: Array = []
	for a in T.b.g.get("levelActions", []): if str(a[0]) != "tick": out.append([str(a[0]), JSON.parse_string(JSON.stringify(a[1]))])
	return out

func _run(T: Truth) -> String:
	for i in 400:
		var st = T.b.q("status")
		if not (st is Dictionary) or str(st.get("status", "")) != "playing": break
		T.b.act("tick", [])
	var st2 = T.b.q("status"); return str(st2.get("status", "")) if st2 is Dictionary else "?"

func _initialize() -> void:
	var T := Truth.new()
	if not T.start(root): print("RETRY-TRUTH FAILED engine"); quit(1); return
	var fake := CbApp.new(); fake.b = T.b
	for lid in MOVES:
		T.level(lid)
		for m in MOVES[lid]:
			var r := T.b.act(m[0], m[1]); T.check(bool(r.get("ok", false)), "%s %s accepted: %s" % [lid, m[0], str(r.get("message", ""))])
		var before := _moves(T)
		T.check(before.size() == (MOVES[lid] as Array).size(), "%s: the engine logged every move (%d of %d)" % [lid, before.size(), (MOVES[lid] as Array).size()])
		var design := ShiftReport.design_of(fake)
		var won1 := _run(T)
		T.check(won1 == "won", "%s: the solver's settings win (%s)" % [lid, won1])
		T.level(lid)
		var bad := ShiftReport.replay(fake, design)
		T.check(bad == 0, "%s: Retry refuses nothing (%d refused)" % [lid, bad])
		var after := _moves(T)
		T.check(JSON.stringify(after) == JSON.stringify(before), "%s: Retry holds every move (%s vs %s)" % [lid, JSON.stringify(after).left(160), JSON.stringify(before).left(160)])
		var won2 := _run(T)
		T.check(won2 == "won", "%s: the same design wins again after Retry (%s)" % [lid, won2])
	T.finish("RETRY-TRUTH", self)
