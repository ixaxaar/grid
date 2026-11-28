class_name Ch7Base
extends Ch4Base
## Chapter 7's stages share this base (it reuses chapter 4's stage plumbing: opaque stage, bottom panel, chips, lock while the clock runs): prediction boxes and
## log/linear plots. Display and input only: every number is the engine's `ch7Study`, every change an engine action.
var edits := {}        ## key -> LineEdit
var plot := {}         ## the last frame drawn by _frame(): rect, lims, logs

func _init() -> void:
	super._init()
	GridUi.load_strings()

func _edit(key: String, w := 78.0) -> LineEdit:
	var e := LineEdit.new(); e.placeholder_text = "?"; e.custom_minimum_size = Vector2(w, 30); e.size = Vector2(w, 30); e.alignment = HORIZONTAL_ALIGNMENT_RIGHT; e.visible = false
	e.text_submitted.connect(func(_s): _submit(key)); e.focus_exited.connect(func(): _submit(key)); e.text_changed.connect(func(_t): queue_redraw()); add_child(e); edits[key] = e
	return e

## What a box sends (the subclass says how: predict, or a setting built from several boxes).
func _submit(_key: String) -> void: pass

func _predict_submit(key: String, qid: String, unit: String) -> void:
	var e: LineEdit = edits[key]; var txt := e.text.strip_edges().replace(",", ".")
	if txt == "" or not txt.is_valid_float() or _locked(): return
	var cur = q.get("predictions", {}).get(qid)
	if cur != null and is_equal_approx(float(cur), float(txt)): return
	_act("predict", [qid, float(txt), unit])

func _sync_predict(key: String, qid: String) -> void:
	var e: LineEdit = edits[key]; e.visible = true; e.editable = not _locked()
	var cur = q.get("predictions", {}).get(qid)
	if not e.has_focus() and cur != null: e.text = WorkOrder.num(float(cur))
	_prompt_style(e)

## A prediction box that is still empty gets a bright border: attempt first.
func _prompt_style(e: LineEdit) -> void:
	if e.text.strip_edges() == "":
		var sb := StyleBoxFlat.new(); sb.bg_color = Color(GridTheme.INK).lightened(0.08); sb.set_corner_radius_all(5); sb.set_border_width_all(2); sb.border_color = GridTheme.SODIUM; sb.content_margin_left = 6; sb.content_margin_right = 6
		e.add_theme_stylebox_override("normal", sb)
	else: e.remove_theme_stylebox_override("normal")

func refresh(st: Dictionary, k: Dictionary) -> void:
	super.refresh(st, k)
	_after_refresh()
	if _phone() and folded: for e in edits.values(): (e as LineEdit).visible = false

func _after_refresh() -> void: pass
func _revealed() -> bool: return bool(q.get("revealed", false))

# ---- plots ----------------------------------------------------------------------------------------------------------------------
func _frame(r: Rect2, xlo: float, xhi: float, ylo: float, yhi: float, logx: bool, logy: bool, xcap := "", ycap := "") -> void:
	plot = {"r": r, "xlo": xlo, "xhi": xhi, "ylo": ylo, "yhi": yhi, "lx": logx, "ly": logy}
	draw_style_box(_box_sb(0.82), r)
	var inner := r.grow(-10.0); plot["r"] = Rect2(inner.position + Vector2(34, 22), inner.size - Vector2(42, 44)); var pr: Rect2 = plot.r
	draw_rect(pr, _bg(Color(GridTheme.NIGHT, 0.6))); draw_rect(pr, Color(GridTheme.SODIUM_DIM, 0.35), false, 1.0)
	var xs: Array = _ticks(xlo, xhi, logx); var ys: Array = _ticks(ylo, yhi, logy)
	for v in xs:
		var p := _pt(float(v), ylo); draw_line(Vector2(p.x, pr.position.y), Vector2(p.x, pr.end.y), Color(GridTheme.TEXT, 0.08), 1.0)
		_text(_mono(), 9, Vector2(p.x - 18.0, pr.end.y + 12.0), WorkOrder.num(float(v)), Color(GridTheme.TEXT, 0.6), 36.0, 1)
	for v in ys:
		var p := _pt(xlo, float(v)); draw_line(Vector2(pr.position.x, p.y), Vector2(pr.end.x, p.y), Color(GridTheme.TEXT, 0.08), 1.0)
		_text(_mono(), 9, Vector2(r.position.x + 4.0, p.y + 3.0), WorkOrder.num(float(v)), Color(GridTheme.TEXT, 0.6), 34.0, 2)
	if xcap != "": _text(_mono(), 10, Vector2(pr.position.x, r.end.y - 6.0), xcap, Color(GridTheme.TEXT, 0.55), pr.size.x, 2)
	if ycap != "": _text(_semi(), 10, Vector2(r.position.x + 14.0, r.position.y + 15.0), ycap, Color(GridTheme.TEXT, 0.7))

