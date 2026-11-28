class_name Ch4Base
extends Control
## Chapter 4's stages share this base: an opaque stage drawn by the subclass, the bottom panel in the tray slot (chips, steppers, the paper price tag), taps and
## drags on the panel and on stage items, and the lock while the clock runs. Display and input only: every number is the engine's `ch4Status`, every change is an
## engine action. Cute mode: the faces are happy exactly when the engine says the numbers are in band.
const M := 14.0
const PANEL_H := 184.0

var app: CbApp
var q: Dictionary = {}          ## ch4Status
var kit: Dictionary = {}        ## ch4Kit
var scenario := ""              ## "l10" .. "l13", set by the subclass
var panel := Rect2()
var hits: Array = []            ## {rect, kind: "chip"|"step"|"item"|"slider", id, arg ...}
var hover := ""
var drag_id := ""
var _t := 0.0
var _pan := Vector2.ZERO        ## phone: the stage is a 1366 x 768 canvas panned under the HUD and above the panel
var _collapsed := false          ## phone: the panel folded to its title bar
var _sc := 1.0                   ## phone: the panel is laid out 660 wide and drawn scaled to the slot
var _p0 := Vector2.ZERO          ## screen top-left of the panel
var _panning := false
var _pan_set := false
const PANEL_VW := 660.0
const HUD_BOTTOM := 70.0

static func T(key: String) -> String: return TranslationServer.translate(key)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP; visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GridUi.load_strings(); TrayStrings.load_strings()

func _phone() -> bool: return CbLayout.kind == "phone"

## The 3D place (world3d/stage3d.gd) is showing: this stage keeps only its charts and its panel, in glass, and hangs chips on the place's anchors.
func _look3() -> bool:
	var w = app.get("grid_world") if app != null else null
	return w != null and w.look3d != null and w.look3d.visible and w.look3d is Stage3D

## In 3D only the panel (and what the stage lists in _extra_hit_rects: the houses' taps) takes the mouse; drags elsewhere reach the world and turn the camera.
func _has_point(p: Vector2) -> bool:
	if not _look3(): return Rect2(Vector2.ZERO, size).has_point(p)
	if panel.grow(4.0).has_point(p) or _tag_rect().has_point(p) or _fold_rect().has_point(p): return true
	if GridTheme.charts_folded and not _exam_sheet(): return false
	for r in _stage_rects(): if (r as Rect2).has_point(p): return true
	return false

## An exam job (L27, L36) keeps its exam sheet when the charts fold: the sheet is the job (1128c, like WO-18's).
func _exam_sheet() -> bool: return false

## The rects of the stage that take the mouse in 3D (charts that are controls: none today; L10's houses).
func _stage_rects() -> Array: return []

func _fold_rect() -> Rect2: return Rect2()
func _tag_rect() -> Rect2:
	return Rect2(Vector2(panel.end.x - 260.0, panel.position.y - 56.0), Vector2(260.0, 56.0)) if _narrow() else Rect2()

## The fill behind a plot: a light tint over the glass in 3D (the world shows through), the stage's own navy otherwise. Charts in 3D are all one glass.
func _bg(c: Color) -> Color: return Color(0.0, 0.0, 0.0, 0.2) if _look3() else c

## A chart box: glass over the 3D place, the navy ink of the classic stage otherwise.
func _box_sb(a: float) -> StyleBoxFlat:
	return GridTheme.glass_sb(0.78, 4, 0.0) if _look3() else GridTheme.ink_sb(a, 10, 0.0)

## The stage's drawing size: the screen on desktop, a fixed canvas on phone.
func _vs() -> Vector2: return Vector2(maxf(size.x, 1366.0), 768.0) if _phone() else size

## Where the stage's boxes end: above the panel on desktop, above where the panel would stand on the canvas on phone.
func _stage_bottom() -> float: return 768.0 - PANEL_H if _phone() else panel.position.y

func _off() -> Vector2: return _pan if _phone() else Vector2.ZERO

