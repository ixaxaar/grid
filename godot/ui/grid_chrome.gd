class_name GridChrome
extends Control
## GRID's own in-level interface (cfg.chrome = "custom"): the instrument cluster, the radio, the breaker and the work-order pin, laid out for
## desktop / handheld / phone. Built by main.gd's game_build_chrome. Extension points for the next tasks: `tray_rect()` (bottom-centre slot the kit
## tray will take: radio and breaker keep clear of it), `add_slot(node)` (extra chrome children laid out by the owner), and the `pin_pressed` signal
## (work-order card). Display only: every number comes from engine queries.

signal pin_pressed
const M := 14.0
var app: CbApp
var instruments: Instruments
var radio: RadioLog
var breaker: Breaker
var pin: PanelContainer
var _pin_title: Label
var _pin_sub: Label
var menu_btn: Button
var tray: KitTray                ## the kit tray (bench levels): hut, reels, price tag
var rtray: RouteTray             ## the route tray (chapter 2 levels with a terrain): survey, supports, conductors, transformers
var gtray: GridTray              ## the grid tray (grid levels without a terrain: chapters 3-7): placeable parts, knobs, operate tags
var tags: TagView                ## in-world paper tags
var ch5: Ch5Panel               ## chapter 5's control card for L14-L18
var chf: ChfPanel                ## the finale's card (day, island lamp, ticker) on L28
var ch6: Ch6Panel               ## chapter 6's control-room card for L19-L22
var ch8: Ch8Host                 ## chapter 8's stages for L31-L36 (feeder, outages, fuse saving, firm capacity, sun, exam); hidden on every other level
var ch7: Ch7Host                 ## chapter 7's stages for L23-L27 (board, feeder, swing, merit order, exam); hidden on every other level
var ch4: Ch4Host                 ## chapter 4's stages for L10-L13 (street, estate, hydro, exam); hidden on every other level
var ch3: Ch3Panel                ## chapter 3's instrument card (phasor, spectrum, bank current, series capacitor and fault); drawn only on L07-L09
var ch2: Ch2Bench                ## chapter 2's stage and panel for L04 (alternator) and L06 (town line); hidden on every other level
var _route_item_ms := -1000      ## when the world last reported a pressed support / span (its tap must not close the tag it opened)
var _level := ""
var _coach_id := "<unset>"
var _on := false
var space_steps := OS.has_environment("CB_SMOKE")   ## core's shared smoke expects Space = one tick; the game itself toggles run

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE; name = "GridChrome"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	GridTheme.apply(self)

func build() -> void:
	ch4 = Ch4Host.new(); ch4.app = app; ch4.build(); add_child(ch4)
	ch7 = Ch7Host.new(); ch7.app = app; ch7.build(); add_child(ch7)
	ch8 = Ch8Host.new(); ch8.app = app; ch8.build(); add_child(ch8)
	ch2 = Ch2Bench.new(); ch2.app = app; add_child(ch2)   # first child: an opaque stage under the instruments, the radio and the breaker
	instruments = Instruments.new(); instruments.app = app; add_child(instruments)
	ch3 = Ch3Panel.new(); ch3.app = app; add_child(ch3)
	ch5 = Ch5Panel.new(); ch5.app = app; add_child(ch5)
	ch6 = Ch6Panel.new(); ch6.app = app; add_child(ch6)
	chf = ChfPanel.new(); chf.app = app; add_child(chf)
	instruments.codex_requested.connect(_codex)
	radio = RadioLog.new(); radio.app = app; add_child(radio)
	breaker = Breaker.new(); breaker.app = app; add_child(breaker)
	pin = PanelContainer.new(); pin.name = "Pin"; pin.mouse_filter = Control.MOUSE_FILTER_STOP; pin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 0); vb.mouse_filter = Control.MOUSE_FILTER_IGNORE; pin.add_child(vb)
	_pin_title = GridTheme.label("", 24, GridTheme.PAPER_INK, "title"); vb.add_child(_pin_title)
	_pin_sub = GridTheme.label("", 16, Color(GridTheme.PAPER_INK, 0.8), "sans"); vb.add_child(_pin_sub)
	_style_pin()
	pin.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT: pin_pressed.emit(); pin.accept_event())
	add_child(pin)
	fold_btn = Button.new(); fold_btn.name = "FoldCharts"; fold_btn.focus_mode = Control.FOCUS_NONE; fold_btn.visible = false   # 11-28b audit: fold every chart away so the place fills the screen
	fold_btn.add_theme_font_size_override("font_size", 16); fold_btn.pressed.connect(toggle_charts); add_child(fold_btn)
	_build_tools()
	menu_btn = Button.new(); menu_btn.name = "Menu"; menu_btn.text = "☰"; menu_btn.flat = true; menu_btn.focus_mode = CbKit.focus_mode()
	menu_btn.tooltip_text = TranslationServer.translate("MENU_TIP"); menu_btn.add_theme_font_size_override("font_size", GridTheme.fs(22))
	menu_btn.pressed.connect(func(): app.open_menu()); add_child(menu_btn)
	set_chrome_visible(false)

