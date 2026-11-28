class_name Bay3D
extends Node3D
## The island bay in 3D (DECISIONS 23): one small scene drawn at metre scale from the bench model, used twice: the title backdrop (dusk, hamlet dark,
## lighthouse lit, a slow camera drift) and the bench levels L01 to L03. It reads what WorldView's `_rebuild_island` already decided (tile kinds and
## heights, trees, homes, hut, junction boxes) and the bench model (cable polylines and sizes, home voltages), so the 3D land is the 2D land.
##
## Lights come from the engine: each home's lamp has brightness (V / V0)^2 from the bench's own vLoadV and sourceV (WorldModel gives it as the town's
## `energies`), warm at the level's limit (43.2 V) or more and amber below; the porch bulb at the hut sits on the source, so it is (V0 / V0)^2 = 1 and white.
## The bench lumps a hamlet's homes on one node, so every home of a hamlet carries the same number: no gradient along the row is invented.
##
## WorldView drives it through the same small interface as Province3D (project, ground_point, ground, tm, px_per_tile, pan/orbit/zoom, camera spec), so the
## 2D overlay (labels, site pegs, the surveyed route, the hand) and the mouse picking stay in WorldView and map to the same tiles as in 2D.

const LEVELS := ["L01", "L02", "L03"]
const PXM := 0.9                  # WorldView's z px per metre (RouteDraw.PX_PER_M)
const HOME_LIGHT_E := 5.0         # OmniLight3D energy of a home at brightness 1
const PORCH_LIGHT_E := 6.0
const WARM := Color(1.0, 0.84, 0.54)      # at or above the limit
const AMBER := Color(1.0, 0.42, 0.06)     # below it
const WHITE := Color(1.0, 0.97, 0.90)     # the porch bulb, on the source
const PITCH_MIN := deg_to_rad(10.0)
const PITCH_MAX := deg_to_rad(80.0)

var quality := "high"
var tm := 10.0
var field = null                  # non-null once built: WorldView's `_l3()` asks for it
var own_lines := true             # the cable is a 3D mesh: WorldView draws no screen-space line overlay
var model: Dictionary = {}
var cam: Camera3D
var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var canvas_size := Vector2.ZERO
var view = null                   # the WorldView that drives this scene (QA picking round trip)
var drift := false                # the title: a slow sway of the camera
var title := false
var target := Vector3.ZERO
var yaw := 0.0
var pitch := deg_to_rad(34.0)
var dist := 330.0
var _g_target := Vector3.ZERO
var _g_yaw := 0.0
var _g_pitch := deg_to_rad(34.0)
var _g_dist := 330.0
var _dist_default := 330.0
var _W := 0
var _H := 0
var _h := PackedFloat32Array()    # ground height (m) at tile centres
var _terrain_key := ""
var _places_key := ""
var _cables_key := ""
var _root_static: Node3D
var _root_places: Node3D
var _root_cables: Node3D
var _homes: Array = []            # [{ti, k, light, mat}]
var _porch: Dictionary = {}       # {light, mat}
var _lh: Dictionary = {}          # lighthouse {lamp_mat, light}
var _lh_pos := Vector2(-1e9, 0.0) # where it stands (metres, x / z)
var _water_mats: Array[ShaderMaterial] = []
var _terrain_mat: ShaderMaterial
var _t := 0.0
var _minute := -1.0
var _measuring := false
var _ft_gpu := 0.0
var _ft_cpu := 0.0
var _ft_n := 0
var _ft_at := 0.0
var _ft_ms := 0.0
var _ft_frames := 0

func _ready() -> void: _setup()

func _setup() -> void:
	if _root_static != null: return
	quality = Province3D.pick_quality()
	_root_static = Node3D.new(); _root_static.name = "Static"; add_child(_root_static)
	_root_places = Node3D.new(); _root_places.name = "Places"; add_child(_root_places)
	_root_cables = Node3D.new(); _root_cables.name = "Cables"; add_child(_root_cables)
	cam = Camera3D.new(); cam.name = "Camera"; cam.near = 0.5; cam.far = 20000.0; cam.fov = 42.0; add_child(cam)
	_make_env()
	print("BAY3D quality=%s renderer=%s adapter=%s" % [quality, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])

# --------------------------------------------------------------------------------------------------------------------
# Environment: sky, sun, moon, haze (the camera carries it, so Province3D's WorldEnvironment is not in the way)
# --------------------------------------------------------------------------------------------------------------------
func _make_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky_mat = ShaderMaterial.new(); sky_mat.shader = load("res://world3d/shaders/sky.gdshader")
	var nt := NoiseTexture2D.new(); nt.seamless = true; nt.width = 256; nt.height = 256
	var fn := FastNoiseLite.new(); fn.frequency = 0.012; fn.fractal_octaves = 4; nt.noise = fn
	sky_mat.set_shader_parameter("noise", nt)
	sky.sky_material = sky_mat; sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = quality != "low"
	env.glow_intensity = 0.8; env.glow_bloom = 0.05; env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true; env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 400.0; env.fog_depth_end = 7000.0; env.fog_depth_curve = 1.4
	env.fog_sky_affect = 0.75;   # 11-28b audit: the sea met the sky in a hard line (fogged sea and clear sky disagreed); the haze now reaches the sky low down
	env.fog_density = 1.0
	env.adjustment_enabled = true; env.adjustment_contrast = 1.06; env.adjustment_saturation = 1.06
	if quality != "low": env.ssao_enabled = true; env.ssao_radius = 1.5; env.ssao_intensity = 1.4
	sun = DirectionalLight3D.new(); sun.name = "Sun"; sun.shadow_enabled = quality != "low"
	sun.directional_shadow_max_distance = 900.0; sun.light_angular_distance = 0.5; add_child(sun)
	moon = DirectionalLight3D.new(); moon.name = "Moon"; moon.shadow_enabled = false; moon.light_color = Color(0.62, 0.72, 1.0); add_child(moon)
	cam.environment = env
	var vp := get_viewport()
	if vp == null: return   # not in the tree yet (a test): the viewport tiers do not matter there
	if quality == "high": vp.msaa_3d = Viewport.MSAA_4X
	elif quality == "medium": vp.msaa_3d = Viewport.MSAA_2X
	else:   # integrated GPUs: the 3D view renders at 60 % and is upscaled with sharpening; the UI stays at full resolution
		vp.scaling_3d_scale = 0.6
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR; vp.fsr_sharpness = 0.35

func _update_sky(mn: float) -> void:
	mn = ShiftReport.night_hold(mn)
	_minute = mn
	var n := WorldMath.night(mn); var d := WorldMath.dusk(mn)
	var zen := Color(0.20, 0.40, 0.74).lerp(Color(0.035, 0.06, 0.15), n).lerp(Color(0.09, 0.17, 0.42), d * 0.7)   # 1.18: a moonlit night sky, not a black hole above the sea (Sigrid r7-c)
	var hor := Color(0.70, 0.80, 0.90).lerp(Color(0.10, 0.14, 0.26), n).lerp(Color(0.95, 0.72, 0.52), d * 0.55)
	sky_mat.set_shader_parameter("zenith", zen); sky_mat.set_shader_parameter("horizon", hor); sky_mat.set_shader_parameter("ground", hor * 0.35)
	sky_mat.set_shader_parameter("night", n); sky_mat.set_shader_parameter("dusk", d)
	sky_mat.set_shader_parameter("sun_glow", Color(1.0, 0.62, 0.32).lerp(Color(1.0, 0.9, 0.75), 1.0 - d))
	sky_mat.set_shader_parameter("cloud_lit", Color(1.0, 0.93, 0.85).lerp(Color(1.0, 0.55, 0.35), d).lerp(Color(0.10, 0.12, 0.2), n))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.55, 0.58, 0.66).lerp(Color(0.35, 0.25, 0.35), d).lerp(Color(0.03, 0.04, 0.07), n))
	var a := (mn - 360.0) / 720.0 * PI
	var elev := sin(a) * deg_to_rad(50.0) + deg_to_rad(6.0)
	var to_sun := Vector3(cos(a) * cos(elev), sin(elev), sin(a) * cos(elev) * 0.6 + 0.35 * cos(elev)).normalized()
	sun.visible = elev > deg_to_rad(-6.0)
	if sun.visible and sun.is_inside_tree(): sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	var lowk := clampf(elev / deg_to_rad(12.0), 0.0, 1.0)
	sun.light_color = Color(1.0, 0.66, 0.40).lerp(Color(1.0, 0.95, 0.88), lowk)
	sun.light_energy = clampf((elev + deg_to_rad(4.0)) / deg_to_rad(10.0), 0.0, 1.0) * lerpf(0.9, 2.0, lowk)
	var mdir := Vector3(-0.55, 0.5, 0.67).normalized()   # 11-28b: from the side, not straight behind the camera: the island gets a lit flank and a shadowed one (front light read as flat blue)
	if moon.is_inside_tree(): moon.look_at_from_position(Vector3.ZERO, -mdir, Vector3.UP)
	moon.light_energy = 0.95 * smoothstep(0.35, 0.85, n); moon.light_color = Color(0.80, 0.84, 0.96)   # 1.18 (manager review): moonlight enough that the island, the hut and the cable route read at night; moon.visible = moon.light_energy > 0.01
	sky_mat.set_shader_parameter("moon_dir", mdir)
	env.ambient_light_color = Color(0.20, 0.27, 0.42).lerp(Color(0.34, 0.40, 0.55), d * (1.0 - n)).lerp(Color(0.15, 0.18, 0.26), n * 0.8)
	env.ambient_light_energy = lerpf(0.9, 0.6, n)   # 1.17: a dark night, so the first lamps carry the scene; 1.18: lifted, the island read as a void
	env.fog_light_color = hor.lerp(Color(0.46, 0.55, 0.72), 0.7 * d * (1.0 - n)).lerp(Color(0.08, 0.12, 0.22), n * 0.6)
	env.fog_light_energy = lerpf(1.0, 0.5, n)
	env.tonemap_exposure = lerpf(1.0, 1.4, n)
	for wm in _water_mats:
		wm.set_shader_parameter("night", n); wm.set_shader_parameter("use_sky_col", true); wm.set_shader_parameter("sky_col", hor.lerp(zen, 0.25))
	Look3D.grade(env, moon, n, d, quality, [_terrain_mat])

