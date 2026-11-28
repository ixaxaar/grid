class_name Instruments
extends Control
## The instrument cluster (UI.md 1): top centre, floating over the sky on a soft dark vignette, no bar. The 24 h clock always; bench levels add the
## VOLTMETER ("worst home", red below the engine's limit, green above); grid levels add the frequency dial. Phones keep the clock and one meter.
## Reads only the engine queries `clock`, `levelInfo`, `benchStatus`, `world` and `dial`.

signal codex_requested(id: String)
const GAP := 14.0
var app: CbApp
var clock: Clock24View
var volt: MeterView
var dial: DialView
var clear: MeterView      ## chapter 2: clearance of the worst span, m (scale -2 ... +3)
var vil: MeterView        ## chapter 2: the village's voltage, V at the load bus (340 ... 460); on L30 the island's 0.42 kV bus
var bat: MeterView        ## L30: the island battery's state of charge, % (small before the anchor cut, full size and warm after it)
var after_cut := false    ## L30: the anchor has cut the cable
var bat_k := 0.78         ## its scale in the cluster: 1.0 once the cable is cut
var _vig: GradientTexture2D
var mode := "volt"        ## "volt" (worst home V) or "loss" (line loss %), chosen from the level's bench limits

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new(); g.set_color(0, Color(GridTheme.NIGHT, 0.62)); g.set_color(1, Color(GridTheme.NIGHT, 0.0))
	_vig = GradientTexture2D.new(); _vig.gradient = g; _vig.fill = GradientTexture2D.FILL_RADIAL; _vig.fill_from = Vector2(0.5, 0.5); _vig.fill_to = Vector2(1.0, 0.5); _vig.width = 256; _vig.height = 128
	clock = Clock24View.new(); add_child(clock)
	volt = MeterView.new(); volt.caption = TranslationServer.translate("METER_VOLT_CAPTION"); volt.units = TranslationServer.translate("METER_VOLT_UNITS")
	volt.set_range(0.0, 60.0, 20.0, 5.0); volt.codex_id = "voltage-control"; volt.visible = false; add_child(volt)
	dial = DialView.new(); dial.codex_id = "frequency-response"; dial.visible = false; add_child(dial)
	clear = MeterView.new(); clear.caption = TranslationServer.translate("METER_CLEAR_CAPTION"); clear.units = TranslationServer.translate("METER_CLEAR_UNITS")
	clear.set_range(-2.0, 3.0, 1.0, 0.5); clear.signed = true; clear.blank_key = "METER_CLEAR_NONE"; clear.blank = true; clear.visible = false
	clear.zones = [[-2.0, 0.0, GridTheme.BAD], [0.0, 0.5, GridTheme.WARN], [0.5, 3.0, GridTheme.GOOD]]; add_child(clear)
	vil = MeterView.new(); vil.caption = TranslationServer.translate("METER_VIL_CAPTION"); vil.units = TranslationServer.translate("METER_VIL_UNITS"); vil.decimals = 0
	vil.set_range(340.0, 460.0, 20.0, 10.0); vil.blank = true; vil.visible = false; add_child(vil)
	bat = MeterView.new(); bat.caption = TranslationServer.translate("METER_BAT_CAPTION"); bat.units = TranslationServer.translate("METER_BAT_UNITS"); bat.decimals = 0
	bat.set_range(0.0, 100.0, 20.0, 5.0); bat.blank_key = "METER_BAT_NONE"; bat.blank = true; bat.visible = false
	bat.zones = [[0.0, 10.0, GridTheme.BAD], [10.0, 30.0, GridTheme.WARN], [30.0, 90.0, GridTheme.GOOD], [90.0, 100.0, Color(GridTheme.DIM, 0.8)]]; add_child(bat)
	for m in [volt, dial, clear, vil]: m.codex_requested.connect(func(id): codex_requested.emit(id))

## Re-read the engine and update every meter.
## The dial is hidden while a failed night is held. Chapter 8's studies (WO-31..36) run as one study and their places stand at a fixed time
## of day: the dial reads the scene's hour there, not the engine's (it read 10:00 over a dusk scene, 1128c C04).
const STUDY_JOBS := ["L31", "L32", "L33", "L34", "L35", "L36"]
func clock_on() -> bool: return not ShiftReport.holding()
func _study() -> bool: return app != null and app.b != null and STUDY_JOBS.has(str(app.b.g.get("level", "")))

