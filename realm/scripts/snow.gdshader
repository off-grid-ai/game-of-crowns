shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// Drawn over a mesh as a material overlay: snow settles on whatever faces up.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

varying float up;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;  // scaled models would shrink it otherwise
}

void fragment() {
	float n = fract(sin(dot(floor(VERTEX.xz * 40.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = vec3(0.84, 0.86, 0.9);  // snow in shade and daylight, not paper white
	ROUGHNESS = 0.85;
	// Settles on what faces the sky, thinner on steep roofs, patchy at the edges.
	ALPHA = smoothstep(0.5, 0.9, up) * amount * (0.6 + n * 0.4);
}
