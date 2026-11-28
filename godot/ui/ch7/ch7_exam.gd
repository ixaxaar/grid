class_name Ch7Exam
extends Ch7Base
## L27 Exam Bridge: Faults & lambda. Left: the five exam questions (a box each; after the run the engine's answer and a tick or a cross). Right: the grown board's breaker
## rating and tonight's 3-unit dispatch (a box per unit; set them with Enter). Display and input only: the engine marks the exam.
const IDS := ["ps17", "ps18", "ps20", "ps21", "ps24"]
const UNITS := {"ps17": "kA", "ps18": "kA", "ps20": "$/MWh", "ps21": "$/MWh", "ps22": "$/MWh", "ps24": "s"}
var qids: Array = IDS
var show_card := false

func _init() -> void:
	super._init(); scenario = "L27"; name = "Ch7Exam"
	for k in IDS: _edit(k)
	for k in 3: _edit("disp%d" % k)

func _submit(key: String) -> void:
	if key.begins_with("disp"):
		var v := []
		for k in 3:
			var t: String = (edits["disp%d" % k] as LineEdit).text.strip_edges().replace(",", ".")
			if not t.is_valid_float(): return
			v.append(float(t))
		var cur: Array = q.design.dispatch
		if is_equal_approx(float(cur[0]), v[0]) and is_equal_approx(float(cur[1]), v[1]) and is_equal_approx(float(cur[2]), v[2]): return
		if not _locked(): _act("setDispatch3", v)
	else: _predict_submit(key, key, str(UNITS[key]))

func _after_refresh() -> void:
	for k in IDS: _sync_predict(k, k)
	for k in 3:
		var e: LineEdit = edits["disp%d" % k]; e.visible = true; e.editable = not _locked()
		if not e.has_focus(): e.text = WorkOrder.num(float(q.design.dispatch[k]))

func _row() -> float: return 30.0 if _phone() else 40.0

func _layout_panel() -> void:
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0)); var rs := []; var ra := []
	for r in kit.get("ratings", []): rs.append(WorkOrder.num(float(r.kA))); ra.append(float(r.kA))
	_chip_row(inner.position.x, inner.position.y + 20.0, 56.0, 40.0, 5.0, rs, "rating", ra, q.design.rating)
	var cr := _card_chip()
	if not _phone(): _add_chip(cr, "card", "")
	if not _phone(): rows.append({"r": cr, "label": T("C7_HIDE") if show_card else T("C7_SHOW"), "on": show_card, "id": "card", "arg": ""})
	for k in 3:
		var e: LineEdit = edits["disp%d" % k]; e.position = Vector2(inner.position.x + 340.0 + 90.0 * k, inner.position.y + 26.0); e.size = Vector2(80, 30)

## "show formulas": at the foot of the exam sheet in 3D, under the questions card on the classic stage.
func _card_chip() -> Rect2:
	if _look3() and not _phone():
		var r := _sheet_rect()
		return Rect2(Vector2(r.position.x + 12.0, r.end.y - 40.0), Vector2(170, 30))
	return Rect2(Vector2(32.0, 420.0), Vector2(150, 30))

func _exam_sheet() -> bool: return true
func _stage_rects() -> Array: return [_sheet_rect()] if _look3() and not _phone() else []

func _press(h: Dictionary, _p: Vector2) -> void:
	if str(h.id) == "fold": folded = not folded; layout(); queue_redraw(); return
	if str(h.id) == "card": show_card = not show_card; layout(); queue_redraw(); return
	if str(h.id) == "rating": _act("setBreakerRating", [float(h.arg)])

func _draw_panel_body() -> void:
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0))
	for k in 3:
		var de: LineEdit = edits["disp%d" % k]; _text(_mono(), 10, de.position + Vector2(8.0, 19.0), T("C7_UNIT_MW"), Color(GridTheme.TEXT, 0.5))
	_text(_semi(), 10, inner.position + Vector2(0, 12), T("C7_BREAKERS"), Color(GridTheme.TEXT, 0.65)); _text(_semi(), 10, inner.position + Vector2(340, 12), T("C7_DISPATCH_CAP"), Color(GridTheme.TEXT, 0.65))
	var s := 0.0   # the boxes as typed (1.6: the sum stayed stale until a box lost focus)
	for k in 3:
		var tx: String = (edits["disp%d" % k] as LineEdit).text.strip_edges().replace(",", ".")
		s += float(tx) if tx.is_valid_float() else float(q.design.dispatch[k])
	_text(_mono(), 12, inner.position + Vector2(340, 84), T("C7_DISPATCH_SUM") % [WorkOrder.num(s), int(q.demandMW)], Color(GridTheme.TEXT, 0.8))
	if _revealed():
		_text(_mono(), 12, inner.position + Vector2(0, 84), T("C7_BOARD_KA") % [WorkOrder.num(float(q.boardKA.threePh)), WorkOrder.num(float(q.boardKA.slg))], _good(bool(q.ratingOk)))

