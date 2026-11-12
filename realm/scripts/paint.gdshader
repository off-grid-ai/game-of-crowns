// A painterly pass over the world (paint.gd; --paint=kuwahara): the Generalized Kuwahara filter, which turns flat
// texture and hard kit edges into soft brush-like patches while holding the edges between them.
//
// Ported from "Generalized Kuwahara" by Firerabbit on Godot Shaders (https://godotshaders.com/shader/generalized-kuwahara/),
// itself a Godot 4 port of Acerola's Unity implementation (https://github.com/GarrettGunnell/Post-Processing).
// MIT License: Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction, including without
// limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the
// Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of
// the Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
//
// Our changes: integer literals in max() made float (Godot's strict typing), a `strength` mix back toward the
// unfiltered frame, the knobs named for look.json paint.
shader_type canvas_item;

const int _N = 8;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;

uniform int radius : hint_range(1, 10, 1) = 3;  // the brush: its half-width in pixels
uniform float hardness : hint_range(1.0, 100.0) = 8.0;  // how hard a busy sector loses to a quiet one
uniform float edge_preserve : hint_range(1.0, 18.0) = 8.0;  // sharpness: higher keeps edges crisper
uniform float zero_crossing : hint_range(0.01, 2.0) = 0.58;
uniform float zeta : hint_range(0.01, 3.0) = 1.0;
uniform float strength : hint_range(0.0, 1.0) = 0.7;  // 0 the frame as it was, 1 all paint

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;
	vec4 m[8];
	vec3 s[8];
	int kr = max(radius, 1);
	float sin_zc = sin(zero_crossing);
	float eta = (zeta + cos(zero_crossing)) / (sin_zc * sin_zc);
	for (int k = 0; k < _N; ++k) {
		m[k] = vec4(0.0);
		s[k] = vec3(0.0);
	}
	for (int y = -kr; y <= kr; ++y) {
		for (int x = -kr; x <= kr; ++x) {
			vec2 v = vec2(float(x), float(y)) / float(kr);
			vec3 c = clamp(texture(SCREEN_TEXTURE, SCREEN_UV + vec2(float(x), float(y)) * texel).rgb, 0.0, 1.0);
			float sum = 0.0;
			float w[8];
			float z;
			float vxx = zeta - eta * v.x * v.x;
			float vyy = zeta - eta * v.y * v.y;
			z = max(0.0, v.y + vxx); w[0] = z * z; sum += w[0];
			z = max(0.0, -v.x + vyy); w[2] = z * z; sum += w[2];
			z = max(0.0, -v.y + vxx); w[4] = z * z; sum += w[4];
			z = max(0.0, v.x + vyy); w[6] = z * z; sum += w[6];
			v = sqrt(2.0) / 2.0 * vec2(v.x - v.y, v.x + v.y);
			vxx = zeta - eta * v.x * v.x;
			vyy = zeta - eta * v.y * v.y;
			z = max(0.0, v.y + vxx); w[1] = z * z; sum += w[1];
			z = max(0.0, -v.x + vyy); w[3] = z * z; sum += w[3];
			z = max(0.0, -v.y + vxx); w[5] = z * z; sum += w[5];
			z = max(0.0, v.x + vyy); w[7] = z * z; sum += w[7];
			float g = exp(-3.125 * dot(v, v)) / max(sum, 1e-5);
			for (int k = 0; k < _N; ++k) {
				float wk = w[k] * g;
				m[k] += vec4(c * wk, wk);
				s[k] += c * c * wk;
			}
		}
	}
	vec4 o = vec4(0.0);
	for (int k = 0; k < _N; ++k) {
		m[k].rgb /= max(m[k].w, 1e-5);
		s[k] = abs(s[k] / max(m[k].w, 1e-5) - m[k].rgb * m[k].rgb);
		float sigma2 = s[k].r + s[k].g + s[k].b;
		float w = 1.0 / (1.0 + pow(hardness * 1000.0 * sigma2, 0.5 * edge_preserve));
		o += vec4(m[k].rgb * w, w);
	}
	vec3 painted = clamp(o.rgb / max(o.w, 1e-5), 0.0, 1.0);
	vec3 base = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	COLOR = vec4(mix(base, painted, strength), 1.0);
}
