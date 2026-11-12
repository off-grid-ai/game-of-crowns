shader_type spatial;
// Team colour, the Warcraft III way (team_colour.gd): one mask per material, tinted per instance from the
// house that holds it. A building's roof tiles and trims, and an army's armour, share this one shader.
// team_color.a is how far the colour has come in (0: the material as made). The near-camera dither fade
// matches realistic.gd's (camera.json near_fade).
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform vec2 uv_scale = vec2(1.0);  // the material's own uv1_scale (a roof's finer tiles: house_kit.roof_uv)
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
// A tiered kit house's own covering (house_tiers.gd names its roof material; data/assets.json house_kit):
// 0 by the seed as below; 1 thatch, 2 the tiles' terracotta, 3 slate, 4 the house's colour, 5 wood shingle
// (slate and shingle are the tiles in their material's own tint, house_kit.roof_tints).
uniform int roof_kind = 0;
uniform vec4 roof_cottage = vec4(0.55, 0.25, 0.1, 0.1);
uniform vec4 roof_town = vec4(0.15, 0.4, 0.2, 0.25);
uniform vec3 thatch : source_color = vec3(0.72, 0.53, 0.27);
// Thatch (look.json team.roofs.thatch, thatch_old, straw.*): straw laid in bundles down the slope, never the tiles' plank-like
// rows. thatch_old: the weathered grey-brown an older roof turns (each roof somewhere between, by its seed);
// fibre and clump: how strong the bundles and the patches read; eave_dark: how much darker the ragged
// eave is; eave_band: how deep it reaches up the roof (a share of a storey); storey: a kit storey in the
// mesh's own units (house_builder.gd: 3 m at 0.12 units a metre), where a roof's eave sits.
uniform vec3 thatch_old : source_color = vec3(0.5, 0.42, 0.31);
uniform float thatch_fibre = 0.14;
uniform float thatch_clump = 0.16;
uniform float thatch_eave_dark = 0.62;
uniform float thatch_eave_band = 0.16;
uniform float thatch_storey = 0.36;
uniform vec3 dark_tile : source_color = vec3(0.5, 0.42, 0.4);
uniform float ordinary_share = 0.5;  // a house's trims and shutters take this share of the colour
uniform float paint_sat = 0.8;  // the house colour toned toward its own grey: warm, painted, not neon
uniform vec3 paint_warm : source_color = vec3(1.0, 0.93, 0.84);
varying float v_seed;
varying vec3 v_mpos;  // the mesh's own frame: a kit roof's ridge runs along z, its slopes fall along x
varying vec3 v_mnormal;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), u.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	// The building's own place (a MultiMesh instance's origin is in MODEL_MATRIX): one seed per house.
	v_seed = h21(floor(MODEL_MATRIX[3].xz * 8.0) + 0.5);
	v_mpos = VERTEX;
	v_mnormal = NORMAL;
}

void fragment() {
	vec4 c = albedo;
	if (has_albedo_tex) c *= texture(albedo_tex, UV * uv_scale);
	// The house's colour at the material's own brightness: the tiles' shading stays, the hue is the house's.
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float tl = max(dot(team_color.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 tc = clamp(team_color.rgb * lum / tl * 1.05, 0.0, 1.0);
	tc = mix(vec3(dot(tc, vec3(0.299, 0.587, 0.114))), tc, paint_sat) * paint_warm;
	float amt = team_amount * team_color.a;
	vec3 base = c.rgb;
	bool straw = false;
	if (is_roof && (team_rank < 1.5 || roof_kind > 0)) {
		vec4 w = team_rank < 0.5 ? roof_cottage : roof_town;
		float s = v_seed;
		// A named covering stands in for the seed's draw: thatch; terracotta, slate and shingle (the
		// tiles in their own tint); the house's colour.
		bool own_tint = roof_kind == 2 || roof_kind == 3 || roof_kind == 5;
		if (roof_kind == 4) s = 2.0;
		if ((roof_kind == 0 && s < w.x) || roof_kind == 1) {
			// Thatch (art target 01-town): soft ochre straw in bundles laid down the slope, patchy,
			// each roof its own age, the eave darker and ragged. The tiles' texture and their
			// rows are left out: their columns read as yellow planks.
			straw = true;
			// A roof whose ridge runs along x (a tiered house turned eaves to the street) falls along z.
			bool turned = abs(v_mnormal.z) > abs(v_mnormal.x);
			float across = turned ? v_mpos.x : v_mpos.z;
			float down = turned ? abs(v_mpos.z) : abs(v_mpos.x);
			float seed_s = fract(s * 7.31);
			float bundle = vnoise(vec2(across * 55.0 + seed_s * 17.0, down * 7.0));
			float fine = vnoise(vec2(across * 140.0, down * 16.0 + seed_s * 5.0));
			// Fine straw only where a pixel can hold it, so it never shimmers at a distance.
			float hold = clamp(1.0 - fwidth(across * 140.0) * 0.8, 0.0, 1.0);
			float clumps = vnoise(v_mpos.xz * 6.0 + seed_s * 31.0);
			vec3 straw_col = mix(thatch, thatch_old, clamp(seed_s * 0.75 + (clumps - 0.5) * 0.3, 0.0, 1.0));
			float shade = 1.0 + thatch_fibre * (bundle - 0.5) * 2.0 + thatch_fibre * 0.6 * hold * (fine - 0.5) * 2.0 + thatch_clump * (clumps - 0.5);
			// The eave: the bottom of the roof, a band above the storey line it sits on, ragged.
			float up = fract(v_mpos.y / max(thatch_storey, 0.01));
			float band = thatch_eave_band * (0.55 + 0.9 * vnoise(vec2(across * 22.0, 3.7 + seed_s * 9.0)));
			float eave = 1.0 - smoothstep(band * 0.4, band, up);
			base = straw_col * shade * mix(1.0, thatch_eave_dark, eave);
			amt = 0.0;
		} else if (own_tint || s < w.x + w.y) {
			amt = 0.0;  // the tiles' own fired terracotta
		} else if (s < w.x + w.y + w.z) {
			base = dark_tile * (0.5 + lum);
			amt = 0.0;
		}
	} else if (!is_roof && team_rank < 1.5) {
		amt *= ordinary_share;
	}
	ALBEDO = mix(base, tc, amt);
	ROUGHNESS = straw ? 0.95 : roughness;
	if (straw) {
		// Straw lies smooth over the roof's plane: the tiles' rounded rows are lit flat (their normal's
		// sway across the slope taken out), so no tile ridges show through the thatch.
		vec3 n = abs(v_mnormal.z) > abs(v_mnormal.x) ? vec3(0.0, v_mnormal.y, v_mnormal.z) : vec3(v_mnormal.x, v_mnormal.y, 0.0);
		if (length(n) > 0.05) NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(normalize(n), 0.0)).xyz);
	} else if (has_normal) NORMAL_MAP = texture(normal_tex, UV * uv_scale).rgb;
	// Dissolve right in front of the lens (Godot's pixel dither, as the other buildings do).
	float d = length(VERTEX);
	if (d < fade_solid) {
		float t = clamp((d - fade_gone) / max(fade_solid - fade_gone, 0.01), 0.0, 1.0);
		const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		if (t <= (BAYER[p.y * 4 + p.x] + 0.5) / 16.0) discard;
	}
}
