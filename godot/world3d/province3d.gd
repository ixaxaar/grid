class_name Province3D
extends Node3D
## LOOK2 (docs/LOOK2.md): the province as a real 3D landscape under a real sky, for the levels that have been rebuilt (the vertical slice: L30).
## It reads the same WorldModel dictionary the 2D diorama reads (WorldView.model) and draws it: terrain from the engine's map, forests, towns
## whose windows are lit by each building's energy (WorldMath.building_energy, from the engine's bus voltage), yards, the hydro set, the
## overhead routes with the engine's supports and sags, the sea cable, the island's battery and lighthouse, the trawler at the anchor-cut
## minute, the sun and moon at the operator clock. It computes no physics. WorldView keeps picking, labels and pegs and asks this node to
## project points and to turn the camera.

const VEX := 1.0                 # vertical scale inside the map: 1 (the clearances on screen are the engine's)
const PXM := RouteDraw.PX_PER_M  # WorldView's z px per metre

var quality := "high"            # high (Forward+ discrete GPU) | medium | low (Compatibility / Mobile / CI)
var field: TerrainField
var tm := 50.0
var map_size := Vector2.ZERO     # metres
var model: Dictionary = {}
var cam: Camera3D
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var _terrain_id := ""
var _layout_sig := ""
var _routes_sig := ""
var _root_static: Node3D
var _root_infra: Node3D
var _root_dyn: Node3D
var _houses: Array = []          # [{mm: MultiMesh, town_ids: PackedStringArray per instance, idx: PackedInt32Array}]
var _house_mm: Array[MultiMesh] = []
var _house_map: Array = []       # per multimesh: Array of [town_id, energy index]
var _town_lamps: Dictionary = {} # town id -> Array[Node3D] (lamps, light pools)
var _yard_lights: Dictionary = {}# sub id -> Array[Node3D]
var _wire_glow: Dictionary = {}  # line id -> MeshInstance3D (glow overlay of the conductors)
var _cable: Dictionary = {}      # sea cable visuals
var _battery: Dictionary = {}
var _lighthouse: Dictionary = {}
var _trawler: Node3D
var _cable_ok := false
var _unit_lights: Array = []
var _water_mats: Array[ShaderMaterial] = []
var _t := 0.0
var _hmat: ShaderMaterial
var _town_inst := {}             # town id -> [[multimesh index, instance, energy index, distance from centre 0..1]]
var _town_lampmm := {}           # town id -> [MultiMesh, PackedFloat32Array distances, Array[Transform3D]]
var _street_mat: ShaderMaterial   # streets glow at night by town, widened far away (street.gdshader)
var _core_mat: ShaderMaterial     # the town cores (town_core.gdshader)
var _cam_fresh := false
var _big_centre := Vector2(INF, INF)   # the largest town's centre (world x, z): the opening camera looks at it when it is far from the map's middle (chapter 3 maps)
var _town_lit := PackedFloat32Array()   # per town index: the lit share shown, eased toward the engine's over one wave
var _wave := {}                  # town id -> {t0, sig}: when the town's energies last changed (the wave runs out from the centre)
var _perf_off: PackedStringArray = OS.get_environment("CB_PERF_OFF").split(",")   # QA: switch a cost off to find what a frame spends (forests, houses, lamps, lines, water, shed, farterrain, 3d, glow, fsr)
var _shed_mats := {}             # town id -> ShaderMaterial of its shed-sector shadow (shed_cast.gdshader), generated provinces only
var _town_geo := {}              # town id -> {c: Vector2 centre (m), rot: float main-street angle, cnt: int energy sectors}
var _subst := {}                 # town id -> {p: Vector3 yard centre, dir: Vector2 unit vector from the town towards the incoming transmission line}
var _warn: Array = []            # red warning lights on the yard gantries: blink at night
var _warn_l: Array = []          # red warning lights on the tower tops
var _night_lights: Array = []    # 1.19: works floodlights: on at night
var dist_max := DIST_MAX
const WAVE_S := 3.2              # seconds for a wave to cross a town

# camera rig (smoothed toward the goal values)
var target := Vector3.ZERO
var yaw := 0.0                   # radians, 0 = looking north (-Z)
var pitch := deg_to_rad(38.0)
var dist := 3000.0
var _g_target := Vector3.ZERO
var _g_yaw := 0.0
var _g_pitch := deg_to_rad(38.0)
var _g_dist := 3000.0
const PITCH_MIN := deg_to_rad(8.0)
const PITCH_MAX := deg_to_rad(84.0)
const DIST_MIN := 60.0
const DIST_MAX := 9500.0
var perf := {"frames": 0, "ms": 0.0, "worst": 0.0}
var _measuring := false
var _ft_gpu := 0.0
var _ft_cpu := 0.0
var _ft_n := 0
var _ft_at := 0.0

static func pick_quality() -> String:
	var q := OS.get_environment("CB_QUALITY")
	if q != "": return q
	var rm := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	if DisplayServer.get_name() == "headless": return "low"
	return quality_for(RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_type())
	@warning_ignore("unreachable_code")
	return rm

## Pure part of pick_quality (tests/town_lights_truth.gd). An integrated GPU gets low even under Forward+: medium measured 118 ms a frame on a Radeon
## iGPU at 1280x800 (8 fps), low 12.6 ms (LOOK2 phase B).
static func quality_for(drv: String, adapter: String, type: int) -> String:
	if drv == "gl_compatibility": return "low"
	if type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU or type == RenderingDevice.DEVICE_TYPE_CPU: return "low"
	if drv == "mobile": return "medium"
	var name := adapter.to_lower()
	if name.contains("nvidia") or name.contains("radeon rx") or name.contains("arc"): return "high"
	return "medium"

func _ready() -> void:
	quality = pick_quality()
	_root_static = Node3D.new(); _root_static.name = "Static"; add_child(_root_static)
	_root_infra = Node3D.new(); _root_infra.name = "Infra"; add_child(_root_infra)
	_root_dyn = Node3D.new(); _root_dyn.name = "Dynamic"; add_child(_root_dyn)
	cam = Camera3D.new(); cam.name = "Camera"; cam.near = 1.0; cam.far = 90000.0; cam.fov = 42.0; add_child(cam)
	_make_env()
	print("LOOK2 province3d quality=%s renderer=%s adapter=%s" % [quality, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])

func active() -> bool: return visible and field != null

# --------------------------------------------------------------------------------------------------------------------
# Environment: sky, sun and moon, fog, tonemapping, GI by tier
# --------------------------------------------------------------------------------------------------------------------
func _make_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new(); sky_mat = ShaderMaterial.new(); sky_mat.shader = load("res://world3d/shaders/sky.gdshader")
	var nt := NoiseTexture2D.new(); nt.seamless = true; nt.width = 512; nt.height = 512
	var fn := FastNoiseLite.new(); fn.frequency = 0.012; fn.fractal_octaves = 5; nt.noise = fn
	sky_mat.set_shader_parameter("noise", nt)
	if ResourceLoader.exists("res://world3d/tex/sky_day_pano.hdr"):   # CC0 HDRIs (docs/ASSETS.md): a midday sky for the day, the night sky with its moon; the shader turns each to the scene's sun and moon
		sky_mat.set_shader_parameter("pano_day", load("res://world3d/tex/sky_day_pano.hdr")); sky_mat.set_shader_parameter("pano_day_k", 1.0)
		sky_mat.set_shader_parameter("pano", load("res://world3d/tex/sky_night_pano.hdr")); sky_mat.set_shader_parameter("pano_k", 1.0)
	sky.sky_material = sky_mat; sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME if quality == "high" else Sky.PROCESS_MODE_INCREMENTAL
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = quality != "low"
	if quality == "low":   # integrated GPUs: ambient from a fixed colour set by the clock (no sky radiance updates), no reflections
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
		env.sky.process_mode = Sky.PROCESS_MODE_QUALITY; env.sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.glow_intensity = 0.7; env.glow_bloom = 0.04; env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 5000.0; env.fog_depth_end = 42000.0; env.fog_depth_curve = 1.8
	env.fog_aerial_perspective = 0.35
	env.fog_sky_affect = 0.25
	env.fog_density = 1.0
	env.adjustment_enabled = true; env.adjustment_contrast = 1.06; env.adjustment_saturation = 1.04
	if quality != "low":
		env.ssao_enabled = true; env.ssao_radius = 2.0; env.ssao_intensity = 1.6
	if quality == "high":
		env.sdfgi_enabled = true; env.sdfgi_use_occlusion = true; env.sdfgi_cascades = 6; env.sdfgi_min_cell_size = 1.0
		env.ssr_enabled = true; env.ssr_max_steps = 48
		env.volumetric_fog_enabled = true; env.volumetric_fog_density = 0.00012; env.volumetric_fog_length = 2200.0
		env.volumetric_fog_anisotropy = 0.6; env.volumetric_fog_ambient_inject = 0.35
		env.volumetric_fog_gi_inject = 0.0   # 1.18: SDFGI lit the haze over every town into a pale disc (the "halo", lead's art review); proven by switching each effect off
	if _perf_off.has("fsr"): get_viewport().scaling_3d_scale = 1.0
	if _perf_off.has("3d"): RenderingServer.viewport_set_disable_3d(get_viewport().get_viewport_rid(), true)
	var off := OS.get_environment("CB_FX_OFF").split(",")   # QA: switch single effects off to find what draws an artefact
	if off.has("sdfgi"): env.sdfgi_enabled = false
	if off.has("ssr"): env.ssr_enabled = false
	if off.has("vfog"): env.volumetric_fog_enabled = false
	if off.has("ssao"): env.ssao_enabled = false
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	sun = DirectionalLight3D.new(); sun.name = "Sun"; sun.shadow_enabled = quality != "low"
	sun.directional_shadow_max_distance = 9000.0 if quality == "high" else 5000.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.light_angular_distance = 0.6
	add_child(sun)
	moon = DirectionalLight3D.new(); moon.name = "Moon"; moon.shadow_enabled = quality == "high"
	moon.directional_shadow_max_distance = 6000.0; moon.light_color = Color(0.78, 0.82, 0.95)   # 11-28b: a silver moon (the saturated blue turned every wall and tower lavender)
	add_child(moon)
	# 1.18: the sun and moon lit the haze only inside their shadow range, so a disc of brighter haze sat round the town in view (Sigrid, r7-d);
	# proven by switching it off alone (CB_FX_OFF=sunfog). The haze keeps its ambient light.
	sun.light_volumetric_fog_energy = 0.0; moon.light_volumetric_fog_energy = 0.0
	if off.has("ambfog"): env.volumetric_fog_ambient_inject = 0.0
	if quality == "high":
		RenderingServer.directional_shadow_atlas_set_size(8192, true)
		get_viewport().msaa_3d = Viewport.MSAA_4X   # geometry edges
		get_viewport().use_taa = true                # thousands of small instances and thin lattice members: temporal AA stops the shimmer
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif quality == "medium":
		get_viewport().msaa_3d = Viewport.MSAA_2X
		get_viewport().use_taa = true
	else:   # low: the 3D view renders at 60 % and is scaled up; the UI stays at full resolution
		get_viewport().scaling_3d_scale = 0.8   # 11-28: was 0.6; at 0.6 the conductors were sub-pixel and striped; the iGPU has the headroom (L16 11 ms at 0.6)
		get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR; get_viewport().fsr_sharpness = 0.35   # FSR 1 upscale with sharpening, not a bilinear blur
		get_viewport().screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA   # 11-28 (Sigrid): with no AA the lattice towers and thin lines aliased into zebra stripes on the closer chapter 5-6 cameras

## Palette by minute of the day (docs/LOOK2.md "Light"): day, golden hour, blue hour, night.
func _sky_at(mn: float) -> Dictionary:
	var n := WorldMath.night(mn); var d := WorldMath.dusk(mn)
	var zen := Color(0.20, 0.40, 0.74).lerp(Color(0.02, 0.035, 0.09), n).lerp(Color(0.09, 0.17, 0.42), d * 0.7)   # blue hour: a deep blue zenith
	var hor := Color(0.70, 0.80, 0.90).lerp(Color(0.06, 0.09, 0.18), n).lerp(Color(0.95, 0.72, 0.52), d * 0.55)   # a peach band, not a red wash
	return {"n": n, "d": d, "zen": zen, "hor": hor}

func _update_sky(mn: float) -> void:
	mn = ShiftReport.night_hold(mn)
	var s := _sky_at(mn)
	var n: float = s.n; var d: float = s.d
	sky_mat.set_shader_parameter("zenith", s.zen); sky_mat.set_shader_parameter("horizon", s.hor)
	sky_mat.set_shader_parameter("ground", (s.hor as Color) * 0.35)
	sky_mat.set_shader_parameter("night", n); sky_mat.set_shader_parameter("dusk", d)
	sky_mat.set_shader_parameter("sun_glow", Color(1.0, 0.62, 0.32).lerp(Color(1.0, 0.9, 0.75), 1.0 - d))
	sky_mat.set_shader_parameter("cloud_lit", Color(1.0, 0.93, 0.85).lerp(Color(1.0, 0.55, 0.35), d).lerp(Color(0.10, 0.12, 0.2), n))
	sky_mat.set_shader_parameter("cloud_dark", Color(0.55, 0.58, 0.66).lerp(Color(0.35, 0.25, 0.35), d).lerp(Color(0.03, 0.04, 0.07), n))
	# the sun: east at 06:00, south at noon, west at 18:00 (the map's +X is east, +Z south); 50 degrees high at noon
	var a := (mn - 360.0) / 720.0 * PI
	var elev := sin(a) * deg_to_rad(50.0) + deg_to_rad(6.0)   # sunset near 18:30, where WorldMath.dusk peaks: raking light at the job's start
	var az := a   # 0 = east, PI/2 = south, PI = west
	var to_sun := Vector3(cos(az) * cos(elev), sin(elev), sin(az) * cos(elev) * 0.6 + 0.35 * cos(elev)).normalized()
	sun.visible = elev > deg_to_rad(-6.0)
	if sun.visible: sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	var lowk := clampf(elev / deg_to_rad(12.0), 0.0, 1.0)
	sun.light_color = Color(1.0, 0.66, 0.40).lerp(Color(1.0, 0.95, 0.88), lowk)   # golden, not red
	sun.light_energy = clampf((elev + deg_to_rad(4.0)) / deg_to_rad(10.0), 0.0, 1.0) * lerpf(0.9, 1.75, lowk)   # 1128c: 2.2 washed noon fields to pastel
	var mdir := Vector3(-0.45, 0.40, -0.80).normalized()   # a low moon: long moon shadows show the relief at night   # a high moon in the north-east sky, constant through the job's evening
	moon.look_at_from_position(Vector3.ZERO, -mdir, Vector3.UP)
	moon.light_energy = 0.6 * smoothstep(0.35, 0.85, n)   # 11-28b: was 0.85 (with the exposure lift, night read as flat blue day)
	moon.visible = moon.light_energy > 0.01
	if moon.visible and sun.visible: moon.shadow_enabled = false
	elif quality == "high": moon.shadow_enabled = true
	sky_mat.set_shader_parameter("moon_dir", mdir)
	env.ambient_light_sky_contribution = lerpf(1.0, 0.45, n) * (1.0 - 0.55 * d)   # golden hour: cool shadows against the warm sun, not a maroon wash
	env.ambient_light_color = Color(0.12, 0.14, 0.20).lerp(Color(0.30, 0.38, 0.55), d * (1.0 - n))   # 11-28b: was (0.13, 0.17, 0.30), a blue night
	env.ambient_light_energy = lerpf(1.0, 0.75, n)
	if quality == "low":   # 11-28b (B09): the low tier takes its ambient from this colour alone, and by day it was the night colour: towers and walls went black on their shadow side
		env.ambient_light_color = Color(0.58, 0.62, 0.70).lerp(Color(0.30, 0.38, 0.55), d).lerp(Color(0.12, 0.14, 0.20), n)
	env.fog_light_color = (s.hor as Color).lerp(Color(0.46, 0.55, 0.72), 0.75 * d * (1.0 - n)).lerp(Color(0.05, 0.08, 0.15), n * 0.6)   # haze stays cool at golden hour
	env.fog_light_energy = lerpf(1.0, 0.5, n)
	env.tonemap_exposure = lerpf(1.0, 1.3, n)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = Color(0.9, 0.85, 0.8).lerp(Color(0.5, 0.55, 0.7), n)
		# 1.18 (manager review: L05 washed out under white haze): thin haze by day, the full haze only at dusk and night
		env.volumetric_fog_density = lerpf(0.00003, 0.00012, clampf(maxf(n, d), 0.0, 1.0))
	var day := (1.0 - n) * (1.0 - d)
	env.adjustment_contrast = lerpf(1.06, 1.14, day); env.adjustment_saturation = lerpf(1.04, 1.16, day)   # daylight colour with some bite
	for wm in _water_mats: wm.set_shader_parameter("night", n)
	if _terrain_mat != null: _terrain_mat.set_shader_parameter("night", n)
	Look3D.grade(env, moon, n, d, quality, [_terrain_mat])

# --------------------------------------------------------------------------------------------------------------------
# Model in
# --------------------------------------------------------------------------------------------------------------------
var _terrain_mat: ShaderMaterial

var _prof_t := 0
## CB_PROFILE=1: how long each build step of the 3D world takes (ms), one PROFILE line per step.
func _tp(label: String) -> void:
	if not OS.has_environment("CB_PROFILE"): return
	var now := Time.get_ticks_msec()
	if label != "": print("PROFILE %s %d ms" % [label, now - _prof_t])
	_prof_t = now

func set_model(m: Dictionary) -> void:
	model = m
	_tp("")
	var has_t: bool = m.get("terrain") is Dictionary and not (m.terrain as Dictionary).is_empty()
	var tid: String = str(m.terrain.id) if has_t else "gen:" + str(m.level)
	if tid != _terrain_id or field == null:
		_terrain_id = tid
		if has_t: field = TerrainField.new(m.terrain, m.map, m.get("island_c", Vector2(-999, -999)))
		else:   # no engine terrain (chapters 5-9): a generated province round the engine's buses, drawn at GEN_TILE_M per tile
			var gf := GenField.new(m, clampf(30000.0 / maxf(1.0, float(m.map.x)), 200.0, 600.0))
			_tp("genfield")
			gf.cache_heights(Rect2(-1500, -1500, gf.size_m.x + 3000, gf.size_m.y + 3000), 50.0 if quality == "high" else 80.0)   # 1.18: 50 m (was 40; finale load)
			_tp("cache_heights")
			field = gf
		tm = field.tm; map_size = field.size_m
		dist_max = maxf(DIST_MAX, maxf(map_size.x, map_size.y) * 0.8)
		env.fog_depth_begin = maxf(5000.0, map_size.x * 0.3); env.fog_depth_end = maxf(42000.0, map_size.x * 2.6)   # haze in layers: depth fog by the province's size
		_build_static()
		_tp("static")
		reset_camera(); _cam_fresh = true
	var lsig := JSON.stringify([m.level, m.towns.map(func(t): return [t.id, t.pos]), m.subs.map(func(s): return [s.id, s.pos]), m.units.map(func(u): return [u.id, u.pos]), m.get("batteries", []).map(func(b): return b.id)])
	if lsig != _layout_sig:
		_layout_sig = lsig; _build_layout(); _tp("layout")
		if _cam_fresh and _big_centre.x < INF and not ("tx=" in OS.get_environment("CB_CAM") or "dist=" in OS.get_environment("CB_CAM")): reset_camera()   # the towns now exist: open on the largest one
	_cam_fresh = false
	var rsig := JSON.stringify([m.routes.map(func(r): return [r.id, r.supports.size(), r.spans.map(func(s): return s.sag_m)]), m.lines.map(func(l): return [l.id, l.kind, l.pts])])
	if rsig != _routes_sig:
		_routes_sig = rsig; _tp("")
		if not _perf_off.has("lines"): _build_lines()
		_tp("lines")
	_update_dynamic()
	_tp("dynamic")

func tile_to_world(p: Vector2, z_m := 0.0) -> Vector3:
	var x := p.x * tm; var z := p.y * tm
	return Vector3(x, ground(x, z) + z_m, z)

func ground(x: float, z: float) -> float:
	if field == null: return 0.0
	return field.height(x, z) * VEX

# --------------------------------------------------------------------------------------------------------------------
# Static world: terrain (near and far), water, forests, rocks
# --------------------------------------------------------------------------------------------------------------------
func _tex(n: String) -> Texture2D:
	var p := "res://world3d/tex/%s.jpg" % n
	if ResourceLoader.exists(p): return load(p)
	var img := Image.load_from_file(ProjectSettings.globalize_path(p))   # not imported yet (fresh checkout without an editor import)
	return ImageTexture.create_from_image(img) if img != null else null

