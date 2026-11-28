// GRID LOOK2 terrain: six splat-mapped CC0 materials (Poly Haven, docs/ASSETS.md), world-space UVs at two scales with a rotated second
// sample (no visible tile), a macro noise for large-scale colour drift, a field patchwork (plots with hedgerows) on farmland, slope rock.
// COLOR = (grass/field, forest floor, rock, sand) weights, UV2 = (mud/salt-marsh, paved/town) weights, written per vertex from the engine's tile kinds.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D field_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D macro_noise : filter_linear_mipmap, repeat_enable;
uniform float tile_m = 22.0;
uniform float night = 0.0;
uniform vec3 grass_tint = vec3(1.0);
uniform vec3 grass_hue = vec3(1.0);   // 1128c r3: the CC0 grass is yellow-olive (hue 47 deg); the province pulls it to a fresh green
uniform vec3 warm_drift = vec3(1.10, 1.04, 0.92);   // the macro colour drift's dry end (the province keeps it nearer to neutral: olive at noon)
uniform vec3 crop_hue = vec3(1.0);    // multiplies the pasture and green-crop colours (the province: greener)
uniform vec3 wheat_c = vec3(0.60, 0.51, 0.28);      // ripe grain and stubble (the province: a paler wheat)
uniform vec3 stubble_c = vec3(0.52, 0.47, 0.33);
uniform vec3 sand_tint = vec3(1.0);   // 1.18: the bay's beach is pale coral sand, not the province's grey shore
uniform float fields = 1.0;    // 1.18: the island bay has no farm plots (0)
uniform float wet_top = 2.2;   // 1.18: height (m) where wet sand ends; the bay's beach sits at 1 m
uniform float clouds = 1.0;   // 1.17: cloud shadows drift over the land by day (0 turns them off)
uniform float cloud_scale = 1.0;   // 1.18: the bay is 400 m across, so its clouds are drawn at a tenth of the province's size
float cloud_shade(vec2 xz) {   // a soft shadow from slow clouds: two octaves of the macro noise, drifting west to east at about 9 m/s
	xz /= cloud_scale;
	float c = texture(macro_noise, xz / 7000.0 + TIME * vec2(0.0013, 0.0004)).r * 0.65 + texture(macro_noise, xz / 2600.0 + TIME * vec2(0.0031, 0.0011)).r * 0.35;
	return 1.0 - 0.34 * smoothstep(0.52, 0.7, c) * (1.0 - night) * clouds;
}
uniform bool cheap = false;   // low tier: one sample per kind, no field plots, no normal maps   // the generated province: greener farmland

varying vec3 wpos;
varying vec3 wnrm;
varying vec2 w2;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	w2 = UV2;
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

// two samples at different scales and rotations, blended by a macro noise: kills the grid of repeats
// detail fades with distance (the owner saw grain: a 22 m tile seen from kilometres is noise): near = two rotated samples,
// mid = an 8x larger tiling, far = the texture's mean colour (its last mip), so the land reads as colour, not sparkle
vec3 tex2f(sampler2D t, vec2 p, float m, float g_mid, float g_far) {
	vec2 q = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * p * 0.37 + vec2(0.31, 0.17);
	vec3 nearc = mix(texture(t, p).rgb, texture(t, q).rgb, 0.35 + 0.3 * m);
	vec3 midc = texture(t, q * 0.125).rgb;
	vec3 farc = textureLod(t, p, 10.0).rgb;
	return mix(mix(nearc, midc, g_mid), farc, g_far);
}
vec3 nrm2(sampler2D t, vec2 p) { return texture(t, p).rgb; }

