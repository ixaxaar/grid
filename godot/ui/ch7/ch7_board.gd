class_name Ch7Board
extends Ch7Base
## L23 Fault Level: the 33 kV industrial board as a single-line diagram (grid, two transformers, two sections, the coupler or its reactor, the captive generators,
## feeder F1 with its breaker). The player predicts the fault current, then picks breaker rating, coupler, reactor and transformer impedance. After the run the
## fault current, the duty of every breaker and the breaker-failure sequence appear; a breaker rated under its duty goes red. Cute mode: the estate's windows go dark.
func _init() -> void:
	super._init(); scenario = "L23"; name = "Ch7Board"
	_edit("faultKA")

func _submit(key: String) -> void: _predict_submit(key, "faultKA", "kA")

func _after_refresh() -> void: _sync_predict("faultKA", "faultKA")

func _layout_panel() -> void:
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0)); var x := inner.position.x; var y := inner.position.y + 22.0
	var rs := []; var ra := []
	for r in kit.get("ratings", []): rs.append(WorkOrder.num(float(r.kA))); ra.append(float(r.kA))
	_chip_row(x, y, 52.0, 40.0, 5.0, rs, "rating", ra, q.get("ratingKA", 25.0))
	x += 57.0 * rs.size() + 12.0
	_chip_row(x, y, 62.0, 40.0, 5.0, [T("C7_CLOSED"), T("C7_OPEN")], "coupler", ["closed", "open"], str(q.design.coupler))
	x += 134.0 + 12.0
	_chip_row(x, y, 46.0, 40.0, 5.0, ["0", "0.1", "0.2"], "reactor", [0.0, 0.1, 0.2], q.design.reactor)
	x += 148.0 + 12.0
	_chip_row(x, y, 46.0, 40.0, 5.0, ["10", "14"], "uk", [10.0, 14.0], q.design.uk)
	var e: LineEdit = edits["faultKA"]; e.position = Vector2(inner.position.x + 300.0, inner.position.y + 84.0); e.size = Vector2(84, 30)

func _press(h: Dictionary, _p: Vector2) -> void:
	if str(h.id) == "fold": folded = not folded; layout(); queue_redraw(); return
	match str(h.id):
		"rating": _act("setBreakerRating", [float(h.arg)])
		"coupler": _act("setBusCoupler", [str(h.arg) == "open"])
		"reactor": _act("setSeriesReactor", [float(h.arg)])
		"uk": _act("setTransformerZ", [float(h.arg)])

func _draw_panel_body() -> void:
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0))
	var caps := [T("C7_BREAKERS"), T("C7_COUPLER_CAP"), T("C7_REACTOR_CAP"), T("C7_XFMR_CAP")]
	var cap := "%s  |  %s  |  %s  |  %s" % caps
	var fz := GridText.floor_size(self, GridTheme.fs(10)) if _look3() else GridTheme.fs(10)
	if _semi().get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fz).x > inner.size.x: cap = "%s | %s | %s | %s" % caps   # QA 1128c Q03: at 1280 px the joined caption ran under the card edge
	if _semi().get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, fz).x > inner.size.x: cap = cap.replace(" (kA, each)", " (kA)").replace("BUS-SECTION ", "")
	_text(_semi(), 10, inner.position + Vector2(0, 14), cap, Color(GridTheme.TEXT, 0.65))
	_text(_semi(), 11, inner.position + Vector2(0, 104), T("C7_PREDICT_KA"), GridTheme.SODIUM)
	_text(_mono(), 12, inner.position + Vector2(392, 104), T("C7_UNIT_kA"), Color(GridTheme.TEXT, 0.8))
	if _revealed():
		var ok := bool(q.get("ok", false))
		_text(_mono(), 14, inner.position + Vector2(432, 104), T("C7_FAULT_KA") % [WorkOrder.num(float(q.faultKA)), str(q.faultMVA)], _good(ok))

