// GRID province street lamps and beacons, seen from the play camera. mode 0: a billboard halo whose size grows with distance (a lamp is a pixel
// at 1 km, so it is drawn about 0.4 % of the distance wide, 1 to 16 m), additive. mode 1: a pool of sodium light on the road, flat, fading out
// beyond 2 km where the halos and the town glow carry. An instance scaled to nothing (the engine's dark or shed area) draws nothing.
shader_type spatial;
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;
uniform int mode = 0;
uniform float night = 0.0;
uniform vec3 tint : source_color = vec3(1.0, 0.62, 0.28);
uniform float gain = 1.6;
uniform float size_k = 0.0042;
uniform float pool_r = 11.0;
varying vec2 q;
varying float fade;
void vertex() {
	q = VERTEX.xy;
	vec3 c = (MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float d = length(c);
	float on = step(0.01, length(MODEL_MATRIX[0].xyz));
	if (mode == 0) {
		float s = clamp(d * size_k, 1.0, 16.0) * on;
		VERTEX = c + vec3(q * s, 0.0);
		fade = 1.0;
	} else {
		q = VERTEX.xz / pool_r;
		VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX * on, 1.0)).xyz;
		fade = 1.0 - smoothstep(500.0, 2200.0, d);
	}
}
void fragment() {
	float r = length(q);
	float k = pow(clamp(1.0 - r, 0.0, 1.0), 2.0);
	float nn = smoothstep(0.35, 0.9, night);
	if (mode == 0) ALBEDO = tint * (k + 1.5 * pow(clamp(1.0 - r * 3.0, 0.0, 1.0), 2.0)) * gain * nn;
	else ALBEDO = tint * k * 0.45 * nn * fade;
}