func _build_static() -> void:
	for c in _root_static.get_children(): c.queue_free()
	var t0 := Time.get_ticks_msec()
	_terrain_mat = ShaderMaterial.new(); _terrain_mat.shader = load("res://world3d/shaders/terrain.gdshader")
	for n in ["grass", "forest", "rock", "sand"]:
		_terrain_mat.set_shader_parameter(n + "_a", _tex(n + "_albedo")); _terrain_mat.set_shader_parameter(n + "_n", _tex(n + "_normal"))
	_terrain_mat.set_shader_parameter("mud_a", _tex("mud_albedo")); _terrain_mat.set_shader_parameter("field_a", _tex("field_albedo"))
	var mn := NoiseTexture2D.new(); mn.seamless = true; mn.width = 512; mn.height = 512
	var fn := FastNoiseLite.new(); fn.frequency = 0.008; fn.fractal_octaves = 4; mn.noise = fn
	_terrain_mat.set_shader_parameter("macro_noise", mn)
	if field is GenField:
		_terrain_mat.set_shader_parameter("grass_tint", Vector3(0.62, 0.95, 0.58))
		_terrain_mat.set_shader_parameter("grass_hue", Vector3(0.72, 1.0, 1.55)); _terrain_mat.set_shader_parameter("warm_drift", Vector3(1.03, 1.05, 1.0)); _terrain_mat.set_shader_parameter("crop_hue", Vector3(0.74, 1.04, 1.30))   # 1128c r3: fresh green and pale wheat, not olive and ochre
		_terrain_mat.set_shader_parameter("wheat_c", Vector3(0.74, 0.68, 0.46)); _terrain_mat.set_shader_parameter("stubble_c", Vector3(0.60, 0.57, 0.43))
	else: _terrain_mat.set_shader_parameter("grass_tint", Vector3(0.74, 0.95, 0.56))   # 1.19 (CRITIQUE-1.18: the Mainland read pale): greener pasture, the same family as the province
	if quality == "low": _terrain_mat.set_shader_parameter("cheap", true)
	var step := 12.5 if quality == "high" else (20.0 if quality == "medium" else 30.0)
	var margin := 900.0
	if field is GenField: step = maxf(step * 4.0, map_size.x / 1000.0) if quality == "high" else maxf(step * 2.5, map_size.x / 700.0)   # 1.18: 40 m on high, the height cache's own step (25 m interpolated it and cost 4 s of the finale load)
	var near := Rect2(-margin, -margin, map_size.x + 2.0 * margin, map_size.y + 2.0 * margin)
	var mi := MeshInstance3D.new(); mi.name = "TerrainNear"; mi.mesh = field.grid_mesh(near, step); mi.material_override = _terrain_mat
	_root_static.add_child(mi)
	_tp("terrain_near")
	var far_half := maxf(26000.0, maxf(map_size.x, map_size.y) * 1.1)
	var c := map_size * 0.5
	var far := Rect2(c.x - far_half, c.y - far_half, far_half * 2.0, far_half * 2.0)
	var fstep := (220.0 if quality != "low" else 400.0) * (2.0 if field is GenField else 1.0)
	var hole := near.grow(-fstep * 1.5)
	var fm := MeshInstance3D.new(); fm.name = "TerrainFar"; fm.mesh = field.grid_mesh(far, fstep, hole, false); fm.material_override = _terrain_mat
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if quality != "high" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root_static.add_child(fm)
	_tp("terrain_far")
	if not _perf_off.has("water"): _build_water()
	_tp("water")
	if not _perf_off.has("forests"): _build_forests(near)
	_tp("forests")
	_build_rocks(); _tp("rocks")
	if not field is GenField: _build_farms(); _tp("farms")
	print("LOOK2 terrain built in %d ms (step %.1f m)" % [Time.get_ticks_msec() - t0, step])

func _water_mat(river: bool) -> ShaderMaterial:
	var wm := ShaderMaterial.new(); wm.shader = load("res://world3d/shaders/water.gdshader")
	for k in ["wave_a", "wave_b"]:
		var nt := NoiseTexture2D.new(); nt.seamless = true; nt.as_normal_map = true; nt.bump_strength = 6.0; nt.width = 512; nt.height = 512
		var fn := FastNoiseLite.new(); fn.frequency = 0.02 if k == "wave_a" else 0.035; fn.fractal_octaves = 3; fn.seed = 7 if k == "wave_a" else 11
		nt.noise = fn; wm.set_shader_parameter(k, nt)
	if river:
		wm.set_shader_parameter("shallow", Color(0.22, 0.36, 0.30)); wm.set_shader_parameter("deep", Color(0.06, 0.12, 0.12))
		wm.set_shader_parameter("flow_z", 0.02); wm.set_shader_parameter("scale", 0.35)
	_water_mats.append(wm)
	return wm

## 1.18 (manager review: L05 empty): farmsteads on the engine map's open fields, a red barn and a white farmhouse round a yard, one mesh.
## Only on grass tiles clear of towns, yards and routes; one tile in about 25, picked by a hash so the same map always has the same farms.
func _build_farms() -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for j in field.H:
		for i in field.W:
			if field.kind_at_tile(i, j) != TerrainField.K_GRASS or _h(i, j, 401) > 0.04: continue
			var x := (i + 0.25 + 0.5 * _h(i, j, 402)) * tm; var z := (j + 0.25 + 0.5 * _h(i, j, 403)) * tm
			if not _clear_of_infra(x, z): continue
			var y := ground(x, z) - 0.3; var rot := TAU * _h(i, j, 404)
			var ax := Vector3(cos(rot), 0, sin(rot)); var az := Vector3(-ax.z, 0, ax.x)
			var o := Vector3(x, y, z)
			_farm_box(st, o, ax, az, Vector3(0, 0, 0), Vector3(24, 9, 12), Color(0.55, 0.20, 0.15), Color(0.30, 0.28, 0.28), 5.0)   # barn
			_farm_box(st, o, ax, az, Vector3(4, 0, 22), Vector3(12, 6, 9), Color(0.90, 0.88, 0.82), Color(0.45, 0.24, 0.18), 3.5)   # farmhouse
			_farm_box(st, o, ax, az, Vector3(-16, 0, 6), Vector3(5, 11, 5), Color(0.62, 0.62, 0.60), Color(0.50, 0.50, 0.50), 1.0)   # silo
			any = true
	if not any: return
	st.generate_normals()
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.roughness = 0.9   # 1128c: closed and wound outward, so it culls like the rest
	var mi := MeshInstance3D.new(); mi.name = "Farms"; mi.mesh = st.commit(); mi.material_override = mat; _root_static.add_child(mi)

## A box with a gable roof, at offset `off` (x along ax, z along az) from o, for _build_farms.
func _farm_box(st: SurfaceTool, o: Vector3, ax: Vector3, az: Vector3, off: Vector3, sz: Vector3, wall: Color, roof: Color, rh: float) -> void:
	var c := o + ax * off.x + az * off.z
	var hx := ax * sz.x * 0.5; var hz := az * sz.z * 0.5; var up := Vector3(0, sz.y, 0)
	var b := [c - hx - hz, c + hx - hz, c + hx + hz, c - hx + hz]
	st.set_color(wall)
	for k in 4:
		var p0: Vector3 = b[k]; var p1: Vector3 = b[(k + 1) % 4]
		st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p1 + up)   # 1128c: walls and roofs were inside out (hidden by CULL_DISABLED, lit from inside)
		st.add_vertex(p0); st.add_vertex(p1 + up); st.add_vertex(p0 + up)
	var r0 := c - hx + up + Vector3(0, rh, 0); var r1 := c + hx + up + Vector3(0, rh, 0)
	st.set_color(wall)   # gable ends
	st.add_vertex(b[0] + up); st.add_vertex(r0); st.add_vertex(b[3] + up)
	st.add_vertex(b[1] + up); st.add_vertex(b[2] + up); st.add_vertex(r1)
	st.set_color(roof)
	for q in [[b[0] + up, b[1] + up, r1, r0], [b[2] + up, b[3] + up, r0, r1]]:
		st.add_vertex(q[0]); st.add_vertex(q[1]); st.add_vertex(q[2])
		st.add_vertex(q[0]); st.add_vertex(q[2]); st.add_vertex(q[3])

func _build_water() -> void:
	_water_mats.clear()
	var sea := MeshInstance3D.new(); sea.name = "Sea"
	var pm := PlaneMesh.new(); pm.size = Vector2(120000, 120000); pm.subdivide_width = 0; pm.subdivide_depth = 0
	sea.mesh = pm; sea.position = Vector3(map_size.x * 0.5, 0.0, map_size.y * 0.5); sea.material_override = _water_mat(false)
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root_static.add_child(sea)
	# the river: one quad per river tile at the river's water level (the bed is carved 2.6 m below it)
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	# 1.18 (DECISIONS 25): the water also covers the tiles round the river, edge to edge with no overlap; the ground hides it where it stands above
	# the water, so the bank follows the land's own contour instead of stepping tile by tile
	var wet := {}
	for j in field.H:
		for i in field.W:
			if field.kind_at_tile(i, j) != TerrainField.K_RIVER: continue
			for dj in [-1, 0, 1]:
				for di in [-1, 0, 1]: wet[Vector2i(i + di, j + dj)] = true
	# a bank tile's water is cut into 8 x 8 pieces and only the pieces whose ground dips near the water stay, so no sheet of water lies over
	# low land at the river mouth (Sigrid r7-f)
	var y := TerrainField.RIVER_LEVEL * VEX
	for key in wet:
		var i: int = key.x; var j: int = key.y
		var kd := field.kind_at_tile(i, j); var own := kd == TerrainField.K_RIVER
		if kd == TerrainField.K_SEA or kd == TerrainField.K_SAND: continue   # the sea and the beach have their own water: no raised sheet at the mouth
		var q := 8; var d := tm / q
		for b in q:
			for a in q:
				var x0 := i * tm + a * d; var z0 := j * tm + b * d; var x1 := x0 + d; var z1 := z0 + d
				if not own and minf(minf(ground(x0, z0), ground(x1, z0)), minf(ground(x0, z1), ground(x1, z1))) > y + 0.5: continue
				any = true
				st.set_normal(Vector3.UP)
				for p in [Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z0), Vector3(x1, y, z1), Vector3(x0, y, z1)]: st.add_vertex(p)
	if field is GenField:
		var rg := MeshInstance3D.new(); rg.name = "River"; rg.mesh = (field as GenField).river_mesh(); rg.material_override = _water_mat(true)
		rg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_static.add_child(rg)
	# 1.18 (manager review): where a road reaches the river it crosses on a bridge: a deck on two piers with low parapets
	if not field is GenField:
		var stone := StandardMaterial3D.new(); stone.albedo_color = Color(0.55, 0.52, 0.48); stone.roughness = 0.9
		var done := {}
		for j in field.H:
			for i in field.W:
				if field.kind_at_tile(i, j) != TerrainField.K_RIVER: continue
				for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
					var a := Vector2i(i, j) - dir; var b := Vector2i(i, j) + dir
					while field.kind_at_tile(b.x, b.y) == TerrainField.K_RIVER: b += dir
					if field.kind_at_tile(a.x, a.y) != TerrainField.K_PAVED and field.kind_at_tile(b.x, b.y) != TerrainField.K_PAVED: continue
					if done.has(a): continue
					done[a] = true
					var pa := (Vector2(a) + Vector2(0.5, 0.5)) * tm; var pb := (Vector2(b) + Vector2(0.5, 0.5)) * tm
					var mid := (pa + pb) * 0.5; var ln := pa.distance_to(pb)
					var y0 := maxf(ground(pa.x, pa.y), ground(pb.x, pb.y)) + 1.0
					var br := Node3D.new(); br.name = "Bridge"; br.position = Vector3(mid.x, y0, mid.y); br.rotation.y = 0.0 if dir.x == 1 else PI * 0.5; _root_static.add_child(br)
					var deck := MeshInstance3D.new(); var dm := BoxMesh.new(); dm.size = Vector3(ln, 1.6, 9.0); deck.mesh = dm; deck.material_override = stone; br.add_child(deck)
					for sz in [-4.3, 4.3]:
						var pp := MeshInstance3D.new(); var pm2 := BoxMesh.new(); pm2.size = Vector3(ln, 1.2, 0.5); pp.mesh = pm2; pp.material_override = stone; pp.position = Vector3(0, 1.4, sz); br.add_child(pp)
					for sx in [-0.17, 0.17]:
						var pier := MeshInstance3D.new(); var pr := BoxMesh.new(); pr.size = Vector3(3.0, 14.0, 8.0); pier.mesh = pr; pier.material_override = stone; pier.position = Vector3(sx * ln, -7.5, 0); br.add_child(pier)
	if any:
		var rv := MeshInstance3D.new(); rv.name = "River"; rv.mesh = st.commit(); rv.material_override = _water_mat(true)
		rv.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root_static.add_child(rv)

func _mm_chunked(mesh: Mesh, xforms: Array, cols: Array, mat: Material, chunk_m: float, vis_end: float, name: String, shadows := true, vis_begin := 0.0) -> void:
	var buckets := {}
	for k in xforms.size():
		var o: Vector3 = (xforms[k] as Transform3D).origin
		var key := Vector2i(floori(o.x / chunk_m), floori(o.z / chunk_m))
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(k)
	for key in buckets:
		var ids: Array = buckets[key]
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = mesh
		mm.instance_count = ids.size()
		for q in ids.size():
			mm.set_instance_transform(q, xforms[ids[q]]); mm.set_instance_color(q, cols[ids[q]])
		var mi := MultiMeshInstance3D.new(); mi.name = "%s_%d_%d" % [name, key.x, key.y]; mi.multimesh = mm; mi.material_override = mat
		mi.visibility_range_end = vis_end; mi.visibility_range_end_margin = vis_end * 0.1
		if vis_begin > 0.0: mi.visibility_range_begin = vis_begin; mi.visibility_range_begin_margin = vis_begin * 0.1
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_root_static.add_child(mi)

func _h(a: int, b: int, s: int) -> float: return WorldMath.hash2(a, b, s)

## Clearings: the routes' right of way over forest and the infrastructure sites stay free of trees.
func _clear_of_infra(x: float, z: float) -> bool:
	if field is GenField:
		var gf: GenField = field
		for t in gf.towns: if (t.c as Vector2).distance_to(Vector2(x, z)) < float(t.r) * 1.05: return false
		for f in gf.flats: if (f.c as Vector2).distance_to(Vector2(x, z)) < float(f.r) * 1.3: return false
		return true
	for t in model.towns:
		if (t.pos as Vector2 + Vector2(0.5, 0.5)).distance_to(Vector2(x, z) / tm) < 3.0: return false
	for s in model.subs:
		if (s.pos as Vector2 + Vector2(0.5, 0.5)).distance_to(Vector2(x, z) / tm) < 1.2: return false
	for r in model.routes:
		for sp in r.spans:
			var a: Vector2 = r.supports[sp.a].m; var b: Vector2 = r.supports[sp.b].m
			var p := Vector2(x, z); var ab := b - a; var l2 := ab.length_squared()
			var t := 0.0 if l2 < 1e-6 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
			if p.distance_to(a + ab * t) < 18.0: return false
	return true

func _build_forests(near: Rect2) -> void:
	var tmat := Look3D.tree_mat()   # 1128c: registered, so the night reaches it
	var con := Props3D.conifer(); var brd := Props3D.broadleaf()
	var xc: Array = []; var cc: Array = []; var xb: Array = []; var cb: Array = []
	var dens := 1.0 if quality == "high" else (0.55 if quality == "medium" else 0.12)
	var cell := (9.0 if not field is GenField else 24.0) / sqrt(dens)
	var nx := int(near.size.x / cell); var nz := int(near.size.y / cell)
	if field is GenField and DisplayServer.get_name() != "headless" and (not OS.has_environment("CB_SHOT") or OS.has_environment("CB_ASYNC_FORESTS")) and not OS.has_environment("CB_SYNC_FORESTS"):
		# 1.18 (finale load): the generated province's woods (2.5 s even in parallel rows) grow on worker threads while the job is already
		# playable; they appear a moment later. Nothing in the game reads the trees. Screenshots build them at once (CB_SHOT).
		# The job starts 20 frames after the build, once the loading card is gone: run beside the town and line builds, its threads slowed them.
		_forest_gen += 1
		_forest_job = {"id": -1, "wait": 20, "rows": [], "gen": _forest_gen, "mat": tmat, "con": con, "brd": brd, "near": near, "cell": cell, "nx": nx, "nz": nz}
		return
	for row in TerrainField.par_rows(nz, _forest_row.bind(near, cell, nx)):   # 1.18: rows in parallel (9 s single-threaded on the finale)
		xc.append_array(row[0]); cc.append_array(row[1]); xb.append_array(row[2]); cb.append_array(row[3])
	_tp("forest_rows")
	_place_forests(xc, cc, xb, cb, tmat, con, brd)

var _forest_gen := 0
var _forest_job: Dictionary = {}
## The background woods finished: add them, unless the world was rebuilt since (a newer generation).
func _forest_poll() -> void:
	if _forest_job.is_empty(): return
	if int(_forest_job.id) < 0:
		_forest_job.wait = int(_forest_job.wait) - 1
		if int(_forest_job.wait) > 0: return
		var j0 := _forest_job; var rows := []; rows.resize(int(j0.nz))
		var near: Rect2 = j0.near; var cell: float = j0.cell; var nx: int = j0.nx
		var task := func(j: int) -> void: rows[j] = _forest_row(j, near, cell, nx)
		j0.rows = rows
		j0.id = WorkerThreadPool.add_group_task(task, int(j0.nz), mini(6, OS.get_processor_count() - 2), false, "grid forests")
		return
	if not WorkerThreadPool.is_group_task_completed(int(_forest_job.id)): return
	WorkerThreadPool.wait_for_group_task_completion(int(_forest_job.id))
	var job := _forest_job; _forest_job = {}
	if int(job.gen) != _forest_gen: return
	var xc: Array = []; var cc: Array = []; var xb: Array = []; var cb: Array = []
	for row in job.rows:
		xc.append_array(row[0]); cc.append_array(row[1]); xb.append_array(row[2]); cb.append_array(row[3])
	_place_forests(xc, cc, xb, cb, job.mat, job.con, job.brd)

func _place_forests(xc: Array, cc: Array, xb: Array, cb: Array, tmat: Material, con: Mesh, brd: Mesh) -> void:
	var ve := (7000.0 if quality == "high" else 4500.0) * (1.6 if field is GenField else 1.0)
	var kit := ResourceLoader.exists(Assets3D.DIR + "trees/broad_lod1.glb")
	# three LODs: the CC0 photogrammetry trees cut in Blender (LOD0 about 4-8 k triangles near the camera, LOD1 800 beyond it), then the generated
	# trees from 1.4 km out, where one is a few pixels; the lists are split by kind first (two firs, one broadleaf)
	var far_from := 1400.0 if kit else 0.0
	if kit:
		var kinds := {"fir_a": [[], []], "fir_b": [[], []], "broad": [[], []], "birch": [[], []]}
		for pass_i in 2:
			var xs: Array = xc if pass_i == 0 else xb; var cs: Array = cc if pass_i == 0 else cb
			for i in xs.size():
				var o: Vector3 = (xs[i] as Transform3D).origin
				var k := Assets3D.broad_kind(o)
				if pass_i == 0: k = "fir_a" if (int(absf(o.x * 7.3 + o.z * 3.1)) % 3) == 0 else "fir_b"
				(kinds[k][0] as Array).append(xs[i]); (kinds[k][1] as Array).append(cs[i])
		for k in kinds:
			var l: Array = kinds[k]
			if quality != "low": Assets3D.forest_lod(_root_static, k, l[0], l[1], 0, 160.0, 0.0, 190.0, quality == "high")
			Assets3D.forest_lod(_root_static, k, l[0], l[1], 1, 320.0, 150.0 if quality != "low" else 0.0, far_from + 120.0, false)
	_mm_chunked(con, xc, cc, tmat, 600.0, ve, "Conifers", quality != "low", far_from)
	_mm_chunked(brd, xb, cb, tmat, 600.0, ve, "Broadleaf", quality != "low", far_from)
	print("LOOK2 trees: %d conifers, %d broadleaf" % [xc.size(), xb.size()])