## LOOK2 (glass HUD over the 3D landscape): on while the 3D view shows. Read-only on the world; when it flips, restyle what holds a style and redraw the rest.
func _look2_wanted() -> bool:
	var w = app.get("grid_world") if app != null else null
	return w != null and w.look3d != null and w.look3d.visible

func sync_look2() -> void:
	var on := _look2_wanted()
	if on == GridTheme.look2: return
	GridTheme.look2 = on
	_style_pin(); radio.restyle()
	var redraw: Array = [breaker, tray, rtray, gtray, tags]
	if instruments != null: redraw.append_array([instruments, instruments.clock, instruments.volt, instruments.dial, instruments.clear, instruments.vil, instruments.bat])
	for n in redraw: if n != null: (n as Control).queue_redraw()

func _style_pin() -> void:
	pin.add_theme_stylebox_override("panel", GridTheme.chit_sb(3, 12.0))
	_pin_title.label_settings = GridTheme.settings(20 if GridTheme.look2 else 24, GridTheme.chit_ink(), GridTheme.skin_font("title"))
	_pin_sub.label_settings = GridTheme.settings(16, GridTheme.G_DIM if GridTheme.look2 else Color(GridTheme.PAPER_INK, 0.8), "sans")

## Kit tray + tags: wired to the bridge, the world and the radio. The relay node (added after the core pad) hears pad / Esc first.
func _build_tools() -> void:
	var world: WorldView = app.get("grid_world")
	tray = KitTray.new(); tray.b = app.b; tray.world = world; tray.radio = radio; tray.instruments = instruments
	tray.sfx = func(cue: String): app.sfx(cue)
	tray.slot = tray_rect; tray.locked = _night_locked; add_child(tray)
	rtray = RouteTray.new(); rtray.b = app.b; rtray.world = world; rtray.radio = radio; rtray.instruments = instruments
	rtray.sfx = func(cue: String): app.sfx(cue)
	rtray.slot = tray_rect; rtray.locked = _night_locked; add_child(rtray)
	rtray.mode_changed.connect(_pad_legend)
	gtray = GridTray.new(); gtray.b = app.b; gtray.world = world; gtray.radio = radio; gtray.instruments = instruments
	gtray.sfx = func(cue: String): app.sfx(cue)
	gtray.slot = tray_rect; gtray.locked = _night_locked; add_child(gtray)
	tags = TagView.new(); tags.b = app.b; tags.world = world; tags.instruments = instruments; tags.slot = tray_rect; add_child(tags)
	tray.tags = tags; rtray.tags = tags; gtray.tags = tags
	if world != null:
		world.tapped.connect(on_world_tap); world.long_pressed.connect(on_world_long); world.hovered.connect(func(p): tray.on_hover(p); rtray.on_hover(p); gtray.on_hover(p))
		if world.has_signal("route_item_pressed"): world.connect("route_item_pressed", _on_route_item)
		if world.has_signal("ground_pressed"): world.connect("ground_pressed", func(m, button): rtray.on_ground_pressed(m, int(button)))
	var relay := KitTray.Relay.new(); relay.chrome = self; relay.name = "TrayRelay"
	app.add_child.call_deferred(relay)

