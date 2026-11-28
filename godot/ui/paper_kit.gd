class_name PaperKit
extends RefCounted
## Shared pieces of GRID's paper screens (work order, shift / incident report, pause card, jobs clipboard): the docket sheet built on the shell's
## `app.dialog()` (so Esc / B / Back keep working), slide-in and fold-into-the-pin animations, paper-ink labels and buttons, and a few hand-drawn
## controls (lamp with a stamp, pencil check box, tick, doodle bulb, dashed rule, histogram in print ink). Display only.

const INK := GridTheme.PAPER_INK
const RED := Color("#A8321F")        ## incident red ink
const BLUE := Color("#2E4A86")       ## ADA's pen
const AMBER := Color("#B5700F")      ## outline of a lit lamp on paper (sodium alone is too pale on cream)
const SPEAKER := {"TOBI": Color("#8A5A0A"), "NIA": Color("#2A7A52"), "ADA": Color("#4A3F8A"), "VANCE": Color("#7A4A1E"), "SYS": Color("#5A5648")}

static func T(key: String) -> String: return TranslationServer.translate(key)

## Animations run only on a real display with motion allowed; smoke and headless runs snap straight to the end state.
static func animate() -> bool:
	return DisplayServer.get_name() != "headless" and not CbSettings.reduced_motion and not OS.has_environment("CB_SMOKE")

# ---- labels and buttons --------------------------------------------------------------------------------------------------------------
static var glass := false   ## LOOK2: the incident report in the glass language (ShiftReport sets it while it builds the sheet)

## Paper inks as light inks on dark glass (alpha kept).
static func ink(col: Color) -> Color:
	if not glass: return col
	var a := col.a
	if Color(col, 1.0).is_equal_approx(RED): return Color(1.0, 0.52, 0.45, a)
	if Color(col, 1.0).is_equal_approx(BLUE): return Color(0.62, 0.78, 1.0, a)
	if Color(col, 1.0).is_equal_approx(INK): return Color(GridTheme.G_TEXT, a)
	return col

static func lbl(text: String, size := 17, kind := "sans", col: Color = INK, wrap := false) -> Label:
	var l := GridTheme.label(text, size, ink(col), GridTheme.skin_font(kind) if glass else kind)
	if wrap: l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func _btn_sb(bg: Color, edge: Color, bw := 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.border_color = edge; s.set_border_width_all(bw); s.set_corner_radius_all(6)
	s.content_margin_left = 22; s.content_margin_right = 22; s.content_margin_top = 10; s.content_margin_bottom = 10
	return s

static func _focus_sb() -> StyleBoxFlat:
	# 1.8 pad pass: an amber ring and a faint wash (the old 3 px ink ring was lost against a row's own ink border at 1280x800)
	var s := StyleBoxFlat.new(); s.bg_color = Color(AMBER, 0.12); s.border_color = AMBER; s.set_border_width_all(4); s.set_corner_radius_all(8); s.set_expand_margin_all(4)
	return s

## A button in paper style: `primary` = sodium (the one action), otherwise a ghost with an ink border.
static func btn(text: String, primary: bool, cb: Callable, size := 20) -> Button:
	var b := Button.new(); b.text = text; b.focus_mode = Control.FOCUS_ALL; b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", GridTheme.font("semi")); b.add_theme_font_size_override("font_size", GridTheme.fs(size))
	var fc: Color = GridTheme.NIGHT if primary else ink(INK)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, fc)
	if primary:
		b.add_theme_stylebox_override("normal", _btn_sb(GridTheme.SODIUM, Color("#8A5F1E")))
		b.add_theme_stylebox_override("hover", _btn_sb(GridTheme.SODIUM.lightened(0.18), Color("#8A5F1E")))
		b.add_theme_stylebox_override("pressed", _btn_sb(GridTheme.SODIUM.darkened(0.1), Color("#8A5F1E")))
	else:
		var ik := ink(INK)
		b.add_theme_stylebox_override("normal", _btn_sb(Color(ik, 0.0), Color(ik, 0.7)))
		b.add_theme_stylebox_override("hover", _btn_sb(Color(ik, 0.1), ik))
		b.add_theme_stylebox_override("pressed", _btn_sb(Color(ik, 0.18), ik))
	b.add_theme_stylebox_override("focus", _focus_sb())
	b.add_theme_stylebox_override("disabled", _btn_sb(Color(INK, 0.04), Color(INK, 0.35)))
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.6))
	b.custom_minimum_size = Vector2(0, maxf(52.0, CbLayout.tap()))
	b.pressed.connect(cb)
	return b

