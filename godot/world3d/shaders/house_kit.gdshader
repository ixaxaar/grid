// GRID province houses, near LOD (MultiMesh of the Kenney suburban kit, docs/ASSETS.md). One material per surface (mode): 0 trim, 1 wall, 2 roof, 3 window.
// The instance carries what the engine drives: COLOR = wall tint, INSTANCE_CUSTOM.r = this building's energy (WorldMath.building_energy, 0 when shed or
// dark), .g = a seed. A pane (UV2.x = a hash of the pane, baked by Assets3D.province_house) is lit when its hash is below the energy, as house.gdshader
// does for the far LOD: a dark town is dark, a sagging town is dimmer and thinner. UVs are metric box projections: the tangent frame follows the axis.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform int mode = 0;
uniform sampler2D alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_depth = 0.8;
uniform vec3 lamp : source_color = vec3(1.0, 0.70, 0.36);
uniform float lamp_power = 2.4;
uniform bool grid = false;   // blocks: the glass is long strips, so a lit room is a 3.2 m bay of the local wall grid, not a pane
uniform float night = 0.0;   // set by Province3D from the operator clock
uniform vec3 roof_tint[3];   // Assets3D.ROOF_TINTS_NEAR (terracotta, slate-blue, brown); no neutral grey: the shed cue below must be the only cool dark roof

varying vec4 ic;
varying float pane;
varying vec3 lp;
varying vec3 ln;

void vertex() {
	ic = INSTANCE_CUSTOM;
	pane = UV2.x; lp = VERTEX; ln = NORMAL;
	vec3 an = abs(NORMAL);
	if (an.z >= an.x && an.z >= an.y) { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 1.0, 0.0); }
	else if (an.x >= an.y) { TANGENT = vec3(0.0, 1.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
	else { TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, 1.0); }
}

float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

vec3 shed_tone(vec3 c, float shed) {   // shed by the engine while the town is live: in a cool shadow (darkened, blue-shifted), as if the sun did not reach it
	return mix(c, vec3(dot(c, vec3(0.3, 0.55, 0.15))) * vec3(0.97, 0.98, 1.0) * 0.6, shed * 0.8) * mix(1.0, 0.82, shed);   // r4: dark and nearly grey (about 40 % darker, desaturated), no blue cast
}

void fragment() {
	float shed = step(0.5, ic.b);
	float dark = (1.0 - step(0.001, ic.r)) * night;   // a dark town at night: its walls lose the lamplight they would catch
	if (mode == 3) {
		float pid = pane;
		if (grid) { float u = abs(ln.x) > abs(ln.z) ? lp.z : lp.x; pid = h21(floor(vec2(u / 3.2, lp.y / 3.2)) + floor(ln.xz * 2.0) * 31.0); }
		float lit = step(h21(vec2(pid * 91.0, ic.g * 17.0)), ic.r) * step(0.18, h21(vec2(pid * 53.0, ic.g * 5.0)));   // some rooms dark by design
		float flick = 0.85 + 0.15 * h21(vec2(pid * 7.0, ic.g));
		ALBEDO = vec3(0.045, 0.055, 0.07) * (1.0 - 0.4 * dark); ROUGHNESS = 0.12; SPECULAR = 0.6;
		float far = smoothstep(80.0, 700.0, length(VERTEX));   // a pane is a pixel from the province camera: it glows wider and brighter with distance, as the far LOD's windows do
		float em = lit * lamp_power * flick * (0.06 + smoothstep(0.15, 0.8, night)) * (1.0 + 2.6 * far);
		EMISSION = lamp * min(em, grid ? 2.6 : 6.0);   // r3 (P02): a core tower's lit bays summed to white blobs under the bloom; the emission is capped, the colour stays amber
	} else if (mode == 2) {
		float k = ic.g;
		vec3 rc = k < 0.6 ? roof_tint[0] : (k < 0.85 ? roof_tint[1] : roof_tint[2]);   // terracotta, slate-blue, brown on the tile texture
		rc *= 0.8 + 0.4 * h21(vec2(ic.g * 91.0, 3.0));
		ALBEDO = shed_tone(texture(alb, UV).rgb * rc * (1.0 - 0.45 * dark), shed);
		ROUGHNESS = texture(rgh, UV).r * 0.95; SPECULAR = 0.3;
		NORMAL_MAP = texture(nrm, UV).rgb; NORMAL_MAP_DEPTH = normal_depth;
		EMISSION = ALBEDO * 0.04;   // sky fill: a slope facing away from the moon is dim, not black
	} else if (mode == 1) {
		ALBEDO = shed_tone(texture(alb, UV).rgb * COLOR.rgb * (1.0 - 0.45 * dark), shed);
		ROUGHNESS = texture(rgh, UV).r; SPECULAR = 0.25;
		NORMAL_MAP = texture(nrm, UV).rgb; NORMAL_MAP_DEPTH = normal_depth;
		EMISSION = ALBEDO * 0.04 + lamp * step(0.001, ic.r) * night * 0.14 * smoothstep(250.0, 1200.0, length(VERTEX));   // a lit house reads as a warm dot from far; a dark one is dark
	} else {
		ALBEDO = shed_tone(texture(alb, UV).rgb * (1.0 - 0.45 * dark), shed); ROUGHNESS = 0.8; SPECULAR = 0.3;
		EMISSION = ALBEDO * 0.04;
	}
}