func _draw_stage() -> void:
	var l3 := _look3()
	if l3 and not _phone(): _draw_sheet3(); return
	var w := _right() if l3 else size.x; var top := _stage_top(); var bh := _stage_h(240.0)
	var r := Rect2(Vector2(30.0, top), Vector2((minf(w - 60.0, 800.0) if not l3 else minf(w - 60.0, 740.0)) if not _phone() else minf(w * 0.52, 620.0), 250.0 if not _phone() else 5.0 * _row() + 44.0)); draw_style_box(_box_sb(0.82), r)
	_text(_semi(), 12, r.position + Vector2(14, 22), T("C7_EXAM"), Color(GridTheme.TEXT, 0.75))
	var y := r.position.y + (46.0 if not _phone() else 30.0); var i := 0
	for qq in q.questions:
		var id := str(qq.id)
		_text(_mono(), 12, Vector2(r.position.x + 14, y + 20), T("C7_Q_" + id), GridTheme.TEXT)
		if edits.has(id):
			var e: LineEdit = edits[id]; e.position = Vector2(r.position.x + 330, y + 2 if not _phone() else y - 1); e.size = Vector2(90, 30 if not _phone() else 26)
		if _revealed() and qq.get("actual") != null:
			var ok := bool(qq.get("within", false)); _text(_mono(), 13, Vector2(r.position.x + (480 if not _phone() else 466), y + 24 if not _phone() else y + 19), (T("C7_ANSWER") % WorkOrder.num(float(qq.actual))) + ("  ✓" if ok else "  ✗"), _good(ok))
		_text(_mono(), 12, Vector2(r.position.x + 428, y + 20), str(UNITS[id]) if false else T("C7_UNIT_" + ("kA" if id in ["ps17", "ps18"] else "s" if id == "ps24" else "usd")), Color(GridTheme.TEXT, 0.7))
		var hint := T("C7_FN_" + id)   # 11-28: the hint ran past the card's edge in 3D (the card is narrower there); "show formulas" has them all, so it is left out when it does not fit
		if not _revealed() and not _phone() and (not l3 or r.position.x + 480.0 + _mono().get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, GridText.floor_size(self, GridTheme.fs(9))).x <= r.end.x - 8.0): _text(_mono(), 9, Vector2(r.position.x + 480, y + 24), hint, Color(GridTheme.TEXT, 0.5))
		y += _row(); i += 1
	var cr := Rect2(Vector2(30.0, 412.0), Vector2(minf(w - 60.0, 800.0), maxf(panel.position.y - 412.0 - 12.0, 60.0)))
	if not _phone() and (not l3 or show_card):
		draw_style_box(_box_sb(0.82), cr)
		if show_card: _text(_semi(), 11, cr.position + Vector2(200.0, 26.0), T("C7_FORMULA_CAP"), Color(GridTheme.TEXT, 0.7))
		else: _text(_mono(), 11, cr.position + Vector2(200.0, 26.0), T("C7_HIDE_NOTE"), Color(GridTheme.TEXT, 0.5))
	var gr := Rect2(Vector2(r.end.x + 14.0, top), Vector2(maxf(w - r.end.x - 44.0, 240.0), panel.position.y - top - 12.0))
	if l3: gr = Rect2(Vector2(w - 380.0 - M, top), Vector2(380.0, panel.position.y - top - 12.0))   # 3D: a column at the right edge, the place stays in the middle
	draw_style_box(_box_sb(0.82), gr)
	var g: Dictionary = q.givens; var u: Array = g.units; var a: Dictionary = g.ps17; var b: Dictionary = g.ps18; var c: Dictionary = g.ps24
	var lines := [T("C7_G27_A") % [WorkOrder.num(a.genX), WorkOrder.num(b.genX2), WorkOrder.num(b.genX0), WorkOrder.num(a.xfmrX), WorkOrder.num(a.lineXOhm), WorkOrder.num(b.lineX0Ohm), int(a.kv)]]
	for k in 3: lines.append(T("C7_G27_B") % [k + 1, WorkOrder.num(u[k].a), WorkOrder.num(u[k].b), WorkOrder.num(u[k].c), int(u[k].pMin), int(u[k].pMax)])
	lines.append(T("C7_G27_B2") % [int(g.demandNoLimitsMW), int(g.demandMW)]); lines.append(T("C7_G27_C") % [int(c.f0), WorkOrder.num(c.H), WorkOrder.num(c.Pm), WorkOrder.num(c.Pmax)]); var bd: Dictionary = q.get("board", {}); lines.append(T("C7_G27_D") % [WorkOrder.num(float(bd.get("z1", 0))), WorkOrder.num(float(bd.get("z2", 0))), WorkOrder.num(float(bd.get("z0", 0))), WorkOrder.num(float(bd.get("ibKA", 0)))])
	_text(_semi(), 11, gr.position + Vector2(12.0, 20.0), T("C7_GIV_CAP"), GridTheme.SODIUM)
	var cl := []
	for ln in lines: cl.append([ln, Color(GridTheme.TEXT, 0.82)])
	_card_text(gr, cl, 10, 4.0, 30.0)
	if l3: _pins3()
	if show_card and not _phone():
		var fy := cr.position.y + 58.0
		for f in ["C7_F1", "C7_F2", "C7_F3", "C7_F5"]:
			_text(_mono(), 11, Vector2(cr.position.x + 14.0, fy), T(f), Color(GridTheme.TEXT, 0.85)); fy += 18.0