func _forest_row(j: int, near: Rect2, cell: float, nx: int) -> Array:
	var xc: Array = []; var cc: Array = []; var xb: Array = []; var cb: Array = []
	for i in nx:
		var x := near.position.x + (i + _h(i, j, 301)) * cell; var z := near.position.y + (j + _h(i, j, 302)) * cell
		# 1.18: the cheap tests first (finale load): a point that cannot be forest, a lone tree or a hedge tree is skipped before any height or tile lookup
		var fp := Vector2(x * 0.966 - z * 0.259, x * 0.259 + z * 0.966)
		var fr := Vector2(fposmod(fp.x, 150.0), fposmod(fp.y, 95.0))
		var hedge_line := (minf(fr.x, 150.0 - fr.x) < 4.0 or minf(fr.y, 95.0 - fr.y) < 4.0) and _h(i, j, 309) > 0.82
		var lone_roll := _h(i, j, 303) > 0.993
		if not hedge_line and not lone_roll and not field.maybe_forest(x, z): continue
		var inside := field.inside(x, z)
		if not inside:   # 1.18: the trees thin out towards the rim of the near area, so no wood ends on a straight line
			var rim := minf(minf(x - near.position.x, near.end.x - x), minf(z - near.position.y, near.end.y - z))
			if _h(i, j, 312) > smoothstep(0.0, near.size.x * 0.12, rim): continue
		var h := field.height(x, z)
		if h < 2.5: continue
		var forest := field.is_forest(x, z, h)
		if not forest and inside and field is TerrainField and not field is GenField and _h(i, j, 313) > 0.8:   # 1.19: a fringe of scattered trees round a wood
			var fr0: float = field.forest_raw(x, z)
			forest = fr0 > 0.14 and fr0 < 0.45
		var lone := not forest and inside and lone_roll and field.kind_at_tile(int(x / tm), int(z / tm)) == TerrainField.K_GRASS   # a lone field tree
		var hedge := false
		if not forest and not lone and inside and hedge_line and field.kind_at_tile(int(x / tm), int(z / tm)) == TerrainField.K_GRASS:
			hedge = true   # trees along the hedgerows
		if not (forest or lone or hedge): continue
		if inside and not _clear_of_infra(x, z): continue
		var sc := (13.0 + 11.0 * _h(i, j, 304)) * (1.0 if not field is GenField else 1.35)
		if hedge: sc *= 0.7
		var conif := _h(i, j, 305) < (0.75 if z < map_size.y * 0.4 else 0.35)
		var xf := Transform3D(Basis(Vector3.UP, TAU * _h(i, j, 306)).scaled(Vector3(sc * (0.9 + 0.2 * _h(i, j, 307)), sc, sc)), Vector3(x, ground(x, z) - 0.3, z))
		var tint := Color(0.85 + 0.3 * _h(i, j, 308), 0.9 + 0.2 * _h(i, j, 310), 0.8 + 0.3 * _h(i, j, 311))
		if conif: xc.append(xf); cc.append(tint)
		else: xb.append(xf); cb.append(tint)
	return [xc, cc, xb, cb]

func _build_rocks() -> void:
	var xs: Array = []; var cs: Array = []
	var mat := StandardMaterial3D.new(); mat.vertex_color_use_as_albedo = true; mat.roughness = 0.95
	for j in field.H:
		for i in field.W:
			if field.kind_at_tile(i, j) != TerrainField.K_ROCK: continue
			for k in 4:
				var x := (i + _h(i, j, 400 + k)) * tm; var z := (j + _h(i, j, 410 + k)) * tm
				var s := 2.0 + 5.0 * _h(i, j, 420 + k)
				xs.append(Transform3D(Basis(Vector3.UP, TAU * _h(i, j, 430 + k)).scaled(Vector3(s, s * 0.7, s * 1.2)), Vector3(x, ground(x, z) - 0.5, z)))
				cs.append(Color(0.55, 0.53, 0.5) * (0.8 + 0.3 * _h(i, j, 440 + k)))
	_mm_chunked(Props3D.boulder(), xs, cs, mat, 800.0, 5000.0, "Rocks")

# --------------------------------------------------------------------------------------------------------------------
# Layout: towns, yards, the hydro set, batteries, the lighthouse (rebuilt when the buses change)
# --------------------------------------------------------------------------------------------------------------------
func _town_areas() -> Array:
	var areas: Array = []
	var seen := {}
	for j in field.H:
		for i in field.W:
			if field.kind_at_tile(i, j) != TerrainField.K_TOWN or seen.has(Vector2i(i, j)): continue
			# only real town tiles (roads share the paved code): flood fill over 't' tiles of the engine map
			if str((model.terrain.kinds as PackedStringArray)[j * field.W + i]) != "town": continue
			var q: Array = [Vector2i(i, j)]; seen[Vector2i(i, j)] = true; var tiles: Array = []
			while not q.is_empty():
				var c: Vector2i = q.pop_back(); tiles.append(c)
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + d
					if n.x < 0 or n.y < 0 or n.x >= field.W or n.y >= field.H or seen.has(n): continue
					if str((model.terrain.kinds as PackedStringArray)[n.y * field.W + n.x]) == "town": seen[n] = true; q.append(n)
			areas.append(tiles)
	return areas

func _nearest_town(p_tiles: Vector2) -> Dictionary:
	var best := {}; var bd := 1e9
	for t in model.towns:
		var d := (t.pos as Vector2 + Vector2(0.5, 0.5)).distance_to(p_tiles)
		if d < bd: bd = d; best = t
	return best

func _build_layout() -> void:
	for c in _root_infra.get_children(): c.queue_free()
	_house_mm.clear(); _house_map.clear(); _town_lamps.clear(); _yard_lights.clear(); _battery = {}; _lighthouse = {}; _unit_lights.clear()
	_town_inst.clear(); _town_lampmm.clear(); _wave.clear(); _warn.clear(); _night_lights.clear(); _lamp_mats.clear()
	_shed_mats.clear(); _town_geo.clear(); _subst.clear()
	var hmat := ShaderMaterial.new(); hmat.shader = load("res://world3d/shaders/house.gdshader"); _hmat = hmat
	hmat.set_shader_parameter("roof_far", PackedVector3Array(Assets3D.ROOF_TINTS_FAR))
	var house := Props3D.house(); var block := Props3D.block()
	var walls := [Color(0.56, 0.34, 0.26), Color(0.62, 0.40, 0.30), Color(0.64, 0.60, 0.52), Color(0.80, 0.74, 0.62), Color(0.58, 0.58, 0.56), Color(0.72, 0.64, 0.52), Color(0.50, 0.30, 0.24)]   # 11-28b audit: brick, stone, cream and grey render (all pale creams read as sugar cubes)
	if field is GenField: walls = [Color(0.78, 0.72, 0.62), Color(0.62, 0.36, 0.26), Color(0.84, 0.8, 0.72), Color(0.55, 0.32, 0.24), Color(0.7, 0.66, 0.6), Color(0.74, 0.6, 0.46), Color(0.5, 0.48, 0.46)]   # stone, brick, render
	var places: Array = []   # [x, z, w, d, h, rot, town_id, idx, block?]
	var gen := field is GenField
	_tp("layout_start")
	var tg: Dictionary = TownGen.build(field, model, quality, ground) if gen else {}
	_tp("towngen")
	var areas := _town_areas() if not gen else []
	var garden: Array = []   # plots left as gardens (trees)
	if gen:
		places = tg.places
		for cc in tg.centres:   # a core of taller blocks round each town's square, so a town has a silhouette from the map camera
			var tid := str(cc[1]); var cnt := 1
			for t in model.towns: if str(t.id) == tid: cnt = maxi(1, int(t.get("count", 1)))
			for k in clampi(3 + cnt / 6, 3, 9):
				var a := TAU * (float(k) + 0.5 * _h(k, cnt, 640)) / float(clampi(3 + cnt / 6, 3, 9)); var rr := 45.0 + 55.0 * _h(k, cnt, 641)
				var bp: Vector2 = (cc[0] as Vector2) + Vector2(cos(a), sin(a)) * rr
				var hh := 17.0 + 24.0 * _h(k, cnt, 642)
				places.append([bp.x, bp.y, 16.0 + 6.0 * _h(k, cnt, 643), 14.0 + 5.0 * _h(k, cnt, 644), hh, a + PI * 0.5, tid, int(fposmod(a - float(cc[2]), TAU) / TAU * cnt) % cnt, true, 0.1 + 0.2 * _h(k, cnt, 645)])
		_gen_substations(tg.centres)
		var pads: Array = []   # 1128c (audit: houses stood inside the WO-22 plant yard): [centre, radius]
		for u in model.get("units", []):
			if str(u.kind) in ["coal", "gas", "biomass", "nuclear", "diesel"]: pads.append([_plant_centre(u), 200.0 * _job_plant_scale()])
		for id in _subst: pads.append([(_subst[id].p as Vector3), 70.0 * CITY_YARD_SCALE / 2.0])
		if not pads.is_empty():
			var keep: Array = []
			for pl in places:
				var ok := true
				for c in pads: if Vector2(float(pl[0]) - (c[0] as Vector3).x, float(pl[1]) - (c[0] as Vector3).z).length() < float(c[1]): ok = false; break
				if ok: keep.append(pl)
			places = keep
		var sm := MeshInstance3D.new(); sm.name = "Streets"; sm.mesh = TownGen.street_mesh(tg.streets, ground)
		_street_mat = _new_street_mat(); sm.material_override = _street_mat
		sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_infra.add_child(sm)
		var radii: Array = []
		for ti in tg.centres.size(): radii.append(float((field as GenField).towns[ti].r))
		var cm := MeshInstance3D.new(); cm.name = "TownCores"; cm.mesh = TownGen.core_mesh(tg.centres, radii, ground, field as GenField)   # the warm lit core seen from play height
		_core_mat = ShaderMaterial.new(); _core_mat.shader = load("res://world3d/shaders/town_core.gdshader"); cm.material_override = _core_mat
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_infra.add_child(cm)
		if not _perf_off.has("shed"): _build_shed_cast(tg.centres)
		_town_lit = PackedFloat32Array(); _town_lit.resize(64)
		for k in places.size(): if _h(k, 1, 615) > 0.8: garden.append(Vector3(places[k][0], 0, places[k][1]) + Vector3(6, 0, 6).rotated(Vector3.UP, places[k][5]))
		var counts := {}
		for t in model.towns: counts[str(t.id)] = int(t.get("count", 1))
		_big_centre = Vector2(INF, INF); var best := -1
		var names := {}
		for t in model.towns: names[str(t.id)] = str(t.get("name", ""))
		for cc in tg.centres:
			if "Mill" in str(names.get(str(cc[1]), "")): _build_works(cc[0], cc[2], (field as GenField).town_edge(tg.centres.find(cc), cc[2]))
		for cc in tg.centres:
			_build_hall(cc[0], cc[2], int(counts.get(str(cc[1]), 1)))
			if int(counts.get(str(cc[1]), 1)) > best: best = int(counts.get(str(cc[1]), 1)); _big_centre = cc[0]
	var area_tg: Dictionary = {}
	var big_areas: Array = areas.filter(func(a): return (a as Array).size() >= 8)
	var small_areas: Array = areas.filter(func(a): return (a as Array).size() < 8)   # a hamlet of a few tiles keeps four plots a tile: grown streets left it near empty
	if not gen and not big_areas.is_empty():   # 1.18 (DECISIONS 25): the engine's town tiles get TownGen's grown streets, not four plots a tile
		area_tg = TownGen.build(AreaTowns.new(field, model, big_areas), model, quality, ground)
		places = area_tg.places
		var sm2 := MeshInstance3D.new(); sm2.name = "Streets"; sm2.mesh = TownGen.street_mesh(area_tg.streets, ground)
		_street_mat = _new_street_mat(); sm2.material_override = _street_mat
		sm2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_infra.add_child(sm2)
		_core_mat = ShaderMaterial.new(); _core_mat.shader = load("res://world3d/shaders/town_core.gdshader")
		_town_lit = PackedFloat32Array(); _town_lit.resize(64)
		for k in places.size(): if _h(k, 1, 615) > 0.78: garden.append(Vector3(places[k][0], 0, places[k][1]) + Vector3(6, 0, 6).rotated(Vector3.UP, places[k][5]))
		for cc in area_tg.centres:   # 1.19 (CRITIQUE-1.18: the Mainland town had no landmark): the church and its spire on the square, a water tower at the edge
			_build_hall(cc[0], cc[2], 0)
			_build_water_tower(cc[0] + Vector2(cos(cc[2] + 2.2), sin(cc[2] + 2.2)) * 150.0)
	var plot_areas: Array = areas if area_tg.is_empty() else small_areas
	for ai in plot_areas.size():
		var tiles: Array = plot_areas[ai]
		var c := Vector2.ZERO
		for t in tiles: c += Vector2(t) + Vector2(0.5, 0.5)
		c /= float(tiles.size())
		var tw := _nearest_town(c)
		if tw.is_empty(): continue
		var count := int(tw.count)
		var k := 0
		for tt in tiles:   # four plots per 50 m tile along two streets, set back a little; jittered sizes and angles
			var t: Vector2i = tt
			for q in 4:
				var lx := 0.27 + 0.46 * float(q % 2); var lz := 0.27 + 0.46 * float(q / 2)
				var x := (t.x + lx) * tm + (_h(t.x, t.y, 500 + q) - 0.5) * 5.0
				var z := (t.y + lz) * tm + (_h(t.x, t.y, 510 + q) - 0.5) * 5.0
				var nb := 0   # town tiles around this one: the edge of town thins out, the centre stays dense
				for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]: if tiles.has(t + dd): nb += 1
				var keep := 0.78 if nb == 4 else 0.45
				if _h(t.x, t.y, 600 + q) > keep:   # a garden, an orchard or a yard: a tree or two instead of a house
					garden.append(Vector3(x, 0, z)); continue
				var big := _h(t.x, t.y, 520 + q) > 0.9
				var w := 9.0 + 5.0 * _h(t.x, t.y, 530 + q); var d := 7.0 + 3.0 * _h(t.x, t.y, 540 + q)
				var h := 5.5 + 3.5 * _h(t.x, t.y, 550 + q)
				if big: w *= 1.8; d *= 1.5; h = 9.0
				places.append([x, z, w, d, h, (_h(t.x, t.y, 560 + q) - 0.5) * 0.25 + (PI * 0.5 if _h(t.x, t.y, 570) > 0.5 else 0.0), str(tw.id), k % count, big, clampf(Vector2(x, z).distance_to((tw.pos as Vector2 + Vector2(0.5, 0.5)) * tm) / (4.0 * tm), 0.0, 1.0)])
				k += 1
	# the island (L30): cottages round the green and the school hall, outside the engine's terrain rows
	if model.has("island_c"):
		var ic: Vector2 = model.island_c
		var tw := _nearest_town(ic)
		if not tw.is_empty():
			var count := int(tw.count)
			for k in 16:
				var a := TAU * (float(k) / 16.0) + 0.3 * _h(k, 3, 580)
				var r := (0.75 + 0.55 * _h(k, 4, 581)) * tm
				var x := ic.x * tm + cos(a) * r; var z := ic.y * tm + sin(a) * r * 0.8
				places.append([x, z, 8.0 + 3.0 * _h(k, 5, 582), 6.5, 5.5 + 1.5 * _h(k, 6, 583), a + PI * 0.5, str(tw.id), k % count, false, float(k) / 16.0])
			places.append([ic.x * tm + 8.0, ic.y * tm - 6.0, 22.0, 12.0, 7.0, 0.1, str(tw.id), 0, true, 0.0])   # the school hall
	if _perf_off.has("houses"): places = []
	if quality == "low": places = places.filter(func(p): return p[8] or _h(int(p[0] * 0.7), int(p[1] * 0.7), 650) < 0.72)   # the low tier keeps about 3 houses in 4 (the cores stay whole)
	var kit_ok := ResourceLoader.exists(Assets3D.DIR + "houses/house_a.glb") and ResourceLoader.exists(Assets3D.DIR + "blocks/building-a.glb")
	_kit_mats = Assets3D.kit_house_mats() if kit_ok else []
	_kit_block_mats = Assets3D.kit_house_mats("block_palette_albedo.png", true) if kit_ok else []
	for kind in [false, true]:
		var sel: Array = places.filter(func(p): return p[8] == kind)
		if sel.is_empty(): continue
		if not _kit_mats.is_empty():
			_build_kit_houses(sel, walls, block if kind else house, hmat, kind)
			continue
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.use_custom_data = true
		mm.mesh = block if kind else house; mm.instance_count = sel.size()
		var mp: Array = []
		for q in sel.size():
			var p: Array = sel[q]
			var x: float = p[0]; var z: float = p[1]
			var g := minf(minf(ground(x - p[2] * 0.5, z), ground(x + p[2] * 0.5, z)), minf(ground(x, z - p[3] * 0.5), ground(x, z + p[3] * 0.5)))
			mm.set_instance_transform(q, Transform3D(Basis(Vector3.UP, p[5]).scaled(Vector3(p[2], p[4], p[3])), Vector3(x, g - 0.4, z)))
			mm.set_instance_color(q, walls[q % walls.size()] if not kind else Color(0.8, 0.8, 0.78))
			mm.set_instance_custom_data(q, Color(0, _h(q, 7, 590 if kind else 591), 0, 1.0 if kind else 0.0))
			mp.append([p[6], p[7]])
			if not _town_inst.has(p[6]): _town_inst[p[6]] = []
			_town_inst[p[6]].append([_house_mm.size(), q, int(p[7]), float(p[9]) + 0.06 * _h(q, 9, 592)])
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = hmat; mi.name = "Blocks" if kind else "Houses"
		_root_infra.add_child(mi)
		_house_mm.append(mm); _house_map.append(mp)
	for ai in areas.size():   # a centre for each town: a hall with a tower at the middle of its tiles
		var tl: Array = areas[ai]
		if tl.size() < 6: continue
		var cc := Vector2.ZERO
		for t2 in tl: cc += Vector2(t2) + Vector2(0.5, 0.5)
		cc = cc / float(tl.size()) * tm
		var tw2 := _nearest_town(cc / tm)
		var hall := MeshInstance3D.new(); hall.mesh = Props3D.lighthouse(); hall.scale = Vector3(1.4, 1.6, 1.4)
		var hm := StandardMaterial3D.new(); hm.albedo_color = Color(0.78, 0.74, 0.66); hm.roughness = 0.9; hall.material_override = hm
		hall.position = Vector3(cc.x, ground(cc.x, cc.y) - 0.3, cc.y); _root_infra.add_child(hall)
		var nave := MeshInstance3D.new(); var nb2 := BoxMesh.new(); nb2.size = Vector3(26, 11, 12); nave.mesh = nb2; nave.material_override = hm
		nave.position = hall.position + Vector3(16, 5.5, 0); _root_infra.add_child(nave)
		var nr := MeshInstance3D.new(); var pr := PrismMesh.new(); pr.size = Vector3(12.5, 5, 27); nr.mesh = pr; nr.rotation.y = PI * 0.5
		var rm2 := StandardMaterial3D.new(); rm2.albedo_color = Color(0.32, 0.3, 0.3); nr.material_override = rm2; nr.position = hall.position + Vector3(16, 13.5, 0); _root_infra.add_child(nr)
	# the harbour: a quay along the shore below the harbour town, with moored boats
	for ai in areas.size():
		var tl2: Array = areas[ai]
		var south := -1.0; var x0 := 1e9; var x1 := -1e9
		for t3 in tl2: south = maxf(south, float(t3.y)); x0 = minf(x0, float(t3.x)); x1 = maxf(x1, float(t3.x))
		if south < field.H - 8: continue   # only a town by the sea
		var zq := 0.0
		for j2 in range(int(south), field.H2):   # first sea row below the town
			if field.kind_at_tile(int((x0 + x1) * 0.5), j2) == TerrainField.K_SEA: zq = j2 * tm; break
		if zq <= 0.0: continue
		var qm := StandardMaterial3D.new(); qm.albedo_color = Color(0.55, 0.53, 0.5); qm.roughness = 0.95
		var quay := MeshInstance3D.new(); var qb := BoxMesh.new(); qb.size = Vector3((x1 - x0 + 0.6) * tm, 4.0, 12.0); quay.mesh = qb; quay.material_override = qm
		quay.position = Vector3((x0 + x1 + 1.0) * 0.5 * tm, 0.6, zq - 2.0); _root_infra.add_child(quay)
		for k2 in 2:
			var pier := MeshInstance3D.new(); var pb := BoxMesh.new(); pb.size = Vector3(8, 3.0, 70); pier.mesh = pb; pier.material_override = qm
			pier.position = Vector3((x0 + (x1 - x0) * (0.3 + 0.4 * k2)) * tm, 0.4, zq + 40.0); _root_infra.add_child(pier)
			for b2 in 3:
				var boat := MeshInstance3D.new(); boat.mesh = Props3D.trawler(); boat.scale = Vector3.ONE * (0.45 + 0.15 * _h(k2, b2, 620))
				var bm2 := StandardMaterial3D.new(); bm2.vertex_color_use_as_albedo = true; boat.material_override = bm2
				boat.position = pier.position + Vector3(9.0 * (1 if b2 % 2 == 0 else -1), -0.3, -20.0 + 18.0 * b2); boat.rotation.y = PI * 0.5 + 0.1 * _h(k2, b2, 621)
				_root_infra.add_child(boat)
	if not garden.is_empty():   # garden trees between the houses
		var gm := MultiMesh.new(); gm.transform_format = MultiMesh.TRANSFORM_3D; gm.use_colors = true; gm.mesh = Props3D.broadleaf()
		gm.instance_count = garden.size() * 2
		for k in garden.size():
			for q in 2:
				var gp: Vector3 = garden[k] + Vector3((_h(k, q, 610) - 0.5) * 14.0, 0, (_h(k, q, 611) - 0.5) * 14.0)
				var sc := 7.0 + 6.0 * _h(k, q, 612)
				gm.set_instance_transform(k * 2 + q, Transform3D(Basis(Vector3.UP, TAU * _h(k, q, 613)).scaled(Vector3(sc, sc, sc)), Vector3(gp.x, ground(gp.x, gp.z) - 0.3, gp.z)))
				gm.set_instance_color(k * 2 + q, Color(0.9 + 0.2 * _h(k, q, 614), 1.0, 0.85))
		var gmi := MultiMeshInstance3D.new(); gmi.multimesh = gm; var tm3 := Look3D.tree_mat(); gmi.material_override = tm3
		_root_infra.add_child(gmi)
		if ResourceLoader.exists(Assets3D.DIR + "trees/broad_lod1.glb"):   # the same garden trees as the CC0 broadleaf model near the camera; the generated blob only beyond 900 m
			var gk := {}   # per kind: oak, birch, shrub (a shrub is a quarter of a tree's height)
			for i in gm.instance_count:
				var gt := gm.get_instance_transform(i); var kd := Assets3D.broad_kind(gt.origin, true)
				if kd == "shrub": gt.basis = gt.basis.scaled(Vector3.ONE * 0.26)
				if not gk.has(kd): gk[kd] = [[], []]
				gk[kd][0].append(gt); gk[kd][1].append(gm.get_instance_color(i))
			for kd in gk:
				if quality != "low": Assets3D.forest_lod(_root_infra, kd, gk[kd][0], gk[kd][1], 0, 160.0, 0.0, 190.0, quality == "high")
				Assets3D.forest_lod(_root_infra, kd, gk[kd][0], gk[kd][1], 1, 320.0, 150.0 if quality != "low" else 0.0, 900.0, false)
			gmi.visibility_range_begin = 850.0; gmi.visibility_range_begin_margin = 80.0; gmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	_tp("houses")
	if _perf_off.has("lamps"): pass
	elif gen: _build_town_lamps(_lamps_with_sector(tg.lamps, tg.centres))
	elif not area_tg.is_empty(): _build_town_lamps(_lamps_with_sector(area_tg.lamps, area_tg.centres))
	else:
		var ll: Array = []
		for k in places.size():
			if k % 2 == 1: continue
			var lp: Vector2 = Vector2(places[k][0], places[k][1]) + Vector2(9.0, 9.0)
			ll.append([Vector3(lp.x, ground(lp.x, lp.y) + 7.0, lp.y), places[k][6], places[k][9]])
		_build_town_lamps(ll)
	for s in model.subs: _build_yard(s)
	for id in _subst: _build_city_yard(str(id))
	for u in model.units: _build_unit(u)
	for b in model.get("batteries", []): _build_battery(b)
	if model.has("island_c"): _build_lighthouse(model.island_c)
	_build_trawler()