func _ticks(lo: float, hi: float, lg: bool) -> Array:
	var out := []
	if lg:
		var e := floorf(log(lo) / log(10.0))
		while pow(10.0, e) <= hi * 1.001:
			for m in [1.0, 2.0, 5.0]:
				var v: float = m * pow(10.0, e)
				if v >= lo * 0.999 and v <= hi * 1.001: out.append(v)
			e += 1.0
	else:
		var step := (hi - lo) / 5.0; var mag := pow(10.0, floorf(log(step) / log(10.0))); step = ceilf(step / mag) * mag
		var v := ceilf(lo / step) * step
		while v <= hi + 1e-9: out.append(v); v += step
	return out

func _pt(x: float, y: float) -> Vector2:
	var r: Rect2 = plot.r
	var fx := (log(maxf(x, 1e-9)) - log(float(plot.xlo))) / (log(float(plot.xhi)) - log(float(plot.xlo))) if bool(plot.lx) else (x - float(plot.xlo)) / (float(plot.xhi) - float(plot.xlo))
	var fy := (log(maxf(y, 1e-9)) - log(float(plot.ylo))) / (log(float(plot.yhi)) - log(float(plot.ylo))) if bool(plot.ly) else (y - float(plot.ylo)) / (float(plot.yhi) - float(plot.ylo))
	return Vector2(r.position.x + clampf(fx, -0.05, 1.05) * r.size.x, r.end.y - clampf(fy, -0.05, 1.05) * r.size.y)

func _poly(pts: Array, col: Color, wd := 2.0) -> void:
	var a := PackedVector2Array()
	for p in pts: a.append(_pt(float(p[0]), float(p[1])))
	if a.size() < 2: return
	var pr = plot.get("r") if plot is Dictionary else null
	if not (pr is Rect2): draw_polyline(a, col, wd, true); return
	for i in a.size() - 1:   # clipped to the plot frame: a curve past the axis range (the I2t limits above 30 s) no longer runs over the frame and its labels
		var seg := _clip(a[i], a[i + 1], pr)
		if seg.size() == 2: draw_line(seg[0], seg[1], col, wd, true)

## The part of the segment p0-p1 inside r (Liang-Barsky); empty when it is wholly outside.
static func _clip(p0: Vector2, p1: Vector2, r: Rect2) -> PackedVector2Array:
	var d := p1 - p0; var t0 := 0.0; var t1 := 1.0
	for e in [[-d.x, p0.x - r.position.x], [d.x, r.end.x - p0.x], [-d.y, p0.y - r.position.y], [d.y, r.end.y - p0.y]]:
		var pp: float = e[0]; var qq: float = e[1]
		if absf(pp) < 1e-9:
			if qq < 0.0: return PackedVector2Array()
		else:
			var t := qq / pp
			if pp < 0.0: t0 = maxf(t0, t)
			else: t1 = minf(t1, t)
	if t0 > t1: return PackedVector2Array()
	return PackedVector2Array([p0 + d * t0, p0 + d * t1])

var rows: Array = []   ## chip rows recorded by _layout_panel, drawn after the panel body
var folded := false    ## phone only: the panel collapsed to its title row so the stage can be reached
var scroll := 0.0      ## phone: vertical drag-scroll offset of the stage's text cards
var scroll_max := 0.0

func _phone() -> bool: return CbLayout.kind == "phone"
func _stage_top() -> float: return 128.0 if _phone() else (TOP if _look3() else 150.0)
func _stage_h(minh: float) -> float: return maxf(panel.position.y - _stage_top() - 10.0, 150.0 if _phone() else minh)

## Draw `lines` ([text, color] pairs) wrapped in `r`, shifted by the scroll offset on a phone; lines that would cross the card edge are left out (a drag scrolls them in).
func _card_text(r: Rect2, lines: Array, fsz: int, gap: float, top_pad: float) -> void:
	var f := _mono(); var fs := GridTheme.fs(fsz); var y := r.position.y + top_pad - (scroll if _phone() else 0.0); var total := 0.0
	for ln in lines:
		var h: float = f.get_multiline_string_size(str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, fs).y
		if y >= r.position.y + top_pad - 1.0 and y + h <= r.end.y - 6.0: GridText.dm(self, f, Vector2(r.position.x + 12.0, y + fs), str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 24.0, fs, -1, ln[1])
		y += h + gap; total += h + gap
	scroll_max = maxf(0.0, total - (r.size.y - top_pad - 8.0))
	if _phone() and scroll_max > 0.0: _text(_mono(), 9, Vector2(r.end.x - 90.0, r.end.y - 8.0), "drag to scroll", Color(GridTheme.TEXT, 0.4))

