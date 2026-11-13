/*
VAT Shader - Antz

INSTANCE_CUSTOM is used to display a unique animation per instance.
It has total of 4 floats. All renderers supported

	Red channel:
		animation offset: used to randomize instances playing the same animation track

	Green channel:
		animation start frame

	Blue channel:
		animation end frame

	Alpha channel:
		alpha of mesh: used to fade in/out a unique instance

		
Instanced COLOR is used for interpolation, looping / non-looping (also called one_shot) animations.
It has total of 4 floats. All renderers supported.

	Red channel: (FLOAT ENCODED)
		digit 0 {use_looping:  1.0 = true, 0.0 = false}
		digit 1 {use_blended:  1.0 = true, 0.0 = false}
		digit 2 {use_reversed: 1.0 = true, 0.0 = false} <-- UNUSED FOR NOW
		digit 3-5 {animation frame rate: 0-999}

	Green channel:
		timestamp:
			if looping - when the looping animation started.
			if non-lopping - Tells the shader when the one_shot has been reset.

	Blue channel: 
		UNUSED
	
	Alpha channel:
		UNUSED
*/

// The army's soldiers (army spike): antzGames' VAT shader (MIT, realm/addons/godot_vat) with team colour
// added, by palette cell (the KayKit knight) or by mask (image-made units) (Warcraft III's way; docs/art/target/03-army.jpg): KayKit's palette paints the cloth (cape,
// tabard) in its red swatches, so the texels inside those palette cells (team_rect_a, team_rect_b; data/army.json
// team.rects) take the regiment's colour, keeping their light and shade. Picked by palette cell, not by hue, so
// skin and leather keep their own colour. Each regiment (a MultiMesh) has its own copy of the material, so every regiment
// wears its house's colour. Opaque (a fade cuts out at half alpha), so the men take the realm's shadows and
// ambient occlusion like everything else; the kit has no normal texture, so none is applied unless given.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D offset_map: filter_nearest;
uniform vec4 team_color : source_color = vec4(0.75, 0.12, 0.10, 1.0);  // the regiment's house (each regiment its own material)
uniform float team_strength : hint_range(0.0, 1.0) = 1.0;
uniform vec4 team_rect_a = vec4(0.0, 0.25, 0.125, 0.5);  // u0, v0, u1, v1: a palette cell that takes the colour
uniform vec4 team_rect_b = vec4(0.25, 0.5, 0.375, 0.75);
uniform vec4 team_rect_c = vec4(-1.0);  // up to four cells; an unused one lies off the palette
uniform vec4 team_rect_d = vec4(-1.0);
uniform vec4 team_mix = vec4(1.0, 1.0, 1.0, 1.0);  // how much of each cell (a, b, c, d) takes the colour: 1 dyed cloth, less a painted plate
uniform float team_shade = 1.1;
// An image-made soldier (tools/rig/README.md) wears its house colour where its mask.png is white (the rig
// pipeline paints the white cloth there), instead of by palette cell; data/army.json meshes.<dir>.team "mask".
uniform bool team_by_mask = false;
uniform sampler2D team_mask : hint_default_black, filter_linear_mipmap;
// The mask's edge: a texel this much dyed or more is all cloth. Far off, the mask's mipmaps average a man's cloth with the
// white around it (about half), and a half-dyed white cloth read candy pink (group render g1, the breach: the besiegers
// pink, not the house's deep red); data/army.json team.mask_edge.
uniform vec2 team_mask_edge = vec2(0.15, 0.4);
uniform sampler2D normal_map: filter_nearest;
// The house's arms worn on the shield's face and the tabard's front (Total War's faction shields; the arms are the
// top of the house's banner, assets/heraldry, the same picture its standard flies). Each place is a box in the
// soldier's rest pose (data/army.json meshes.<dir>.emblem): centre (xyz, w 1 for a round shield), size (across, up,
// depth; w the least its face must turn toward the box's facing), facing and up. Read from the mesh as it stands
// before the bake's offsets, so the arms ride every frame of every clip; one texture per regiment, no draw added.
uniform bool emblem_on = false;
uniform sampler2D emblem_texture : source_color, hint_default_transparent, filter_linear_mipmap_anisotropic, repeat_disable;  // anisotropic: the arms stay crisp on a shield seen edge-on
uniform vec4 emblem_rect = vec4(0.0, 0.06, 1.0, 0.56);  // u0, v0, u1, v1: the arms within the banner picture
uniform float emblem_light = 0.9;  // the arms' paint under the realm's sun
uniform vec4 emblem_a_center = vec4(0.0, -99.0, 0.0, 0.0);
uniform vec4 emblem_a_size = vec4(0.0, 0.0, 0.0, 0.3);
uniform vec3 emblem_a_facing = vec3(0.0, 0.0, 1.0);
uniform vec3 emblem_a_up = vec3(0.0, 1.0, 0.0);
uniform vec4 emblem_b_center = vec4(0.0, -99.0, 0.0, 0.0);
uniform vec4 emblem_b_size = vec4(0.0, 0.0, 0.0, 0.3);
uniform vec3 emblem_b_facing = vec3(0.0, 0.0, 1.0);
uniform vec3 emblem_b_up = vec3(0.0, 1.0, 0.0);
varying vec3 rest_pos;
varying vec3 rest_nrm;
varying flat float man_roll;  // this man's own draw, 0..1: his variation from his fellows

