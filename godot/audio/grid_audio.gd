class_name GridAudio
extends Node
## GRID audio layer. Everything is synthesised (no audio files, nothing to license) and deterministic.
##
## Own one GridAudio in the scene tree (add_child) and call:
##   Hum (continuous, AudioStreamGenerator):
##     set_mode("dc" | "ac")   "dc" = very quiet warm room tone (chapter 1 bench); "ac" = the 100 Hz transformer hum.
##     set_frequency(hz)       grid frequency; the hum fundamental is 2 f (100 Hz at 50 Hz), partials at 2x and 3x.
##                             Pitch truth: hum_pitch_scale() == f / 50.
##     set_load(0..1)          total load, drives hum loudness and brightness.
##     set_hum_volume(db)      separate hum trim in dB (default -6).
##     cable_tick()            DC mode: tiny tick, call once per 15-minute block.
##   One-shots (pool of 8 voices on the SFX bus): play(kind) with kind in ONE_SHOTS, plink(i) for home number i
##     (i = 0..9 rises as a little pentatonic arpeggio; wraps after 10), and
##     "breaker_close" "breaker_open" "relay_tick" "radio" "plink" "cheer" "aww" "place" "reel" "stamp" "page" "tick".
##   Music (the GridMusic catalogue: four 2-3 minute night-shift tracks played in turn, each rendered on a worker thread):
##     start_music() / stop_music(fade)
##     set_stress(0..1)        pad+bass always; soft percussion fades in above 0.5.
##     set_cute(bool)          adds the music-box lead.
##   apply_volumes()          re-read CbSettings master/music/sfx (call after the settings screen changes them).
## Buses: SFX and Music (created if missing, shared with CbAudio). Master volume is CbSettings' job (CbSettings.apply).
## Headless (dummy audio driver): state setters work, nothing is played, no threads are started.
##
## The synthesis lives in static functions so tools/audio/render_samples.gd can render the exact same samples to WAV.

const RATE := 32000        ## one-shot sample rate
const HUM_RATE := 16000    ## hum generator rate (partials top out near 300 Hz)
const MRATE := 16000       ## music rate
const PEAK_N6 := 0.5012    ## -6 dBFS
const BPM := 70.0
const ONE_SHOTS := ["breaker_close", "breaker_open", "relay_tick", "radio", "plink", "cheer", "aww", "place", "reel", "stamp", "page", "tick",
	"speed", "trip", "blackout", "coin", "spend", "quarter", "town_on0", "town_on1", "town_on2"]   ## 1.7: speed keys, a protection trip, a blackout, Career money in / out, the quarter closing
const PLINK_SEMIS := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]
const KIND_DB := {"breaker_close": 1.0, "breaker_open": -5.0, "relay_tick": -6.0, "radio": -3.0, "plink": -7.0, "cheer": -6.0, "aww": -7.0,
	"place": -3.0, "reel": -9.0, "stamp": -2.0, "page": -7.0, "tick": -10.0,
	"speed": -7.0, "trip": -5.0, "blackout": -3.0, "coin": -6.0, "spend": -9.0, "quarter": -8.0, "town_on": -8.0}
## 1.18 levels (docs/audio/ANALYSIS.md): every cue is peak-normalised to -6 dBFS, so what the listener hears is set here. The 1.17 trims left the radio at
## -34 and the cheer at -33 dBFS RMS (under a hum at -19); now key events sit near -22, interface sounds near -27, the DC tick near -35.
## Cues longer than the 0.8 s one-shot rule: a town coming on swells, and the blackout rings out into silence.
const LONG_CUES := {"town_on0": 1.3, "town_on1": 1.5, "town_on2": 1.8, "blackout": 1.4}

var mode := "dc"
var frequency := 50.0
var load_level := 0.3
var hum_db := -12.0
var stress := 0.0
var cute := false
var muted := false
var headless := DisplayServer.get_name() == "headless" or OS.has_environment("CB_NOAUDIO")   # CB_NOAUDIO: perf A/B runs
var _hum: HumSynth = HumSynth.new()
var _out: OutdoorSynth = OutdoorSynth.new()   ## LOOK2 (1.16): wind, and crickets at night, over the 3D province
var _out_pb: AudioStreamGeneratorPlayback
var _hum_player: AudioStreamPlayer
var _hum_pb: AudioStreamGeneratorPlayback
var _voices: Array[AudioStreamPlayer] = []
var _streams := {}
var _last_play := {}
var _stems_players := {}     # name -> AudioStreamPlayer
var _stem_db := {"pad": -80.0, "perc": -80.0, "lead": -80.0}
var _thread: Thread
var _music_wanted := false
static var _stem_cache := {}      ## stems of the track now playing (GridMusic.render_track)
static var _next_cache := {}      ## stems of the next track, rendered on the worker thread while this one plays
static var _track := 0            ## GridMusic track index now playing (1.7: four tracks of 2-3 minutes play in turn; 1.6 looped one 27 s phrase)

