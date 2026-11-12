// A regiment's banner (Total War's regiment banner, Shogun 2's way: the type painted on the cloth, strength
// under it; docs/research/army-and-town-rules.md section 1): one quad, pole and cloth together, turned about
// its pole to face the camera as heraldry.gd's flags are (banner_cloth.gdshader's turn). The cloth is the
// house's painted arms with its unit-type glyph (sword, spear, bow, horse, axe, engine) in the canton on the house
// colour (Total War: the faction's emblem on every regiment's banner, the type beside it); a house with no arms
// drawn, its colour with the glyph large; the army's standard the arms alone (or a crown); a swallowtail for a regiment, and up to five strength pips beneath: filled for
// the strength it holds, hollow for what it has lost. Selected, it brightens and wears a gold edge (the one
// accent); wavering, it flashes. The quad's pivot is the pole's foot; army.gd scales it so it keeps its
// size on screen from afar. Numbers in data/army.json banner.*.
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec4 field_color : source_color = vec4(0.72, 0.12, 0.12, 1.0);
uniform vec4 glyph_color : source_color = vec4(0.95, 0.92, 0.84, 1.0);
uniform vec4 pole_color : source_color = vec4(0.28, 0.21, 0.15, 1.0);
uniform vec4 glow_color : source_color = vec4(0.86, 0.71, 0.43, 1.0);  // theme.gd ACCENT, aged gold
uniform int glyph = 1;  // 0 none, 1 sword, 2 spear, 3 bow, 4 horse, 5 axe, 6 engine, 7 crown
uniform float strength = 1.0;  // 0..1, shown as pips
uniform int pips = 5;  // 0 shows none (the standard)
uniform float selected = 0.0;
uniform float waver = 0.0;
uniform bool swallow = true;
uniform bool use_arms = false;  // the house's painted banner on the cloth
uniform bool canton = false;  // with the arms: the glyph in a square of house colour at the hoist's top (a regiment)
uniform float canton_size = 0.46;  // the canton's side, share of the cloth's height
uniform sampler2D arms : source_color, filter_linear_mipmap;
uniform float phase = 0.0;  // this flag's place in the wind
uniform float span = 0.35;  // the quad's width in world units
uniform float aspect = 1.6;  // the cloth's width over its height (world)
uniform float pole_w = 0.04;  // the pole's share of the quad's width
uniform vec2 flag_v = vec2(0.03, 0.40);  // the cloth's top and bottom, down the quad (UV.y)
uniform float pip_v = 0.47;  // the pips' row, down the quad

varying float ripple;