## The exam sheet (L27, L36 in 3D; 1128c, like WO-18's): one glass sheet docked at the right edge, givens on top (the wheel scrolls them), the questions and their boxes below.
var _gs := 0.0       ## the givens' wheel scroll
var _gs_max := 0.0
func _sheet_rect() -> Rect2:
	var sw := 440.0 if size.x >= 1500.0 else 380.0; var top := TOP - 18.0
	return Rect2(Vector2(_right() - sw - M, top), Vector2(sw, maxf(panel.position.y - top - 12.0, 260.0)))
func _sheet_frame(r: Rect2, title: String) -> void:
	draw_style_box(_box_sb(0.86), r)
	_text(_semi(), 13, r.position + Vector2(12.0, 26.0), title, GridTheme.TEXT)
## [text, colour] lines wrapped between y0 and y1 of the sheet, shifted by the wheel scroll; a line that would cross either edge is left out.
func _sheet_lines(r: Rect2, y0: float, y1: float, lines: Array) -> void:
	var f := _semi(); var fz := GridText.floor_size(self, GridTheme.fs(11)); var wd := r.size.x - 24.0
	var y := y0 - _gs; var total := 0.0
	for ln in lines:
		var h: float = f.get_multiline_string_size(str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, wd, fz).y
		if y >= y0 - 1.0 and y + h <= y1 + 1.0: GridText.dm(self, f, Vector2(r.position.x + 12.0, y + fz), str(ln[0]), HORIZONTAL_ALIGNMENT_LEFT, wd, fz, -1, ln[1])
		y += h + 6.0; total += h + 6.0
	_gs_max = maxf(0.0, total - 6.0 - (y1 - y0)); _gs = clampf(_gs, 0.0, _gs_max)
	if _gs_max > 0.0: _text(_mono(), 9, Vector2(r.end.x - 150.0, r.position.y + 26.0), T("C7_SHEET_MORE") if _gs < _gs_max - 1.0 else T("C7_SHEET_TOP"), Color(GridTheme.TEXT, 0.5), 138.0, 2)

func _gui_input(e: InputEvent) -> void:
	if visible and not _phone() and _exam_sheet() and _look3() and e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_WHEEL_DOWN or e.button_index == MOUSE_BUTTON_WHEEL_UP) and _sheet_rect().has_point(e.position):
		if e.pressed: _gs = clampf(_gs + (30.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -30.0), 0.0, _gs_max); queue_redraw()
		accept_event(); return   # the wheel over the sheet never zooms the world
	if visible and _phone():
		if e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and drag_id == "" and hit_at(e.position).is_empty() and scroll_max > 0.0:
			scroll = clampf(scroll - e.relative.y, 0.0, scroll_max); queue_redraw(); accept_event(); return
		if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_DOWN or e.button_index == MOUSE_BUTTON_WHEEL_UP):
			scroll = clampf(scroll + (24.0 if e.button_index == MOUSE_BUTTON_WHEEL_DOWN else -24.0), 0.0, scroll_max); queue_redraw(); accept_event(); return
	super._gui_input(e)

var _last_slot := Rect2()

## The tray slot moves when the window or the phone insets settle: lay out again whenever it does (the chip rows are recorded at layout time).
func _process(dt: float) -> void:
	super._process(dt)
	if not visible or app == null: return
	var ch = app.get("chrome")
	if ch != null:
		var sl: Rect2 = ch.tray_rect()
		if sl != _last_slot: _last_slot = sl; layout()

func _draw() -> void:
	if visible and app != null: layout()   # the chip rows and boxes are recorded at layout time: lay out against the panel that is drawn now
	super._draw()