## Which kit model a place gets: any house at random; a block by closeness of its height to the place's (a tower file above 19 m).
func _kit_pick(blocks: bool, h: float, q: int, n: int, px := 0.0, pz := 0.0) -> int:
	if not blocks: return mini(int(_h(int(px * 3.1) + q, int(pz * 2.3), 593) * n), n - 1)   # by position, so neighbours along a street are not the same house
	var lo := 4 if h > 19.0 else 0
	var best := lo; var second := lo
	for i in 4:
		var d := absf(float(Assets3D.BLOCK_HEIGHT[lo + i]) - h)
		if d < absf(float(Assets3D.BLOCK_HEIGHT[best]) - h): second = best; best = lo + i
		elif lo + i != best and (second == best or d < absf(float(Assets3D.BLOCK_HEIGHT[second]) - h)): second = lo + i
	return second if _h(q, 13, 595) > 0.55 else best

var _kit_block_mats: Array = []   # the same for the blocks (the Commercial kit's palette; lit bays from the wall grid)
var _kit_mats: Array = []   # the near house LOD's four shader materials (Assets3D.kit_house_mats): Province3D sets their night
const HOUSE_CHUNK := 250.0

## Houses as chunked MultiMeshes with two LODs: the Kenney kit models (PBR, a lit pane each) within `near` metres, the generated box beyond it.
## Both carry the engine's per-building energy in INSTANCE_CUSTOM.r, and both are listed in _town_inst, so the lit and dark waves reach each.
func _build_kit_houses(sel: Array, walls: Array, box: Mesh, hmat: Material, blocks := false) -> void:
	var near := 1300.0 if quality == "high" else (900.0 if quality == "medium" else 320.0)
	var mats: Array = _kit_block_mats if blocks else _kit_mats
	var meshes: Array = []   # [mesh, height in metres]
	if blocks:
		for t in [false, true]:
			for i in (Assets3D.TOWERS if t else Assets3D.BLOCKS).size(): meshes.append([Assets3D.province_block(t, i), Assets3D.BLOCK_HEIGHT[int(t) * 4 + i]])
	else:
		for k in Assets3D.HOUSES.size(): meshes.append([Assets3D.province_house(k), 1.0])
	for m in meshes:
		var nm: Array = (m[0] as ArrayMesh).get_meta("names")
		for si in nm.size(): (m[0] as ArrayMesh).surface_set_material(si, mats[Assets3D.KIT_SURFACES.find(str(nm[si]))])
	var chunks := {}
	for q in sel.size():
		var key := Vector2i(floori(float(sel[q][0]) / HOUSE_CHUNK), floori(float(sel[q][1]) / HOUSE_CHUNK))
		if not chunks.has(key): chunks[key] = []
		(chunks[key] as Array).append(q)
	for key in chunks:
		var ids: Array = chunks[key]
		var far_mm := MultiMesh.new(); far_mm.transform_format = MultiMesh.TRANSFORM_3D; far_mm.use_colors = true; far_mm.use_custom_data = true
		far_mm.mesh = box; far_mm.instance_count = ids.size()
		var far_idx := _house_mm.size()
		_house_mm.append(far_mm); _house_map.append([])
		var by_kind := {}
		for i in ids.size():
			var q: int = ids[i]; var p: Array = sel[q]
			var x: float = p[0]; var z: float = p[1]
			var g := minf(minf(ground(x - p[2] * 0.5, z), ground(x + p[2] * 0.5, z)), minf(ground(x, z - p[3] * 0.5), ground(x, z + p[3] * 0.5)))
			var col: Color = walls[q % walls.size()]; var seed := _h(q, 7, 591)
			far_mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p[5]).scaled(Vector3(p[2], p[4], p[3])), Vector3(x, g - 0.4, z)))
			far_mm.set_instance_color(i, col if not blocks else Color(0.8, 0.8, 0.78)); far_mm.set_instance_custom_data(i, Color(0, seed, 0, 1.0 if blocks else 0.0))   # .a = a core block: the far LOD draws it taller (house.gdshader)
			var kd := _kit_pick(blocks, float(p[4]), q, meshes.size(), x, z)
			if not by_kind.has(kd): by_kind[kd] = []
			(by_kind[kd] as Array).append(i)
			if not _town_inst.has(p[6]): _town_inst[p[6]] = []
			var dist := float(p[9]) + 0.06 * _h(q, 9, 592)
			(_town_inst[p[6]] as Array).append([far_idx, i, int(p[7]), dist])
		var fm := MultiMeshInstance3D.new(); fm.name = "HousesFar_%d_%d" % [key.x, key.y]; fm.multimesh = far_mm; fm.material_override = hmat
		fm.visibility_range_begin = near + 20.0; fm.visibility_range_begin_margin = 20.0; fm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		_root_infra.add_child(fm)
		for kd in by_kind:
			var kids: Array = by_kind[kd]
			var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.use_custom_data = true
			mm.mesh = meshes[kd][0]; mm.instance_count = kids.size()
			var mi_idx := _house_mm.size()
			_house_mm.append(mm); _house_map.append([])
			for j in kids.size():
				var i: int = kids[j]; var q: int = ids[i]; var p: Array = sel[q]
				var x: float = p[0]; var z: float = p[1]
				var g := minf(minf(ground(x - p[2] * 0.5, z), ground(x + p[2] * 0.5, z)), minf(ground(x, z - p[3] * 0.5), ground(x, z + p[3] * 0.5)))
				var sc := clampf((float(p[2]) / 10.0 + float(p[3]) / 8.0) * 0.5, 0.85, 1.3) * (0.9 + 0.22 * _h(q, 14, 596))
				var turn: float = p[10] if p.size() > 10 else PI * 0.5 * floorf(_h(q, 12, 594) * 4.0)
				if blocks: sc = clampf(float(p[4]) / float(meshes[kd][1]), 0.55, 1.25); turn = PI * floorf(_h(q, 12, 594) * 2.0)
				mm.set_instance_transform(j, Transform3D(Basis(Vector3.UP, float(p[5]) + turn + (_h(q, 15, 597) - 0.5) * 0.12).scaled(Vector3(sc * (0.95 + 0.1 * _h(q, 16, 598)), sc, sc)), Vector3(x, g - 0.2, z)))
				mm.set_instance_color(j, (walls[(q + int(_h(q, 17, 599) * 5.0)) % walls.size()] * (1.0 + 0.45 * _h(q, 18, 600))) if not blocks else Color(0.86, 0.86, 0.84)); mm.set_instance_custom_data(j, Color(0, _h(q, 7, 591), 0, 0))
				(_town_inst[p[6]] as Array).append([mi_idx, j, int(p[7]), float(p[9]) + 0.06 * _h(q, 9, 592)])
			var nm := MultiMeshInstance3D.new(); nm.name = "HousesNear_%d_%d_%d" % [key.x, key.y, kd]; nm.multimesh = mm
			nm.visibility_range_end = near + 40.0; nm.visibility_range_end_margin = 20.0; nm.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			nm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if quality != "low" else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_root_infra.add_child(nm)

func _new_street_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load("res://world3d/shaders/street.gdshader")
	var a := _tex("asphalt_albedo")
	if a != null: m.set_shader_parameter("asp_a", a); m.set_shader_parameter("asphalt", true)
	return m

func _glow_mat(col: Color, power := 2.0, pulse := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new(); m.shader = load("res://world3d/shaders/glow.gdshader")
	m.set_shader_parameter("tint", col); m.set_shader_parameter("power", power); m.set_shader_parameter("pulse", pulse)
	return m

## Street lamps along the town streets (on the town tiles' plot lines) and a few warm light pools; lit only while the town has voltage.
var _lamp_mats: Array = []   # the lamp halo and road-pool materials: their night is set with the clock
## One quad per surface: a billboard halo at the lamp head and a flat pool on the road 7 m below it (lamp_glow.gdshader). One instance per lamp, so the
## engine's lit or dark area switches both together.
func _lamp_mesh() -> ArrayMesh:
	var am := ArrayMesh.new()
	for mode in (1 if quality == "low" else 2):   # the low tier skips the road pools (overdraw) and keeps the halos
		var a := []; a.resize(Mesh.ARRAY_MAX)
		var vs := PackedVector3Array(); var ix := PackedInt32Array([0, 1, 2, 0, 2, 3])
		if mode == 0: vs = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)])
		else: vs = PackedVector3Array([Vector3(-11, -6.6, -11), Vector3(11, -6.6, -11), Vector3(11, -6.6, 11), Vector3(-11, -6.6, 11)])
		a[Mesh.ARRAY_VERTEX] = vs; a[Mesh.ARRAY_INDEX] = ix
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
		var m := ShaderMaterial.new(); m.shader = load("res://world3d/shaders/lamp_glow.gdshader"); m.set_shader_parameter("mode", mode)
		am.surface_set_material(mode, m); _lamp_mats.append(m)
	return am

## Each lamp's energy sector, by the formula TownGen gives the houses (the town's angle and count), so a shed sector's lamps go dark with its houses.
func _lamps_with_sector(lamps: Array, centres: Array) -> Array:
	var info := {}
	var counts := {}
	for t in model.towns: counts[str(t.id)] = maxi(1, int(t.get("count", 1)))
	for cc in centres: info[str(cc[1])] = [cc[0], float(cc[2])]
	var out: Array = []
	for l in lamps:
		var id := str(l[1]); var idx := -1
		if info.has(id):
			var c: Vector2 = info[id][0]; var cnt: int = counts.get(id, 1)
			idx = int(fposmod(atan2(float(l[0].z) - c.y, float(l[0].x) - c.x) - float(info[id][1]), TAU) / TAU * cnt) % cnt
		out.append([l[0], l[1], l[2], idx])
	return out

func _build_town_lamps(lamp_list: Array) -> void:
	var by_town := {}
	for l in lamp_list:
		var id: String = l[1]
		if not by_town.has(id): by_town[id] = []
		by_town[id].append(l)
	var sph := _lamp_mesh()
	var pole_m := CylinderMesh.new(); pole_m.top_radius = 0.08; pole_m.bottom_radius = 0.12; pole_m.height = 7.0; pole_m.radial_segments = 5
	var pole_mat := StandardMaterial3D.new(); pole_mat.albedo_color = Color(0.25, 0.26, 0.28); pole_mat.metallic = 0.5
	for id in by_town:
		var ls: Array = by_town[id]
		if quality == "low": ls = ls.filter(func(l): return (int(absf(l[0].x * 0.37 + l[0].z * 0.91)) % 4) == 0)   # a quarter of the lamps on the low tier
		var nodes: Array = []
		var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = sph; mm.instance_count = ls.size()
		var pm2 := MultiMesh.new(); pm2.transform_format = MultiMesh.TRANSFORM_3D; pm2.mesh = pole_m; pm2.instance_count = ls.size()
		var dns := PackedFloat32Array(); var xfs: Array = []; var sec := PackedInt32Array()
		var c := Vector3.ZERO
		for k in ls.size():
			var lp: Vector3 = ls[k][0]
			var xf := Transform3D(Basis(), lp); xfs.append(xf); dns.append(float(ls[k][2])); sec.append(int(ls[k][3]) if (ls[k] as Array).size() > 3 else -1)
			mm.set_instance_transform(k, xf); pm2.set_instance_transform(k, Transform3D(Basis(), lp - Vector3(0, 3.6, 0)))
			c += lp
		c /= maxf(1.0, float(ls.size()))
		var pmi := MultiMeshInstance3D.new(); pmi.multimesh = pm2; pmi.material_override = pole_mat; pmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_infra.add_child(pmi)
		var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.extra_cull_margin = 40.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_infra.add_child(mi)
		_town_lampmm[id] = [mm, dns, xfs, mi, sec]
		var n_pool := clampi(ls.size() / 14, 1, 6 if quality != "low" else 2)
		if quality == "low": n_pool = 0   # no dynamic lights on the low tier: the amber disc and the windows carry the town
		for k in n_pool:   # warm pools of light on the streets (they also light the volumetric haze over the town)
			var l: Vector3 = ls[(k * ls.size()) / n_pool][0]
			var o := OmniLight3D.new(); o.position = l + Vector3(0, 14, 0); o.omni_range = 160.0; o.light_color = Color(1.0, 0.7, 0.42)
			o.light_energy = 2.0; o.omni_attenuation = 1.4; o.shadow_enabled = false; o.light_volumetric_fog_energy = 0.0   # 1.18: lit haze read as a pale halo (lead's review)
			_root_infra.add_child(o); nodes.append(o)
		# 1.18 (lead's art review): the amber disc under each town read as a pale halo by day and dusk; it is gone. A lit town reads by its
		# windows, its lamps and its street lines far away.
		_town_lamps[id] = nodes

## A town centre: a hall with a tower on the square, the nave along the main street.
## The town centre: a church with a tall spire, and in a big town a works chimney with a red beacon. Both are drawn larger than life (like the map) so a town
## has a silhouette from play height (art review 1.15).
func _build_hall(c: Vector2, rot: float, count := 1) -> void:
	var n := Node3D.new(); n.position = Vector3(c.x, ground(c.x, c.y) - 0.3, c.y); n.rotation.y = -rot; _root_infra.add_child(n)
	var hm := StandardMaterial3D.new(); hm.albedo_color = Color(0.8, 0.75, 0.66); hm.roughness = 0.9
	var tower := MeshInstance3D.new(); tower.mesh = Props3D.lighthouse(); tower.scale = Vector3(2.6, 6.5, 2.6) if count > 0 else Vector3(1.7, 3.2, 1.7);   # count 0: a market town's church (1.19), a spire to scale with two-storey homes var sm := StandardMaterial3D.new(); sm.albedo_color = Color(0.36, 0.33, 0.33); sm.roughness = 0.9; tower.material_override = sm;   # 1.16 (Sigrid): a dark spire that breaks the skyline
	tower.position = Vector3(-14, 0, 0); n.add_child(tower)
	var nave := MeshInstance3D.new(); var nb := BoxMesh.new(); nb.size = Vector3(28, 11, 13); nave.mesh = nb; nave.material_override = hm; nave.position = Vector3(4, 5.5, 0); n.add_child(nave)
	var roof := MeshInstance3D.new(); var pr := PrismMesh.new(); pr.size = Vector3(13.5, 5.5, 29); roof.mesh = pr; roof.rotation.y = PI * 0.5
	var rm := StandardMaterial3D.new(); rm.albedo_color = Color(0.3, 0.29, 0.3); roof.material_override = rm; roof.position = Vector3(4, 13.75, 0); n.add_child(roof)
	if count >= 14:   # the works chimney: dark brick, 140 m, a red band and beacon (1.16, Sigrid: the light 84 m one did not read at play height)
		var ch := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 4.0; cy.bottom_radius = 7.0; cy.height = 140.0; ch.mesh = cy
		var cm2 := StandardMaterial3D.new(); cm2.albedo_color = Color(0.52, 0.31, 0.24); cm2.roughness = 0.9; ch.material_override = cm2; ch.position = Vector3(70, 70.0, 55); n.add_child(ch)
		var band := MeshInstance3D.new(); var bc := CylinderMesh.new(); bc.top_radius = 4.05; bc.bottom_radius = 4.5; bc.height = 14.0; band.mesh = bc
		var bm2 := StandardMaterial3D.new(); bm2.albedo_color = Color(0.85, 0.85, 0.82); band.material_override = bm2; band.position = Vector3(70, 128.0, 55); n.add_child(band)
		var bk := MeshInstance3D.new(); var bs := SphereMesh.new(); bs.radius = 2.4; bs.height = 4.8; bk.mesh = bs
		bk.material_override = _glow_mat(Color(1.0, 0.12, 0.08), 8.0); bk.position = Vector3(70, 142.0, 55); n.add_child(bk); _warn.append(bk)
	var sq := MeshInstance3D.new(); var sb := BoxMesh.new(); sb.size = Vector3(60, 0.3, 60); sq.mesh = sb
	var sqm := StandardMaterial3D.new(); sqm.albedo_color = Color(0.55, 0.52, 0.47); sqm.roughness = 0.95; sq.material_override = sqm; sq.position = Vector3(0, 0.35, 0); n.add_child(sq)

## A steel water tower on four legs (about 32 m): a landmark that reads above roofs and trees from play height.
func _build_water_tower(c: Vector2) -> void:
	var n := Node3D.new(); n.name = "WaterTower"; n.position = Vector3(c.x, ground(c.x, c.y) - 0.3, c.y); _root_infra.add_child(n)
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.72, 0.74, 0.72); steel.metallic = 0.4; steel.roughness = 0.5
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 4:
		var a := TAU * float(k) / 4.0 + PI * 0.25
		Props3D._cyl(st, Vector3(cos(a) * 7.0, 0, sin(a) * 7.0), Vector3(cos(a) * 4.0, 24.0, sin(a) * 4.0), 0.5, 0.4, 6, Color(0.6, 0.62, 0.6))
		var b := TAU * float(k + 1) / 4.0 + PI * 0.25
		Props3D._cyl(st, Vector3(cos(a) * 5.5, 12.0, sin(a) * 5.5), Vector3(cos(b) * 5.5, 12.0, sin(b) * 5.5), 0.25, 0.25, 5, Color(0.6, 0.62, 0.6))
	st.generate_normals()
	var legs := MeshInstance3D.new(); legs.mesh = st.commit(); var lm := StandardMaterial3D.new(); lm.vertex_color_use_as_albedo = true; lm.metallic = 0.4; lm.roughness = 0.55; legs.material_override = lm; n.add_child(legs)
	var tank := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 6.5; cy.bottom_radius = 6.5; cy.height = 7.0; tank.mesh = cy; tank.material_override = steel; tank.position = Vector3(0, 27.5, 0); n.add_child(tank)
	var cap := MeshInstance3D.new(); var cn := CylinderMesh.new(); cn.top_radius = 0.6; cn.bottom_radius = 6.8; cn.height = 3.0; cap.mesh = cn; cap.material_override = steel; cap.position = Vector3(0, 32.5, 0); n.add_child(cap)
	var bk := MeshInstance3D.new(); var bs := SphereMesh.new(); bs.radius = 0.8; bs.height = 1.6; bk.mesh = bs; bk.material_override = _glow_mat(Color(1.0, 0.12, 0.08), 6.0); bk.position = Vector3(0, 34.4, 0); n.add_child(bk); _warn.append(bk)