func _givens_lines() -> Array:
	var g: Dictionary = q.givens; var u: Array = g.units; var a: Dictionary = g.ps17; var b: Dictionary = g.ps18; var c: Dictionary = g.ps24
	var lines := [T("C7_G27_A") % [WorkOrder.num(a.genX), WorkOrder.num(b.genX2), WorkOrder.num(b.genX0), WorkOrder.num(a.xfmrX), WorkOrder.num(a.lineXOhm), WorkOrder.num(b.lineX0Ohm), int(a.kv)]]
	for k in 3: lines.append(T("C7_G27_B") % [k + 1, WorkOrder.num(u[k].a), WorkOrder.num(u[k].b), WorkOrder.num(u[k].c), int(u[k].pMin), int(u[k].pMax)])
	lines.append(T("C7_G27_B2") % [int(g.demandNoLimitsMW), int(g.demandMW)]); lines.append(T("C7_G27_C") % [int(c.f0), WorkOrder.num(c.H), WorkOrder.num(c.Pm), WorkOrder.num(c.Pmax)]); var bd: Dictionary = q.get("board", {}); lines.append(T("C7_G27_D") % [WorkOrder.num(float(bd.get("z1", 0))), WorkOrder.num(float(bd.get("z2", 0))), WorkOrder.num(float(bd.get("z0", 0))), WorkOrder.num(float(bd.get("ibKA", 0)))])
	return lines

## The 3D exam sheet (1128c, like WO-18's): docked at the right edge and kept when the charts fold. Givens on top (the formulas below them when shown; the
## wheel scrolls), the five questions with their boxes at the foot, the engine's answer under each after the run.
func _draw_sheet3() -> void:
	var r := _sheet_rect(); _sheet_frame(r, T("C7_SHEET")); var rv := _revealed()
	var qs := []
	for qq in q.questions: if edits.has(str(qq.id)): qs.append(qq)
	var rh := 36.0 + (18.0 if rv else 0.0)
	var qy := r.end.y - 48.0 - 30.0 - rh * qs.size()
	var cl := []
	for ln in _givens_lines(): cl.append([ln, Color(GridTheme.TEXT, 0.85)])
	if show_card:
		cl.append([T("C7_FORMULA_CAP"), GridTheme.SODIUM])
		for f in ["C7_F1", "C7_F2", "C7_F3", "C7_F5"]: cl.append([T(f), Color(GridTheme.TEXT, 0.85)])
	_text(_semi(), 11, r.position + Vector2(12.0, 54.0), T("C7_GIV_CAP"), GridTheme.SODIUM)
	_sheet_lines(r, r.position.y + 64.0, qy - 8.0, cl)
	draw_line(Vector2(r.position.x + 12.0, qy), Vector2(r.end.x - 12.0, qy), Color(GridTheme.TEXT, 0.18), 1.0)
	_text(_semi(), 11, Vector2(r.position.x + 12.0, qy + 22.0), T("C7_EXAM"), GridTheme.SODIUM)
	var y := qy + 30.0
	for qq in qs:
		var id := str(qq.id)
		_text(_semi(), 12, Vector2(r.position.x + 12.0, y + 21.0), T("C7_Q_" + id), GridTheme.TEXT)
		var e: LineEdit = edits[id]; e.position = Vector2(r.end.x - 12.0 - 84.0, y + 2.0); e.size = Vector2(84, 30); e.visible = true
		if rv and qq.get("actual") != null:
			var ok := bool(qq.get("within", false)); _text(_mono(), 12, Vector2(r.position.x + 24.0, y + 42.0), (T("C7_ANSWER") % WorkOrder.num(float(qq.actual))) + ("  ✓" if ok else "  ✗"), _good(ok))
		y += rh
	if not GridTheme.charts_folded: _pins3()

## The 3D exam: the grown board's rating once run, and tonight's three units against the demand.
func _pins3() -> void:
	var sg := GridTheme.G_TEXT
	if _revealed(): _pin("board", [T("C7_BOARD_KA") % [WorkOrder.num(float(q.boardKA.threePh)), WorkOrder.num(float(q.boardKA.slg))]], [_good(bool(q.ratingOk))], 20.0)
	var s := 0.0
	for k in 3: s += float(q.design.dispatch[k])
	_pin("units", [T("C7_DISPATCH_SUM") % [WorkOrder.num(s), int(q.demandMW)]], [sg], 20.0)