func refresh() -> void:
	if clock != null: clock.visible = clock_on()
	visible = not (ShiftReport.is_open() and get_viewport_rect().size.x < 1500.0)   # 1128c: at 1280 px the report covered the gauges; the report carries the numbers   # 1128c art review 2: the dial read 08:00 under the held night; the report states the hour
	if app == null or not app.started: return
	var c = app.b.q("clock")
	if c is Dictionary and not c.is_empty():
		var li = app.b.q("levelInfo"); var hz = li.get("horizonBlocks") if li is Dictionary and li.get("active", false) else null
		if _study():
			c = c.duplicate(); c["minuteOfDay"] = Stage8.sky_minute(str(app.b.g.get("level", "")).to_lower()); hz = null
		clock.set_state(c, app.b.g.get("levelStart"), hz); clock.running = app.speed > 0 and not _study()
	var w = app.b.q("world"); var kind: String = str(w.get("kind", "")) if w is Dictionary else ""
	var bs = app.b.q("benchStatus") if kind == "bench" else null
	var show_v: bool = bs is Dictionary and bs.get("active", false)
	volt.visible = show_v; volt.live = app.speed > 0
	var live_ok: bool = show_v and bool(bs.get("powered", false))
	volt.blank = not live_ok
	if show_v:   # the quantity is the one the level checks: lowest home voltage (limits.vMinV) or line loss share (limits.lossMaxPct)
		var lims: Dictionary = (bs.bench as Dictionary).limits
		if lims.get("vMinV") == null and lims.get("lossMaxPct") != null:
			mode = "loss"; var mx := float(lims.lossMaxPct)
			volt.caption = TranslationServer.translate("METER_LOSS_CAPTION"); volt.units = TranslationServer.translate("METER_LOSS_UNITS"); volt.codex_id = ""
			volt.set_range(0.0, 20.0, 5.0, 1.0); volt.zones = [[0.0, mx, GridTheme.GOOD], [mx, 20.0, GridTheme.BAD]]
			volt.set_target(float(bs.lossPct) if live_ok else 0.0)
		else:
			mode = "volt"
			volt.caption = TranslationServer.translate("METER_VOLT_CAPTION"); volt.units = TranslationServer.translate("METER_VOLT_UNITS"); volt.codex_id = "voltage-control"
			var src := float((w.bench as Dictionary).get("sourceV", 48.0)); var hi := ceilf(src * 1.25 / 20.0) * 20.0
			volt.set_range(0.0, hi, 20.0, 5.0)
			var lim = lims.get("vMinV")
			volt.zones = [] if lim == null else [[0.0, float(lim), GridTheme.BAD], [float(lim), hi, GridTheme.GOOD]]
			volt.set_target(float(bs.vMinV) if live_ok else 0.0)
	var terr: bool = w is Dictionary and w.get("terrain") != null
	if terr: volt.visible = false
	refresh_route(app.b, w if terr else {}, terr, app.speed > 0)
	var li8 = app.b.q("levelInfo"); var ch8: bool = li8 is Dictionary and bool(li8.get("active", false)) and int(li8.get("chapter", 0)) == 8   # chapter 8 studies one feeder or one substation: there is no system frequency (the dial drifted to 30 Hz on L34)
	var dq = app.b.q("dial") if kind == "grid" and not terr and not ch8 else null
	var show_d: bool = dq is Dictionary and not dq.get("error", false)
	dial.visible = show_d
	if show_d: dial.set_query(dq)
	layout()

## Chapter 2 meters (levels with a terrain): the clearance gauge shows the engine's worst span margin over the lines laid (`routes[].worstMarginM`),
## the voltmeter the load bus voltage (`busInfo`: vPu x kvNom). Both blank until there is something to read.
func refresh_route(b, w: Dictionary, on: bool, running: bool) -> void:
	clear.visible = on; vil.visible = on
	if not on: bat.visible = false; return
	clear.live = running; vil.live = running
	var rs: Array = b.g.get("routes", [])
	var m := INF
	for r in rs: m = minf(m, float(r.worstMarginM))
	clear.blank = rs.is_empty(); clear.set_target(0.0 if rs.is_empty() else m)
	var vb := {}
	for bus in w.get("buses", []): if str(bus.kind) == "load" and not bool(vb.get("offshore", false)): vb = bus   # the last load bus, but an offshore island's (L30) wins
	vil.caption = TranslationServer.translate("METER_ISL_CAPTION" if bool(vb.get("offshore", false)) else "METER_VIL_CAPTION")
	_refresh_battery(b, w, running)
	var bi = b.q("busInfo", [str(vb.id)]) if not vb.is_empty() else null
	var ok: bool = bi is Dictionary and bool(bi.get("energised", false)) and bi.get("vPu") != null
	vil.blank = not ok
	if ok:
		var kvn := float(bi.kvNom) * 1000.0
		var lo := vil.vmin; var hi := vil.vmax
		var li = b.q("levelInfo"); var lop = li.get("thresholds", {}).get("villageBandLoPu") if li is Dictionary else null
		var blo := clampf((float(lop) if lop != null else float(bi.bandLo)) * kvn, lo, hi); var bhi := clampf(float(bi.bandHi) * kvn, lo, hi)
		vil.zones = [[lo, blo, GridTheme.BAD], [blo, bhi, GridTheme.GOOD], [bhi, hi, GridTheme.BAD]]
		vil.set_target(float(bi.vPu) * kvn)
	else:
		vil.zones = []; vil.set_target(vil.vmin)