## Segmented chip: options = [[id, label], ...]; `on_pick(id)` runs when another one is chosen. The chosen one is unmistakable: filled sodium, a heavy ink
## border and a pencilled check at its left; the others are plain outlines.
static func chip(options: Array, selected: String, on_pick: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 6)
	for o in options:
		var id: String = str(o[0]); var on: bool = id == selected
		var b := Button.new(); b.text = str(o[1]); b.name = "Chip_" + id; b.toggle_mode = false; b.focus_mode = Control.FOCUS_ALL; b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.set_meta("selected", on)
		b.add_theme_font_override("font", GridTheme.font("semi")); b.add_theme_font_size_override("font_size", GridTheme.fs(16))
		var fc: Color = GridTheme.NIGHT if on else Color(ink(INK), 0.8)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]: b.add_theme_color_override(k, fc)
		var sb := _btn_sb(GridTheme.SODIUM if on else Color(ink(INK), 0.0), ink(INK) if on else Color(ink(INK), 0.55), 3 if on else 2); sb.set_corner_radius_all(16)
		sb.content_margin_top = 4; sb.content_margin_bottom = 4; sb.content_margin_left = 40 if on else 18; sb.content_margin_right = 18
		for k in ["normal", "pressed"]: b.add_theme_stylebox_override(k, sb)
		var hv := sb.duplicate() as StyleBoxFlat; hv.bg_color = GridTheme.SODIUM.lightened(0.15) if on else Color(ink(INK), 0.1); b.add_theme_stylebox_override("hover", hv)
		b.add_theme_stylebox_override("focus", _focus_sb())
		b.custom_minimum_size.y = maxf(38.0, CbLayout.tap() * 0.8)
		if on:
			var ck := ChipCheck.new(); ck.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE); ck.offset_left = 10; ck.offset_right = 34; b.add_child(ck)
		else: b.pressed.connect(func(): on_pick.call(id))
		hb.add_child(b)
	return hb

## True on a phone-sized safe area (landscape phone minus the notch): the paper screens switch to their compact layouts.
static func compact(app: CbApp) -> bool: return app.vs_h() < 600.0

## The dimmed backdrop of a dialog reaches the physical screen edges: the shell insets the whole UI root by the safe area, so the scrim is pushed back out
## by the inset (otherwise the world shows as a lit rectangle with dark bars around it).
static func bleed(app: CbApp, host: Control) -> void:
	if host.get_child_count() == 0 or not (host.get_child(0) is ColorRect): return
	var dim := host.get_child(0) as ColorRect; var ins: Vector4 = app.inset
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.offset_left = -ins.x; dim.offset_top = -ins.y; dim.offset_right = ins.z; dim.offset_bottom = ins.w

## A vertically scrolling column with a visible cue: when more content is hidden below, the bottom edge fades into the paper and a "more" tab with an
## arrow shows; it vanishes at the end. Returns the box (expands to the room the sheet gives it).
static func scroll_box(content: Control, fade: Color = GridTheme.PAPER) -> Control:
	if glass and fade == GridTheme.PAPER: fade = Color(GridTheme.GLASS, 1.0)   # LOOK2: the "more" cue fades into glass, not cream
	var box := CueBox.new(content, fade)
	return box

static func rule() -> Control: return DashedRule.new()

# ---- the sheet -----------------------------------------------------------------------------------------------------------------------
## A modal paper docket (dialog host named `name`, class PaperHost). Returns the dialog dictionary {host, panel, vb}; `vb` is the sheet's column.
static func sheet(app: CbApp, name: String, w: float, h: float, dim := 0.8, pad := 30.0) -> Dictionary:
	var d: Dictionary = app.dialog(name, w, h, INK, dim)
	var host: Control = d.host
	host.set_script(PaperHost); host.theme = GridTheme.theme()
	(host.get_child(0) as ColorRect).color = Color(GridTheme.NIGHT, dim)
	(host as PaperHost).app = app; bleed(app, host)
	var pn: PanelContainer = d.panel
	pn.clip_contents = false
	if glass: pn.add_theme_stylebox_override("panel", GridTheme.glass_sb(0.9, 6, pad))
	else:
		pn.add_theme_stylebox_override("panel", GridTheme.paper_sb(4, pad))
		var tape := Tape.new(); pn.add_child(tape)
	(d.vb as VBoxContainer).add_theme_constant_override("separation", 10)
	return d

