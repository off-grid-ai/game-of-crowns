// Low plants in the wind (countryside.gd's grass, clover and flowers): each
// bends from its root by its height, in slow gusts that roll across the land,
// and the low sun shines through the blades. The wind is the one shared fact
// (weather_fx.gd's global `wind`: x, z where it blows, w its strength): a calm
// day stirs the grass, a storm lays it over, always the way the smoke leans.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float sway = 0.35; // bend at the tip, per metre of height, at a fresh breeze
// Under snow (the season's one fact, the global `snow`, terrain.gd; batch 9: summer tufts and red flowers
// poked up through it): this share of the plants is buried outright, the rest sink low and go straw-brown.
// A flower (bury 1.0) is all gone under it. countryside.gd sets bury from data/weather.json plants.
uniform float bury = 0.6;
uniform vec3 straw : source_color = vec3(0.55, 0.47, 0.33);
global uniform vec4 wind;
global uniform float snow;
varying float under;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float strength = clamp(wind.w, 0.0, 1.0);
	float pace = 0.7 + strength * 1.6;  // gusts come quicker as it blows harder
	float gust = sin(TIME * 1.3 * pace + dot(w.xz, vec2(3.1, 2.3))) * 0.6 + sin(TIME * 2.9 * pace + w.x * 7.0) * 0.25 + 0.4;
	float h = max(VERTEX.y, 0.0);
	vec2 dir = length(wind.xz) > 0.001 ? normalize(wind.xz) : vec2(0.8, 0.6);
	VERTEX.xz += dir * gust * sway * (0.35 + strength * 2.2) * h * h;
	// Snow: s 0 bare .. 1 deep. A plant whose own hash is under the buried share is pressed to nothing;
	// the rest stand shorter as it deepens.
	float s = clamp(snow * 2.0, 0.0, 1.0);
	float own = fract(sin(dot(w.xz, vec2(41.3, 17.9))) * 43758.5453);
	if (own < bury * s) {
		VERTEX = vec3(0.0);
	}
	VERTEX.y *= 1.0 - 0.55 * s;
	under = s;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = mix(c.rgb, straw * (0.7 + 0.3 * dot(c.rgb, vec3(0.33))), under * 0.85);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	BACKLIGHT = c.rgb * 0.5 * (1.0 - under);
}