// The painted finish every soldier wears (data/army.json look): the kit soldier read as Age of Empires IV's and
// Warcraft III Reforged's men do at the camera's closest stop. Steel that reads as steel from every side (found
// by its low saturation, so a palette knight and a mask-painted soldier alike; metal, a lower roughness, a rim);
// the house cloth with a darker trim band at its hem and collar (bands of the rest pose's height); feet grounded
// by a darkening toward the ground; each man a little off his fellows in value and tint.
uniform float mesh_height = 2.45;  // the soldier's rest-pose height, in his own units (army.gd sets it)
uniform float steel_sat = 0.14;  // saturation below which a texel is steel
uniform float steel_metal = 0.65;
uniform float steel_rough = 0.38;
uniform float steel_lift = 1.12;  // steel's paint a touch brighter, so its dark side is never flat grey
uniform float steel_glow = 0.05;  // and a faint light of its own there
uniform float rim = 0.35;
uniform float rim_tint = 0.6;
uniform float foot_dark = 0.55;  // the paint's value at the soles
uniform float foot_height = 0.14;  // share of his height the darkening fades up through
uniform float trim_dark = 0.62;  // the trim band's value against the cloth
uniform vec2 trim_a = vec2(-1.0, -1.0);  // a band (share of height, low and high) where the cloth is trim
uniform vec2 trim_b = vec2(-1.0, -1.0);
uniform float vary_value = 0.08;  // each man's paint lighter or darker by up to half this
uniform float vary_tint = 0.06;  // and his cloth's colour off by up to half this

group_uniforms Albedo;
uniform vec4 albedo : source_color = vec4(1.0); // Opaque white by default
uniform sampler2D albedo_texture : source_color;
group_uniforms;

group_uniforms Metallic;
uniform sampler2D metallic_texture : hint_default_white;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 metallic_texture_channel: source_color = vec4(1.0, 0.0, 0.0, 0.0); // Red channel by default
uniform float specular : hint_range(0.0, 1.0) = 0.5;
group_uniforms;

group_uniforms Roughness;
uniform sampler2D roughness_texture : hint_roughness_r;
uniform float roughness : hint_range(0.0, 1.0) = 1.0;
uniform vec4 roughness_texture_channel : source_color = vec4(1.0, 0.0, 0.0, 0.0); // Red channel by default
group_uniforms;

group_uniforms NormalMap;
uniform bool use_normal_texture = false;
uniform sampler2D normal_map_texture : hint_normal;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
group_uniforms;

varying flat vec4 custom_data;
varying flat vec4 color_data;

// How much of the arms lie at this point of the soldier, and where in them (rgb, a: their cover).
vec4 emblem_at(vec4 centre, vec4 size, vec3 facing, vec3 up) {
	vec3 f = normalize(facing);
	vec3 u = normalize(up - f * dot(up, f));
	vec3 r = cross(u, f);
	vec3 d = rest_pos - centre.xyz;
	vec2 q = vec2(dot(d, r) / max(size.x, 0.0001), -dot(d, u) / max(size.y, 0.0001));  // -0.5..0.5 across the box
	float inside = step(abs(q.x), 0.5) * step(abs(q.y), 0.5) * step(abs(dot(d, f)), size.z * 0.5);
	inside *= step(size.w, dot(normalize(rest_nrm), f));  // its face, not its rim or the arm behind
	inside *= mix(1.0, step(length(q), 0.5), centre.w);  // a round shield wears the arms in a roundel
	vec4 arms = texture(emblem_texture, mix(emblem_rect.xy, emblem_rect.zw, q + 0.5));
	return vec4(arms.rgb, arms.a * inside);
}

