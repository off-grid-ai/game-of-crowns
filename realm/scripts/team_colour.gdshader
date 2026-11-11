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

void fragment() {
	vec4 c = albedo;
	if (has_albedo_tex) c *= texture(albedo_tex, UV);
	// The house's colour at the material's own brightness: the tiles' shading stays, the hue is the house's.
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float tl = max(dot(team_color.rgb, vec3(0.299, 0.587, 0.114)), 0.05);
	vec3 tc = clamp(team_color.rgb * lum / tl * 1.05, 0.0, 1.0);
	ALBEDO = mix(c.rgb, tc, team_amount * team_color.a);
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