# --------------------------------------------------------------------------------------------------------------------
# Model in: WorldView hands over its own tiles, heights and objects after it rebuilt them
# --------------------------------------------------------------------------------------------------------------------
func set_model(m: Dictionary, tiles: Array, zgrid: Dictionary, objs: Array) -> void:
	_setup()   # a scene built in a test is filled before its first frame
	model = m
	tm = float(m.get("tile_m", 10.0))
	_W = int(m.map.x); _H = int(m.map.y)
	var kinds := PackedStringArray()
	for t in tiles: kinds.append(str(t.kind))
	var tkey := "%s|%d|%d|%d" % [m.level, _W, _H, hash("".join(kinds))]
	if tkey != _terrain_key or field == null:
		_terrain_key = tkey
		_h.resize(_W * _H)
		for t in tiles: _h[int(t.j) * _W + int(t.i)] = float(zgrid.get(Vector2i(int(t.i), int(t.j)), 0.0)) / PXM
		_smooth_heights(2)
		_kind_of = {}
		for t in tiles: _kind_of[Vector2i(int(t.i), int(t.j))] = str(t.kind)
		_lh_pos = _pick_lighthouse(tiles)
		_hf_nx = 0
		_build_mask(objs)
		_build_heights()
		var jetty := _pick_jetty()
		_plan_paths(jetty[0])
		_build_terrain(tiles)
		_build_props(objs)
		field = self
		_build_lighthouse()
		_build_coast(jetty)
		reset_camera()
	var pkey := JSON.stringify([m.level, m.towns.map(func(t): return [t.id, t.pos, t.count]), m.units.map(func(u): return [u.id, u.pos]), m.subs.map(func(s): return [s.id, s.pos, s.get("energised", true)])])
	if pkey != _places_key: _places_key = pkey; _build_places(objs)
	var ckey := JSON.stringify(m.lines.map(func(l): return [l.id, l.pts, l.get("mm2")]))
	if ckey != _cables_key: _cables_key = ckey; _build_cables()
	_update_lights()
	if absf(float(m.minute) - _minute) > 0.4: _update_sky(float(m.minute))
	if OS.has_environment("CB_BAYPICK") and view != null and not _pick_done:
		_pick_done = true
		get_tree().create_timer(3.0).timeout.connect(qa_pick)

var _pick_done := false

## QA (CB_BAYPICK=1): every tile centre on screen goes world -> screen (WorldView.world_to_screen) -> ground under the pointer (WorldView.map_metres_at,
## the call the tray and the route survey use) and must land on the same tile. Prints one BAYPICK line.
func qa_pick() -> void:
	var n := 0; var ok := 0; var worst := 0.0
	var vr := Rect2(Vector2.ZERO, view.size).grow(-40.0)
	for j in _H:
		for i in _W:
			var sp: Vector2 = view.world_to_screen(Vector2(i, j))
			if not vr.has_point(sp): continue
			n += 1
			var m: Vector2 = view.map_metres_at(sp)
			if is_nan(m.x): continue
			if Vector2i(int(floorf(m.x / tm)), int(floorf(m.y / tm))) == Vector2i(i, j): ok += 1
			worst = maxf(worst, m.distance_to((Vector2(i, j) + Vector2(0.5, 0.5)) * tm))
	print("BAYPICK level=%s tiles_on_screen=%d same_tile=%d worst_offset_m=%.2f tile_m=%.0f" % [str(model.get("level", "-")), n, ok, worst, tm])

func set_title(on: bool) -> void:
	title = on; drift = on and not CbSettings.reduced_motion   # reduced motion: the bay holds still
	if field != null: reset_camera()

func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c); c.queue_free()

func _noise(a: int, b: int, s: int) -> float: return WorldMath.hash2(a, b, s)

## Things grow with the tile size, so a 25 m tile (L03) does not leave a school too small to see; one rule, no level named.
func _bs() -> float: return clampf(tm / 10.0, 1.0, 2.5)

# --------------------------------------------------------------------------------------------------------------------
# Land and sea
# --------------------------------------------------------------------------------------------------------------------
## Ground height (m). 1.18: the shaped island (warped coast, dunes, hills, the headland) baked on a 1/4-tile grid by _build_heights; the hut, the
## cable, the homes and the mouse picking all read this one function, so what is drawn is what is picked.
func ground(x: float, z: float) -> float:
	if _hf_nx < 2: return _base(x, z)
	var fx := (x - _hf_o.x) / _hf_cell; var fz := (z - _hf_o.y) / _hf_cell
	if fx < 0.0 or fz < 0.0 or fx >= float(_hf_nx) or fz >= float(_hf_nz): return _base(x, z)
	var i := int(fx); var j := int(fz); var u := fx - float(i); var v := fz - float(j)
	var r := _hf_nx + 1
	var a := lerpf(_hf[j * r + i], _hf[j * r + i + 1], u); var b := lerpf(_hf[(j + 1) * r + i], _hf[(j + 1) * r + i + 1], u)
	return lerpf(a, b, v)

## The 2D island's own heights: bilinear between tile centres, clamped at the map's rim (which is sea).
func _base(x: float, z: float) -> float:
	if _W < 2: return 0.0
	var fx := clampf(x / tm - 0.5, 0.0, float(_W) - 1.001); var fz := clampf(z / tm - 0.5, 0.0, float(_H) - 1.001)
	var i := int(fx); var j := int(fz); var u := fx - float(i); var v := fz - float(j)
	var a := lerpf(_h[j * _W + i], _h[j * _W + i + 1], u); var b := lerpf(_h[(j + 1) * _W + i], _h[(j + 1) * _W + i + 1], u)
	var out := Vector2(maxf(maxf(-x, x - float(_W) * tm), 0.0), maxf(maxf(-z, z - float(_H) * tm), 0.0)).length()   # past the map's rim the sea bed drops away: deep water, no edge
	return lerpf(a, b, v) - minf(out * 0.12, 30.0)

static func _kind_colour(kind: String) -> Color:
	match kind:
		"sand": return Color(0.66, 0.58, 0.42)
		"mangrove": return Color(0.17, 0.25, 0.13)
		"water": return Color(0.30, 0.30, 0.24)
		_: return Color(0.26, 0.40, 0.17)

## The 2D island steps between tile kinds (sand +1 m, sea -6.7 m); blurred here so a shore is a slope, not a wall. The hut, the cable and the picking use the blurred ground.
func _smooth_heights(passes: int) -> void:
	var land := _h.duplicate()   # the unblurred heights: a tile that was land (>= 0) keeps at least half a metre
	for k in land.size(): land[k] = land[k] if land[k] >= 0.0 else 0.0
	for _p in passes:
		var src := _h.duplicate()
		for j in _H:
			for i in _W:
				var sum := 0.0; var n := 0
				for dj: int in [-1, 0, 1]:
					for di: int in [-1, 0, 1]:
						var ii := i + di; var jj := j + dj
						if ii < 0 or jj < 0 or ii >= _W or jj >= _H: continue
						sum += src[jj * _W + ii]; n += 1
				_h[j * _W + i] = sum / float(n)
		for k in _h.size():   # land stays land: a blurred rim must not sink the homes into the sea
			if land[k] > 0.0: _h[k] = maxf(_h[k], minf(land[k], 0.5))

# 1.18 (lead's art review): the island was a flat slab with a ruler-straight beach. The coast is now warped by noise, the land has dunes and low
# hills, the far point is a rocky headland under the lighthouse, and paths run from the hamlet to a jetty and along the island. All of it is render
# only and stays off the engine's things: a mask (0 at the hut sites, the routes, the homes; 1 well away) scales every change, and near them the
# warp may only add land, never take it. tests/bay_relief_truth.gd checks that every route point and home stays dry and that the picking still lands.
const WARP_TILES := 1.7          # how far the coast may wander (tiles)
const HILL_M := 9.0              # inland relief (m, times _bs())
const DUNE_M := 1.3              # dune height on the sand (m)
const HEAD_M := 13.0             # the headland's rise under the lighthouse (m)

var _hf := PackedFloat32Array()
var _hf_nx := 0
var _hf_nz := 0
var _hf_o := Vector2.ZERO
var _hf_cell := 2.5
var _mask := PackedFloat32Array()  # per tile: 0 at the engine's things, 1 far from them
var _paths: Array = []             # polylines in metres (PackedVector2Array): footpaths, drawn as bare earth
var _kind_of := {}
var _nz_warp: FastNoiseLite
var _nz_hill: FastNoiseLite
var _nz_dune: FastNoiseLite
var _boats: Array = []             # [{node, y, ph}] floating boats bob in _process
var _bld_pts: Array = []           # homes, the hut, boxes (metres): boats keep clear of them

func _protect_pts(objs: Array) -> Array:
	var pts: Array = []   # [Vector2 tile point, radius tiles]
	for o in objs:
		var t := str(o.t)
		if t == "bld" or t == "unit" or t == "sub" or t == "flag": pts.append([o.p as Vector2, 1.6])
	for tw in model.towns: pts.append([(tw.pos as Vector2) + Vector2(0.5, 0.5), 2.6])
	return pts

func _protect_segs() -> Array:
	var segs: Array = []
	var polys: Array = []
	for r in model.get("island", {}).get("routes", []): polys.append(r)
	for l in model.lines: polys.append(l.pts)
	for g in model.get("ghosts", []): polys.append(g)
	for poly in polys:
		for k in range((poly as Array).size() - 1): segs.append([(poly[k] as Vector2) + Vector2(0.5, 0.5), (poly[k + 1] as Vector2) + Vector2(0.5, 0.5)])
	if model.get("level", "") == "L01":   # every hut site on the beach, not only the one in use
		for d in [120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0]:
			var hp: Vector2 = WorldModel.l01_hut_pos(d) + Vector2(0.5, 0.5); segs.append([hp, hp])
	return segs

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a; var l2 := ab.length_squared()
	if l2 < 1e-6: return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))

