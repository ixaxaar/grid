// GRID LOOK2 houses (MultiMesh): wall tint from the instance colour, roofs marked by UV.x > 1.5, windows in a world-sized grid per floor.
// INSTANCE_CUSTOM.r = this building's energy from the engine (WorldMath.building_energy: (V/Vnom)^2, 0 when shed or dark), .g = a seed,
// .b unused (night is a uniform). A window is lit when its hash is below the energy: a dark town is dark, a sagging town is dimmer and thinner.
shader_type spatial;
render_mode diffuse_burley;

uniform vec3 roof_a : source_color = vec3(0.50, 0.17, 0.11);
uniform vec3 roof_b : source_color = vec3(0.30, 0.31, 0.36);
uniform vec3 lamp : source_color = vec3(1.0, 0.70, 0.36);
uniform float lamp_power = 2.2;
uniform float night = 0.0;   // set by Province3D from the operator clock

varying vec3 wp;
varying vec3 wn;
varying vec4 ic;
varying float roof;
varying float hy;
void vertex() {
	// 1128c: far houses grow (up to 2.2x at 6 km) so a town reads as a cluster of roofs from the province camera, not a street skeleton
	float hd = length((MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz);
	float grow = 1.0 + 1.2 * smoothstep(1200.0, 6000.0, hd);
	VERTEX.xz *= grow; VERTEX.y *= mix(1.0, grow, 0.5);
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	ic = INSTANCE_CUSTOM;
	roof = step(1.5, UV.x);
	hy = wp.y - MODEL_MATRIX[3].y;
}
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	if (roof > 0.5) {
		vec3 rc = ic.g < 0.6 ? roof_a : (ic.g < 0.85 ? roof_b : vec3(0.42, 0.34, 0.26));   // mostly terracotta: slate and brown read as holes from above
		rc *= 0.75 + 0.5 * h21(vec2(ic.g * 91.0, 3.0));
		float rfar = smoothstep(500.0, 3000.0, length(VERTEX));
		rc = mix(rc, rc * vec3(0.92, 0.78, 0.74), rfar * (1.0 - night));   // 1128c: far roofs deeper (the warm lift read as pale pink frost)   // far roofs by day: a little warmer so a town reads as red roofs, not a pale texture
		rc = mix(rc, vec3(0.52, 0.28, 0.21) * (0.85 + 0.3 * h21(vec2(ic.g * 13.0, 5.0))), 0.8 * (1.0 - night) * smoothstep(1800.0, 5000.0, length(VERTEX)));   // by day, from the map camera a town is one warm tone, not red and slate confetti
		float tiles = 0.85 + 0.15 * step(0.5, fract(wp.y * 3.0));
		float dark = (1.0 - step(0.001, ic.r)) * night;   // a dark town at night: roofs lose the lamplight they would catch
		ALBEDO = rc * tiles * (1.0 - 0.45 * dark); ROUGHNESS = 0.7; SPECULAR = mix(0.5, 0.15, smoothstep(300.0, 1500.0, length(VERTEX)));   // 1128c: far roofs mirrored the sky white   // roofs catch the moon instead of reading as holes
		EMISSION = lamp * step(0.001, ic.r) * night * 0.05 * smoothstep(350.0, 1500.0, length(VERTEX)) + rc * 0.07 * (1.0 - 0.6 * dark);   // sky fill: a slope facing away from the moon is dim, not black
	} else {
		// 1128c: walls in a builder's palette (cream and grey render, brick, ochre, whitewash) at photo albedo; the bright white
		// and pink boxes read as a toy town in strong sun
		float hk = h21(vec2(ic.g * 37.0, 11.0));
		vec3 pal = hk < 0.3 ? vec3(0.66, 0.60, 0.49) : (hk < 0.5 ? vec3(0.55, 0.55, 0.53) : (hk < 0.72 ? vec3(0.46, 0.27, 0.20) : (hk < 0.88 ? vec3(0.64, 0.52, 0.33) : vec3(0.74, 0.73, 0.70))));
		vec3 base = mix(COLOR.rgb * 0.7, pal * 0.78, 0.8);
		base = mix(base, vec3(0.58, 0.52, 0.45), 0.7 * (1.0 - night) * smoothstep(1800.0, 5000.0, length(VERTEX)));
		base *= 1.0 - 0.18 * step(hy, 0.6);   // a darker plinth
		// along-wall coordinate in metres
		float u = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
		vec2 cell = vec2(floor(u / 2.6), floor(hy / 2.9));
		vec2 f = vec2(fract(u / 2.6), fract(hy / 2.9));
		float win = step(0.28, f.x) * step(f.x, 0.72) * step(0.35, f.y) * step(f.y, 0.8);
		win *= step(1.0, hy);   // no windows in the plinth
		float lit = step(h21(cell + ic.g * 17.0), ic.r) * win * step(0.18, h21(cell * 1.7 + ic.g * 5.0));   // some rooms dark by design
		float dark = (1.0 - step(0.001, ic.r)) * night;
		float wfar = smoothstep(600.0, 3000.0, length(VERTEX));
		ALBEDO = mix(base * (1.0 - 0.45 * wfar), vec3(0.05, 0.06, 0.08), win * 0.85) * (1.0 - 0.45 * dark);   // far walls a little darker so the roofs carry the town
		ROUGHNESS = mix(0.85, 0.15, win); SPECULAR = mix(0.4, 0.1, smoothstep(300.0, 1500.0, length(VERTEX)));
		float flick = 0.85 + 0.15 * h21(cell * 3.1 + ic.g);
		float far = smoothstep(350.0, 1500.0, length(VERTEX));
		EMISSION = lamp * lit * lamp_power * flick * (0.04 * (1.0 - far) + smoothstep(0.15, 0.8, night)) * (1.0 + 2.2 * far);   // windows carry the town from afar at night; by day they do not glow (far daytime towns read as pink dots)
		EMISSION += lamp * step(0.001, ic.r) * night * 0.16 * far;   // a lit house reads as a warm dot from the whole province; a dark one is dark
	}
}