## Panel space (the layout's) to screen space and back.
func _scr(v: Vector2) -> Vector2: return _p0 + (v - panel.position) * _sc
func _unscr(p: Vector2) -> Vector2: return panel.position + (p - _p0) / _sc

func _pan_limits() -> Rect2:
	var top := _p0.y if _phone() else size.y
	var lo := Vector2(minf(0.0, size.x - _vs().x), minf(0.0, top - 612.0))
	return Rect2(lo, -lo)

## Phone: open the stage panned to the bottom (its charts clear of the coach card and the panel) instead of the top.
func _start_low() -> bool: return false

func _clamp_pan() -> void:
	var r := _pan_limits(); _pan = Vector2(clampf(_pan.x, r.position.x, 0.0), clampf(_pan.y, r.position.y, 0.0))

func _locked() -> bool:
	return app == null or app.speed > 0 or str(app.b.g.get("status", "playing")) != "playing"

func refresh(st: Dictionary, k: Dictionary) -> void:
	q = st; kit = k; visible = true
	if size.x < 8.0 or size.y < 8.0: set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)   # built before the chrome had a size: anchor again now that it has
	layout(); queue_redraw()

func layout() -> void:
	if app == null or not visible: return
	var ch = app.get("chrome")
	if ch != null and (ch.radio == null or ch.breaker == null): return   # the chrome is still being built
	var slot: Rect2 = ch.tray_rect() if ch != null else Rect2(Vector2(M, size.y - 96 - M), Vector2(size.x - 2 * M, 96))
	var w := maxf(slot.size.x, 320.0)
	if _phone():
		_sc = clampf(w / PANEL_VW, 0.5, 1.0)
		var ph := 26.0 if _collapsed else PANEL_H * _sc
		_p0 = Vector2(slot.position.x, slot.end.y - ph)
		panel = Rect2(_p0, Vector2(PANEL_VW, PANEL_H))
		if not _pan_set: _pan_set = true; _pan = Vector2(0.0, -10000.0 if scenario == "l10" or _start_low() else 0.0)
		_clamp_pan()
		hits.clear()
		if not _collapsed: _layout_panel()
		else: _on_collapsed()
		_layout_extra()
		hits.append({"rect": Rect2(Vector2(_p0.x + w - 40.0, _p0.y), Vector2(40.0, 26.0)), "kind": "fold", "id": "fold", "arg": "", "screen": true})
		return
	_sc = 1.0
	panel = Rect2(Vector2(slot.position.x, slot.end.y - PANEL_H), Vector2(w, PANEL_H))
	if panel.end.x > size.x - M: panel.position.x = size.x - M - panel.size.x
	_p0 = panel.position
	hits.clear()
	_layout_panel()
	_layout_extra()

## A stage's own hits on the screen (the chip that opens the charts it keeps shut in 3D).
func _layout_extra() -> void: pass
func _tog(_id: String) -> void: pass
func _layout_panel() -> void: pass
func _on_collapsed() -> void: pass
func _draw_stage() -> void: pass
func _draw_panel_body() -> void: pass
func _press(_h: Dictionary, _p: Vector2) -> void: pass
func _drag(_h: Dictionary, _p: Vector2) -> void: pass
func _narrow() -> bool: return panel.size.x < 560.0

