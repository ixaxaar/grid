class_name RadioLog
extends PanelContainer
## The radio (UI.md 2): bottom-left, ink, Plex Mono, three visible lines with the newest at the bottom, older ones fade. Replaces toasts and the
## coach card. `say(speaker, text, kind)` adds a line stamped with the engine clock; the current coach step carries a sodium tick and a "why?"
## link that makes ADA explain. Click the panel for the full log (a modal dialog).

signal why_said(step_id: String)
const SPEAKERS := {"TOBI": GridTheme.SODIUM, "ADA": GridTheme.PAPER, "VANCE": GridTheme.SODIUM_DIM, "NIA": GridTheme.GOOD, "SYS": GridTheme.DIM}
var app: CbApp
var lines: Array = []        ## {time, speaker, text, kind, step, why}
var _box: VBoxContainer
var _current := ""           ## step id of the coach line that carries the tick
var last_clock := "--:--"
var width := 560.0
var visible_lines := 4      ## rows kept on the panel (phone: 1); every row wraps in full, the panel grows, never an ellipsis
var max_h := 320.0          ## the panel never grows past this (about 30 % of the screen); then the oldest rows drop off
var full_opened := 0        ## times the full log was opened (tests)
const FADE := [1.0, 0.66, 0.44, 0.3, 0.22, 0.18]

func _init() -> void:
	TrayStrings.load_strings()
	mouse_filter = Control.MOUSE_FILTER_STOP
	restyle()
	_box = VBoxContainer.new(); _box.add_theme_constant_override("separation", 4); _box.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_box)
	visible = false

## The panel's skin follows GridTheme.look2 (the chrome calls this when the flag flips).
func restyle() -> void: add_theme_stylebox_override("panel", GridTheme.ink_sb(0.92, 8, 12.0))

func clock_text() -> String:
	if app != null and app.started and app.b != null:
		var c = app.b.q("clock")
		var lv := str(app.b.g.get("level", ""))
		if Instruments.STUDY_JOBS.has(lv): var sm := int(Stage8.sky_minute(lv.to_lower())); last_clock = "%02d:%02d" % [sm / 60, sm % 60]   # 1128c C04: the studies' radio reads the scene's hour, like the dial
		elif c is Dictionary and not c.is_empty():
			var pm := WorldModel.preview_minute(lv, int(c.get("tick", 1 << 30)), app.b.g.get("levelStart"))   # the 3D view previews the peak hour before Run: the radio reads it too
			if pm >= 0.0: last_clock = "%02d:%02d" % [int(pm) / 60, int(pm) % 60]
			else: last_clock = "%02d:%02d" % [int(c.hour), int(c.minute)]
	return last_clock

func clear() -> void: lines.clear(); _current = ""; _rebuild()

## kind: coach | why | story | sys | warn. `step` (coach lines) is the engine step id; `why` the text ADA says for it.
func say(speaker: String, text: String, kind := "sys", step := "", why := "") -> void:
	if text == "": return
	if not lines.is_empty() and lines.back().text == text and lines.back().speaker == speaker: return   # an identical repeat adds nothing
	lines.append({"time": clock_text(), "speaker": speaker, "text": text, "kind": kind, "step": step, "why": why})
	if kind == "coach" and step != "": _current = step
	while lines.size() > 200: lines.pop_front()
	visible = true; _rebuild()
	if app != null: app.sfx("radio")   # the little radio blip for every new line

func set_current(step_id: String) -> void: _current = step_id; _rebuild()

func _prefix(l: Dictionary) -> String: return "%s  %-5s ›" % [l.time, l.speaker]

func _color(l: Dictionary) -> Color:
	if l.kind == "warn": return GridTheme.WARN
	return SPEAKERS.get(l.speaker, GridTheme.TEXT)

## One display row; `full` rows (log dialog) never truncate.
func make_row(l: Dictionary, alpha := 1.0, full := false) -> Control:
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); row.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.modulate.a = alpha
	var live: bool = l.kind == "coach" and l.step != "" and l.step == _current
	var tick := ColorRect.new(); tick.custom_minimum_size = Vector2(3, 0); tick.color = GridTheme.SODIUM if live else Color(0, 0, 0, 0); tick.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(tick)
	var sz := 15
	var pre := GridTheme.label(_prefix(l), sz, _color(l), "mono"); pre.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var stack := narrow() and not full   # a narrow panel (small window): time and speaker above the line, or the text column shrinks to a word per row
	var col: Container = row
	if stack:
		col = VBoxContainer.new(); col.add_theme_constant_override("separation", 0); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; col.mouse_filter = Control.MOUSE_FILTER_IGNORE; row.add_child(col)
	col.add_child(pre)
	var tx := GridTheme.label(str(l.text), sz, GridTheme.WARN if l.kind == "warn" else GridTheme.TEXT, "mono")
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tx.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING   # never "…": a line wraps in full
	col.add_child(tx)
	if live and str(l.why) != "" and not l.get("why_said", false) and not full:
		var b := Button.new(); b.text = TranslationServer.translate("RADIO_WHY"); b.flat = true; b.focus_mode = CbKit.focus_mode(); b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		b.add_theme_color_override("font_color", GridTheme.SODIUM); b.add_theme_font_size_override("font_size", GridTheme.fs(14)); b.name = "Why"
		b.pressed.connect(func(): ask_why(l)); row.add_child(b)
	return row

