class_name ShiftReport
extends RefCounted
## The result screen (cfg game_end_screen -> true). Won: a paper "Shift report" with three lamps stamped one after the other (lit = earned), the metrics,
## the histogram in print ink, ADA's note (the engine's lesson line with the player's numbers) and Retry / Next job / Copy design code.
## Lost: an "Incident report" in red ink: the cause in plain words, the lesson with the player's numbers, what to try (the coach's current step) and
## Retry / Look around. A failure never shows the histogram. The world stays visible beside the sheet. Data: app.end_data(), levelInfo, resultCard,
## benchStatus, coach, solutionCode (queries only).

const STAMP_DELAY := 0.42
const CHAPTER_END := {"L03": "L04", "L30": "L07", "L09": "L10", "L13": "L14", "L18": "L19", "L22": "L23", "L27": "L28"}   ## last job of a chapter -> the first job of the next one (opens the chapter-end card, not the work order). L30 closes chapter 2; L07 opens chapter 3 (src/level/chapters/ch3.ts)
const HIST_MIN_N := 10                ## fewer designs than this and the histogram says so instead of drawing a lonely bar
static var _d: Dictionary = {}
static var _force_short := false   ## a report taller than the screen (L16's long lesson and next-lamp note at 1080 p) reopens in the scrolling layout

static func T(key: String) -> String: return TranslationServer.translate(key)

static func is_open() -> bool: return not _d.is_empty() and is_instance_valid(_d.host) and not (_d.host as Node).is_queued_for_deletion()
## 1128c (art review: "the DARK report renders at 08:00 in full daylight"): while a failed job's report is open, the 3D places
## hold the night (22:30) if the clock has run into daylight, so the dark homes read as dark beside the lit ones.
## Art review 2: only when the run itself passed through night (a noon PV failure keeps its sun: WO-21, WO-35).
static var _run_dark := false
static var _last_mn := -1.0
static func night_hold(mn: float) -> float:
	if not is_open():
		if mn < _last_mn - 1.0: _run_dark = false   # the clock went back: a new run (Retry, another job)
		_last_mn = mn
		if WorldMath.night(mn) >= 0.5: _run_dark = true
		return mn
	return 1350.0 if _d.get("lost", false) and _run_dark and WorldMath.night(mn) < 0.5 else mn
static func holding() -> bool: return is_open() and _d.get("lost", false) and _run_dark
static func host_node() -> Control: return _d.host if is_open() else null

## cfg hook: build the report and own the end state. Returns true (the kit card is skipped).
static func open(app: CbApp) -> bool:
	GridUi.load_strings()
	var e: Dictionary = app.end_data()
	var won: bool = bool(e.won)
	var li = app.b.q("levelInfo"); var has_li: bool = li is Dictionary and li.get("active", false)
	var lid := str(e.level_id)
	var stars := int(app.b.g.get("stars", 0)) if won else 0
	if won and lid != "": GridSettings.record_stars(lid, stars); GridSettings.record_pass(lid)
	PaperKit.glass = GridTheme.look2   # LOOK2: glass, docked in a third of the width, no dim: the dark district stays in view
	var compact := PaperKit.compact(app) or app.vs_h() < 860.0   # Deck 1280x800 / 768p laptops: the compact sheet fits without the "more" cue over ADA's note
	var short: bool = app.vs_h() < 920.0 or _force_short
	var dock := _dock(app, minf(700.0, app.vw() * (0.52 if app.vw() >= 1000.0 else 0.94)))   # {left, w}: the side that keeps the built island visible
	var w: float = dock.w
	if PaperKit.glass:   # 11-28b (B03): under 560 px the won report clipped (lamps, loss column, histogram)
		w = clampf(app.vw() * 0.29, minf(560.0, app.vw() - 32.0), 600.0)   # 1128c (art review): a narrower sheet on the right; the left two thirds show what happened
		dock.left = app.vw() - 16.0 - w
	var d := PaperKit.sheet(app, "end", w, (app.vs_h() - 24.0) if short and not compact else 0.0, 0.0 if PaperKit.glass else 0.34, (14.0 if compact else 22.0) if PaperKit.glass else (16.0 if compact else 30.0))
	_d = d; _d["lost"] = not won or lid == "P0"   # the prologue always ends dark
	app.sfx("page")
	var host: Control = d.host; var pn: PanelContainer = d.panel
	app.end_ui = host
	pn.remove_meta("cb_dlg")
	var left: float = dock.left
	pn.anchor_left = 0.0; pn.anchor_right = 0.0; pn.anchor_top = 0.5; pn.anchor_bottom = 0.5
	pn.offset_left = left; pn.offset_right = left + w
	if short: pn.offset_top = -(app.vs_h() - 24.0) * 0.5; pn.offset_bottom = (app.vs_h() - 24.0) * 0.5; pn.set_meta("rep_short", true)
	else: pn.offset_top = 0; pn.offset_bottom = 0; pn.grow_vertical = Control.GROW_DIRECTION_BOTH
	var vb: VBoxContainer = d.vb
	if compact: vb.add_theme_constant_override("separation", 6)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 6 if compact else 12); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sbx: Control = null
	if short: sbx = PaperKit.scroll_box(col); vb.add_child(sbx)
	else: vb.add_child(col)
	var lamps: Array = []
	if lid == "P0":   # the prologue is a scene, not a job: no lamps, no cost; Ada's line and the way to the island
		_head(col, T("REP_P0_TITLE"), T("REP_P0_SUB"), PaperKit.RED, compact)
		col.add_child(PaperKit.rule())
		col.add_child(_note(T("REP_P0_ADA"), PaperKit.BLUE, "ADA ›", compact))
		vb.add_child(PaperKit.rule())
		var prow := HFlowContainer.new(); prow.add_theme_constant_override("h_separation", 12); vb.add_child(prow)
		var again := PaperKit.btn(T("REP_P0_AGAIN"), false, func(): app.start_level("P0", true), 20); again.name = "Retry"; prow.add_child(again)
		var go := PaperKit.btn(T("REP_P0_GO"), true, func(): app.start_level("L01", true), 20); go.name = "Next"; prow.add_child(go)
		_hold_now(app)
		go.call_deferred("grab_focus")
		PaperKit.glass = false
		return true
	if won: lamps = _won(app, col, e, li if has_li else {}, stars, short, compact)
	else: _lost(app, col, e, li if has_li else {}, compact)
	vb.add_child(PaperKit.rule())
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 12); row.add_theme_constant_override("v_separation", 8); vb.add_child(row)
	var primary: Button = null
	var retry := PaperKit.btn(T("REP_RETRY"), not won, func(): _retry(app, lid, str(e.mode)), 20); retry.name = "Retry"; row.add_child(retry)
	if won:
		if str(e.next_level) != "" or lid == "L28":   # the finale has no next job: its Next opens the game-end card
			var nx := PaperKit.btn(T("REP_NEXT"), true, func(): _next(app, lid, str(e.next_level)), 20); nx.name = "Next"; row.add_child(nx); primary = nx
		var cp := PaperKit.btn(T("REP_COPY"), false, func(): pass, 20); cp.name = "Copy"
		cp.pressed.connect(func(): _copy_code(app, cp)); row.add_child(cp)
		if primary == null: primary = retry
	else:
		var lk := PaperKit.btn(T("REP_LOOK"), false, func(): _look(app, won), 20); lk.name = "Look"; row.add_child(lk); primary = retry
	if not short and pn.get_combined_minimum_size().y > app.vs_h() - 24.0:   # too tall to fit: build it again in the scrolling layout, before anything is submitted
		host.queue_free(); _d = {}; app.end_ui = null
		_force_short = true; var r := open(app); _force_short = false
		return r
	if won and lid != "" and app.scores != null:
		var line: String = app.scores_submit_level(lid)
		if line != "": vb.add_child(PaperKit.lbl(line, 14, "sans", Color(PaperKit.INK, 0.6), true))
	_fit_v(app, d, left, w)
	if PaperKit.glass: pn.set_meta("rep_glass", true)
	PaperKit.glass = false
	PaperKit.slide_in(d, 60.0)
	(host as PaperHost).primary = primary
	app.focus_dialog()
	for i in 2: app.get_tree().process_frame.connect(func(): _redock(app, d, minf(700.0, app.vw() * (0.52 if app.vw() >= 1000.0 else 0.94))), CONNECT_ONE_SHOT)
	if short and sbx != null and pn.has_meta("rep_glass"):   # 11-28b audit: the scrolling layout was a full-height slab of empty glass; fit it to its text
		pn.set_meta("rep_full_h", app.vs_h() - 24.0)
		col.resized.connect(func(): if pn.has_meta("rep_fit"): _shrink_short(app, d, sbx, col))   # re-fit whenever the text lays out late (a slow machine: B02); never during the slide-in (it fought the tween)
		app.get_tree().create_timer(0.45).timeout.connect(func(): if is_instance_valid(pn): pn.set_meta("rep_fit", true); _shrink_short(app, d, sbx, col))   # the world may still be refitting on the frame the job ended
	if primary != null: primary.call_deferred("grab_focus")   # won: Next job is focused; lost: Retry
	_stamp_lamps(app, lamps)
	if pn.has_meta("rep_glass"): _frame_for_report(app, w)
	return true