func _build_mask(objs: Array) -> void:
	var pts := _protect_pts(objs); var segs := _protect_segs()
	_bld_pts.clear()
	for o in objs:
		if str(o.t) == "bld" or str(o.t) == "unit" or str(o.t) == "sub": _bld_pts.append((o.p as Vector2) * tm)
	_mask.resize(_W * _H)
	for j in _H:
		for i in _W:
			var q := Vector2(i + 0.5, j + 0.5); var m := 1.0
			for pr in pts: m = minf(m, smoothstep(float(pr[1]), float(pr[1]) + 2.5, q.distance_to(pr[0])))
			for s in segs: m = minf(m, smoothstep(0.9, 3.0, _seg_dist(q, s[0], s[1])))
			_mask[j * _W + i] = m

## The mask at a point in metres (bilinear between tile centres; 1 off the map).
func mask_at(x: float, z: float) -> float:
	var fx := x / tm - 0.5; var fz := z / tm - 0.5
	if fx < -0.5 or fz < -0.5 or fx > float(_W) - 0.5 or fz > float(_H) - 0.5: return 1.0
	fx = clampf(fx, 0.0, float(_W) - 1.001); fz = clampf(fz, 0.0, float(_H) - 1.001)
	var i := int(fx); var j := int(fz); var u := fx - float(i); var v := fz - float(j)
	return lerpf(lerpf(_mask[j * _W + i], _mask[j * _W + i + 1], u), lerpf(_mask[(j + 1) * _W + i], _mask[(j + 1) * _W + i + 1], u), v)

func _noises() -> void:
	var sd := hash(str(model.get("level", "bay")))
	_nz_warp = FastNoiseLite.new(); _nz_warp.seed = sd; _nz_warp.frequency = 0.9 / (tm * 6.0); _nz_warp.fractal_octaves = 3
	_nz_hill = FastNoiseLite.new(); _nz_hill.seed = sd + 1; _nz_hill.frequency = 1.0 / (tm * 9.0); _nz_hill.fractal_octaves = 4
	_nz_dune = FastNoiseLite.new(); _nz_dune.seed = sd + 2; _nz_dune.frequency = 1.0 / 26.0; _nz_dune.fractal_octaves = 2
	_nz_dune.fractal_type = FastNoiseLite.FRACTAL_RIDGED

## The shaped height at (x, z): the 2D island's heights at a warped point, then dunes, hills and the headland, all scaled by the mask.
func _shaped(x: float, z: float) -> float:
	var m := mask_at(x, z)
	var wa := WARP_TILES * tm
	var wm := maxf(m, 0.6)
	var hw := _base(x + _nz_warp.get_noise_2d(x, z) * wa * wm, z + _nz_warp.get_noise_2d(x + 917.0, z - 433.0) * wa * wm)
	var hb := _base(x, z)
	var h := lerpf(maxf(hw, hb), hw, m)   # near the engine's things the warp only adds land (sand spits, never a cove)
	var land := smoothstep(0.2, 2.5, h)
	var marsh: float = _kind_w(x, z)[0].g   # the mangrove stays a flat marsh
	var hill := pow(clampf(_nz_hill.get_noise_2d(x, z) * 0.5 + 0.55, 0.0, 1.0), 1.6) * HILL_M * _bs() * smoothstep(1.2, 5.0, h) * (1.0 - marsh)
	var dune := _nz_dune.get_noise_2d(x, z) * DUNE_M * land * (1.0 - smoothstep(3.0, 7.0, h))
	h += (hill + dune) * m
	var dh := 1e9   # every home, the hut and each box stands on a dry shelf of its own, not at the water's edge
	for q in _bld_pts: dh = minf(dh, Vector2(x, z).distance_to(q))
	h = maxf(h, 0.8 - 3.0 * smoothstep(7.0 * _bs(), 17.0 * _bs(), dh))
	if _lh_pos.x > -1e8:   # the headland: a rise under the lighthouse, rock on its seaward faces
		var d := Vector2(x, z).distance_to(_lh_pos) / (3.2 * tm)
		h = maxf(h, h + HEAD_M * _bs() * exp(-d * d) * smoothstep(-6.0, 0.5, h) * maxf(m, 0.4))   # it only adds height: near the hut it may still rise a little
	return h

func _build_heights() -> void:
	_noises()
	var mg := 14
	_hf_cell = tm / 4.0; _hf_o = Vector2(-mg * tm, -mg * tm)
	var nx := (_W + 2 * mg) * 4; var nz := (_H + 2 * mg) * 4
	var hf := PackedFloat32Array(); hf.resize((nx + 1) * (nz + 1))
	for jz in nz + 1:
		for ix in nx + 1:
			hf[jz * (nx + 1) + ix] = _shaped(_hf_o.x + float(ix) * _hf_cell, _hf_o.y + float(jz) * _hf_cell)
	_hf = hf; _hf_nx = nx; _hf_nz = nz

## Tile kind weights at a point (bilinear): COLOR = (grass, forest floor, rock, sand), UV2 = (mud, paved) as terrain.gdshader reads them.
func _kind_w(x: float, z: float) -> Array:
	var fx := clampf(x / tm - 0.5, 0.0, float(_W) - 1.001); var fz := clampf(z / tm - 0.5, 0.0, float(_H) - 1.001)
	var i0 := int(fx); var j0 := int(fz); var u := fx - float(i0); var v := fz - float(j0)
	var c := Color(0, 0, 0, 0); var mud := 0.0
	for dj in 2:
		for di in 2:
			var wgt := (u if di == 1 else 1.0 - u) * (v if dj == 1 else 1.0 - v)
			match str(_kind_of.get(Vector2i(i0 + di, j0 + dj), "water")):
				"grass": c.r += wgt
				"mangrove": c.g += wgt; mud += wgt * 0.6
				_: c.a += wgt
	return [c, mud]

## The footpaths: hamlet to the jetty, hamlet to the lighthouse, each one stepped round water and mangrove.
func _plan_paths(jetty_root: Vector2) -> void:
	_paths.clear()
	var homes := []
	for tw in model.towns: homes.append(((tw.pos as Vector2) + Vector2(0.5, 0.5)) * tm)
	if homes.is_empty(): return
	if jetty_root.x > -1e8: _paths.append(_walk(homes[0], jetty_root))
	if _lh_pos.x > -1e8: _paths.append(_walk(homes[0], _lh_pos))
	for k in range(1, homes.size()): _paths.append(_walk(homes[0], homes[k]))

func _walk(a: Vector2, b: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, int(a.distance_to(b) / 12.0))
	var side := (b - a).normalized().orthogonal()
	for k in n + 1:
		var t := float(k) / float(n); var p := a.lerp(b, t)
		var best := p; var bo := 1e9
		for s in 13:   # 0, +1, -1, +2, -2 ... tiles sideways: the nearest dry, open ground
			var off := float((s + 1) / 2) * (1.0 if s % 2 == 1 else -1.0) * tm
			var q := p + side * (off + sin(t * 9.0 + a.x) * tm * 0.6 * sin(t * PI))
			var kk := str(_kind_of.get(Vector2i(int(floorf(q.x / tm)), int(floorf(q.y / tm))), "water"))
			if ground(q.x, q.y) > 0.6 and kk != "mangrove" and kk != "water": best = q; bo = off; break
		if bo < 1e8 or k == 0 or k == n: out.append(best if k > 0 and k < n else p)
	return out

func _path_d(p: Vector2) -> float:
	var d := 1e9
	for poly in _paths:
		for k in range((poly as PackedVector2Array).size() - 1): d = minf(d, _seg_dist(p, poly[k], poly[k + 1]))
	return d

func _build_terrain(tiles: Array) -> void:
	_clear(_root_static)
	_water_mats.clear(); _boats.clear()
	var nx := _hf_nx; var nz := _hf_nz; var r := nx + 1
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var cols := PackedColorArray(); var uv2 := PackedVector2Array(); var idx := PackedInt32Array()
	verts.resize(r * (nz + 1)); norms.resize(verts.size()); cols.resize(verts.size()); uv2.resize(verts.size())
	var wa := WARP_TILES * tm
	for jz in nz + 1:
		for ix in nx + 1:
			var x := _hf_o.x + float(ix) * _hf_cell; var z := _hf_o.y + float(jz) * _hf_cell
			var k := jz * r + ix
			var y := _hf[k]
			verts[k] = Vector3(x, y, z)
			var hl := _hf[jz * r + maxi(ix - 1, 0)]; var hr := _hf[jz * r + mini(ix + 1, nx)]
			var hd := _hf[maxi(jz - 1, 0) * r + ix]; var hu := _hf[mini(jz + 1, nz) * r + ix]
			norms[k] = Vector3(hl - hr, 2.0 * _hf_cell, hd - hu).normalized()
			var m := mask_at(x, z)
			var wm := maxf(m, 0.6)
			var kw := _kind_w(x + _nz_warp.get_noise_2d(x, z) * wa * wm, z + _nz_warp.get_noise_2d(x + 917.0, z - 433.0) * wa * wm)
			var c: Color = kw[0]; var mud: float = kw[1]
			if y < 0.5: c = Color(0, 0, 0, 1)                                   # the shore and the sea bed are sand
			elif y > 2.6 and c.a > 0.0: var g := smoothstep(2.6, 5.0, y) * c.a; c.a -= g; c.r += g   # grass takes the dune tops
			if _lh_pos.x > -1e8:   # the headland: bare rock where it rises
				var hk := smoothstep(4.0 * tm, 1.5 * tm, Vector2(x, z).distance_to(_lh_pos)) * smoothstep(2.0, 6.0, y)
				c = c * (1.0 - hk); c.b += hk
			var pd := _path_d(Vector2(x, z))
			var pw := (1.0 - smoothstep(0.9, 2.0, pd + _noise(ix, jz, 41) * 0.8)) * smoothstep(0.3, 0.8, y)
			uv2[k] = Vector2(clampf(mud + pw * 1.6, 0.0, 2.0), 0.0)
			cols[k] = c
	for jz in nz:
		for ix in nx:
			var a := jz * r + ix; var b := a + 1; var c := a + r; var d := c + 1
			idx.append_array([a, b, c, b, d, c])   # clockwise seen from above (front faces in Godot)
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_COLOR] = cols; arr[Mesh.ARRAY_TEX_UV2] = uv2; arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_terrain_mat = ShaderMaterial.new(); _terrain_mat.shader = load("res://world3d/shaders/terrain.gdshader")
	for n in ["grass", "forest", "rock", "sand"]:
		_terrain_mat.set_shader_parameter(n + "_a", _tex(n + "_albedo")); _terrain_mat.set_shader_parameter(n + "_n", _tex(n + "_normal"))
	_terrain_mat.set_shader_parameter("mud_a", _tex("mud_albedo")); _terrain_mat.set_shader_parameter("field_a", _tex("field_albedo"))
	var mn := NoiseTexture2D.new(); mn.seamless = true; mn.width = 512; mn.height = 512
	var fn := FastNoiseLite.new(); fn.frequency = 0.008; fn.fractal_octaves = 4; mn.noise = fn
	_terrain_mat.set_shader_parameter("macro_noise", mn)
	_terrain_mat.set_shader_parameter("tile_m", 7.0 * _bs())
	_terrain_mat.set_shader_parameter("fields", 0.0)
	_terrain_mat.set_shader_parameter("wet_top", 1.2)
	_terrain_mat.set_shader_parameter("cloud_scale", 0.15)
	_terrain_mat.set_shader_parameter("sand_tint", Vector3(1.55, 1.5, 1.42))
	_terrain_mat.set_shader_parameter("grass_tint", Vector3(0.82, 0.95, 0.66))
	if quality == "low": _terrain_mat.set_shader_parameter("cheap", true)
	var mi := MeshInstance3D.new(); mi.name = "Land"; mi.mesh = mesh; mi.material_override = _terrain_mat; _root_static.add_child(mi)
	# the sea
	var sea := MeshInstance3D.new(); sea.name = "Sea"
	var pm := PlaneMesh.new(); pm.size = Vector2(60000, 60000); pm.subdivide_width = 0; pm.subdivide_depth = 0
	sea.mesh = pm; sea.position = Vector3(float(_W) * tm * 0.5, 0.0, float(_H) * tm * 0.5)
	sea.material_override = _water_mat(); sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root_static.add_child(sea)