# ---- input ------------------------------------------------------------------------------------------------------------------------
func _gui_input(e: InputEvent) -> void:
	if not visible: return
	if e is InputEventMouseButton and (e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT):
		if e.pressed:
			var h := hit_at(e.position)
			if h.is_empty():
				if _phone(): _panning = true; accept_event()
				return
			if str(h.kind) == "fold": _collapsed = not _collapsed; layout(); queue_redraw(); accept_event(); return
			if str(h.kind) == "tog": _tog(str(h.id)); layout(); queue_redraw(); app.sfx("click"); accept_event(); return   # a view toggle works while the clock runs
			if _locked(): app.toast(T("C4_LOCKED"), "warn"); app.sfx("bad"); accept_event(); return
			h = h.duplicate(); h["right"] = e.button_index == MOUSE_BUTTON_RIGHT or e.shift_pressed
			drag_id = str(h.id) if str(h.kind) == "slider" and on_track(h.rect, _local(h, e.position)) else ""   # a press on − / + or the caption never starts a drag
			_press(h, _local(h, e.position)); accept_event()
		else: drag_id = ""; _panning = false
	elif e is InputEventMouseMotion:
		var hv := hit_at(e.position)
		var hs := "%s/%s" % [str(hv.get("id", "")), str(hv.get("arg", ""))] if not hv.is_empty() else ""
		if hs != hover: hover = hs; queue_redraw()
		if _panning and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			_pan += (e as InputEventMouseMotion).relative; _clamp_pan(); layout(); queue_redraw(); accept_event(); return
		if drag_id != "" and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and not _locked():
			for h in hits: if str(h.id) == drag_id and str(h.kind) == "slider": _drag(h, _local(h, e.position))
			accept_event()

## A point of the screen in the space of a hit's rect: stage items live on the panned canvas, panel items in the scaled panel, folds on the screen.
func _local(h: Dictionary, p: Vector2) -> Vector2:
	if bool(h.get("screen", false)): return p
	if bool(h.get("stage", false)): return p - _off()
	return _unscr(p)

func hit_at(p: Vector2) -> Dictionary:
	for i in range(hits.size() - 1, -1, -1):
		var h: Dictionary = hits[i]
		if (h.rect as Rect2).has_point(_local(h, p)): return h
	return {}

var quiet := false              ## headless tests: no sound, toast or shell refresh (the engine still answers)
var last_msg := ""

func _act(act: String, args: Array) -> bool:
	var r: Dictionary = app.b.act(act, args)
	last_msg = str(r.get("message", ""))
	if not quiet:
		if r.get("ok", false): app.sfx("click")
		else: app.sfx("bad"); app.toast(last_msg, "bad")
		app.game_on_changed()
	return bool(r.get("ok", false))

func _process(dt: float) -> void:
	if not visible: return
	_t += dt
	var l3 := _look3()
	if l3 != _was3: _was3 = l3; layout()   # the 3D place came up (or went) after this level's first layout
	if not CbSettings.reduced_motion: queue_redraw()

# ---- the 3D place: glass chips hung on its anchors --------------------------------------------------------------------------------
const TOP := 92.0               ## below the work order pin
var _pins: Array = []           ## rects of the chips drawn this frame (a later chip steps clear of an earlier one)
var _top_y := TOP
var _was3 := false

func _right() -> float: return size.x - (app.world_cover() if app != null and app.has_method("world_cover") else 0.0)

## A glass chip hung over a place of the 3D scene (Stage3D.anchors), with a leader line down to it; off screen or behind the camera it is not drawn.
func _pin(key: String, lines: Array, cols: Array, lift := 34.0) -> void:
	var wv = app.get("grid_world")
	var l3 = wv.look3d
	var a = l3.anchors.get(key)
	if a == null: return
	_pin_at(l3.project(a), lines, cols, lift, wv)

## A point in the 3D world's screen space (what Stage3D.project returns) in this stage's own space.
func _to_local(wp: Vector2, wv = null) -> Vector2:
	if wv == null: wv = app.get("grid_world")
	return get_global_transform_with_canvas().affine_inverse() * ((wv as Control).get_global_transform_with_canvas() * wp)

func _pins_hit(r: Rect2) -> bool:
	for c in _pins: if (c as Rect2).grow(4.0).intersects(r): return true
	return false

