shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// Drawn over a mesh as a material overlay: snow settles on whatever faces up.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

varying float up;
varying vec3 world;
varying float above;  // how far above the model's own base this point stands

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;  // scaled models would shrink it otherwise
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	above = world.y - MODEL_MATRIX[3].y;
}

void fragment() {
	// Patchiness fixed to the world, in soft patches a couple of metres across:
	// view-space or fine cells sparkled as the camera eased.
	vec2 q = world.xz * 2.5;
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float n = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
	ALBEDO = vec3(0.84, 0.86, 0.9);  // snow in shade and daylight, not paper white
	ROUGHNESS = 0.85;
	// Settles on what faces the sky, thinner on steep roofs, patchy at the edges.
	// Not on a model's own floor (a house's base plate, a doorstep): those sat
	// as bright white slabs. The ground has its own snow; roofs and boughs
	// stand well above their base.
	float lifted = smoothstep(0.04, 0.12, above);
	ALPHA = smoothstep(0.5, 0.9, up) * amount * (0.6 + n * 0.4) * lifted;
}
