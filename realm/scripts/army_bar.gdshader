// A selected regiment's health bar (Warcraft III's bar over a selected unit): a dark frame, filled from the left in
// its house's colour to its strength (0..1), always facing the lens and drawn over the ground and the men.
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;

uniform vec4 fill_color : source_color = vec4(0.8, 0.2, 0.2, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 1.0;
uniform float border = 0.12; // share of the bar's height that is frame

void vertex() {
	// Billboard: the quad turned to the lens, keeping its size in the world.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 uv = UV;
	float bx = border * 0.25; // the frame is thinner along the bar
	bool frame = uv.x < bx || uv.x > 1.0 - bx || uv.y < border || uv.y > 1.0 - border;
	float inner = (uv.x - bx) / (1.0 - 2.0 * bx);
	vec3 c = frame ? vec3(0.06) : (inner <= strength ? fill_color.rgb : vec3(0.16, 0.14, 0.12));
	ALBEDO = c;
	ALPHA = 0.95;
}
