shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// Drawn over a mesh as a material overlay: snow settles on whatever faces up.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

varying float up;
varying vec3 world;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;  // scaled models would shrink it otherwise
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Patchiness fixed to the world, not the view: the camera's least movement
	// must not reshuffle which bits of a roof are snowy.
	float n = fract(sin(dot(floor(world.xz * 40.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = vec3(0.84, 0.86, 0.9);  // snow in shade and daylight, not paper white
	ROUGHNESS = 0.85;
	// Settles on what faces the sky, thinner on steep roofs, patchy at the edges.
	ALPHA = smoothstep(0.5, 0.9, up) * amount * (0.6 + n * 0.4);
}