## 1128c: the report covers the right of the screen; slide the world so what was in the middle of the view (the job's subject) sits
## in the middle of the part the sheet leaves free, and let the 3D place frame its own consequence when it knows one (report_focus).
## Apply night_hold at once (the places otherwise redraw their sky only when the clock moves).
static func _hold_now(app: CbApp) -> void:
	var chm = app.get("chrome")
	if chm != null and chm.get("instruments") != null and chm.instruments.clock != null: chm.instruments.clock.visible = chm.instruments.clock_on()
	if chm != null and chm.get("instruments") != null: chm.instruments.visible = app.vw() >= 1500.0
	var wv = app.get("grid_world")
	var l3 = wv.get("look3d") if wv != null else null
	if l3 == null or not is_instance_valid(l3): return
	if l3.has_method("_update_sky") and l3.get("_minute") != null and float(l3._minute) >= 0.0: l3._update_sky(float(l3._minute))
	elif l3.has_method("_update_dynamic") and l3.get("model") != null: l3._update_dynamic()

static func _frame_for_report(app: CbApp, w: float) -> void:
	var chm = app.get("chrome")
	if chm != null and chm.get("breaker") != null: (chm.breaker as CanvasItem).visible = false
	var wv = app.get("grid_world")
	if wv == null: return
	var l3 = wv.get("look3d")
	if l3 == null or not is_instance_valid(l3) or not (l3 as Node3D).visible: return
	if l3.has_method("report_focus") and l3.report_focus(): pass
	_hold_now(app)
	var c3: Camera3D = l3.get("cam")
	if c3 == null or l3.get("_g_target") == null: return
	# shift the goal right by the ground width that half the sheet covers, so the old centre sits mid-way in the free part
	var vr := app.get_viewport().get_visible_rect().size
	var aspect := vr.x / maxf(1.0, vr.y)
	var half_w := float(l3._g_dist) * tan(deg_to_rad(c3.fov) * 0.5) * aspect   # ground half-width at the goal distance
	var frac := (w * 0.5) / maxf(1.0, app.vw())
	var yw := float(l3._g_yaw)
	l3._g_target += Vector3(cos(yw), 0.0, -sin(yw)) * (2.0 * half_w * frac)
	if l3.has_method("_clamp_goal"): l3._clamp_goal()

## Where the sheet goes: {left, w} in the UI root's coordinates. It sits on the side that overlaps the built island (hamlets, hut: WorldView.object_rects) the
## least, and gets narrower (down to 460) when neither side is clear. No island rects (grid levels): left.
static func _dock(app: CbApp, w0: float) -> Dictionary: return dock_for(app.vw(), island_rect(app), w0, island_bounds(app))

## Re-run the docking once the world has settled (the island moves a little when the model and camera refit after the last tick).
static func _redock(app: CbApp, d: Dictionary, w0: float) -> void:
	if is_instance_valid(d.get("panel")) and (d.panel as Control).has_meta("rep_glass"): return   # LOOK2: stays docked at the left third
	if not is_instance_valid(d.host) or _d != d: return
	var dk := _dock(app, w0); var pn: Control = d.panel
	pn.offset_left = float(dk.left); pn.offset_right = float(dk.left) + float(dk.w)

## Pure part of `_dock` (unit-tested): usable width `vw`, island rect `ir` in the same coordinates, preferred sheet width `w0`.
static func dock_for(vw: float, ir: Rect2, w0: float, isl := Rect2()) -> Dictionary:
	var m := 24.0; var w := w0
	if ir.size.x <= 0.0 or vw < 1000.0: return {"left": (vw - w) * 0.5 if vw < 1000.0 else m, "w": w}
	var ov_l := _overlap(Rect2(m, 0, w, 10.0), ir); var ov_r := _overlap(Rect2(vw - m - w, 0, w, 10.0), ir)
	if minf(ov_l, ov_r) <= 0.0 and ov_l == ov_r and isl.size.x > 0.0:   # both sides clear of the built things: take the one that covers less of the island
		return {"left": m if _overlap(Rect2(m, 0, w, 10.0), isl) <= _overlap(Rect2(vw - m - w, 0, w, 10.0), isl) else vw - m - w, "w": w}
	if minf(ov_l, ov_r) > 0.0:   # neither side is clear: shrink to the room the roomier side has
		var room_l := ir.position.x - 2.0 * m; var room_r := vw - ir.end.x - 2.0 * m
		w = clampf(maxf(room_l, room_r), 460.0, w0)
		ov_l = _overlap(Rect2(m, 0, w, 10.0), ir); ov_r = _overlap(Rect2(vw - m - w, 0, w, 10.0), ir)
	return {"left": m if ov_l <= ov_r else vw - m - w, "w": w}

## Keep clear of the bottom row (tray, price tag, the run lever): the sheet centres in the room above it when it fits there. Called before the slide-in (its tween animates these offsets).
static func _fit_v(app: CbApp, d: Dictionary, left: float, w: float) -> void:
	var pn: Control = d.panel
	var ch = app.get("chrome")
	if ch == null or not ch.has_method("tray_rect") or pn.has_meta("rep_short"): return
	var bottom: float = (ch.tray_rect() as Rect2).position.y
	if ch.breaker != null and ch.breaker.visible:
		bottom = minf(bottom, ch.breaker.position.y)   # the sheet may redock to the lever's side once the world settles
	var h := pn.get_combined_minimum_size().y
	if h > bottom - 20.0 or bottom <= 0.0: return
	var top := maxf(10.0, (bottom - h) * 0.5)
	pn.anchor_top = 0.0; pn.anchor_bottom = 0.0; pn.grow_vertical = Control.GROW_DIRECTION_END; pn.offset_top = top; pn.offset_bottom = top + h

