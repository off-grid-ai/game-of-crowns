shader_type canvas_item;
// Frosted glass: the world behind a panel, blurred and darkened, under the
// panel's own tint and border.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur = 3.2;
uniform float darken = 0.72;

void fragment() {
	vec4 own = COLOR;
	if (own.a < 0.01) {
		discard;
	}
	vec3 behind = textureLod(screen_tex, SCREEN_UV, blur).rgb * darken;
	COLOR = vec4(mix(behind, own.rgb, own.a), 1.0);
}