int extractDigitGroup(float value, int groupIndex, int digitCount) {
    float exp = pow(10.0, float(digitCount));
    return int(mod(value * exp * pow(10.0, float(groupIndex * digitCount)), exp));
}

void vertex(){
	man_roll = fract(sin(float(INSTANCE_ID) * 12.9898 + 78.233) * 43758.5453);
	rest_pos = VERTEX;  // the soldier as he stands in the bind pose, before the clip's offsets
	rest_nrm = NORMAL;
	custom_data = INSTANCE_CUSTOM;
	color_data = COLOR;

	float use_looping = float(extractDigitGroup(color_data.r, 0, 1));
	float use_blended = float(extractDigitGroup(color_data.r, 1, 1));
	float timestamp   = color_data.g;
	
	float start_frame = custom_data.g;
	float end_frame = custom_data.b;
	float num_frames = end_frame - start_frame;
	int frame_count = int(end_frame - start_frame);  // for % mod used later
	
	float frame_offset = num_frames * custom_data.r;
	float speed = max(1.0, float(float(extractDigitGroup(color_data.r, 1, 3))));

	// if start_frame and end_frame are the same - prevents divide by zero
	num_frames = clamp(num_frames, 0.0001, 8192.0);

	float time_scale_normalized = (TIME - timestamp) * (speed / num_frames);
	
	float loop_time  = mod(time_scale_normalized, 1.0);
	float frame_time = mix(time_scale_normalized, loop_time, use_looping);

	float frame_progress        = frame_time * num_frames;
	float frame_progress_offset = frame_progress + frame_offset;
		
	float stop_frame = start_frame + floor(frame_progress);

	float blend_frame = start_frame + mix(
		frame_progress_offset + 1.0,
		mod(frame_progress_offset, num_frames) + 1.0,
		use_looping
	);
		
	float current_frame_raw = mix(stop_frame, blend_frame, use_blended);
	float ceil_frame        = ceil(current_frame_raw);

	float current_frame = mix(
		clamp(current_frame_raw, start_frame, end_frame),
		mix(current_frame_raw, start_frame, step(end_frame, current_frame_raw)),
		use_looping
	);

	float frame_ceil = mix(
		clamp(ceil_frame, start_frame, end_frame),
		float(int(ceil_frame - start_frame) % frame_count) + start_frame,
		use_looping
	);
		
	ivec2 tex_size = textureSize(offset_map, 0);
	float pixel_size = 1.0 / float(tex_size.y);

	float frame_floor = clamp(floor(current_frame), start_frame, end_frame);
	vec2 frame_floor_uv_offset = vec2(0.0, -((frame_floor + 0.5) * pixel_size));
	vec2 frame_ceil_uv_offset = vec2(0.0, -((frame_ceil + 0.5) * pixel_size));

	float lerp_factor = current_frame - frame_floor;

	// Calculate vertex position
	vec3 offset_floor = texture(offset_map, UV2 + frame_floor_uv_offset).xyz;
	vec3 offset_ceil = texture(offset_map, UV2 + frame_ceil_uv_offset).xyz;
	vec3 offset_lerp = mix(offset_floor, offset_ceil, lerp_factor);
	vec3 new_offset = vec3(offset_lerp.x, offset_lerp.z, offset_lerp.y);
	VERTEX += new_offset;

	// Calculate normal
	vec3 normal_floor = texture(normal_map, UV2 + frame_floor_uv_offset).xyz;
	vec3 normal_ceil = texture(normal_map, UV2 + frame_ceil_uv_offset).xyz;
	vec3 normal_lerp = mix(normal_floor, normal_ceil, lerp_factor);
	vec3 new_normal = vec3((normal_lerp.x * 2.0) - 1.0, (normal_lerp.z * 2.0) - 1.0, (normal_lerp.y * 2.0) - 1.0);
	NORMAL = new_normal;
	
	//// Recomputes TANGENT & BIPLANAR based on the updated NORMAL (taken from the Godot source)
	TANGENT = normalize(vec3(abs(NORMAL.y) + abs(NORMAL.z), 0.0, -abs(NORMAL.x)));
	BINORMAL = normalize(vec3(0.0, abs(NORMAL.x) + abs(NORMAL.z), -abs(NORMAL.y)));
}