## Pure part of `_shrink_short` (tests/island_flow.gd): the panel's new height, or -1 to leave it. `content` under 40 px means the text is not laid
## out yet (B02: on a slow machine the first fit cut the report down to its buttons); the result never passes `full`.
static func fit_height(cur_h: float, scroll_h: float, content: float, full: float) -> float:
	if content < 40.0: return -1.0
	var need := minf(full, cur_h - scroll_h + content + 4.0)
	return -1.0 if absf(need - cur_h) < 2.0 else need

## The scrolling layout fills the window's height; once laid out, a report shorter than that shrinks to its content (the top stays where it was).
static func _shrink_short(app: CbApp, d: Dictionary, sbx: Control, col: Control) -> void:
	if not is_instance_valid(d.get("panel")) or not is_instance_valid(sbx) or not is_instance_valid(col) or _d != d: return
	var pn: Control = d.panel
	var need := fit_height(pn.size.y, sbx.size.y, maxf(col.get_combined_minimum_size().y, col.size.y), float(pn.get_meta("rep_full_h", app.vs_h() - 24.0)))
	if need < 0.0: return
	var top := minf(pn.global_position.y, app.vs_h() - 12.0 - need)
	pn.anchor_top = 0.0; pn.anchor_bottom = 0.0; pn.grow_vertical = Control.GROW_DIRECTION_END
	pn.offset_top = top; pn.offset_bottom = top + need

static func _overlap(a: Rect2, b: Rect2) -> float:
	var l := maxf(a.position.x, b.position.x); var r := minf(a.end.x, b.end.x)
	return maxf(0.0, r - l)

## Screen rect (UI root coordinates) of what the player built and what it feeds: hamlets, schools, huts. Rect2() when the world shows none.
static func island_rect(app: CbApp) -> Rect2:
	var wv = app.get("grid_world")
	if wv == null or not wv.has_method("object_rects"): return Rect2()
	var rs: Array = wv.object_rects()
	if rs.is_empty(): return Rect2()
	var u: Rect2 = rs[0]
	for r in rs: u = u.merge(r)
	return Rect2(u.position - Vector2(app.inset.x, app.inset.y), u.size)

## Screen rect (UI root coordinates) of the whole island slab, from the corners of the map. Rect2() when there is no map.
static func island_bounds(app: CbApp) -> Rect2:
	var wv = app.get("grid_world")
	if wv == null or not wv.has_method("world_to_screen") or not wv.model.has("map") or str(wv.model.get("kind", "none")) == "none": return Rect2()
	var mp: Vector2 = wv.model.map
	var pts := [wv.world_to_screen(Vector2(0, 0)), wv.world_to_screen(Vector2(mp.x, 0)), wv.world_to_screen(Vector2(0, mp.y)), wv.world_to_screen(mp)]
	var r := Rect2(pts[0], Vector2.ZERO)
	for q in pts: r = r.expand(q)
	return Rect2(r.position - Vector2(app.inset.x, app.inset.y), r.size)

## "Next job": the last job of a chapter opens the chapter-end card instead of the next work order.
static func _next(app: CbApp, lid: String, next_id: String) -> void:
	if lid == "L28": ChfEnd.open(app); return   # the finale: the game-end card, no next chapter
	if CHAPTER_END.has(lid): chapter_end(app, next_id if next_id != "" else str(CHAPTER_END[lid]), lid)   # the finale shows its card whatever job the campaign lists next
	else: GridLoading.start(app, next_id)

static func _look(app: CbApp, won: bool) -> void:
	app.menus.end_look()
	if not won: app.toast(T("REP_LOOK_HINT"), "warn")   # the radio tells the stranded player how to get back to work

## Retry keeps the player's design: the job restarts at dusk with the same hut, reels, junction and converters already laid (the work order
## stays folded in the pin), so a failed night costs one swap and a breaker pull, not a rebuild. "Start over" (pause menu) still clears it.
static func _retry(app: CbApp, lid: String, mode: String) -> void:
	if lid == "": app.new_game(mode); return
	var design := design_of(app)
	var bs = app.b.q("benchStatus"); var bench_job: bool = bs is Dictionary and bool(bs.get("active", false))   # chapter 1's bench (hut, reels, breaker) has its own line; every other job gets the plain one
	WorkOrder.skip_once = true   # Retry never re-reads the docket (a tester met the briefing again and the step counter back at "Press Run"); the pin still opens it
	var cq = app.b.q("coach"); var coach_at: int = int(cq.get("index", 0)) if cq is Dictionary and bool(cq.get("active", false)) else 0
	app.start_level(lid, true)
	var refused := replay(app, design)
	if coach_at > 0 and refused == 0: app.b.act("coachCarry", [coach_at])   # the coach carries on where the last attempt left it (a partly refused design keeps the full coach)
	app.game_on_changed()
	var ch = app.get("chrome")
	var grid_job: bool = design.any(func(a): return str(a[0]) == "buildRoute")
	if not design.is_empty() and ch != null: ch.radio.say("TOBI", T("REP_RETRY_PARTIAL") % refused if refused > 0 else T("REP_RETRY_KEPT_GRID" if grid_job else ("REP_RETRY_KEPT" if bench_job else "REP_RETRY_KEPT_BUILD")))

## The bench design now on the table as a list of [action, args] (empty on grid levels or before anything is built).
static func design_of(app: CbApp) -> Array:
	var out := _built_design(app)
	var log: Array = app.b.g.get("levelActions", [])
	if log.any(func(a): return str(a[0]) == "predict"): out = out.filter(func(a): return str(a[0]) != "predict")   # the prediction comes back from the log, in the order played
	var have := {}
	for a in out: have[str(a[0])] = true
	for a in log:   # 1128c Q01: settings (poles, ratios, phases, banks, conductors, taps, fuses, sizes, limits) are the design too; replay them in the order played
		var n := str(a[0])
		if have.has(n): continue
		if n.begins_with("set") or n.begins_with("assign") or n == "placeSeriesCap" or n == "predict": out.append([n, JSON.parse_string(JSON.stringify(a[1]))])
	return out

static func _built_design(app: CbApp) -> Array:
	var bs = app.b.q("benchStatus")
	if not (bs is Dictionary and bs.get("active", false)): return _grid_design(app)
	var bench: Dictionary = bs.bench
	var out: Array = []
	if bench.get("hutM") != null: out.append(["placeHut", [float(bench.hutM)]])
	if str(bench.get("topology", "")) == "trunk": out.append(["placeJunction", []])
	var cm: Dictionary = bench.get("cableMm2", {})
	for run in ["main", "b", "b2"]:
		if cm.get(run) != null: out.append(["layCable", [run, float(cm[run])]])
	if bool(bench.get("converters", false)): out.append(["placeConverters", [true]])
	return out

