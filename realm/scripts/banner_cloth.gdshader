shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// A banner's cloth in the wind: still at the pole, rippling more toward the
// free edge, a slow swell with a quicker flutter over it, each flag on its own
// beat. Turned about its pole to face the camera (a banner seen from above is
// never a sliver), as heraldry.gd's flags always have been.

uniform sampler2D cloth_tex : source_color, filter_linear_mipmap;
uniform vec4 cloth_color : source_color = vec4(1.0);
uniform bool use_tex = false;
uniform float wind = 1.0;  // the sky's wind (Sky3D), 0 still .. 2 strong
instance uniform float span = 0.2;  // the cloth's width in world units
instance uniform float phase = 0.0;  // this flag's place in the wind
instance uniform float fringe = 0.0;  // 1: the house is sworn to the crown, and its banners carry a gold fringe

void vertex() {
	float t = UV.x;  // 0 at the pole, 1 at the free edge
	float pace = 0.6 + wind * 0.8;
	float reach = 0.4 + wind * 0.6;
	float a = TIME * 2.1 * pace + UV.x * 6.0 - UV.y * 1.5 + phase;
	float b = TIME * 3.9 * pace + UV.x * 11.0 + phase * 1.7;
	float wave = (sin(a) * 0.07 + sin(b) * 0.025) * reach;
	float slope = (cos(a) * 0.07 * 6.0 + cos(b) * 0.025 * 11.0) * reach;
	VERTEX.z += wave * t * span;
	VERTEX.y += sin(a * 0.7) * 0.03 * t * span;
	VERTEX.x -= abs(wave) * t * span * 0.35;  // a rippling cloth reaches less far
	NORMAL = normalize(vec3(-slope * t, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

// Like the trees (realistic.gd fade_near): a banner right in front of the lens
// dissolves (dithered), so it never fills the view; world units from the camera.
uniform float near_gone = 0.6;  // a banner is read from afar (its favour), so it gives way sooner than a tree
uniform float near_solid = 1.6;

void fragment() {
	float fade = smoothstep(near_gone, near_solid, length(VERTEX));
	if (fade < 1.0) {
		ivec2 px = ivec2(FRAGCOORD.xy) % 4;
		float bayer[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
		if (fade < (bayer[px.y * 4 + px.x] + 0.5) / 16.0) discard;
	}
	vec4 c = use_tex ? texture(cloth_tex, UV) : cloth_color;
	ALBEDO = c.rgb;
	ROUGHNESS = 1.0;
	// A sworn house's banner: a band of crown gold along its free edge.
	ALBEDO = mix(ALBEDO, vec3(0.79, 0.66, 0.35), fringe * step(0.86, UV.x));
	if (use_tex) {
		ALPHA = c.a;
		ALPHA_SCISSOR_THRESHOLD = 0.5;
	}
}