func _draw_stage() -> void:
	if _look3(): _draw_stage3(); return
	var w := size.x; var top := _stage_top(); var bh := _stage_h(220.0)
	var r := Rect2(Vector2(30.0, top), Vector2(minf(w * 0.58, 760.0), bh)); draw_style_box(_box_sb(0.82), r)
	var cx := r.position.x + r.size.x * 0.5; var gy := r.position.y + 28.0; var by := r.position.y + bh * 0.56
	var ax := cx - r.size.x * 0.22; var bx := cx + r.size.x * 0.22
	var dark := _revealed() and not bool(q.get("ok", true)); var wire := GridTheme.LIVE if not dark else Color(GridTheme.DIM, 0.6)
	# grid and transformers
	var gv: Dictionary = q.givens
	_text(_semi(), 11, Vector2(cx - 130, gy - 8.0), T("C7_GRID") + "  " + (T("C7_Z") % WorkOrder.num(float(gv.gridZ))), Color(GridTheme.TEXT, 0.8), 260.0, 1)
	draw_line(Vector2(ax - 20, gy), Vector2(bx + 20, gy), wire, 3.0)
	for sx in [ax, bx]:
		_text(_mono(), 10, Vector2(sx + 18.0, gy + 50.0), T("C7_Z") % WorkOrder.num(float(gv.xfmrZ)), Color(GridTheme.TEXT, 0.75))
		draw_line(Vector2(sx, gy), Vector2(sx, gy + 30), wire, 2.0); draw_arc(Vector2(sx, gy + 42), 12.0, 0, TAU, 20, wire, 2.0); draw_arc(Vector2(sx, gy + 54), 12.0, 0, TAU, 20, wire, 2.0)
		draw_line(Vector2(sx, gy + 66), Vector2(sx, by), wire, 2.0)
	# busbars and coupler
	var open: bool = str(q.design.coupler) == "open"
	draw_line(Vector2(ax - 70, by), Vector2(cx - 24, by), wire, 5.0); draw_line(Vector2(cx + 24, by), Vector2(bx + 70, by), wire, 5.0)
	if open: draw_line(Vector2(cx - 24, by), Vector2(cx - 8, by - 12), GridTheme.WARN, 3.0)
	else:
		draw_line(Vector2(cx - 24, by), Vector2(cx + 24, by), wire, 5.0)
		if float(q.design.reactor) > 0.0:
			for i in 4: draw_arc(Vector2(cx - 18 + i * 12, by - 7), 6.0, PI, TAU, 8, GridTheme.COPPER, 3.0)
	_text(_semi(), 10, Vector2(cx - 50, by + 22), T("C7_COUPLER") + " " + (T("C7_OPEN") if open else T("C7_CLOSED")), Color(GridTheme.TEXT, 0.7), 100.0, 1)
	_text(_semi(), 10, Vector2(ax - 70, by + 26), T("C7_SEC_A"), Color(GridTheme.TEXT, 0.7)); _text(_semi(), 10, Vector2(bx + 20, by + 26), T("C7_SEC_B"), Color(GridTheme.TEXT, 0.7))
	# generators and the feeder breaker
	for gx in [ax - 40.0, bx + 40.0]:
		draw_line(Vector2(gx, by), Vector2(gx, by + 46), wire, 2.0); draw_circle(Vector2(gx, by + 62), 16.0, Color(GridTheme.INK)); draw_arc(Vector2(gx, by + 62), 16.0, 0, TAU, 24, wire, 2.0); _text(_semi(), 13, Vector2(gx - 8, by + 67), "G", GridTheme.TEXT, 16.0, 1); _text(_mono(), 10, Vector2(gx - 38.0, by + 92.0), T("C7_Z") % WorkOrder.num(float(gv.genZ)), Color(GridTheme.TEXT, 0.75), 76.0, 1)
	var fx := ax + 40.0; draw_line(Vector2(fx, by), Vector2(fx, by + 40), wire, 2.0)
	var br := Rect2(Vector2(fx - 11, by + 40), Vector2(22, 22)); var over := _revealed() and not bool(q.get("ok", true))
	draw_rect(br, Color(GridTheme.BAD, 0.85) if over else Color(GridTheme.GOOD, 0.75) if _revealed() else Color(GridTheme.SODIUM, 0.6))
	draw_line(Vector2(fx, by + 62), Vector2(fx, by + 90), wire, 2.0)
	_text(_semi(), 10, Vector2(fx + 34, by + 78), T("C7_FEEDER") + "  " + T("C7_RATED") % WorkOrder.num(float(q.ratingKA)), Color(GridTheme.TEXT, 0.85))
	if _revealed():
		# the bolt: the scripted fault just outside the breaker
		var bp := Vector2(fx, by + 96); var pulse := 0.6 + 0.4 * sin(_t * 9.0)
		draw_colored_polygon(PackedVector2Array([bp + Vector2(-6, -8), bp + Vector2(4, -8), bp + Vector2(-2, 2), bp + Vector2(8, 2), bp + Vector2(-8, 18), bp + Vector2(-2, 5), bp + Vector2(-8, 5)]), Color(GridTheme.WARN, pulse))
		if dark: _text(_semi(), 22, Vector2(r.position.x, r.position.y + 24), T("C7_ESTATE_DARK"), GridTheme.BAD, r.size.x, 1)
	var gy2 := r.end.y - 52.0
	if not _phone():
		for g in ["C7_GLOSS_IF", "C7_GLOSS_PU", "C7_GLOSS_REACTOR"]:
			_text(_mono(), 10, Vector2(r.position.x + 14.0, gy2), T(g), Color(GridTheme.TEXT, 0.6)); gy2 += 15.0
	# right: the table of who breaks what, and N-1
	var tr := Rect2(Vector2(r.end.x + 16.0, top), Vector2(maxf(w - r.end.x - 46.0, 260.0), bh))
	_draw_table(tr)

