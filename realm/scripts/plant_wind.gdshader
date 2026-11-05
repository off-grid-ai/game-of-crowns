// Low plants in the wind (countryside.gd's grass, clover and flowers): each
// bends from its root by its height, in slow gusts that roll across the land,
// and the low sun shines through the blades.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cut = 0.5;
uniform float sway = 0.35; // bend at the tip, per metre of height
uniform vec2 wind = vec2(0.8, 0.6);

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float gust = sin(TIME * 1.3 + dot(w.xz, vec2(3.1, 2.3))) * 0.6 + sin(TIME * 2.9 + w.x * 7.0) * 0.25 + 0.4;
	float h = max(VERTEX.y, 0.0);
	VERTEX.xz += normalize(wind) * gust * sway * h * h;
}

void fragment() {
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.9;
	BACKLIGHT = c.rgb * 0.5;
}