## Panel slides up from below and the dim fades in.
static func slide_in(d: Dictionary, from_below := 80.0) -> void:
	if not animate(): return
	var pn: Control = d.panel; var host: Control = d.host
	var ot := pn.offset_top; var ob := pn.offset_bottom; var dim := host.get_child(0) as ColorRect; var da := dim.color.a
	pn.offset_top = ot + from_below; pn.offset_bottom = ob + from_below; pn.modulate.a = 0.0; dim.color.a = 0.0
	var tw := pn.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(pn, "offset_top", ot, 0.34); tw.tween_property(pn, "offset_bottom", ob, 0.34)
	tw.tween_property(pn, "modulate:a", 1.0, 0.24); tw.tween_property(dim, "color:a", da, 0.3)

## The panel shrinks into `target` (screen point, normally the pin), then the host is freed and `on_done` runs.
static func fold(d: Dictionary, target: Vector2, on_done := Callable()) -> void:
	var host: Control = d.host
	if not is_instance_valid(host) or host.has_meta("folding"): return
	host.set_meta("folding", true)
	_mouse_through(host)   # while it folds away (0.3 s) the sheet and its dim must not eat the player's next click
	if host.has_meta("cb_modal"): host.remove_meta("cb_modal")   # nor count as an open dialog (the game ignores world clicks behind a modal)
	if not animate():
		host.queue_free()
		if on_done.is_valid(): on_done.call()
		return
	var pn: Control = d.panel; var dim := host.get_child(0) as ColorRect
	pn.pivot_offset = target - pn.global_position
	var tw := pn.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(pn, "scale", Vector2(0.06, 0.06), 0.3); tw.tween_property(pn, "modulate:a", 0.0, 0.3); tw.tween_property(dim, "color:a", 0.0, 0.3)
	tw.chain().tween_callback(func():
		if is_instance_valid(host): host.queue_free()
		if on_done.is_valid(): on_done.call())

static func _mouse_through(n: Node) -> void:
	if n is Control: (n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children(): _mouse_through(c)

## QA screenshots: open a paper screen by name from CB_CAM (`paper=menu`, `jobs`, `workorder`, `report`, `chapter`, `look` = press Look around on the open report).
static func qa(app: CbApp, what: String) -> void:
	match what:
		"menu": app.open_menu()
		"settings": app.open_settings()
		"codex": app.show_screen("codex")
		"close":   # QA: close every open dialog (so the next QA screen is shot alone)
			app.menus.close_menu()
			for n in app.get_tree().root.find_children("*", "", true, false): if n.has_meta("cb_modal") and is_instance_valid(n): n.queue_free()
			app.show_screen(app.home)
		"jobs": Jobs.open(app)
		"workorder": WorkOrder.open(app)
		"report", "look":   # a fresh report once the world has settled (the job may already have ended and opened one while the QA ticks ran); `look` then presses Look around
			app.get_tree().create_timer(1.5).timeout.connect(func():
				if ShiftReport.is_open(): app.menus.end_look()
				app.end_seen = false; app.menus.end_card()
				if what == "look": app.get_tree().create_timer(0.3).timeout.connect(func(): ShiftReport._look(app, str(app.b.g.get("status", "")) == "won")))
		"chapter": ShiftReport.chapter_end(app, "L07")

# ---- hand-drawn controls -------------------------------------------------------------------------------------------------------------
## Strip of tape across the top edge of a sheet.
class Tape extends Control:
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := 120.0; var h := 30.0
		draw_set_transform(Vector2(size.x * 0.5, -4.0), deg_to_rad(-2.5), Vector2.ONE)
		draw_rect(Rect2(-w * 0.5 + 2, -h * 0.5 + 3, w, h), Color(0, 0, 0, 0.12))
		draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), Color(GridTheme.SODIUM, 0.55))
		for i in 7: draw_line(Vector2(-w * 0.5, -h * 0.5 + 4 + i * 4.0), Vector2(w * 0.5, -h * 0.5 + 4 + i * 4.0), Color(1, 1, 1, 0.12), 1.0)