## 1.17 (manager, Sigrid): the mill as a place. Beyond the mill town's edge, along its main street: three weaving sheds with saw-tooth roofs,
## an engine house with two brick chimneys, a yard of bales, and a rail siding running out across the fields. Presentation only; the engine's
## mill is the load on its bus.
func _build_works(c: Vector2, rot: float, edge: float) -> void:
	var ax := Vector2(cos(rot), sin(rot)); var ay := Vector2(-ax.y, ax.x)
	var o := c + ax * (edge + 140.0)
	var n := Node3D.new(); n.name = "Works"; n.position = Vector3(o.x, ground(o.x, o.y) - 0.4, o.y); n.rotation.y = -rot; _root_infra.add_child(n)
	if OS.has_environment("CB_WORKS_AT"): print("WORKS tile=%.1f,%.1f" % [o.x / tm - 0.5, o.y / tm - 0.5])   # QA: where to point CB_CAM
	var brick := StandardMaterial3D.new(); brick.albedo_color = Color(0.5, 0.28, 0.22); brick.roughness = 0.95
	var slate := StandardMaterial3D.new(); slate.albedo_color = Color(0.46, 0.44, 0.45); slate.roughness = 0.8   # 1.18 (manager review): lighter, so each tooth's lit slope reads from above
	var lit := StandardMaterial3D.new(); lit.albedo_color = Color(0.2, 0.17, 0.12); lit.emission_enabled = true; lit.emission = Color(1.0, 0.78, 0.45); lit.emission_energy_multiplier = 1.6   # the mill runs 06:00-22:00: its windows are lit
	var roof_lit: StandardMaterial3D = lit.duplicate(); roof_lit.emission_energy_multiplier = 1.1   # panes between bars, so bright skylights no longer read as rods
	var yard := StandardMaterial3D.new(); yard.albedo_color = Color(0.58, 0.56, 0.52); yard.roughness = 1.0   # 1.19 (CRITIQUE-1.18: a dark slab from above): a pale concrete yard (it was 0.42, near black at night), lit by floodlights
	var pad := MeshInstance3D.new(); var pb := BoxMesh.new(); pb.size = Vector3(230, 0.5, 170); pad.mesh = pb; pad.material_override = yard; pad.position = Vector3(10, 0.2, 0); n.add_child(pad)
	for k in 3:   # weaving sheds: long and low, a saw-tooth of north lights
		var z := -55.0 + 42.0 * k
		var shed := MeshInstance3D.new(); var sb := BoxMesh.new(); sb.size = Vector3(120, 9, 34); shed.mesh = sb; shed.material_override = brick; shed.position = Vector3(-10, 4.5, z); n.add_child(shed)
		for t in 8:   # 1.17 (Sigrid): slate saw-teeth, the glazing only on each tooth's steep north face (it read as solar panels)
			var tooth := MeshInstance3D.new(); var pr := PrismMesh.new(); pr.left_to_right = 0.0; pr.size = Vector3(15, 5, 34); tooth.mesh = pr
			tooth.material_override = slate; tooth.position = Vector3(-62.5 + 15.0 * t + 7.5, 11.5, z); n.add_child(tooth)
			for q in 7:   # 1.18 (Sigrid r7-d): panes between dark glazing bars, and dimmer than the walls, so a roof no longer reads as a glowing rod
				var gl := MeshInstance3D.new(); var gb := BoxMesh.new(); gb.size = Vector3(0.3, 3.2, 3.4); gl.mesh = gb; gl.material_override = roof_lit
				gl.position = Vector3(-62.5 + 15.0 * t + 0.3, 11.6, -13.8 + 4.6 * q + z); n.add_child(gl)
		for sd in [-1.0, 1.0]:   # a row of lit windows down each long wall, one per bay
			for q in 18:
				var wr := MeshInstance3D.new(); var wb2 := BoxMesh.new(); wb2.size = Vector3(3.6, 2.2, 0.3); wr.mesh = wb2; wr.material_override = lit; wr.position = Vector3(-62.0 + 6.1 * q, 5.0, z + sd * 17.1); n.add_child(wr)
	for k in 6:   # 1.19: sodium floodlights round the yard, so the works reads as a lit place at night, not a slab
		var lp := Vector3(-70.0 + 34.0 * k, 0.0, 78.0 if k % 2 == 0 else -80.0)
		var post := MeshInstance3D.new(); var pc := CylinderMesh.new(); pc.top_radius = 0.25; pc.bottom_radius = 0.35; pc.height = 14.0; post.mesh = pc; post.material_override = slate; post.position = lp + Vector3(0, 7, 0); n.add_child(post)
		var head := MeshInstance3D.new(); var hb := BoxMesh.new(); hb.size = Vector3(2.2, 0.6, 1.2); head.mesh = hb; head.material_override = _glow_mat(Color(1.0, 0.7, 0.35), 3.0); head.position = lp + Vector3(0, 14.2, 0); n.add_child(head)
		var ol := OmniLight3D.new(); ol.light_color = Color(1.0, 0.72, 0.4); ol.omni_range = 70.0; ol.light_energy = 5.0; ol.omni_attenuation = 1.0; ol.position = lp + Vector3(0, 12.5, 0); n.add_child(ol)
		_night_lights.append(head); _night_lights.append(ol)
	var eng := MeshInstance3D.new(); var eb := BoxMesh.new(); eb.size = Vector3(30, 22, 26); eng.mesh = eb; eng.material_override = brick; eng.position = Vector3(75, 11, -20); n.add_child(eng)
	var er := MeshInstance3D.new(); var epr := PrismMesh.new(); epr.size = Vector3(31, 7, 27); er.mesh = epr; er.material_override = slate; er.position = Vector3(75, 25.5, -20); n.add_child(er)
	for k in 2:   # two chimneys: the works reads from across the valley
		var h := 78.0 - 16.0 * k
		var ch := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 2.4; cy.bottom_radius = 4.6; cy.height = h; ch.mesh = cy
		ch.material_override = brick; ch.position = Vector3(96 + 14 * k, h * 0.5, -36 + 30 * k); n.add_child(ch)
		var cap := MeshInstance3D.new(); var cc2 := CylinderMesh.new(); cc2.top_radius = 3.0; cc2.bottom_radius = 2.6; cc2.height = 3.0; cap.mesh = cc2
		cap.material_override = slate; cap.position = Vector3(96 + 14 * k, h + 1.5, -36 + 30 * k); n.add_child(cap)
		if quality != "low": n.add_child(_smoke(Vector3(96 + 14 * k, h + 3.0, -36 + 30 * k)))
	var cotton := StandardMaterial3D.new(); cotton.albedo_color = Color(0.86, 0.82, 0.72); cotton.roughness = 1.0
	var coal := StandardMaterial3D.new(); coal.albedo_color = Color(0.09, 0.09, 0.1); coal.roughness = 1.0
	for b in 42:   # stock in the yard: cotton bales in three stacks (1.18: a yard that reads as a works, manager review)
		var bale := MeshInstance3D.new(); var bb := BoxMesh.new(); bb.size = Vector3(4, 3, 4); bale.mesh = bb; bale.material_override = cotton
		var st := b / 14; var k := b % 14
		bale.position = Vector3(30 + 32.0 * st + 5.0 * (k % 5), 1.5 + 3.0 * float(k / 5), 52 - 5.0 * float((k / 5) % 2)); n.add_child(bale)
	var heap := MeshInstance3D.new(); var hc := CylinderMesh.new(); hc.top_radius = 1.0; hc.bottom_radius = 14.0; hc.height = 8.0; heap.mesh = hc
	heap.material_override = coal; heap.position = Vector3(100, 4.0, 10); n.add_child(heap)   # the boiler house's coal heap
	var rail := StandardMaterial3D.new(); rail.albedo_color = Color(0.22, 0.2, 0.19); rail.roughness = 0.6; rail.metallic = 0.5
	var bed := StandardMaterial3D.new(); bed.albedo_color = Color(0.38, 0.34, 0.3); bed.roughness = 1.0
	for seg in 30:   # the siding: ballast and two rails, 900 m out across the fields, following the ground
		var x0 := 120.0 + 30.0 * seg
		var wp := o + ax * x0 + ay * 70.0
		var gy := ground(wp.x, wp.y) - (n.position.y)
		var bl := MeshInstance3D.new(); var blm := BoxMesh.new(); blm.size = Vector3(30, 0.6, 4.5); bl.mesh = blm; bl.material_override = bed; bl.position = Vector3(x0, gy + 0.3, 70); n.add_child(bl)
		for sd in [-0.75, 0.75]:
			var r := MeshInstance3D.new(); var rm := BoxMesh.new(); rm.size = Vector3(30, 0.25, 0.2); r.mesh = rm; r.material_override = rail; r.position = Vector3(x0, gy + 0.75, 70 + sd); n.add_child(r)
	var slm := MultiMesh.new(); slm.transform_format = MultiMesh.TRANSFORM_3D; var sbm := BoxMesh.new(); sbm.size = Vector3(0.5, 0.25, 2.6); slm.mesh = sbm
	slm.instance_count = 300
	for k in 300:   # sleepers every 3 m: it reads as track
		var x1 := 120.0 + 3.0 * k; var wp1 := o + ax * x1 + ay * 70.0
		slm.set_instance_transform(k, Transform3D(Basis(), Vector3(x1, ground(wp1.x, wp1.y) - n.position.y + 0.65, 70)))
	var sli := MultiMeshInstance3D.new(); sli.multimesh = slm; var slmat := StandardMaterial3D.new(); slmat.albedo_color = Color(0.3, 0.22, 0.16); sli.material_override = slmat; n.add_child(sli)
	for w in 3:   # three wagons waiting at the yard end
		var wg := MeshInstance3D.new(); var wb := BoxMesh.new(); wb.size = Vector3(12, 3.6, 3.0); wg.mesh = wb; wg.material_override = brick; wg.position = Vector3(135 + 13.5 * w, 2.6, 70); n.add_child(wg)


## Chimney smoke: a slow grey plume of soft billboards, drifting with the wind.
func _smoke(at: Vector3) -> GPUParticles3D:
	var p := GPUParticles3D.new(); p.amount = 24; p.lifetime = 9.0; p.position = at; p.visibility_aabb = AABB(Vector3(-80, -5, -80), Vector3(160, 120, 160))
	var pm := ParticleProcessMaterial.new(); pm.direction = Vector3(0.35, 1.0, 0.1); pm.spread = 8.0; pm.initial_velocity_min = 4.0; pm.initial_velocity_max = 6.0
	pm.gravity = Vector3(0.6, 0.4, 0.0); pm.scale_min = 6.0; pm.scale_max = 9.0
	var sc := Curve.new(); sc.add_point(Vector2(0, 0.5)); sc.add_point(Vector2(1, 2.6)); var ct := CurveTexture.new(); ct.curve = sc; pm.scale_curve = ct
	var gr := Gradient.new(); gr.set_color(0, Color(0.62, 0.6, 0.58, 0.55)); gr.set_color(1, Color(0.62, 0.6, 0.58, 0.0)); var gt := GradientTexture1D.new(); gt.gradient = gr; pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new(); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; m.albedo_texture = _soft_dot(); q.material = m
	p.draw_pass_1 = q
	return p

var _dot: Texture2D
func _soft_dot() -> Texture2D:
	if _dot != null: return _dot
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 1)); g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL; t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(1.0, 0.5); t.width = 64; t.height = 64
	_dot = t; return t

## The shadow of the shed sectors of each generated town (shed_cast.gdshader): a fan of wedges, wedge k = the engine's energy index k (the formula
## TownGen gives the houses), over the ground and roofs. Presentation only: the engine's energies decide which wedges are shed (_set_shed).
func _build_shed_cast(centres: Array) -> void:
	var gf := field as GenField
	var counts := {}
	for t in model.towns: counts[str(t.id)] = maxi(1, int(t.get("count", 1)))
	var sub := 2 if quality == "low" else 3
	var rings := 4 if quality == "low" else 6
	for ti in centres.size():
		var id := str(centres[ti][1]); var c: Vector2 = centres[ti][0]; var rot: float = centres[ti][2]; var cnt: int = mini(int(counts.get(id, 1)), 64)
		if float(gf.towns[ti].r) <= 0.0: continue
		_town_geo[id] = {"c": c, "rot": rot, "cnt": cnt}
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_normal(Vector3.UP)
		for k in cnt:
			st.set_color(Color(float(k) / 63.0, 0, 0, 1))
			for sb in sub:
				var a0 := rot + TAU * (float(k) + float(sb) / sub) / float(cnt); var a1 := rot + TAU * (float(k) + float(sb + 1) / sub) / float(cnt)
				var e0 := gf.town_edge(ti, a0) * 1.25; var e1 := gf.town_edge(ti, a1) * 1.25
				for ri in rings:
					var r0 := float(ri) / rings; var r1 := float(ri + 1) / rings
					var q := [[a0, e0, r0], [a0, e0, r1], [a1, e1, r1], [a1, e1, r0]]
					for ix in [0, 1, 2, 0, 2, 3]:
						var pt: Array = q[ix]; var pp := c + Vector2(cos(float(pt[0])), sin(float(pt[0]))) * float(pt[1]) * float(pt[2])
						st.set_uv(Vector2(float(pt[2]), 0)); st.add_vertex(Vector3(pp.x, ground(pp.x, pp.y) + 0.9, pp.y))
		var mi := MeshInstance3D.new(); mi.name = "ShedCast_%s" % id; mi.mesh = st.commit()
		var m := ShaderMaterial.new(); m.shader = load("res://world3d/shaders/shed_cast.gdshader"); m.render_priority = 2
		var zero := PackedFloat32Array(); zero.resize(64); m.set_shader_parameter("sector_shed", zero); m.set_shader_parameter("front", 2.0)
		mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; mi.extra_cull_margin = 200.0
		_root_infra.add_child(mi); _shed_mats[id] = m

## Which wedges of a town are shed: 1 where the engine's town is live and the building energy of that sector is 0 (the same test that marks the houses).
static func shed_sectors(tw: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(); out.resize(64)
	var live := float(tw.get("v", 0.0)) > 0.0
	var en: Array = Array(tw.get("energies", []))
	for k in mini(en.size(), 64): out[k] = 1.0 if live and float(en[k]) <= 0.0 else 0.0
	return out

func _set_shed(id: String, tw: Dictionary) -> void:
	if _shed_mats.has(id): (_shed_mats[id] as ShaderMaterial).set_shader_parameter("sector_shed", shed_sectors(tw))

## The city substation of a job: where a transmission line ends at a town, the yard stands just inside the last tower (the line's ring is 140 m), drawn
## CITY_YARD_SCALE times larger than a plain yard so it reads from play height. Only the jobs of chapters 5 and 6 (JOB_SUBJECT) get one.
const CITY_YARD_SCALE := 3.5
func _gen_substations(centres: Array) -> void:
	if not JOB_SUBJECT.has(str(model.get("level", ""))): return
	for cc in centres:
		var id := str(cc[1]); var c: Vector2 = cc[0]
		var tw := {}
		for t in model.towns: if str(t.id) == id: tw = t
		if tw.is_empty(): continue
		var dir := Vector2.ZERO
		for l in model.lines:
			var kind := str(l.kind)
			if kind == "xfmr" or kind == "cable" or float(l.get("kv", 11.0)) < 66.0: continue
			var pts: Array = l.pts
			if pts.size() < 2: continue
			if (pts[0] as Vector2).distance_to(tw.pos) < 0.3: dir += ((pts[1] as Vector2) - (pts[0] as Vector2)).normalized()
			elif (pts[pts.size() - 1] as Vector2).distance_to(tw.pos) < 0.3: dir += ((pts[pts.size() - 2] as Vector2) - (pts[pts.size() - 1] as Vector2)).normalized()
		if dir.length() < 0.01: continue
		dir = dir.normalized()
		var p := c + dir * 100.0
		_subst[id] = {"p": Vector3(p.x, ground(p.x, p.y), p.y), "dir": dir}

func _build_city_yard(id: String) -> void:
	var sd: Dictionary = _subst[id]
	_yard_at(sd.p, "town:" + id, CITY_YARD_SCALE, -atan2((sd.dir as Vector2).y, (sd.dir as Vector2).x))

func _build_yard(s: Dictionary) -> void:
	_yard_at(tile_to_world(s.pos as Vector2 + Vector2(0.5, 0.5)), str(s.id), 1.0, 0.0)

func _yard_at(p: Vector3, key: String, sc: float, yaw_y: float) -> void:
	var y := Node3D.new(); y.name = "Yard_%s" % key; y.position = p; y.scale = Vector3.ONE * sc; y.rotation.y = yaw_y; _root_infra.add_child(y)
	var pad := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(26, 0.6, 18); pad.mesh = bm
	var pm := StandardMaterial3D.new(); pm.albedo_color = Color(0.5, 0.49, 0.46); pm.roughness = 1.0; pad.material_override = pm
	pad.position = Vector3(0, 0.1, 0); y.add_child(pad)
	var fence := StandardMaterial3D.new(); fence.albedo_color = Color(0.6, 0.62, 0.64, 0.28); fence.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; fence.metallic = 0.6; fence.roughness = 0.4; fence.cull_mode = BaseMaterial3D.CULL_DISABLED
	for e in [[Vector3(0, 1.2, -9), Vector3(26, 2.2, 0.08)], [Vector3(0, 1.2, 9), Vector3(26, 2.2, 0.08)], [Vector3(-13, 1.2, 0), Vector3(0.08, 2.2, 18)], [Vector3(13, 1.2, 0), Vector3(0.08, 2.2, 18)]]:
		var f := MeshInstance3D.new(); var fb := BoxMesh.new(); fb.size = e[1]; f.mesh = fb; f.material_override = fence; f.position = e[0]; y.add_child(f)
	for k in 2:   # the yard kit: two transformers, the gantry, a control hut
		var t2 := MeshInstance3D.new(); t2.mesh = Props3D.transformer(); t2.position = Vector3(-8 + 6 * k, 0.4, 3); var tm4 := StandardMaterial3D.new(); tm4.vertex_color_use_as_albedo = true; tm4.roughness = 0.5; tm4.metallic = 0.3; t2.material_override = tm4; y.add_child(t2)
	var hut := MeshInstance3D.new(); var hb := BoxMesh.new(); hb.size = Vector3(6, 3.2, 4); hut.mesh = hb; var hm3 := StandardMaterial3D.new(); hm3.albedo_color = Color(0.7, 0.68, 0.62); hut.material_override = hm3; hut.position = Vector3(8, 2.0, 5); y.add_child(hut)
	var tr := MeshInstance3D.new(); tr.mesh = Props3D.transformer(); tr.position = Vector3(-5, 0.4, 2); tr.visible = false
	var tmat := StandardMaterial3D.new(); tmat.vertex_color_use_as_albedo = true; tmat.roughness = 0.5; tmat.metallic = 0.3
	tr.material_override = tmat; y.add_child(tr)
	var g := MeshInstance3D.new(); g.mesh = Props3D.gantry(); g.material_override = tmat; g.position = Vector3(5, 0.4, -2); y.add_child(g)
	_yard_kit(y, tmat)
	var lamp := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; lamp.mesh = sm
	lamp.material_override = _glow_mat(Color(0.75, 0.85, 1.0), 4.0); lamp.position = Vector3(0, 8, -8); y.add_child(lamp)
	var o := OmniLight3D.new(); o.position = Vector3(0, 10, 0); o.omni_range = 45.0; o.light_color = Color(0.8, 0.88, 1.0); o.light_energy = 1.5; y.add_child(o)
	_yard_lights[key] = [lamp, o]
	if quality == "low": o.free(); _yard_lights[key] = [lamp]

## The switchgear of a yard: fence posts and top rail, three breaker bays, the busbars on posts and a red warning light on the gantry.
func _yard_kit(y: Node3D, steel: Material) -> void:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var g := Color(0.55, 0.57, 0.6)
	for k in 14:   # fence posts round the 26 x 18 m pad, and the top rail
		var t := float(k) / 14.0 * 88.0
		var p := Vector3(-13 + minf(t, 26.0), 0, -9) if t < 26.0 else (Vector3(13, 0, -9 + (t - 26.0)) if t < 44.0 else (Vector3(13 - (t - 44.0), 0, 9) if t < 70.0 else Vector3(-13, 0, 9 - (t - 70.0))))
		Props3D._cyl(st, p, p + Vector3(0, 2.4, 0), 0.05, 0.05, 4, g)
	for e in [[Vector3(-13, 2.4, -9), Vector3(13, 2.4, -9)], [Vector3(13, 2.4, -9), Vector3(13, 2.4, 9)], [Vector3(13, 2.4, 9), Vector3(-13, 2.4, 9)], [Vector3(-13, 2.4, 9), Vector3(-13, 2.4, -9)]]:
		Props3D._cyl(st, e[0], e[1], 0.03, 0.03, 3, g)
	for x in [-9.0, 0.0, 9.0]:   # busbar posts and the three phase bars at 6 m
		for z in [-6.5, -4.5]: Props3D._cyl(st, Vector3(x, 0.4, z), Vector3(x, 6.0, z), 0.12, 0.1, 5, Color(0.75, 0.76, 0.78))
	for ph in 3:
		var z := -6.8 + ph * 0.9
		Props3D._cyl(st, Vector3(-10, 6.0 + ph * 0.0, z), Vector3(10, 6.0, z), 0.09, 0.09, 6, Color(0.78, 0.6, 0.4))
	st.generate_normals()
	var mi := MeshInstance3D.new(); mi.mesh = st.commit(); var mm := StandardMaterial3D.new(); mm.vertex_color_use_as_albedo = true; mm.metallic = 0.6; mm.roughness = 0.4
	mi.material_override = mm; y.add_child(mi)
	var br := Props3D.breaker()
	for k in 3:
		var b := MeshInstance3D.new(); b.mesh = br; b.material_override = mm; b.position = Vector3(-7 + 7 * k, 0.4, -1.5); y.add_child(b)
	var warn := MeshInstance3D.new(); var ws := SphereMesh.new(); ws.radius = 0.35; ws.height = 0.7; warn.mesh = ws
	warn.material_override = _glow_mat(Color(1.0, 0.12, 0.08), 6.0); warn.position = Vector3(5, 8.6, -2); y.add_child(warn); _warn.append(warn)

func _build_unit(u: Dictionary) -> void:
	if str(u.kind) in ["coal", "gas", "biomass", "nuclear", "diesel"]: _build_plant(u); return
	if str(u.kind) != "hydro" and not str(u.kind).contains("hydro"): return
	var p := tile_to_world(u.pos as Vector2 + Vector2(0.5, 0.5))
	var n := Node3D.new(); n.name = "Hydro_%s" % u.id; n.position = p; _root_infra.add_child(n)
	var hmat := StandardMaterial3D.new(); hmat.albedo_color = Color(0.72, 0.68, 0.6); hmat.roughness = 0.9
	var b := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(16, 9, 11); b.mesh = bm; b.material_override = hmat; b.position = Vector3(0, 4.0, 0); n.add_child(b)
	var r := MeshInstance3D.new(); var rm := PrismMesh.new(); rm.size = Vector3(17, 3.5, 12); r.mesh = rm
	var rmat := StandardMaterial3D.new(); rmat.albedo_color = Color(0.3, 0.32, 0.34); r.material_override = rmat; r.position = Vector3(0, 10.2, 0); n.add_child(r)
	# the penstock: a steel pipe down the hillside from the west
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev := Vector3(-8, 3, 0)
	for k in range(1, 13):
		var x := -8.0 - k * 28.0
		var q := Vector3(x, ground(p.x + x, p.z + sin(k * 0.4) * 6.0) - p.y + 1.4, sin(k * 0.4) * 6.0)
		Props3D._cyl(st, prev, q, 1.1, 1.1, 8, Color(0.36, 0.33, 0.3))
		prev = q
	st.generate_normals()
	var pipe := MeshInstance3D.new(); pipe.mesh = st.commit(); var pmat := StandardMaterial3D.new(); pmat.vertex_color_use_as_albedo = true; pmat.metallic = 0.5; pmat.roughness = 0.45
	pipe.material_override = pmat; n.add_child(pipe)
	var win := MeshInstance3D.new(); var wm := BoxMesh.new(); wm.size = Vector3(14, 2.0, 0.2); win.mesh = wm; win.material_override = _glow_mat(Color(1.0, 0.78, 0.5), 2.5)
	win.position = Vector3(0, 5.0, 5.6); n.add_child(win)
	_unit_lights.append([str(u.id), win])

## 1.19: a thermal station where the engine has one (the prologue's two pockets, the finale's plants). Coal and nuclear: a boiler or reactor
## house, a long turbine hall, a tall chimney and two cooling towers; gas, diesel and biomass: a turbine hall with short stacks. Windows and
## the towers' steam follow the unit's `online`; the chimney carries red warning lights.
## 1128c: where a plant's yard centre lands (the same rule _build_plant uses), so the town generator's houses stay off the pad.
func _plant_centre(u: Dictionary) -> Vector3:
	var p := tile_to_world(u.pos as Vector2 + Vector2(0.5, 0.5))
	var big := str(u.kind) == "coal" or str(u.kind) == "nuclear"
	var away := Vector2.ZERO   # behind the yard, away from the lines that leave it, so no conductor runs into a tower
	for l in model.lines:
		var pts: Array = l.pts
		if pts.size() < 2: continue
		if (pts[0] as Vector2).distance_to(u.pos) < 0.6: away -= ((pts[1] as Vector2) - (pts[0] as Vector2)).normalized()
		elif (pts[pts.size() - 1] as Vector2).distance_to(u.pos) < 0.6: away -= ((pts[pts.size() - 2] as Vector2) - (pts[pts.size() - 1] as Vector2)).normalized()
	away = away.normalized() if away.length() > 0.01 else Vector2(-0.8, -0.6)
	var ps := _job_plant_scale()
	var off := Vector3(away.x, 0.0, away.y) * 260.0 * (1.0 + 0.6 * (ps - 1.0))
	return Vector3(p.x + off.x, 0.0, p.z + off.z)

## A lamp seen from the play camera: a billboard halo that grows with distance (lamp_glow.gdshader), at `pos` in `parent`. `col` red for aviation lights.
var _beacon_mesh: ArrayMesh
func _beacon(parent: Node3D, pos: Vector3, col: Color, gain := 2.2, size_k := 0.006) -> MeshInstance3D:
	if _beacon_mesh == null:
		_beacon_mesh = ArrayMesh.new(); var a := []; a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, -1, 0), Vector3(1, -1, 0), Vector3(1, 1, 0), Vector3(-1, 1, 0)]); a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_beacon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	var mi := MeshInstance3D.new(); mi.mesh = _beacon_mesh; mi.position = pos; mi.extra_cull_margin = 40.0
	var m := ShaderMaterial.new(); m.shader = load("res://world3d/shaders/lamp_glow.gdshader"); m.set_shader_parameter("mode", 0); m.set_shader_parameter("tint", col)
	m.set_shader_parameter("gain", gain); m.set_shader_parameter("size_k", size_k); _lamp_mats.append(m)
	mi.material_override = m; mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; parent.add_child(mi)
	return mi

