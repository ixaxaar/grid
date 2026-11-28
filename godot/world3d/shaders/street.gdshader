// GRID LOOK2 streets and town cores (manager review 1.15: from play height a town must read as a place, not speckle).
// Streets: asphalt by day; at night a sodium glow that grows with distance, widened so a far street stays a line instead of sub-pixel noise.
// The town's lit share (town_lit, from the engine) scales the glow. The warm core disc is town_core.gdshader.
shader_type spatial;
render_mode cull_disabled;
uniform float night = 0.0;
uniform float town_lit[64];
uniform vec3 lamp : source_color = vec3(1.0, 0.66, 0.32);
uniform sampler2D asp_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;   // CC0 pass: ambientCG Asphalt031, in world metres; far streets stay the flat tone
uniform bool asphalt = false;
varying vec3 wp;
varying float lat_s;
varying float far;
varying float lit;
void vertex() {
	float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	far = smoothstep(700.0, 3500.0, d);
	lit = town_lit[clamp(int(COLOR.a * 63.0 + 0.5), 0, 63)];
	vec2 lat = COLOR.rg * 2.0 - 1.0;
	float side = COLOR.b * 2.0 - 1.0;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; lat_s = COLOR.b;
	float nn_v = smoothstep(0.35, 0.9, night);
	// main streets stay about one pixel wide at any distance past 3.5 km at night, where they carry the sodium line; by day the widening is a
	// third of that (owner review 11-28 of chapters 5-6: widened asphalt read as thick black ribbons across the fields)
	VERTEX.xz += lat * side * d * 0.0007 * far * UV.y * mix(0.0, 1.0, nn_v);   // 1128c: 0.33 still drew far towns as grey scribbles
	VERTEX.y += far * d * 0.0002;
}
void fragment() {
	float nn = smoothstep(0.35, 0.9, night);
	// by day a far street fades toward a dusty road tone instead of staying black asphalt
	ALBEDO = mix(vec3(0.10, 0.10, 0.11), vec3(0.12, 0.12, 0.115), far * (1.0 - nn)) * (1.0 - 0.6 * far * nn);   // 1128c: the dusty far tone read as chalk scribbles over the towns
	if (asphalt) {
		float near = 1.0 - smoothstep(250.0, 1400.0, length(VERTEX));
		vec3 ta = texture(asp_a, wp.xz / 5.0).rgb * 0.62 * mix(0.8, 1.15, texture(asp_a, wp.xz / 37.0).r);   // a patched, worn surface: a second, large sample varies the tone
		float edge = smoothstep(0.0, 0.07, lat_s) * smoothstep(1.0, 0.93, lat_s);   // a worn verge along each kerb
		ta = mix(ta * vec3(1.25, 1.2, 1.05), ta, edge);
		ALBEDO = mix(ALBEDO, ta, near * (1.0 - 0.5 * nn));
	}
	ROUGHNESS = 0.95; SPECULAR = 0.06;   // 1128c: default specular at a grazing view mirrored the sky: far streets read as pale scribbles
	// 11-28: the ribbon's own normal pointed down, so by day a street was lit like the underside of the ground (near black); light it as flat ground
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	// 1.18 (lead's review: orange stubs like glowing rods at dusk): up close the street is asphalt lit by its own lamps; only far away, where a
	// street is a pixel wide, does it carry a sodium line, so a town reads from the horizon
	EMISSION = lamp * nn * lit * 0.4 * smoothstep(0.35, 1.0, far) * mix(0.3, 1.0, UV.y);
}
