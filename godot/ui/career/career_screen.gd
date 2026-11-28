class_name CareerScreen
extends Control
## Career "The Utility": the full-screen district view. Top: the year / quarter, the forty-quarter timeline, the End quarter button and the cash and SAIDI / SAIFI readouts.
## Left: the district map and, under it, the picked section / feeder / primary. Right: the drawer with the project board (cards with cost, lead time and the engine's
## "why this helps"), the running projects and the connection requests. Sheets (incidents, quarter report, annual review, ending) are paper dockets (career_sheets.gd).
## Display and input only: every number is the engine's `career`, `careerBoard` and `careerQuote` queries, every change an engine action through app.b.act.

const KIND_TARGET := {"reconductor": "section", "harden": "feeder", "remoteSwitch": "section", "newFeeder": "feeder", "newTransformer": "primary", "tieSwitch": "feeder", "recloser": "feeder",
	"vegetation": "feeder", "regulator": "feeder", "battery": "feeder", "demandResponse": "feeder", "replaceAssets": "asset"}

## 1.13: text straight on the brown drawer (not on a paper card) in light ink; dark ink there was unreadable
const DRAWER_INK := Color("#E8D9A8", 0.85)

func _ink() -> Color: return GridTheme.G_TEXT if CareerKit.glass() else GridTheme.PAPER_INK
func _bad() -> Color: return GridTheme.BAD if CareerKit.glass() else CareerKit.INK_BAD

func _dlbl(text: String, size: int, kind := "sans") -> Label:   # bypasses CareerKit.ink, which turns every colour to paper ink
	var l := GridTheme.label(text, size, Color(GridTheme.G_TEXT, 0.85) if CareerKit.glass() else DRAWER_INK, kind)
	if kind == "sans": l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
var app: CbApp
var d: Dictionary = {}
var board: Dictionary = {}
var sel: Dictionary = {}
## Board stability (1.4 testers misclicked: a Start re-sorted the cards and pulled the next one under the pointer). Until the quarter or the
## selection changes, the card order is kept and whatever was started stays in place as a "Started" placeholder of the same height.
var _held := {}            ## "kind|target" or "fix|asset" -> height of the card/row that was started
var _held_t := -1          ## the quarter _held belongs to
var _order: Array = []     ## the board's kind order for _order_key
var _order_key := ""
var _rows_prev: Array = [] ## the worst-asset card's row ids as last shown (plant and sections), for the same order after a Start
var tab := "board"
var colour := "load"
var msg := ""
var msg_good := true
var compact := false
var map: CareerMap
var timeline: CareerTimeline
var bar_saidi: CareerBar
var alarm_note: PanelContainer
var alarm_lbl: Label   ## 1.7: "SAIDI is heading for ... strike 2 of 3" on the main screen, not only in the quarter report
var bar_saifi: CareerBar
var year_lbl: Label
var charter_lbl: Label   ## the district's charter (DESIGN-1.3) under the year, and 'this week' for the weekly district
var end_btn: Button
var info_box: VBoxContainer
var tab_row: HBoxContainer
var drawer_body: VBoxContainer
var drawer_sc: ScrollContainer
var drawer: PanelContainer
var tool_row: HBoxContainer
var stat_box: HBoxContainer
var stats := {}
var _bg: ColorRect
var _busy := false
var district: District3D = null   ## the 3D look: the district behind the map (main.gd builds it; a phone, the classic look and the tests have none)
var _hidden: Array = []           ## what the 3D district covered while this screen is open: [Control or Node3D], shown again on leaving
var _wv_was := true
var _cam_spec_done := false

func T(key: String) -> String: return TranslationServer.translate(key)

func _init() -> void:
	name = "career"; set_meta("cb_modal", true); mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and app != null and is_instance_valid(app) and _bg != null:
		_bleed()
		if district != null: district.canvas_size = size; _fit_district.call_deferred()

func _exit_tree() -> void: _leave_3d()

## The district stands behind the map: the world layer, the title and the other 3D scenes are put away while this screen is open, the district is shown, and the
## screen's own ground is clear glass (the strip, the info box and the drawer stay glass panels over the world).
func _enter_3d() -> void:
	var dn = app.get("district3d")
	if not (dn is District3D) or CbLayout.kind == "phone" or not CareerKit.glass(): return
	district = dn
	var wv = app.get("grid_world")
	if wv != null:
		for n in [wv.prov3d, wv.bay3d, wv.bench3d, wv.stage3d]:
			if n != null and n.visible: _hidden.append(n); n.visible = false; if n.cam != null: n.cam.current = false
		_wv_was = wv.visible; wv.visible = false; wv.career3d = true
	for n in app.root.get_children():   # the title and any other full-screen sheet under this one
		if n != self and n is Control and n.has_meta("cb_modal") and n.visible: _hidden.append(n); n.visible = false
	district.canvas_size = size; district.visible = true
	_bg.color = Color(0, 0, 0, 0)

func _leave_3d() -> void:
	if district == null: return
	var dn := district; district = null
	if is_instance_valid(dn):
		dn.visible = false
		if dn.cam != null: dn.cam.current = false
	for n in _hidden: if is_instance_valid(n): n.visible = true
	_hidden.clear()
	if app != null and is_instance_valid(app):
		var wv = app.get("grid_world")
		if wv != null and is_instance_valid(wv):
			wv.career3d = false; wv.visible = _wv_was
			if not wv.model.is_empty(): wv.set_model(wv.model)

func _fit_district() -> void:
	if district != null and is_instance_valid(district) and map != null and is_instance_valid(map): district.fit_to(map.get_global_rect())

## The district follows the screen's data: the colour mode, the incidents, the structure.
func _district_sync() -> void:
	if district == null: return
	district.set_district(d, colour, map.hot)
	_fit_district()
	if not _cam_spec_done and OS.get_environment("CB_CAM") != "": _cam_spec_done = true; district.set_camera_spec(OS.get_environment("CB_CAM"))   # desk QA: a camera for the screenshot

func _bleed() -> void:
	var ins: Vector4 = app.inset
	_bg.offset_left = -ins.x; _bg.offset_top = -ins.y; _bg.offset_right = ins.z; _bg.offset_bottom = ins.w

func close() -> void:
	Career.save(app)
	queue_free()

