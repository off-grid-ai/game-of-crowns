shader_type spatial;
render_mode diffuse_burley;

// Ground layers (Poly Haven, CC0). Weights come from the mesh:
// COLOR = grass, dirt, sand, snow; CUSTOM0.xy = rock, forest floor.
uniform sampler2D grass_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_a : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D forest_n : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile_scale = 0.09;
// Colour grading per layer: the gallery look is lush green, warm earth, deep shadow.
uniform vec3 grass_tint : source_color = vec3(0.62, 0.86, 0.38);
uniform vec3 dirt_tint : source_color = vec3(0.95, 0.82, 0.66);
uniform vec3 forest_tint : source_color = vec3(0.55, 0.72, 0.4);

// The realm map: each house's land tinted in its colour, with borders where
// it meets another house's, red where the two are at war. realm_mix fades it
// in as the camera pulls back. realm_tex: rgb = house colour, a = owner id / 64
// (0 = nobody); war_tex: r = 1 where a tile's owner is at war with a neighbour.
uniform sampler2D realm_tex : filter_nearest;
uniform sampler2D war_tex : filter_nearest;
uniform vec2 realm_size = vec2(1.0);
uniform float tile_size = 4.0;
uniform float realm_mix = 0.0;

varying vec3 wpos;
varying vec3 wnrm;
varying vec4 w_a;
varying vec2 w_b;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	w_a = COLOR;
	w_b = CUSTOM0.xy;
}

// Two scales blended by a slow wobble to hide texture repetition.
vec4 layer(sampler2D tex, vec2 uv, float mixv) {
	return mix(texture(tex, uv), texture(tex, uv * 0.27 + vec2(0.37, 0.71)), mixv);
}

void fragment() {
	vec2 uv = wpos.xz * tile_scale;
	float mixv = 0.35 + 0.25 * sin(wpos.x * 0.05) * cos(wpos.z * 0.045);
	float slope = 1.0 - clamp(wnrm.y, 0.0, 1.0);
	float rock = w_b.x + smoothstep(0.32, 0.55, slope) * 1.5;
	float snow = w_a.w * (1.0 - smoothstep(0.5, 0.75, slope));
	float grass = w_a.x * (1.0 - smoothstep(0.3, 0.5, slope));
	float wsum = grass + w_a.y + w_a.z + snow + rock + w_b.y + 0.0001;
	float g = grass / wsum, d = w_a.y / wsum, s = w_a.z / wsum, n = snow / wsum, r = rock / wsum, f = w_b.y / wsum;
	vec3 albedo = layer(grass_a, uv, mixv).rgb * grass_tint * g + layer(dirt_a, uv, mixv).rgb * dirt_tint * d + layer(sand_a, uv, mixv).rgb * s
		+ layer(snow_a, uv, mixv).rgb * n + layer(rock_a, uv * 0.6, mixv).rgb * r + layer(forest_a, uv * 1.4, mixv).rgb * forest_tint * f;
	vec3 nrm = layer(grass_n, uv, mixv).rgb * g + layer(dirt_n, uv, mixv).rgb * d + layer(sand_n, uv, mixv).rgb * s
		+ layer(snow_n, uv, mixv).rgb * n + layer(rock_n, uv * 0.6, mixv).rgb * r + layer(forest_n, uv * 1.4, mixv).rgb * f;
	if (realm_mix > 0.001) {
		vec2 t = wpos.xz / tile_size;
		ivec2 c = clamp(ivec2(floor(t)), ivec2(0), ivec2(realm_size) - 1);
		vec4 own = texelFetch(realm_tex, c, 0);
		vec2 f = fract(t);
		float edge = 0.0;
		float war = 0.0;
		ivec2 dirs[4] = {ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1)};
		float near[4] = {f.x, 1.0 - f.x, f.y, 1.0 - f.y};
		for (int i = 0; i < 4; i++) {
			ivec2 nc = clamp(c + dirs[i], ivec2(0), ivec2(realm_size) - 1);
			vec4 other = texelFetch(realm_tex, nc, 0);
			if (abs(other.a - own.a) > 0.001) {
				bool at_war = texelFetch(war_tex, c, 0).r > 0.5 && texelFetch(war_tex, nc, 0).r > 0.5 && other.a > 0.0 && own.a > 0.0;
				// War fronts are drawn thicker than peaceful borders.
				if (near[i] < (at_war ? 0.16 : 0.07)) {
					edge = 1.0;
					war = max(war, at_war ? 1.0 : 0.0);
				}
			}
		}
		if (own.a > 0.0) {
			albedo = mix(albedo, own.rgb, 0.38 * realm_mix);
		}
		vec3 line = war > 0.5 ? vec3(0.85, 0.12, 0.1) : (own.a > 0.0 ? own.rgb * 0.45 : vec3(0.1));
		albedo = mix(albedo, line, edge * realm_mix * 0.9);
	}
	ALBEDO = albedo;
	NORMAL_MAP = nrm;
	NORMAL_MAP_DEPTH = 1.2;
	ROUGHNESS = mix(0.95, 0.6, n);
}
