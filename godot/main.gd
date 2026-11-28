extends CbApp
## GRID front-end. The world (godot/world: diorama, lights, flow ribbons, day-night) comes from the engine queries; drawers arrive in M2.4+.
## pad, touch, smoke) comes from CbApp in addons/cobanana. The real world and drawers arrive in M2.
var grid_world: WorldView
var district3d: District3D = null   ## the Career's district in 3D (ui/career/career_screen.gd takes it over while the screen is open)
var chrome: GridChrome
var sound: GridSound   ## GridAudio wired to the screen (ui/grid_sound.gd)

func game_config() -> Dictionary:
	GridUi.load_strings()
	return GridUi.extend_config({
		"chrome": "custom", "home": "home",
		"title": str(ProjectSettings.get_setting("application/config/name", "GRID")),
		"tagline": tr("GRID_TAGLINE"),
		"blurb": tr("GRID_BLURB"),
		"accent": Color("#39E1FF") if OS.get_environment("CB_LOOK") == "1" else GridTheme.SODIUM,   # 11-28b audit: the shell's Settings and codex drew in cyan, a colour the new look has nowhere else
		"accent2": Color("#FFB020"),
		"modes": [["learner", tr("MODE_LEARNER"), tr("MODE_LEARNER_DESC")], ["engineer", tr("MODE_ENGINEER"), tr("MODE_ENGINEER_DESC")], ["sandbox", tr("MODE_SANDBOX"), tr("MODE_SANDBOX_DESC")]],
		"dock": [["home", tr("DOCK_HOME"), Color("#39E1FF"), tr("DOCK_HOME")]],   # the shell wants a home id; it is blank (ui/home_blank.gd), the old Operator Clock drawer is gone
		"screens": {"home": "res://ui/home_blank.gd"},
		"overlay": [], "full": [],
		"tick_label": tr("TICK_BUTTON"), "tick_seconds": TICKS_NORMAL.duplicate(),   # a 5-hour bench night (20 blocks) runs 16 s at 2x, 6 s at 4x: no dead air once the build is right
		"keys": [["Space", tr("KEY_SPACE_DESC")]],
	})

func game_build_world(parent: Node) -> Node:
	GridSettings.load_all()
	grid_world = WorldView.new(); grid_world.app = self; grid_world.cute = GridSettings.cute; parent.add_child(grid_world)
	if DisplayServer.get_name() != "headless" and OS.get_environment("CB_LOOK") != "1" and not OS.has_environment("CB_SMOKE"):   # LOOK2: the 3D province under the 2D overlay (world3d/)
		var p3 := Province3D.new(); p3.name = "Province3D"; p3.visible = false; add_child(p3); grid_world.look3d = p3; grid_world.prov3d = p3
		var b3 := Bay3D.new(); b3.name = "Bay3D"; b3.visible = false; add_child(b3); grid_world.bay3d = b3   # DECISIONS 23: the island bay under the title and L01 to L03
		var bn := Bench3D.new(); bn.name = "Bench3D"; bn.visible = false; add_child(bn); grid_world.bench3d = bn   # chapter 2's bench jobs L04 and L06 in 3D
		var sg3 := Stage3D.new(); sg3.name = "Stage3D"; sg3.visible = false; add_child(sg3); grid_world.stage3d = sg3   # chapter 4's jobs L10 to L13 in 3D
		var dn := District3D.new(); dn.name = "District3D"; dn.visible = false; add_child(dn); district3d = dn   # the Career's district at night
	return grid_world

