shader_type spatial;
render_mode cull_disabled;

// A house's painted arms hung flat (the castle's hangs, a town's arms panels, its walls' arms): the painting muted and
// darkened as the world wears every house colour (look.json team.banners, set by heraldry.gd hung()), so a kept town
// keeps a link to the painting, never a copy of it.

uniform sampler2D arms : source_color, filter_linear_mipmap;
uniform float worn_sat = 0.55;
uniform float worn_value = 0.85;

void fragment() {
	vec4 c = texture(arms, UV);
	ALBEDO = mix(vec3(dot(c.rgb, vec3(0.2126, 0.7152, 0.0722))), c.rgb, worn_sat) * worn_value;
	ROUGHNESS = 0.95;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
