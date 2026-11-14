shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley;

// The weather on what stands (weather_fx.gd puts it as a material overlay on the towns' building batches,
// never on people): rain darkens roofs and walls and makes them glint, snow settles on whatever faces up.
// Snow: `amount` (the season's, weather_fx.gd). Wet: the one wetness fact (global `wet`, 0 dry .. 1 soaked).
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float dark = 0.34;  // how much a soaked roof darkens
uniform float sheen = 0.5;  // how glossy a soaked roof gets (its roughness when soaked: never a mirror)
uniform float spec = 0.4;  // a soaked roof's specular (batch 9: at 0.7 the sun blew it out to white)
uniform vec3 snow_col : source_color = vec3(0.66, 0.7, 0.79);  // the one snow colour (ground.json winter.snow; g24 raid: 0.9 blew out white)
global uniform float wet;

varying float up;
varying vec3 world;
varying float above;  // how far above the model's own base this point stands

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

void vertex() {
	up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;  // scaled models would shrink it otherwise
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	above = world.y - MODEL_MATRIX[3].y;
}

void fragment() {
	// Patchiness fixed to the world, soft patches a couple of metres across over a finer grain: view-space or
	// fine cells sparkled as the camera eased; one coarse layer read as flat grey sheets (terrain.gd's note).
	float n = cell(world.xz * 2.5) * 0.65 + cell(world.xz * 9.0 + 3.7) * 0.35;
	// Not on a model's own floor (a house's base plate, a doorstep): those sat as bright white slabs.
	float lifted = smoothstep(0.04, 0.12, above);
	// Snow: on what faces the sky, thinner on steep roofs, broken into patches that join as it deepens.
	float facing = smoothstep(0.45, 0.85, up);
	float snow = facing * lifted * smoothstep(0.55, 0.85, n + amount * 0.75 - 0.25) * clamp(amount * 1.4, 0.0, 1.0);
	// Wet: everything above the ground darker, the roofs most, and glinting.
	float soak = clamp(wet, 0.0, 1.0) * lifted * mix(0.55, 1.0, smoothstep(0.2, 0.7, up)) * (0.85 + n * 0.3);
	float wet_a = soak * dark;
	ALBEDO = mix(vec3(0.03, 0.03, 0.035), snow_col, step(wet_a, snow));
	ROUGHNESS = snow > wet_a ? 0.85 : mix(1.0, sheen, soak);
	SPECULAR = snow > wet_a ? 0.3 : mix(0.3, spec, soak);
	ALPHA = max(snow, wet_a);
}
