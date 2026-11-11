// Stylised flames for fire particles: GDQuest's "Stylized fire (3D)" (MIT, the shader only; their textures are
// not used), itself after MinionsArt's stylized fire. https://godotshaders.com/shader/stylized-fire-3d/
// https://github.com/gdquest-demos/godot-shaders (godot/Shaders/stylized_fire.gdshader), MIT licence:
// Copyright (c) GDQuest. Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software... (the full MIT text: https://github.com/gdquest-demos/godot-shaders/blob/main/LICENSE).
//
// Ours on top (glue): the mask is Kenney's flame tongues (Particle Pack, CC0) as a flipbook, the colour is three
// toon bands (core, body, edge) cut from the eroded alpha instead of a gradient, edges are cut hard (no
// sorting), and each flame leans with the one wind (the global `wind`, weather_fx.gd its owner).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

global uniform vec4 wind;  // x, z: where the wind blows (world), w: its strength 0..1 (weather_fx.gd)

uniform sampler2D noise_texture : repeat_enable;  // seamless noise (Godot's NoiseTexture2D)
uniform sampler2D texture_mask : filter_linear_mipmap;  // Kenney's flame tongues, a flipbook strip
uniform int frames = 4;
uniform float time_scale = 1.6;
uniform float texture_scale = 7.0;  // noise per world unit
uniform float noise_amount = 0.75;  // how much the noise eats into the tongue
uniform vec3 core : source_color = vec3(1.0, 0.93, 0.55);
uniform vec3 body : source_color = vec3(1.0, 0.52, 0.08);
uniform vec3 edge : source_color = vec3(0.78, 0.14, 0.03);
uniform float core_at = 0.55;
uniform float body_at = 0.3;
uniform float edge_at = 0.06;
uniform float lean = 0.6;  // how far the flame's tip goes downwind, in its own heights at full wind
uniform float brightness = 1.25;

varying vec3 world_coord;
varying float world_x_dot;

void vertex() {
	// Billboard keeping the particle's scale (as Godot's own particle billboard writes it).
	mat4 mat_world = mat4(
			normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0].xyz),
			normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1].xyz),
			normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2].xyz),
			MODEL_MATRIX[3]);
	// Downwind lean, more toward the tip (the quad's top), in the world's own horizontal.
	float up = clamp(UV.y, 0.0, 1.0);
	float tip = (1.0 - up) * (1.0 - up);
	float h = length(MODEL_MATRIX[1].xyz);
	vec3 shove = vec3(wind.x, 0.0, wind.z) * (0.25 + 0.75 * wind.w) * lean * tip * h;  // always a breath of air
	VERTEX += (inverse(mat_world) * vec4(shove, 0.0)).xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat_world;
	world_coord = (mat_world * vec4(VERTEX, 1.0)).xyz;
	vec4 world_normal = mat_world * vec4(NORMAL, 0.0);
	world_x_dot = abs(dot(normalize(world_normal.xyz), vec3(1.0, 0.0, 0.0)));
	// The flipbook frame: Godot's particle anim offset (INSTANCE_CUSTOM.z).
	float f = mod(floor(INSTANCE_CUSTOM.z * float(frames)), float(frames));
	UV = vec2((UV.x + f) / float(frames), UV.y);
}

void fragment() {
	float mask = texture(texture_mask, UV).r;
	vec2 pan = vec2(0.15, 1.0) * (-TIME * time_scale);
	float noise_xy = texture(noise_texture, world_coord.xy * texture_scale + pan).r;
	float noise_zy = texture(noise_texture, world_coord.zy * texture_scale + pan + vec2(0.7, 0.3)).r;
	float noise = mix(noise_xy, noise_zy, clamp(world_x_dot, 0.0, 1.0));
	// Alpha erosion: the particle's alpha (its age, from the colour ramp) eats the tongue from its thin edges in.
	float heat = mask * mix(1.0, noise * 1.6, noise_amount);
	float v = heat + COLOR.a - 1.0;
	if (v < edge_at) {
		discard;
	}
	vec3 c = v > core_at ? core : (v > body_at ? body : edge);
	ALBEDO = c * brightness * COLOR.rgb;
}