## The prologue's cascade in bullet time: every new trip slows the clock 4x for 3.5 s and flashes the world, so the player watches each line go.
var _trips_seen := -1
var _bullet_until := 0
const TICKS_NORMAL := [0.0, 2.0, 0.8, 0.3]
func _bullet_check() -> void:
	var li = b.q("levelInfo")
	if not (li is Dictionary and str(li.get("id", "")) == "P0"): _trips_seen = -1; return
	var out := 0
	for br in b.g.get("branches", []): if not bool(br.get("inService", true)) and str(br.id) != "T5": out += 1
	if _trips_seen >= 0 and out > _trips_seen:
		_bullet_until = Time.get_ticks_msec() + 3500
		cfg.tick_seconds = TICKS_NORMAL.map(func(x): return x * 4.0)
		if grid_world != null: grid_world.flash_trip()
		if _trips_seen == 0 and grid_world != null and grid_world.look3d is Province3D and grid_world.look3d.visible and not OS.has_environment("CB_CAM"): grid_world.look3d.turn_to_city()   # 1.19 (Ravi): the first trip turns the camera to the city, so its lights are seen going out
		sfx("breaker_open")   # the relay lets go
	_trips_seen = out

func game_on_changed() -> void:
	_bullet_check()
	if grid_world != null: grid_world.refresh(b)
	if chrome != null: chrome.refresh(); _skin_pin()
	if sound != null and grid_world != null: sound.on_changed(grid_world.model)

func game_end_card(vb: VBoxContainer, g: Dictionary) -> void:
	GridUi.end_card(vb, g, self)

func game_time_text() -> String:
	var c = b.q("clock")
	if c == null or c.is_empty(): return ""
	return tr("HUD_TIME") % [int(c.day) + 1, int(c.hour), int(c.minute)]

func game_top_stats() -> Array:
	var c = b.q("clock")
	if c == null or c.is_empty(): return []
	return [[tr("HUD_CLOCK"), "%02d:%02d" % [int(c.hour), int(c.minute)], CbKit.ACC], [tr("HUD_DAY"), str(int(c.day) + 1), CbKit.TX]]

func game_coach_steps() -> Array:
	# The core coach only needs one placeholder step; the level's own coach (engine query `coach`) speaks through the radio, GridChrome polls it.
	return [{"id": "welcome", "kind": "read", "title": tr("COACH_WELCOME_TITLE"), "body": tr("COACH_WELCOME_BODY"), "why": tr("COACH_WELCOME_WHY")}]

## CB_CAM for screenshots: parts separated by '|'. `act=name/arg/arg` runs an engine action (numbers, true/false or text args), `ff=n` advances n
## blocks, anything else goes to the world camera ("zoom=2,tx=12,ty=7").
func game_camera(spec: String) -> void:
	var cam: PackedStringArray = []
	for part in spec.split("|"):
		if part.begins_with("act="):
			var f := part.substr(4).split("/"); var args: Array = []
			for a in f.slice(1):
				if a == "true" or a == "false": args.append(a == "true")
				elif a.is_valid_float(): args.append(float(a))
				else: args.append(a)
			b.act(f[0], args)
		elif part.begins_with("ff="): b.act("tick", [int(part.substr(3))])
		elif part.begins_with("paper="): game_on_changed(); PaperKit.qa(self, part.substr(6))   # QA: open a paper screen (menu, jobs, workorder, report)
		elif part.begins_with("ui="): game_on_changed(); chrome.qa_ui(part.substr(3))   # QA: tray / tag state, see GridChrome.qa_ui
		else: cam.append(part)
	game_on_changed()
	if grid_world != null: grid_world.set_camera(",".join(cam))
	var later := OS.get_environment("CB_CAM_LATER")   # QA captures: a second spec after CB_CAM_LATER_AT seconds (a tick that lights a town on camera)
	if later != "" and spec != later:
		get_tree().create_timer(float(OS.get_environment("CB_CAM_LATER_AT")) if OS.get_environment("CB_CAM_LATER_AT") != "" else 4.0).timeout.connect(func(): game_camera(later))