## Scroll container with the "more" cue (see PaperKit.scroll_box). The cue is drawn by an overlay child above the scroller, so opaque content never covers it.
class CueBox extends Control:
	var sc: ScrollContainer
	var ov: Control
	var fade_col := GridTheme.PAPER
	var _more := false
	func _init(content: Control, fade: Color) -> void:
		fade_col = fade; name = "CueBox"; size_flags_vertical = Control.SIZE_EXPAND_FILL; size_flags_horizontal = Control.SIZE_EXPAND_FILL; clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_PASS
		sc = ScrollContainer.new(); sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.follow_focus = true   # a pad moving down a long list scrolls with it (1.16 hand play)
		add_child(sc); content.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(content)
		ov = Control.new(); ov.name = "Cue"; ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); ov.mouse_filter = Control.MOUSE_FILTER_IGNORE; ov.draw.connect(_paint); add_child(ov)
	## True while content is hidden below the visible part.
	func more_below() -> bool:
		var vs := sc.get_v_scroll_bar()
		return vs.max_value - vs.page > 6.0 and vs.value + vs.page < vs.max_value - 6.0
	func _process(_dt: float) -> void:
		var m := more_below()
		if m != _more:
			_more = m; ov.queue_redraw()
			sc.offset_bottom = -strip() if m else 0.0   # 1128c C10: the cue has its own strip under the list, so it never sits on a row or a chapter header
	func strip() -> float: return float(GridTheme.fs(15)) + 14.0
	func _paint() -> void:
		if not _more: return
		var sz := ov.size; var h := 26.0 + strip(); var y0 := sz.y - h
		ov.draw_rect(Rect2(Vector2(0, sz.y - strip()), Vector2(sz.x, strip())), Color(fade_col, 1.0))
		ov.draw_polygon(PackedVector2Array([Vector2(0, y0), Vector2(sz.x, y0), Vector2(sz.x, sz.y), Vector2(0, sz.y)]), PackedColorArray([Color(fade_col, 0.0), Color(fade_col, 0.0), Color(fade_col, 1.0), Color(fade_col, 1.0)]))
		var f := GridTheme.font("mono"); var fs := GridTheme.fs(15); var txt := TranslationServer.translate("UI_MORE")
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var cx := sz.x * 0.5; var by := sz.y - 8.0
		var ink_c := Color(INK if fade_col.get_luminance() > 0.5 else GridTheme.G_TEXT, 0.85)
		ov.draw_rect(Rect2(Vector2(cx - ts.x * 0.5 - 18.0, by - 4.0 - float(fs) - 2.0), Vector2(ts.x + 46.0, float(fs) + 10.0)), Color(fade_col, 1.0))   # 11-28b (B07): a solid chip, so the list under the fade does not print through the cue
		GridText.ds(ov, f, Vector2(cx - ts.x * 0.5 - 8.0, by - 4.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink_c)
		var ax := cx + ts.x * 0.5 + 6.0
		ov.draw_colored_polygon(PackedVector2Array([Vector2(ax, by - 14.0), Vector2(ax + 14.0, by - 14.0), Vector2(ax + 7.0, by - 4.0)]), ink_c)

## Pencilled check mark inside the chosen chip.
class ChipCheck extends Control:
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(8, -7)]), GridTheme.NIGHT, 3.4, true)

class DashedRule extends Control:
	var col := Color(INK, 0.45)
	func _init() -> void:
		custom_minimum_size = Vector2(0, 8); mouse_filter = Control.MOUSE_FILTER_IGNORE; size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if PaperKit.glass: col = GridTheme.HAIR
	func _draw() -> void:
		if PaperKit.glass or col == GridTheme.HAIR: draw_line(Vector2(0, 4), Vector2(size.x, 4), col, 1.0); return
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 4), Vector2(minf(x + 7.0, size.x), 4), col, 2.0); x += 12.0