func _pin_at(wp: Vector2, lines: Array, cols: Array, lift: float, wv = null) -> void:
	if wp.x < -9000.0: return
	if wv == null: wv = app.get("grid_world")
	var sp := _to_local(wp, wv)
	if not Rect2(Vector2.ZERO, Vector2(_right(), size.y)).grow(-4.0).has_point(sp): return
	var semi := _semi(); var fz := GridText.floor_size(self, GridTheme.fs(13)) if _look3() else GridTheme.fs(13)   # 11-28b: measured at the size drawn (the 16 px floor), or the text ran out of its chip
	var cw := 0.0
	for ln in lines: cw = maxf(cw, semi.get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, fz).x)
	var lh := float(fz) + 6.0
	var r := Rect2(Vector2(sp.x - (cw + 24.0) * 0.5, sp.y - lift * size.y / 1080.0 - (lh * lines.size() + 12.0)), Vector2(cw + 24.0, lh * lines.size() + 12.0))
	r.position.x = clampf(r.position.x, M, _right() - M - r.size.x)
	r.position.y = clampf(r.position.y, _top_y, panel.position.y - 8.0 - r.size.y)
	if _pins_hit(r):   # step clear of the chips (and glass cards) already drawn: the nearest free place to the side on the same row, below them only if none is free
		var cands: Array = []
		for c in _pins:
			cands.append((c as Rect2).end.x + 10.0); cands.append((c as Rect2).position.x - 10.0 - r.size.x)
		cands.sort_custom(func(a: float, b: float) -> bool: return absf(a - r.position.x) < absf(b - r.position.x))
		var placed := false
		for cx in cands:
			if float(cx) < M or float(cx) + r.size.x > _right() - M: continue
			var tr := Rect2(Vector2(float(cx), r.position.y), r.size)
			if not _pins_hit(tr): r = tr; placed = true; break
		if not placed:
			var low := r.position.y
			for c in _pins: if (c as Rect2).grow(4.0).intersects(r): low = maxf(low, (c as Rect2).end.y + 8.0)
			r.position.y = low
	if r.end.y > panel.position.y - 8.0: return
	if _pins_hit(r.grow(-4.0)): return   # 11-28b: no free place left (small windows): leave the chip out rather than print it over a chart (L32 at 1280x800)
	_pins.append(r)
	var foot := Vector2(clampf(sp.x, r.position.x + 8.0, r.end.x - 8.0), r.end.y)
	if sp.y > r.end.y + 4.0:
		draw_line(foot, sp, Color(GridTheme.G_TICK, 0.7), 1.0, true)
		draw_circle(sp, 3.0, GridTheme.G_TICK)
	draw_style_box(GridTheme.glass_sb(0.78, 4, 0.0), r)
	for i in lines.size():
		_text(semi, 13, Vector2(r.position.x + 12.0, r.position.y + 6.0 + lh * (i + 1) - 6.0), str(lines[i]), cols[mini(i, cols.size() - 1)])

