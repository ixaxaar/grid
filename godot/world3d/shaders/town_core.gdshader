// GRID LOOK2 town core: a warm additive disc over a lit town, seen only from far away (a town reads as a place from play height).
// Scaled by the town's lit share from the engine: a dark town has no core.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;
uniform float night = 0.0;
uniform float town_lit[64];
uniform vec3 lamp : source_color = vec3(1.0, 0.62, 0.30);
varying float far;
varying float lit;
void vertex() {
	far = smoothstep(1200.0, 4500.0, length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz));
	lit = town_lit[clamp(int(COLOR.a * 63.0 + 0.5), 0, 63)];
}
void fragment() {
	float k = 1.0 - UV.x * UV.x; k *= k;
	ALBEDO = lamp * k * smoothstep(0.35, 0.9, night) * lit * far * 0.28;
}