void vertex() {
	float t = clamp((UV.x - pole_w) / (1.0 - pole_w), 0.0, 1.0);  // 0 at the pole, 1 at the free edge
	float a = TIME * 2.3 + UV.x * 7.0 - UV.y * 2.0 + phase;
	float b = TIME * 4.1 + UV.x * 12.0 + phase * 1.7;
	float wave = sin(a) * 0.06 + sin(b) * 0.02;
	VERTEX.z += wave * t * span;
	ripple = 0.86 + 0.14 * cos(a) * t;
	NORMAL = normalize(vec3(-(cos(a) * 0.4 + cos(b) * 0.24) * t, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	return length(pa - ba * clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0));
}

// How much of the glyph covers q (the glyph's square, 0..1 each way, y down); aa: one pixel in q.
float glyph_mask(vec2 q, int g, float aa) {
	float d = 1.0;
	if (g == 1) {  // sword: blade, crossguard, pommel
		d = min(seg(q, vec2(0.5, 0.12), vec2(0.5, 0.68)) - 0.05, seg(q, vec2(0.32, 0.66), vec2(0.68, 0.66)) - 0.04);
		d = min(d, seg(q, vec2(0.5, 0.66), vec2(0.5, 0.84)) - 0.035);
		d = min(d, length(q - vec2(0.5, 0.88)) - 0.06);
	} else if (g == 2) {  // spear: shaft and a leaf head
		d = seg(q, vec2(0.5, 0.3), vec2(0.5, 0.92)) - 0.03;
		d = min(d, (abs(q.x - 0.5) / 0.1 + abs(q.y - 0.24) / 0.15 - 1.0) * 0.08);
	} else if (g == 3) {  // bow: a drawn arc, its string and an arrow
		vec2 c = vec2(0.72, 0.5);
		float ring = abs(length(q - c) - 0.36) - 0.04;
		d = q.x < 0.54 ? ring : 1.0;
		d = min(d, seg(q, vec2(0.54, 0.19), vec2(0.54, 0.81)) - 0.015);
		d = min(d, seg(q, vec2(0.18, 0.5), vec2(0.84, 0.5)) - 0.025);
		d = min(d, (abs(q.x - 0.15) / 0.09 + abs(q.y - 0.5) / 0.07 - 1.0) * 0.05);
	} else if (g == 4) {  // horse: a horseshoe, open below
		float ring = abs(length(q - vec2(0.5, 0.46)) - 0.27) - 0.075;
		d = (q.y > 0.6 && abs(q.x - 0.5) < 0.17) ? 1.0 : ring;
	} else if (g == 5) {  // axe: haft and a bearded blade
		d = seg(q, vec2(0.42, 0.12), vec2(0.42, 0.9)) - 0.035;
		d = min(d, q.x > 0.42 ? length((q - vec2(0.42, 0.32)) * vec2(1.0, 0.8)) - 0.26 : 1.0);
	} else if (g == 6) {  // engine: a wheel with its spokes
		d = abs(length(q - vec2(0.5)) - 0.3) - 0.05;
		d = min(d, seg(q, vec2(0.29, 0.29), vec2(0.71, 0.71)) - 0.03);
		d = min(d, seg(q, vec2(0.29, 0.71), vec2(0.71, 0.29)) - 0.03);
		d = min(d, length(q - vec2(0.5)) - 0.08);
	} else if (g == 7) {  // crown: a band and three points
		d = max(abs(q.x - 0.5) - 0.26, abs(q.y - 0.68) - 0.07);
		d = min(d, seg(q, vec2(0.27, 0.62), vec2(0.22, 0.3)) - 0.04);
		d = min(d, seg(q, vec2(0.5, 0.62), vec2(0.5, 0.22)) - 0.04);
		d = min(d, seg(q, vec2(0.73, 0.62), vec2(0.78, 0.3)) - 0.04);
		d = min(d, min(length(q - vec2(0.22, 0.27)), min(length(q - vec2(0.5, 0.19)), length(q - vec2(0.78, 0.27)))) - 0.055);
	}
	return 1.0 - smoothstep(-aa, aa, d);
}

void fragment() {
	vec2 uv = UV;
	float fx = (uv.x - pole_w) / (1.0 - pole_w);
	float fy = (uv.y - flag_v.x) / (flag_v.y - flag_v.x);
	bool tail = swallow && fx > 0.8 && abs(fy - 0.5) < (fx - 0.8) * 1.7;
	bool cloth = fx >= 0.0 && fx <= 1.0 && fy >= 0.0 && fy <= 1.0 && !tail;
	float edge = 0.05;  // the gold edge's width, share of the cloth's height
	bool rim = !cloth && fx >= -edge / aspect && fx <= 1.0 + edge / aspect && fy >= -edge && fy <= 1.0 + edge && !(swallow && fx > 0.8 + edge && abs(fy - 0.5) < (fx - 0.8) * 1.7 - edge);
	bool pole = uv.x < pole_w && uv.y > flag_v.x - 0.025;
	bool finial = uv.x < pole_w * 2.2 && length(vec2(uv.x / pole_w * 0.5 - 0.5, (uv.y - (flag_v.x - 0.03)) / 0.02)) < 1.0;
	vec3 col = vec3(0.0);
	float shown = 0.0;
	if (cloth) {
		vec3 field = field_color.rgb;
		if (use_arms) {
			field = texture(arms, vec2(fx, fy)).rgb;
			vec2 c = vec2(fx * aspect, fy) / canton_size;  // the canton's square, 0..1 each way
			if (canton && c.x <= 1.0 && c.y <= 1.0) {
				vec3 ground = field_color.rgb * ((c.x > 0.92 || c.y > 0.92) ? 0.72 : 1.0);
				vec2 q = (c - 0.5) / 0.8 + 0.5;
				float aa = max(fwidth(q.x) * 0.8, 0.0001);
				float lum = dot(field_color.rgb, vec3(0.3, 0.59, 0.11));
				field = mix(ground, lum > 0.62 ? vec3(0.12, 0.09, 0.07) : glyph_color.rgb, glyph_mask(q, glyph, aa));
			}
		} else {
			float border = (fx < 0.035 || fy < 0.06 || fy > 0.94) ? 0.72 : 1.0;
			field *= border;
			// The glyph in a square on the cloth's near part (clear of the tail), light on dark or dark on light.
			float side = 0.78;
			vec2 q = vec2((fx - 0.4) * aspect / side + 0.5, (fy - 0.5) / side + 0.5);
			float aa = max(fwidth(q.x) * 0.8, 0.0001);
			float on = glyph_mask(q, glyph, aa);
			float lum = dot(field_color.rgb, vec3(0.3, 0.59, 0.11));
			vec3 ink = lum > 0.62 ? vec3(0.12, 0.09, 0.07) : glyph_color.rgb;
			field = mix(field, ink, on);
		}
		field = mix(field, vec3(1.0), waver * (0.5 + 0.5 * sin(TIME * 9.0)) * 0.45);
		col = mix(field, field * 1.25 + vec3(0.05), selected) * ripple;
		shown = 1.0;
	} else if (rim && selected > 0.01) {
		col = glow_color.rgb;
		shown = selected;
	} else if (pole || finial) {
		col = finial ? glow_color.rgb * 0.8 : pole_color.rgb;
		shown = 1.0;
	} else if (pips > 0) {
		// The strength pips: a row under the cloth, filled for what the regiment holds.
		vec2 w = vec2(fx * aspect, (uv.y - pip_v) / (flag_v.y - flag_v.x));  // in cloth heights
		float step_x = aspect * 0.8 / float(pips);
		float i = floor(w.x / step_x);
		if (i >= 0.0 && i < float(pips)) {
			float d = length(vec2(w.x - (i + 0.5) * step_x, w.y));
			float r = min(step_x * 0.3, 0.09);
			bool full = i < ceil(strength * float(pips) - 0.001);
			if (full ? d < r : abs(d - r * 0.8) < r * 0.25) {
				col = full ? glyph_color.rgb : glyph_color.rgb * 0.7;
				shown = 1.0;
			}
		}
	}
	if (shown < 0.01) {
		discard;
	}
	ALBEDO = col;
	EMISSION = (cloth || rim) ? col * selected * 0.35 + glow_color.rgb * (rim ? 1.0 : 0.0) * selected * 0.6 : vec3(0.0);
	ROUGHNESS = 0.9;
}