func _build_plant(u: Dictionary) -> void:
	var p := tile_to_world(u.pos as Vector2 + Vector2(0.5, 0.5))
	var big := str(u.kind) == "coal" or str(u.kind) == "nuclear"
	var away := Vector2.ZERO   # behind the yard, away from the lines that leave it, so no conductor runs into a tower
	for l in model.lines:
		var pts: Array = l.pts
		if pts.size() < 2: continue
		if (pts[0] as Vector2).distance_to(u.pos) < 0.6: away -= ((pts[1] as Vector2) - (pts[0] as Vector2)).normalized()
		elif (pts[pts.size() - 1] as Vector2).distance_to(u.pos) < 0.6: away -= ((pts[pts.size() - 2] as Vector2) - (pts[pts.size() - 1] as Vector2)).normalized()
	away = away.normalized() if away.length() > 0.01 else Vector2(-0.8, -0.6)
	var ps := _job_plant_scale()
	var off := Vector3(away.x, 0.0, away.y) * 260.0 * (1.0 + 0.6 * (ps - 1.0))
	var n := Node3D.new(); n.name = "Plant_%s" % u.id; n.scale = Vector3.ONE * ps; n.position = Vector3(p.x + off.x, ground(p.x + off.x, p.z + off.z) - 0.5, p.z + off.z); n.rotation.y = -atan2(away.y, away.x); _root_infra.add_child(n)
	var conc := StandardMaterial3D.new(); conc.albedo_color = Color(0.74, 0.73, 0.7); conc.roughness = 0.95
	var clad := ShaderMaterial.new(); clad.shader = load("res://world3d/shaders/clad.gdshader")   # 11-28b: ribbed, seamed, streaked cladding (was a flat grey box)
	clad.set_shader_parameter("base", Color(0.46, 0.50, 0.53) if big else Color(0.58, 0.60, 0.61)); clad.set_shader_parameter("grime", _tex("rock_rough"))
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.34, 0.33, 0.31); dark.roughness = 1.0   # 11-28b audit: the yard read as a pale untextured slab
	dark.albedo_texture = _tex("rock_albedo"); dark.uv1_triplanar = true; dark.uv1_scale = Vector3.ONE * 0.04
	var pad := MeshInstance3D.new(); var pbm := BoxMesh.new(); pbm.size = Vector3(300, 0.6, 210); pad.mesh = pbm; pad.position = Vector3(20, 0.3, 0); n.add_child(pad)
	var ym := ShaderMaterial.new(); ym.shader = load("res://world3d/shaders/yard.gdshader"); pad.material_override = ym   # 1128c: slabs, stains, tracks (the flat box went black at night)
	for cx in [-128.0, 168.0]:   # 1128c: yard floodlights at the pad corners (the plant stood unlit at night)
		for cz in [-102.0, 102.0]:
			Kit3D.flood_mast(n, Vector3(cx, 0.6, cz), Vector3(20.0, 0.0, 0.0), quality, 28.0, "plant")
			_night_lights.append(_beacon(n, Vector3(cx, 29.0, cz), Color(1.0, 0.8, 0.5), 2.0, 0.0045))   # the mast head as a lamp from the map camera
	var hall_l := 110.0 if big else 70.0
	var hall := MeshInstance3D.new(); var hm := BoxMesh.new(); hm.size = Vector3(hall_l, 26, 34); hall.mesh = hm; hall.material_override = clad; hall.position = Vector3(0, 13, 0); n.add_child(hall)
	var lit := StandardMaterial3D.new(); lit.albedo_color = Color(0.2, 0.17, 0.12); lit.emission_enabled = true; lit.emission = Color(1.0, 0.8, 0.5); lit.emission_energy_multiplier = 2.2
	var win := Node3D.new(); win.name = "Windows"; n.add_child(win)
	for sd in [-1.0, 1.0]:
		for row in 2:
			var band := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(hall_l - 8.0, 1.6, 0.3); band.mesh = bm; band.material_override = lit
			band.position = Vector3(0, 7.0 + 9.0 * row, sd * 17.1); win.add_child(band)
	if big:
		var boiler := MeshInstance3D.new(); var bx := BoxMesh.new(); bx.size = Vector3(44, 68, 40); boiler.mesh = bx; boiler.material_override = clad; boiler.position = Vector3(-hall_l * 0.5 - 22.0, 34, 0); n.add_child(boiler)
		var bl := MeshInstance3D.new(); var blm := BoxMesh.new(); blm.size = Vector3(0.3, 50, 1.4); bl.mesh = blm; bl.material_override = lit; bl.position = Vector3(-hall_l * 0.5 - 44.2, 34, 0); win.add_child(bl)
		var h := 165.0
		var ch := MeshInstance3D.new(); var cy := CylinderMesh.new(); cy.top_radius = 4.5; cy.bottom_radius = 8.0; cy.height = h; ch.mesh = cy; var chm := ShaderMaterial.new(); chm.shader = load("res://world3d/shaders/concrete.gdshader"); chm.set_shader_parameter("grime", _tex("rock_rough")); chm.set_shader_parameter("top_y", h * 0.5); chm.set_shader_parameter("tint", Color(0.66, 0.65, 0.62)); ch.material_override = chm
		ch.position = Vector3(-hall_l * 0.5 - 70.0, h * 0.5, 30); n.add_child(ch)
		for k in 2:   # red aviation lights near the top and half way
			var wl := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 2.2; sm.height = 4.4; wl.mesh = sm; wl.material_override = _glow_mat(Color(1.0, 0.12, 0.08), 4.0)
			wl.position = Vector3(-hall_l * 0.5 - 70.0 + 5.0, h * (1.0 - 0.45 * k) - 3.0, 30); n.add_child(wl); _warn.append(wl)
			_warn.append(_beacon(n, wl.position, Color(1.0, 0.1, 0.06), 2.6, 0.007))
		if quality != "low": n.add_child(_smoke(Vector3(-hall_l * 0.5 - 70.0, h + 2.0, 30)))
		var tower := _cooling_tower_mesh()
		var tconc := ShaderMaterial.new(); tconc.shader = load("res://world3d/shaders/concrete.gdshader"); tconc.set_shader_parameter("grime", _tex("rock_rough"))   # 11-28b: pour lifts, rain streaks, a soot band (it read as pale plastic)
		# the lathe's winding is not checked: both faces; weathered darker toward the foot
		for k in 2:
			var tw := MeshInstance3D.new(); tw.mesh = tower; tw.material_override = tconc; tw.position = Vector3(hall_l * 0.5 + 70.0 + 95.0 * k, 0, 40.0 - 20.0 * k); n.add_child(tw)
			var throat := MeshInstance3D.new(); var thm := CylinderMesh.new(); thm.top_radius = 26.5; thm.bottom_radius = 26.5; thm.height = 0.5; thm.radial_segments = 24; throat.mesh = thm   # 1128c art review 2: from above the hollow read as a black void
			var thmat := StandardMaterial3D.new(); thmat.albedo_color = Color(0.62, 0.64, 0.68); thmat.roughness = 1.0; thmat.emission_enabled = true; thmat.emission = Color(0.20, 0.21, 0.24); throat.material_override = thmat
			throat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; throat.position = tw.position + Vector3(0, 104.0, 0); n.add_child(throat)
			for q4 in 4: _warn.append(_beacon(n, tw.position + Vector3(cos(TAU * q4 / 4.0) * 27.0, 116.0, sin(TAU * q4 / 4.0) * 27.0), Color(1.0, 0.1, 0.06), 2.0, 0.006))   # aircraft lights round the rim   # a steam-filled throat
			if quality != "low":
				var steam := _smoke(Vector3(tw.position.x, 118.0, tw.position.z)); steam.name = "Steam%d" % k; steam.amount = 30
				var sm2 := steam.process_material as ParticleProcessMaterial; sm2.scale_min = 40.0; sm2.scale_max = 60.0; sm2.initial_velocity_min = 3.0; sm2.initial_velocity_max = 5.0
				var g := Gradient.new(); g.set_color(0, Color(0.8, 0.82, 0.86, 0.6)); g.set_color(1, Color(0.8, 0.82, 0.86, 0.0)); var gt := GradientTexture1D.new(); gt.gradient = g; sm2.color_ramp = gt
				win.add_child(steam)   # the steam stops with the unit
		var heap := MeshInstance3D.new(); var hc := CylinderMesh.new(); hc.top_radius = 3.0; hc.bottom_radius = 36.0; hc.height = 20.0; hc.radial_segments = 24; heap.mesh = hc   # 1128c: a pile, not a flat black disc on the new yard
		var coal := StandardMaterial3D.new(); coal.albedo_color = Color(0.16, 0.15, 0.15); coal.roughness = 0.85; coal.metallic = 0.15; heap.material_override = coal; heap.position = Vector3(-40, 10, -75); n.add_child(heap)
	else:
		for k in 2:   # heat-recovery boilers and their stacks
			var hr := MeshInstance3D.new(); var hb := BoxMesh.new(); hb.size = Vector3(18, 30, 26); hr.mesh = hb; hr.material_override = clad; hr.position = Vector3(hall_l * 0.5 + 14.0, 15, -18.0 + 36.0 * k); n.add_child(hr)
			var st := MeshInstance3D.new(); var sc := CylinderMesh.new(); sc.top_radius = 3.2; sc.bottom_radius = 3.6; sc.height = 62.0; st.mesh = sc; st.material_override = conc
			st.position = Vector3(hall_l * 0.5 + 30.0, 31, -18.0 + 36.0 * k); n.add_child(st)
			if quality != "low": win.add_child(_smoke(Vector3(hall_l * 0.5 + 30.0, 63.0, -18.0 + 36.0 * k)))
			_warn.append(_beacon(n, Vector3(hall_l * 0.5 + 30.0, 64.5, -18.0 + 36.0 * k), Color(1.0, 0.1, 0.06), 2.2, 0.006))
	_unit_lights.append([str(u.id), win])

static var _ct_mesh: ArrayMesh
## A hyperbolic cooling tower, 115 m tall, as a lathe: r(y) = r_throat * sqrt(1 + ((y - y_throat) / c)^2).
static func _cooling_tower_mesh() -> ArrayMesh:
	if _ct_mesh != null: return _ct_mesh
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 28; var seg := 72; var H := 115.0; var yt := 0.78 * H; var rt := 26.0; var c := 50.0
	var r := func(y: float) -> float: return rt * sqrt(1.0 + pow((y - yt) / c, 2.0))
	for i in rings:
		var y0 := H * float(i) / rings; var y1 := H * float(i + 1) / rings
		var r0: float = r.call(y0); var r1: float = r.call(y1)
		for k in seg:
			var a0 := TAU * float(k) / seg; var a1 := TAU * float(k + 1) / seg
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0); var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1); var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var c0 := Color(0.44, 0.42, 0.39).lerp(Color(0.66, 0.64, 0.60), y0 / H); var c1 := Color(0.44, 0.42, 0.39).lerp(Color(0.66, 0.64, 0.60), y1 / H)   # weathered concrete, not porcelain (Sigrid)
			if i == rings - 1: c1 = Color(0.42, 0.42, 0.42)   # the soot-dark lip
			for q in [[p00, p10, p11], [p00, p11, p01]]:
				for v in q:
					st.set_color(c1 if v.y > (y0 + y1) * 0.5 else c0); st.add_vertex(v)
	st.index(); st.generate_normals()   # 11-28b: shared vertices, smooth normals
	var m := st.commit()
	_ct_mesh = m; return m

func _build_battery(b: Dictionary) -> void:
	var p := tile_to_world(b.pos as Vector2 + Vector2(1.3, 1.1))
	var n := Node3D.new(); n.name = "Battery_%s" % b.id; n.position = p; _root_infra.add_child(n)
	var box := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(12.2, 2.6, 2.45); box.mesh = bm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.86, 0.86, 0.82); m.roughness = 0.6; box.material_override = m; box.position = Vector3(0, 1.5, 0); n.add_child(box)
	var bar := MeshInstance3D.new(); var bb := BoxMesh.new(); bb.size = Vector3(1, 0.5, 0.1); bar.mesh = bb; bar.position = Vector3(0, 2.0, 1.28); n.add_child(bar)
	_battery = {"node": n, "bar": bar, "id": str(b.id)}

func _build_lighthouse(ic: Vector2) -> void:
	var lp := (ic + Vector2(-1.7, 0.9)) * tm
	var n := Node3D.new(); n.name = "Lighthouse"; n.position = Vector3(lp.x, ground(lp.x, lp.y) - 0.3, lp.y); _root_infra.add_child(n)
	var mi := MeshInstance3D.new(); mi.mesh = Props3D.lighthouse()
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.roughness = 0.7; mi.material_override = m; n.add_child(mi)
	var lamp := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.8; sm.height = 1.6; lamp.mesh = sm
	lamp.material_override = _glow_mat(Color(1.0, 0.92, 0.7), 8.0); lamp.position = Vector3(0, 16.4, 0); n.add_child(lamp)
	var beam := Node3D.new(); beam.position = Vector3(0, 16.4, 0); n.add_child(beam)
	for sgn in []:   # (beams removed after the art review: they read as a rendering error) two beams: long thin cones, additive, fading outward
		var c := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.6; cm.bottom_radius = 14.0; cm.height = 600.0; cm.radial_segments = 10; cm.cap_top = false; cm.cap_bottom = false
		c.mesh = cm; var gm := _glow_mat(Color(1.0, 0.93, 0.7, 0.025), 1.0); gm.set_shader_parameter("fade_v", 3.0); c.material_override = gm
		c.rotation = Vector3(0, 0, -PI * 0.5 * sgn); c.position = Vector3(300.0 * sgn, 0, 0); c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_child(c)
	var o := OmniLight3D.new(); o.omni_range = 60.0; o.light_color = Color(1, 0.9, 0.7); o.light_energy = 3.0; o.position = Vector3(0, 16.4, 0); n.add_child(o)
	_lighthouse = {"node": n, "lamp": lamp, "beam": beam, "light": o}

func _build_trawler() -> void:
	_trawler = Node3D.new(); _trawler.name = "Trawler"; _trawler.visible = false; _root_infra.add_child(_trawler)
	var mi := MeshInstance3D.new(); mi.mesh = Props3D.trawler()
	var m := StandardMaterial3D.new(); m.vertex_color_use_as_albedo = true; m.roughness = 0.6; mi.material_override = m; _trawler.add_child(mi)
	var lamp := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 1.0; lamp.mesh = sm
	lamp.material_override = _glow_mat(Color(1.0, 0.95, 0.75), 6.0); lamp.position = Vector3(1, 11.2, 0); _trawler.add_child(lamp)
	var deck := OmniLight3D.new(); deck.position = Vector3(-2, 6, 0); deck.omni_range = 30.0; deck.light_energy = 1.5; deck.light_color = Color(1, 0.9, 0.7); _trawler.add_child(deck)

# --------------------------------------------------------------------------------------------------------------------
# Lines: overhead routes (engine supports and sags), plain pole lines, the sea cable
# --------------------------------------------------------------------------------------------------------------------
func _line_by_id(id: String) -> Dictionary:
	for l in model.lines: if str(l.id) == id: return l
	return {}