# ---- drawing helpers --------------------------------------------------------------------------------------------------------------
func _text(font: Font, fsz: int, at: Vector2, s: String, col: Color, w := -1.0, align := 0) -> void:
	var l3 := _look3()   # the fixes below are for the 3D place; the classic stage keeps its drawing
	var f := GridText.floor_size(self, GridTheme.fs(fsz)) if l3 else GridTheme.fs(fsz); var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x   # measured at the size that is drawn (the 16 px floor)
	if l3 and w > 0.0 and tw > w and "$" in s: s = _short_money(s); tw = font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, f).x   # "$900,000" in a narrow chip ran into its neighbour: "$0.9M"
	var x := at.x
	if w > 0.0: x = at.x + (maxf(w - tw, 0.0) if l3 else (w - tw)) * (0.5 if align == 1 else 1.0 if align == 2 else 0.0)   # too wide for its box: it starts at the box's edge, never spills left
	GridText.ds(self, font, Vector2(x, at.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, f, col)

## Text wrapped to the width w (the boxes of the estate are 220 px wide; a long gloss ran out of its box at 1080p).
func _wrap(font: Font, fsz: int, at: Vector2, s: String, col: Color, w: float) -> void:
	GridText.dm(self, font, at, s, HORIZONTAL_ALIGNMENT_LEFT, w, GridTheme.fs(fsz), -1, col)

static var _money_re: RegEx
## "$1,000,000" -> "$1.0M" for every full dollar amount in a string (CbRegion.money's short form).
static func _short_money(s: String) -> String:
	if _money_re == null: _money_re = RegEx.new(); _money_re.compile("\\$[0-9]{1,3}(,[0-9]{3})+")
	var out := s
	for m in _money_re.search_all(s):
		var digits := m.get_string().replace("$", "").replace(",", "")
		out = out.replace(m.get_string(), CbRegion.money(float(digits), true))
	return out

func _money(x: float) -> String: return CbRegion.money(x, false, 0)
func _f(x: float, d: int) -> String: return String.num(x, d)
func _good(ok: bool) -> Color: return GridTheme.GOOD if ok else GridTheme.BAD
func _mono() -> Font: return GridTheme.font("mono")
func _semi() -> Font: return GridTheme.font("semi")

func _cell_sb(fill: Color, lit: bool) -> StyleBoxFlat:
	if _look3(): return GridTheme.glass_cell_sb(fill, lit)
	var s := StyleBoxFlat.new(); s.bg_color = fill; s.set_corner_radius_all(7)
	s.border_color = GridTheme.SODIUM if lit else Color(GridTheme.SODIUM_DIM, 0.28); s.set_border_width_all(2 if lit else 1)
	return s

func _sky() -> void:
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(0, size.y)]), PackedColorArray([Color("#0E1432"), Color("#0E1432"), Color("#2A3768"), Color("#2A3768")]))
	for i in 38:
		var sx := fposmod(float(i) * 197.31, size.x); var sy := fposmod(float(i) * 83.7, size.y * 0.42)
		draw_circle(Vector2(sx, sy), 1.0 + float(i % 3) * 0.4, Color(1, 1, 1, 0.25 + 0.2 * sin(_t * 1.3 + float(i))))

## A chip: label (and optional second line), lit when `on`, greyed when `off`.
func _chip(r: Rect2, label: String, sub := "", on := false, id := "", arg = "", enabled := true) -> void:
	var hv := hover == "%s/%s" % [id, str(arg)] and enabled
	var fill := Color(GridTheme.SODIUM, 0.22) if on else (Color(GridTheme.INK).lightened(0.12) if hv else Color(GridTheme.NIGHT, 0.55))
	draw_style_box(_cell_sb(fill, on or hv), r)
	var mono := _mono(); var col := GridTheme.SODIUM if on else (GridTheme.TEXT if enabled else GridTheme.DIM)
	if sub == "":
		_text(mono, 13, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + 5.0), label, col, r.size.x, 1)
	else:
		var l3 := _look3()   # 3D: two lines at the 16 px floor need 18 px between baselines (the label and its price printed over each other)
		_text(mono, 13, Vector2(r.position.x, r.position.y + r.size.y * 0.5 - (5.0 if l3 else 1.0)), label, col, r.size.x, 1)
		_text(mono, 10 if sub.length() < 10 else 9, Vector2(r.position.x, r.position.y + r.size.y * 0.5 + (13.0 if l3 else 12.0)), sub, Color(GridTheme.TEXT, 0.6), r.size.x, 1)

func _add_chip(r: Rect2, id: String, arg) -> void: hits.append({"rect": r, "kind": "chip", "id": id, "arg": arg})