# ---------------------------------------------------------------- public API
func set_mode(m: String) -> void:
	mode = "ac" if m == "ac" else "dc"
	_hum.ac = mode == "ac"

func set_frequency(hz: float) -> void:
	frequency = clampf(hz, 20.0, 80.0)
	_hum.f_t = frequency

func set_load(l: float) -> void:
	load_level = clampf(l, 0.0, 1.0)
	_hum.load_t = load_level

func set_hum_volume(db: float) -> void:
	hum_db = db
	if _hum_player != null: _hum_player.volume_db = db

## f / 50, the pitch ratio of the hum relative to nominal (what the audio tests assert).
func hum_pitch_scale() -> float:
	return frequency / 50.0

## Current hum fundamental in Hz (2 f).
func hum_fundamental_hz() -> float:
	return 2.0 * frequency

func cable_tick() -> void:
	play("tick")

## A town comes on: a warm chord that swells, bigger with the number of homes lit (3 or more: small, 6 or more: medium, 12 or more: large).
func town_on(homes: int) -> void:
	play("town_on%d" % (2 if homes >= 12 else (1 if homes >= 6 else 0)))

func plink(i: int) -> void:
	play("plink%d" % posmod(i, PLINK_SEMIS.size()))

func play(kind: String) -> void:
	if muted or headless or _voices.is_empty() or not is_inside_tree(): return
	if kind == "plink": kind = "plink0"
	var base := "plink" if kind.begins_with("plink") else ("town_on" if kind.begins_with("town_on") else kind)
	if not (kind in ONE_SHOTS or base == "plink"): return
	var t := Time.get_ticks_msec()
	if t - int(_last_play.get(kind, -1000)) < 25: return
	_last_play[kind] = t
	if not _streams.has(kind):
		_streams[kind] = to_wav(render_oneshot(kind), RATE, false)
	var p: AudioStreamPlayer = null
	for v in _voices:
		if not v.playing: p = v; break
	if p == null: p = _voices[0]
	p.stream = _streams[kind]; p.volume_db = float(KIND_DB.get(base, -8.0)); p.play()

func start_music() -> void:
	_music_wanted = true
	if headless or CbSettings.music_mode == "off": return
	if _stems_players.is_empty():
		if _stem_cache.is_empty():
			if _thread == null: _thread = Thread.new(); _thread.start(func(): _stem_cache = _render_wavs(_track))
		else: _build_music_players()
	else:
		for p in _stems_players.values():
			if not p.playing: p.play()

func stop_music(fade := 1.0) -> void:
	_music_wanted = false
	for p in _stems_players.values():
		if p.playing:
			var tw := create_tween(); tw.tween_property(p, "volume_db", -80.0, fade); tw.tween_callback(p.stop)

func set_stress(s: float) -> void:
	stress = clampf(s, 0.0, 1.0)

func set_cute(on: bool) -> void:
	cute = on

func apply_volumes() -> void:
	_set_bus("Music", CbSettings.music_volume * (0.0 if CbSettings.music_mode == "off" else 1.0), -6.0)
	_set_bus("SFX", CbSettings.sfx_volume, 0.0)

# ---------------------------------------------------------------- node plumbing
func _ready() -> void:
	for n in ["Music", "SFX"]:
		if AudioServer.get_bus_index(n) == -1:
			AudioServer.add_bus(); var i := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(i, n); AudioServer.set_bus_send(i, "Master")
	var mi := AudioServer.get_bus_index("Music")
	if mi != -1 and AudioServer.get_bus_effect_count(mi) == 0:
		var rv := AudioEffectReverb.new(); rv.room_size = 0.6; rv.wet = 0.18; rv.dry = 0.9; AudioServer.add_bus_effect(mi, rv)
	for i in 8:
		var p := AudioStreamPlayer.new(); p.bus = "SFX"; add_child(p); _voices.append(p)
	var g := AudioStreamGenerator.new(); g.mix_rate = HUM_RATE; g.buffer_length = 0.25
	_hum_player = AudioStreamPlayer.new(); _hum_player.stream = g; _hum_player.bus = "SFX"; _hum_player.volume_db = hum_db
	add_child(_hum_player)
	if not headless:
		_hum_player.play(); _hum_pb = _hum_player.get_stream_playback() as AudioStreamGeneratorPlayback
	_hum.f = frequency; _hum.f_t = frequency; _hum.ac = mode == "ac"
	var og := AudioStreamGenerator.new(); og.mix_rate = OutdoorSynth.RATE; og.buffer_length = 0.3
	var op := AudioStreamPlayer.new(); op.stream = og; op.bus = "SFX"; op.volume_db = -6.0; add_child(op)
	if not headless: op.play(); _out_pb = op.get_stream_playback() as AudioStreamGeneratorPlayback
	apply_volumes()

## LOOK2: the outdoor bed. level 0 (off, every classic screen) .. 1 (the 3D province); night 0..1 brings the crickets in and the wind down.
func set_outdoor(level: float, night: float) -> void:
	_out.level_t = clampf(level, 0.0, 1.0); _out.night_t = clampf(night, 0.0, 1.0)

