// Standing grain seen from roof height and beyond (countryside.gd sow; batch 9: from d6 to d30 a wheat field read
// as a flat ochre slab, its modelled stalks too fine to show and gone past CROP_REACH). Shell texturing, the old
// grass and fur trick: the field is drawn as a stack of see-through layers over its own ground, each cutting
// away all but the stalks that reach its height, so from above and oblique the field has depth, rows and ears.
// The tips lean in the one wind (the global `wind`, as the grass and the stalks do) and a sheen runs across the
// ears in waves, the way a wheat field moves in a breeze. Layer: COLOR.a (0 the ground, 1 the ears). UV: the
// field's own metres-in-game-units (x along the rows, y across them).
shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform vec3 ear : source_color = vec3(0.86, 0.68, 0.32);   // the ripe ear
uniform vec3 stem : source_color = vec3(0.55, 0.42, 0.2);   // low in the stand, in its own shade
uniform vec3 soil : source_color = vec3(0.3, 0.23, 0.15);   // between the rows at the foot
uniform float row_gap = 0.03;    // between rows (game units), as the sown stalks
uniform float step_along = 0.014; // between stalks along a row
uniform float stalk = 0.32;      // a stalk's width, as a share of its cell
uniform float thin = 0.45;       // how many stalks drop out toward the top (the stand thins to its ears)
uniform float lean = 0.06;       // the tips' lean in a fresh breeze (game units)
uniform float wave_len = 1.6;    // the sheen's wavelength across the field (game units)
uniform float wave_speed = 0.9;
uniform float sheen = 0.22;      // how much brighter the ears are under a passing wave
uniform float far_px = 0.7;      // when a stalk's cell is under 1/far_px pixels across, the field is drawn as a whole stand (no shimmer)
instance uniform vec4 tint : source_color = vec4(1.0);  // the field's stage (green, yellowing, gold, stubble)
global uniform vec4 wind;
global uniform float snow;
varying float layer;
varying vec3 world;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	layer = COLOR.a;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world = w;
	float strength = clamp(wind.w, 0.0, 1.0);
	vec2 dir = length(wind.xz) > 0.001 ? normalize(wind.xz) : vec2(0.8, 0.6);
	float gust = sin(TIME * (1.1 + strength) + dot(w.xz, dir) * 2.4) * 0.6 + 0.5;
	// Lean in world space, turned back into the field's own frame.
	vec3 shove = vec3(dir.x, 0.0, dir.y) * gust * lean * (0.4 + strength * 1.6) * layer * layer;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(shove, 0.0)).xyz;
}

void fragment() {
	if (snow > 0.5) {
		discard;
	}
	vec2 cell = vec2(UV.x / step_along, UV.y / row_gap);
	vec2 dir = length(wind.xz) > 0.001 ? normalize(wind.xz) : vec2(0.8, 0.6);
	float wave = 0.5 + 0.5 * sin(dot(world.xz, dir) * 6.2832 / wave_len - TIME * wave_speed * (0.6 + wind.w));
	// Far off a stalk is less than a pixel: cutting them out would only shimmer. Then the top layer alone is
	// drawn, the stand's own colour with its drill lines and the wind's sheen.
	float px = max(fwidth(cell.x), fwidth(cell.y));
	if (px > far_px) {
		if (layer < 0.99) {
			discard;
		}
		float drills = 0.9 + 0.1 * sin(UV.y / row_gap * 0.5);
		vec3 far_c = mix(stem, ear, 0.62) * drills * (1.0 + sheen * wave);
		ALBEDO = far_c * tint.rgb;
		ROUGHNESS = 0.9;
	} else {
	vec2 id = floor(cell);
	vec2 f = fract(cell) - 0.5;
	float h = hash(id);
	// Each stalk stands a little off its cell's middle and has its own height; the stand thins near the top.
	vec2 off = vec2(hash(id + 7.3), hash(id + 3.1)) - 0.5;
	float r = length((f - off * 0.4) * vec2(1.0, step_along / row_gap));
	float tall = 1.0 - thin * h;
	if (layer > 0.02 && (r > stalk * 0.5 * (1.0 - 0.35 * layer) || layer > tall)) {
		discard;
	}
	vec3 c = mix(stem, ear, smoothstep(0.35, 0.95, layer / tall));
	c = layer <= 0.02 ? mix(soil, stem * 0.8, 0.35) : c;
	c *= 0.82 + 0.18 * h;  // no two stalks the same
	c *= 1.0 + sheen * wave * layer;
	ALBEDO = c * tint.rgb;
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.3 * layer;
	}
}