func _draw_table(tr: Rect2) -> void:
	draw_style_box(_box_sb(0.82), tr)
	_text(_semi(), 11, tr.position + Vector2(12, 18), T("C7_TABLE") if _revealed() else T("C7_GIV_CAP"), Color(GridTheme.TEXT, 0.7))
	if _revealed():
		_text(_mono(), 11, tr.position + Vector2(12, 38), T("C7_ZTH") % WorkOrder.num(float(q.zthPu)), Color(GridTheme.TEXT, 0.8))
		var y := tr.position.y + 60.0
		for d in q.duty:
			_text(_mono(), 12, Vector2(tr.position.x + 12, y), "%s  %s kA" % [str(d.id), WorkOrder.num(float(d.kA))], GridTheme.BAD if bool(d.over) else GridTheme.TEXT)
			y += 18.0
	else:
		var g: Dictionary = q.givens
		var lines := [T("C7_GIV_BASE") % [int(g.baseMVA), int(g.kv), WorkOrder.num(g.kaPerPu)], T("C7_GIV_GRID") % [int(g.gridMVA), WorkOrder.num(g.gridZ)], T("C7_GIV_T") % [int(g.xfmrMVA), WorkOrder.num(g.uk), WorkOrder.num(g.xfmrZ)],
			T("C7_GIV_G") % [WorkOrder.num(g.genMVA), WorkOrder.num(g.xdd), WorkOrder.num(g.genZ)], T("C7_GIV_COUPLER") % [T("C7_OPEN") if str(g.coupler) == "open" else T("C7_CLOSED"), (T("C7_GIV_R") % WorkOrder.num(g.reactor)) if float(g.reactor) > 0.0 and str(g.coupler) != "open" else ""]]
		var cl := []
		for ln in lines: cl.append([ln, Color(GridTheme.TEXT, 0.85)])
		cl.append([T("C7_GIV_CHAIN"), GridTheme.SODIUM])
		if _phone():
			var n1p: Dictionary = q.n1; var secp := bool(n1p.secure) and float(n1p.vPu) >= 0.94
			cl.append([(T("C7_N1_OK") % WorkOrder.num(float(n1p.vPu))) if secp else T("C7_N1_BAD"), _good(secp)])
		_card_text(tr, cl, 11, 8.0, 36.0)
	var n1: Dictionary = q.n1; var sec := bool(n1.secure) and float(n1.vPu) >= 0.94
	if not (_phone() and not _revealed()):
		var n1t := (T("C7_N1_OK") % WorkOrder.num(float(n1.vPu))) if sec else T("C7_N1_BAD")
		if _look3(): _wrap(_semi(), 11, Vector2(tr.position.x + 12, tr.end.y - 40), n1t, _good(sec), tr.size.x - 24.0)   # 3D: wrapped inside the card (it ran past its right edge)
		else: _text(_semi(), 11, Vector2(tr.position.x + 12, tr.end.y - 14), n1t, _good(sec))

## The 3D substation: the place is Stage3D's; the givens / duty table stays in glass on the right and each part of the board gets a chip.
func _draw_stage3() -> void:
	var w := _right(); var top := TOP; var bh := minf(_stage_bottom() - top - 12.0, 380.0)
	var tw := minf(400.0, w * 0.3)
	_draw_table(Rect2(Vector2(w - tw - M, top), Vector2(tw, bh)))
	var g: Dictionary = q.givens; var dim := GridTheme.G_DIM; var txt := GridTheme.G_TEXT
	_pin("incomer", [T("C7_GRID"), T("C7_Z") % WorkOrder.num(float(g.gridZ))], [txt, dim], 20.0)
	_pin("xfmr", [T("C7_T1") % WorkOrder.num(float(g.xfmrZ))], [txt], 20.0)
	_pin("board", [T("C7_SEC_A")], [txt], 16.0)
	var open: bool = str(q.design.coupler) == "open"
	var cl: Array = [T("C7_COUPLER") + " " + (T("C7_OPEN") if open else T("C7_CLOSED"))]; var cc: Array = [GridTheme.WARN if open else txt]
	if float(q.design.reactor) > 0.0 and not open: cl.append(T("C7_GIV_R").trim_prefix(", ") % WorkOrder.num(float(q.design.reactor))); cc.append(GridTheme.COPPER)
	_pin("coupler", cl, cc, 26.0)
	_pin("gens", [T("C7_Z") % WorkOrder.num(float(g.genZ)) + "  G"], [txt], 20.0)
	var fl: Array = [T("C7_FEEDER"), T("C7_RATED") % WorkOrder.num(float(q.ratingKA))]; var fc: Array = [txt, dim]
	if _revealed():
		for d in q.duty: if str(d.id) == "F1": fl.append(T("C7_DUTY") % WorkOrder.num(float(d.kA))); fc.append(GridTheme.BAD if bool(d.over) else GridTheme.GOOD)
	_pin("feeder", fl, fc, 24.0)
	if _revealed() and not bool(q.get("ok", true)): _pin("estate", [T("C7_ESTATE_DARK")], [GridTheme.BAD], 20.0)