## The cable cannot change while the night runs or once the level is over.
func _night_locked() -> bool:
	return app.speed > 0 or str(app.b.g.get("status", "playing")) != "playing"

## A support or span of a surveyed line was pressed in the world (C1): its paper tag. Not while a survey or a transformer is being placed.
func _on_route_item(k: String, branch_id: String, index: int) -> void:
	if not _on or rtray == null or not rtray.visible or rtray.mode != "" or app.modal() != null: return
	_route_item_ms = Time.get_ticks_msec()
	if k == "support" or k == "span": tags.open(k, TagView.route_id(branch_id, index))

## The tray that is up: the route tray on chapter 2 levels, else the kit tray.
func _tray():
	if gtray != null and gtray.visible: return gtray
	return rtray if rtray != null and rtray.visible else tray

## Tap on the world: the tray first (a pick in progress), then the tags.
func on_world_tap(p: Vector2) -> void:
	var wv = app.get("grid_world")
	var bk: String = wv.breaker_at(p) if wv != null and wv.has_method("breaker_at") else ""
	if bk != "" and app.modal() == null and str(app.b.g.get("status", "playing")) == "playing":   # P0: the glowing breaker closes the line
		var r: Dictionary = app.b.act("switchBranch", [bk, true])
		app.sfx("breaker_close" if r.get("ok", false) else "bad"); app.toast(str(r.get("message", "")), "good" if r.get("ok", false) else "bad")
		app.game_on_changed(); return
	if not _on or tray == null: return
	if rtray != null and rtray.visible:
		if rtray.on_tap(p): return
		if Time.get_ticks_msec() - _route_item_ms > 300: tags.close()   # a tap on bare ground puts the tag away (a pressed support / span has just opened one)
		return
	if gtray != null and gtray.visible:   # grid levels without a terrain: a pick in progress, else the operate tag of a placed element
		gtray.on_tap(p); return
	if tray.visible and tray.on_tap(p): return
	if tray.visible or tags.is_open(): tags.on_tap(p)

func on_world_long(p: Vector2) -> void:
	if rtray != null and rtray.visible: rtray.on_long(p); return
	if gtray != null and gtray.visible: gtray.on_long(p); return
	if _on and tray != null and tags.on_long_press(p): tray.cancel()

## Pad buttons and Esc, before the shell: tray first, then the open tag. True when used.
func handle_input(e: InputEvent) -> bool:
	if not _on or tray == null or app.modal() != null: return false
	var tr = _tray()
	if e is InputEventKey:
		if e.pressed and not e.echo and e.keycode == KEY_ESCAPE: return tr.cancel_key() or tags.close()
		if e.pressed and not e.echo and e.keycode == KEY_BACKSPACE and (tr == rtray or tr == gtray): return tr.remove_last()
		if e.pressed and not e.echo and e.keycode == KEY_X and tags.is_open(): return tags.close()
		return false
	if e is InputEventJoypadButton and e.pressed and CbPad.enabled:
		var jb := e as InputEventJoypadButton
		if jb.button_index == JOY_BUTTON_B:   # B: undo the pick, else step out of the tray, else close the tag, else leave it to the shell
			if tr.mode != "" or tr.engaged: return tr.pad_button(jb.button_index)
			return tags.close() or (tr == gtray and gtray.cancel_key())
		if jb.button_index == JOY_BUTTON_X and not tags.is_open():   # X: the breaker (X also closes an open tag, as on the keyboard)
			breaker.toggle(); return true
		if jb.button_index == JOY_BUTTON_X: return tags.close()
		if jb.button_index == JOY_BUTTON_BACK:   # 1.18 (Dagny): Back cycles 1x, 2x, 4x from anywhere; the D-pad only reached the knob with focus on the breaker
			breaker.cycle_rate(); return true
		return tr.pad_button(jb.button_index)
	return false

