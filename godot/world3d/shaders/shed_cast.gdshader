// GRID province: the cool shadow over the sectors of a live town that the engine has shed (energy 0). A multiply over the ground and roofs
// below it, so the served half stays in warm sun and the shed half is darker and blue-shifted, a cue no healthy house or field has.
// Mesh: one fan per town, wedge k = the engine's energy index k. COLOR.r = k / 63, UV.x = radius / town edge. `sector_shed[k]` is 1 for a shed
// wedge. `front` is the wave radius (0..1): the shadow arrives with the wave that darkens the houses. Presentation only.
shader_type spatial;
render_mode blend_mul, unshaded, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float sector_shed[64];
uniform float front = 2.0;
uniform float night = 0.0;
uniform vec3 tint : source_color = vec3(0.42, 0.50, 0.72);
uniform float strength = 0.85;
varying float sec;

void vertex() { sec = COLOR.r * 63.0; }

void fragment() {
	float s = sector_shed[clamp(int(sec + 0.5), 0, 63)];
	float rn = UV.x;
	float k = s * (1.0 - smoothstep(front - 0.1, front, rn)) * (1.0 - smoothstep(0.78, 1.0, rn)) * strength * (1.0 - 0.6 * night);
	ALBEDO = mix(vec3(1.0), tint * 1.4, k);
}