## L30: the island battery's state of charge and the hours it has left at the evening peak (the world query's storage list, via TagView.island_battery). Shown while the level has an
## offshore island; blank until a battery stands there. Small before the anchor cut, full size and warm from the cut on (levelInfo.cableCutBlock against the clock).
func _refresh_battery(b, w: Dictionary, running: bool) -> void:
	var off := {}
	for bus in w.get("buses", []): if bool(bus.get("offshore", false)): off[str(bus.id)] = true
	bat.visible = not off.is_empty()
	if not bat.visible: return
	var soc := INF; var hours := 0.0
	for st in w.get("storage", []):
		if not off.has(str(st.bus)): continue
		var v := TagView.island_battery(b, str(st.id))
		if not v.is_empty() and float(v.soc) < soc: soc = float(v.soc); hours = float(v.hours)
	bat.blank = is_inf(soc); bat.set_target(0.0 if is_inf(soc) else soc * 100.0)
	bat.caption = TranslationServer.translate("METER_BAT_CAPTION") if is_inf(soc) or hours <= 0.0 else TranslationServer.translate("METER_BAT_CAPTION_H") % ("%.1f" % hours)
	var li = b.q("levelInfo"); var cut = li.get("cableCutBlock") if li is Dictionary else null
	var clk = b.g.get("clock", {}); var blk := int(clk.get("block", 0)) if clk is Dictionary else 0
	after_cut = cut != null and blk >= int(cut)
	bat_k = 1.0 if after_cut else 0.78
	bat.live = running or after_cut

## What-if of the route tray: the clearance gauge's ghost needle (m). NAN clears it.
func set_clear_ghost(v: float) -> void: clear.set_ghost(v)

func _visible_items() -> Array:
	var a: Array = [clock]
	if clear.visible: a.append(clear)
	if vil.visible: a.append(vil)
	if bat.visible: a.append(bat)
	if volt.visible: a.append(volt)
	if dial.visible: a.append(dial)
	if CbLayout.phone and a.size() > 2: a = [clock, bat] if bat.visible and after_cut else a.slice(0, 2)   # phone: clock plus one meter (the island battery once the cable is cut)
	return a

## What-if from the kit tray: the meter's ghost needle. NAN clears it. `v` is in the meter's own unit (volts, or % in the loss meter).
func set_ghost(v: float) -> void:
	volt.set_ghost(v)

## Centre the cluster at the top of the safe area (root is already inset).
func layout() -> void:
	if app == null: return
	var items := _visible_items(); var sc := 0.82 if CbLayout.phone else 1.0
	var tw := 0.0; var th := 0.0
	for it in items:
		var kk := sc * (bat_k if it == bat else 1.0)
		tw += (it as Control).custom_minimum_size.x * kk; th = maxf(th, (it as Control).custom_minimum_size.y * kk)
	tw += GAP * (items.size() - 1)
	var x := 0.0
	for it in [clock, clear, vil, bat, volt, dial]:
		var ctl := it as Control
		if not items.has(it): ctl.position = Vector2(-9999, -9999); continue
		var k := sc * (bat_k if it == bat else 1.0)
		ctl.scale = Vector2(k, k); ctl.size = ctl.custom_minimum_size; ctl.pivot_offset = Vector2.ZERO
		ctl.position = Vector2(x, 0); x += ctl.custom_minimum_size.x * k + GAP
	var top := 8.0
	size = Vector2(tw, th); position = Vector2((app.vw() - tw) * 0.5, top)
	queue_redraw()

func _draw() -> void:
	var pad := Vector2(70, 40)
	draw_texture_rect(_vig, Rect2(-pad, size + pad * 2.0), false)

## Bounding rect in root coordinates (layout audit, other chrome avoiding it).
func cluster_rect() -> Rect2: return Rect2(position, size)