## CB_SEQ for audit captures (debug builds): steps "secs:what" separated by ';', each run that many seconds after start.
## what = @name (save the window to $CB_SHOT_DIR/name.png), quit, or a CB_CAM spec (act=..., ff=n, paper=report, camera words).
func _qa_seq(seq: String) -> void:
	var dir := OS.get_environment("CB_SHOT_DIR") if OS.get_environment("CB_SHOT_DIR") != "" else ProjectSettings.globalize_path("user://seq")
	DirAccess.make_dir_recursive_absolute(dir)
	for step in seq.split(";", false):
		var i := step.find(":")
		if i < 0: continue
		var at := float(step.left(i)); var what := step.substr(i + 1)
		get_tree().create_timer(at).timeout.connect(func():
			if what == "quit": get_tree().quit()
			elif what.begins_with("win="):   # QA: live resize (win=WxH) or fullscreen (win=full) / back (win=window)
				var v := what.substr(4)
				if v == "full": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				elif v == "window": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				else: var wh := v.split("x"); DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
			elif what.begins_with("@"):
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, what.substr(1)]); print("CB_SEQ shot ", what.substr(1))
			else: game_camera(what))

## The 3D look keeps moving while paused (water, clouds, smoke): the 30 fps idle cap waits 2 min, for a player who has left, not one reading a decision (1.17).
func game_idle_ms() -> int:
	if grid_world != null and grid_world.look3d != null and grid_world.look3d.visible: return 120000
	if district3d != null and district3d.visible: return 120000   # the Career's district moves too
	return 20000

func game_unhandled_key(e: InputEventKey) -> bool:
	if chrome != null and chrome.key(e): return true
	match e.keycode:   # bench levels use the kit tray and tags; the old Build / Inspect drawers remain on B / I for grid levels (L07) until their task
		KEY_B: if chrome != null and not chrome.tray_active(): show_screen(home if cur == "build" else "build"); chrome.refresh(); return true
		KEY_I: if chrome != null and not chrome.tray_active(): show_screen(home if cur == "inspect" else "inspect"); chrome.refresh(); return true
		KEY_T: if chrome != null and not chrome.tray_active(): show_screen(home if cur == "timeline" else "timeline"); chrome.refresh(); return true
	return grid_world != null and grid_world.key(e)

# --- custom chrome hooks ---
func game_build_chrome(r: Control) -> void:
	audio.headless = true   # the shell's generated music stays off: GridAudio plays the music (the shell's sfx cues still work)
	sound = GridSound.new(); sound.name = "GridSound"; add_child(sound); sound.setup(self)
	chrome = GridChrome.new(); chrome.app = self; r.add_child(chrome); chrome.build()
	get_window().size_changed.connect(func(): if chrome != null and is_instance_valid(chrome): chrome.call_deferred("refresh"))   # 1128c: a resized window (or one the window manager enlarged) left the cards where the old size put them
	chrome.pin_pressed.connect(_on_pin)
	get_tree().node_added.connect(func(n: Node): if n is Label or n is Button or n is LineEdit or n is RichTextLabel: (func(id: int): var c = instance_from_id(id); if c is Control: GridText.floor_control(c)).call_deferred(n.get_instance_id()))   # by id: a node freed before the deferred call ran   # a node freed before the deferred call ran raised "Cannot convert argument 1"   # 1.9: 16 px floor
	if OS.is_debug_build() and OS.get_environment("CB_SEQ") != "": _qa_seq(OS.get_environment("CB_SEQ"))   # audit captures: timed steps in one window
	if OS.get_environment("CB_SHOT_DIR") != "" and OS.get_environment("CB_SEQ") == "":   # QA hand play on a GPU window: save the viewport every CB_SHOT_EVERY seconds (default 5) as NNNN.png, no quit
		var dir := OS.get_environment("CB_SHOT_DIR"); DirAccess.make_dir_recursive_absolute(dir)
		var every := float(OS.get_environment("CB_SHOT_EVERY")) if OS.get_environment("CB_SHOT_EVERY") != "" else 5.0
		var t := Timer.new(); t.wait_time = every; t.autostart = true; add_child(t)
		var n := [0]
		t.timeout.connect(func(): n[0] += 1; get_viewport().get_texture().get_image().save_png("%s/%04d.png" % [dir, n[0]]))
	if OS.has_environment("CB_TEXTAUDIT"):   # 1.9: the text-size audit (tests/text_flow.gd, loaded by path: tests/ is not exported)
		get_tree().create_timer(1.0).timeout.connect(func():
			var tf = load("res://tests/text_flow.gd")
			if tf == null: get_tree().quit(2); return
			await tf.run(self)
			get_tree().quit(0 if tf.fails == 0 else 1))
	if QaPad.want(): var qp := QaPad.new(); qp.name = "QaPad"; add_child(qp)   # 1.8 QA: a scripted pad tour in this window (qa_pad.gd)
	if OS.is_debug_build() and not OS.has_environment("CB_SMOKE"):   # perf log for device runs: "CB_FPS fps=.. min=.." every 5 s (logcat / stdout)
		var tm := Timer.new(); tm.wait_time = 5.0; tm.autostart = true; add_child(tm)
		tm.timeout.connect(func():
			var pf: Dictionary = grid_world.perf if grid_world != null else {}
			var fr := maxf(1.0, float(Engine.get_frames_per_second()) * 5.0)
			print("CB_FPS fps=%d frame_ms=%.1f level=%s static_ms=%.1f dyn_ms=%.2f top_ms=%.2f model_ms=%.1f models=%d static_n=%d homes_n=%d tick=%s" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, str(b.q("levelInfo").get("id", "-")) if started else "title", float(pf.get("static_us", 0)) / 1000.0, float(pf.get("dyn_us", 0)) / 1000.0 / fr, float(pf.get("top_us", 0)) / 1000.0 / fr, float(pf.get("model_us", 0)) / 1000.0 / maxf(1.0, float(pf.get("models", 1))), int(pf.get("models", 0)), int(pf.get("static_n", 0)), int(pf.get("homes_n", 0)), ("busy%d/applied%d/dropped%d/apply_ms%d/speed%d" % [int(ticker.busy()), ticker.applied, ticker.dropped, ticker.apply_us / 1000, speed]) if ticker != null else "-"])
			if ticker != null: ticker.apply_us = 0
			if grid_world != null: for k in grid_world.perf: grid_world.perf[k] = 0)