## Grid levels with surveyed routes (chapter 2): every line as buildRoute (same ends, kit and bends) and every transformer, in build order.
static func _grid_design(app: CbApp) -> Array:
	var out: Array = []
	var br_of := {}
	for br in app.b.g.get("branches", []): br_of[str(br.id)] = br
	for br in app.b.g.get("branches", []):
		if str(br.kind) == "xfmr": out.append(["placeTransformer", [str(br.from), str(br.to), str(br.catalogId)]]); continue
		if str(br.kind) == "cable":   # L30: the sea cable is part of the design (its catalogue id lives on the cable record)
			for c in app.b.g.get("cables", []): if str(c.branchId) == str(br.id): out.append(["layCableRoute", [str(br.from), str(br.to), str(c.cableId)]])
			continue
		for rr in app.b.g.get("routes", []):
			if str(rr.branchId) != str(br.id): continue
			var rq: Dictionary = rr.request
			var wp: Array = (rq.waypoints as Array).slice(1, (rq.waypoints as Array).size() - 1)
			var ra := [str(br.from), str(br.to), str(rq.conductorId).trim_prefix("acsr-"), str(rq.familyId), rq.crossingFamilyId, float(rq.spanM), wp]
			if rq.has("insulatorId"): ra.append_array([str(rq.insulatorId), str(rq.get("coastInsulatorId", rq.insulatorId))])   # L29: the insulators are part of the design ('pin' otherwise)
			out.append(["buildRoute", ra])
	for st in app.b.g.get("storage", []): out.append(["placeStorage", [str(st.bus), str(st.catalogId)]])   # L30: the island battery
	var fd = app.b.q("freqDesign")   # chapter 6: units placed and held, store clocks, pumps, ride-through, in build order (the level places its own units first, so the ids come out the same)
	if fd is Array: for a in fd: out.append([str(a.name), a.args])
	var li = app.b.q("levelInfo"); var allowed: Array = li.get("allowedActions", []) if li is Dictionary else []
	var cd = app.b.q("controlDesign")   # chapter 5: shunts bought, steps, tap positions and automatic settings (only what this level lets the player touch)
	if cd is Array:
		for a in cd:
			if allowed.has(str(a.name)) or str(a.name) == "predict": out.append([str(a.name), a.args])   # predict is always allowed (it is not in the level's list)
	return out

## Rebuilds the design; returns how many steps the engine refused (the radio must not claim a design was kept when part of it was not).
static func replay(app: CbApp, design: Array) -> int:
	var bad := 0
	var base := {}; var seen := {}   # storage already standing when the job starts, and storage placed by this replay: several batteries of one kind must all come back (chapter 6)
	for st in app.b.g.get("storage", []): var k0 := str(st.bus) + "/" + str(st.catalogId); base[k0] = int(base.get(k0, 0)) + 1
	for a in design:
		if str(a[0]) == "placeStorage":
			var k := str((a[1] as Array)[0]) + "/" + str((a[1] as Array)[1]); seen[k] = int(seen.get(k, 0)) + 1
			if int(seen[k]) <= int(base.get(k, 0)): continue
		elif _standing(app, a): continue   # a job that starts with part of the design already built (L29's district line and transformers) must not stack it twice
		var r = app.b.act(str(a[0]), a[1])
		if not (r is Dictionary and bool(r.get("ok", false))): bad += 1
	return bad

## Is this design step already standing (same ends and same part) in the job as it started?
static func _standing(app: CbApp, a: Array) -> bool:
	var args: Array = a[1]
	if str(a[0]) == "placeStorage":
		for st in app.b.g.get("storage", []): if str(st.bus) == str(args[0]) and str(st.catalogId) == str(args[1]): return true
		return false
	if str(a[0]) == "layCableRoute":
		for c in app.b.g.get("cables", []):
			for br in app.b.g.get("branches", []): if str(br.id) == str(c.branchId) and str(br.from) == str(args[0]) and str(br.to) == str(args[1]) and str(c.cableId) == str(args[2]): return true
		return false
	for br in app.b.g.get("branches", []):
		if str(br.from) != str(args[0]) or str(br.to) != str(args[1]): continue
		if str(a[0]) == "placeTransformer":
			if str(br.kind) == "xfmr" and str(br.catalogId) == str(args[2]): return true
		elif str(a[0]) == "buildRoute":
			for rr in app.b.g.get("routes", []):
				if str(rr.branchId) != str(br.id): continue
				var rq: Dictionary = rr.request
				var wp: Array = (rq.waypoints as Array).slice(1, (rq.waypoints as Array).size() - 1)
				var ins: String = str(rq.get("insulatorId", "pin")); var coast: String = str(rq.get("coastInsulatorId", ins))
				if str(rq.conductorId).trim_prefix("acsr-") == str(args[2]) and str(rq.familyId) == str(args[3]) and float(rq.spanM) == float(args[5]) and str(rq.crossingFamilyId) == str(args[4]) and JSON.stringify(wp) == JSON.stringify(args[6]) \
						and ins == (str(args[7]) if args.size() > 7 else "pin") and coast == (str(args[8]) if args.size() > 8 else ins): return true
	return false

static func _copy_code(app: CbApp, btn: Button) -> void:
	var code = app.b.q("solutionCode")
	if not (code is String) or str(code) == "": app.toast(T("REP_NO_CODE"), "warn"); return
	DisplayServer.clipboard_set(str(code))
	var old := btn.text; btn.text = T("REP_COPIED")
	app.toast(T("REP_CODE_TOAST"), "good")
	if btn.is_inside_tree():   # a tween on the button, not a scene timer: a report closed inside the 2 s freed the button and the timer then called a lambda with a freed capture (engine ERROR)
		var tw := btn.create_tween(); tw.tween_interval(2.0); tw.tween_callback(func(): btn.text = old)

# ---- won ----------------------------------------------------------------------------------------------------------------------------
static func _head(col: VBoxContainer, title: String, sub: String, ink: Color, compact := false) -> void:
	var head := HBoxContainer.new(); col.add_child(head)
	var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.add_theme_constant_override("separation", 0); head.add_child(hv)
	hv.add_child(PaperKit.lbl(title.to_upper(), (26 if compact else 34) if PaperKit.glass else (38 if compact else 60), "title", ink, true))
	hv.add_child(PaperKit.lbl(sub, 15 if compact else 18, "semi", Color(PaperKit.INK, 0.75), true))