func _exit_tree() -> void:
	if _thread != null and _thread.is_started(): _thread.wait_to_finish()

func _set_bus(n: String, lin: float, trim_db: float) -> void:
	var i := AudioServer.get_bus_index(n)
	if i != -1: AudioServer.set_bus_volume_db(i, linear_to_db(maxf(lin, 0.0001)) + trim_db)

func _process(delta: float) -> void:
	if _hum_pb != null:
		var n := mini(_hum_pb.get_frames_available(), 4096)
		if n > 0:
			var s := _hum.fill(n); var v := PackedVector2Array(); v.resize(n)
			for i in n: v[i] = Vector2(s[i], s[i])
			_hum_pb.push_buffer(v)
	if _out_pb != null:
		var n2 := mini(_out_pb.get_frames_available(), 4096)
		if n2 > 0:
			var s2 := _out.fill(n2); var v2 := PackedVector2Array(); v2.resize(n2)
			for i in n2: v2[i] = Vector2(s2[i], s2[i])
			_out_pb.push_buffer(v2)
	if _thread != null and _thread.is_started() and not _thread.is_alive():
		_thread.wait_to_finish(); _thread = null
		if _music_wanted: _build_music_players()
		if _next_cache.is_empty() and not _stem_cache.is_empty():   # render the next track while this one plays
			_thread = Thread.new(); var nxt := _track + 1; _thread.start(func(): _next_cache = _render_wavs(nxt))
	if _music_wanted and _stems_players.has("pad") and not (_stems_players["pad"] as AudioStreamPlayer).playing and not _next_cache.is_empty() and (_thread == null or not _thread.is_alive()):
		_next_track()
	if not _stems_players.is_empty():
		var gains := stem_gains(stress, cute)
		for k in _stems_players:
			var p: AudioStreamPlayer = _stems_players[k]
			if not _music_wanted: continue
			var tgt: float = -80.0 if float(gains[k]) < 0.002 else linear_to_db(float(gains[k]))
			_stem_db[k] = move_toward(float(_stem_db[k]), tgt, 30.0 * delta)
			p.volume_db = float(_stem_db[k])

## A track's stems and their 16-bit streams, made on the worker thread: encoding three long stems on the main thread cost a 470 ms frame when the first track was ready.
static func _render_wavs(i: int) -> Dictionary:
	var d := GridMusic.render_track(i); var w := {}
	for k in ["pad", "perc", "lead"]: w[k] = to_wav(d[k], MRATE, false)
	d["wav"] = w
	return d

func _build_music_players() -> void:
	if _stem_cache.is_empty() or not _stems_players.is_empty(): return
	for k in ["pad", "perc", "lead"]:
		var p := AudioStreamPlayer.new(); p.bus = "Music"; p.volume_db = -80.0 if k != "pad" else float(_stem_db.get(k, -80.0))
		p.stream = (_stem_cache.wav[k] as AudioStreamWAV) if _stem_cache.has("wav") else to_wav(_stem_cache[k], MRATE, false); add_child(p); _stems_players[k] = p
	for p in _stems_players.values(): p.play()

## The track ended: swap in the pre-rendered next one (the stems' own fades make the join) and start rendering the one after.
func _next_track() -> void:
	for p in _stems_players.values(): (p as AudioStreamPlayer).queue_free()
	_stems_players.clear()
	_track = posmod(_track + 1, GridMusic.count()); _stem_cache = _next_cache; _next_cache = {}
	_build_music_players()
	_thread = Thread.new(); var nxt := _track + 1; _thread.start(func(): _next_cache = _render_wavs(nxt))

## Title of the track now playing ("" before the first one is ready).
func track_title() -> String: return str(_stem_cache.get("title", ""))

