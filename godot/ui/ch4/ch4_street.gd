class_name Ch4Street
extends Ch4Base
## L10 Balance the Phases: Tanner Street at dusk. The transformer on the left, three phase wires and the neutral along six poles, three houses under each pole. A house hangs
## from the phase wire its service drop is on (tap it to move the drop a -> b -> c, right-click or shift back). Above the street: the phasor chain I_a + I_b + I_c (it
## closes into a triangle when the street is balanced and the missing side is the neutral current), the phase currents against the neutral, and the far-pole voltages
## against the supply band. Cute mode: the houses have faces, happy while their phase is in band; TVs spark when a phase rises too high.
const PH := ["a", "b", "c"]
const PH_COL := {"a": Color("#E5484D"), "b": Color("#F2C94C"), "c": Color("#4FA3FF")}
var _g := {}

func _init() -> void:
	scenario = "l10"; name = "Ch4Street"

func _geo() -> Dictionary:
	var w := _vs().x; var h := _vs().y
	var ground := h * 0.665; var wire := ground - 150.0
	var x0 := 215.0; var x1 := w - 175.0; var sp := (x1 - x0) / 5.0
	return {"ground": ground, "wire": wire, "x0": x0, "sp": sp, "tx": 92.0}

func _house_rect(i: int, g: Dictionary) -> Rect2:
	var pole := i / 3; var j := i % 3
	var hs := minf(62.0, float(g.sp) / 3.1); var hx := float(g.x0) + float(g.sp) * pole + (j - 1) * hs
	return Rect2(Vector2(hx - 21.0, float(g.ground) - 46.0), Vector2(42.0, 46.0))

func _layout_panel() -> void:
	_g = _geo()
	for i in 18: hits.append({"rect": _house_rect(i, _g).grow(4.0), "kind": "item", "id": "house", "arg": i, "stage": true})
	var ns: Array = kit.get("l10", {}).get("neutrals", [])
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0))
	var cw := 140.0; var x := inner.position.x
	for k in ns.size():
		_add_chip(Rect2(Vector2(x + (cw + 6.0) * k, inner.position.y + 22.0), Vector2(cw, 46.0)), "neutral", float(ns[k].mm2))

func _press(h: Dictionary, _p: Vector2) -> void:
	if str(h.kind) == "chip" and str(h.id) == "neutral": _act("setNeutral", [float(h.arg)])
	elif str(h.kind) == "item":
		var i := int(h.arg); var cur: String = str(q.houses[i].phase); var k := PH.find(cur)
		var nxt: String = PH[(k + (2 if bool(h.get("right", false)) else 1)) % 3]
		_act("assignPhase", ["H%d" % (i + 1), nxt])

# ---- stage ------------------------------------------------------------------------------------------------------------------------
func _draw_stage() -> void:
	if _look3(): _draw_stage3(); return
	var g := _g if not _g.is_empty() else _geo()
	var w := _vs().x; var h := _vs().y; var ground: float = g.ground; var wire: float = g.wire
	draw_rect(Rect2(0, ground, w, h - ground), Color("#17331F"))
	draw_rect(Rect2(0, ground, w, 5), Color("#2B4A2C"))
	_draw_instruments()
	_draw_wires(g)
	for i in 18: _draw_house(i, g)
	_draw_transformer(g)

# ---- the 3D street: the place is Stage3D; the charts stay in glass, a click on a house is the tap it always was ---------------------------------

## Put each house's tap on the house as the 3D camera sees it (the hits keep their order and count; only the rects follow the view).
func _sync_house_hits() -> void:
	var l3 = app.get("grid_world").look3d
	for h in hits:
		if str(h.id) != "house": continue
		var r: Rect2 = l3.house_rect(int(h.arg))
		if r.size == Vector2.ZERO: h["rect"] = Rect2(Vector2(-9999, -9999), Vector2.ZERO); continue
		var a := _to_local(r.position); var b := _to_local(r.end)
		h["rect"] = Rect2(a, Vector2.ZERO).expand(b)

func hit_at(p: Vector2) -> Dictionary:
	if _look3(): _sync_house_hits()
	return super.hit_at(p)