# ---- build ----------------------------------------------------------------------------------------------------------------------
func build() -> void:
	GridUi.load_strings()
	theme = GridTheme.theme()
	compact = PaperKit.compact(app)
	_bg = ColorRect.new(); _bg.color = GridTheme.NIGHT; _bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); _bg.mouse_filter = Control.MOUSE_FILTER_STOP; add_child(_bg); _bleed()
	_enter_3d()
	var m := MarginContainer.new(); m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for k in ["left", "right", "top", "bottom"]: m.add_theme_constant_override("margin_" + k, 6 if compact else 12)
	add_child(m)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 5 if compact else 9); m.add_child(col)
	col.add_child(_build_strip())
	var body := HBoxContainer.new(); body.add_theme_constant_override("separation", 6 if compact else 10); body.size_flags_vertical = Control.SIZE_EXPAND_FILL; col.add_child(body)
	var left := VBoxContainer.new(); left.add_theme_constant_override("separation", 4 if compact else 8); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_child(left)
	tool_row = _build_tools()
	if district != null:   # over the world the row is a glass strip, so its words read on the fields
		var tp := PanelContainer.new(); tp.name = "ToolsGlass"; tp.add_theme_stylebox_override("panel", GridTheme.glass_sb(0.62, 4, 8.0)); tp.add_child(tool_row); left.add_child(tp)
	else: left.add_child(tool_row)
	map = CareerMap.new(); map.compact = compact; map.size_flags_vertical = Control.SIZE_EXPAND_FILL; map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map.picked.connect(_on_pick); map.d3 = district; left.add_child(map)
	var ip := PanelContainer.new(); ip.name = "InfoPanel"; ip.add_theme_stylebox_override("panel", GridTheme.glass_sb(0.72, 4, 14.0) if CareerKit.glass() else CareerKit.sb(GridTheme.PAPER, Color(GridTheme.PAPER_INK, 0.35), 1, 4, 14.0, 8.0)); ip.custom_minimum_size.y = 72.0 if compact else 104.0; left.add_child(ip)   # a fixed height: the map must not jump when a pick changes the text
	info_box = VBoxContainer.new(); info_box.add_theme_constant_override("separation", 2); ip.add_child(info_box)
	drawer = PanelContainer.new(); drawer.name = "Drawer"; drawer.add_theme_stylebox_override("panel", GridTheme.glass_sb(0.72, 4, 10.0) if CareerKit.glass() else CareerKit.sb(Color("#4A3524"), Color("#2C1E12"), 3, 10, 10.0, 10.0))   # 1.9: a clipboard of paper cards
	drawer.custom_minimum_size.x = clampf(app.vw() * 0.34, 380.0, 420.0) if compact else clampf(app.vw() * 0.29, 480.0, 600.0)
	body.add_child(drawer)
	var dv := VBoxContainer.new(); dv.add_theme_constant_override("separation", 6); drawer.add_child(dv)
	tab_row = HBoxContainer.new(); tab_row.add_theme_constant_override("separation", 6); dv.add_child(tab_row)
	drawer_sc = ScrollContainer.new(); drawer_sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; drawer_sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; dv.add_child(drawer_sc)
	drawer_body = VBoxContainer.new(); drawer_body.add_theme_constant_override("separation", 6); drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; drawer_sc.add_child(drawer_body)
	refresh()

## 1.10: the top of the Career is a paper wall planner, not a dark strip of numbers: the year and district in ink, the ten-year planner,
## cash as a ledger line, the two reliability targets as gauges with their plain names, the rest small. The alarm is a pinned note.
func _build_strip() -> Control:
	var pc := PanelContainer.new(); pc.name = "Strip"
	var gl := CareerKit.glass()
	var st := CareerKit.sb(GridTheme.PAPER, Color("#6B4A2A"), 2, 4, 14.0, 4.0 if compact else 8.0); st.shadow_color = Color(0, 0, 0, 0.4); st.shadow_size = 5; st.shadow_offset = Vector2(0, 3)
	if gl: st = GridTheme.glass_sb(0.72, 4, 14.0); st.content_margin_top = 4.0 if compact else 8.0; st.content_margin_bottom = st.content_margin_top
	pc.add_theme_stylebox_override("panel", st)
	var ink := GridTheme.G_TEXT if gl else GridTheme.PAPER_INK
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 2 if compact else 6); pc.add_child(v)
	var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 14); v.add_child(r1)
	var yv := VBoxContainer.new(); yv.add_theme_constant_override("separation", 0); yv.alignment = BoxContainer.ALIGNMENT_CENTER; r1.add_child(yv)
	year_lbl = GridTheme.label("", 24 if compact else 32, GridTheme.SODIUM if gl else Color("#8A3A1E"), "title")
	year_lbl.name = "YearLabel"; year_lbl.custom_minimum_size.x = 190 if compact or app.vw() < 1500.0 else 280; yv.add_child(year_lbl)
	charter_lbl = GridTheme.label("", 16, Color(ink, 0.75), "semi")
	charter_lbl.name = "CharterLabel"; yv.add_child(charter_lbl)
	timeline = CareerTimeline.new(); timeline.compact = compact; timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL; timeline.custom_minimum_size.y = 44 if compact else 54; r1.add_child(timeline)
	end_btn = CareerKit.btn(T("CAR_END_Q"), true, _on_end, 18 if compact else 21) if gl else PaperKit.btn(T("CAR_END_Q"), true, _on_end, 18 if compact else 21); end_btn.name = "EndQuarter"; r1.add_child(end_btn)
	var narrow := compact or app.vw() < 1500.0   # 1280 wide: the ledger row must fit beside nothing (End quarter was pushed off the edge)
	stat_box = HBoxContainer.new(); stat_box.add_theme_constant_override("separation", 12 if narrow else 28); v.add_child(stat_box)
	stats["cash"] = _stat(T("CAR_CASH"), 150 if narrow else 220, true)
	stats["owed"] = GridTheme.label("", 16, Color(ink, 0.62), "mono"); (stats.cash as Label).get_parent().add_child(stats.owed)
	stats["standing"] = GridTheme.label("", 14, Color(ink, 0.62), "mono")
	stats.standing.name = "Standing"; stats.standing.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; stats.standing.custom_minimum_size.x = 140 if narrow else 300   # wraps inside the cash column (unwrapped it widened the strip past a phone)
	(stats.cash as Label).get_parent().add_child(stats.standing)
	bar_saidi = CareerBar.new(); bar_saidi.compact = compact; bar_saidi.name = "BarSaidi"; bar_saidi.ink = ink; bar_saidi.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stat_box.add_child(bar_saidi)
	bar_saifi = CareerBar.new(); bar_saifi.compact = compact; bar_saifi.name = "BarSaifi"; bar_saifi.ink = ink; bar_saifi.size_flags_horizontal = Control.SIZE_EXPAND_FILL; stat_box.add_child(bar_saifi)
	stats["health"] = _stat(T("CAR_HEALTH"), 120 if narrow else 190)
	stats["crews"] = _stat(T("CAR_CREWS"), 80 if narrow else 110)
	stats["met"] = _stat(T("CAR_MET"), 60 if narrow else 90)
	stats["score"] = _stat(T("CAR_SCORE"), 50 if narrow else 80)
	# the pinned note: one line, what to do; the long explanation is its tooltip
	alarm_note = PanelContainer.new(); alarm_note.name = "AlarmNote"; alarm_note.visible = false; alarm_note.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ns := CareerKit.sb(Color("#FFF1A8"), Color("#B03A2E"), 2, 2, 14.0, 6.0); ns.shadow_color = Color(0, 0, 0, 0.35); ns.shadow_size = 3; ns.shadow_offset = Vector2(1, 2)
	if gl: ns = CareerKit.sb(Color(GridTheme.BAD, 0.14), GridTheme.BAD, 1, 4, 14.0, 6.0)
	alarm_note.add_theme_stylebox_override("panel", ns); alarm_note.mouse_filter = Control.MOUSE_FILTER_PASS
	alarm_lbl = GridTheme.label("", 18 if not compact else 16, GridTheme.G_TEXT if gl else Color("#8A1F12"), "semi")
	alarm_lbl.name = "StrikeAlarm"; alarm_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	alarm_note.add_child(alarm_lbl); v.add_child(alarm_note)
	return pc

