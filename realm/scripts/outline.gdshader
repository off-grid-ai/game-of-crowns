shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, fog_disabled, shadows_disabled;

// The v3 look's painted line and edge light (look.gd _add_outline; look.json v3.outline; art target 01-town).
// A full-screen pass over the scene's depth and normals, drawn by a 2x2 quad in front of the lens.
//
// Built on two MIT shaders from godotshaders.com:
//   High Quality Post Process Outline, Hannah "EMBYR" Crawford (MIT): the 3x3 depth and normal edge tests,
//     the line's width and strength easing with distance.
//     https://godotshaders.com/shader/high-quality-post-process-outline/
//   3D Pixel art outline & highlight, Leo Peltola, perspective by Riley Evans (MIT): lightening an edge where
//     a surface folds toward the light, inspired by the three.js pixel post-processing example.
//     https://godotshaders.com/shader/3d-pixel-art-outline-highlight-post-processing-shader/
// Fitted to the realm: the depth test is relative to the distance (a game unit is about 8 m and the camera
// stands 6 to 60 units off, so one absolute threshold can't serve both), the normals are decoded before use,
// grazing ground (the terrain at a low pitch) needs a much larger jump to draw a line, and the edge light falls
// only on convex folds of one surface (a roof's ridge, a beam's corner), never across a silhouette.

uniform vec4 line_color : source_color = vec4(0.16, 0.09, 0.05, 0.7);  // warm dark brown, not black
uniform float width_near = 1.6;   // line width in pixels at near
uniform float width_far = 0.8;    // and at far
uniform float near_at = 4.0;       // game units from the lens
uniform float far_at = 60.0;
uniform float fade_far = 80.0;    // gone by this distance
uniform float near_soft = 1.0;    // the line's and edge light's strength at near_at (1: no close fade)
uniform float soft_to = 4.0;      // whole again by this distance (game units from the lens)
uniform float depth_threshold = 0.035;  // a jump of this share of the distance (summed over 8 neighbours) draws a line
uniform float grazing = 6.0;       // how much larger the jump must be on a surface seen edge-on
uniform float grazing_power = 3.0;
uniform float normal_threshold = 0.9;   // a crease this sharp (summed normal differences) draws a line
uniform float normal_smoothing = 0.25;
uniform float normal_line = 0.6;   // creases' share of the line's strength (silhouettes 1.0)
uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.78, 0.22);  // the edge light: warm, soft
uniform float light_from = 0.15;  // convexity where the edge light begins
uniform float light_to = 0.6;     // and where it's whole
uniform float same_surface = 0.02;  // the edge light only within this share of the distance (one surface)

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D NORMR_TEXTURE : hint_normal_roughness_texture, filter_nearest, repeat_disable;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_pos(vec2 uv, mat4 inv_proj) {
	float raw = texture(DEPTH_TEXTURE, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, raw, 1.0);
	return v.xyz / v.w;
}

float lin(vec2 uv, mat4 inv_proj) {
	return -view_pos(uv, inv_proj).z;
}

vec3 nrm(vec2 uv) {
	return normalize(texture(NORMR_TEXTURE, uv).xyz * 2.0 - 1.0);
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec3 p = view_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float d = -p.z;
	if (d > fade_far) {
		discard;
	}
	float t = clamp((d - near_at) / max(far_at - near_at, 0.001), 0.0, 1.0);
	float w = mix(width_near, width_far, t);
	vec2 h = vec2(px.x * w, 0.0);
	vec2 v = vec2(0.0, px.y * w);

	// Depth: the 8 neighbours against the centre, as a share of the distance (EMBYR's sum).
	float dl = lin(SCREEN_UV - h, INV_PROJECTION_MATRIX);
	float dr = lin(SCREEN_UV + h, INV_PROJECTION_MATRIX);
	float du = lin(SCREEN_UV - v, INV_PROJECTION_MATRIX);
	float dd = lin(SCREEN_UV + v, INV_PROJECTION_MATRIX);
	float dtl = lin(SCREEN_UV - h - v, INV_PROJECTION_MATRIX);
	float dtr = lin(SCREEN_UV + h - v, INV_PROJECTION_MATRIX);
	float dbl = lin(SCREEN_UV - h + v, INV_PROJECTION_MATRIX);
	float dbr = lin(SCREEN_UV + h + v, INV_PROJECTION_MATRIX);
	float jump = (min(dl + dr + du + dd + dtl + dtr + dbl + dbr, 8.0 * fade_far) - 8.0 * d) / max(d, 0.001);
	vec3 n = nrm(SCREEN_UV);
	vec3 view = normalize(-p);
	float edge_on = pow(1.0 - clamp(abs(dot(n, view)), 0.0, 1.0), grazing_power);
	float sil = step(depth_threshold * (1.0 + grazing * edge_on), jump);

	// Creases: the normals' finite differences across the 3x3 (EMBYR's).
	vec3 nl = nrm(SCREEN_UV - h);
	vec3 nr = nrm(SCREEN_UV + h);
	vec3 nu = nrm(SCREEN_UV - v);
	vec3 nd = nrm(SCREEN_UV + v);
	vec3 ntl = nrm(SCREEN_UV - h - v);
	vec3 ntr = nrm(SCREEN_UV + h - v);
	vec3 nbl = nrm(SCREEN_UV - h + v);
	vec3 nbr = nrm(SCREEN_UV + h + v);
	vec3 f0 = ntr - nbl;
	vec3 f1 = ntl - nbr;
	vec3 f2 = nl - nr;
	vec3 f3 = nu - nd;
	float crease_amt = sqrt(dot(f0, f0) + dot(f1, f1) + dot(f2, f2) + dot(f3, f3));
	float crease = smoothstep(normal_threshold - normal_smoothing, normal_threshold + normal_smoothing, crease_amt);

	// The edge light (Peltola's idea): a fold that turns away from the lens on both sides is convex. Moving right
	// on screen its normal turns right, moving up (uv - v) it turns up; only on one surface (no depth jump).
	float convex = (nr.x - nl.x) + (nu.y - nd.y);
	float one_surface = 1.0 - smoothstep(same_surface, same_surface * 2.0, abs(jump) / 8.0);
	float lit = smoothstep(light_from, light_to, convex) * one_surface * (1.0 - sil);

	float fade = (1.0 - smoothstep(far_at, fade_far, d)) * mix(near_soft, 1.0, smoothstep(near_at, max(soft_to, near_at + 0.001), d));
	float line_a = max(sil, crease * normal_line * (1.0 - smoothstep(light_from, light_to, convex))) * line_color.a * fade;
	float light_a = lit * light_color.a * fade;
	if (line_a >= light_a) {
		ALBEDO = line_color.rgb;
		ALPHA = line_a;
	} else {
		ALBEDO = light_color.rgb;
		ALPHA = light_a;
	}
	if (ALPHA <= 0.003) {
		discard;
	}
}
