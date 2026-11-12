// A town tree in the wind (towns.gd's yard, square and edge trees, KayKit's round crowns; Mac, round 7: the trees
// had no finesse): the crown leans and breathes with the realm's wind (weather_fx.gd's global `wind`, as the grass
// and the smoke do), more the higher it is above the tree's foot, the trunk's foot still. Its colour is the painted
// atlas (tools/paint_kaykit.sh: a sunlit top, a deep underside), matte, with a little light through the leaves.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float sway = 0.03; // lean at the top per (world unit of height)^2, at a fresh breeze
uniform float breathe = 0.015; // the crown swelling and settling a little, as leaves stir
uniform float near_gone = -1.0; // nearer the lens than this (world units) the tree is gone, whole from near_solid
uniform float near_solid = -1.0; // (camera.json near_fade; realistic.gd fade_near does the same for the kit's materials)
global uniform vec4 wind;

void vertex() {
	vec3 foot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max((MODEL_MATRIX * vec4(VERTEX, 1.0)).y - foot.y, 0.0);
	float strength = clamp(wind.w, 0.0, 1.0);
	float pace = 0.5 + strength * 1.2;
	float gust = sin(TIME * 0.9 * pace + dot(foot.xz, vec2(3.1, 2.3))) * 0.6 + sin(TIME * 2.1 * pace + foot.x * 5.0) * 0.2 + 0.3;
	vec2 dir = length(wind.xz) > 0.001 ? normalize(wind.xz) : vec2(0.8, 0.6);
	vec3 lean = vec3(dir.x, 0.0, dir.y) * gust * sway * (0.4 + strength * 1.6) * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(lean, 0.0)).xyz;
	VERTEX.xz *= 1.0 + breathe * sin(TIME * 1.7 + foot.z * 4.0) * clamp(h * 2.0, 0.0, 1.0);
}

void fragment() {
	if (near_solid > 0.0) {
		float f = clamp((length(VERTEX) - near_gone) / max(near_solid - near_gone, 0.001), 0.0, 1.0);
		float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.4375, 0.3125)) + 0.0625 * mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 4.0));
		if (f < dither) {
			discard;
		}
	}
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = c.rgb;
	ROUGHNESS = 0.85;
	BACKLIGHT = c.rgb * 0.35;
}
