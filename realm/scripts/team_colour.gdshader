shader_type spatial;
// Team colour, the Warcraft III way (team_colour.gd): one mask per material, tinted per instance from the
// house that holds it. A building's roof tiles and trims, and an army's armour, share this one shader.
// team_color.a is how far the colour has come in (0: the material as made). The near-camera dither fade
// matches realistic.gd's (camera.json near_fade).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.85;
uniform float team_amount : hint_range(0.0, 1.0) = 0.85;  // how much of this material takes the colour
uniform float fade_gone = 1.2;
uniform float fade_solid = 2.6;
instance uniform vec4 team_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
// What the building is (team_colour.gd, from its kit model): 0 a cottage, 1 a townhouse or inn, 2 the
// castle, hall and anything else (banners, armour): the full colour. Ordinary houses carry a smaller share.
instance uniform float team_rank = 2.0;
// Roofs (data/look.json team.roofs; art target 01-town): each house's roof is, by a seed from where it
// stands, thatch, the tiles' own terracotta, darker tile, or the house's colour; the castle's and the
// hall's always the house's. The weights are thatch, terracotta, dark, house (summing to 1).
uniform bool is_roof = false;
uniform vec4 roof_cottage = vec4(0.55, 0.25, 0.1, 0.1);
uniform vec4 roof_town = vec4(0.15, 0.4, 0.2, 0.25);
uniform vec3 thatch : source_color = vec3(0.8, 0.64, 0.34);
uniform vec3 dark_tile : source_color = vec3(0.5, 0.42, 0.4);
uniform float ordinary_share = 0.5;  // a house's trims and shutters take this share of the colour
uniform float paint_sat = 0.8;  // the house colour toned toward its own grey: warm, painted, not neon
uniform vec3 paint_warm : source_color = vec3(1.0, 0.93, 0.84);
varying float v_seed;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	// The building's own place (a MultiMesh instance's origin is in MODEL_MATRIX): one seed per house.
	v_seed = h21(floor(MODEL_MATRIX[3].xz * 8.0) + 0.5);
}

void fragment() {
	vec4 c = albedo;
	if (has_albedo_tex) c *= texture(albedo_tex, UV);
	// The house's colour at the material's own brightness: the tiles' shading stays, the hue is the house's.
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float tl = max(dot(team_color.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 tc = clamp(team_color.rgb * lum / tl * 1.05, 0.0, 1.0);
	tc = mix(vec3(dot(tc, vec3(0.299, 0.587, 0.114))), tc, paint_sat) * paint_warm;
	float amt = team_amount * team_color.a;
	vec3 base = c.rgb;
	if (is_roof && team_rank < 1.5) {
		vec4 w = team_rank < 0.5 ? roof_cottage : roof_town;
		float s = v_seed;
		if (s < w.x) {
			// Thatch: straw at the tiles' shading, combed into fine streaks down the slope.
			float streak = 0.82 + 0.3 * h21(vec2(floor(UV.x * 90.0), floor(UV.y * 6.0)));
			base = thatch * (0.6 + 0.8 * lum) * streak;
			amt = 0.0;
		} else if (s < w.x + w.y) {
			amt = 0.0;  // the tiles' own fired terracotta
		} else if (s < w.x + w.y + w.z) {
			base = dark_tile * (0.5 + lum);
			amt = 0.0;
		}
	} else if (!is_roof && team_rank < 1.5) {
		amt *= ordinary_share;
	}
	ALBEDO = mix(base, tc, amt);
	ROUGHNESS = roughness;
	if (has_normal) NORMAL_MAP = texture(normal_tex, UV).rgb;
	// Dissolve right in front of the lens (Godot's pixel dither, as the other buildings do).
	float d = length(VERTEX);
	if (d < fade_solid) {
		float t = clamp((d - fade_gone) / max(fade_solid - fade_gone, 0.01), 0.0, 1.0);
		const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if (t <= (BAYER[p.y * 4 + p.x] + 0.5) / 16.0) discard;
	}
}