func _stat(cap: String, minw: float, big := false) -> Label:
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 0); v.custom_minimum_size.x = minw; stat_box.add_child(v)
	v.add_child(GridTheme.label(cap, 16, Color(_ink(), 0.62), "mono"))
	var l := GridTheme.label("", (24 if big else 18) if compact else (30 if big else 20), _ink(), "semi"); v.add_child(l)
	return l

func _build_tools() -> HBoxContainer:
	var hb := HBoxContainer.new(); hb.name = "Tools"; hb.add_theme_constant_override("separation", 6 if compact else 10)
	hb.add_child(CareerKit.lbl(T("CAR_COLOUR_BY"), 14, Color(GridTheme.TEXT, 0.7), "mono"))
	hb.set_meta("chips", HBoxContainer.new())
	var chips: HBoxContainer = hb.get_meta("chips"); chips.add_theme_constant_override("separation", 4); hb.add_child(chips)
	var leg := CareerKit.lbl("", 13, Color(GridTheme.TEXT, 0.6), "sans", true); leg.name = "Legend"; leg.clip_text = true; leg.autowrap_mode = TextServer.AUTOWRAP_OFF; leg.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(leg)
	var cp := CareerKit.btn(T("CAR_COPY_CODE"), false, _copy_code, 14); cp.name = "CopyCode"; hb.add_child(cp)
	var lv := CareerKit.btn(T("CAR_LEAVE"), false, func(): close(), 14); lv.name = "Leave"; hb.add_child(lv)
	return hb

func _tools_refresh() -> void:
	var chips: HBoxContainer = tool_row.get_meta("chips")
	_clear(chips)
	for o in [["load", T("CAR_BY_LOAD")], ["health", T("CAR_BY_HEALTH")]]:
		var c := CareerKit.chip(str(o[1]), colour == str(o[0]), func(): colour = str(o[0]); map.mode = colour; _district_sync(); _tools_refresh(); map.queue_redraw(), 14); c.name = "Colour_" + str(o[0]); chips.add_child(c)
	var leg: Label = tool_row.get_node("Legend")
	leg.text = T("CAR_LEG_LOAD") if colour == "load" else T("CAR_LEG_HEALTH")
	leg.text += "  " + T("CAR_LEG_BADGES")
	leg.tooltip_text = leg.text; leg.mouse_filter = Control.MOUSE_FILTER_STOP   # 1128c C11: the key clips at narrow widths; the whole text is on hover
	if compact: leg.visible = false; tool_row.tooltip_text = leg.text   # the phone has no room for the key: it is the row's tooltip

func _copy_code() -> void:
	DisplayServer.clipboard_set(str(d.get("code", ""))); _say(T("CAR_CODE_COPIED"), true)

static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c); c.queue_free()

# ---- state ----------------------------------------------------------------------------------------------------------------------
func _say(text: String, good: bool) -> void:
	msg = text; msg_good = good; _build_info()

## One engine action; the result sentence goes under the map, the career code is saved, every panel refreshes.
func act(name_: String, args: Array) -> Dictionary:
	var fo := get_viewport().gui_get_focus_owner(); var fname := str(fo.name) if fo != null and is_ancestor_of(fo) else ""
	var r: Dictionary = app.b.act(name_, args)
	msg = str(r.get("message", "")); msg_good = bool(r.get("ok", false))
	# 1.7: money sounds like money: a register for a project started, the ledger closing at the end of a quarter
	app.sfx(("spend" if name_ == "careerProject" else ("quarter" if name_ == "careerEndQuarter" else "confirm")) if msg_good else "bad")
	Career.save(app)
	refresh()
	if fname != "" and CbKit.pad_mode: _refocus.call_deferred(fname)   # 1.8 pad: the rebuilt board keeps the focus on the same control
	return r

func _refocus(fname: String) -> void:
	var n := find_child(fname, true, false)
	if n is Control and (n as Control).is_visible_in_tree(): (n as Control).grab_focus()

## 1.8 pad: LB / RB walk the map's pickables (the primaries, then every feeder section) since a pad cannot tap the map.
func pickables() -> Array:
	var out: Array = []
	for p in d.get("primaries", []): out.append({"type": "primary", "id": str(p.id)})
	for f in d.get("feeders", []):
		for sct in f.sections: out.append({"type": "section", "id": str(sct.id), "feeder": str(f.id)})
	return out

func pad_walk(dir: int) -> void:
	var all := pickables()
	if all.is_empty(): return
	var at := -1
	for i in all.size():
		if str(all[i].type) == str(sel.get("type", "")) and str(all[i].id) == str(sel.get("id", "")): at = i
	_on_pick(all[posmod(at + dir, all.size()) if at >= 0 else (0 if dir > 0 else all.size() - 1)])

func _input(e: InputEvent) -> void:
	if not (e is InputEventJoypadButton) or not e.pressed or not CbPad.enabled or app.modal() != self: return
	var jb := e as InputEventJoypadButton
	if jb.button_index == JOY_BUTTON_LEFT_SHOULDER or jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		pad_walk(-1 if jb.button_index == JOY_BUTTON_LEFT_SHOULDER else 1); get_viewport().set_input_as_handled()

func refresh() -> void:
	var q = app.b.q("career")
	if not (q is Dictionary) or not q.get("active", false): queue_free(); return
	d = q
	var bq = app.b.q("careerBoard"); board = bq if bq is Dictionary else {}
	var ended: bool = d.get("ending") != null
	year_lbl.text = T("CAR_ED_TITLE") if ended else T("CAR_YEAR_Q") % [int(d.year), int(d.quarter)]
	charter_lbl.text = (T("CAR_WEEKLY_TAG") % [str(d.get("charterName", "")), str(d.get("weekly", ""))]) if str(d.get("weekly", "")) != "" else str(d.get("charterName", ""))
	charter_lbl.tooltip_text = str(d.get("charterText", ""))
	timeline.set_data(d)
	var inc := str(d.phase) == "incident"
	end_btn.text = T("CAR_END_Q_INC") if inc else T("CAR_END_Q"); end_btn.disabled = ended
	(stats.cash as Label).text = str(d.cashText); (stats.cash as Label).add_theme_color_override("font_color", _ink() if float(d.cash) >= 0.0 else _bad())
	(stats.cash as Label).tooltip_text = T("CAR_CASH_LIM") % str(d.creditText)
	if bool(d.get("borrowing", false)): (stats.cash as Label).text = T("CAR_CASH_DEBT") % str(d.cashText)
	(stats.owed as Label).text = T("CAR_CASH_OWED") % [str(d.get("owedText", "")), str(d.get("cashAfterText", ""))] if str(d.get("owedText", "")) != "" and float(d.get("committedQ", 0.0)) > 0.0 else ""
	(stats.standing as Label).text = "\n".join([_keep_items(str(d.get("standingText", ""))), str(d.get("ownersDueText", ""))].filter(func(x): return x != "")); (stats.standing as Label).visible = not compact   # a phone has no room for a third line: there it is the cash tooltip
	if compact and (stats.standing as Label).text != "": (stats.cash as Label).tooltip_text += "\n" + (stats.standing as Label).text
	(stats.owed as Label).add_theme_color_override("font_color", Color(_ink(), 0.62) if not str(d.get("cashAfterText", "")).begins_with("-") else _bad())
	bar_saidi.set_vals(T("CAR_SAIDI"), float(d.ytd.saidi), float(d.targets.saidi), float(d.expected.saidi), 1)
	var al := str(d.get("alarmDo", "")); alarm_lbl.text = al; alarm_note.visible = al != ""; alarm_note.tooltip_text = str(d.get("alarmText", "")); alarm_lbl.tooltip_text = alarm_note.tooltip_text
	alarm_lbl.add_theme_color_override("font_color", (GridTheme.G_TEXT if CareerKit.glass() else Color("#8A1F12")) if bool(d.get("alarmStrike", false)) else (GridTheme.WARN if CareerKit.glass() else CareerKit.INK_WARN))
	bar_saifi.set_vals(T("CAR_SAIFI"), float(d.ytd.saifi), float(d.targets.saifi), float(d.expected.saifi), 2)
	(stats.health as Label).text = T("CAR_HEALTH_VAL") % [CareerKit.num(float(d.health), 1), CareerKit.num(float(d.startHealth), 1)]
	(stats.crews as Label).text = T("CAR_CREWS_VAL") % [int(d.crewsFree), int(d.crews)]
	(stats.met as Label).text = T("CAR_MET_VAL") % int(d.yearsMet)
	(stats.score as Label).text = CareerKit.num(float(d.score), 0)
	map.mode = colour; map.sel = sel; map.hot = (d.incidents as Array).map(func(x): return str(x.feederId)) if inc else []
	_district_sync()
	map.set_data(d)
	_tools_refresh(); _build_info(); _build_tabs(); _build_drawer()