func _tex(n: String) -> Texture2D:
	var p := "res://world3d/tex/%s.jpg" % n
	return load(p) if ResourceLoader.exists(p) else null
func _water_mat() -> ShaderMaterial:
	var wm := ShaderMaterial.new(); wm.shader = load("res://world3d/shaders/water.gdshader")
	for k in ["wave_a", "wave_b"]:
		var nt := NoiseTexture2D.new(); nt.seamless = true; nt.as_normal_map = true; nt.bump_strength = 6.0; nt.width = 256; nt.height = 256
		var fn := FastNoiseLite.new(); fn.frequency = 0.02 if k == "wave_a" else 0.035; fn.fractal_octaves = 3; fn.seed = 7 if k == "wave_a" else 11
		nt.noise = fn; wm.set_shader_parameter(k, nt)
	wm.set_shader_parameter("scale", 0.35)   # a bay: small ripples
	wm.set_shader_parameter("ssr_steps", 28 if quality == "high" else (16 if quality == "medium" else 0))
	wm.set_shader_parameter("surf", 1.0)
	_water_mats.append(wm)
	return wm

# --------------------------------------------------------------------------------------------------------------------
# Trees: palms on the sand, broadleaf inland, mangrove in the marsh (positions are WorldView's `_objs`)
# --------------------------------------------------------------------------------------------------------------------
static func palm_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2.ZERO)   # the trunk and the fronds share one surface: every vertex needs a UV
	Props3D._cyl(st, Vector3.ZERO, Vector3(0.03, 0.82, 0.0), 0.035, 0.022, 5, Color(0.45, 0.34, 0.22))
	st.set_color(Color(0.20, 0.36, 0.14))
	var base := Vector3(0.03, 0.82, 0.0)
	for k in 8:
		var a := TAU * float(k) / 8.0
		var d := Vector3(cos(a), 0.0, sin(a)); var side := Vector3(-d.z, 0.0, d.x) * 0.05
		var mid := base + d * 0.2 + Vector3(0.0, 0.07, 0.0); var tip := base + d * 0.4 + Vector3(0.0, -0.13, 0.0)
		Props3D._tri(st, base, mid + side, tip); Props3D._tri(st, base, tip, mid - side)
	return Props3D._commit(st)

func _mm(mesh: Mesh, xf: Array, cols: Array, nm: String, two_sided := false) -> void:
	if xf.is_empty(): return
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh; mm.instance_count = xf.size()
	for i in xf.size(): mm.set_instance_transform(i, xf[i]); mm.set_instance_color(i, cols[i])
	var m: Material = Look3D.tree_mat()
	if two_sided or nm == "Rocks":
		var sm := StandardMaterial3D.new(); sm.vertex_color_use_as_albedo = true; sm.roughness = 0.9; sm.cull_mode = BaseMaterial3D.CULL_DISABLED if two_sided else BaseMaterial3D.CULL_BACK; m = sm
	var mi := MultiMeshInstance3D.new(); mi.name = nm; mi.multimesh = mm; mi.material_override = m; _root_static.add_child(mi)

func _build_props(objs: Array) -> void:
	var tx := []; var tc := []; var mx := []; var mc := []; var px := []; var pc := []
	for o in objs:
		var t := str(o.t)
		if not (t == "tree" or t == "mangrove" or t == "palm"): continue
		var p: Vector2 = o.p; var v := float(o.get("v", 0.5))
		var x := p.x * tm; var z := p.y * tm; var y := ground(x, z) - 0.15
		if y < 0.25: continue   # 1.18: the warped coast put this spot in the sea
		var rot := Basis(Vector3.UP, v * TAU)
		var g := 1.0 + (_bs() - 1.0) * 0.6
		if t == "palm":
			var s := (6.5 + 3.0 * v) * g
			px.append(Transform3D(rot.scaled(Vector3(s, s, s)), Vector3(x, y, z))); pc.append(Color(0.9 + 0.1 * v, 0.9, 0.9))
		elif t == "mangrove":
			var s := (2.4 + 1.6 * v) * g
			mx.append(Transform3D(rot.scaled(Vector3(s, s * 0.9, s)), Vector3(x, y, z))); mc.append(Color(0.55 + 0.2 * v, 0.7, 0.5))
		else:
			var s := (5.0 + 3.0 * v) * g
			tx.append(Transform3D(rot.scaled(Vector3(s, s, s)), Vector3(x, y, z))); tc.append(Color(0.8 + 0.3 * v, 0.9 + 0.1 * v, 0.7))
	_mm(Props3D.broadleaf(), tx, tc, "Trees"); _mm(Props3D.broadleaf(), mx, mc, "Mangrove")
	_mm(palm_mesh(), px, pc, "Palms", true)

## A headland: sand next to the sea, as far as possible from the hamlets (the same rule as WorldView's cute lighthouse, which is not drawn in 3D).
func _pick_lighthouse(tiles: Array) -> Vector2:
	var towns: Array = []
	for tw in model.towns: towns.append((tw.pos as Vector2) + Vector2(0.5, 0.5))
	var best := Vector2i(-1, -1); var bs := -1e9
	for t in tiles:
		if str(t.kind) != "sand": continue
		var i := int(t.i); var j := int(t.j)
		if _kind_of.get(Vector2i(i - 1, j), "water") != "water" and _kind_of.get(Vector2i(i, j - 1), "water") != "water": continue
		var sc := 99.0
		for q in towns: sc = minf(sc, Vector2(i + 0.5, j + 0.5).distance_to(q))
		if sc > bs: bs = sc; best = Vector2i(i, j)
	if best.x < 0: return Vector2(-1e9, 0.0)
	return (Vector2(best) + Vector2(0.5, 0.5)) * tm

func _build_lighthouse() -> void:
	_lh = {}
	if _lh_pos.x < -1e8: return
	var x := _lh_pos.x; var z := _lh_pos.y
	var n := Node3D.new(); n.name = "Lighthouse"
	n.position = Vector3(x, maxf(ground(x, z), 0.0) - 0.3, z); _root_static.add_child(n)
	var mi := MeshInstance3D.new(); mi.mesh = Props3D.lighthouse()
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.roughness = 0.7; mi.material_override = mat; n.add_child(mi)
	var lamp := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.9; sm.height = 1.8; sm.radial_segments = 12; sm.rings = 6; lamp.mesh = sm
	var lm := StandardMaterial3D.new(); lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; lm.albedo_color = Color(1.0, 0.92, 0.7)
	lamp.material_override = lm; lamp.position = Vector3(0, 16.4, 0); lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(lamp)
	var o := OmniLight3D.new(); o.omni_range = 70.0; o.light_color = Color(1.0, 0.9, 0.7); o.position = Vector3(0, 16.4, 0); n.add_child(o)
	var halo := MeshInstance3D.new(); var hm := SphereMesh.new(); hm.radius = 7.0; hm.height = 14.0; hm.radial_segments = 12; hm.rings = 6; halo.mesh = hm
	var hmat := ShaderMaterial.new(); hmat.shader = load("res://world3d/shaders/glow.gdshader"); hmat.set_shader_parameter("tint", Color(1.0, 0.85, 0.55, 0.05)); hmat.set_shader_parameter("power", 1.0)
	halo.material_override = hmat; halo.position = Vector3(0, 16.4, 0); halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(halo)
	_lh = {"light": o, "lamp": lm, "halo": hmat}