## 1.8 pad: A on a focused, editable number box opens the on-screen number pad (ui/grid_numpad.gd); a pad cannot type.
func _input(e: InputEvent) -> void:
	if not (e is InputEventJoypadButton) or not e.pressed or not CbKit.pad_mode: return
	if (e as InputEventJoypadButton).button_index != JOY_BUTTON_A: return
	var f := get_viewport().gui_get_focus_owner()
	if not (f is LineEdit) or not (f as LineEdit).editable or app.root.get_node_or_null("Numpad") != null: return
	GridNumpad.open_for(f as LineEdit, app.root); get_viewport().set_input_as_handled()

## QA screenshots (CB_CAM "ui=..."): hut | reel/2.5 | hover/2.5 | peg/2 | run/0 | tag/cable/main | tag/hamlet/h1
func qa_ui(spec: String) -> void:
	if spec == "fold": toggle_charts(); return
	if tray == null: return
	var f := spec.split("/")
	match f[0]:
		"hut": tray.activate(tray.item_index("hut"))
		"reel": tray.activate(tray.item_index("reel", float(f[1])))
		"hover": tray.hover = tray.item_index("reel", float(f[1])); tray._after_hover()
		"peg", "run": tray.set_target_hi(int(f[1]))
		"tag": tags.open(f[1], f[2])
		"gt":   # grid tray: gt/pick/<n> (arm cell n), gt/place/<bus> (arm cell 0 and pick a bus), gt/op/<kind>/<id> (operate tag), gt/knob/<id>/<steps>
			match f[1]:
				"pick": gtray.activate(int(f[2]))
				"place": gtray.activate(0); gtray.press_target(f[2])
				"op": gtray.open_op(f[2], f[3])
				"knob": gtray.step_knob(f[2], int(f[3]))
		"padx":
			var jb := InputEventJoypadButton.new(); jb.button_index = JOY_BUTTON_X; jb.pressed = true; handle_input(jb)
		"pad": if app.pad != null: app.pad.set_active(true)
		"focus": tray.engaged = true; tray.focus = int(f[1]); tray._update_preview(); tray.queue_redraw()
		"say": for ln in f.slice(1): radio.say("TOBI", ln.replace("_", " "), "coach", "qa%d" % radio.lines.size(), "Because copper resists.")
		"why": for l in radio.lines: if l.kind == "coach" and l.step != "" and str(l.get("why", "")) != "": radio.ask_why(l); break

## The pin of a passed job: "lit" only when every home was served; P0 passes in the dark by design (1.19: "WO-P0 · lit" over a dark city).
static func done_pin_key(g: Dictionary) -> String:
	return "PIN_DONE_DARK" if float((g.get("metrics", {}) as Dictionary).get("ensMWh", 0.0)) > 0.0 else "PIN_DONE"

func tray_active() -> bool: return (ch8 != null and ch8.visible) or (ch7 != null and ch7.visible) or (ch4 != null and ch4.visible) or (ch2 != null and ch2.visible) or (tray != null and tray.visible) or (rtray != null and rtray.visible) or (gtray != null and gtray.visible)

func set_chrome_visible(v: bool) -> void:
	_on = v
	visible = v
	if v: refresh()

func _codex(id: String) -> void:
	for c in app.b.concepts():   # only open a Codex page that exists
		if (c is Dictionary and str(c.get("id", "")) == id) or str(c) == id: app.learn(id); return

## Engine state changed: update everything.
var fold_btn: Button = null
## True on a job whose 3D place has charts or a text card over it (chapters 4 to 8).
func _has_charts() -> bool:
	for c in [ch4, ch5, ch6, ch7, ch8]: if c != null and c.visible: return true
	return false

## Fold or unfold every chart and text card (V, or the chip under the job title).
func toggle_charts() -> void:
	GridTheme.charts_folded = not GridTheme.charts_folded
	for c in [ch4, ch5, ch6, ch7, ch8]:
		if c == null: continue
		if c.has_method("layout"): c.layout()
		c.queue_redraw()
		for k in c.get_children(): if k is CanvasItem: (k as CanvasItem).queue_redraw()
	if ch5 != null: ch5.refresh()
	if ch6 != null and ch6.has_method("_apply_collapse"): ch6._apply_collapse()
	layout()