func game_chrome_visible(v: bool) -> void:
	if chrome != null: chrome.set_chrome_visible(v)
func game_relayout() -> void:
	if chrome != null: chrome.layout()
	for n in root.get_children():   # dialogs keep their scrim full-bleed behind the notch when the safe area changes
		if n is PaperHost: PaperKit.bleed(self, n)
func game_toast(text: String, level: String) -> bool:
	if chrome == null: return false
	chrome.toast(text, level); return true
func game_coach(step: Dictionary, index: int, total: int) -> bool:
	if chrome == null: return false
	if str(step.get("id", "")) != "welcome": chrome.coach(step, index, total)
	return true

func game_title_demo() -> void:   # backdrop of the title: the first job as it begins (dusk, the hamlet dark, nothing placed); the bay lights the lighthouse
	b.act("startLevel", ["L01", 7, "learner"])
	game_on_changed()

# --- paper screens (ui/work_order.gd, shift_report.gd, title_screen.gd, pause_menu.gd) ---
func game_title(r: Control) -> bool:
	if OS.is_debug_build() and FileAccess.file_exists("user://qa_level.txt"):   # device QA (debug APK only): `adb shell run-as <app> sh -c 'echo L05 > files/qa_level.txt'` jumps to a job once, since a phone launch cannot pass CB_LEVEL
		var lv := FileAccess.get_file_as_string("user://qa_level.txt").strip_edges(); DirAccess.remove_absolute("user://qa_level.txt")
		if lv != "": get_tree().create_timer(0.3).timeout.connect(func(): new_game(_mode_pref()); start_level(lv, true))
	if OS.has_environment("CB_LOAD_TIME"): get_tree().create_timer(2.0).timeout.connect(func(): new_game(_mode_pref()); GridLoading.start(self, OS.get_environment("CB_LOAD_TIME")))   # QA: start a job through the loading card, as the jobs list does; with CB_PADLOG the card prints its times
	if OS.has_environment("CB_CAREER"): get_tree().create_timer(0.5).timeout.connect(func(): Career.qa(self, OS.get_environment("CB_CAREER")))   # desk QA: land on the Career (ui/career/career.gd)
	return TitleScreen.build(self, r)