# --------------------------------------------------------------------------------------------------------------------
# The coast (1.18): a jetty below the hamlet, boats at it and on the beach, rocks on the headland and along wild shore
# --------------------------------------------------------------------------------------------------------------------
## [shore root on land (m), direction out to sea, length (m)]; root.x = -1e9 when no shore is near the hamlet.
func _pick_jetty() -> Array:
	if model.towns.is_empty(): return [Vector2(-1e9, 0), Vector2.ZERO, 0.0]
	var c: Vector2 = ((model.towns[0].pos as Vector2) + Vector2(0.5, 0.5)) * tm
	var best := [Vector2(-1e9, 0), Vector2.ZERO, 0.0]; var bs := 1e9
	for a in 48:
		var d := Vector2.from_angle(TAU * float(a) / 48.0)
		var shore := -1.0; var deep := -1.0; var pen := 0.0
		var t := 0.0
		while t < 34.0 * tm:
			t += 2.0
			var p := c + d * t; var h := ground(p.x, p.y)
			if shore < 0.0 and t > 2.5 * tm and mask_at(p.x, p.y) < 0.45: pen += 3.0
			if shore < 0.0 and h < 0.0: shore = t
			if shore > 0.0 and h < -2.2: deep = t; break
		if shore < 0.0 or deep < 0.0: continue
		for k in 8:   # the deck must pass clear of the homes
			if _near_home(c + d * (shore - 5.0 + float(k) * 4.0), 6.0): pen += 2.0
		var sc := shore + 0.6 * (deep - shore) + pen * tm
		if sc < bs: bs = sc; best = [c + d * (shore - 5.0), d, clampf(deep - shore + 9.0, 18.0, 42.0)]
	return best

static func boat_mesh(hull: Color) -> ArrayMesh:   # a small open fishing boat, bow along +X, about 6 m
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var L := 2.4; var B := 1.0; var H := 0.75
	var ring := [Vector3(-L, H, -B * 0.85), Vector3(L * 0.55, H, -B), Vector3(L * 1.25, H + 0.25, 0.0), Vector3(L * 0.55, H, B), Vector3(-L, H, B * 0.85)]
	var keel := [Vector3(-L * 0.95, 0.05, -B * 0.55), Vector3(L * 0.5, 0.0, -B * 0.4), Vector3(L * 1.1, 0.35, 0.0), Vector3(L * 0.5, 0.0, B * 0.4), Vector3(-L * 0.95, 0.05, B * 0.55)]
	st.set_color(hull)
	for k in 4:
		Props3D._tri(st, ring[k], keel[k], ring[k + 1]); Props3D._tri(st, ring[k + 1], keel[k], keel[k + 1])
	Props3D._tri(st, ring[4], keel[4], ring[0]); Props3D._tri(st, ring[0], keel[4], keel[0])   # transom
	st.set_color(Color(0.12, 0.10, 0.09))
	Props3D._tri(st, keel[0], keel[1], keel[4]); Props3D._tri(st, keel[1], keel[3], keel[4]); Props3D._tri(st, keel[1], keel[2], keel[3])
	st.set_color(Color(0.58, 0.46, 0.32))   # the floor boards and two thwarts, inside
	Props3D._box(st, Vector3(0.0, 0.3, 0.0), Vector3(L * 1.5, 0.06, B * 1.1), Color(0.50, 0.40, 0.28))
	Props3D._box(st, Vector3(-0.6, 0.55, 0.0), Vector3(0.28, 0.06, B * 1.7), Color(0.62, 0.50, 0.34))
	Props3D._box(st, Vector3(1.0, 0.55, 0.0), Vector3(0.28, 0.06, B * 1.6), Color(0.62, 0.50, 0.34))
	Props3D._box(st, Vector3(0.0, H + 0.02, 0.0), Vector3(L * 2.0, 0.05, 0.05), hull.lightened(0.5))   # a gunwale stripe reads from afar
	st.generate_normals()
	return st.commit()

func _build_coast(jetty: Array) -> void:
	var body := StandardMaterial3D.new(); body.vertex_color_use_as_albedo = true; body.roughness = 0.85; body.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hulls := [Color(0.86, 0.85, 0.80), Color(0.18, 0.34, 0.55), Color(0.62, 0.18, 0.14), Color(0.22, 0.42, 0.32), Color(0.85, 0.62, 0.20)]
	var root: Vector2 = jetty[0]
	if root.x > -1e8:
		var d: Vector2 = jetty[1]; var L: float = jetty[2]; var side := d.orthogonal()
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var deck := 1.35
		var ang := -d.angle()
		var basis := Basis(Vector3.UP, ang)
		var n := int(L / 0.6)
		for k in n:   # planks across the deck, each a slightly different grey-brown
			var p := root + d * (float(k) * 0.6 + 0.3)
			var y := maxf(deck, ground(p.x, p.y) + 0.35)
			var c := Color(0.42, 0.34, 0.26).lerp(Color(0.56, 0.50, 0.42), _noise(k, 3, 17))
			var xf := Transform3D(basis, Vector3(p.x, y, p.y))
			_box_xf(st, xf, Vector3(0.52, 0.09, 2.2), c)
		for k in int(L / 3.0) + 1:   # posts down to the sea bed, pairs either side
			for s: float in [-1.0, 1.0]:
				var p := root + d * (float(k) * 3.0 + 0.3) + side * s * 1.0
				var gb := ground(p.x, p.y)
				Props3D._cyl(st, Vector3(p.x, gb - 0.5, p.y), Vector3(p.x, deck + 0.65, p.y), 0.13, 0.12, 6, Color(0.30, 0.25, 0.20))
		var mi := MeshInstance3D.new(); mi.name = "Jetty"; mi.mesh = Props3D._commit(st); mi.material_override = body; _root_static.add_child(mi)
		var tip := root + d * L
		for k in 3:   # moored along the jetty's lee side, bows out to sea
			var p := tip - d * (4.0 + 6.5 * float(k)) + side * (2.6 if k % 2 == 0 else -2.6)
			if ground(p.x, p.y) > -0.35 or _near_home(p, 4.0): continue
			_boat(p, -d.angle() + (0.08 * float(k) - 0.05), hulls[k % hulls.size()], body, true)
		var far := tip + d * 38.0 + side * 22.0   # one out at the moorings
		if ground(far.x, far.y) < -1.0: _boat(far, -d.angle() + 0.9, hulls[3], body, true)
		for k in 2:   # two drawn up on the sand beside the jetty, bows inland
			var b := root + side * (7.0 + 5.0 * float(k)) * (1.0 if k == 0 else -1.0) - d * 1.5
			var g := ground(b.x, b.y)
			if g > 0.15 and g < 2.5 and not _near_home(b, 7.0): _boat(b, -(-d).angle() + 0.25 * float(k), hulls[(k + 2) % hulls.size()], body, false)
	# rocks: the headland's foot and some wild stretches of shore
	var rx := []; var rc := []
	var step := 3
	for jz in range(0, _hf_nz, step):
		for ix in range(0, _hf_nx, step):
			var x := _hf_o.x + (float(ix) + _noise(ix, jz, 51) * step) * _hf_cell; var z := _hf_o.y + (float(jz) + _noise(ix, jz, 52) * step) * _hf_cell
			var h := ground(x, z)
			if h < -1.6 or h > 3.5: continue
			var head := 0.0
			if _lh_pos.x > -1e8: head = smoothstep(5.0 * tm, 1.5 * tm, Vector2(x, z).distance_to(_lh_pos))
			var wild := clampf(_nz_hill.get_noise_2d(x * 3.0, z * 3.0) * 1.8, 0.0, 1.0) * 0.35
			if _noise(ix, jz, 53) > 0.12 + 0.75 * maxf(head, wild): continue
			if mask_at(x, z) < 0.8: continue
			var s := (0.8 + 2.6 * _noise(ix, jz, 54)) * (1.0 + head)
			rx.append(Transform3D(Basis(Vector3.UP, _noise(ix, jz, 55) * TAU).scaled(Vector3(s, s * (0.6 + 0.5 * _noise(ix, jz, 56)), s * 1.2)), Vector3(x, h - 0.25 * s, z)))
			rc.append(Color(0.75 + 0.3 * _noise(ix, jz, 57), 0.75 + 0.25 * _noise(ix, jz, 57), 0.72 + 0.2 * _noise(ix, jz, 58)))
	_mm(Props3D.boulder(), rx, rc, "Rocks")

func _near_home(p: Vector2, r: float) -> bool:
	for q in _bld_pts:
		if p.distance_to(q) < r * _bs(): return true
	return false

func _boat(p: Vector2, ang: float, hull: Color, mat: Material, floating: bool) -> void:
	var n := MeshInstance3D.new(); n.name = "Boat"; n.mesh = boat_mesh(hull); n.material_override = mat
	var y := 0.0 if floating else ground(p.x, p.y) - 0.1
	n.position = Vector3(p.x, y - (0.32 if floating else 0.0), p.y); n.rotation.y = ang
	if not floating: n.rotation.z = 0.12
	n.scale = Vector3.ONE * _bs()
	_root_static.add_child(n)
	if floating: _boats.append({"node": n, "y": n.position.y, "ph": p.x * 0.13 + p.y * 0.07})

static func _box_xf(st: SurfaceTool, xf: Transform3D, s: Vector3, col: Color) -> void:
	var tmp := SurfaceTool.new(); tmp.begin(Mesh.PRIMITIVE_TRIANGLES)
	Props3D._box(tmp, Vector3.ZERO, s, col)
	var arr := tmp.commit_to_arrays()
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var ix = arr[Mesh.ARRAY_INDEX]
	st.set_color(col)
	var order: Array = range(vs.size()) if ix == null else Array(ix)
	for k in order:
		if ns.size() > 0: st.set_normal(xf.basis * ns[k])
		st.add_vertex(xf * vs[k])