func _on_pick(s: Dictionary) -> void:
	sel = s; msg = ""
	app.sfx("click")
	map.sel = sel; map.queue_redraw(); _build_info(); _build_drawer(true)

func _on_end() -> void:
	if _busy: return
	if str(d.phase) == "incident": CareerSheets.incidents(self); return
	var before := (d.reviews as Array).size()
	var r := act("careerEndQuarter", [true])
	if not bool(r.get("ok", false)): return
	if str(d.phase) == "incident": CareerSheets.incidents(self); return
	CareerSheets.after_quarter(self, before)

## Called by the incident sheet's Done button: settle the quarter, then the report chain.
func settle() -> void:
	var before := (d.reviews as Array).size()
	var r := act("careerEndQuarter", [true])
	if bool(r.get("ok", false)): CareerSheets.after_quarter(self, before)

# ---- the picked thing -----------------------------------------------------------------------------------------------------------
func feeder_of(fid: String) -> Dictionary:
	var i := CareerKit.find_id(d.get("feeders", []), fid)
	return d.feeders[i] if i >= 0 else {}

func section_of(sid: String) -> Dictionary:
	for f in d.get("feeders", []):
		for s in f.sections:
			if str(s.id) == sid: return s
	return {}

func primary_of(pid: String) -> Dictionary:
	var i := CareerKit.find_id(d.get("primaries", []), pid)
	return d.primaries[i] if i >= 0 else {}

func _asset_line(a: Dictionary, label: String) -> String:
	var st := T("CAR_INSPECTED") if bool(a.inspected) else T("CAR_ESTIMATE")
	if bool(a.failed): st = (T("CAR_FAILED") % int(a.outQ)) if float(a.outQ) > 0.0 else T("CAR_PATCHED")   # a failed transformer is out; a failed line section was patched and awaits a proper fix
	return T("CAR_ASSET_HEALTH") % [label, CareerKit.num(float(a.health), 1), st]

func _build_info() -> void:
	if info_box == null: return
	_clear(info_box)
	var was := CareerKit.paper; CareerKit.paper = true
	_build_info_body()
	CareerKit.paper = was

func _build_info_body() -> void:
	var sz := 14 if compact else 16
	if msg != "":
		var ml := CareerKit.lbl(msg, sz, GridTheme.GOOD if msg_good else GridTheme.BAD, "semi", true); ml.name = "Message"; ml.max_lines_visible = 2 if compact else 3; ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; info_box.add_child(ml)
	var t := str(sel.get("type", ""))
	if t == "section":
		var sec := section_of(str(sel.id)); var f := feeder_of(str(sel.get("feeder", "")))
		if sec.is_empty() or f.is_empty(): sel = {}; _build_info(); return
		var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); info_box.add_child(hb)
		var tv := VBoxContainer.new(); tv.add_theme_constant_override("separation", 1); tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(tv)
		tv.add_child(CareerKit.lbl(T("CAR_SEC_TITLE") % str(sec.id), sz + 3, GridTheme.SODIUM, "semi"))
		tv.add_child(CareerKit.lbl(T("CAR_SEC_INFO_CABLE" if str(f.get("kind", "")) == "cable" else "CAR_SEC_INFO") % [CareerKit.num(float(sec.km), 1), str(sec.conductor), T("CAR_DEV_" + str(sec.device))] + "  " + _asset_line(sec, str(sec.assetId)), sz - 1, GridTheme.TEXT, "sans", true))
		if not compact: tv.add_child(CareerKit.lbl(_feeder_text(f), sz - 1, Color(GridTheme.TEXT, 0.8), "sans", true))
		var ib := CareerKit.btn(T("CAR_INSPECT") % str(sec.assetId), false, func(): act("careerInspect", [str(sec.assetId)]), 14); ib.name = "Inspect"; ib.size_flags_vertical = Control.SIZE_SHRINK_CENTER; hb.add_child(ib)
	elif t == "primary":
		var p := primary_of(str(sel.id))
		if p.is_empty(): sel = {}; _build_info(); return
		info_box.add_child(CareerKit.lbl(T("CAR_PRIMARY_INFO") % [str(p.name), CareerKit.num(float(p.peakMva), 1), CareerKit.num(float(p.firmMva), 1), CareerKit.num(float(p.firmMarginPct), 0)], sz, GridTheme.TEXT, "sans", true))
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); info_box.add_child(row)
		var assets: Array = []
		for u in p.units: assets.append([str(u.id), T("CAR_UNIT") % [str(u.id), CareerKit.num(float(u.ratingMva), 0)], u])
		assets.append([str(p.switchgear.id), T("CAR_SWGEAR") % str(p.id), p.switchgear])
		if str(sel.get("asset", "")) == "": sel["asset"] = str(assets[0][0])
		for a in assets:
			var aid := str(a[0])
			var c := CareerKit.chip("%s  %s" % [str(a[1]), CareerKit.num(float(a[2].health), 1)], str(sel.get("asset", "")) == aid, func(): sel["asset"] = aid; _build_info(); _build_drawer(), 13 if compact else 14); c.name = "Asset_" + aid; row.add_child(c)
		for a in assets:
			if str(a[0]) == str(sel.get("asset", "")):
				var rr := HBoxContainer.new(); rr.add_theme_constant_override("separation", 10); info_box.add_child(rr)
				var al := CareerKit.lbl(_asset_line(a[2], str(a[0])), sz - 1, GridTheme.TEXT, "sans", true); rr.add_child(al)
				var ib2 := CareerKit.btn(T("CAR_INSPECT") % str(a[0]), false, func(): act("careerInspect", [str(a[0])]), 14); ib2.name = "Inspect"; rr.add_child(ib2)
	else:
		if msg == "": info_box.add_child(CareerKit.lbl(T("CAR_SEL_NONE_PAD") if CbKit.pad_mode else T("CAR_SEL_NONE"), sz, Color(GridTheme.TEXT, 0.75), "sans", true))