## A [-] track [+] stepper cell with a caption, a value text and the fraction of the track filled.
func _stepper(r: Rect2, cap: String, vtxt: String, frac: float, id: String) -> void:
	var lock := _locked()
	draw_style_box(_cell_sb(Color(GridTheme.NIGHT, 0.55), drag_id == id), r)
	_text(_semi(), 11, r.position + Vector2(8, 15), cap, Color(GridTheme.TEXT, 0.7))
	_text(_mono(), 16, Vector2(r.position.x, r.position.y + 33.0), vtxt, GridTheme.SODIUM if not lock else GridTheme.DIM, r.size.x - 8.0, 2)
	var pt := stepper_parts(r)
	for k in ["minus", "plus"]:
		var br: Rect2 = pt[k]; draw_rect(br, Color(GridTheme.INK)); draw_rect(br, Color(GridTheme.SODIUM_DIM, 0.5), false, 1.0)
		_text(_semi(), 16, br.position + Vector2(0, 18), "−" if k == "minus" else "+", GridTheme.TEXT, br.size.x, 1)
	var tr: Rect2 = pt.track
	draw_rect(Rect2(tr.position + Vector2(0, 6), Vector2(tr.size.x, 4)), Color(GridTheme.SODIUM_DIM, 0.35))
	draw_rect(Rect2(tr.position + Vector2(0, 6), Vector2(tr.size.x * clampf(frac, 0.0, 1.0), 4)), GridTheme.SODIUM if not lock else GridTheme.DIM)
	draw_circle(tr.position + Vector2(tr.size.x * clampf(frac, 0.0, 1.0), 8), 8.0, GridTheme.SODIUM if not lock else GridTheme.DIM); draw_circle(tr.position + Vector2(tr.size.x * clampf(frac, 0.0, 1.0), 8), 3.0, GridTheme.NIGHT)

## True on a stepper's slider track (with a finger's margin).
func on_track(r: Rect2, p: Vector2) -> bool: return (stepper_parts(r).track as Rect2).grow_individual(10.0, 12.0, 10.0, 12.0).has_point(p)

func stepper_parts(r: Rect2) -> Dictionary:
	var by := r.position.y + 40.0
	return {"minus": Rect2(Vector2(r.position.x, by), Vector2(24, 24)), "plus": Rect2(Vector2(r.end.x - 24.0, by), Vector2(24, 24)), "track": Rect2(Vector2(r.position.x + 30.0, by + 4.0), Vector2(r.size.x - 60.0, 16.0))}

func _face(c: Vector2, r: float, happy: bool, a: float) -> void:
	draw_circle(c + Vector2(-r * 0.35, -r * 0.2), r * 0.12, Color(GridTheme.INK, a)); draw_circle(c + Vector2(r * 0.35, -r * 0.2), r * 0.12, Color(GridTheme.INK, a))
	var pts := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0; var bow := 1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0)
		pts.append(c + Vector2(lerpf(-r * 0.4, r * 0.4, t), r * ((0.2 + 0.22 * bow) if happy else (0.5 - 0.22 * bow))))
	draw_polyline(pts, Color(GridTheme.INK, a), maxf(1.5, r * 0.1), true)

## An arrow from a to b with a head.
func _arrow(a: Vector2, b: Vector2, col: Color, wd := 3.0) -> void:
	draw_line(a, b, col, wd, true)
	var d := (b - a); if d.length() < 3.0: return
	var u := d.normalized(); var n := Vector2(-u.y, u.x); var hl := minf(12.0, d.length() * 0.5)
	draw_colored_polygon(PackedVector2Array([b, b - u * hl + n * hl * 0.45, b - u * hl - n * hl * 0.45]), col)

func _draw() -> void:
	if not visible or q.is_empty(): return
	if panel.size.x < 1.0: layout()   # the first layout came before the chrome was built
	if _look3():   # the 3D place is the stage: charts and the panel stay, in glass
		_pins.clear(); _top_y = TOP
		if not GridTheme.charts_folded or _exam_sheet(): _draw_stage()   # 11-28b: V folds the charts away
		_draw_panel()
		return
	draw_rect(Rect2(Vector2.ZERO, size), GridTheme.NIGHT, true)   # an opaque stage: the world underneath is not this level's place
	_sky()
	if _phone():
		draw_set_transform(_pan, 0.0, Vector2.ONE); _draw_stage()
		draw_set_transform(_p0 - panel.position * _sc, 0.0, Vector2(_sc, _sc))
		if not _collapsed: _draw_panel()
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_draw_fold()
	else:
		_draw_stage()
		_draw_panel()

