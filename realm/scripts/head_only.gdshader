shader_type spatial;
// Draws only the head and neck of the base character, so it can wear the
// Fantasy Outfits (which supply the clothed body) without poking through them.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform int head_bone = -1;
uniform int neck_bone = -1;

varying float keep;

void vertex() {
	keep = 0.0;
	for (int i = 0; i < 4; i++) {
		int b = int(BONE_INDICES[i]);
		if (b == head_bone || b == neck_bone) {
			keep += BONE_WEIGHTS[i];
		}
	}
}

void fragment() {
	if (keep < 0.5) {
		discard;
	}
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = 0.75;
}