# ---------------------------------------------------------------- hum synth
## Streaming hum generator. fill(n) returns n mono samples. Parameters ease (pitch 40 ms, load 200 ms, mode 350 ms).
class HumSynth extends RefCounted:
	var rate := 16000
	var f := 50.0
	var f_t := 50.0
	var load_v := 0.3
	var load_t := 0.3
	var ac := true
	var g_ac := 0.0
	var g_dc := 1.0
	var ph := 0.0
	var ph_dc := 0.0
	var trem := 0.0
	var lp1 := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()

	func _init(r := 16000, seed_ := 5) -> void:
		rate = r; rng.seed = seed_

	## Snap to the targets (used by offline rendering so the first sample is already at pitch).
	func snap(ac_on: bool) -> void:
		f = f_t; load_v = load_t; ac = ac_on; g_ac = 1.0 if ac_on else 0.0; g_dc = 0.0 if ac_on else 1.0

	func fill(n: int) -> PackedFloat32Array:
		var out := PackedFloat32Array(); out.resize(n)
		var kf := 1.0 - exp(-1.0 / (0.04 * rate)); var kl := 1.0 - exp(-1.0 / (0.2 * rate)); var kg := 1.0 - exp(-1.0 / (0.35 * rate))
		for i in n:
			f += (f_t - f) * kf; load_v += (load_t - load_v) * kl
			g_ac += ((1.0 if ac else 0.0) - g_ac) * kg; g_dc += ((0.0 if ac else 1.0) - g_dc) * kg
			var s := 0.0
			if g_ac > 0.0001:
				ph = fposmod(ph + 2.0 * f / rate, 1.0); trem = fposmod(trem + 0.13 / rate, 1.0)
				var a := TAU * ph; var s1 := sin(a); var c1 := cos(a)
				var s2 := 2.0 * s1 * c1; var c2 := 1.0 - 2.0 * s1 * s1; var s3 := s2 * c1 + c2 * s1
				var l := load_v
				var amp := (0.10 + 0.28 * l) * (1.0 + 0.03 * sin(TAU * trem))
				s += (s1 + s2 * (0.25 + 0.45 * l) + s3 * (0.12 + 0.35 * l)) * amp * g_ac
			if g_dc > 0.0001:
				ph_dc = fposmod(ph_dc + 55.0 / rate, 1.0)
				lp1 += (rng.randf_range(-1.0, 1.0) - lp1) * 0.12; lp2 += (lp1 - lp2) * 0.12
				s += (lp2 * 0.35 + sin(TAU * ph_dc) * 0.012) * g_dc
			out[i] = s
		return out

