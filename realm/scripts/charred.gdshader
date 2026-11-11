// A burnt house (fire.gd): its own materials blackened with soot and roughened, part of its roof fallen in
// (a ragged hole above `cut`, a share of its height), embers glowing in the char while it still burns.
// After the charring pass in ruins.gd (albedo times a char colour), as a shader so one house's roof can go.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D noise_texture : repeat_enable;  // seamless noise (Godot's NoiseTexture2D)
uniform vec3 soot : source_color = vec3(0.05, 0.043, 0.04);
uniform float char_amount : hint_range(0.0, 1.0) = 0.82;
uniform float hole = 0.42;  // above the cut, this share of the roof is gone
uniform float noise_scale = 4.0;  // per mesh unit
uniform vec3 ember : source_color = vec3(1.0, 0.36, 0.06);

instance uniform float glow = 0.0;  // embers in the char: 1 while it burns, out after
instance uniform float cut = 1.0;  // the share of its height above which the roof has fallen in (1: whole)
instance uniform float lo = 0.0;  // the mesh's own lowest and highest point (its AABB), for `cut`
instance uniform float hi = 1.0;

varying vec3 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 base = albedo;
	if (has_albedo_tex) {
		base *= texture(albedo_tex, UV);
	}
	float n = texture(noise_texture, local.xz * noise_scale + vec2(local.y * 1.7, 0.0)).r;
	float h = (local.y - lo) / max(hi - lo, 0.0001);
	if (h > cut && n > 1.0 - hole) {
		discard;
	}
	// Soot heaviest high up (where the flames licked), the char never quite even.
	float sooty = clamp(char_amount * (0.7 + 0.6 * n) * mix(0.75, 1.1, clamp(h, 0.0, 1.0)), 0.0, 1.0);
	ALBEDO = mix(base.rgb, soot, sooty);
	ROUGHNESS = 1.0;
	SPECULAR = 0.1;
	EMISSION = ember * smoothstep(0.6, 0.78, n) * glow * 2.5;
}