func game_end_screen() -> bool:
	if OS.has_environment("CB_CLEAN"): return true   # QA captures: no report over the world
	if grid_world != null and grid_world.look3d != null and grid_world.look3d.visible and not OS.has_environment("CB_SHOT"):   # LOOK2: let the player see the lights go out before the paper comes
		_report_soon()
		return true
	return ShiftReport.open(self)

const REPORT_WAIT := 2.5   # 1.18: was 3.5 s with nothing on screen (the 1.17 tester pressed Y and the D-pad in the gap)
var _report_btn: Button = null
## The shift is over in the 3D look: the world stays in view for REPORT_WAIT seconds so the player sees the lights, and a glass banner says the
## report is coming, with a bar that fills. The banner is a focused button: A, Enter or a click opens the report at once.
func _report_soon() -> void:
	if is_instance_valid(_report_btn): return
	var b := Button.new(); b.name = "ReportSoon"; b.text = tr("REP_COMING"); b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", GridTheme.font("semi")); b.add_theme_font_size_override("font_size", GridTheme.fs(20))
	for st in ["normal", "hover", "pressed", "focus"]: b.add_theme_stylebox_override(st, GridTheme.glass_sb(0.82, 6, 16.0))
	b.add_theme_color_override("font_color", GridTheme.G_TEXT); b.add_theme_color_override("font_focus_color", GridTheme.G_TEXT); b.add_theme_color_override("font_hover_color", GridTheme.SODIUM)
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP); b.grow_horizontal = Control.GROW_DIRECTION_BOTH; b.grow_vertical = Control.GROW_DIRECTION_END
	b.offset_top = 132.0   # 11-28b (B14): under the clock; at the bottom it sat on the taller trays' headers
	var bar := ColorRect.new(); bar.color = GridTheme.SODIUM; bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.anchor_left = 0.0; bar.anchor_right = 0.0; bar.anchor_top = 1.0; bar.anchor_bottom = 1.0; bar.offset_top = -4.0; bar.offset_bottom = -1.0
	b.add_child(bar)
	root.add_child(b); _report_btn = b
	b.grab_focus()
	var open := func() -> void:
		if not is_instance_valid(_report_btn): return
		_report_btn.queue_free(); _report_btn = null
		ShiftReport.open(self)
	b.pressed.connect(open)
	var tw := create_tween(); tw.tween_method(func(k: float) -> void: if is_instance_valid(bar): bar.offset_right = b.size.x * k, 0.0, 1.0, REPORT_WAIT)
	tw.tween_callback(open)
func game_menu() -> bool: return PauseMenu.toggle(self)

## A job starts (new game, level start, load): the work order slides in unless the job is already under way.
func _begin() -> void:
	super()
	if chrome != null and chrome.rtray != null: chrome.rtray.level = ""   # a restart or retry of the same job must not resume the old survey (review 2026-11-10)
	WorkOrder.close_now()
	if WorkOrder.auto: WorkOrder.open_fresh(self)

## Core re-applies the drawer cover on every relayout (_cover_of(home) = drawer_w, 68 % of a handheld screen) even though GRID's home drawer is
## blank and hidden: the island then fitted into the left third of a 1280x800 screen. Keep the world uncovered whenever no drawer shows.
## (Core request filed in status/core-requests.md: _cover_of should be 0 while drawer_hidden.)
func _apply_drawer_width() -> void:
	super()
	if drawer_hidden or cur == home: _set_cover(0.0)

## Top-left pin: the work order while the job runs, the report again once it has ended.
func _on_pin() -> void:
	if modal() != null: return
	if str(b.g.get("status", "playing")) != "playing": end_seen = false; menus.end_card()
	else: WorkOrder.open(self)