func _draw_fold() -> void:
	var w := panel.size.x * _sc
	if _collapsed: draw_style_box(_panel_sb(8), Rect2(_p0, Vector2(w, 26.0)))
	_text(_semi(), 12, _p0 + Vector2(10.0, 18.0), T("C4_PANEL_TITLE") if _collapsed else "", Color(GridTheme.TEXT, 0.75))
	_text(_mono(), 16, _p0 + Vector2(w - 34.0, 19.0), "▸" if _collapsed else "▾", GridTheme.SODIUM)

func _panel_sb(r: int) -> StyleBoxFlat:
	return GridTheme.glass_sb(0.86, 4, 0.0) if _look3() else GridTheme.ink_sb(0.94, r, 0.0)

func _draw_panel() -> void:
	draw_style_box(_panel_sb(10), panel)
	draw_line(panel.position + Vector2(10, 2), panel.position + Vector2(panel.size.x - 10, 2), Color(GridTheme.SODIUM_DIM, 0.35), 1.0)
	_draw_panel_body()
	_draw_price_tag(panel)

func _draw_price_tag(pn: Rect2) -> void:
	var spent := float(q.get("cost", 0.0)); var budget := float(q.get("budget", 0.0))
	if budget <= 0.0 and spent <= 0.0: return   # nothing to buy on this level (the L13 exam): no "$0" tag
	var over := budget > 0.0 and spent > budget + 0.0001
	var txt := T("C4_SPENT") % [_money(spent), _money(budget)] if budget > 0.0 else _money(spent)
	var mono := _mono(); var semi := _semi()
	var w := 176.0; var h := 44.0
	var fz16 := GridText.floor_size(self, 13)   # 1.9: the tag grows to its words at the 16 px floor (it clipped "build incl. starting kit")
	w = maxf(w, maxf(semi.get_string_size(tr("TRAY_BUDGET_CAP"), HORIZONTAL_ALIGNMENT_LEFT, -1, fz16).x + 34.0, mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fz16).x + 20.0)); h = maxf(h, fz16 * 2.0 + 16.0)
	var org := Vector2(pn.end.x - 12.0 - w, pn.end.y - 12.0 - h) if not _narrow() else Vector2(pn.end.x - 12.0 - w, pn.position.y - h - 6.0)
	var g3 := _look3()
	draw_set_transform(_scr(org + Vector2(w, h) * 0.5), 0.0 if g3 else deg_to_rad(-1.4), Vector2(_sc, _sc))
	var rect := Rect2(Vector2(-w * 0.5, -h * 0.5), Vector2(w, h))
	draw_style_box(GridTheme.glass_sb(0.8, 4, 0.0) if g3 else GridTheme.paper_sb(3, 0.0), rect)
	if not g3: draw_circle(Vector2(-w * 0.5 + 11.0, -h * 0.5 + 11.0), 3.5, GridTheme.INK)
	var fsz := GridTheme.fs(13); var tw2 := mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	while tw2 > w - 16.0 and fsz > 9: fsz -= 1; tw2 = mono.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x
	var ink := GridTheme.G_TEXT if g3 else GridTheme.PAPER_INK
	GridText.ds(self, semi, Vector2(-w * 0.5 + (12.0 if g3 else 22.0), -h * 0.5 + 15.0), tr("TRAY_BUDGET_CAP"), HORIZONTAL_ALIGNMENT_LEFT, -1, GridTheme.fs(10), Color(GridTheme.G_DIM if g3 else ink, 1.0 if g3 else 0.7))
	GridText.ds(self, mono, Vector2(-tw2 * 0.5, h * 0.5 - 8.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, (GridTheme.BAD if g3 else GridTheme.BAD.darkened(0.15)) if over else ink)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