static func _won(app: CbApp, col: VBoxContainer, e: Dictionary, li: Dictionary, stars: int, _short := false, compact := false) -> Array:
	var lid := str(e.level_id)
	_head(col, T("REP_WON"), T("REP_SUB") % [lid.trim_prefix("L"), str(e.title)], PaperKit.INK, compact)
	col.add_child(PaperKit.rule())
	var texts := WorkOrder.lamp_texts(li)
	var lamps: Array = []
	if bool(li.get("stars", false)) and lid != "P0":   # the first line: the lamps earned and what the next one asks (a tester never saw the lamp count)
		var ll := PaperKit.lbl((T("REP_LAMPS_NEXT") % [stars, str(texts[stars])]) if stars < 3 and stars < texts.size() else (T("REP_LAMPS") % stars), 16 if compact else 20, "semi", PaperKit.INK, true); ll.name = "LampLine"; col.add_child(ll)
	var lr := HBoxContainer.new(); lr.add_theme_constant_override("separation", 10); col.add_child(lr)
	for i in 3:
		var cell := VBoxContainer.new(); cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cell.add_theme_constant_override("separation", 0); lr.add_child(cell)
		var lamp := PaperKit.Lamp.new(44.0 if compact else 86.0, i < stars); lamp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; cell.add_child(lamp); lamps.append(lamp)
		if i < texts.size():
			var cap := PaperKit.lbl(str(texts[i]), 14 if compact else 15, "sans", PaperKit.INK if i < stars else Color(PaperKit.INK, 0.55), true); cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; cell.add_child(cap)
	col.add_child(PaperKit.rule())
	# metrics: cost, worst home, line loss (bench) or what the grid level tracks
	var g: Dictionary = app.b.g
	var score_lvl: bool = str(li.get("histogram", "")) == "score"   # judged on a score (seconds, kA, a prediction), not on what was built: no "Cost $0" and no line loss
	var spent_ := float(g.get("budget", {}).get("spent", 0.0))
	var rc0 = app.b.q("resultCard"); var no_build: bool = rc0 is Dictionary and bool(rc0.get("noBuild", false))   # 1.7: an exam with nothing to build (L13)
	var m: Array = [] if (score_lvl or no_build) and spent_ <= 0.0 else [[T("REP_COST"), CbRegion.money(spent_, false, 0)]]
	var bs = app.b.q("benchStatus")
	var cb = app.b.q("ch2Bench")
	if cb is Dictionary and cb.get("active", false):   # chapter 2's closed-form benches (L04 alternator, L06 town line) report their own numbers
		if str(cb.kind) == "machine":
			m.append([T("C2_REP_FREQ"), T("C2_REP_HZ") % WorkOrder.num(snappedf(float(cb.fHz), 0.01))]); m.append([T("C2_REP_VOLT"), T("REP_V") % WorkOrder.num(snappedf(float(cb.eRmsV), 0.1))])
		else:
			m.append([T("REP_LOSS"), T("REP_PCT") % WorkOrder.num(snappedf(float(cb.lossPct), 0.01))]); m.append([T("C2_REP_TOWN"), T("REP_PCT") % WorkOrder.num(snappedf(float(cb.vTownPu) * 100.0, 0.1))])
	elif bs is Dictionary and bs.get("active", false):
		if bool(bs.get("powered", false)): m.append([T("REP_WORST"), T("REP_V") % WorkOrder.num(snappedf(float(bs.vMinV), 0.1))])
		m.append([T("REP_LOSS"), T("REP_PCT") % WorkOrder.num(snappedf(float(bs.lossPct), 0.1))])
	else:
		var tr_: Dictionary = g.get("metrics", {}).get("track", {})
		var r3_ = g.get("rules", {}).get("ch3"); var no_loss: bool = r3_ is Dictionary and (r3_.has("harmonics") or r3_.has("fault"))   # L08 and L09 are not judged on losses
		if tr_.get("lossPct") != null and not no_loss and not score_lvl and not no_build and not bool(g.get("rules", {}).get("freqTrack", false)): m.append([T("REP_LOSS"), T("REP_PCT") % WorkOrder.num(snappedf(float(tr_.lossPct), 0.1))])   # chapter 6 is judged on frequency, not losses
	var mr := HBoxContainer.new(); mr.add_theme_constant_override("separation", 20); col.add_child(mr)
	for it in m:
		var cell := VBoxContainer.new(); cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cell.add_theme_constant_override("separation", 0); mr.add_child(cell)
		cell.add_child(PaperKit.lbl(str(it[0]), 14, "mono", Color(PaperKit.INK, 0.6)))
		cell.add_child(PaperKit.lbl(str(it[1]), 26 if compact else 34, "title", PaperKit.INK))
	# histogram in print ink (only ever on a win)
	var rc = app.b.q("resultCard")
	if rc is Dictionary and rc.get("active", false) and not (rc.get("bins", []) as Array).is_empty():
		if int(rc.get("n", 0)) < HIST_MIN_N:   # a histogram of a handful of designs is noise: say so instead
			var few := PaperKit.lbl(T("REP_FEW"), 15, "sans", Color(PaperKit.INK, 0.65), true); few.name = "FewDesigns"; col.add_child(few)
		else:
			col.add_child(PaperKit.lbl(str(rc.metric), 14, "mono", Color(PaperKit.INK, 0.6)))
			var h := PaperKit.PaperHist.new(); h.name = "PaperHist"; h.custom_minimum_size = Vector2(240, 70 if compact else 120); h.set_data(rc); col.add_child(h)
			if str(rc.get("source", "")) == "bot": col.add_child(PaperKit.lbl(str(rc.label), 14, "sans", Color(PaperKit.INK, 0.6), true))
			if rc.get("mine") != null and rc.get("percentile") != null:
				col.add_child(PaperKit.lbl(T("RESULT_MINE_FMT") % [str(rc.get("mineText", CbKit.num(float(rc.mine), 1))), int(round(float(rc.percentile) * 100.0)), int(rc.n)] if int(round(float(rc.percentile) * 100.0)) > 0 else T("C4_MATCHED_BEST") % [str(rc.get("mineText", CbKit.num(float(rc.mine), 1))), int(rc.n)], 15, "sans", PaperKit.INK, true))
	var lesson := str(li.get("lesson", ""))
	if lesson != "": col.add_child(_note(lesson, PaperKit.BLUE, "", compact))
	if stars < 3 and GridStrings.S.has("NEXT_LAMP_" + lid):   # what the next lamp wants (testers passed L02, L05, L12, L16 and never learnt what the third lamp asked)
		var nl := _note(T("NEXT_LAMP_" + lid), PaperKit.INK, T("REP_NEXT_LAMP"), compact); nl.name = "NextLamp"; col.add_child(nl)
	return lamps

## ADA's handwritten-ish note: a sticky slip, slightly crooked, in pen blue.
static func _note(text: String, ink: Color, title := "", compact := false) -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(1, 1, 1, 0.06) if PaperKit.glass else Color("#FBF1B6"); sb.set_corner_radius_all(3); sb.border_color = GridTheme.HAIR if PaperKit.glass else Color(PaperKit.INK, 0.2); sb.set_border_width_all(1)
	sb.content_margin_left = 14 if compact else 18; sb.content_margin_right = 14 if compact else 18; sb.content_margin_top = 8 if compact else 12; sb.content_margin_bottom = 10 if compact else 14; sb.shadow_color = Color(0, 0, 0, 0.18); sb.shadow_size = 4; sb.shadow_offset = Vector2(1, 2)
	pc.add_theme_stylebox_override("panel", sb); pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2); pc.add_child(v)
	v.add_child(PaperKit.lbl(title if title != "" else T("REP_ADA") + " ›", 16, "mono", Color(ink, 0.85)))
	v.add_child(PaperKit.lbl(text, 15 if compact else 18, "semi", ink, true))
	pc.rotation = 0.0 if PaperKit.glass else deg_to_rad(-0.8)
	if PaperKit.glass: sb.shadow_size = 0
	pc.name = "Note"
	return pc