## The pin after a job has ended: a lost job turns it into a red "Incident · Retry ▸" pin (tap = the incident report with Retry again, e.g. after "Look
## around"), a won one into "WO-xx · lit ▸" (report, Next job). GridChrome owns the pin and rewrites its text on every refresh, so this runs after each one.
## NOTE for GridChrome's owner: a `set_pin_state(kind, title, sub)` setter would replace the label / stylebox pokes below.
var _pin_kind := ""
var _pin_sb0: StyleBox
func _skin_pin() -> void:
	if chrome == null or chrome.pin == null or not started: return
	var pin: PanelContainer = chrome.pin
	var st := str(b.g.get("status", "playing"))
	var kind := "" if st == "playing" else ("done" if st == "won" else "lost")
	var li = b.q("levelInfo"); var lid := str(li.id).trim_prefix("L") if li is Dictionary and li.get("active", false) else ""
	if kind == "" and _pin_kind == "": return
	var vbx := pin.get_child(0) as VBoxContainer
	var t: Label = vbx.get_child(0); var sub: Label = vbx.get_child(1)
	if kind == "":
		if _pin_sb0 != null: pin.add_theme_stylebox_override("panel", _pin_sb0)
		t.remove_theme_color_override("font_color"); sub.remove_theme_color_override("font_color"); pin.modulate = Color.WHITE; _pin_kind = ""
		for l in [t, sub]:
			if l.has_meta("ls0"): (l as Label).label_settings = l.get_meta("ls0"); l.remove_meta("ls0")
		return
	if _pin_sb0 == null: _pin_sb0 = pin.get_theme_stylebox("panel")
	if _pin_kind != kind:
		var sb := GridTheme.paper_sb(3, 12.0).duplicate() as StyleBoxFlat
		sb.border_color = PaperKit.RED if kind == "lost" else GridTheme.SODIUM_DIM; sb.set_border_width_all(4 if kind == "lost" else 3)
		if kind == "lost": sb.bg_color = Color("#F3D9CF")
		var ink: Color = PaperKit.RED if kind == "lost" else GridTheme.PAPER_INK
		if GridTheme.look2:   # LOOK2: the pin stays glass (the paper pin's dark ink never reached the LabelSettings, so it read white on cream)
			sb = GridTheme.glass_sb(0.86, 6, 10.0).duplicate() as StyleBoxFlat
			sb.border_color = Color("#E0604A") if kind == "lost" else GridTheme.SODIUM; sb.set_border_width_all(2)
			ink = Color("#FFB4A6") if kind == "lost" else Color("#F4EBD8")
		pin.add_theme_stylebox_override("panel", sb); _pin_kind = kind
		t.add_theme_color_override("font_color", ink); sub.add_theme_color_override("font_color", Color(ink, 0.85))
		for l in [t, sub]:
			if GridTheme.look2 and (l as Label).label_settings != null:
				if not l.has_meta("ls0"): l.set_meta("ls0", (l as Label).label_settings)
				var ls := (l as Label).label_settings.duplicate() as LabelSettings; ls.font_color = ink if l == t else Color(ink, 0.85); (l as Label).label_settings = ls
	var tt: String = tr("PIN_INCIDENT") if kind == "lost" else tr(GridChrome.done_pin_key(b.g)) % lid
	var ss: String = tr("PIN_INCIDENT_SUB") % lid if kind == "lost" else tr("PIN_DONE_SUB")
	if t.text != tt: t.text = tt
	if sub.text != ss: sub.text = ss

## 1.8: the tick runs on a worker thread (ui/grid_ticker.gd), so no frame waits on the sidecar. CB_SYNC_TICK=1 (and the CB_SMOKE run) keep the shell's blocking tick.
var ticker: GridTicker
func next_tick() -> void:
	if OS.has_environment("CB_SYNC_TICK") or OS.has_environment("CB_SMOKE"): super(); return   # the shell smoke checks the tick a frame after Space; tests/ticker_flow.gd covers the worker path
	if ticker == null: ticker = GridTicker.new(b); tree_exiting.connect(func(): if ticker != null: ticker.finish())
	if not started or str(b.g.get("status", "playing")) != "playing" or ticker.busy(): return
	audio.play("tick")
	ticker.start()

