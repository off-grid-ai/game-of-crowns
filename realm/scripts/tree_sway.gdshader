// A town tree in the wind (towns.gd's yard, square and edge trees, KayKit's round crowns; Mac, round 7: the trees
// had no finesse; round 8: they read as smooth lime lollipops). The crown leans and breathes with the realm's wind
// (weather_fx.gd's global `wind`, as the grass and the smoke do), more the higher it is above the tree's foot. Its
// leaves are painted, not textured: four greens from 01-town (a deep olive in the crown's shade, a mid green, a warm
// yellow-green, a sunlit top), chosen by how high on the crown, how far it faces the sky and leaf-cluster noise in
// the world (so no two trees and no two sides match), and the round crown's surface is lumped by the same clusters
// so its outline breaks up. The trunk keeps its painted atlas colour.
shader_type spatial;
render_mode cull_disabled; // leaf cards are seen from both sides

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float sway = 0.03; // lean at the top per (world unit of height)^2, at a fresh breeze
uniform float breathe = 0.015; // the crown swelling and settling a little, as leaves stir
uniform vec3 leaf_deep : source_color = vec3(0.17, 0.24, 0.10);
uniform vec3 leaf_mid : source_color = vec3(0.30, 0.42, 0.15);
uniform vec3 leaf_warm : source_color = vec3(0.52, 0.60, 0.22);
uniform vec3 leaf_sun : source_color = vec3(0.74, 0.74, 0.34);
uniform float clusters = 7.0; // leaf clusters per world unit
uniform float lump = 0.025; // how far a cluster stands out of the crown (world units)
uniform float leaf_mix = 1.0; // 0: the atlas's own green, 1: the painted greens
uniform float alpha_cut = 0.0; // > 0: leaf cards cut out where their texture is clear (a leaf-card tree's leaves)
uniform float near_gone = -1.0; // nearer the lens than this (world units) the tree is gone, whole from near_solid
uniform float near_solid = -1.0; // (camera.json near_fade; realistic.gd fade_near does the same for the kit's materials)
global uniform vec4 wind;

varying float leaf;
varying vec3 wpos;
varying float up;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0.0, 0.0, 0.0)), hash(i + vec3(1.0, 0.0, 0.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 0.0)), hash(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash(i + vec3(0.0, 0.0, 1.0)), hash(i + vec3(1.0, 0.0, 1.0)), f.x), mix(hash(i + vec3(0.0, 1.0, 1.0)), hash(i + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

void vertex() {
	// KayKit's atlas: the leaves' swatch is the top-left eighth across, quarter down (lit at its top).
	leaf = (UV.x < 0.125 && UV.y < 0.25) ? 1.0 : 0.0;
	up = leaf > 0.5 ? clamp(1.0 - UV.y / 0.25, 0.0, 1.0) : 0.0;
	vec3 foot = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(w.y - foot.y, 0.0);
	// The crown's surface lumped by its leaf clusters, so a ball reads as foliage.
	if (leaf > 0.5) {
		vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
		float n = noise(w * clusters) * 0.65 + noise(w * clusters * 2.3 + 7.0) * 0.35;
		VERTEX += (inverse(MODEL_MATRIX) * vec4(wn * (n - 0.45) * 2.0 * lump, 0.0)).xyz;
	}
	float strength = clamp(wind.w, 0.0, 1.0);
	float pace = 0.5 + strength * 1.2;
	float gust = sin(TIME * 0.9 * pace + dot(foot.xz, vec2(3.1, 2.3))) * 0.6 + sin(TIME * 2.1 * pace + foot.x * 5.0) * 0.2 + 0.3;
	vec2 dir = length(wind.xz) > 0.001 ? normalize(wind.xz) : vec2(0.8, 0.6);
	vec3 lean = vec3(dir.x, 0.0, dir.y) * gust * sway * (0.4 + strength * 1.6) * h * h;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(lean, 0.0)).xyz;
	VERTEX.xz *= 1.0 + breathe * sin(TIME * 1.7 + foot.z * 4.0) * clamp(h * 2.0, 0.0, 1.0);
	wpos = w;
}

void fragment() {
	if (near_solid > 0.0) {
		float f = clamp((length(VERTEX) - near_gone) / max(near_solid - near_gone, 0.001), 0.0, 1.0);
		float dither = fract(dot(floor(FRAGCOORD.xy), vec2(0.4375, 0.3125)) + 0.0625 * mod(floor(FRAGCOORD.x) + floor(FRAGCOORD.y), 4.0));
		if (f < dither) {
			discard;
		}
	}
	vec4 c = texture(albedo_tex, UV) * albedo_color;
	vec3 col = c.rgb;
	if (leaf > 0.5) {
		float sky = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
		float n = noise(wpos * clusters * 1.7) * 0.6 + noise(wpos * clusters * 4.1 + 3.0) * 0.4;
		float t = clamp(up * 0.45 + sky * 0.3 + (n - 0.5) * 0.7 + 0.12, 0.0, 1.0);
		vec3 painted = t < 0.33 ? mix(leaf_deep, leaf_mid, t / 0.33) : (t < 0.66 ? mix(leaf_mid, leaf_warm, (t - 0.33) / 0.33) : mix(leaf_warm, leaf_sun, (t - 0.66) / 0.34));
		col = mix(col, painted, leaf_mix);
	}
	ALBEDO = col;
	ALPHA = alpha_cut > 0.0 ? c.a : 1.0;
	ALPHA_SCISSOR_THRESHOLD = max(alpha_cut, 0.001);
	ROUGHNESS = 0.85;
	BACKLIGHT = col * 0.3;
}