# ---- lost ---------------------------------------------------------------------------------------------------------------------------
static func _lost(app: CbApp, col: VBoxContainer, e: Dictionary, li: Dictionary, compact := false) -> void:
	var lid := str(e.level_id)
	var head := HBoxContainer.new(); col.add_child(head)
	var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.add_theme_constant_override("separation", 0); head.add_child(hv)
	hv.add_child(PaperKit.lbl(T("REP_LOST").to_upper(), (26 if compact else 34) if PaperKit.glass else (38 if compact else 60), "title", PaperKit.RED, true))
	hv.add_child(PaperKit.lbl(T("REP_SUB") % [lid.trim_prefix("L"), str(e.title)] if lid != "" else str(e.title), 15 if compact else 18, "semi", Color(PaperKit.INK, 0.75), true))
	var bud = app.b.g.get("budget", {})
	var over_budget: bool = bud is Dictionary and float(bud.get("capexLimit", 0.0)) > 0.0 and float(bud.get("spent", 0.0)) > float(bud.get("capexLimit", 0.0)) + 1e-6
	if not compact and not PaperKit.glass: head.add_child(Stamp.new(T("REP_STAMP_COST" if over_budget else "REP_STAMP_LOST")))   # an over-budget line may well light the market: the stamp must not say it did not
	col.add_child(PaperKit.rule())
	if str(e.get("reason", "")) != "":   # 11-28b: a report opened before the end has no cause yet; no empty heading
		col.add_child(PaperKit.lbl(T("REP_CAUSE"), 16, "mono", Color(PaperKit.INK, 0.72)))
		col.add_child(PaperKit.lbl(str(e.reason), 18 if compact else 23, "semi", PaperKit.RED, true))
	var bs = app.b.q("benchStatus")
	if bs is Dictionary and bs.get("active", false) and bool(bs.get("powered", false)) and (bs.bench as Dictionary).get("limits", {}).get("vMinV") != null:
		col.add_child(PaperKit.lbl(T("REP_NUMBERS") % [WorkOrder.num(snappedf(float(bs.vMinV), 0.1)), WorkOrder.num(float(bs.bench.limits.vMinV))], 18, "sans", PaperKit.INK, true))
	var lesson := str(li.get("lesson", ""))
	if lesson != "": col.add_child(_note(lesson, PaperKit.BLUE, "", compact))
	var co = app.b.q("coach"); var tip := T("REP_TRY_FALLBACK")
	if co is Dictionary and co.get("active", false) and not co.get("done", true) and str(co.get("text", "")) != "": tip = str(co.text)
	if str(li.get("tryHint", "")) != "": tip = str(li.tryHint)   # the engine's advice for this loss (e.g. the span that flashed over and what lifts it)
	col.add_child(_note(tip, PaperKit.INK, T("REP_TRY"), compact))

## A rubber stamp, tilted, in red ink.
class Stamp extends Control:
	var text := ""
	func _init(t := "") -> void:
		text = t; custom_minimum_size = Vector2(150, 80); mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var f := GridTheme.font("title"); var sz := GridTheme.fs(34)
		draw_set_transform(size * 0.5, deg_to_rad(-10.0), Vector2.ONE)
		var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
		var r := Rect2(-ts * 0.5 - Vector2(12, 6), ts + Vector2(24, 12))
		draw_rect(r, Color(PaperKit.RED, 0.9), false, 4.0)
		draw_rect(r.grow(-6), Color(PaperKit.RED, 0.55), false, 1.5)
		GridText.ds(self, f, Vector2(-ts.x * 0.5, ts.y * 0.5 - 8.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(PaperKit.RED, 0.9))

# ---- stamping -----------------------------------------------------------------------------------------------------------------------
## Each earned lamp is stamped in turn: the ring thumps down and the "stamp" sound plays. Headless / reduced motion: all stamped at once.
static func _stamp_lamps(app: CbApp, lamps: Array) -> void:
	var n := 0
	for lp in lamps:
		var lamp := lp as PaperKit.Lamp
		if not lamp.lit: continue
		if not PaperKit.animate():
			lamp.set_stamp(1.0); n += 1; continue
		var delay := 0.55 + STAMP_DELAY * n
		var tw := lamp.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func(): app.sfx("stamp"))
		tw.tween_method(lamp.set_stamp, 0.01, 1.0, 0.22)
		n += 1
	if n > 0 and not PaperKit.animate(): app.sfx("stamp")

# ---- chapter end --------------------------------------------------------------------------------------------------------------------
static var _chapter: Dictionary = {}

static func chapter_is_open() -> bool: return not _chapter.is_empty() and is_instance_valid(_chapter.host) and not (_chapter.host as Node).is_queued_for_deletion()
static func chapter_node() -> Control: return _chapter.host if chapter_is_open() else null

## The card after the last job of a chapter: "Saltmarsh is lit", a lit-island doodle, Nia's line, the lamps earned in the chapter, and "Chapter 2 · The Mainland,
## coming soon" with the next work order offered as a preview job (`preview_id`). The shift report is gone by now; Esc just leaves the card.
static func chapter_end(app: CbApp, preview_id: String, lid := "") -> void:
	GridUi.load_strings()
	if chapter_is_open(): return
	if lid == "":   # the QA screen and old callers: the card of the job on the table (chapter 1's unless it is a finale with its own card)
		var cur = app.b.q("levelInfo"); lid = str(cur.get("id", "")) if cur is Dictionary and cur.get("active", false) else ""
	var finale := lid == "L30"
	if app.end_ui != null and is_instance_valid(app.end_ui): app.end_ui.queue_free()
	app.end_ui = null; app.end_seen = true
	_d = {}
	var compact := PaperKit.compact(app)
	PaperKit.glass = GridTheme.look2   # 11-28 audit: the chapter card was cream paper over the 3D scene (the old look); glass like the report
	var d := PaperKit.sheet(app, "chapter", minf(780.0, app.vw() - 24.0), 0.0, 0.45 if PaperKit.glass else 0.55, 14.0 if compact else 30.0)
	_chapter = d
	app.sfx("page")
	var host: PaperHost = d.host
	host.closer = func(): _chapter_close(app, d)
	var vb: VBoxContainer = d.vb; vb.add_theme_constant_override("separation", 4 if compact else 10)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 4 if compact else 10); col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(col)
	var head := HBoxContainer.new(); head.add_theme_constant_override("separation", 14); col.add_child(head)
	var hv := VBoxContainer.new(); hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hv.add_theme_constant_override("separation", 0); head.add_child(hv)
	var cn := Jobs.chapter_of(lid)   # chapters 3-7 close with a card of their own (CH3_* ... CH7_*)
	var mid := cn in ["3", "4", "5", "6", "7"]
	var p := "CH2_" if finale else ("CH%s_" % cn if mid else "CH_")   # strings of the card: chapter 1 keeps CH_*, the chapter 2 finale has CH2_*
	hv.add_child(PaperKit.lbl(T(p + "TITLE").to_upper(), (34 if finale else 38) if compact else (52 if finale else 64), "title", PaperKit.INK, true))
	hv.add_child(PaperKit.lbl(T(p + "SUB"), 15 if compact else 18, "semi", Color(PaperKit.INK, 0.75), true))
	var isl: Control = CableDoodle.new() if finale else (ChapterDoodle.new() if mid else IslandDoodle.new()); isl.name = "CableDoodle" if finale else ("ChapterDoodle" if mid else "IslandDoodle")
	if mid: (isl as ChapterDoodle).chapter = int(cn)
	isl.custom_minimum_size = Vector2(210, 105) if compact else Vector2(300, 150); head.add_child(isl)   # every card gets its picture (a one-line `if mid:` had left chapters 1 and 2 without theirs)
	col.add_child(PaperKit.rule())
	var nia := _note(T(p + "NIA"), PaperPen.NIA, T("CH_NIA_TAG"), compact); nia.name = "NiaNote"; col.add_child(nia)
	if finale:   # Ada retires, Tobi has the last word: two notes side by side so the card still fits a 768 p screen
		var two := HBoxContainer.new(); two.add_theme_constant_override("separation", 14); col.add_child(two)
		var ada := _note(T("CH2_ADA"), PaperKit.SPEAKER["ADA"], T("CH2_ADA_TAG"), compact); ada.name = "AdaNote"; two.add_child(ada)
		var tobi := _note(T("CH2_TOBI"), PaperKit.SPEAKER["TOBI"], T("CH2_TOBI_TAG"), compact); tobi.name = "TobiNote"; two.add_child(tobi)
	var jobs: Array = _chapter_jobs(app, lid) if finale else (Jobs.list(app).map(func(lv): return str(lv.id)).filter(func(id): return Jobs.chapter_of(id) == cn) if mid else CHAPTER_JOBS)
	var earned := 0
	for id in jobs: earned += GridSettings.stars(id)
	var lr := PaperKit.lbl(T(p + "LAMPS") % [earned, jobs.size() * 3], 16 if compact else 20, "semi", PaperKit.INK, true); lr.name = "ChapterLamps"; col.add_child(lr)
	var soon := PanelContainer.new(); soon.name = "Soon"; soon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new(); sb.draw_center = false; sb.border_color = GridTheme.HAIR if PaperKit.glass else Color(PaperKit.INK, 0.55); sb.set_border_width_all(1 if PaperKit.glass else 2); sb.set_corner_radius_all(6)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 6 if compact else 10; sb.content_margin_bottom = 6 if compact else 10
	soon.add_theme_stylebox_override("panel", sb)
	var sv := VBoxContainer.new(); sv.add_theme_constant_override("separation", 0); soon.add_child(sv)
	sv.add_child(PaperKit.lbl(T(p + "NEXT"), 20 if compact else 28, "title", PaperKit.INK, true))
	sv.add_child(PaperKit.lbl(T(p + "SOON"), 14 if compact else 16, "sans", Color(PaperKit.INK, 0.75), true))
	col.add_child(soon)
	vb.add_child(PaperKit.rule())
	var row := HFlowContainer.new(); row.add_theme_constant_override("h_separation", 12); row.add_theme_constant_override("v_separation", 8); vb.add_child(row)
	var pv := PaperKit.btn(T(p + "PREVIEW"), true, func(): _chapter_close(app, d); app.start_level(preview_id, true), 20); pv.name = "Preview"; row.add_child(pv)
	var jb := PaperKit.btn(T("PAUSE_JOBS"), false, func(): _chapter_close(app, d); Jobs.open(app), 20); jb.name = "ChapterJobs"; row.add_child(jb)
	var st := PaperKit.btn(T(p + "STAY"), false, func(): _chapter_close(app, d), 20); st.name = "Stay"; row.add_child(st)
	host.primary = pv
	PaperKit.slide_in(d, 60.0)
	app.focus_dialog()
	pv.call_deferred("grab_focus")
	PaperKit.glass = false