func _poll_tick() -> void:
	if ticker == null: return
	var res := ticker.poll()
	if res.is_empty(): return
	if not bool(res.ok): toast(str(res.message), "bad"); return
	var ms: Array = res.missions
	if ms.is_empty(): return
	banner.text = tr("MISSION_BANNER") % [ms[0].title, ms[0].get("lesson", "")]; _banner_life = 4.5; audio.play("win")
	_claim()   # any further finished missions (rare)

var _hitch_last := 0.0
var _hitch_ms := float(OS.get_environment("CB_HITCH")) if OS.is_debug_build() else 0.0
func _process(dt: float) -> void:
	if _hitch_ms > 0.0 and (dt * 1000.0 > _hitch_ms or (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0 > _hitch_ms and absf(Performance.get_monitor(Performance.TIME_PROCESS) - _hitch_last) > 0.001)):
		_hitch_last = Performance.get_monitor(Performance.TIME_PROCESS)
		print("CB_HITCH t=%.2f frame_ms=%.0f process_ms=%.0f level=%s" % [Time.get_ticks_msec() / 1000.0, dt * 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, str(b.q("levelInfo").get("id", "-")) if started else "title"])   # frames over CB_HITCH ms, for stall hunts
	_poll_tick()
	super(dt)
	if _bullet_until > 0 and Time.get_ticks_msec() > _bullet_until: _bullet_until = 0; cfg.tick_seconds = TICKS_NORMAL.duplicate()
	if OS.has_environment("CB_CLEAN") and chrome != null and chrome.visible: chrome.visible = false   # QA captures: the world only
	if GridTheme.look2 and chrome != null and chrome.pin != null:   # LOOK2: the docked glass report covers the job card's corner; the card steps aside while it is open
		var rp = ShiftReport._d.get("panel")
		var open_rep := is_instance_valid(rp) and (rp as Control).is_visible_in_tree()
		for c in [chrome.pin, chrome.radio, chrome.rtray, chrome.gtray, chrome.tray]:   # the job card, the radio log (it ghosted through the glass) and the parts tray (the report cut through it)
			if c == null: continue
			if open_rep:
				if c.visible: c.visible = false; c.set_meta("rep_hid", true)
			elif c.has_meta("rep_hid"): c.visible = true; c.remove_meta("rep_hid")
		var veil := open_rep or modal() != null   # 11-28b audit (B04, B05): charts, tags and world labels showed through the report's glass and the dialogs
		for c in [chrome.ch2, chrome.ch3, chrome.ch4, chrome.ch5, chrome.ch6, chrome.ch7, chrome.ch8, chrome.chf, chrome.tags, chrome.fold_btn]:
			if c == null: continue
			var want := 0.0 if veil else 1.0
			if not is_equal_approx(c.modulate.a, want): c.modulate.a = want
	if _pin_kind != "" and chrome != null and chrome.pin != null and started:
		_skin_pin()   # GridChrome may have rewritten the labels
		if _pin_kind == "lost": chrome.pin.modulate = Color.WHITE.darkened(0.06 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)))   # a slow breathing so the way back is noticed

## GRID cues go to GridAudio, everything else (click, confirm, back ...) stays with the shell's own sounds.
func sfx(k: String) -> void:
	if sound != null and sound.route(k): return
	super(k)