func _stage_rects() -> Array:
	_sync_house_hits()
	var out: Array = []
	for h in hits: if str(h.id) == "house": out.append(h.rect)
	return out

func _draw_stage3() -> void:
	_g = _geo()
	_draw_instruments()
	var tx := T("C4_TX"); var tl := tx.substr(0, 1).to_upper() + tx.substr(1)
	_pin("tx", [tl, "11 kV · 230/400 V"], [GridTheme.G_TEXT, GridTheme.G_DIM], 30.0)
	_pin("neutral", [T("C4_IN_SUM") % _f(float(q.iN), 1)], [_good(bool(q.pass.neutral))], 40.0)
	if hover.begins_with("house/"):   # the house under the pointer: its number, load, phase and voltage
		var i := int(hover.get_slice("/", 1)); var st := _house_state(i); var l3 = app.get("grid_world").look3d
		var r: Rect2 = l3.house_rect(i)
		if r.size != Vector2.ZERO:
			var okv: bool = float(st.v) >= float(q.loV) and float(st.v) <= float(q.hiV)
			_pin_at(Vector2(r.get_center().x, r.position.y), ["H%d · %s kVA · %s kW" % [i + 1, _f(float(q.houses[i].kva), 1), WorkOrder.num(float(q.houses[i].kw))], "%s · %s V" % [String(st.ph), _f(float(st.v), 1)]], [GridTheme.G_TEXT, _good(okv)], 14.0)

func _wire_y(g: Dictionary, ph: String) -> float: return float(g.wire) + 11.0 * PH.find(ph)
func _neutral_y(g: Dictionary) -> float: return float(g.wire) + 44.0

func _draw_wires(g: Dictionary) -> void:
	var ground: float = g.ground; var x0: float = g.x0; var sp: float = g.sp; var tx: float = g.tx
	var ip: Dictionary = q.iPhase; var imax := maxf(float(q.iMax), 1.0)
	var n_dir := -1.0
	for k in 6:   # the poles and cross-arms
		var px := x0 + sp * k
		draw_line(Vector2(px, ground), Vector2(px, float(g.wire) - 14.0), Color("#8A6A43"), 6.0)
		draw_line(Vector2(px - 16, float(g.wire) - 6.0), Vector2(px + 16, float(g.wire) - 6.0), Color("#8A6A43"), 5.0)
		_text(_mono(), 11, Vector2(px - 18.0, float(g.wire) - 20.0), T("C4_POLE") % (k + 1), Color(GridTheme.TEXT, 0.55), 36.0, 1)
	var xe := x0 + sp * 5.0
	for ph in PH:
		var y := _wire_y(g, ph); var c: Color = PH_COL[ph]
		draw_line(Vector2(tx, y), Vector2(xe + 12.0, y), Color(c, 0.9), 3.0, true)
		var spd := 0.05 + 0.5 * float(ip[ph]) / maxf(imax, 60.0)
		var n := int((xe - tx) / 26.0)
		for d in n:
			var u := fposmod(float(d) / float(n) + _t * spd, 1.0)
			draw_circle(Vector2(lerpf(tx, xe + 12.0, u), y), 2.4, Color(1, 1, 1, 0.85))
	var ny := _neutral_y(g); var inn := float(q.iN)
	draw_line(Vector2(tx, ny), Vector2(xe + 12.0, ny), Color("#C9CED6"), 3.0, true)
	var nsp := 0.05 + 0.5 * inn / maxf(imax, 60.0); var nn := int((xe - tx) / 26.0)
	for d in nn:
		var u2 := fposmod(float(d) / float(nn) - _t * nsp * n_dir * -1.0, 1.0)
		if inn > 0.5: draw_circle(Vector2(lerpf(tx, xe + 12.0, u2), ny), 2.4 + minf(inn / 60.0, 2.0), Color("#FFFFFF", 0.9))
	_text(_mono(), 11, Vector2(xe + 22.0, ny + 4.0), T("C4_NEUTRAL"), Color("#C9CED6"))
	for ph in PH: _text(_mono(), 11, Vector2(xe + 22.0, _wire_y(g, ph) + 4.0), String(ph), PH_COL[ph])