# --------------------------------------------------------------------------------------------------------------------
# Places: homes, the school, the hut with its porch bulb, junction boxes and converters
# --------------------------------------------------------------------------------------------------------------------
static func house_mesh(w: float, d: float, h: float, rh: float, wall: Color, roof: Color) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Props3D._box(st, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
	var ov := 0.4; var x := w * 0.5 + ov; var zz := d * 0.5 + ov
	st.set_color(roof)
	var a := Vector3(-x, h, -zz); var b := Vector3(x, h, -zz); var c := Vector3(x, h, zz); var dd := Vector3(-x, h, zz)
	var t0 := Vector3(-x, h + rh, 0); var t1 := Vector3(x, h + rh, 0)
	Props3D._tri(st, a, t1, b); Props3D._tri(st, a, t0, t1); Props3D._tri(st, dd, c, t1); Props3D._tri(st, dd, t1, t0)
	st.set_color(wall)
	Props3D._tri(st, Vector3(-w * 0.5, h, -d * 0.5), Vector3(-w * 0.5, h, d * 0.5), Vector3(-w * 0.5, h + rh * 0.9, 0))
	Props3D._tri(st, Vector3(w * 0.5, h, d * 0.5), Vector3(w * 0.5, h, -d * 0.5), Vector3(w * 0.5, h + rh * 0.9, 0))
	# 1.17 (Sigrid): a door and a chimney, so a home reads as a home before its lamp is lit
	Props3D._box(st, Vector3(w * 0.18, h * 0.32, d * 0.5 + 0.04), Vector3(0.9, h * 0.64, 0.08), Color(0.32, 0.2, 0.13))
	Props3D._box(st, Vector3(-w * 0.18, h * 0.32, -d * 0.5 - 0.04), Vector3(0.9, h * 0.64, 0.08), Color(0.32, 0.2, 0.13))
	Props3D._box(st, Vector3(-w * 0.28, h + rh * 0.75, -d * 0.18), Vector3(0.7, rh * 1.1, 0.7), Color(0.45, 0.3, 0.25))
	# 1.18 (manager review: the homes are the title's foreground): a porch over the front door, a picket fence round the front garden,
	# and on some homes a washing line behind (v picks which)
	var wood := Color(0.52, 0.40, 0.28); var paint := Color(0.88, 0.86, 0.80)
	var pz := d * 0.5 + 0.9
	Props3D._box(st, Vector3(w * 0.18, 0.12, pz), Vector3(2.6, 0.24, 1.8), wood)                                # deck
	for sx in [-1.1, 1.1]: Props3D._box(st, Vector3(w * 0.18 + sx, h * 0.38, pz + 0.75), Vector3(0.14, h * 0.76, 0.14), paint)   # posts
	Props3D._box(st, Vector3(w * 0.18, h * 0.78, pz), Vector3(2.9, 0.12, 2.0), roof)                             # porch roof
	var fz := d * 0.5 + 4.2; var fx := w * 0.5 + 1.2
	for sgn in [-1.0, 1.0]:
		var gap0 := w * 0.18 - 0.8; var gap1 := w * 0.18 + 0.8   # the gate is open in front of the door
		var px := -fx
		while px <= fx + 0.01 and sgn < 0.0:   # one row of pickets (the loop runs once; the sides come from both signs)
			if px < gap0 or px > gap1: Props3D._box(st, Vector3(px, 0.45, fz), Vector3(0.1, 0.9, 0.1), paint)
			px += 0.6
		if sgn < 0.0:
			Props3D._box(st, Vector3((-fx + gap0) * 0.5, 0.6, fz), Vector3(gap0 + fx, 0.08, 0.06), paint)
			Props3D._box(st, Vector3((gap1 + fx) * 0.5, 0.6, fz), Vector3(fx - gap1, 0.08, 0.06), paint)
		Props3D._box(st, Vector3(sgn * fx, 0.6, (d * 0.5 + fz) * 0.5), Vector3(0.06, 0.08, fz - d * 0.5), paint)   # the sides back to the house
	if int(w * 37.0) % 2 == 0:   # a washing line behind the house, three cloths on it
		var lz := -d * 0.5 - 3.0
		for sx in [-w * 0.4, w * 0.4]: Props3D._box(st, Vector3(sx, 1.0, lz), Vector3(0.1, 2.0, 0.1), wood)
		Props3D._box(st, Vector3(0, 1.95, lz), Vector3(w * 0.8, 0.03, 0.03), Color(0.85, 0.85, 0.85))
		var cloths := [Color(0.85, 0.35, 0.30), Color(0.92, 0.92, 0.88), Color(0.35, 0.50, 0.75)]
		for k in 3: Props3D._box(st, Vector3(-w * 0.25 + w * 0.25 * k, 1.55, lz), Vector3(0.9, 0.8, 0.03), cloths[k])
	return Props3D._commit(st)

static func _quad(st: SurfaceTool, c: Vector3, ex: Vector3, ey: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	for p in [c - ex - ey, c + ex + ey, c + ex - ey, c - ex - ey, c - ex + ey, c + ex + ey]: st.add_vertex(p)   # 1128c: clockwise from the side n points to (was inside out)

static func windows_mesh(w: float, d: float, h: float) -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var zf := d * 0.5 + 0.03
	for sx in [-0.5, 0.5]:   # 1.17: windows on every wall, so the hamlet reads from any camera
		_quad(st, Vector3(sx * w * 0.5, h * 0.58, zf), Vector3(0.7, 0, 0), Vector3(0, 0.7, 0), Vector3.BACK)
		_quad(st, Vector3(sx * w * 0.5, h * 0.58, -zf), Vector3(-0.7, 0, 0), Vector3(0, 0.7, 0), Vector3.FORWARD)
	_quad(st, Vector3(w * 0.5 + 0.03, h * 0.58, 0.0), Vector3(0, 0, -0.7), Vector3(0, 0.7, 0), Vector3.RIGHT)
	_quad(st, Vector3(-w * 0.5 - 0.03, h * 0.58, 0.0), Vector3(0, 0, 0.7), Vector3(0, 0.7, 0), Vector3.LEFT)
	# 1.18: the glass of the front door and a porch lamp light with the windows, so light spills from the door when the home has power
	_quad(st, Vector3(w * 0.18, h * 0.42, d * 0.5 + 0.09), Vector3(0.3, 0, 0), Vector3(0, h * 0.18, 0), Vector3.BACK)
	_quad(st, Vector3(w * 0.18 + 0.75, h * 0.66, d * 0.5 + 0.09), Vector3(0.12, 0, 0), Vector3(0, 0.16, 0), Vector3.BACK)
	return Props3D._commit(st)

## A soft disc of light on the ground (additive): the lamp's pool, readable from the whole bay. Its strength is set in _update_lights.
func _pool(parent: Node3D, pos: Vector3, radius: float) -> ShaderMaterial:
	var pm := PlaneMesh.new(); pm.size = Vector2(radius * 2.0, radius * 2.0)
	var mi := MeshInstance3D.new(); mi.mesh = pm; mi.position = pos; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := ShaderMaterial.new(); gm.shader = load("res://world3d/shaders/glow.gdshader"); gm.set_shader_parameter("radial", radius); gm.set_shader_parameter("power", 0.0)
	mi.material_override = gm; parent.add_child(mi)
	return gm

func _flat_mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = rough; return m

func _build_places(objs: Array) -> void:
	_clear(_root_places)
	_homes.clear(); _porch = {}
	var wall_cols := [Color(0.86, 0.80, 0.68), Color(0.78, 0.84, 0.82), Color(0.90, 0.74, 0.60), Color(0.82, 0.82, 0.76)]
	var roof_cols := [Color(0.50, 0.22, 0.16), Color(0.36, 0.38, 0.42), Color(0.46, 0.28, 0.18)]
	var body_mat := StandardMaterial3D.new(); body_mat.vertex_color_use_as_albedo = true; body_mat.roughness = 0.9; body_mat.metallic_specular = 0.2; body_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for o in objs:
		var t := str(o.t)
		var p: Vector2 = o.p
		var x := p.x * tm; var z := p.y * tm
		var y := maxf(ground(x, z), 0.0)
		if t == "bld":
			var v := float(o.get("v", 0.5)); var role := str(o.get("role", ""))
			var w := 5.6 + 1.2 * v; var d := 4.6 + 0.8 * v; var h := 3.0 + 0.5 * v; var rh := 1.9
			var wall: Color = wall_cols[int(v * 97.0) % wall_cols.size()]; var roof: Color = roof_cols[int(v * 53.0) % roof_cols.size()]
			if role == "school": w = 18.0; d = 9.0; h = 6.2; rh = 2.6; wall = Color(0.62, 0.28, 0.20); roof = Color(0.30, 0.31, 0.35)
			elif role == "health": w = 10.0; d = 7.0; h = 3.6; rh = 1.6; wall = Color(0.92, 0.92, 0.90); roof = Color(0.55, 0.57, 0.60)
			var n := Node3D.new(); n.name = "Home_%s_%d" % [str(model.towns[int(o.ti)].id), int(o.k)]
			n.position = Vector3(x, y - 0.1, z); n.rotation.y = (v - 0.5) * 0.35; n.scale = Vector3.ONE * _bs(); _root_places.add_child(n)
			var bi := MeshInstance3D.new(); bi.mesh = house_mesh(w, d, h, rh, wall, roof); bi.material_override = body_mat; n.add_child(bi)
			var wi := MeshInstance3D.new(); wi.mesh = windows_mesh(w, d, h)
			var wm := StandardMaterial3D.new(); wm.albedo_color = Color(0.13, 0.17, 0.25); wm.metallic = 0.3; wm.roughness = 0.2; wm.cull_mode = BaseMaterial3D.CULL_DISABLED; wm.emission_enabled = true; wm.emission = WARM; wm.emission_energy_multiplier = 0.0
			wi.material_override = wm; wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(wi)
			var lt := OmniLight3D.new(); lt.omni_range = (16.0 if role == "" else 22.0); lt.omni_attenuation = 1.3; lt.light_specular = 0.2; lt.position = Vector3(0, h * 0.6, d * 0.5 + 1.6); n.add_child(lt)
			if role == "health":   # a red cross on the front
				var cm := _flat_mat(Color(0.8, 0.1, 0.1)); var cb := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.5, 2.0, 0.1); cb.mesh = bm; cb.material_override = cm; cb.position = Vector3(0, h * 0.62, d * 0.5 + 0.06); n.add_child(cb)
				var cb2 := MeshInstance3D.new(); var bm2 := BoxMesh.new(); bm2.size = Vector3(2.0, 0.5, 0.1); cb2.mesh = bm2; cb2.material_override = cm; cb2.position = cb.position; n.add_child(cb2)
			var pool := _pool(n, Vector3(0, 0.35, d * 0.5 + 2.0), 9.0 if role == "" else 14.0)
			# 1128c rollout: a street lamp at the front corner, its arm over the door; halo and pool lit with the home (_update_lights), dark when unserved
			var grp := "bay_%d_%d" % [int(o.ti), int(o.k)]
			Kit3D.street_lamp(n, Vector3(w * 0.5 + 2.2, -0.1, d * 0.5 + 3.4), PI, quality, grp, 5.2)
			_homes.append({"ti": int(o.ti), "k": int(o.k), "light": lt, "mat": wm, "pool": pool, "group": grp})
		elif t == "unit" and str(o.u.kind) == "hut": _build_hut(Vector3(x, y, z), bool(o.u.online))
		elif t == "sub": _build_sub(Vector3(x, y, z))
		elif t == "flag":
			var pole := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.07; cm.bottom_radius = 0.09; cm.height = 9.0; pole.mesh = cm; pole.material_override = _flat_mat(Color(0.8, 0.8, 0.82), 0.4)
			pole.position = Vector3(x, y + 4.5, z); _root_places.add_child(pole)

func _build_hut(pos: Vector3, _online: bool) -> void:
	var n := Node3D.new(); n.name = "Hut"; n.position = pos - Vector3(0, 0.1, 0); n.scale = Vector3.ONE * _bs() * 1.7;   # 1.17 hand play: the hut was too small to find once placed
	_root_places.add_child(n)
	var body := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(4.2, 2.6, 3.0); body.mesh = bm; body.material_override = _flat_mat(Color(0.40, 0.50, 0.46), 0.6); body.position = Vector3(0, 1.3, 0); n.add_child(body)
	var roof := MeshInstance3D.new(); var rm := BoxMesh.new(); rm.size = Vector3(4.6, 0.2, 3.4); roof.mesh = rm; roof.material_override = _flat_mat(Color(0.22, 0.24, 0.26), 0.5); roof.position = Vector3(0, 2.7, 0); n.add_child(roof)
	var panel := MeshInstance3D.new(); var pm := BoxMesh.new(); pm.size = Vector3(3.4, 0.08, 1.8); panel.mesh = pm; panel.material_override = _flat_mat(Color(0.08, 0.12, 0.28), 0.2)
	panel.position = Vector3(0, 3.15, 0.2); panel.rotation.x = deg_to_rad(-22.0); n.add_child(panel)
	var door := MeshInstance3D.new(); var dm := BoxMesh.new(); dm.size = Vector3(1.0, 1.9, 0.08); door.mesh = dm; door.material_override = _flat_mat(Color(0.28, 0.20, 0.14)); door.position = Vector3(-0.8, 0.95, 1.52); n.add_child(door)
	var post := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.05; cm.bottom_radius = 0.05; cm.height = 2.7; post.mesh = cm; post.material_override = _flat_mat(Color(0.3, 0.3, 0.32)); post.position = Vector3(0.9, 1.35, 1.9); n.add_child(post)
	var bulb := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.22; sm.height = 0.44; sm.radial_segments = 10; sm.rings = 5; bulb.mesh = sm
	var bm2 := StandardMaterial3D.new(); bm2.albedo_color = Color(0.1, 0.1, 0.1); bm2.emission_enabled = true; bm2.emission = WHITE; bm2.emission_energy_multiplier = 0.0
	bulb.material_override = bm2; bulb.position = Vector3(0.9, 2.75, 1.9); bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; n.add_child(bulb)
	var lt := OmniLight3D.new(); lt.omni_range = 16.0; lt.omni_attenuation = 1.3; lt.light_color = WHITE; lt.position = Vector3(0.9, 2.6, 2.3); n.add_child(lt)
	_porch = {"light": lt, "mat": bm2, "pool": _pool(n, Vector3(0.9, 0.35, 3.0), 8.0)}

func _build_sub(pos: Vector3) -> void:
	var b := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(2.4, 1.8, 1.8) * _bs(); b.mesh = bm; b.material_override = _flat_mat(Color(0.55, 0.58, 0.60), 0.5); b.position = pos + Vector3(0, 0.9 * _bs(), 0); _root_places.add_child(b)

# --------------------------------------------------------------------------------------------------------------------
# Cables: a dark sheath along the ground and a glow overlay in the engine's loading colour, pulses running while the line carries power
# --------------------------------------------------------------------------------------------------------------------
func _build_cables() -> void:
	_clear(_root_cables)
	for l in model.lines:
		if str(l.kind) != "cable": continue
		var pts: Array = l.pts
		if pts.size() < 2: continue
		var mm2 := float(l.get("mm2", 10.0)) if l.get("mm2") != null else 10.0
		var r := (0.08 + 0.024 * sqrt(mm2)) * _bs()
		var path: Array[Vector3] = []
		for k in range(pts.size() - 1):
			var a: Vector2 = ((pts[k] as Vector2) + Vector2(0.5, 0.5)) * tm; var b: Vector2 = ((pts[k + 1] as Vector2) + Vector2(0.5, 0.5)) * tm
			var n := maxi(1, int(a.distance_to(b) / 2.0))
			for q in n + (1 if k == pts.size() - 2 else 0):
				var p := a.lerp(b, float(q) / float(n)); path.append(Vector3(p.x, maxf(ground(p.x, p.y), 0.0) + r + 0.05, p.y))
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); var s2 := SurfaceTool.new(); s2.begin(Mesh.PRIMITIVE_TRIANGLES)
		var run := 0.0
		for k in range(path.size() - 1):
			Props3D.add_wire(st, path[k], path[k + 1], 0.0, r, run, 1); Props3D.add_wire(s2, path[k], path[k + 1], 0.0, r * 1.3, run, 1); run += path[k].distance_to(path[k + 1])
		var core := MeshInstance3D.new(); core.name = "Cable_" + str(l.id); core.mesh = st.commit(); core.material_override = _flat_mat(Color(0.10, 0.09, 0.08), 0.6); _root_cables.add_child(core)
		var gl := MeshInstance3D.new(); gl.name = "Glow_" + str(l.id); gl.mesh = s2.commit()
		var gm := ShaderMaterial.new(); gm.shader = load("res://world3d/shaders/glow.gdshader")
		gm.set_shader_parameter("tint", Color(l.color, 0.5)); gm.set_shader_parameter("power", 1.1); gm.set_shader_parameter("pulse", 0.9 if int(l.dir) != 0 else 0.0); gm.set_shader_parameter("inflate", 0.0011)
		gl.material_override = gm; gl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_cables.add_child(gl)