func _feeder_text(f: Dictionary) -> String:
	var s: String = T("CAR_FDR_INFO") % [str(f.id), str(primary_of(str(f.primaryId)).get("name", f.primaryId)), int(f.customers), int(f.peakKw), CareerKit.num(float(f.loadingPct), 0), CareerKit.num(float(f.minV), 2), CareerKit.num(float(f.saidi), 0), CareerKit.num(float(f.saifi), 2)]
	if float(f.get("shedMin", 0)) > 0.5: s += " " + T("CAR_FDR_SHED") % CareerKit.num(float(f.shedMin), 0)   # 1.12 past the emergency rating: rota cuts at the peak
	var has: Array = []
	if bool(f.tie): has.append(T("CAR_B_tie"))
	if bool(f.recloser): has.append(T("CAR_B_recloser"))
	if bool(f.get("hardened", false)): has.append(T("CAR_B_harden"))
	if bool(f.regulator): has.append(T("CAR_B_regulator"))
	if float(f.batteryKw) > 0.0: has.append(T("CAR_B_battery") % int(f.batteryKw))
	if float(f.drKw) > 0.0: has.append(T("CAR_B_dr") % int(f.drKw))
	s += "  " + (T("CAR_HAS") % ", ".join(has) if not has.is_empty() else T("CAR_HAS_NONE"))
	if bool(f.vViolation): s += "  " + T("CAR_VVIOL")
	return s

# ---- the drawer -----------------------------------------------------------------------------------------------------------------
func _build_tabs() -> void:
	_clear(tab_row)
	var nrun := (d.projects as Array).filter(func(p): return str(p.status) == "building" or str(p.status) == "active").size()
	var nreq := (d.requests as Array).size()
	for o in [["board", T("CAR_TAB_BOARD")], ["run", T("CAR_TAB_RUN") % nrun], ["req", T("CAR_TAB_REQ") % nreq]]:
		var c := CareerKit.chip(str(o[1]), tab == str(o[0]), func(): tab = str(o[0]); _build_tabs(); _build_drawer(true), 14 if compact else 16); c.name = "Tab_" + str(o[0]); tab_row.add_child(c)

func _build_drawer(to_top := false) -> void:
	var keep := 0 if to_top else drawer_sc.scroll_vertical
	_clear(drawer_body)
	var was := CareerKit.paper; CareerKit.paper = true
	match tab:
		"run": _run_tab()
		"req": _req_tab()
		_: _board_tab()
	CareerKit.paper = was
	drawer_sc.set_deferred("scroll_vertical", keep)

## The target string a project kind takes for what is picked on the map ("" when the pick is the wrong sort of thing).
func target_for(kind: String) -> String:
	var need: String = KIND_TARGET.get(kind, "section"); var t := str(sel.get("type", ""))
	if t == "section":
		match need:
			"section": return str(sel.id)
			"feeder": return str(sel.get("feeder", ""))
			"asset": return str(section_of(str(sel.id)).get("assetId", sel.id))
	elif t == "primary":
		match need:
			"primary": return str(sel.id)
			"asset": return str(sel.get("asset", ""))
	return ""

## The assets whose replacement buys the most SAIDI: the board's own quotes for the worn and patched ones, best first.
func worst_assets(limit := 4) -> Array:
	var cand: Array = []
	for f in d.feeders:
		for s in f.sections:
			if bool(s.failed) or float(s.health) < 6.0: cand.append([str(s.id), float(s.health) - (2.0 if bool(s.failed) else 0.0)])
	for p in d.primaries:
		for u in p.units: if bool(u.failed) or float(u.health) < 6.0: cand.append([str(u.id), float(u.health)])
		if float(p.switchgear.health) < 6.0: cand.append([str(p.switchgear.id), float(p.switchgear.health)])
	cand.sort_custom(func(a, b): return float(a[1]) < float(b[1]))
	var out: Array = []
	for c in cand.slice(0, 16):
		var q = app.b.q("careerQuote", ["replaceAssets", str(c[0])])
		if q is Dictionary and bool(q.get("ok", false)) and float(q.dSaidi) <= -1.0: out.append({"id": str(c[0]), "dSaidi": float(q.dSaidi), "capexText": str(q.capexText), "capex": float(q.capex)})
	out.sort_custom(func(a, b): return float(a.dSaidi) < float(b.dSaidi))
	return out.slice(0, limit)

func _asset_pick(id: String) -> Dictionary:
	if id.contains("."): return {"type": "section", "id": id, "feeder": id.split(".")[0]}
	return {"type": "primary", "id": id.split("-")[0], "asset": id}