func _draw_transformer(g: Dictionary) -> void:
	var tx: float = g.tx; var ground: float = g.ground
	draw_line(Vector2(tx, ground), Vector2(tx, float(g.wire) - 20.0), Color("#8A6A43"), 8.0)
	var r := Rect2(Vector2(tx - 30.0, float(g.wire) - 78.0), Vector2(60.0, 56.0))
	draw_rect(r, Color("#58606E")); draw_rect(r, Color("#8E99A8"), false, 2.0)
	for k in 3: draw_rect(Rect2(r.position + Vector2(8.0 + 17.0 * k, -9.0), Vector2(7, 9)), Color("#B8C0CC"))
	_text(_mono(), 11, r.position + Vector2(0, 22.0), "11 kV", Color.WHITE, r.size.x, 1)
	_text(_mono(), 11, r.position + Vector2(0, 38.0), "230/400", Color(GridTheme.SODIUM), r.size.x, 1)
	_text(_semi(), 12, Vector2(4.0, float(g.ground) + 22.0), T("C4_TX"), Color(GridTheme.TEXT, 0.7), 84.0, 0)
	if GridSettings.cute: _face(r.position + Vector2(30.0, 44.0), 11.0, bool(q.pass.neutral), 0.9)

func _house_state(i: int) -> Dictionary:
	var hv: Dictionary = q.houses[i]; var ph: String = str(hv.phase)
	var v := float(q.vLevels[ph][1 + i / 3 + 1]) if q.vLevels.has(ph) else 230.0   # voltage at this house's pole (level k + 2)
	return {"v": v, "ph": ph, "kw": float(hv.kw)}

func _draw_house(i: int, g: Dictionary) -> void:
	var r := _house_rect(i, g); var st := _house_state(i); var ph: String = st.ph; var col: Color = PH_COL[ph]
	var lo := float(q.loV); var hi := float(q.hiV); var v: float = st.v
	var okv := v >= lo and v <= hi
	var cx := r.position.x + r.size.x * 0.5
	# the service drop from this phase's wire
	draw_line(Vector2(cx, _wire_y(g, ph)), Vector2(cx, r.position.y - 12.0), Color(col, 0.95), 2.0, true)
	draw_rect(r, Color("#B9A27F").lerp(col, 0.38)); draw_colored_polygon(PackedVector2Array([r.position + Vector2(-5, 0), r.position + Vector2(r.size.x + 5, 0), r.position + Vector2(r.size.x * 0.5, -14.0)]), Color("#8B3B2E"))
	var lit := clampf((v - 170.0) / 60.0, 0.15, 1.0)
	var win := Rect2(r.position + Vector2(6.0, 8.0), Vector2(12.0, 11.0))
	draw_rect(win, Color("#141A33")); draw_rect(win, Color("#FFD27A", lit), true)
	var door := Rect2(r.position + Vector2(r.size.x - 18.0, r.size.y - 22.0), Vector2(12.0, 22.0)); draw_rect(door, col.darkened(0.25))
	_text(_mono(), 11, door.position + Vector2(0, 14.0), ph, Color.WHITE, door.size.x, 1)
	if v > hi:   # the TV sparks: the lightly loaded phase rises when the neutral carries the imbalance
		var sx := cx + 4.0; var sy := r.position.y - 20.0
		var z := PackedVector2Array([Vector2(sx, sy), Vector2(sx + 5, sy - 7), Vector2(sx - 1, sy - 8), Vector2(sx + 6, sy - 17)])
		draw_polyline(z, Color("#FFF27A"), 2.0, true)
	if GridSettings.cute: _face(r.position + Vector2(r.size.x * 0.5 - 2.0, 30.0), 8.0, okv, 0.8)
	_text(_mono(), 10, Vector2(r.position.x - 8.0, r.end.y + 13.0), "H%d" % (i + 1), Color(GridTheme.TEXT, 0.75), r.size.x + 16.0, 1)
	_text(_mono(), 10, Vector2(r.position.x - 8.0, r.end.y + 25.0), "%s kVA" % _f(float(q.houses[i].kva), 1), Color(GridTheme.SODIUM, 0.9), r.size.x + 16.0, 1)
	_text(_mono(), 9, Vector2(r.position.x - 8.0, r.end.y + 36.0), "%s kW" % WorkOrder.num(float(q.houses[i].kw)), Color(GridTheme.TEXT, 0.45), r.size.x + 16.0, 1)