func game_smoke() -> void:
	for id in ["P0", "L01", "L02", "L03", "L07"]:
		b.act("startLevel", [id, 1, "learner"]); b.act("tick", [1]); game_on_changed(); await get_tree().process_frame
		CbSmoke._check(grid_world.model.kind != "none" and grid_world.model.towns.size() > 0, "the world builds a diorama for level %s" % id)
	grid_world.set_camera("zoom=2,tx=10,ty=6"); grid_world.set_camera("reset")
	CbSmoke._check(tr("GRID_TAGLINE") != "GRID_TAGLINE", "string catalogue locales/strings.csv is loaded (run --import)")
	var c0: Dictionary = b.q("clock")
	b.act("tick", [3]); await get_tree().process_frame
	var c1: Dictionary = b.q("clock")
	CbSmoke._check(int(c1.block) == int(c0.block) + 3 and int(c1.day) == int(c0.day), "the clock advances one block per tick")
	show_screen(home); await get_tree().process_frame
	CbSmoke._check(cur == home and not holder.visible and not screens.has("clock"), "the home screen is blank: no Operator Clock drawer exists or shows")
	# GRID chrome: nodes exist, kit bar and dock are hidden, breaker drives the speed, radio hears the coach
	b.act("startLevel", ["L01", 1, "learner"]); game_on_changed(); await get_tree().process_frame; _relayout(); await get_tree().process_frame
	CbSmoke._check(chrome != null and chrome.visible and chrome.instruments != null and chrome.radio != null and chrome.breaker != null and chrome.pin != null, "GRID chrome nodes exist and are shown in a level")
	CbSmoke._check(not top.visible and not dock_scroll.visible and _bar_h == 0.0 and _dock_h == 0.0, "kit bar and dock are hidden in custom chrome")
	CbSmoke._check(chrome.instruments.clock.visible and chrome.instruments.volt.visible and not chrome.instruments.dial.visible, "bench level: clock and voltmeter, no frequency dial")
	set_speed(0); chrome.breaker.set_rate(1); chrome.breaker.toggle(); CbSmoke._check(speed == 1, "breaker run sets speed 1")
	chrome.breaker.cycle_rate(); CbSmoke._check(speed == 2, "rate knob moves a running night to 2x")
	var pad_was := CbPad.enabled; CbPad.enabled = true
	var jb := InputEventJoypadButton.new(); jb.button_index = JOY_BUTTON_BACK; jb.pressed = true
	CbSmoke._check(chrome.handle_input(jb) and speed == 3, "pad Back steps a running night 2x -> 4x (1.18, Dagny: the D-pad never reached the speed keys)")
	chrome.handle_input(jb); CbSmoke._check(speed == 1, "pad Back wraps 4x -> 1x")
	CbPad.enabled = pad_was
	chrome.breaker.toggle(); CbSmoke._check(speed == 0, "breaker pause sets speed 0")
	chrome.space_steps = false; var ev := InputEventKey.new(); ev.keycode = KEY_SPACE; ev.pressed = true; game_unhandled_key(ev); CbSmoke._check(speed > 0, "Space toggles run"); game_unhandled_key(ev); CbSmoke._check(speed == 0, "Space toggles pause"); chrome.space_steps = true
	var t0 := int(b.q("clock").tick); ev.keycode = KEY_PERIOD; game_unhandled_key(ev); CbSmoke._check(int(b.q("clock").tick) == t0 + 1, "'.' steps one block")
	CbSmoke._check(chrome.radio.lines.any(func(l): return l.speaker == "TOBI" and l.kind == "coach"), "the radio received the coach line")
	var msg := tr("TEST_REFUSED")
	toast(msg, "warn")
	CbSmoke._check(chrome.radio.lines.back().speaker == "SYS" and chrome.radio.lines.back().kind == "warn", "a toast arrives on the radio as a SYS warning")
	b.act("startLevel", ["L03", 1, "learner"]); game_on_changed(); await get_tree().process_frame
	CbSmoke._check(chrome.instruments.mode == "loss" and chrome.instruments.volt.units == "%" and chrome.instruments.volt.vmax == 20.0, "L03: the meter is LINE LOSS 0-20 %, not volts")
	CbSmoke._check(chrome.instruments.volt.blank and chrome.instruments.volt.needle_value() == 0.0 and chrome.breaker.label_text() == tr("BREAKER_RUN_NIGHT"), "L03 before the circuit is built: blank meter at rest, breaker says Run the night (the study hall starts at 18:00)")
	b.act("startLevel", ["L07", 1, "learner"]); game_on_changed(); await get_tree().process_frame
	CbSmoke._check(chrome.instruments.dial.visible and not chrome.instruments.volt.visible, "grid level: frequency dial, no voltmeter")
	var pf = load("res://tests/paper_flow.gd")   # by path: tests/ is not exported, so main.gd must never name a test class (Android parse error)
	if pf != null: await pf.run(self)
	var cf = load("res://tests/career_flow.gd")
	if cf != null: await cf.run(self)