func _worst_card(sz: int) -> void:
	var v := CareerKit.card(drawer_body); v.get_parent().name = "WorstCard"
	v.add_child(CareerKit.lbl(T("CAR_WORST"), sz + 1, GridTheme.SODIUM, "semi", true))
	# substation plant first: its failure costs an emergency replacement and a primary outage, which expected SAIDI does not show
	var entries := {}; var fresh: Array = []
	for r in (d.get("plantRisk", []) as Array).slice(0, 2): entries[str(r.id)] = {"plant": true, "r": r}; fresh.append(str(r.id))
	for r in worst_assets(3 if compact else 4): entries[str(r.id)] = {"plant": false, "r": r}; fresh.append(str(r.id))
	# after a Start this quarter: the rows keep the order they had, the started one stays as a placeholder (no row slides under the pointer)
	var order: Array = []
	if not _held.is_empty():
		for id in _rows_prev:
			if _held.has("fix|" + str(id)) or entries.has(str(id)): order.append(str(id))
	for id in fresh:
		if not order.has(id): order.append(id)
	_rows_prev = order
	if order.is_empty(): v.add_child(CareerKit.lbl(T("CAR_WORST_NONE"), sz - 1, Color(GridTheme.TEXT, 0.6), "sans", true)); return
	for id in order:
		if not entries.has(id):
			_held_placeholder(v, "fix|" + id, id); continue
		var e: Dictionary = entries[id]; var r: Dictionary = e.r
		# 1.14 each asset is a card (coordinator: "the board is still a list of identical rows"): a picture of the thing, its health as a gauge, the gain in
		# plain words, the price and Start. Tapping the card picks the asset on the map; picking it on the map outlines its card.
		var plant := bool(e.plant)
		var a := _asset_of(id)
		var health := float(r.health) if plant else float(a.get("health", 0.0))
		var chosen: bool = (str(sel.get("type", "")) == "section" and str(sel.get("id", "")) == id) or (str(sel.get("type", "")) == "primary" and (str(sel.get("asset", "")) == id or (not sel.has("asset") and id.begins_with(str(sel.get("id", "")) + "-"))))
		var pc := PanelContainer.new(); pc.name = "AssetCard_" + id
		var stb := CareerKit.sb(Color("#E6DCC2"), GridTheme.SODIUM if chosen else Color(CareerKit.INK_AMBER, 0.35), 3 if chosen else 1, 6, 8.0, 6.0)
		if CareerKit.glass(): stb = CareerKit.glass_card_sb(chosen, 8.0, 6.0)
		pc.add_theme_stylebox_override("panel", stb); v.add_child(pc)
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); pc.add_child(row)
		var icon := CareerAssetIcon.new(); icon.col = CareerKit.health_col(health)
		icon.kind = ("tx" if id.contains("-T") else "switchgear") if plant else ("joint" if str(_feeder_kind(id)) == "cable" else "pole")
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(icon)
		var mid := VBoxContainer.new(); mid.add_theme_constant_override("separation", 2); mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(mid)
		var pick: Button
		if plant:
			pick = CareerKit.btn(T("CAR_ASSET_PLANT") % [id, T("CAR_KIND_TX") if id.contains("-T") else T("CAR_KIND_SG")], false, func(): _on_pick(_asset_pick(id)), sz - 1); pick.name = "RiskPick_" + id
		else:
			pick = CareerKit.btn(T("CAR_ASSET_LINE") % [id, str(a.get("conductor", "")), T("CAR_WORST_PATCH") if bool(a.get("failed", false)) and float(a.get("outQ", 0.0)) <= 0.0 else ""], false, func(): _on_pick(_asset_pick(id)), sz - 1); pick.name = "WorstPick_" + id
		pick.flat = true; pick.alignment = HORIZONTAL_ALIGNMENT_LEFT; pick.clip_text = true; pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL; mid.add_child(pick)
		var gauge := CareerHealthGauge.new(); gauge.health = health; mid.add_child(gauge)
		var words := T("CAR_ASSET_RISK_WORDS") % [CareerKit.num(float(r.pFail), 0), str(r.emergencyText)] if plant else T("CAR_ASSET_GAIN_WORDS") % CareerKit.num(absf(float(r.dSaidi)), 1)
		mid.add_child(CareerKit.lbl(words, sz - 2, GridTheme.BAD if plant else GridTheme.GOOD, "sans", true))
		var right := VBoxContainer.new(); right.add_theme_constant_override("separation", 4); right.size_flags_vertical = Control.SIZE_SHRINK_CENTER; row.add_child(right)
		right.add_child(CareerKit.lbl(str(r.get("capexText", "")), sz - 2, GridTheme.TEXT, "mono"))
		var fix := CareerKit.btn(T("CAR_START"), true, func(): _start_held("fix|" + id, pc, "replaceAssets", id), sz - 1); fix.name = "Fix_" + id; right.add_child(fix)

func _feeder_kind(section_id: String) -> String:
	var fi := CareerKit.find_id(d.feeders, section_id.split(".")[0])
	return str(d.feeders[fi].get("kind", "")) if fi >= 0 else ""

func _asset_of(id: String) -> Dictionary:
	for f in d.feeders:
		for s in f.sections: if str(s.id) == id: return s
	for p in d.primaries:
		for u in p.units: if str(u.id) == id: return u
		if str(p.switchgear.id) == id: return p.switchgear
	return {}

## 1.8 the guided first year (the fun critic's lowest score was the Career's first screen: "a spreadsheet for a newcomer"). Quarter 1 shows one
## job (the weakest asset, picked on the map) and End quarter; the readiness card opens in quarter 2, tree cutting in 3, every project in 4.
## "Show every tool now" ends the guide for this session. Quarter 5 on, the board is the full one.
static var guide_all := false
func guided() -> int:
	if guide_all or d.get("ending") != null or int(d.get("t", 99)) >= 4: return -1
	return int(d.t)

func _guide_card(sz: int, gq: int, hidden: int) -> void:
	# 1.9: the quarter's job is a pinned work order, the most readable thing on screen (title 26 px, body 20 px; the rest of the board is 16)
	var pc := PanelContainer.new(); pc.name = "GuideCard"; pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := CareerKit.sb(GridTheme.PAPER, CareerKit.INK_AMBER, 3, 3, 18.0, 14.0); st.shadow_color = Color(0, 0, 0, 0.45); st.shadow_size = 6; st.shadow_offset = Vector2(2, 4)
	if CareerKit.glass(): st = CareerKit.glass_card_sb(true, 18.0, 14.0)
	pc.add_theme_stylebox_override("panel", st); drawer_body.add_child(pc)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 8); pc.add_child(v)
	var tape := ColorRect.new(); tape.visible = not CareerKit.glass(); tape.color = Color("#E8D9A8", 0.85); tape.custom_minimum_size = Vector2(90, 14); tape.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; tape.mouse_filter = Control.MOUSE_FILTER_IGNORE; v.add_child(tape)
	v.add_child(CareerKit.lbl(T("CAR_GUIDE_T") % (gq + 1), 26 if not compact else 22, GridTheme.SODIUM, "title", true))
	var body := ""
	if gq == 0:
		var w := worst_assets(1)
		if not (d.projects as Array).is_empty(): body = T("CAR_GUIDE_Q1_DONE")
		elif w.is_empty(): body = T("CAR_GUIDE_Q1_NONE")
		else: body = T("CAR_GUIDE_Q1") % [str(w[0].id), str(w[0].capexText)]
	elif gq == 2 and str(d.get("charter", "")) == "city": body = T("CAR_GUIDE_Q3_CABLE")   # 1.13: the tree card is hidden in an all-cable district
	else: body = T("CAR_GUIDE_Q%d" % (gq + 1))
	var bl := CareerKit.lbl(body, 20 if not compact else 18, GridTheme.TEXT, "sans", true); bl.name = "GuideText"; v.add_child(bl)
	if hidden > 0: v.add_child(CareerKit.lbl(T("CAR_GUIDE_MORE") % hidden, 16, Color(GridTheme.TEXT, 0.55), "sans", true))
	var all := CareerKit.btn(T("CAR_GUIDE_ALL"), false, func(): guide_all = true; _build_drawer(), 16); all.name = "GuideAll"; all.size_flags_horizontal = Control.SIZE_SHRINK_END; v.add_child(all)