## ADA explains the why of a coach line (once).
func ask_why(l: Dictionary) -> void:
	l["why_said"] = true
	say("ADA", str(l.why), "why", str(l.step)); why_said.emit(str(l.step)); _rebuild()

func narrow() -> bool: return width < 440.0

## Estimated height of one row at the current width (wrapped in full), so the panel can be capped without waiting for a layout pass.
func _row_h(l: Dictionary) -> float:
	var f := GridTheme.font("mono"); var sz := GridTheme.fs(15)
	var pw := 0.0 if narrow() else f.get_string_size(_prefix(l), HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	var tw := maxf(80.0, width - 24.0 - 3.0 - 16.0 - pw - (46.0 if str(l.get("why", "")) != "" and not l.get("why_said", false) else 0.0))
	var h := f.get_multiline_string_size(str(l.text), HORIZONTAL_ALIGNMENT_LEFT, tw, sz, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	return maxf(h, f.get_height(sz)) + 4.0 + (f.get_height(sz) if narrow() else 0.0)

func _rebuild() -> void:
	if _box == null: return
	for c in _box.get_children(): _box.remove_child(c); c.queue_free()
	var n := lines.size(); var first := maxi(0, n - visible_lines)
	var foot := 24.0 + 12.0 * 2.0 + 4.0
	while n - first > 1 and foot + _rows_h(first, n) > max_h: first += 1   # over the cap: the oldest row fades out
	for i in range(first, n):
		var age := n - 1 - i
		_box.add_child(make_row(lines[i], FADE[mini(age, FADE.size() - 1)]))
	_box.add_child(_log_link())
	custom_minimum_size.x = width
	size = Vector2(width, 0)   # height follows content
	visible = not lines.is_empty()
	call_deferred("_settle")

## The panel's height follows its content: a layout pass with narrow labels can leave it too tall, so let it shrink back every time.
func _settle() -> void:
	if is_inside_tree() and visible: reset_size()

func _process(_dt: float) -> void:
	if visible and absf(size.y - get_combined_minimum_size().y) > 0.5: reset_size()

func _rows_h(first: int, n: int) -> float:
	var h := 0.0
	for i in range(first, n): h += _row_h(lines[i]) + 4.0
	return h

## The small visible way to the full log (the whole panel opens it too).
func _log_link() -> Control:
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_END; hb.mouse_filter = Control.MOUSE_FILTER_IGNORE; hb.name = "LogRow"
	var b := Button.new(); b.name = "Log"; b.text = TranslationServer.translate("RADIO_LOG_LINK"); b.flat = true; b.focus_mode = CbKit.focus_mode()
	b.add_theme_color_override("font_color", GridTheme.SODIUM_DIM); b.add_theme_color_override("font_hover_color", GridTheme.SODIUM); b.add_theme_font_size_override("font_size", GridTheme.fs(13))
	b.custom_minimum_size = Vector2(0, 24); b.pressed.connect(open_full); hb.add_child(b)
	return hb

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: open_full(); accept_event()

## Full log, scrollable, newest at the bottom. Esc closes it (shell modal discipline).
func open_full() -> void:
	full_opened += 1
	if app == null or app.modal() != null: return
	var d: Dictionary = app.dialog("radiolog", minf(900.0, app.vw() - 40.0), minf(640.0, app.vs_h() - 40.0), GridTheme.SODIUM_DIM, 0.55)
	d.host.set_script(GridDialogHost); d.host.theme = GridTheme.theme()
	(d.panel as PanelContainer).add_theme_stylebox_override("panel", GridTheme.ink_sb(0.98, 10, 22.0))
	var vb: VBoxContainer = d.vb
	var hb := HBoxContainer.new(); vb.add_child(hb)
	var t := GridTheme.label(TranslationServer.translate("RADIO_LOG_TITLE"), 34, GridTheme.SODIUM, "title"); t.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(t)
	var x := Button.new(); x.text = TranslationServer.translate("RADIO_CLOSE"); x.focus_mode = Control.FOCUS_ALL; x.pressed.connect(func(): d.host.queue_free()); hb.add_child(x)
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; vb.add_child(sc)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 6); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(col)
	if lines.is_empty(): col.add_child(GridTheme.label(TranslationServer.translate("RADIO_EMPTY"), 15, GridTheme.DIM, "mono"))
	for l in lines: col.add_child(make_row(l, 1.0, true))
	sc.set_deferred("scroll_vertical", 100000)
	x.call_deferred("grab_focus")