# --------------------------------------------------------------------------------------------------------------------
# Lights: the engine's voltages
# --------------------------------------------------------------------------------------------------------------------
## (V / V0)^2 for a home: WorldModel's `energies` are exactly that from the bench's vLoadV and sourceV (and zero when the hamlet is dead).
static func home_brightness(m: Dictionary, ti: int, k: int) -> float:
	var t: Dictionary = m.towns[ti]
	var en: PackedFloat32Array = t.energies
	return clampf(float(en[k]) if k < en.size() else 0.0, 0.0, 1.5)

## Warm at the level's limit or more, amber below. A level with no voltage limit on the home (L03's school is judged on losses) is warm whenever it is lit.
static func home_warm(m: Dictionary, ti: int) -> bool:
	var t: Dictionary = m.towns[ti]
	var lim := float(t.get("limit", 0.0))
	return float(t.get("volts", 0.0)) >= lim if lim > 0.0 else true

## The porch bulb hangs on the hut, which sits on the source: (V0 / V0)^2 = 1 while the hut runs, 0 otherwise.
static func porch_brightness(m: Dictionary) -> float:
	for u in m.units:
		if str(u.kind) == "hut": return 1.0 if bool(u.online) else 0.0
	return 0.0

func _update_lights() -> void:
	for h in _homes:
		var b := home_brightness(model, int(h.ti), int(h.k))
		var col := WARM if home_warm(model, int(h.ti)) else AMBER
		var lt: OmniLight3D = h.light; var mat: StandardMaterial3D = h.mat
		lt.light_energy = b * HOME_LIGHT_E; lt.light_color = col; lt.visible = b > 0.003
		mat.emission = col; mat.emission_energy_multiplier = b * 9.0
		Kit3D.set_group(str(h.group), b > 0.003); Kit3D.set_level(str(h.group), b)
		var pm: ShaderMaterial = h.pool; pm.set_shader_parameter("tint", Color(col, 1.0)); pm.set_shader_parameter("power", b * 1.5)
	if not _porch.is_empty():
		var b := porch_brightness(model)
		var lt: OmniLight3D = _porch.light; var mat: StandardMaterial3D = _porch.mat
		lt.light_energy = b * PORCH_LIGHT_E; lt.light_color = WHITE; lt.visible = b > 0.003
		mat.emission = WHITE; mat.emission_energy_multiplier = b * 4.0
		var pm: ShaderMaterial = _porch.pool; pm.set_shader_parameter("tint", Color(WHITE, 1.0)); pm.set_shader_parameter("power", b * 0.9)
	if not _lh.is_empty():
		var nn := WorldMath.night(float(model.get("minute", 1080.0)))
		var k := clampf(0.25 + 1.2 * nn, 0.0, 1.4)
		(_lh.light as OmniLight3D).light_energy = 3.0 * k; (_lh.halo as ShaderMaterial).set_shader_parameter("power", 1.0 * k)
		(_lh.lamp as StandardMaterial3D).albedo_color = Color(1.0, 0.92, 0.7) * (0.6 + 1.6 * k)

## What the scene's own lights say (tests/bay_lights_truth.gd): per home its brightness, the Light3D's energy and colour; the porch bulb.
func lamp_report() -> Dictionary:
	var homes: Array = []
	for h in _homes:
		var lt: OmniLight3D = h.light
		homes.append({"town": model.towns[int(h.ti)].id, "k": int(h.k), "b": home_brightness(model, int(h.ti), int(h.k)), "light": lt.light_energy, "warm": lt.light_color.g > 0.7, "lamp_on": Kit3D.group_on(str(h.group))})
	var rep := {"homes": homes}
	if not _porch.is_empty():
		var lt: OmniLight3D = _porch.light
		rep["porch"] = {"b": lt.light_energy / PORCH_LIGHT_E, "light": lt.light_energy, "amber": lt.light_color.g < 0.7}
	return rep

# --------------------------------------------------------------------------------------------------------------------
# Camera: orbit / pan / zoom for WorldView (same interface as Province3D)
# --------------------------------------------------------------------------------------------------------------------
func _map_m() -> Vector2: return Vector2(float(_W), float(_H)) * tm

