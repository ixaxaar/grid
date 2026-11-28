// Unshaded emissive marker (lamps, conductor glow, the cut marker, beams). COLOR alpha used for additive beams.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.8, 0.5, 1.0);
uniform float power = 2.0;
uniform float pulse_depth = 0.65;   // how deep the travelling pulses cut: 0.65 beads (the default), 0.2 a continuous conductor with a slow shimmer
uniform float pulse = 0.0;      // > 0: travelling pulses along UV.x at this speed (flow)
uniform float fade_v = 0.0;     // > 0: fade along UV.y (beams)
uniform float radial = 0.0;     // > 0: soft disc, fading to the edge at this radius (light pools)
uniform float inflate = 0.0;    // > 0: tubes grow with camera distance (metres per metre), so a conductor keeps a few pixels of width at play zoom
varying vec3 lp;
void vertex() {
	lp = VERTEX;
	if (inflate > 0.0) { float d = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz); VERTEX += NORMAL * inflate * d; }
}
void fragment() {
	float k = 1.0;
	if (pulse != 0.0) k = (1.0 - pulse_depth) + pulse_depth * pow(0.5 + 0.5 * sin((UV.x - TIME * pulse) * 6.2832), 6.0);
	if (fade_v > 0.0) k *= pow(1.0 - UV.y, fade_v);
	if (radial > 0.0) k *= pow(1.0 - smoothstep(0.0, radial, length(lp.xz)), 1.6);
	ALBEDO = tint.rgb * power * k * COLOR.rgb;
	ALPHA = tint.a * k;
}
