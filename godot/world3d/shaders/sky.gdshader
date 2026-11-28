// GRID LOOK2 sky: gradient by time of day (colours set from GDScript), sun disc and glow from the directional light, a moon, stars at night,
// a thin drifting cloud layer. Cheap, no textures beyond one noise.
shader_type sky;
render_mode use_debanding;

uniform vec3 zenith : source_color = vec3(0.2, 0.4, 0.75);
uniform vec3 horizon : source_color = vec3(0.7, 0.8, 0.9);
uniform vec3 ground : source_color = vec3(0.15, 0.16, 0.18);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.6, 0.3);
uniform float night = 0.0;
uniform float dusk = 0.0;
uniform float cloud_cover = 0.45;
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.85, 0.7);
uniform vec3 cloud_dark : source_color = vec3(0.3, 0.32, 0.4);
uniform vec3 moon_dir = vec3(0.3, 0.5, -0.8);
uniform sampler2D pano : filter_linear_mipmap, repeat_enable;   // CC0 pass: Poly Haven Kloppenheim 02 (Pure Sky), a night sky with its own moon and stars
uniform float pano_k = 0.0;        // 0 = the generated sky only
uniform float pano_gain = 0.35;
uniform vec2 pano_moon = vec2(0.62, 0.295);   // where the moon sits in the file: longitude and elevation (radians)
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;

float h31(vec3 p) { return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453); }

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon, zenith, pow(clamp(up, 0.0, 1.0), 0.45));
	if (up < 0.0) col = mix(horizon, ground, clamp(-up * 4.0, 0.0, 1.0));
	if (LIGHT0_ENABLED) {
		vec3 sd = LIGHT0_DIRECTION;
		float c = clamp(dot(d, sd), 0.0, 1.0);
		col += sun_glow * (pow(c, 6.0) * 0.45 + pow(c, 64.0) * 0.8) * (0.4 + dusk);
		col += sun_glow * pow(c, 3.0) * 0.25 * dusk * (1.0 - clamp(up * 2.5, 0.0, 1.0));
		if (c > 0.99965 && up > -0.02) col += LIGHT0_COLOR * 3.0 * (1.0 - night);
	}
	// the night panorama, turned in azimuth and tilted so its moon sits where the scene's moon light comes from
	if (pano_k > 0.0 && night > 0.02 && up > -0.05) {
		vec3 md = normalize(moon_dir);
		float lon = atan(d.x, -d.z) - atan(md.x, -md.z) + pano_moon.x;
		float el = asin(clamp(d.y, -1.0, 1.0)) - (asin(md.y) - pano_moon.y);
		vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 - el / 3.1415927);
		vec3 pc = min(textureLod(pano, uv, 0.0).rgb, vec3(6.0)) * pano_gain;
		col = mix(col, pc, night * pano_k * smoothstep(-0.05, 0.03, up));
	}
	// stars and the moon
	if (night > 0.05 && up > 0.0 && pano_k < 0.5) {
		vec3 q = floor(d * 380.0);
		float s = h31(q);
		float star = step(0.9975, s) * (0.4 + 0.6 * h31(q + 1.7));
		col += vec3(0.85, 0.9, 1.0) * star * smoothstep(0.55, 0.95, night) * smoothstep(0.0, 0.25, up) * 1.6;   // stars only after civil dusk (they read as dust in a pink sky)
		float mc = dot(d, normalize(moon_dir));
		col += vec3(0.9, 0.93, 1.0) * (smoothstep(0.9993, 0.9996, mc) * 1.4 + pow(max(mc, 0.0), 80.0) * 0.08) * night;
	}
	// clouds: a plane at 2.5 km, drifting
	if (up > 0.01) {
		vec2 cp = d.xz / (d.y + 0.08) * 0.32 + vec2(TIME * 0.0016, TIME * 0.0006);
		float n = texture(noise, cp).r * 0.65 + texture(noise, cp * 2.9 + 0.3).r * 0.35;
		float cov = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		float edge = clamp((n - (1.0 - cloud_cover)) * 3.0, 0.0, 1.0);
		vec3 cc = mix(cloud_lit, cloud_dark, edge);
		col = mix(col, cc, cov * smoothstep(0.01, 0.12, up) * 0.9);
	}
	COLOR = col;
}