func _board_tab() -> void:
	if int(d.t) != _held_t: _held.clear(); _held_t = int(d.t); _rows_prev = []
	var sz := 14 if compact else 15
	var gq := guided()
	if gq == 0 and sel.is_empty():   # quarter 1: the weakest asset is already picked on the map
		var w := worst_assets(1)
		if not w.is_empty(): sel = _asset_pick(str(w[0].id)); map.sel = sel; map.queue_redraw(); _build_info()
	if gq >= 0:
		var kinds := (board.get("kinds", []) as Array).size()
		var hidden := (0 if gq >= 1 else 1) + (0 if gq >= 2 else 1) + (0 if gq >= 3 else kinds)
		_guide_card(sz, gq, hidden)
		_letters()
		if gq >= 1: _ready_card(sz)
		if gq >= 2: _veg_card()
		_worst_card(sz)
		if gq < 3: return
	else:
		_letters()
		_ready_card(sz)
		_veg_card()
		_worst_card(sz)
	var t := str(sel.get("type", ""))
	var head := T("CAR_BOARD_NONE")
	if t == "section": head = T("CAR_TARGET_IS") % (T("CAR_SEC_TITLE") % str(sel.id))
	elif t == "primary": head = T("CAR_TARGET_IS") % str(primary_of(str(sel.id)).get("name", sel.id))
	var hl := CareerKit.lbl(head, sz, GridTheme.SODIUM if t != "" else Color(GridTheme.TEXT, 0.7), "semi", true); hl.name = "TargetLine"; drawer_body.add_child(hl)
	var okey := "%s|%s|%d" % [str(sel.get("type", "")), str(sel.get("id", "")), int(d.t)]
	var cards: Array = []
	for k in board.get("kinds", []):
		var kind := str(k.kind); var tg := target_for(kind)
		var opt: Dictionary = {}
		for o in k.options:
			if str(o.target) == tg and tg != "": opt = o
		cards.append({"k": k, "target": tg, "opt": opt, "rank": 0 if not opt.is_empty() else (1 if tg != "" else 2)})
	if okey == _order_key and _order.size() == cards.size():   # same selection, same quarter: keep the order the player is looking at
		cards.sort_custom(func(a, b): return _order.find(str(a.k.kind)) < _order.find(str(b.k.kind)))
	else:
		cards.sort_custom(func(a, b): return int(a.rank) < int(b.rank))
		_order = cards.map(func(c): return str(c.k.kind)); _order_key = okey
	for c in cards: _kind_card(c, sz)

## 1.9 letters on the desk: a plan beat from one of the district's people, two honest answers, what each costs. Unanswered, it lapses
## at the end of the quarter (the asker decides alone). The open promise to the hospital stays pinned as a line under it.
func _letters() -> void:
	for p in d.get("promises", []):
		var pl := CareerKit.lbl(str(p), 16, GridTheme.SODIUM, "semi", true); pl.name = "Promise"; drawer_body.add_child(pl)
	for b in d.get("story", []):
		if str(b.on) != "plan": continue
		drawer_body.add_child(StoryCard.make(b, func(opt: String): _answer(str(b.id), opt), compact))

func _answer(id: String, opt: String) -> void:
	var r := act("careerStory", [id, opt])
	if bool(r.get("ok", false)): _say(str(r.get("message", "")), true)

## Start from a card or row, keeping its place: the rebuilt board shows a same-height "Started" placeholder there.
func _start_held(key: String, holder: Control, kind: String, target: String) -> void:
	var h := holder.size.y
	_held[key] = h
	var r := act("careerProject", [kind, target])
	if not bool(r.get("ok", false)): _held.erase(key); _build_drawer()

func _held_placeholder(parent: Control, key: String, label: String) -> bool:
	if not _held.has(key): return false
	var pc := PanelContainer.new(); pc.name = "Held_" + key.replace("|", "_"); pc.custom_minimum_size.y = float(_held[key])
	pc.add_theme_stylebox_override("panel", CareerKit.sb(Color(GridTheme.GOOD, 0.08), Color(GridTheme.GOOD, 0.5), 1, 8, 10.0, 6.0))
	var sl := CareerKit.lbl(T("CAR_STARTED") % label, 14 if compact else 15, GridTheme.GOOD, "semi", true); sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER; sl.size_flags_vertical = Control.SIZE_FILL
	pc.add_child(sl); parent.add_child(pc)
	return true

func _kind_card(c: Dictionary, sz: int) -> void:
	var k: Dictionary = c.k; var kind := str(k.kind); var tg := str(c.target); var opt: Dictionary = c.opt
	if _held_placeholder(drawer_body, kind + "|" + tg, "%s, %s" % [str(k.name), tg]): return
	var v := CareerKit.card(drawer_body, GridTheme.SODIUM if not opt.is_empty() else Color(0, 0, 0, 0)); v.get_parent().name = "Card_" + kind
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); v.add_child(top)
	var nm := CareerKit.lbl(str(k.name), sz + 3, GridTheme.TEXT if not opt.is_empty() or tg == "" else Color(GridTheme.TEXT, 0.6), "semi"); nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(nm)
	if not opt.is_empty():
		top.add_child(CareerKit.lbl(T("CAR_COST_LINE") % [str(opt.capexText), int(opt.leadQ), int(opt.crew)], sz - 1, GridTheme.SODIUM, "mono"))
	elif tg == "":
		var best := 0.0; var cnt := 0
		for o in k.options:
			cnt += 1
			if best == 0.0 or float(o.capex) < best: best = float(o.capex); top.set_meta("bt", str(o.capexText))
		if cnt > 0 and top.has_meta("bt"): top.add_child(CareerKit.lbl(T("CAR_FROM") % str(top.get_meta("bt")), sz - 1, Color(GridTheme.TEXT, 0.6), "mono"))
	if not compact or not opt.is_empty() or tg == "": v.add_child(CareerKit.lbl(str(k.blurb), sz - 1, Color(GridTheme.TEXT, 0.72), "sans", true))
	if tg == "":
		var need: String = KIND_TARGET.get(kind, "section")
		v.add_child(CareerKit.lbl(T("CAR_NEEDS") % T("CAR_TGT_" + need), sz - 1, Color(GridTheme.TEXT, 0.5), "mono", true))
		return
	var q = app.b.q("careerQuote", [kind, tg])
	if not opt.is_empty():
		var why := str(q.get("why", "")) if q is Dictionary else ""
		var wl := CareerKit.lbl(T("CAR_ON") % tg + ": " + why, sz, GridTheme.GOOD, "sans", true); wl.name = "Why"; v.add_child(wl)
		var od := str(q.get("overdrawText", "")) if q is Dictionary else ""
		if od != "":   # warn before the money goes, not at the review
			var ol := CareerKit.lbl(od, sz - 1, GridTheme.BAD, "sans", true); ol.name = "Overdraw"; v.add_child(ol)
		var card := v.get_parent() as Control
		var sb := CareerKit.btn(T("CAR_START"), true, func(): _start_held(kind + "|" + tg, card, kind, tg), 15); sb.name = "Start_" + kind; sb.size_flags_horizontal = Control.SIZE_SHRINK_END; v.add_child(sb)
	else:
		var rl := CareerKit.lbl(str(q.get("text", "")) if q is Dictionary else T("CAR_CANT"), sz - 1, Color(GridTheme.WARN, 0.9), "sans", true); rl.name = "Why"; v.add_child(rl)

## 1.5 storm readiness: the quarter's forecast and three levels (none / pre-switching and standby crews / mutual aid), each with its effect and cost.
func _ready_card(sz: int) -> void:
	var v := CareerKit.card(drawer_body); v.get_parent().name = "ReadyCard"
	var fc := str(d.get("forecast", ""))
	v.add_child(CareerKit.lbl(T("CAR_READY"), sz + 1, GridTheme.SODIUM, "semi", true))
	var fl := CareerKit.lbl(str(d.get("forecastText", "")), sz, GridTheme.BAD if fc == "stormy" else (GridTheme.WARN if fc == "unsettled" else GridTheme.GOOD), "semi", true); fl.name = "Forecast"; v.add_child(fl)
	var lv := int(d.get("readiness", 0))
	for row in d.get("readyLevels", []):
		var l := int(row.level)
		var b := CareerKit.btn(str(row.text), l == lv, func(): act("careerReadiness", [l]), sz - 1); b.name = "Ready%d" % l
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT; b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL; v.add_child(b)
	v.add_child(CareerKit.lbl(T("CAR_READY_NOTE"), sz - 2, Color(GridTheme.TEXT, 0.55), "sans", true))