void fragment() {
	vec3 base = albedo.rgb * texture(albedo_texture, UV).rgb;
	// The palette's red swatches are the cloth: they take the regiment's colour at their own brightness.
	// The cloth swatches (a, b) and, where data/army.json asks, a plate cell (c, d: the kit's knight has
	// almost no cloth, 3.5% of his surface, so his breastplate takes the colour as painted steel).
	float in_a = step(team_rect_a.x, UV.x) * step(UV.x, team_rect_a.z) * step(team_rect_a.y, UV.y) * step(UV.y, team_rect_a.w) * team_mix.x;
	float in_b = step(team_rect_b.x, UV.x) * step(UV.x, team_rect_b.z) * step(team_rect_b.y, UV.y) * step(UV.y, team_rect_b.w) * team_mix.y;
	float in_c = step(team_rect_c.x, UV.x) * step(UV.x, team_rect_c.z) * step(team_rect_c.y, UV.y) * step(UV.y, team_rect_c.w) * team_mix.z;
	float in_d = step(team_rect_d.x, UV.x) * step(UV.x, team_rect_d.z) * step(team_rect_d.y, UV.y) * step(UV.y, team_rect_d.w) * team_mix.w;
	float shade = max(base.r, max(base.g, base.b));
	float dyed = team_by_mask ? smoothstep(team_mask_edge.x, team_mask_edge.y, texture(team_mask, UV).r) : max(max(in_a, in_b), max(in_c, in_d));
	vec3 cloth = team_color.rgb * shade * team_shade;
	float rel = rest_pos.y / max(mesh_height, 0.001);  // how far up the man this point stands in his rest pose
	// His own cloth, a little off his fellows'; a darker trim band at the hem and collar.
	float r2 = fract(man_roll * 7.31);
	cloth *= vec3(1.0 + (r2 - 0.5) * vary_tint, 1.0 + (fract(r2 * 3.7) - 0.5) * vary_tint, 1.0 + (fract(r2 * 9.1) - 0.5) * vary_tint);
	float trim = max(step(trim_a.x, rel) * step(rel, trim_a.y), step(trim_b.x, rel) * step(rel, trim_b.y));
	cloth *= mix(1.0, trim_dark, trim);
	ALBEDO = mix(base, cloth, dyed * team_strength);
	float painted = 0.0;
	if (emblem_on) {
		vec4 ea = emblem_at(emblem_a_center, emblem_a_size, emblem_a_facing, emblem_a_up);
		vec4 eb = emblem_at(emblem_b_center, emblem_b_size, emblem_b_facing, emblem_b_up);
		vec4 e = ea.a >= eb.a ? ea : eb;
		ALBEDO = mix(ALBEDO, e.rgb * emblem_light, e.a);
		painted = e.a;
	}
	METALLIC = dot(texture(metallic_texture, UV), metallic_texture_channel) * metallic * (1.0 - painted);  // the arms are paint; the rest of the steel stays steel
	SPECULAR = specular;
	ROUGHNESS = dot(texture(roughness_texture, UV), roughness_texture_channel) * roughness;
	// Steel that reads as steel: found by its low saturation.
	float hi = max(base.r, max(base.g, base.b));
	float sat = (hi - min(base.r, min(base.g, base.b))) / max(hi, 0.001);
	float steel = (1.0 - smoothstep(steel_sat, steel_sat + 0.08, sat)) * smoothstep(0.22, 0.38, hi) * (1.0 - dyed * team_strength) * (1.0 - painted);
	ALBEDO = mix(ALBEDO, ALBEDO * steel_lift, steel);
	METALLIC = mix(METALLIC, steel_metal, steel);
	ROUGHNESS = mix(ROUGHNESS, steel_rough, steel);
	EMISSION = ALBEDO * steel_glow * steel;
	RIM = rim;
	RIM_TINT = rim_tint;
	// Grounded: darker toward his feet; and his own value, a little off his fellows'.
	ALBEDO *= mix(foot_dark, 1.0, smoothstep(0.0, foot_height, rel));
	ALBEDO *= 1.0 + (man_roll - 0.5) * vary_value;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_map_texture, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	ALPHA = custom_data.a;  // fader: a man fading out is cut away at half
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