func refresh() -> void:
	if app == null or not app.started or instruments == null: return
	sync_look2()
	var li = app.b.q("levelInfo"); var act: bool = li is Dictionary and li.get("active", false)
	var id: String = str(li.id) if act else ""
	if id != _level:
		_level = id; radio.clear(); _coach_id = "<unset>"
		# 1128c (manager, art review): chapters 4, 7 and 8 open with the charts folded so the place fills the screen; V or the chip
		# shows them. Other chapters open unfolded. Headless flow tests keep them open (they audit the chart layout).
		var fold_ch := Jobs.chapter_of(id) in ["4", "7", "8"] and GridTheme.look2 and DisplayServer.get_name() != "headless" and not OS.has_environment("CB_CHARTS_OPEN")
		if fold_ch != GridTheme.charts_folded and id != "": toggle_charts()
	if ch4 != null: ch4.refresh()
	if ch7 != null: ch7.refresh()
	if ch8 != null: ch8.refresh()
	if ch2 != null: ch2.refresh()
	if ch3 != null: ch3.refresh()
	if ch5 != null: ch5.refresh()
	if ch6 != null: ch6.refresh()
	if chf != null: chf.refresh()
	instruments.refresh(); breaker.sync()
	breaker.visible = not ShiftReport.is_open()   # 1128c (manager): the lever sat over the foot of the report; the report has its own Retry
	if tray != null: tray.refresh(); rtray.refresh(); gtray.refresh(); tags.refresh()
	_poll_coach(act)
	_home_drawer()
	_update_pin(li if act else {})
	layout()

func _poll_coach(act: bool) -> void:
	if not act or CbSettings.tutorial == "off": return
	var c = app.b.q("coach")
	if not (c is Dictionary) or not c.get("active", false): return
	if c.get("done", false):
		if _coach_id != "": radio.set_current(""); _coach_id = ""
		return
	if str(c.id) != _coach_id: _coach_id = str(c.id); radio.say("TOBI", str(c.text), "coach", str(c.id), str(c.why))

func _update_pin(li: Dictionary) -> void:
	pin.visible = not li.is_empty()
	if li.is_empty(): return
	_pin_title.text = TranslationServer.translate("PIN_TITLE") % [str(li.id).trim_prefix("L"), str(li.title)]
	var c = app.b.q("coach")
	if c is Dictionary and c.get("active", false) and int(c.total) > 0: _pin_sub.text = TranslationServer.translate("PIN_PROGRESS") % [mini(int(c.index) + 1, int(c.total)) if not c.get("done", false) else int(c.total), int(c.total)]
	else: _pin_sub.text = ""

## The home screen is not a drawer here: fold it away so the world is full-bleed; B / I / T open the old drawers as overlays until the tray lands.
func _home_drawer() -> void:
	if app.cur == app.home:
		if not app.drawer_hidden: app.toggle_drawer()
		if app.drawer_tab != null: app.drawer_tab.visible = false

# --- called by main.gd hooks ---------------------------------------------------------------------------------------------------------
func toast(text: String, level: String) -> void:
	if text.begins_with("★ Level passed") and app != null and app.b != null and str(app.b.g.get("level", "")) == "P0": return   # QA 1128c Q04: the prologue's blackout is scripted; the engine's "passed" line beside a DARK report misleads
	radio.say("SYS", text, "warn" if level == "warn" or level == "bad" else "sys")

func coach(step: Dictionary, index: int, _total: int) -> void:
	if index < 0: radio.set_current(""); return
	radio.say("TOBI", str(step.get("body", step.get("title", ""))), "coach", str(step.get("id", "step%d" % index)), str(step.get("why", "")))

## Space toggles the breaker, "." steps once. Returns true when the key was used.
func key(e: InputEventKey) -> bool:
	if ch6 != null and ch6.editing(): return false   # a number being typed into the exam or prediction field is not a tray shortcut
	if e.keycode == KEY_V and _has_charts() and not (get_viewport().gui_get_focus_owner() is LineEdit): toggle_charts(); return true
	if tray != null and (rtray.key(e) if rtray.visible else (gtray.key(e) if gtray.visible else tray.key(e))): return true
	match e.keycode:
		KEY_SPACE:
			if space_steps: return false   # core then ticks once
			breaker.toggle(); return true
		KEY_PERIOD: app.next_tick(); return true
		KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: breaker.step_rate(1); return true
		KEY_MINUS, KEY_KP_SUBTRACT: breaker.step_rate(-1); return true
	return false