# ---------------------------------------------------------------- DSP helpers (static)
static func to_wav(buf: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var d := PackedByteArray(); d.resize(buf.size() * 2)
	for i in buf.size(): d.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var s := AudioStreamWAV.new(); s.format = AudioStreamWAV.FORMAT_16_BITS; s.mix_rate = rate; s.data = d
	if loop: s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_begin = 0; s.loop_end = buf.size()
	return s

static func _buf(seconds: float, rate := RATE) -> PackedFloat32Array:
	var b := PackedFloat32Array(); b.resize(int(seconds * rate)); return b

static func _add(dst: PackedFloat32Array, src: PackedFloat32Array, start_s: float, gain := 1.0, rate := RATE, wrap := false) -> void:
	var s0 := int(start_s * rate); var n := dst.size()
	for i in src.size():
		var j := s0 + i
		if wrap: j = j % n
		elif j >= n: break
		dst[j] += src[i] * gain

static func peak(b: PackedFloat32Array) -> float:
	var p := 0.0
	for v in b: p = maxf(p, absf(v))
	return p

static func normalize(b: PackedFloat32Array, target: float) -> void:
	var p := peak(b)
	if p < 1e-9: return
	var k := target / p
	for i in b.size(): b[i] *= k

## Exponentially decaying noise burst (unfiltered).
static func _nb(rng: RandomNumberGenerator, dur: float, decay: float, amp: float, rate := RATE) -> PackedFloat32Array:
	var b := _buf(dur, rate)
	for i in b.size():
		var t := float(i) / rate
		b[i] = rng.randf_range(-1.0, 1.0) * amp * exp(-t * decay) * minf(1.0, t / 0.0006)
	return b

## Sum of decaying sines.
static func _modal(freq: float, decay: float, amp: float, dur: float, rate := RATE) -> PackedFloat32Array:
	var b := _buf(dur, rate)
	for i in b.size():
		var t := float(i) / rate
		b[i] = sin(TAU * freq * t) * amp * exp(-t * decay) * minf(1.0, t / 0.0015)
	return b

## Sine with exponential pitch glide f0 -> f1 and decay.
static func _thump(f0: float, f1: float, glide: float, decay: float, amp: float, dur: float, rate := RATE) -> PackedFloat32Array:
	var b := _buf(dur, rate); var ph := 0.0
	for i in b.size():
		var t := float(i) / rate
		ph += (f1 + (f0 - f1) * exp(-t * glide)) / rate
		b[i] = sin(TAU * ph) * amp * exp(-t * decay) * minf(1.0, t / 0.001)
	return b

## Soft saturation: gives a low thump odd harmonics (3x, 5x) so it is heard on small speakers that cannot reproduce 40 to 90 Hz. 1.18.
static func _sat(x: PackedFloat32Array, drive: float) -> PackedFloat32Array:
	var y := PackedFloat32Array(); y.resize(x.size()); var k := 1.0 / tanh(drive)
	for i in x.size(): y[i] = tanh(x[i] * drive) * k
	return y

## RBJ band-pass (0 dB peak), centre sweeps f0 -> f1 over the buffer.
static func _bp(x: PackedFloat32Array, f0: float, f1: float, q: float, rate := RATE) -> PackedFloat32Array:
	var y := PackedFloat32Array(); y.resize(x.size())
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var b0 := 0.0; var a1 := 0.0; var a2 := 0.0
	for i in x.size():
		if i % 8 == 0:
			var f := lerpf(f0, f1, float(i) / maxf(1.0, float(x.size())))
			var w := TAU * f / rate; var al := sin(w) / (2.0 * q); var a0 := 1.0 + al
			b0 = al / a0; a1 = -2.0 * cos(w) / a0; a2 = (1.0 - al) / a0
		var o := b0 * (x[i] - x2) - a1 * y1 - a2 * y2
		x2 = x1; x1 = x[i]; y2 = y1; y1 = o; y[i] = o
	return y

static func _lp(x: PackedFloat32Array, fc: float, rate := RATE) -> PackedFloat32Array:
	var y := PackedFloat32Array(); y.resize(x.size())
	var k := 1.0 - exp(-TAU * fc / rate); var s := 0.0
	for i in x.size():
		s += (x[i] - s) * k; y[i] = s
	return y

static func _hp(x: PackedFloat32Array, fc: float, rate := RATE) -> PackedFloat32Array:
	var l := _lp(x, fc, rate); var y := PackedFloat32Array(); y.resize(x.size())
	for i in x.size(): y[i] = x[i] - l[i]
	return y

static func _rng(seed_: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = seed_; return r

# ---------------------------------------------------------------- one-shots
## Render one SFX to float samples at RATE, peak-normalised to -6 dBFS, deterministic, < 0.8 s.
static func render_oneshot(kind: String) -> PackedFloat32Array:
	var r := _rng(hash(kind) & 0x7fffffff)
	var b: PackedFloat32Array
	match kind:
		"breaker_close":   # heavy clunk, then a smaller latch clack
			b = _buf(0.42)
			_add(b, _sat(_thump(140.0, 75.0, 30.0, 20.0, 0.45, 0.3), 2.0), 0.0)
			_add(b, _bp(_nb(r, 0.06, 150.0, 1.0), 1800.0, 1800.0, 1.2), 0.0)
			_add(b, _modal(870.0, 70.0, 0.35, 0.12), 0.0); _add(b, _modal(1340.0, 90.0, 0.25, 0.1), 0.0)
			_add(b, _bp(_nb(r, 0.05, 170.0, 0.55), 2500.0, 2500.0, 1.3), 0.085)
			_add(b, _modal(1620.0, 110.0, 0.2, 0.08), 0.085)
		"breaker_open":    # lower thud, latch release, springy twang
			b = _buf(0.62)
			_add(b, _sat(_thump(110.0, 60.0, 18.0, 13.0, 0.4, 0.45), 2.0), 0.0)
			_add(b, _bp(_nb(r, 0.1, 40.0, 0.5), 500.0, 300.0, 0.7), 0.0)
			_add(b, _bp(_nb(r, 0.03, 220.0, 0.5), 1200.0, 1200.0, 1.0), 0.16)
			var tw := _buf(0.4); var ph := 0.0; var mph := 0.0
			for i in tw.size():
				var t := float(i) / RATE
				mph += 37.0 / RATE
				ph += (240.0 + 280.0 * exp(-t * 8.0) + 45.0 * sin(TAU * mph)) / RATE
				tw[i] = sin(TAU * ph) * 0.35 * exp(-t * 9.0) * minf(1.0, t / 0.002)
			_add(b, tw, 0.18)
		"relay_tick":
			b = _buf(0.06)
			_add(b, _bp(_nb(r, 0.015, 450.0, 1.0), 2800.0, 2800.0, 2.0), 0.0)
			_add(b, _modal(1900.0, 230.0, 0.4, 0.04), 0.0); _add(b, _modal(700.0, 160.0, 0.25, 0.04), 0.012)
		"tick":            # soft cable tick (DC 15-minute block)
			b = _buf(0.05)
			_add(b, _bp(_nb(r, 0.01, 500.0, 1.0), 1800.0, 1800.0, 3.0), 0.0)
			_add(b, _modal(1400.0, 300.0, 0.3, 0.04), 0.0)
		"radio":           # key-up blip, crackle bed, squelch tail
			b = _buf(0.55)
			var cr := _buf(0.3)
			for i in cr.size():
				var t := float(i) / RATE
				var env := minf(1.0, t / 0.02) * minf(1.0, (0.3 - t) / 0.05)
				if r.randf() < 0.01: cr[i] = r.randf_range(-1.0, 1.0) * 1.5 * env
				cr[i] += r.randf_range(-1.0, 1.0) * 0.12 * env
			_add(b, _bp(cr, 1800.0, 1800.0, 0.8), 0.03)
			_add(b, _modal(1000.0, 120.0, 0.35, 0.03), 0.0)
			_add(b, _bp(_nb(r, 0.12, 24.0, 0.8), 2300.0, 1400.0, 1.4), 0.34)
		"cheer":           # gentle: a few detuned "ah" voices, formant-filtered, with soft clap-like flutter
			b = _buf(0.72)
			var raw := _buf(0.72)
			var mults := [1.0, 1.19, 1.5, 1.26, 2.0, 1.78]
			for v in mults.size():
				var ph2 := r.randf(); var vib := r.randf() * TAU
				for i in raw.size():
					var t := float(i) / RATE
					ph2 += 300.0 * float(mults[v]) * (1.0 + 0.15 * t + 0.012 * sin(TAU * 5.5 * t + vib)) / RATE
					raw[i] += (fposmod(ph2, 1.0) * 2.0 - 1.0) * 0.5
			for i in raw.size(): raw[i] += r.randf_range(-1.0, 1.0) * 0.5
			var f1 := _bp(raw, 800.0, 900.0, 3.0); var f2 := _bp(raw, 2200.0, 2400.0, 4.0)
			for i in b.size():
				var t := float(i) / RATE
				var env := pow(minf(1.0, t / 0.18), 1.5) * exp(-maxf(0.0, t - 0.3) * 4.5)
				var fl := 0.75 + 0.25 * sin(TAU * 9.0 * t + 1.3 * sin(TAU * 2.3 * t))
				b[i] = (f1[i] + 0.5 * f2[i]) * env * fl
			b = _lp(b, 3500.0)
		"aww":             # two soft falling tones, E5 -> Eb5 then C5 -> Bb4
			b = _buf(0.66)
			for nt in [[659.0, 622.0, 0.0, 0.26], [523.0, 466.0, 0.22, 0.42]]:
				var nb: PackedFloat32Array = _buf(float(nt[3])); var ph3 := 0.0
				for i in nb.size():
					var t := float(i) / RATE; var u := t / float(nt[3])
					ph3 += lerpf(float(nt[0]), float(nt[1]), u * u) * (1.0 + 0.004 * sin(TAU * 5.0 * t)) / RATE
					var a := TAU * ph3
					nb[i] = (sin(a) + 0.3 * sin(2.0 * a) + 0.08 * sin(3.0 * a)) * 0.5 * minf(1.0, t / 0.02) * pow(1.0 - u, 1.3) * exp(-t * 2.0)
				_add(b, nb, float(nt[2]))
		"place":           # wood thunk
			b = _buf(0.22)
			_add(b, _thump(210.0, 170.0, 40.0, 36.0, 1.0, 0.2), 0.0)
			_add(b, _modal(410.0, 55.0, 0.5, 0.15), 0.0); _add(b, _modal(690.0, 80.0, 0.3, 0.1), 0.0)
			_add(b, _bp(_nb(r, 0.02, 200.0, 0.6), 900.0, 900.0, 1.0), 0.0)
		"reel":            # unreel zip: ratcheting noise sweeping up
			b = _buf(0.5)
			var zn := _buf(0.5)
			for i in zn.size():
				var t := float(i) / RATE
				var rat := 0.55 + 0.45 * sin(TAU * (50.0 + 40.0 * t) * t)
				zn[i] = r.randf_range(-1.0, 1.0) * rat * minf(1.0, t / 0.03) * minf(1.0, (0.5 - t) / 0.1)
			_add(b, _bp(zn, 700.0, 3800.0, 2.5), 0.0)
			var zz := _buf(0.45); var pz := 0.0
			for i in zz.size():
				var t := float(i) / RATE
				pz += lerpf(900.0, 3200.0, t / 0.45) / RATE
				zz[i] = sin(TAU * pz) * 0.4 * minf(1.0, t / 0.03) * minf(1.0, (0.45 - t) / 0.1)   # 1.7: a stronger rising tone, so the reel is not mistaken for the page slide
			_add(b, zz, 0.0)
		"stamp":           # paper stamp: thud + slap + rattle
			b = _buf(0.3)
			_add(b, _thump(120.0, 62.0, 35.0, 24.0, 1.0, 0.25), 0.0)
			_add(b, _bp(_nb(r, 0.04, 90.0, 0.8), 1500.0, 1500.0, 0.6), 0.0)
			_add(b, _lp(_nb(r, 0.1, 40.0, 0.25), 2500.0), 0.0); _add(b, _modal(240.0, 40.0, 0.3, 0.12), 0.0)
		"page":            # paper slide
			b = _buf(0.42)
			var pn := _buf(0.38)
			for i in pn.size():
				var u := float(i) / float(pn.size())
				pn[i] = r.randf_range(-1.0, 1.0) * pow(sin(PI * pow(u, 0.6)), 2.0)
			_add(b, _bp(pn, 2200.0, 4200.0, 0.9), 0.0)
			_add(b, _bp(_nb(r, 0.04, 80.0, 0.5), 500.0, 500.0, 1.0), 0.0)
		"speed":           # a rotary detent: short click with a little spring
			b = _buf(0.12)
			_add(b, _bp(_nb(r, 0.015, 300.0, 1.0), 2600.0, 2600.0, 2.0), 0.0); _add(b, _modal(1250.0, 60.0, 0.35, 0.1), 0.004)
		"trip":            # a protection trip: relay chatter, then the breaker's heavy open and a falling whine as the line drops
			b = _buf(0.75)
			for k in 3: _add(b, _bp(_nb(r, 0.012, 300.0, 0.6), 3000.0, 3000.0, 2.5), 0.025 * k)
			_add(b, _sat(_thump(120.0, 55.0, 16.0, 9.0, 0.5, 0.5), 2.0), 0.09)
			_add(b, _bp(_nb(r, 0.06, 60.0, 0.6), 1600.0, 600.0, 1.0), 0.09)
			var wh := _buf(0.6); var pw := 0.0
			for i in wh.size():
				var t := float(i) / RATE; pw += lerpf(400.0, 90.0, t / 0.6) / RATE
				wh[i] = sin(TAU * pw) * 0.25 * exp(-t * 4.0) * minf(1.0, t / 0.01)
			_add(b, wh, 0.12)
		"blackout":        # the hum spins down (0.5 s), a low thud, then the tail dies into silence: the radio comes after
			b = _buf(1.4)
			for fr in [100.0, 200.0]:
				var gl := _buf(0.55); var pg := 0.0
				for i in gl.size():
					var t := float(i) / RATE; pg += fr * pow(0.3, t / 0.55) / RATE
					gl[i] = sin(TAU * pg) * 0.3 * minf(1.0, t / 0.01) * pow(1.0 - t / 0.55, 1.5)
				_add(b, gl, 0.0)
			_add(b, _sat(_thump(85.0, 40.0, 10.0, 6.0, 0.6, 0.8), 2.5), 0.55); _add(b, _modal(180.0, 14.0, 0.35, 0.4), 0.55)
			_add(b, _lp(_nb(r, 0.12, 30.0, 0.5), 400.0), 0.55)
		"coin":            # money in: two bright coin rings, a fifth apart
			b = _buf(0.5)
			for c in [[1976.0, 0.0], [2960.0, 0.07]]:
				_add(b, _modal(c[0], 9.0, 1.0, 0.42), c[1]); _add(b, _modal(c[0] * 2.4, 16.0, 0.35, 0.3), c[1])
		"spend":           # money out: a register's drawer clunk and bell
			b = _buf(0.55)
			_add(b, _thump(160.0, 90.0, 30.0, 25.0, 0.9, 0.2), 0.0)
			_add(b, _bp(_nb(r, 0.08, 50.0, 0.5), 1200.0, 700.0, 1.0), 0.03)
			_add(b, _modal(2093.0, 6.0, 0.7, 0.45), 0.1); _add(b, _modal(4186.0, 12.0, 0.2, 0.3), 0.1)
		"quarter":         # the ledger closes: a book shut and a low two-note chime
			b = _buf(0.7)
			_add(b, _thump(140.0, 70.0, 30.0, 22.0, 0.9, 0.2), 0.0); _add(b, _bp(_nb(r, 0.05, 90.0, 0.6), 900.0, 900.0, 0.8), 0.0)
			_add(b, _modal(587.3, 5.0, 0.6, 0.55), 0.12); _add(b, _modal(440.0, 5.0, 0.6, 0.45), 0.25)
		"town_on0", "town_on1", "town_on2":   # people getting light: a warm chord that swells in note by note
			var notes: Array = [[261.63, 392.0], [261.63, 329.63, 392.0, 523.25], [130.81, 261.63, 329.63, 392.0, 493.88, 587.33]][int(kind.substr(7))]
			var dur: float = LONG_CUES[kind]; b = _buf(dur)
			for ni in notes.size():
				var fn := float(notes[ni]); var nb2 := _buf(dur - 0.08 * ni)
				for dt in [-1.0, 1.0]:
					var ph4 := r.randf()
					for i in nb2.size():
						var t := float(i) / RATE; ph4 += fn * (1.0 + 0.0015 * dt) / RATE
						var a := TAU * ph4
						var env := pow(sin(PI * 0.5 * minf(1.0, t / 0.4)), 2.0) * exp(-maxf(0.0, t - 0.4) * 2.6) * minf(1.0, (dur - 0.08 * ni - t) / 0.15)
						nb2[i] += (sin(a) + 0.3 * sin(2.0 * a) + 0.08 * sin(3.0 * a)) * 0.5 * env
				_add(b, nb2, 0.08 * ni)
			b = _lp(b, 3000.0)
		_:
			if kind.begins_with("plink"):
				var idx := int(kind.substr(5)) % PLINK_SEMIS.size()
				var f := 523.25 * pow(2.0, float(PLINK_SEMIS[idx]) / 12.0)
				b = _buf(0.5)
				_add(b, _modal(f, 7.0, 1.0, 0.5), 0.0); _add(b, _modal(2.0 * f, 12.0, 0.4, 0.4), 0.0); _add(b, _modal(3.01 * f, 22.0, 0.15, 0.3), 0.0)
			else:
				b = _buf(0.05)
	var mean := 0.0
	for v in b: mean += v
	mean /= maxf(1.0, b.size())
	var tail := mini(b.size(), int(0.004 * RATE))   # 1.18: no DC, and the last 4 ms fade so no cue ends on a step
	for i in b.size():
		b[i] -= mean
		if i >= b.size() - tail: b[i] *= float(b.size() - i) / tail
	normalize(b, PEAK_N6)
	return b

# ---------------------------------------------------------------- hum (offline)
## Render a steady hum at the given grid frequency and load. mode "ac" or "dc".
static func render_hum(hz: float, load_v: float, seconds: float, mode_ := "ac") -> PackedFloat32Array:
	var h := HumSynth.new(HUM_RATE)
	h.f_t = hz; h.load_t = load_v; h.snap(mode_ == "ac")
	return h.fill(int(seconds * HUM_RATE))

## Render the outdoor bed (wind, crickets when night > 0.3) at full level for `seconds`, for analysis.
static func render_outdoor(night: float, seconds: float) -> PackedFloat32Array:
	var o := OutdoorSynth.new(); o.level = 1.0; o.level_t = 1.0; o.night = night; o.night_t = night
	return o.fill(int(seconds * OutdoorSynth.RATE))

## Hum with a 1 Hz frequency dip (50 -> 49 -> 50) to hear pitch following f.
static func render_hum_dip(seconds: float) -> PackedFloat32Array:
	var h := HumSynth.new(HUM_RATE); h.snap(true); var out := PackedFloat32Array()
	var chunk := HUM_RATE / 10
	for k in int(seconds * 10):
		var t := float(k) / 10.0
		h.f_t = 50.0 - 1.0 * clampf(minf(t - 2.0, seconds - 2.0 - t) / 1.0 + 0.5, 0.0, 1.0)
		out.append_array(h.fill(chunk))
	return out

# ---------------------------------------------------------------- music
static func stem_gains(stress_v: float, cute_v: bool) -> Dictionary:
	return {"pad": 1.0, "perc": smoothstep(0.5, 0.85, stress_v) * 0.9, "lead": 0.8 if cute_v else 0.0}

static func _nf(root_midi: int, scale: Array, deg: int, oct: int) -> float:
	var o := int(floor(float(deg) / scale.size())); var d := posmod(deg, scale.size())
	return 440.0 * pow(2.0, float(root_midi + int(scale[d]) + 12 * (oct + o) - 69) / 12.0)

## Mix stems for `seconds` (looping) at the given stress/cute settings, peak-normalised to 0.8, with fades.
static func mix_music(stems: Dictionary, seconds: float, stress_v: float, cute_v: bool) -> PackedFloat32Array:
	var g := stem_gains(stress_v, cute_v); var n := int(seconds * MRATE)
	var out := PackedFloat32Array(); out.resize(n)
	for k in ["pad", "perc", "lead"]:
		var s: PackedFloat32Array = stems[k]; var gk := float(g[k])
		if gk <= 0.0: continue
		for i in n: out[i] += s[i % s.size()] * gk
	normalize(out, 0.8)
	for i in n: out[i] *= minf(1.0, minf(float(i) / (MRATE * 0.5), float(n - i) / (MRATE * 1.0)))
	return out


## Outdoor bed for the 3D province (synthesised, deterministic): wind as low-passed noise with slow gusts, and at night sparse cricket chirps
## (4.6 kHz pulses in groups of three). Silent when level is 0.
class OutdoorSynth:
	const RATE := 22050
	var level := 0.0
	var level_t := 0.0
	var night := 0.0
	var night_t := 0.0
	var lp := 0.0
	var lp2 := 0.0
	var hp := 0.0
	var gust := 0.0
	var t := 0.0
	var chirp_at := 1.0
	var chirp_n := 0
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	func _init() -> void: rng.seed = 11
	func fill(n: int) -> PackedFloat32Array:
		var out := PackedFloat32Array(); out.resize(n)
		var kl := 1.0 - exp(-1.0 / (0.8 * RATE))
		for i in n:
			level += (level_t - level) * kl; night += (night_t - night) * kl
			t += 1.0 / RATE
			if level < 0.0005: out[i] = 0.0; continue
			var w := rng.randf_range(-1.0, 1.0)
			lp += (w - lp) * 0.10; lp2 += (lp - lp2) * 0.20; hp += (lp2 - hp) * 0.012   # 1.18: wind was 61 % under 60 Hz (a rumble); now 40 Hz to 700 Hz
			gust = 0.55 + 0.45 * sin(t * 0.21) * sin(t * 0.077 + 1.3)
			var s := (lp2 - hp) * 1.0 * gust * (1.0 - 0.6 * night)
			if night > 0.3:   # crickets: a group of three short chirps, then a pause
				if t >= chirp_at:
					var k := fmod(t - chirp_at, 0.09)
					if k < 0.035: ph += 4600.0 / RATE; s += sin(TAU * ph) * 0.15 * (night - 0.3) * sin(PI * k / 0.035)
					if t - chirp_at > 0.27: chirp_at = t + 0.6 + rng.randf() * 1.4
			out[i] = s * level
		return out