func _draw_far_voltage(g: Dictionary) -> void:
	var xe := float(g.x0) + float(g.sp) * 5.0
	var vf: Dictionary = q.vFar
	for ph in PH:
		var v := float(vf[ph]); var ok := v >= float(q.loV) and v <= float(q.hiV)
		_text(_mono(), 11, Vector2(xe + 30.0, float(g.ground) + 18.0 + 13.0 * PH.find(ph)), "%s %s V" % [String(ph), _f(v, 1)], _good(ok))

# ---- instruments ------------------------------------------------------------------------------------------------------------------
func _draw_instruments() -> void:
	var w := _vs().x
	# the phasor chain: I_a, then I_b from its tip, then I_c: the closing side is I_N
	var c := Vector2(150.0, 178.0); var R := 64.0
	draw_style_box(_box_sb(0.82), Rect2(c - Vector2(R + 22.0, R + 30.0), Vector2((R + 22.0) * 2.0, (R + 22.0) * 2.0 + 18.0)))
	if _look3(): _wrap(_semi(), 11, c + Vector2(-R - 12.0, -R - 12.0), T("C4_CHAIN"), Color(GridTheme.TEXT, 0.7), (R + 12.0) * 2.0)   # wraps inside its glass box
	else: _text(_semi(), 11, c + Vector2(-R - 12.0, -R - 12.0), T("C4_CHAIN"), Color(GridTheme.TEXT, 0.7))
	var ph: Dictionary = q.phasors; var pts: Array = [Vector2.ZERO]
	var cur := Vector2.ZERO
	for p in PH:
		var m := float(ph[p].mag); var a := deg_to_rad(float(ph[p].deg)); cur += Vector2(cos(a), -sin(a)) * m; pts.append(cur)
	var lo := Vector2(INF, INF); var hi := Vector2(-INF, -INF)
	for p in pts: lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y)); hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var ext := maxf(maxf(hi.x - lo.x, hi.y - lo.y), 1.0); var sc := (R * 1.55) / ext; var ctr := (lo + hi) * 0.5
	var P := func(v: Vector2) -> Vector2: return c + (v - ctr) * sc
	for k in 3:
		_arrow(P.call(pts[k]), P.call(pts[k + 1]), PH_COL[PH[k]], 3.0)
	var inn := float(q.iN)
	if inn > 0.4: _arrow(P.call(pts[0]), P.call(pts[3]), Color.WHITE, 4.0)
	else: draw_circle(P.call(pts[0]), 4.0, Color.WHITE)
	draw_circle(P.call(pts[0]), 3.0, Color(GridTheme.INK))
	_text(_mono(), 12, c + Vector2(-R - 14.0, R + 16.0), T("C4_IN_SUM") % _f(inn, 1), _good(bool(q.pass.neutral)))
	# phase currents and the neutral
	var bx := 300.0 if not _look3() else 330.0; var by := 120.0; var bh := 160.0; var bw := 38.0
	draw_style_box(_box_sb(0.82), Rect2(Vector2(bx - 14.0, by - 30.0), Vector2(bw * 4.0 + 120.0 + (110.0 if _look3() else 0.0), bh + 96.0 + (40.0 if _look3() else 0.0))))
	_text(_semi(), 11, Vector2(bx, by - 12.0), T("C4_CURRENTS"), Color(GridTheme.TEXT, 0.7))
	var scale_a := maxf(180.0, float(q.iMax) * 1.1)
	var ip: Dictionary = q.iPhase
	for k in 3:
		var p: String = PH[k]; var v := float(ip[p]); var rr := Rect2(Vector2(bx + (bw + 10.0) * k, by + bh - bh * v / scale_a), Vector2(bw, bh * v / scale_a))
		draw_rect(rr, Color(PH_COL[p], 0.9)); _text(_mono(), 11, Vector2(rr.position.x - 4.0, rr.position.y - 4.0), "%s" % _f(v, 0), Color.WHITE, bw + 8.0, 1)
		_text(_mono(), 11, Vector2(rr.position.x, by + bh + 14.0), String(p), PH_COL[p], bw, 1)
	var nrect := Rect2(Vector2(bx + (bw + 10.0) * 3, by + bh - bh * float(q.iN) / scale_a), Vector2(bw, bh * float(q.iN) / scale_a))
	draw_rect(nrect, Color("#FFFFFF", 0.9)); _text(_mono(), 11, Vector2(nrect.position.x - 4.0, nrect.position.y - 4.0), _f(float(q.iN), 0), Color.WHITE, bw + 8.0, 1)
	_text(_mono(), 11, Vector2(nrect.position.x, by + bh + 14.0), "N", Color.WHITE, bw, 1)
	var lim_y := by + bh - bh * (float(q.iNmaxPct) / 100.0 * float(q.iMax)) / scale_a
	draw_line(Vector2(bx + (bw + 10.0) * 3 - 6.0, lim_y), Vector2(bx + (bw + 10.0) * 3 + bw + 6.0, lim_y), GridTheme.GOOD, 2.0)
	var rat_y := by + bh - bh * float(q.neutral.ampacityA) / scale_a
	draw_line(Vector2(bx + (bw + 10.0) * 3 - 6.0, rat_y), Vector2(bx + (bw + 10.0) * 3 + bw + 6.0, rat_y), GridTheme.BAD, 2.0)
	_text(_mono(), 10, Vector2(bx + (bw + 10.0) * 3 + bw + 10.0, lim_y + 4.0), T("C4_LIM_PCT") % WorkOrder.num(float(q.iNmaxPct)), GridTheme.GOOD)
	_text(_mono(), 10, Vector2(bx + (bw + 10.0) * 3 + bw + 10.0, rat_y + 4.0), T("C4_RATED") % int(q.neutral.ampacityA), GridTheme.BAD)
	if _look3():   # 3D: the two sentences wrap inside the box
		var cwid := bw * 4.0 + 110.0 + 80.0
		_wrap(_mono(), 12, Vector2(bx - 4.0, by + bh + 34.0), T("C4_IN_PCT") % [_f(float(q.iNpct), 1)], _good(bool(q.pass.neutral)), cwid)
		_wrap(_mono(), 11, Vector2(bx - 4.0, by + bh + 74.0), T("C4_CUT"), Color(GridTheme.SODIUM, 0.9), cwid)
	else:
		_text(_mono(), 11, Vector2(bx - 4.0, by + bh + 52.0), T("C4_CUT"), Color(GridTheme.SODIUM, 0.9))
		_text(_mono(), 12, Vector2(bx - 4.0, by + bh + 34.0), T("C4_IN_PCT") % [_f(float(q.iNpct), 1)], _good(bool(q.pass.neutral)))
	# far-pole voltages against the supply band
	var vx := 850.0; var vy := 158.0; var vw := 330.0
	if w < 1250.0: vx = 640.0; vw = w - vx - 20.0
	if _look3(): vx = 900.0; vy = 196.0; vw = minf(330.0, _right() - vx - 40.0)   # under the clock, clear of the currents box
	draw_style_box(_box_sb(0.82), Rect2(Vector2(vx - 14.0, vy - 30.0), Vector2(vw + 28.0, 160.0 if _look3() else 150.0)))
	_text(_semi(), 11, Vector2(vx, vy - 12.0), T("C4_VFAR"), Color(GridTheme.TEXT, 0.7))
	var vmin := 185.0; var vmax := 265.0
	var X := func(v: float) -> float: return vx + vw * (clampf(v, vmin, vmax) - vmin) / (vmax - vmin)
	draw_rect(Rect2(Vector2(vx, vy + 16.0), Vector2(vw, 18.0)), _bg(Color("#0B1026")))
	draw_rect(Rect2(Vector2(X.call(float(q.loV)), vy + 16.0), Vector2(X.call(float(q.hiV)) - X.call(float(q.loV)), 18.0)), Color(GridTheme.GOOD, 0.35))
	for k in [200.0, 230.0, 260.0]: _text(_mono(), 10, Vector2(X.call(k) - 14.0, vy + 50.0), "%d" % int(k), Color(GridTheme.TEXT, 0.55), 28.0, 1)
	draw_line(Vector2(X.call(230.0), vy + 12.0), Vector2(X.call(230.0), vy + 38.0), Color(1, 1, 1, 0.5), 1.0)
	for k in 3:
		var p: String = PH[k]; var v := float(q.vFar[p]); var xx: float = X.call(v)
		draw_colored_polygon(PackedVector2Array([Vector2(xx, vy + 36.0), Vector2(xx - 7.0, vy + 22.0 - 2.0), Vector2(xx + 7.0, vy + 22.0 - 2.0)]), PH_COL[p])
		_text(_mono(), 12, Vector2(vx + (vw + 28.0) / 3.0 * k, vy + 76.0) if _look3() else Vector2(vx + 100.0 * k, vy + 76.0), "%s  %s V" % [String(p), _f(v, 1)], _good(v >= float(q.loV) and v <= float(q.hiV)))
	_text(_mono(), 11, Vector2(vx, vy + 98.0), T("C4_BAND") % [int(q.loV), int(q.hiV)], Color(GridTheme.GOOD, 0.9))
	_text(_mono(), 11, Vector2(vx, vy + (122.0 if _look3() else 114.0)), T("C4_LOSS") % _f(float(q.lossPct), 2), _good(bool(q.starLoss)))