static func _chapter_close(app: CbApp, d: Dictionary) -> void:
	if is_instance_valid(d.host): (d.host as Node).queue_free()
	if _chapter == d: _chapter = {}
	app.end_seen = true

const CHAPTER_JOBS := ["L01", "L02", "L03"]

## The jobs of chapter 2 for the finale's lamp count: everything the campaign lists after L03 up to the finale itself (the engine's order).
static func _chapter_jobs(app: CbApp, last: String) -> Array:
	var out: Array = []; var on := false
	for id in Jobs.chain(app):
		if on: out.append(str(id))
		if str(id) == "L03": on = true
		if str(id) == last: break
	return out

## Nia's pen colour (the speaker table of PaperKit has the same green).
class PaperPen:
	const NIA := Color("#2A7A52")

## Doodle of Saltmarsh at night with every window lit: a mound of island, palm, huts with sodium windows, a lighthouse with its beam, stars and waves.
class IslandDoodle extends Control:
	var _ink := PaperKit.ink(PaperKit.INK)   # captured at build: light ink on glass
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var k := minf(size.x / 300.0, size.y / 150.0); var ink := Color(_ink, 0.8)
		draw_set_transform(Vector2((size.x - 300.0 * k) * 0.5, (size.y - 150.0 * k) * 0.5), 0.0, Vector2(k, k))
		var sod := GridTheme.SODIUM
		for p in [Vector2(22, 18), Vector2(70, 34), Vector2(262, 22), Vector2(214, 40), Vector2(120, 12)]:   # stars
			draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(PaperKit.AMBER, 0.9), 2.0, true); draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(PaperKit.AMBER, 0.9), 2.0, true)
		draw_circle(Vector2(246, 56), 15.0, Color(PaperKit.INK, 0.06)); draw_arc(Vector2(246, 56), 15.0, 0.0, TAU, 28, ink, 2.2, true)   # moon
		var mound := PackedVector2Array([Vector2(30, 118), Vector2(60, 98), Vector2(100, 84), Vector2(150, 78), Vector2(200, 86), Vector2(240, 100), Vector2(272, 118)])
		draw_colored_polygon(mound, Color("#C9C09F")); draw_polyline(mound, ink, 2.6, true)
		for x in [40.0, 90.0, 150.0, 210.0]:   # waves
			draw_arc(Vector2(x, 128), 12.0, deg_to_rad(200), deg_to_rad(340), 10, Color(PaperKit.BLUE, 0.7), 2.4, true)
			draw_arc(Vector2(x + 28, 138), 12.0, deg_to_rad(200), deg_to_rad(340), 10, Color(PaperKit.BLUE, 0.7), 2.4, true)
		draw_line(Vector2(20, 118), Vector2(282, 118), ink, 2.4, true)
		# lighthouse with a sodium beam
		var lh := PackedVector2Array([Vector2(214, 90), Vector2(218, 52), Vector2(232, 52), Vector2(236, 90)])
		draw_colored_polygon(lh, Color("#F4EEDD")); draw_polyline(lh + PackedVector2Array([lh[0]]), ink, 2.4, true)
		draw_line(Vector2(216, 68), Vector2(234, 68), Color(PaperKit.RED, 0.8), 4.0); draw_rect(Rect2(218, 42, 14, 10), sod); draw_rect(Rect2(218, 42, 14, 10), ink, false, 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(218, 44), Vector2(230, 40), Vector2(226, 50)]), Color(sod, 0.0)); 
		draw_colored_polygon(PackedVector2Array([Vector2(232, 46), Vector2(284, 30), Vector2(284, 60)]), Color(sod, 0.25))
		# palm
		draw_polyline(PackedVector2Array([Vector2(60, 98), Vector2(56, 80), Vector2(62, 62)]), ink, 3.0, true)
		for a in [-150.0, -110.0, -70.0, -30.0]:
			var d := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))); draw_line(Vector2(62, 62), Vector2(62, 62) + d * 22.0 + Vector2(0, 6), Color("#3F7A52"), 3.0, true)
		# huts, lit
		for hx in [100.0, 128.0, 156.0, 182.0]:
			var by := 96.0 + absf(hx - 142.0) * 0.12
			for i in 4: draw_circle(Vector2(hx, by - 8), 18.0 - i * 3.5, Color(sod, 0.10 + 0.07 * i))
			draw_rect(Rect2(hx - 9, by - 14, 18, 14), Color("#E8DDBB")); draw_rect(Rect2(hx - 9, by - 14, 18, 14), ink, false, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(hx - 12, by - 14), Vector2(hx, by - 26), Vector2(hx + 12, by - 14)]), Color("#B5700F")); draw_polyline(PackedVector2Array([Vector2(hx - 12, by - 14), Vector2(hx, by - 26), Vector2(hx + 12, by - 14)]), ink, 2.0, true)
			draw_rect(Rect2(hx - 3, by - 11, 6, 7), sod)