## A pencil-drawn empty check box (a pass condition not yet met).
class Check extends Control:
	var done := false
	var _ink := INK   # LOOK2: captured at build time (light ink on glass)
	func _init(d := false) -> void: _ink = PaperKit.ink(INK); done = d; custom_minimum_size = Vector2(30, 30); mouse_filter = Control.MOUSE_FILTER_IGNORE; size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	func _draw() -> void:
		var c := Color(_ink, 0.85)
		var pts := PackedVector2Array([Vector2(5, 6), Vector2(25, 5), Vector2(26, 25), Vector2(4, 26), Vector2(5, 5)])
		draw_polyline(pts, c, 2.4, true)
		if done: draw_polyline(PackedVector2Array([Vector2(8, 16), Vector2(14, 22), Vector2(29, 2)]), PaperKit.BLUE, 3.2, true)

## Nia's pencil tick (Cute mode): a little graphite check with a pencil stub.
class Tick extends Control:
	func _init() -> void: custom_minimum_size = Vector2(46, 30); mouse_filter = Control.MOUSE_FILTER_IGNORE; size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	func _draw() -> void:
		var g := Color("#55525F")
		draw_polyline(PackedVector2Array([Vector2(3, 15), Vector2(10, 23), Vector2(24, 4)]), g, 3.0, true)
		draw_line(Vector2(30, 24), Vector2(44, 10), Color("#D9A441"), 6.0, true)
		draw_line(Vector2(28, 26), Vector2(32, 22), Color("#E8B7A0"), 6.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(28, 26), Vector2(26, 29), Vector2(31, 27)]), g)

## Doodle of a smiling bulb in the corner of a docket (Cute mode).
class Doodle extends Control:
	func _init() -> void: custom_minimum_size = Vector2(112, 112); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var g := Color(INK, 0.75); var c := Vector2(56, 48); var r := 28.0
		draw_arc(c, r, deg_to_rad(-60), deg_to_rad(250), 36, g, 2.6, true)
		draw_polyline(PackedVector2Array([c + Vector2(-16, 22), c + Vector2(-12, 34), c + Vector2(12, 34), c + Vector2(16, 22)]), g, 2.6, true)
		draw_line(c + Vector2(-11, 41), c + Vector2(11, 41), g, 2.6, true); draw_line(c + Vector2(-7, 47), c + Vector2(7, 47), g, 2.6, true)
		draw_circle(c + Vector2(-9, -4), 3.0, g); draw_circle(c + Vector2(9, -4), 3.0, g)
		draw_arc(c + Vector2(0, 4), 10.0, deg_to_rad(20), deg_to_rad(160), 12, g, 2.4, true)
		for i in 7:
			var a := deg_to_rad(-150.0 + i * 50.0); var d := Vector2(cos(a), sin(a))
			draw_line(c + d * (r + 8.0), c + d * (r + 17.0), Color(PaperKit.AMBER, 0.9), 2.6, true)

## A lamp icon: unlit outline or lit sodium, with an optional inked stamp ring (`stamp` 0..1 animates the thump).
class Lamp extends Control:
	var lit := false
	var stamp := 0.0
	var ring := PaperKit.RED
	var _ink := INK
	func _init(px := 96.0, is_lit := false) -> void: _ink = PaperKit.ink(INK); lit = is_lit; custom_minimum_size = Vector2(px, px * 1.1); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_stamp(v: float) -> void: stamp = v; queue_redraw()
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.42); var r := size.x * 0.27
		var ink := Color(_ink, 0.85)
		if lit:
			for i in 5: draw_circle(c, r * (2.0 - 0.25 * i), Color(GridTheme.SODIUM, 0.07 + 0.02 * i))
			for i in 8:
				var a := TAU * i / 8.0 + 0.2; var d := Vector2(cos(a), sin(a)); draw_line(c + d * r * 1.3, c + d * r * 1.75, Color(PaperKit.AMBER, 0.9), maxf(2.0, r * 0.1), true)
		draw_circle(c, r, GridTheme.SODIUM if lit else Color(_ink, 0.07))
		draw_arc(c, r, 0.0, TAU, 40, PaperKit.AMBER if lit else ink, maxf(2.0, r * 0.1), true)
		var nk := PackedVector2Array([c + Vector2(-r * 0.55, r * 0.8), c + Vector2(r * 0.55, r * 0.8), c + Vector2(r * 0.42, r * 1.35), c + Vector2(-r * 0.42, r * 1.35)])
		draw_colored_polygon(nk, Color(_ink, 0.55)); draw_polyline(nk + PackedVector2Array([nk[0]]), ink, 2.0, true)
		for k in 2: draw_line(c + Vector2(-r * 0.4, r * (1.5 + 0.2 * k)), c + Vector2(r * 0.4, r * (1.5 + 0.2 * k)), ink, 3.0, true)
		var fil := PackedVector2Array([c + Vector2(-r * 0.3, r * 0.7), c + Vector2(-r * 0.3, r * 0.1), c + Vector2(-r * 0.1, -r * 0.2), c + Vector2(r * 0.1, r * 0.1), c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.3, r * 0.7)])
		draw_polyline(fil, Color("#9A4A08") if lit else Color(_ink, 0.55), 2.2, true)
		if stamp > 0.0 and lit:   # ink ring pressed on the paper: starts big and faint, thumps down to size
			var k := ease(clampf(stamp, 0.0, 1.0), 0.35); var sc := lerpf(1.9, 1.0, k); var al := clampf(stamp * 2.0, 0.0, 1.0) * 0.9
			draw_set_transform(c, deg_to_rad(-9.0), Vector2(sc, sc))
			draw_arc(Vector2.ZERO, r * 1.95, 0.0, TAU, 56, Color(ring, al), 5.0, true)
			draw_arc(Vector2.ZERO, r * 1.72, 0.0, TAU, 56, Color(ring, al * 0.8), 2.0, true)

