// Snow on the trees' leaves (batch 9 review: snow drawn as flat white cards across the crowns): a second pass
// on a leaf material (terrain.gd's season pass sets it as the leaves' next_pass in a snowy season), cut by the
// leaf's own texture so it lies only on the leaves, and only on what faces the sky: the tops of the crowns,
// in patches, never a sheet. How much: the season's one snow fact (the global `snow`, terrain.gd).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut = 0.5;
uniform vec3 snow_col : source_color = vec3(0.66, 0.7, 0.79);  // the one snow colour (ground.json winter.snow)
uniform float cover = 0.8;  // how white the snowiest leaf gets (data/weather.json leaves.cover)
global uniform float snow;

varying float up;
varying vec3 world;

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float cell(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = fract(sin(dot(i, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(i + vec2(1.0, 0.0), vec2(12.9898, 78.233))) * 43758.5453);
	float c = fract(sin(dot(i + vec2(0.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	float d = fract(sin(dot(i + vec2(1.0, 1.0), vec2(12.9898, 78.233))) * 43758.5453);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	float leaf = texture(albedo_tex, UV).a;
	if (leaf < alpha_cut || snow <= 0.001) {
		discard;
	}
	float facing = smoothstep(0.2, 0.75, up);
	float n = cell(world.xz * 3.0 + world.y * 1.7) * 0.6 + cell(world.xz * 11.0) * 0.4;
	float lie = facing * smoothstep(0.35, 0.75, n + snow * 0.6 - 0.15) * clamp(snow * 1.6, 0.0, 1.0);
	ALBEDO = snow_col;
	ROUGHNESS = 0.9;
	SPECULAR = 0.2;
	ALPHA = lie * cover;
}