## Doodle of the cable that joined Saltmarsh to the mainland: harbour pole on the left, the cable running under the waves, the island's lit huts on the right,
## and the trawler's anchor that did not get the cable (crossed out).
## Chapters 3-7: a pencil doodle of the chapter's idea (a phasor pair, three phases, a P-V nose, a frequency dip, a relay curve).
class ChapterDoodle extends Control:
	var _ink := PaperKit.ink(PaperKit.INK)   # captured at build: light ink on glass
	var chapter := 3
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var k := minf(size.x / 300.0, size.y / 150.0); var ink := Color(_ink, 0.8); var o := Vector2(20, 20) * k; var w := 260.0 * k; var h := 110.0 * k
		draw_line(o + Vector2(0, h), o + Vector2(w, h), ink, 2.0); draw_line(o, o + Vector2(0, h), ink, 2.0)
		var pts := PackedVector2Array()
		for i in 61:
			var x := float(i) / 60.0; var y := 0.0
			match chapter:
				3: y = 0.5 + 0.4 * sin(TAU * x * 2.0)
				4: y = 0.5 + 0.4 * sin(TAU * (x * 2.0 + 0.33))
				5: y = 0.15 + 0.8 * sqrt(maxf(0.0, 1.0 - pow(abs(x - 0.8) / 0.8, 2.0))) * (1.0 if x < 0.8 else 0.0)
				6: y = 0.8 - 0.45 * (x * 8.0) * exp(1.0 - x * 8.0) - 0.15 * (1.0 - exp(-x * 8.0))   # a frequency dip: the nadir, then droop settles it lower
				_: y = 0.1 + 0.08 / maxf(x, 0.09)
			pts.append(o + Vector2(x * w, h - clampf(y, 0.0, 1.0) * h))
		draw_polyline(pts, Color("#B5402F"), 3.0, true)
		if chapter in [3, 4]:
			var p2 := PackedVector2Array()
			for i in 61: var x := float(i) / 60.0; p2.append(o + Vector2(x * w, h - (0.5 + 0.4 * sin(TAU * (x * 2.0 + (0.66 if chapter == 4 else 0.12)))) * h))
			draw_polyline(p2, Color("#2F6FB5"), 3.0, true)

class CableDoodle extends Control:
	var _ink := PaperKit.ink(PaperKit.INK)   # captured at build: light ink on glass
	func _init() -> void: mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var k := minf(size.x / 300.0, size.y / 150.0); var ink := Color(_ink, 0.8)
		draw_set_transform(Vector2((size.x - 300.0 * k) * 0.5, (size.y - 150.0 * k) * 0.5), 0.0, Vector2(k, k))
		var sod := GridTheme.SODIUM
		for p in [Vector2(30, 16), Vector2(96, 30), Vector2(190, 14), Vector2(268, 24), Vector2(150, 40)]:   # stars
			draw_line(p + Vector2(-4, 0), p + Vector2(4, 0), Color(PaperKit.AMBER, 0.9), 2.0, true); draw_line(p + Vector2(0, -4), p + Vector2(0, 4), Color(PaperKit.AMBER, 0.9), 2.0, true)
		var sea_y := 100.0
		var shore := PackedVector2Array([Vector2(14, 118), Vector2(14, 84), Vector2(40, 80), Vector2(72, 88), Vector2(92, sea_y), Vector2(104, 118)])   # the mainland
		draw_colored_polygon(shore, Color("#C9C09F")); draw_polyline(shore, ink, 2.4, true)
		var mound := PackedVector2Array([Vector2(196, 118), Vector2(214, 98), Vector2(244, 88), Vector2(272, 96), Vector2(288, 118)])   # the island
		draw_colored_polygon(mound, Color("#C9C09F")); draw_polyline(mound, ink, 2.4, true)
		draw_line(Vector2(10, 118), Vector2(292, 118), ink, 2.4, true)
		for x in [112.0, 142.0, 172.0]:   # waves over the cable
			draw_arc(Vector2(x, 112), 11.0, deg_to_rad(200), deg_to_rad(340), 10, Color(PaperKit.BLUE, 0.7), 2.4, true)
			draw_arc(Vector2(x + 14, 126), 11.0, deg_to_rad(200), deg_to_rad(340), 10, Color(PaperKit.BLUE, 0.7), 2.4, true)
		# the pole at the harbour yard and the cable from its foot, under the sea, to the island
		draw_line(Vector2(54, 84), Vector2(54, 44), ink, 3.0, true); draw_line(Vector2(42, 50), Vector2(66, 50), ink, 3.0, true)
		draw_polyline(PackedVector2Array([Vector2(66, 50), Vector2(84, 62), Vector2(96, 90)]), Color(PaperKit.INK, 0.65), 1.8, true)
		var seabed := PackedVector2Array([Vector2(96, 98), Vector2(120, 134), Vector2(160, 138), Vector2(196, 122), Vector2(214, 104)])
		for i in seabed.size() - 1:   # a dashed run: it is under the water
			var a := seabed[i]; var b := seabed[i + 1]; var n := int(a.distance_to(b) / 8.0)
			for j in n:
				if j % 2 == 0: draw_line(a.lerp(b, float(j) / n), a.lerp(b, float(j + 1) / n), Color(PaperKit.RED, 0.85), 3.0, true)
		# the anchor over the cable, crossed out: it fell short
		var an := Vector2(148, 66)
		draw_line(an + Vector2(0, -14), an + Vector2(0, 14), ink, 3.0, true); draw_line(an + Vector2(-8, -8), an + Vector2(8, -8), ink, 3.0, true)
		draw_arc(an + Vector2(0, 6), 12.0, deg_to_rad(20), deg_to_rad(160), 12, ink, 3.0, true); draw_arc(an + Vector2(0, -16), 3.0, 0.0, TAU, 8, ink, 2.0, true)
		draw_line(an + Vector2(-18, -20), an + Vector2(18, 20), Color(PaperKit.RED, 0.9), 3.4, true)
		# huts on the island, lit
		for hx in [222.0, 246.0, 268.0]:
			var by := 98.0 + absf(hx - 246.0) * 0.1
			for i in 4: draw_circle(Vector2(hx, by - 8), 16.0 - i * 3.2, Color(sod, 0.10 + 0.07 * i))
			draw_rect(Rect2(hx - 8, by - 13, 16, 13), Color("#E8DDBB")); draw_rect(Rect2(hx - 8, by - 13, 16, 13), ink, false, 2.0)
			draw_colored_polygon(PackedVector2Array([Vector2(hx - 11, by - 13), Vector2(hx, by - 24), Vector2(hx + 11, by - 13)]), Color("#B5700F")); draw_polyline(PackedVector2Array([Vector2(hx - 11, by - 13), Vector2(hx, by - 24), Vector2(hx + 11, by - 13)]), ink, 2.0, true)
			draw_rect(Rect2(hx - 3, by - 10, 6, 6), sod)