## Slot for the kit tray (bottom-centre), between the radio and the breaker.
func tray_rect() -> Rect2:
	var w := app.vw(); var h := app.vs_h()
	var l := radio.position.x + radio.size.x + M; var r := breaker.position.x - M
	var hint = app.pad.hint if app.pad != null else null
	if hint != null and hint.visible and CbKit.pad_mode: l = maxf(l, hint.position.x + hint.size.x + M)   # the pad hint strip runs under the radio: the tray starts after it
	return Rect2(Vector2(l, h - 96.0 - M), Vector2(maxf(0.0, r - l), 96.0))

## Bottom edge of the radio: above the pad hint strip while it shows (handheld / phone: the strip would sit on the radio).
func _radio_y() -> float:
	var y := app.vs_h() - M - radio.size.y
	var hint = app.pad.hint if app.pad != null else null
	if hint != null and hint.visible and CbKit.pad_mode and hint.position.x < radio.position.x + radio.width:
		y = minf(y, hint.position.y - 6.0 - radio.size.y)
	return y

func layout() -> void:
	if app == null or instruments == null: return
	var w := app.vw(); var h := app.vs_h(); var kind := CbLayout.kind
	instruments.layout()
	if app.cur == app.home and app.drawer_tab != null: app.drawer_tab.visible = false
	var left: float = M + (app.world_tools_w() if CbLayout.touch and app.has_method("world_tools_w") else 0.0)
	var nl := 1 if kind == "phone" else 4; var nw := clampf(w * (0.30 if kind == "desktop" else 0.34), 300.0, 560.0)
	var wide_stage := kind != "phone" and ((ch4 != null and ch4.visible) or (ch7 != null and ch7.visible) or (ch8 != null and ch8.visible))
	var cap := h * 0.30
	if wide_stage and w < 1700.0:   # 11-28b (B25, B26): at 1280 wide the stage's tray ran under the speed keys; the radio gives it room (narrower, shorter)
		nw = clampf(w * 0.30 - (1700.0 - w) * 0.35, 240.0, nw); nl = 2; cap = h * 0.24
	if nl != radio.visible_lines or nw != radio.width or cap != radio.max_h: radio.visible_lines = nl; radio.width = nw; radio.max_h = cap; radio._rebuild()
	radio.position = Vector2(left, _radio_y())
	var bs := 0.80 if kind == "phone" else (1.0 if kind == "desktop" else 0.92)
	breaker.scale = Vector2(bs, bs); breaker.size = breaker.custom_minimum_size
	var bw := breaker.size.x * bs; var bh := breaker.size.y * bs
	breaker.position = Vector2(w - M - bw, h - M - bh)
	# the stages and trays lay out against the radio and the breaker just placed (they used last frame's sizes)
	if ch4 != null: ch4.layout()
	if ch7 != null: ch7.layout()
	if ch8 != null: ch8.layout()
	if ch2 != null: ch2.layout()
	if tray != null: tray.layout(); rtray.layout(); gtray.layout()
	var tap := maxf(CbLayout.tap(), 36.0)
	menu_btn.custom_minimum_size = Vector2(tap, tap); menu_btn.size = Vector2(tap, tap); menu_btn.position = Vector2(w - M - tap, M)
	# phone: a dark disc behind the ☰ so it reads as a button over a stage's text card, not a glyph inside it (tester, ch8)
	var disc := GridTheme._sb(Color(GridTheme.INK, 0.92), Color(GridTheme.SODIUM_DIM, 0.6), int(tap / 2.0), 1, 0.0) if CbLayout.kind == "phone" else null
	menu_btn.flat = disc == null   # a flat button draws no stylebox
	for st in ["normal", "hover", "pressed", "focus"]:
		if disc != null: menu_btn.add_theme_stylebox_override(st, disc)
		else: menu_btn.remove_theme_stylebox_override(st)
	pin.position = Vector2(M, M); pin.size = Vector2(0, 0)
	if fold_btn != null:
		fold_btn.visible = _has_charts()
		fold_btn.text = (tr("FOLD_SHOW") if GridTheme.charts_folded else tr("FOLD_HIDE")) + "   V"
		fold_btn.reset_size(); fold_btn.position = Vector2(M + pin.get_combined_minimum_size().x + 8.0, M + 4.0)   # beside the job title: the top-left charts start under it

