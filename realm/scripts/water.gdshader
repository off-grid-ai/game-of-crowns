shader_type spatial;
render_mode blend_mix, specular_schlick_ggx, cull_disabled;

// Northern water: dark, cold and clear at the shore, deep blue-black further
// out, the sky caught in it at a glance, and a thin line of foam where it
// meets the land. Small rolling waves keep it alive.
uniform vec3 deep : source_color = vec3(0.03, 0.08, 0.13);
uniform vec3 shallow : source_color = vec3(0.09, 0.22, 0.24);
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float thick = max(VERTEX.z - view.z, 0.0);
	float water_depth = clamp(thick * 1.4, 0.0, 1.0);
	// Two sets of waves crossing, at different scales.
	vec2 p = world_pos.xz * 0.6 + vec2(TIME * 0.05, TIME * 0.03);
	vec2 q = world_pos.xz * 1.7 - vec2(TIME * 0.09, -TIME * 0.06);
	float wave = sin(p.x * 3.0 + sin(p.y * 2.0 + TIME * 0.6)) * cos(p.y * 2.7 - TIME * 0.4);
	float chop = sin(q.x * 4.0 + q.y * 3.0) * 0.5;
	NORMAL = normalize(NORMAL + vec3((wave + chop) * 0.05, 0.0, (wave - chop) * 0.045));
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(shallow, deep, water_depth);
	ALBEDO = mix(ALBEDO, vec3(0.35, 0.45, 0.55), fresnel * 0.5);
	ALPHA = mix(0.78, 0.97, water_depth);
	ROUGHNESS = 0.12;
	SPECULAR = 0.5;
	float foam = smoothstep(0.03, 0.0, thick) * (0.6 + 0.4 * sin(TIME * 1.5 + world_pos.x * 4.0));
	ALBEDO = mix(ALBEDO, vec3(0.82, 0.86, 0.86), foam * 0.5);
}