## The histogram of the result card in print ink (same data as HistView, drawn with the paper palette). Never shown on a failure.
class PaperHist extends HistView:
	var _ink := PaperKit.ink(PaperKit.INK)   # captured when built: light on glass (1.17, Sigrid: the axis labels were dark on near-black)
	func _x2(v: float, lo: float, hi: float, x0: float, w: float) -> float: return x0 + w * clampf((v - lo) / maxf(hi - lo, 1e-9), 0.0, 1.0)
	func _draw() -> void:
		var bins: Array = r.get("bins", [])
		if bins.is_empty(): return
		var f := GridTheme.font("mono"); var fs := GridTheme.fs(13)
		var x0 := 6.0; var w := size.x - 12.0; var base := size.y - 22.0; var top := 8.0
		var lo := float(bins[0].from); var hi := float(bins[bins.size() - 1].to)
		var mx := 1
		for b in bins: mx = maxi(mx, int(b.count))
		var bw := w / bins.size()
		for i in bins.size():
			var h := (base - top) * float(int(bins[i].count)) / mx
			draw_rect(Rect2(x0 + i * bw + 1.0, base - h, bw - 2.0, h), Color(GridTheme.COPPER, 0.8))
			draw_rect(Rect2(x0 + i * bw + 1.0, base - h, bw - 2.0, h), Color(_ink, 0.5), false, 1.0)
		draw_line(Vector2(x0, base), Vector2(x0 + w, base), Color(_ink, 0.8), 2.0)
		GridText.ds(self, f, Vector2(x0, size.y - 5.0), CbKit.num(lo, 0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(_ink, 0.9))
		GridText.ds(self, f, Vector2(x0 + w - 70.0, size.y - 5.0), CbKit.num(hi, 0), HORIZONTAL_ALIGNMENT_RIGHT, 70.0, fs, Color(_ink, 0.9))
		if r.get("mine") != null:
			var mx_ := _x2(float(r.mine), lo, hi, x0, w)
			draw_line(Vector2(mx_, top), Vector2(mx_, base), PaperKit.RED, 3.0)
			GridText.ds(self, f, Vector2(clampf(mx_ + 5.0, 0.0, size.x - 44.0), top + 10.0), tr("HIST_YOU"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PaperKit.RED)
		if str(r.get("histogram", "")) == "capex":
			for pair in [[r.get("starA"), "HIST_STAR_A"], [r.get("starB"), "HIST_STAR_B"]]:
				if pair[0] == null or float(pair[0]) < lo or float(pair[0]) > hi: continue
				var sx := _x2(float(pair[0]), lo, hi, x0, w)
				draw_line(Vector2(sx, top + 14.0), Vector2(sx, base), PaperKit.BLUE, 2.0)
				GridText.ds(self, f, Vector2(sx + 3.0, top + 24.0), tr(pair[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, PaperKit.BLUE)