func _build_lines() -> void:
	for c in _root_dyn.get_children(): c.queue_free()
	_wire_glow.clear(); _cable = {}; _warn_l.clear()
	var wire_mat := StandardMaterial3D.new(); wire_mat.albedo_color = Color(0.52, 0.54, 0.56); wire_mat.metallic = 0.8; wire_mat.roughness = 0.35
	var pole_mat := StandardMaterial3D.new(); pole_mat.vertex_color_use_as_albedo = true; pole_mat.roughness = 0.75
	var meshes := {}
	var routed := {}
	for r in model.routes:
		routed[str(r.id)] = true
		var sts := SurfaceTool.new(); sts.begin(Mesh.PRIMITIVE_TRIANGLES)
		var sup_att: Array = []   # per support: world attachment points of the three phases
		for s in r.supports:
			var fam := str(s.family)
			var key := "%s|%.1f|%.1f" % [fam, float(s.pole_m), float(s.attach_m)]
			if not meshes.has(key): meshes[key] = Props3D.support(fam, float(s.pole_m), float(s.attach_m))
			var mm: Array = meshes[key]
			var m: Vector2 = s.m
			var base := Vector3(m.x, ground(m.x, m.y), m.y)
			var d: Vector2 = s.dir
			var basis := Basis(Vector3.UP, -atan2(d.y, d.x))   # local +X along the line
			var mi := MeshInstance3D.new(); mi.mesh = mm[0]; mi.material_override = pole_mat; mi.transform = Transform3D(basis, base); _root_dyn.add_child(mi)
			var att: Array = []
			for a in mm[1]: att.append(base + basis * (a as Vector3))
			sup_att.append(att)
		var acc := 0.0
		for sp in r.spans:
			var A: Array = sup_att[int(sp.a)]; var B: Array = sup_att[int(sp.b)]
			for ph in mini(A.size(), B.size()):
				Props3D.add_wire(sts, A[ph], B[ph], float(sp.sag_m), 0.05, acc)
			acc += (A[0] as Vector3).distance_to(B[0])
		var wmesh := sts.commit()
		var wi := MeshInstance3D.new(); wi.mesh = wmesh; wi.material_override = wire_mat; wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_dyn.add_child(wi)
		# the glow overlay: the same conductors, slightly fatter, emissive in the loading band colour with pulses in the flow direction
		var stg := SurfaceTool.new(); stg.begin(Mesh.PRIMITIVE_TRIANGLES)
		acc = 0.0
		for sp in r.spans:
			var A: Array = sup_att[int(sp.a)]; var B: Array = sup_att[int(sp.b)]
			Props3D.add_wire(stg, A[min(1, A.size() - 1)], B[min(1, B.size() - 1)], float(sp.sag_m), 0.14, acc)
			acc += (A[0] as Vector3).distance_to(B[0])
		var gi := MeshInstance3D.new(); gi.mesh = stg.commit(); gi.material_override = _glow_mat(Color(0.4, 0.85, 1.0, 1.0), 1.0, 0.6)
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_dyn.add_child(gi)
		_wire_glow[str(r.id)] = gi
	for l in model.lines:
		var kind := str(l.kind)
		if routed.has(str(l.id)) or kind == "xfmr": continue
		if kind == "cable": _build_sea_cable(l); continue
		_build_pole_line(l, wire_mat, pole_mat, meshes)

func _build_pole_line(l: Dictionary, wire_mat: Material, pole_mat: Material, meshes: Dictionary) -> void:
	if field is GenField and float(l.get("kv", 11.0)) >= 66.0: _build_tower_line(l, wire_mat, meshes); return
	var pts: Array = l.pts
	var key := "pcc-11|11.0|9.0"
	if not meshes.has(key): meshes[key] = Props3D.support("pcc-11", 11.0, 9.0)
	var mm: Array = meshes[key]
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev: Array = []
	var acc := 0.0
	for k in range(pts.size() - 1):
		var a: Vector2 = (pts[k] as Vector2 + Vector2(0.5, 0.5)) * tm; var b: Vector2 = (pts[k + 1] as Vector2 + Vector2(0.5, 0.5)) * tm
		var n := maxi(1, int(round(a.distance_to(b) / 80.0)))
		for q in range(0 if k == 0 else 1, n + 1):
			var m := a.lerp(b, float(q) / n)
			var d := (b - a).normalized()
			var basis := Basis(Vector3.UP, -atan2(d.y, d.x))
			var base := Vector3(m.x, ground(m.x, m.y), m.y)
			var mi := MeshInstance3D.new(); mi.mesh = mm[0]; mi.material_override = pole_mat; mi.transform = Transform3D(basis, base); _root_dyn.add_child(mi)
			var att: Array = []
			for at in mm[1]: att.append(base + basis * (at as Vector3))
			if not prev.is_empty():
				for ph in 3: Props3D.add_wire(st, prev[ph], att[ph], 1.6, 0.05, acc)
				acc += (prev[0] as Vector3).distance_to(att[0])
			prev = att
	var wi := MeshInstance3D.new(); wi.mesh = st.commit(); wi.material_override = wire_mat; _root_dyn.add_child(wi)

## A transmission line on lattice towers: height and arm by voltage, about 330 m spans, six conductors (two circuits) and an earth wire,
## a glow overlay in the loading band colour, a red light on each tower top at night.
func _build_tower_line(l: Dictionary, wire_mat: Material, meshes: Dictionary) -> void:
	var kv := float(l.kv)
	var h := 46.0 if kv >= 300.0 else (36.0 if kv >= 200.0 else 27.0)
	var arm := 9.0 if kv >= 300.0 else (7.0 if kv >= 200.0 else 5.0)
	var key := "tower|%d" % int(h)
	if not meshes.has(key): meshes[key] = Props3D.tower(h, arm)
	var tw: Array = meshes[key]
	var tmat := ShaderMaterial.new(); tmat.shader = load("res://world3d/shaders/tower.gdshader")
	var pts: Array = l.pts
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sg := SurfaceTool.new(); sg.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xfs: Array = []; var tops: Array = []
	var prev: Array = []; var acc := 0.0
	var ring := 140.0   # towers stand outside the yards at both ends
	for k in range(pts.size() - 1):
		var a: Vector2 = (pts[k] as Vector2 + Vector2(0.5, 0.5)) * tm; var b: Vector2 = (pts[k + 1] as Vector2 + Vector2(0.5, 0.5)) * tm
		var dv := (b - a).normalized()
		if k == 0: a += dv * ring
		if k == pts.size() - 2: b -= dv * ring
		var n := maxi(1, int(round(a.distance_to(b) / 330.0)))
		for q in range(0 if k == 0 else 1, n + 1):
			var m := a.lerp(b, float(q) / n)
			var basis := Basis(Vector3.UP, -atan2(dv.y, dv.x))
			var base := Vector3(m.x, ground(m.x, m.y) - 0.3, m.y)
			xfs.append(Transform3D(basis, base))
			var att: Array = []
			for at in tw[1]: att.append(base + basis * (at as Vector3))
			tops.append(att[att.size() - 1])
			if not prev.is_empty():
				var span := (prev[0] as Vector3).distance_to(att[0])
				var sag := span * span / 8.0 / 1900.0   # a catenary parameter of about 1900 m at a warm evening
				for ph in 7: Props3D.add_wire(st, prev[ph], att[ph], sag * (0.75 if ph == 6 else 1.0), 0.11 if ph < 6 else 0.06, acc)
				Props3D.add_wire(sg, prev[1], att[1], sag, 0.3, acc); Props3D.add_wire(sg, prev[4], att[4], sag, 0.3, acc)
				acc += span
			prev = att
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = tw[0]; mm.instance_count = xfs.size()
	for k in xfs.size(): mm.set_instance_transform(k, xfs[k])
	var mi := MultiMeshInstance3D.new(); mi.multimesh = mm; mi.material_override = tmat; _root_dyn.add_child(mi)
	var cmat := ShaderMaterial.new(); cmat.shader = load("res://world3d/shaders/tower.gdshader"); cmat.set_shader_parameter("inflate", 0.00028); cmat.set_shader_parameter("metal", 0.5); cmat.set_shader_parameter("rough", 0.55); cmat.set_shader_parameter("tint", Vector3(0.42, 0.43, 0.45))   # 1128c: dark threads, not chalk lines (a polished metal tube mirrored the bright sky)
	var wi := MeshInstance3D.new(); wi.mesh = st.commit(); wi.material_override = cmat; wi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_dyn.add_child(wi)
	var gm := _glow_mat(Color(0.4, 0.85, 1.0, 1.0), 1.0, 0.6); gm.set_shader_parameter("inflate", 0.00045)
	var gi := MeshInstance3D.new(); gi.mesh = sg.commit(); gi.material_override = gm
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_dyn.add_child(gi)
	_wire_glow[str(l.id)] = gi
	var rm := MultiMesh.new(); rm.transform_format = MultiMesh.TRANSFORM_3D; var rs := SphereMesh.new(); rs.radius = 0.5; rs.height = 1.0; rs.radial_segments = 6; rs.rings = 3
	rm.mesh = rs; rm.instance_count = tops.size()
	for k in tops.size(): rm.set_instance_transform(k, Transform3D(Basis(), tops[k]))
	var ri := MultiMeshInstance3D.new(); ri.multimesh = rm; ri.material_override = _glow_mat(Color(1.0, 0.1, 0.06), 6.0); ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root_dyn.add_child(ri); _warn_l.append(ri)

## The submarine cable: an armoured line on the seabed (seen through shallow water) and a chart line on the surface, the way a control-room
## overlay draws it; pulses run along it while it carries power. After the anchor cut the far part is dark and a red marker pulses at the cut.
func _build_sea_cable(l: Dictionary) -> void:
	var pts: Array = l.pts
	if pts.size() < 2: return
	var a: Vector2 = (pts[0] as Vector2 + Vector2(0.5, 0.5)) * tm; var c: Vector2 = (pts[pts.size() - 1] as Vector2 + Vector2(0.5, 0.5)) * tm
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sc := SurfaceTool.new(); sc.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 40
	var prev := Vector3.ZERO; var prev_s := Vector3.ZERO
	for k in n + 1:
		var m := a.lerp(c, float(k) / n)
		var p := Vector3(m.x, minf(ground(m.x, m.y), 0.0) + 0.3, m.y)
		var ps := Vector3(m.x, maxf(ground(m.x, m.y), 0.0) + 1.2, m.y)
		if k > 0:
			Props3D._tube_seg(st, prev, p, 0.25, a.distance_to(m) - 1.0, a.distance_to(m))
			Props3D._tube_seg(sc, prev_s, ps, 0.7, a.distance_to(m) * 0.25 - 1.0, a.distance_to(m) * 0.25)
		prev = p; prev_s = ps
	var bed := MeshInstance3D.new(); bed.mesh = st.commit()
	var bm := StandardMaterial3D.new(); bm.albedo_color = Color(0.08, 0.08, 0.09); bm.roughness = 0.6; bed.material_override = bm
	_root_dyn.add_child(bed)
	var chart := MeshInstance3D.new(); chart.mesh = sc.commit(); chart.material_override = _glow_mat(Color(1.0, 0.7, 0.35, 1.0), 0.8, 0.8)
	chart.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; _root_dyn.add_child(chart)
	var cut := a.lerp(c, 0.4)
	var mk := MeshInstance3D.new(); var tm2 := TorusMesh.new(); tm2.inner_radius = 9.0; tm2.outer_radius = 12.0; tm2.rings = 24; tm2.ring_segments = 6; mk.mesh = tm2
	mk.material_override = _glow_mat(Color(1.0, 0.18, 0.12, 1.0), 4.0); mk.position = Vector3(cut.x, 1.5, cut.y); mk.visible = false; _root_dyn.add_child(mk)
	_cable = {"id": str(l.id), "chart": chart, "mark": mk, "a": a, "c": c}

# --------------------------------------------------------------------------------------------------------------------
# Every model refresh: windows, lamps, yards, conductor glow, battery, lighthouse, trawler, sky
# --------------------------------------------------------------------------------------------------------------------
func _update_dynamic() -> void:
	var mn := ShiftReport.night_hold(float(model.get("minute", 720.0)))   # 1128c: a failed report holds the night (windows and lamps too)
	if OS.is_debug_build() and OS.has_environment("CB_SKY_MIN"): mn = float(OS.get_environment("CB_SKY_MIN"))   # audit shots: a fixed clock for the sky, windows and lamps (the engine's own numbers are not touched)
	var n := WorldMath.night(mn)
	_update_sky(mn)
	var by_id := {}
	for t in model.towns: by_id[str(t.id)] = t
	if _hmat != null: _hmat.set_shader_parameter("night", n)
	for km in _kit_mats: (km as ShaderMaterial).set_shader_parameter("night", n)
	for km in _kit_block_mats: (km as ShaderMaterial).set_shader_parameter("night", n)
	for lm in _lamp_mats: (lm as ShaderMaterial).set_shader_parameter("night", n)
	for sm in _shed_mats.values(): (sm as ShaderMaterial).set_shader_parameter("night", n)
	for id in _town_inst:   # a change in a town's energies starts a wave from its centre (the first model applies at once)
		var tw: Dictionary = by_id.get(id, {})
		var sig := str(tw.get("energies", [])) + str(tw.get("v", 0.0) > 0.0)
		if not _wave.has(id): _wave[id] = {"t0": -100.0, "sig": sig, "done": false}
		elif str(_wave[id].sig) != sig: _wave[id] = {"t0": _t, "sig": sig, "done": false}
		_set_shed(id, tw)
	for id in _town_lamps:
		var tw: Dictionary = by_id.get(id, {})
		var on := not tw.is_empty() and float(tw.v) > 0.0 and n > 0.25
		var bright := clampf(float(tw.get("v", 0.0)), 0.0, 1.1)
		bright *= bright
		for node in _town_lamps[id]:
			node.visible = on
			if node is OmniLight3D: node.light_energy = 2.2 * bright * n
		if _town_lampmm.has(id): (_town_lampmm[id][3] as Node3D).visible = n > 0.25
	for nl in _night_lights: (nl as Node3D).visible = n > 0.25
	for s in model.subs:
		var ls: Array = _yard_lights.get(str(s.id), [])
		for node in ls: node.visible = bool(s.get("energised", false)) and n > 0.2
	for id in _subst:   # the city substation's lamp and flood follow the town's bus
		var tw: Dictionary = by_id.get(id, {})
		for node in _yard_lights.get("town:" + str(id), []): node.visible = not tw.is_empty() and float(tw.get("v", 0.0)) > 0.0 and n > 0.2
	for ul in _unit_lights:
		var on := false
		for u in model.units: if str(u.id) == ul[0]: on = bool(u.online)
		(ul[1] as Node3D).visible = on and n > 0.15
	for id in _wire_glow:
		var l := _line_by_id(id)
		var gi: MeshInstance3D = _wire_glow[id]
		var live := not l.is_empty() and bool(l.in_service) and (int(l.dir) != 0 or float(l.get("overload", 0.0)) > 0.0)
		var gen := field is GenField
		var idle := gen and not live and not l.is_empty() and bool(l.in_service)   # a standing line with no flow yet (before Run): a calm voltage-coloured thread, so the map reads as a grid
		gi.visible = live or idle   # 1128c (art review): by day the loading was invisible (the glow showed only at night)
		if idle:
			var kv0 := float(l.get("kv", 11.0)); var m0: ShaderMaterial = gi.material_override
			m0.set_shader_parameter("tint", Color(0.3, 0.85, 0.95, 1.0) if kv0 >= 200.0 else Color(0.45, 0.95, 0.55, 1.0)); m0.set_shader_parameter("pulse", 0.0)
			m0.set_shader_parameter("power", 0.6); m0.set_shader_parameter("inflate", 0.0007)
		if live:
			var m: ShaderMaterial = gi.material_override
			var kv := float(l.get("kv", 11.0))   # voltage colour (400 kV violet, 220 kV teal, 132 kV green, below amber); the loading band colour takes over above 90 %
			var vc := Color(0.62, 0.55, 1.0) if kv >= 300.0 else (Color(0.3, 0.85, 0.95) if kv >= 200.0 else (Color(0.45, 0.95, 0.55) if kv >= 66.0 else Color(1.0, 0.75, 0.4)))
			if float(l.get("loading", 0.0)) > 0.9 or field is TerrainField and not field is GenField or (n <= 0.3 and float(l.get("loading", 0.0)) > 0.5): vc = Color(l.color)
			m.set_shader_parameter("tint", Color(vc, 1.0)); m.set_shader_parameter("pulse", 0.25 + float(l.speed) * 0.8 * float(l.dir))
			var pw := (0.35 + 0.3 * n) * (0.35 if field is GenField else 1.0)
			var ld := float(l.get("loading", 0.0))
			if n <= 0.3 or gen:   # 1128c: by day a ramp the eye reads: teal when light, amber at 70 %, red at 100 %; brighter and wider as it loads (r3: the province's lines at night too)
				pw = (1.3 if n <= 0.3 else 1.1) + 1.5 * clampf(ld - 0.5, 0.0, 0.5)
				var rc := Color(0.3, 0.85, 0.95).lerp(Color(1.0, 0.68, 0.15), smoothstep(0.35, 0.7, ld)).lerp(Color(1.0, 0.16, 0.08), smoothstep(0.8, 1.0, ld))
				m.set_shader_parameter("tint", Color(rc, 1.0))
			if float(l.get("loading", 0.0)) > 1.0 or float(l.get("overload", 0.0)) > 0.0:   # 1128c: an overloaded line is plainly red
				m.set_shader_parameter("tint", Color(1.0, 0.16, 0.08, 1.0)); pw = maxf(pw, 2.6); m.set_shader_parameter("inflate", 0.0044 if gen else 0.0026)
			elif gen: m.set_shader_parameter("inflate", lerpf(0.0008, 0.0032, clampf(ld, 0.0, 1.0)))   # r3 (P03): at map distance 25 % and 69 % differ by a visible width (3 and 6 px at 4.5 km)
			else: m.set_shader_parameter("inflate", lerpf(0.00035, 0.0016, clampf(ld, 0.0, 1.0)))
			m.set_shader_parameter("power", pw)
	if not _cable.is_empty():
		var l := _line_by_id(str(_cable.id))
		var ok := not l.is_empty() and bool(l.in_service)
		var cm: ShaderMaterial = (_cable.chart as MeshInstance3D).material_override
		cm.set_shader_parameter("tint", Color(1.0, 0.68, 0.32, 1.0) if ok else Color(0.35, 0.38, 0.45, 1.0))
		cm.set_shader_parameter("pulse", 0.8 * float(l.get("dir", 0)) if ok else 0.0)
		cm.set_shader_parameter("power", 1.2 if ok else 0.5)
		(_cable.mark as Node3D).visible = not ok
		if _cable_ok and not ok and not OS.has_environment("CB_CAM"):   # the cut: turn the camera to the island before the report opens
			var ic: Vector2 = model.get("island_c", Vector2.ZERO)
			_g_target = tile_to_world(ic + Vector2(0, -3)); _g_dist = 1400.0; _g_pitch = deg_to_rad(26.0); _clamp_goal()
		_cable_ok = ok
	if not _battery.is_empty():
		for b in model.get("batteries", []):
			if str(b.id) != _battery.id: continue
			var soc := clampf(float(b.soc), 0.0, 1.0)
			var bar: MeshInstance3D = _battery.bar
			bar.scale = Vector3(maxf(0.05, soc) * 11.0, 1, 1); bar.position.x = -5.5 + soc * 5.5
			var col := Color("#4FB477") if soc > 0.5 else (Color("#E2A33B") if soc > 0.2 else Color("#D9483B"))
			bar.material_override = _glow_mat(col, 2.5, 0.0)
	if not _lighthouse.is_empty():
		var lit := false
		var ic: Vector2 = model.get("island_c", Vector2.ZERO)
		for tw in model.towns: if (tw.pos as Vector2).distance_to(ic) < 3.0 and float(tw.v) > 0.0: lit = true   # the lamp turns only while the island bus is live
		(_lighthouse.lamp as Node3D).visible = lit
		(_lighthouse.beam as Node3D).visible = lit and n > 0.2
		(_lighthouse.light as Node3D).visible = lit
	_place_trawler(mn)

## Lights follow the engine's energies building by building: a house switches when the wave front (WAVE_S seconds from the centre to the
## edge) passes it, so a town lights up outward from its substation and goes dark the same way. Lamps follow the same front.
## The street glow and the town core follow each town's lit share (mean window energy of its streets, 0 when the bus is dead), eased over
## one wave so a far town brightens and dims with the wave its houses show.
func _ease_town_glow(dt: float) -> void:
	if _street_mat == null or _town_lit.is_empty(): return
	var n := WorldMath.night(float(model.get("minute", 720.0)))
	for ti in mini(model.towns.size(), 64):
		var tw: Dictionary = model.towns[ti]
		var target := 0.0
		if float(tw.get("v", 0.0)) > 0.0:
			var en: Array = Array(tw.get("energies", []))
			if en.is_empty(): target = 1.0
			else:
				for e in en: target += clampf(float(e), 0.0, 1.0)
				target /= float(en.size())
		_town_lit[ti] = move_toward(_town_lit[ti], target, dt / WAVE_S)
	_street_mat.set_shader_parameter("town_lit", _town_lit); _street_mat.set_shader_parameter("night", n)
	_core_mat.set_shader_parameter("town_lit", _town_lit); _core_mat.set_shader_parameter("night", n)