var _pad_seen := false
func _process(_dt: float) -> void:
	if _on and radio != null: sync_look2()   # the 3D view can show or hide without an engine change
	if app != null and CbKit.pad_mode and app.pad != null and app.pad.hint.visible and app.pad.hint.text.replace("\n", "   ") != _legend_now():   # title and dialogs too
		app.pad.hint.text = _legend_now()
		if _on and radio != null: layout()
	if app != null and app.pad != null and app.pad.hint.visible: _place_hint.call_deferred()
	if not _on or radio == null or app == null: return
	var ph: bool = CbKit.pad_mode and app.pad != null and app.pad.hint.visible
	if ph != _pad_seen: _pad_seen = ph; layout()
	radio.position.y = _radio_y()
	_fade_hud_over_pan()
	if app.cur == app.home and app.drawer_tab != null and app.drawer_tab.visible: app.drawer_tab.visible = false   # the core re-shows its grip on some paths

## Phone, chapters 4/7/8: once the stage is panned down under the HUD, the title card and the clock fade away so they never cover the chart
## (a tester read the plot's axis through them at full pan); they come back as the stage pans home.
func _fade_hud_over_pan() -> void:
	var panned := false
	if CbLayout.kind == "phone":
		for h in [ch4, ch7, ch8]:
			if h == null or not h.visible: continue
			for st in h.stages.values():
				if st != null and st.visible and st._pan.y < -24.0: panned = true
	var a := 0.0 if panned else 1.0
	for n in [pin, instruments]:
		if n != null: n.modulate.a = move_toward(n.modulate.a, a, 0.15)

## The pad legend strip follows the route tray's mode: surveying with a pad has its own buttons (the shell's default comes back after).
## 1.9: the strip wraps to the radio's width and sits on the bottom edge under it (the shell places it as one long line, which at the 16 px
## floor ran into chapter 4's status line). Runs after the shell's own placement each frame.
func hint_rect() -> Rect2:
	var hint = app.pad.hint if app != null and app.pad != null else null
	return Rect2(hint.position, hint.size) if hint != null and hint.visible else Rect2()

func _place_hint() -> void:
	var hint: Label = app.pad.hint
	if not hint.visible: return
	var w := radio.width if _on and radio != null and app.started and radio.width > 100.0 else minf(560.0, app.vw() - 28.0)
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF; hint.custom_minimum_size = Vector2.ZERO
	var one := hint.text.replace("\n", "   ")
	var f := hint.get_theme_font("font"); var fsz := hint.get_theme_font_size("font_size")
	if hint.label_settings != null: f = hint.label_settings.font if hint.label_settings.font != null else f; fsz = hint.label_settings.font_size
	var t := one
	if f != null and f.get_string_size(one, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > w:   # two lines, split at the separator nearest the middle
		var parts := one.split("   ", false); var half := int(ceil(parts.size() / 2.0))
		t = "   ".join(parts.slice(0, half)) + "\n" + "   ".join(parts.slice(half))
	if hint.text != t: hint.text = t
	hint.size = hint.get_minimum_size()
	var x := radio.position.x if _on and radio != null and app.started else 14.0
	hint.position = Vector2(x, app.vs_h() - M - hint.size.y)

## 1.8: the strip names GRID's own buttons in a level (the shell's "LB/RB drawers" pointed at drawers GRID does not have) and only the
## menu buttons over a dialog or the title.
var _rt_mode := ""
func _pad_legend(m: String) -> void: _rt_mode = m

func _legend_now() -> String:
	if not app.started or app.modal() != null: return tr("PAD_LEGEND_MENU")
	if _rt_mode == "survey": return tr("PAD_LEGEND_SURVEY")
	if _rt_mode == "xfmr": return tr("PAD_LEGEND_XF")
	return tr("PAD_LEGEND_GRID")