func _veg_card() -> void:
	if str(d.get("charter", "")) == "city": return   # 1.12 all cable: no trees to cut
	var sz := 14 if compact else 15
	var v := CareerKit.card(drawer_body); v.get_parent().name = "VegCard"
	var lvl := int(d.vegLevel)
	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); v.add_child(top)
	var nm := CareerKit.lbl(T("CAR_VEG"), sz + 3, GridTheme.TEXT, "semi"); nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(nm)
	var mi := CareerKit.btn(T("CAR_MINUS"), false, func(): act("careerVegetation", [maxi(0, lvl - 1)]), 18); mi.name = "VegMinus"; mi.disabled = lvl <= 0; mi.custom_minimum_size.x = 44; top.add_child(mi)
	top.add_child(CareerKit.lbl("%d" % lvl, sz + 5, GridTheme.SODIUM, "title"))
	var pl := CareerKit.btn(T("CAR_PLUS"), false, func(): act("careerVegetation", [mini(3, lvl + 1)]), 18); pl.name = "VegPlus"; pl.disabled = lvl >= 3; pl.custom_minimum_size.x = 44; top.add_child(pl)
	v.add_child(CareerKit.lbl("%s. %s" % [T("CAR_VEG_LVL") % [lvl, T("CAR_VEG_" + str(lvl))], T("CAR_VEG_COST") % str(d.vegCostQText)], sz - 1, Color(GridTheme.TEXT, 0.72), "sans", true))
	for row in d.get("vegLevels", []):   # what each level buys (a tester saw level 2 double the cost with no stated benefit)
		var cur := int(row.level) == lvl
		var rl := CareerKit.lbl("%s %s: %s" % ["▸" if cur else "  ", T("CAR_VEG_" + str(int(row.level))), str(row.text)], sz - 2, GridTheme.SODIUM if cur else Color(GridTheme.TEXT, 0.6), "mono", true); rl.name = "VegLevel%d" % int(row.level); v.add_child(rl)

func _run_tab() -> void:
	var sz := 14 if compact else 15
	drawer_body.add_child(_dlbl(T("CAR_CREWS_LEFT") % int(d.crewsFree), sz, "mono"))
	var n := 0
	for p in d.projects:
		if not (str(p.status) == "building" or str(p.status) == "active"): continue
		n += 1
		var v := CareerKit.card(drawer_body); v.get_parent().name = "Run_" + str(p.id)
		var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 8); v.add_child(top)
		var nl := CareerKit.lbl(T("CAR_RUN_LINE") % [str(p.kindName), str(p.target)], sz + 2, GridTheme.TEXT, "semi", true); top.add_child(nl)
		top.add_child(CareerKit.lbl(T("CAR_RUN_" + str(p.status)), sz - 1, GridTheme.SODIUM, "mono"))
		v.add_child(CareerKit.lbl(T("CAR_RUN_STATE") % [int(p.left), int(p.leadQ), str(p.spentText), str(p.capexText)], sz - 1, Color(GridTheme.TEXT, 0.75), "sans", true))
		var pid := str(p.id)
		var cb := CareerKit.btn(T("CAR_CANCEL"), false, func(): act("careerCancel", [pid]), 14); cb.name = "Cancel_" + pid; cb.size_flags_horizontal = Control.SIZE_SHRINK_END; v.add_child(cb)
	if n == 0: drawer_body.add_child(_dlbl(T("CAR_RUN_NONE"), sz))

func _req_tab() -> void:
	var sz := 14 if compact else 15
	if (d.requests as Array).is_empty(): drawer_body.add_child(_dlbl(T("CAR_REQ_NONE"), sz)); return
	drawer_body.add_child(_dlbl(T("CAR_REQ_HINT"), sz - 1))
	for r in d.requests:
		var v := CareerKit.card(drawer_body, GridTheme.SODIUM if int(r.quartersLeft) <= 1 else Color(0, 0, 0, 0)); v.get_parent().name = "Req_" + str(r.id)
		v.add_child(CareerKit.lbl(T("CAR_REQ_LINE") % [str(r.kindName), str(r.feederId)], sz + 3, GridTheme.TEXT, "semi", true))
		var det: String = T("CAR_REQ_DETAIL") % [CareerKit.num(float(r.kw), 0), int(r.customers), str(r.chargeText)]
		if bool(r.critical): det += ", " + T("CAR_REQ_CRIT")
		if float(r.solarKw) > 0.0: det += ", " + T("CAR_REQ_PV") % CareerKit.num(float(r.solarKw), 0)
		v.add_child(CareerKit.lbl(det, sz - 1, Color(GridTheme.TEXT, 0.8), "sans", true))
		var f := feeder_of(str(r.feederId))
		if not f.is_empty(): v.add_child(CareerKit.lbl(T("CAR_REQ_LOAD") % [str(r.feederId), CareerKit.num(float(r.get("loadingWinterPct", f.loadingPct)), 0), CareerKit.num(float(r.get("loadingAfterPct", f.loadingPct)), 0)], sz - 1, CareerKit.load_col(float(r.get("loadingAfterPct", f.loadingPct))), "sans", true))
		var due := T("CAR_REQ_LAST") if int(r.quartersLeft) <= 0 else T("CAR_REQ_DUE") % int(r.quartersLeft)
		# 1.13: the deadline on its own line, so Accept, Decline and the map button fit the card (the map button was clipped at 1920 px)
		v.add_child(CareerKit.lbl(due, sz - 1, GridTheme.WARN if int(r.quartersLeft) <= 1 else Color(GridTheme.TEXT, 0.7), "mono"))
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 8); row.alignment = BoxContainer.ALIGNMENT_END; v.add_child(row)
		var rid := str(r.id)
		var ab := CareerKit.btn(T("CAR_ACCEPT"), true, func(): act("careerAccept", [rid]), 15); ab.name = "Accept_" + rid; row.add_child(ab)
		var fid := str(r.feederId)
		var db := CareerKit.btn(T("CAR_DECLINE"), false, func(): act("careerDecline", [rid]), 15); db.name = "Decline_" + rid; db.tooltip_text = T("CAR_DECLINE_TIP"); row.add_child(db)
		var show := CareerKit.btn(T("CAR_SHOW_ON_MAP") % str(r.feederId), false, func():
			var f2 := feeder_of(fid)
			if not f2.is_empty() and not (f2.sections as Array).is_empty(): _on_pick({"type": "section", "id": str(f2.sections[0].id), "feeder": fid}), 14); show.name = "Show_" + rid; row.add_child(show)

## 1128c C11: "trees lv 1 $91,440" broke mid-item when the line wrapped; each item between the dots stays whole.
static func _keep_items(t: String) -> String:
	var i := t.find(": ")
	if i < 0: return t
	var items := t.substr(i + 2).split(" · ")
	return t.left(i + 2) + " · ".join(Array(items).map(func(x): return str(x).replace(" ", "\u00a0")))