func layout() -> void:
	rows.clear()
	super.layout()
	if GridTheme.charts_folded and _look3() and not _exam_sheet():   # 11-28b: the stage's answer boxes fold with the charts; the panel's stay
		for e in edits.values(): if not panel.grow(4.0).has_point((e as LineEdit).position): (e as LineEdit).visible = false
	if _phone() and visible and not _collapsed:   # the levels place their answer boxes in panel coordinates: map them into the scaled slot
		for e in edits.values():
			var le := e as LineEdit
			if le.visible and panel.has_point(le.position): le.position = _scr(le.position); le.scale = Vector2(_sc, _sc)   # stage boxes (L27's exam column) stay as they are
	if _phone() and visible:
		if folded:   # only the title row stays: tap it to open the panel again
			var slot_end := panel.end.y; panel = Rect2(Vector2(panel.position.x, slot_end - 34.0), Vector2(panel.size.x, 34.0)); hits.clear(); rows.clear()
			for e in edits.values(): (e as LineEdit).visible = false
		hits.append({"rect": Rect2(panel.position + Vector2(panel.size.x - 150.0, 0.0), Vector2(150.0, 34.0)), "kind": "chip", "id": "fold", "arg": ""})

func _chip_row(x: float, y: float, w: float, h: float, gap: float, labels: Array, id: String, args: Array, on_arg) -> void:
	for k in labels.size():
		var r := Rect2(Vector2(x + (w + gap) * k, y), Vector2(w, h)); _add_chip(r, id, args[k])
		rows.append({"r": r, "label": str(labels[k]), "on": str(args[k]) == str(on_arg), "id": id, "arg": args[k]})

func _draw_panel() -> void:
	if _phone() and folded:
		draw_style_box(GridTheme.ink_sb(0.94, 10, 0.0), panel); _text(_semi(), 12, panel.position + Vector2(12.0, 22.0), T("C7_PANEL") + "  (%s)" % scenario, Color(GridTheme.TEXT, 0.85)); _text(_semi(), 14, panel.position + Vector2(panel.size.x - 40.0, 23.0), "▸", GridTheme.SODIUM)
		return
	super._draw_panel()
	if _phone(): _text(_semi(), 14, panel.position + Vector2(panel.size.x - 40.0, 23.0), "▾", GridTheme.SODIUM)
	for c in rows: _chip(c.r, c.label, "", c.on, c.id, c.arg)

## The price tag, with a caption that says what the number is: the starting kit (the build the level begins with) is already on the bill.
func _draw_price_tag(pn: Rect2) -> void:
	var spent := float(q.get("cost", 0.0)); var budget := float(q.get("budget", 0.0))
	var over := budget > 0.0 and spent > budget + 0.0001
	var txt := T("C4_SPENT") % [_money(spent), _money(budget)] if budget > 0.0 else _money(spent)
	var mono := _mono(); var semi := _semi()
	var w := 176.0; var h := 44.0
	var fz16 := GridText.floor_size(self, 13)   # 1.9: the tag grows to its words at the 16 px floor (it clipped "build incl. starting kit")
	w = maxf(w, maxf(semi.get_string_size(T("C7_KIT_CAP"), HORIZONTAL_ALIGNMENT_LEFT, -1, fz16).x + 34.0, mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fz16).x + 20.0)); h = maxf(h, fz16 * 2.0 + 16.0)
	var org := Vector2(pn.end.x - 12.0 - w, pn.end.y - 12.0 - h) if not _narrow() else Vector2(pn.end.x - 12.0 - w, pn.position.y - h - 6.0)
	var g3 := _look3()
	draw_set_transform(_scr(org + Vector2(w, h) * 0.5), 0.0 if g3 else deg_to_rad(-1.4), Vector2(_sc, _sc))   # phone: the panel is drawn scaled into the tray slot, so is its tag
	var rect := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_style_box(GridTheme.glass_sb(0.8, 4, 0.0) if g3 else GridTheme.paper_sb(3, 0.0), rect)
	if not g3: draw_circle(Vector2(-w * 0.5 + 11.0, -h * 0.5 + 11.0), 3.5, GridTheme.INK)
	var fsz := GridTheme.fs(13); var tw2 := mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	while tw2 > w - 16.0 and fsz > 9: fsz -= 1; tw2 = mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var ink := GridTheme.G_TEXT if g3 else GridTheme.PAPER_INK
	GridText.ds(self, semi, Vector2(-w * 0.5 + (12.0 if g3 else 22.0), -h * 0.5 + 15.0), T("C7_KIT_CAP"), HORIZONTAL_ALIGNMENT_LEFT, -1, GridTheme.fs(10), Color(GridTheme.G_DIM if g3 else ink, 1.0 if g3 else 0.7))
	GridText.ds(self, mono, Vector2(-tw2 * 0.5, h * 0.5 - 8.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, (GridTheme.BAD if g3 else GridTheme.BAD.darkened(0.15)) if over else ink)
	draw_set_transform(_p0 - panel.position * _sc, 0.0, Vector2(_sc, _sc))   # back to the panel's transform (identity on desktop): the chip rows drawn after the tag were left unscaled and ran past the slot on the phone