func _draw_panel_body() -> void:
	var inner := Rect2(panel.position + Vector2(12.0, 8.0), panel.size - Vector2(24.0, 16.0))
	var semi := _semi(); var mono := _mono(); var lock := _locked()
	_text(semi, 11, inner.position + Vector2(0, 15.0), T("C4_NEUTRAL_CAP"), Color(GridTheme.TEXT, 0.7))
	_text(semi, 12, inner.position + Vector2(0, 86.0), T("C4_TAP_HOUSE"), Color(GridTheme.SODIUM, 0.9))
	var tw := inner.size.x - 450.0   # the notes right of the three chips wrap inside the panel
	_wrap(mono, 12, inner.position + Vector2(450.0, 34.0), T("C4_MOVED") % [int(q.moved), str(kit.get("l10", {}).get("moveHouse", ""))], Color(GridTheme.TEXT, 0.8), tw)
	_wrap(mono, 12, inner.position + Vector2(450.0, 72.0), T("C4_SPREAD") % [_f(float(q.kvaPh.a), 1), _f(float(q.kvaPh.b), 1), _f(float(q.kvaPh.c), 1)], Color(GridTheme.TEXT, 0.8), tw)
	var ns: Array = kit.get("l10", {}).get("neutrals", [])
	for h in hits:
		if str(h.kind) != "chip": continue
		var mm := float(h.arg); var info: Dictionary = {}
		for n in ns: if float(n.mm2) == mm: info = n
		_chip(h.rect, "%s mm²" % WorkOrder.num(mm), "%d A · %s" % [int(info.get("ampacityA", 0)), str(info.get("upgrade", ""))], is_equal_approx(float(q.neutral.mm2), mm), "neutral", mm, not lock)
	var y := inner.position.y + 134.0
	var checks := [[T("C4_CHK_NEUTRAL") % [_f(float(q.iNpct), 1), WorkOrder.num(float(q.iNmaxPct))], bool(q.pass.neutral)], [T("C4_CHK_VOLTS"), bool(q.pass.volts)], [T("C4_CHK_RATING") % [_f(float(q.iN), 0), int(q.neutral.ampacityA)], bool(q.pass.rating)]]
	var x := inner.position.x
	var right := inner.end.x - 250.0   # QA 1128c Q03: the price tag sits bottom right; a check that would run under it starts a line above
	var ws: Array = checks.map(func(c): return mono.get_string_size(("✓ " if c[1] else "✗ ") + str(c[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, GridTheme.fs(11)).x + 28.0)
	var total: float = ws.reduce(func(a, b): return a + b, 0.0)
	if x + total > right: y -= 20.0
	for i in checks.size():
		var c: Array = checks[i]
		var ct := ("✓ " if c[1] else "✗ ") + str(c[0])
		if x + float(ws[i]) - 28.0 > right and x > inner.position.x: x = inner.position.x; y += 20.0
		_text(mono, 11, Vector2(x, y), ct, _good(bool(c[1])))
		x += float(ws[i])   # each check starts after the one before it
	if q.fail != null and not bool(q.done): pass