func reset_camera() -> void:
	var mm := _map_m()
	_dist_default = maxf(mm.x * 0.66, mm.y * 1.25)
	_g_target = Vector3(mm.x * 0.5, 0.0, mm.y * 0.44); _g_yaw = deg_to_rad(8.0); _g_pitch = deg_to_rad(36.0); _g_dist = _dist_default
	var play := _play_box()
	if play.size.x > 0.0:   # 1.18 (lead's review): look along the work from beside the first hamlet, so its homes are big in the foreground and the
		# routes and hut sites run away behind them; the box of everything the player places or lights stays in view
		var hm: Vector2 = ((model.towns[0].pos as Vector2) + Vector2(0.5, 0.5)) * tm
		var c := play.get_center()
		var two: bool = (model.towns as Array).size() > 1   # 11-28b (B17): with two hamlets, frame the whole play box; hamlet 2 sat cut at the left edge
		var tc := Vector2.ZERO
		for tw in model.towns: tc += ((tw.pos as Vector2) + Vector2(0.5, 0.5)) * tm
		tc /= float(maxi(1, (model.towns as Array).size()))
		var tg := tc.lerp(c, 0.35) if two else hm.lerp(c, 0.62)
		var away := (c - hm); var yaw0 := atan2(-away.x, -away.y) if away.length() > tm else deg_to_rad(30.0)   # the camera stands behind the hamlet, looking over it to the work
		_g_yaw = yaw0 - deg_to_rad(52.0); _g_pitch = deg_to_rad(29.0)
		_dist_default = clampf(maxf(play.size.x, play.size.y) * (0.75 if two else 0.62) + 60.0 * _bs(), 120.0, mm.x * 0.8)
		_g_dist = _dist_default; _g_target = Vector3(tg.x, 0.0, tg.y)
	if title:   # from the east along the island: the hamlet in the foreground, the lighthouse at the far end, the last of the sun behind it; the menu sits over the quiet left
		var hamlet := Vector2(mm.x * 0.8, mm.y * 0.3)
		for tw in model.get("towns", []): hamlet = ((tw.pos as Vector2) + Vector2(0.5, 0.5)) * tm; break
		_g_target = Vector3(hamlet.x - 0.14 * mm.x, 0.0, hamlet.y + 0.055 * mm.x); _g_yaw = deg_to_rad(88.0); _g_pitch = deg_to_rad(12.0); _g_dist = 0.39 * mm.x
	_g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist
	_apply_camera()

## Everything the player works with, in metres: the homes, the hut and every route any design may take.
func _play_box() -> Rect2:
	var pts: Array = []
	for tw in model.get("towns", []): pts.append((tw.pos as Vector2) + Vector2(0.5, 0.5))
	for u in model.get("units", []): pts.append((u.pos as Vector2) + Vector2(0.5, 0.5))
	for r in model.get("island", {}).get("routes", []):
		for p in r: pts.append((p as Vector2) + Vector2(0.5, 0.5))
	if pts.size() < 2: return Rect2()
	var b := Rect2(pts[0] * tm, Vector2.ZERO)
	for p in pts: b = b.expand(p * tm)
	return b

func _clamp_goal() -> void:
	var mm := _map_m()
	_g_target.x = clampf(_g_target.x, -0.1 * mm.x, 1.1 * mm.x); _g_target.z = clampf(_g_target.z, -0.1 * mm.y, 1.1 * mm.y)
	_g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
	_g_pitch = clampf(_g_pitch, PITCH_MIN, PITCH_MAX)
	_g_dist = clampf(_g_dist, 25.0, _dist_default * 1.35)   # 11-28b (B01): farther out than 1.35x, the sea plane's edge showed

func _apply_camera() -> void:
	var y := yaw + (deg_to_rad(4.0) * sin(_t * 0.05) if drift else 0.0)
	var p := pitch + (deg_to_rad(1.5) * sin(_t * 0.037) if drift else 0.0)
	var tg := target
	if drift: tg += Vector3(cos(y), 0, -sin(y)) * 14.0 * sin(_t * 0.031)
	var pos := tg + Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * dist
	pos.y = maxf(pos.y, maxf(ground(pos.x, pos.z), 0.0) + 4.0)
	if not cam.is_inside_tree(): return
	pos = Kit3D.clear_eye(get_world_3d(), tg, pos)
	cam.look_at_from_position(pos, tg, Vector3.UP)
	cam.current = true

func pan_px(rel: Vector2) -> void:
	var s := dist * 0.0012
	var right := Vector3(cos(yaw), 0, -sin(yaw)); var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	_g_target += (-right * rel.x + fwd * rel.y) * s / maxf(0.35, sin(pitch) * 0.6 + 0.4)
	_clamp_goal()

func orbit_px(rel: Vector2) -> void:
	_g_yaw -= rel.x * 0.006; _g_pitch += rel.y * 0.004; _clamp_goal()

func zoom_at(sp: Vector2, f: float) -> void:
	var g := ground_point(sp)
	var nd := clampf(_g_dist / f, 25.0, _dist_default * 1.35)
	if not is_nan(g.x): _g_target = _g_target.lerp(g, (1.0 - nd / _g_dist) * 0.9)
	_g_dist = nd; _clamp_goal()

func center_on_tile(p: Vector2, z := 1.0) -> void:
	_g_target = Vector3((p.x + 0.5) * tm, 0.0, (p.y + 0.5) * tm); _g_dist = clampf(_dist_default / z, 25.0, _dist_default * 1.35); _clamp_goal()

## CB_CAM camera words for screenshots: yaw=deg, pitch=deg, dist=m, tx / ty (tiles), zoom (1 = the opening framing). They apply at once.
func set_camera_spec(spec: String) -> bool:
	var used := false
	for part in spec.split(","):
		var kv := part.strip_edges().split("=")
		if kv.size() < 2: continue
		match kv[0]:
			"yaw": _g_yaw = deg_to_rad(float(kv[1])); used = true
			"pitch": _g_pitch = deg_to_rad(float(kv[1])); used = true
			"dist": _g_dist = float(kv[1]); used = true
			"tx": _g_target.x = (float(kv[1]) + 0.5) * tm; used = true
			"ty": _g_target.z = (float(kv[1]) + 0.5) * tm; used = true
			"zoom": _g_dist = _dist_default / maxf(0.1, float(kv[1])); used = true
			"nodrift": drift = false; used = true
			"node":   # QA shots: aim at the first node whose name matches the pattern (wildcards allowed), e.g. node=Home*
				var nd := find_child(kv[1], true, false) as Node3D
				if nd != null:
					var c := nd.global_position
					if nd is VisualInstance3D: c = (nd as VisualInstance3D).global_transform * (nd as VisualInstance3D).get_aabb().get_center()
					_g_target = c; used = true
	_clamp_goal()
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist; _apply_camera()
	return used

func _process(dt: float) -> void:
	if not visible or field == null: return
	_t += dt
	var k := 1.0 - exp(-dt * 9.0)
	target = target.lerp(_g_target, k); yaw = lerp_angle(yaw, _g_yaw, k); pitch = lerpf(pitch, _g_pitch, k); dist = lerpf(dist, _g_dist, k)
	_apply_camera()
	for b in _boats:   # moored boats ride the swell
		var bn: Node3D = b.node
		bn.position.y = float(b.y) + 0.09 * sin(_t * 1.1 + float(b.ph)); bn.rotation.z = 0.035 * sin(_t * 0.9 + float(b.ph) * 1.7); bn.rotation.x = 0.02 * sin(_t * 0.7 + float(b.ph))
	_ft_frames += 1; _ft_ms += dt * 1000.0
	if OS.has_environment("CB_FRAMETIME"):   # render time of the viewport as the RenderingServer measures it, independent of vsync
		var vp := get_viewport().get_viewport_rid()
		if not _measuring: RenderingServer.viewport_set_measure_render_time(vp, true); _measuring = true
		_ft_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp); _ft_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(); _ft_n += 1
		if _t - _ft_at > 2.0 and _t > 6.0:
			print("BAYTIME res=%dx%d gpu_ms=%.2f cpu_render_ms=%.2f frame_ms=%.2f adapter=%s quality=%s level=%s" % [get_viewport().size.x, get_viewport().size.y, _ft_gpu / _ft_n, _ft_cpu / _ft_n, _ft_ms / _ft_frames, RenderingServer.get_video_adapter_name(), quality, str(model.get("level", "-"))])
			_ft_at = _t; _ft_gpu = 0.0; _ft_cpu = 0.0; _ft_n = 0; _ft_ms = 0.0; _ft_frames = 0

# --------------------------------------------------------------------------------------------------------------------
# Projection for the 2D overlay: screen <-> world (screen = the canvas coordinates of the full-rect WorldView)
# --------------------------------------------------------------------------------------------------------------------
func _canvas_scale() -> float:
	if canvas_size.x < 1.0: return 1.0
	return get_viewport().get_visible_rect().size.x / canvas_size.x

func project(p: Vector3) -> Vector2:
	if cam.is_position_behind(p): return Vector2(-99999, -99999)
	return cam.unproject_position(p) / _canvas_scale()

## The ground (or the sea surface) under a screen point, in metres; NAN when the ray misses.
func ground_point(sp: Vector2) -> Vector3:
	var vp := sp * _canvas_scale()
	var o := cam.project_ray_origin(vp); var d := cam.project_ray_normal(vp)
	var t := 0.0; var step := maxf(1.0, dist * 0.01)
	for _i in 800:
		var p := o + d * t
		if p.y <= maxf(ground(p.x, p.z), 0.0):
			var lo := t - step; var hi := t
			for _k in 12:
				var mid := (lo + hi) * 0.5; var q := o + d * mid
				if q.y <= maxf(ground(q.x, q.z), 0.0): hi = mid
				else: lo = mid
			return o + d * hi
		t += step; step *= 1.01
		if t > 30000.0: break
	return Vector3(NAN, NAN, NAN)

func px_per_tile() -> float:
	var a := project(target); var b := project(target + Vector3(tm, 0, 0))
	return maxf(1.0, a.distance_to(b))