uniform sampler2D gravel_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // CC0 pass: ambientCG Gravel023 for the substation yards
uniform sampler2D gravel_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool real_gravel = false;
uniform float yard_gravel = 0.0;   // 1128c: 1 = paved areas are a gravel substation yard (crushed stone, tyre tracks, damp patches)
// paved ground: town gardens (dark green-grey) or a gravel yard: rock texture desaturated to stone grey, a fine speckle, wheel tracks
vec3 yard(vec2 xz, vec2 p, float m, float m2, float g_mid, float g_far) {
	vec3 town = mix(vec3(0.22, 0.27, 0.16), vec3(0.33, 0.32, 0.29), m2 * 0.6);
	if (yard_gravel < 0.5) return town;
	if (real_gravel) {
		vec3 gr = tex2f(gravel_a, p * 4.0, m, g_mid, g_far);
		float sp2 = h21(floor(xz * 3.0));
		vec3 gg = gr * vec3(0.40, 0.395, 0.385) * (0.85 + 0.3 * sp2);
		gg *= 1.0 - 0.25 * smoothstep(0.55, 0.75, texture(macro_noise, xz / 30.0).r);
		return gg;
	}
	vec3 r = tex2f(rock_a, p * 2.4, m, g_mid, g_far);
	float l = dot(r, vec3(0.333));
	float sp = h21(floor(xz * 9.0));
	vec3 g = vec3(0.30, 0.298, 0.29) * (0.65 + 0.7 * l) * (0.8 + 0.4 * sp);
	float damp = smoothstep(0.55, 0.75, texture(macro_noise, xz / 30.0).r);
	g *= 1.0 - 0.25 * damp;
	return g;
}
void fragment() {
	float vd = length(VERTEX);
	float g_mid = smoothstep(250.0, 1400.0, vd) * 0.7; float g_far = smoothstep(1800.0, 6000.0, vd);
	vec2 p = wpos.xz / tile_m;
	float m1 = texture(macro_noise, wpos.xz / 1900.0).r;
	float m2 = texture(macro_noise, wpos.xz / 420.0 + vec2(0.37, 0.71)).r;
	float m = m1 * 0.7 + m2 * 0.3;
	vec4 w = COLOR;
	float mud = w2.x, paved = w2.y;
	// slope: steep ground shows rock whatever the map says
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float rk = smoothstep(0.22, 0.42, slope);
	w.b = max(w.b, rk);
	// break the splat edges with noise so kinds do not meet on straight tile lines
	float jit = (m2 - 0.5) * 0.5;
	w = max(w + vec4(jit, -jit, 0.0, 0.0) * 0.6, vec4(0.0));
	float sum = w.r + w.g + w.b + w.a + mud + paved + 1e-4;
	w /= sum; mud /= sum; paved /= sum;

	if (cheap) {
		vec3 cc = texture(grass_a, p).rgb * grass_hue * grass_tint * w.r + texture(forest_a, p * 1.3).rgb * vec3(0.55, 0.62, 0.45) * w.g + texture(rock_a, p * 0.6).rgb * w.b
			+ texture(sand_a, p * 1.5).rgb * sand_tint * w.a + texture(mud_a, p).rgb * mud + vec3(0.26, 0.29, 0.20) * paved;
		cc *= mix(vec3(0.86, 0.92, 0.80), warm_drift, m1);
		ALBEDO = cc * mix(0.62, 1.0, smoothstep(0.2, wet_top, wpos.y)) * cloud_shade(wpos.xz); ROUGHNESS = 0.92; SPECULAR = 0.25;
	} else {
	// 11-28b (audit: the Voronoi plots read as the old low-poly map): farmland as rectangular strip fields, the way a field system looks
	// from the air. Each ~0.7 km block (warped edges) has one heading; inside it, staggered rectangles 75-150 m wide and 260-420 m long,
	// tramlines every 24 m and crop rows along the long side, grass headlands and broken hedges at every edge.
	vec2 bq = wpos.xz / 720.0 + 0.05 * vec2(sin(wpos.z / 900.0), cos(wpos.x / 1100.0));   // a slight wobble: curved block edges read as ring roads
	vec2 bc = floor(bq);
	float bang = (h21(bc * 1.7 + 4.0) - 0.5) * 1.6 + step(0.5, h21(bc)) * 1.5708;
	mat2 R = mat2(vec2(cos(bang), -sin(bang)), vec2(sin(bang), cos(bang)));
	vec2 r = R * wpos.xz;
	float colw = mix(110.0, 170.0, h21(bc + 2.0));   // each block its own field width
	float ci = floor(r.x / colw);
	float rowl = 260.0 + 160.0 * h21(vec2(ci, bc.x * 3.0 + bc.y));
	float ry = r.y + h21(vec2(ci, 9.0)) * rowl;
	float ri = floor(ry / rowl);
	vec2 cell = vec2(ci, ri) + bc * 131.0;
	float fx = fract(r.x / colw);
	if (h21(cell + 5.0) < 0.45) { cell.x += step(0.5, fx) * 0.5; fx = fract(fx * 2.0); colw *= 0.5; }   // some fields split in two strips
	float fy = fract(ry / rowl);
	vec2 bf = fract(bq);
	float edge = min(min(min(fx, 1.0 - fx) * colw, min(fy, 1.0 - fy) * rowl), min(min(bf.x, 1.0 - bf.x), min(bf.y, 1.0 - bf.y)) * 720.0);   // metres to the nearest field edge
	float crop = h21(cell * 1.31);
	float px = max(fwidth(r.x), 1e-3);                       // metres per pixel across the rows
	float tram_d = abs(fract(r.x / 24.0 + 0.5) - 0.5) * 24.0;  // metres to the nearest tramline
	float tram = clamp((0.9 - tram_d) / px + 0.5, 0.0, 1.0) * min(1.0, 1.8 / px) * (1.0 - smoothstep(1500.0, 4500.0, vd));
	float rows = (0.5 + 0.5 * sin(r.x * 6.2832 / 2.5)) * (1.0 - smoothstep(0.25, 1.0, px));   // crop rows, only where a pixel is smaller than a row
	vec3 g = tex2f(grass_a, p, m, g_mid, g_far) * grass_hue;
	vec3 plot = g;
	float lum = dot(g, vec3(0.33));
	// 1128c: an aerial-photo palette (the pastel creams read as a board game): deeper greens, honest soil browns, muted gold;
	// inside each field a sprayer/moisture streak along the rows and a colour drift, so a field is not one flat swatch
	vec2 rr = vec2(r.x / 9.0, ry / 140.0);
	float streak = texture(macro_noise, rr * 0.11 + cell * 0.21).r;
	float drift = texture(macro_noise, wpos.xz / 160.0 + cell * 0.13).r;
	if (crop < 0.26) plot = vec3(0.25, 0.38, 0.14) * crop_hue * (0.8 + 0.7 * lum);                                                 // pasture
	else if (crop < 0.42) plot = wheat_c * (0.75 + 0.6 * lum) * (1.0 - 0.12 * rows - 0.22 * tram);   // ripe grain
	else if (crop < 0.58) plot = mix(vec3(0.30, 0.23, 0.16), tex2f(field_a, r / 14.0, m, g_mid, g_far) * vec3(0.72, 0.58, 0.44), 0.55) * (1.0 - 0.25 * rows - 0.15 * tram);   // plough
	else if (crop < 0.86) plot = mix(vec3(0.20, 0.34, 0.11), vec3(0.30, 0.42, 0.13), h21(cell + 3.0)) * crop_hue * (0.8 + 0.7 * lum) * (1.0 - 0.14 * rows - 0.25 * tram);   // green crops
	else plot = stubble_c * (0.8 + 0.6 * lum) * (1.0 - 0.1 * rows - 0.2 * tram);                       // stubble
	plot *= 0.84 + 0.3 * streak;
	plot *= mix(vec3(0.94, 1.0, 0.94), vec3(1.05, 0.98, 0.92), drift);
	plot = mix(vec3(dot(plot, vec3(0.3, 0.55, 0.15))), plot, 0.72);   // 1128c (art review): the quilt was loud; a third less saturation
	float en = texture(macro_noise, wpos.xz / 55.0).r;
	plot *= 0.9 + 0.22 * texture(macro_noise, wpos.xz / 23.0 + cell * 0.37).r;
	plot = mix(g * grass_tint * 1.05, plot, smoothstep(2.0, 5.0 + 7.0 * en, edge));   // a grass headland of uneven width
	vec3 hedge_c = vec3(0.10, 0.18, 0.07) * (0.8 + lum);
	float tuft = smoothstep(0.3, 0.6, texture(macro_noise, wpos.xz / 9.0).r);
	plot = mix(plot, hedge_c, (1.0 - smoothstep(0.0, 2.6, edge)) * 0.75 * tuft);   // hedges with gaps
	vec3 grass = mix(g * grass_tint, plot, 0.85 * fields * (1.0 - 0.5 * g_far) * (1.0 - 0.7 * night));   // 11-28b: calmer at night (the quilt was loud under the moon)   // field colours calm down with distance and at night: no quilt from the air

	vec3 col = grass * w.r
		+ tex2f(forest_a, p * 1.3, m, g_mid, g_far) * vec3(0.55, 0.62, 0.45) * w.g
		+ tex2f(rock_a, p * 0.6, m, g_mid, g_far) * w.b
		+ tex2f(sand_a, p * 1.5, m, g_mid, g_far) * sand_tint * w.a
		+ tex2f(mud_a, p, m, g_mid, g_far) * vec3(0.85, 0.9, 0.8) * mud
		+ yard(wpos.xz, p, m, m2, g_mid, g_far) * paved;   // gardens and yards between the houses: a town reads darker than the fields around it, not as a pale disc
	// macro colour drift: some hillsides drier, some lusher
	col *= mix(vec3(0.86, 0.92, 0.80), warm_drift, m1);
	// wet sand / mud darkens near the waterline
	col *= mix(0.62, 1.0, smoothstep(0.2, wet_top, wpos.y));

	vec3 pn = real_gravel && yard_gravel > 0.5 ? nrm2(gravel_n, p * 4.0) : nrm2(grass_n, p);
	vec3 n = nrm2(grass_n, p) * w.r + pn * paved + nrm2(forest_n, p * 1.3) * (w.g + mud) + nrm2(rock_n, p * 0.6) * w.b + nrm2(sand_n, p * 1.5) * w.a;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = 0.9 * (1.0 - smoothstep(150.0, 1500.0, vd));   // normal detail only up close: no specular sparkle far away
	ALBEDO = col * cloud_shade(wpos.xz);
	ROUGHNESS = max(mix(0.95, 0.75, w.b) * mix(1.0, 0.5, mud), mix(0.0, 0.97, smoothstep(300.0, 2500.0, vd)));
	SPECULAR = 0.3;
	}
}