func _run_waves() -> void:
	if _wave.is_empty(): return
	var by_id := {}
	for t in model.towns: by_id[str(t.id)] = t
	for id in _wave:
		var w: Dictionary = _wave[id]
		if bool(w.done): continue
		var front := (_t - float(w.t0)) / WAVE_S
		if _shed_mats.has(id): (_shed_mats[id] as ShaderMaterial).set_shader_parameter("front", front if front <= 1.2 else 2.0)
		var tw: Dictionary = by_id.get(id, {})
		var en: PackedFloat32Array = tw.get("energies", PackedFloat32Array())
		var live := not tw.is_empty() and float(tw.get("v", 0.0)) > 0.0
		for it in _town_inst.get(id, []):
			if float(it[3]) > front: continue
			var mm: MultiMesh = _house_mm[int(it[0])]
			var e := en[int(it[2]) % en.size()] if en.size() > 0 else 0.0
			var cd := mm.get_instance_custom_data(int(it[1]))
			var shed := live and e <= 0.0
			mm.set_instance_custom_data(int(it[1]), Color(clampf(e, 0.0, 1.0) * 0.82, cd.g, 1.0 if shed else 0.0, cd.a))
			w["written"] = int(w.get("written", 0)) + 1; w["shed_n"] = int(w.get("shed_n", 0)) + (1 if shed else 0)   # counted, so a headless test can see what was written (the dummy renderer keeps no buffers)   # .b: shed while the town is live (shown cool and grey by day)
		if _town_lampmm.has(id):
			var lm: Array = _town_lampmm[id]
			var dns: PackedFloat32Array = lm[1]
			for k in dns.size():
				if dns[k] > front: continue
				var xf: Transform3D = lm[2][k]
				var sx: int = (lm[4] as PackedInt32Array)[k]
				var served := live and (sx < 0 or en.size() == 0 or en[sx % en.size()] > 0.0)   # a shed sector's lamps go dark with its houses
				(lm[0] as MultiMesh).set_instance_transform(k, xf if served else Transform3D(Basis().scaled(Vector3.ONE * 0.001), xf.origin))
		if front > 1.2: w.done = true

func _place_trawler(mn: float) -> void:
	if _trawler == null or _cable.is_empty(): if _trawler != null: _trawler.visible = false; return
	var cm := float(model.get("cut_min", -1.0))
	if cm <= 0.0 or mn <= cm - 90.0 or mn >= cm + 60.0: _trawler.visible = false; return
	var u := (mn - cm) / 60.0
	var a: Vector2 = _cable.a; var c: Vector2 = _cable.c
	var mid := a.lerp(c, 0.4)
	var bp := mid + Vector2(u * 7.0, 0.4 + 0.5 * u) * tm
	_trawler.visible = true
	_trawler.position = Vector3(bp.x, 0.0, bp.y)
	_trawler.rotation = Vector3(0, -atan2(0.5, 7.0), 0)

func _process(dt: float) -> void:
	if not _forest_job.is_empty(): _forest_poll()
	if not visible or field == null: return
	_t += dt
	var k := 1.0 - exp(-dt * 9.0)
	target = target.lerp(_g_target, k); yaw = lerp_angle(yaw, _g_yaw, k); pitch = lerpf(pitch, _g_pitch, k); dist = lerpf(dist, _g_dist, k)
	_apply_camera()
	_run_waves()
	_ease_town_glow(dt)
	if not (_warn.is_empty() and _warn_l.is_empty()):
		var nn := WorldMath.night(float(model.get("minute", 720.0)))
		var on := nn > 0.3 and fmod(_t, 1.6) < 0.8
		for w in _warn + _warn_l: (w as Node3D).visible = on
	if not _lighthouse.is_empty() and (_lighthouse.beam as Node3D).visible: (_lighthouse.beam as Node3D).rotation.y = _t * 0.9
	if not _cable.is_empty() and (_cable.mark as Node3D).visible: (_cable.mark as Node3D).scale = Vector3.ONE * (1.0 + 0.25 * sin(_t * 5.0))
	if _trawler != null and _trawler.visible: _trawler.position.y = sin(_t * 1.4) * 0.3
	if OS.has_environment("CB_DBGSCALE") and perf.frames == 200: _dbg_scale()
	perf.frames += 1; var ms := dt * 1000.0; perf.ms += ms; perf.worst = maxf(perf.worst, ms)
	if OS.has_environment("CB_FRAMETIME"):   # GPU and CPU render time of the viewport, measured by the RenderingServer (independent of vsync)
		var vp := get_viewport().get_viewport_rid()
		if not _measuring: RenderingServer.viewport_set_measure_render_time(vp, true); _measuring = true
		_ft_gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp); _ft_cpu += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu(); _ft_n += 1
		if _t - _ft_at > 2.0 and _t > 6.0:
			print("FRAMETIME res=%dx%d gpu_ms=%.2f cpu_render_ms=%.2f frame_ms=%.2f adapter=%s quality=%s" % [get_viewport().size.x, get_viewport().size.y, _ft_gpu / _ft_n, _ft_cpu / _ft_n, perf.ms / perf.frames, RenderingServer.get_video_adapter_name(), quality])
			_ft_at = _t; _ft_gpu = 0.0; _ft_cpu = 0.0; _ft_n = 0; perf.frames = 0; perf.ms = 0.0

# --------------------------------------------------------------------------------------------------------------------
# Camera: orbit / pan / zoom, limits that never show an edge
# --------------------------------------------------------------------------------------------------------------------
## The shift report asks the place to frame its consequence: when the engine has shed part of a live town, look along the line between the served
## and the shed wedges (the shed half in its cool shadow on one side, the served half in sun on the other), the city substation nearest the camera.
func report_focus() -> bool:
	var best := ""; var most := 0
	for t in model.get("towns", []):
		if float(t.get("v", 0.0)) <= 0.0: continue
		var m := 0
		for e in Array(t.get("energies", [])): if float(e) <= 0.0: m += 1
		if m > most: most = m; best = str(t.id)
	if most == 0: return _focus_overload()
	if _town_geo.has(best):
		var g: Dictionary = _town_geo[best]; var c: Vector2 = g.c
		var f := Vector2(cos(float(g.rot)), sin(float(g.rot)))   # the first shed wedge starts on the main street: that ray is the boundary
		var at := c
		if _subst.has(best):
			var sp: Vector3 = _subst[best].p
			if (Vector2(sp.x, sp.z) - c).dot(f) > 0.0: f = -f   # the substation on the camera's side of the boundary
			at = c.lerp(Vector2(sp.x, sp.z), 0.3)
		_g_target = Vector3(at.x, ground(at.x, at.y), at.y)
		_g_yaw = atan2(-f.x, -f.y); _g_pitch = deg_to_rad(21.0); _g_dist = minf(_g_dist, 820.0)
		return true
	if _big_centre.x >= INF: return false
	_g_target = Vector3(_big_centre.x, ground(_big_centre.x, _big_centre.y), _big_centre.y)
	_g_dist = minf(_g_dist, 900.0)
	return true

const OVERLOAD_FOCUS := ["L16"]   # jobs whose failed report frames the overloaded line with the plant that feeds it and the town it serves

## WO-16: the report shows the overloaded line (red), the plant at one end and the town at the other in one frame, the line seen side-on.
func _focus_overload() -> bool:
	if not OVERLOAD_FOCUS.has(str(model.get("level", ""))): return false
	var pts: Array = []; var first := Vector3.ZERO; var last := Vector3.ZERO
	for l in model.get("lines", []):
		if not (float(l.get("overload", 0.0)) > 0.0 or float(l.get("loading", 0.0)) > 1.0): continue
		var lp: Array = l.pts
		if pts.is_empty(): first = tile_to_world((lp[0] as Vector2) + Vector2(0.5, 0.5)); last = tile_to_world((lp[lp.size() - 1] as Vector2) + Vector2(0.5, 0.5))
		for q in lp: pts.append(tile_to_world((q as Vector2) + Vector2(0.5, 0.5)))
	if pts.is_empty(): return false
	for n in _root_infra.get_children():   # the plant at an end of the line
		if (n as Node).name.begins_with("Plant_"):
			for q in [first, last]:
				if Vector2((n as Node3D).position.x - q.x, (n as Node3D).position.z - q.z).length() < 1500.0: pts.append((n as Node3D).position); break
	var lo := Vector2(INF, INF); var hi := Vector2(-INF, -INF)
	for q in pts: lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.z)); hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.z))
	var c := (lo + hi) * 0.5
	var along := Vector2(last.x - first.x, last.z - first.z).normalized()
	var f := Vector2(-along.y, along.x)   # across the line: it runs left to right
	if f.y > 0.0: f = -f   # looking north
	_g_target = Vector3(c.x, maxf(ground(c.x, c.y), 0.0), c.y)
	_g_yaw = atan2(-f.x, -f.y); _g_pitch = deg_to_rad(27.0); _g_dist = maxf((hi - lo).length() * 1.9, 1700.0)
	return true

func reset_camera() -> void:
	_g_target = Vector3(map_size.x * 0.72, 0.0, map_size.y * 0.66)
	_g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
	_g_yaw = deg_to_rad(32.0); _g_pitch = deg_to_rad(23.0); _g_dist = maxf(map_size.x, map_size.y) * 0.45   # 11-28b audit: lower and closer (opened as a map from a plane)
	if field is GenField:   # the generated province opens on its capital at play zoom: whole streets readable, the next towns on the horizon
		_g_target = Vector3(map_size.x * 0.5, 0.0, map_size.y * 0.56); _g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
		_g_yaw = deg_to_rad(205.0); _g_pitch = deg_to_rad(19.0); _g_dist = 2800.0   # 1.16: closer, so the spire and chimney read (Sigrid)
		if _big_centre.x < INF and Vector2(_g_target.x, _g_target.z).distance_to(_big_centre) > maxf(map_size.x, map_size.y) * 0.2:   # 1.16: L07 and L09 opened on empty hills
			_g_target = Vector3(_big_centre.x, 0.0, _big_centre.y); _g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
			_g_dist = 1900.0; _g_pitch = deg_to_rad(21.0)
		if true:   # 1.18 (Dagny): the finale opens on Eastgate, the harbour and Saltmarsh Island, where the first sag and the storm come
			var pts: Array = []; var island := false
			for t in model.get("towns", []):
				var nm := str((t as Dictionary).get("name", "")).to_lower()
				if nm == "eastgate" or nm == "harbour" or nm == "saltmarsh island": pts.append(tile_to_world((t.pos as Vector2) + Vector2(0.5, 0.5)))
				if nm == "saltmarsh island": island = true
			if island and pts.size() >= 2:
				var c := Vector3.ZERO
				for q in pts: c += q
				c /= float(pts.size())
				var spread := 0.0
				for q in pts: spread = maxf(spread, Vector2(q.x - c.x, q.z - c.z).length())
				_g_target = Vector3(c.x, maxf(ground(c.x, c.z), 0.0), c.z); _g_dist = clampf(spread * 1.8, 2000.0, 7000.0); _g_pitch = deg_to_rad(22.0)
	var subj := _job_subject_pts()   # 11-28 (Sigrid): a grid job of chapters 5 and 6 opens on what its brief is about, at about 40 % of the old distance
	if not subj.is_empty():
		var c := Vector3.ZERO
		for q in subj: c += q
		c /= float(subj.size())
		var spread := 0.0
		for q in subj: spread = maxf(spread, Vector2(q.x - c.x, q.z - c.z).length())
		_g_target = Vector3(c.x, maxf(ground(c.x, c.z), 0.0), c.z); _g_dist = maxf(_g_dist * 0.3, maxf(spread * 2.3, 700.0)); _g_pitch = deg_to_rad(25.0)   # 1128c: 3.4 left the subject a third of the frame; art review 2: 2.75 still read as a map
	var lone: Array = JOB_SUBJECT.get(str(model.get("level", "")), [])
	if SUBSTATION_FOCUS.has(str(model.get("level", ""))) and lone.size() == 1 and _subst.has(str(lone[0])) and _town_geo.has(str(lone[0])):   # WO-17: the city substation is the subject, the core behind it
		var sp: Vector3 = _subst[str(lone[0])].p; var c: Vector2 = _town_geo[str(lone[0])].c
		var sc := Vector2(sp.x, sp.z) - c
		var f := Vector2(-sc.y, sc.x).normalized()   # across the line from the substation to the core: the substation on the left, the core on the right
		if Vector2(sp.x, sp.z).distance_to(c) > 0.0 and (Vector2(sp.x, sp.z) - c).dot(Vector2(cos(atan2(-f.x, -f.y)), -sin(atan2(-f.x, -f.y)))) > 0.0: f = -f
		var at := Vector2(sp.x, sp.z).lerp(c, 0.22)
		_g_target = Vector3(at.x, maxf(ground(at.x, at.y), 0.0), at.y); _g_yaw = atan2(-f.x, -f.y); _g_pitch = deg_to_rad(16.0); _g_dist = 560.0
	if str(model.get("level", "")) == "P0":   # 1.19 (Sigrid): the prologue opens low behind the lit coal plant, looking east over Line 7 to the city's glow
		var plant := Vector2(INF, INF); var city := Vector2(INF, INF)
		for u in model.get("units", []):
			if plant.x == INF or (u.pos as Vector2).x < plant.x: plant = u.pos
		for t in model.get("towns", []): city = t.pos
		if plant.x < INF and city.x < INF:
			var pw := tile_to_world(plant + Vector2(0.5, 0.5)); var cw := tile_to_world(city + Vector2(0.5, 0.5))
			var dir := Vector2(cw.x - pw.x, cw.z - pw.z).normalized()
			var t := Vector2(pw.x, pw.z) + dir * 250.0
			_g_target = Vector3(t.x, maxf(ground(t.x, t.y), 0.0), t.y)
			_g_yaw = atan2(-dir.x, -dir.y); _g_pitch = deg_to_rad(14.0); _g_dist = 1750.0   # 11-28b audit: the towers were cut by the frame at 1150 m
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist
	_apply_camera()

## What each job of chapters 5 and 6 is about, as the engine's bus ids (the brief names it): the towns on L14's line, L15's receiving end, L16's loop B3-B4-B5 (the loads the chord feeds),
## L17's city bus, L18's load bus, the plant bus of L19-L22. The default view frames them; every other generated province (the finale, the prologue) keeps its own.
const JOB_SUBJECT := {"L07": ["B2"], "L08": ["B2"], "L09": ["B2"], "L14": ["B4", "B5", "B6"], "L15": ["B2"], "L16": ["B1", "B2", "B3", "B4", "B5", "B6"], "L17": ["B3"], "L18": ["B2"], "L19": ["B1"], "L20": ["B1"], "L21": ["B1"], "L22": ["B1"]}
const SUBSTATION_FOCUS := ["L17"]   # jobs that open on the city substation (_subst) with the town core behind it
const JOB_PLANT_SCALE := 1.5   # the plants of those jobs are drawn 1.5 times larger (2.5 dwarfed the towns, Sigrid 11-28): at play distance a true-size plant is a toy on a 300 m square

func _job_plant_scale() -> float: return JOB_PLANT_SCALE if field is GenField and JOB_SUBJECT.has(str(model.get("level", ""))) else 1.0

## World points of the job's subject: its buses; a plant that stands at a lone subject bus replaces the bus (the plant is what the brief means).
func _job_subject_pts() -> Array:
	var pts: Array = []
	if not field is GenField: return pts
	var ids: Array = JOB_SUBJECT.get(str(model.get("level", "")), [])
	for sb in model.subs + model.towns:   # a bus with load is a town in the world model, any other a substation
		if str(sb.id) in ids: pts.append(tile_to_world((sb.pos as Vector2) + Vector2(0.5, 0.5)))
	if pts.size() == 1 and _root_infra != null:
		for n in _root_infra.get_children():
			if (n as Node).name.begins_with("Plant_") and Vector2((n as Node3D).position.x - pts[0].x, (n as Node3D).position.z - pts[0].z).length() < 1200.0:
				pts[0] = (n as Node3D).position; break
	return pts

## The prologue's cascade: the camera eases round to the largest town, close enough to see its streets go dark.
func turn_to_city() -> void:
	var best := {}
	for t in model.get("towns", []): if best.is_empty() or int(t.get("count", 0)) > int(best.get("count", 0)): best = t
	if best.is_empty(): return
	var c := tile_to_world((best.pos as Vector2) + Vector2(0.5, 0.5))
	var from := Vector2(c.x - _g_target.x, c.z - _g_target.z)
	if from.length() > 1.0: _g_yaw = atan2(-from.x, -from.y)   # keep looking the way we were looking, from this side of the city
	_g_target = Vector3(c.x, maxf(ground(c.x, c.z), 0.0), c.z); _g_dist = 2600.0; _g_pitch = deg_to_rad(24.0)
	_clamp_goal()

func _clamp_goal() -> void:
	_g_target.x = clampf(_g_target.x, -1200.0, map_size.x + 1200.0)
	_g_target.z = clampf(_g_target.z, -1200.0, map_size.y + 900.0)
	_g_target.y = maxf(ground(_g_target.x, _g_target.z), 0.0)
	_g_pitch = clampf(_g_pitch, PITCH_MIN, PITCH_MAX)
	_g_dist = clampf(_g_dist, DIST_MIN, dist_max)

func _cam_pos(t: Vector3, y: float, p: float, d: float) -> Vector3:
	var off := Vector3(sin(y) * cos(p), sin(p), cos(y) * cos(p)) * d
	return t + off

func _apply_camera() -> void:
	var pos := _cam_pos(target, yaw, pitch, dist)
	var floor_y := maxf(ground(pos.x, pos.z), 0.0) + 15.0 + dist * 0.02   # never under the hill in front
	if pos.y < floor_y: pos.y = floor_y
	pos = Kit3D.clear_eye(get_world_3d(), target, pos)
	cam.look_at_from_position(pos, target, Vector3.UP)
	cam.current = true

## Drag the ground: `rel` in screen px.
func pan_px(rel: Vector2) -> void:
	var s := dist * 0.0012
	var right := Vector3(cos(yaw), 0, -sin(yaw)); var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	_g_target += (-right * rel.x + fwd * rel.y) * s / maxf(0.35, sin(pitch) * 0.6 + 0.4)
	_clamp_goal()

func orbit_px(rel: Vector2) -> void:
	_g_yaw -= rel.x * 0.006; _g_pitch += rel.y * 0.004; _clamp_goal()

## Zoom by `f` (>1 closer) toward the ground under screen point `sp`.
func zoom_at(sp: Vector2, f: float) -> void:
	var g := ground_point(sp)
	var nd := clampf(_g_dist / f, DIST_MIN, dist_max)
	if not is_nan(g.x):
		var k := 1.0 - nd / _g_dist
		_g_target = _g_target.lerp(g, k * 0.9)
	_g_dist = nd; _clamp_goal()

func center_on_tile(p: Vector2, z := 1.0) -> void:
	_g_target = tile_to_world(p + Vector2(0.5, 0.5)); _g_dist = clampf(maxf(map_size.x, map_size.y) * 0.95 / z, DIST_MIN, dist_max); _clamp_goal()

## CB_CAM camera words for screenshots: yaw=deg, pitch=deg, dist=m, tx/ty (tiles), snap (no easing).
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
			"zoom": _g_dist = maxf(map_size.x, map_size.y) * 0.95 / float(kv[1]); used = true
	_clamp_goal()
	target = _g_target; yaw = _g_yaw; pitch = _g_pitch; dist = _g_dist; _apply_camera()
	return used

# --------------------------------------------------------------------------------------------------------------------
# Projection for the 2D overlay (WorldView): screen <-> world. Screen = the canvas coordinates of the full-rect world control.
# --------------------------------------------------------------------------------------------------------------------
func _dbg_scale() -> void:
	var w := get_window()
	print("LOOK2SCALE win=%s vis=%s csf=%s final=%s canvas=%s" % [w.size, get_viewport().get_visible_rect(), w.content_scale_factor, get_viewport().get_final_transform(), get_viewport().canvas_transform])

var canvas_size := Vector2.ZERO   ## the overlay control's size in canvas units (WorldView sets it): screen px per canvas unit = viewport px / this

func _canvas_scale() -> float:
	if canvas_size.x < 1.0: return 1.0
	return get_viewport().get_visible_rect().size.x / canvas_size.x

func project(p: Vector3) -> Vector2:
	if cam.is_position_behind(p): return Vector2(-99999, -99999)
	return cam.unproject_position(p) / _canvas_scale()

## The ground (or sea surface) under a screen point, world metres (Vector3), NAN when the ray misses.
func ground_point(sp: Vector2) -> Vector3:
	var vp := sp * _canvas_scale()
	var o := cam.project_ray_origin(vp); var d := cam.project_ray_normal(vp)
	var t := 0.0; var step := maxf(4.0, dist * 0.01)
	var prev := o
	for i in 600:
		var p := o + d * t
		var g := maxf(ground(p.x, p.z), 0.0)
		if p.y <= g:
			var lo := t - step; var hi := t   # bisect the crossing
			for _k in 12:
				var mid := (lo + hi) * 0.5; var q := o + d * mid
				if q.y <= maxf(ground(q.x, q.z), 0.0): hi = mid
				else: lo = mid
			return o + d * hi
		prev = p
		t += step; step *= 1.01
		if t > 60000.0: break
	return Vector3(NAN, NAN, NAN)

## Screen px per tile at the camera target (WorldView sizes its markers by it).
func px_per_tile() -> float:
	var a := project(target); var b := project(target + Vector3(tm, 0, 0))
	return maxf(1.0, a.distance_to(b))
