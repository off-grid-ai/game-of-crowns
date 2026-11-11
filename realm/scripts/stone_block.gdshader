shader_type spatial;
// One dressed stone of a wall (stone_wall.gd): the Medieval Village kit's own
// rock trim (T_RockTrim, Quaternius), each face showing exactly one of its
// painted blocks. A MultiMesh instance picks its block through its custom data
// (u0, v0, du, dv of the texture) and its shade through its colour, so a whole
// wall, standing or fallen, is one draw.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);

varying vec4 rect;
varying vec3 shade;

void vertex() {
	rect = INSTANCE_CUSTOM;
	shade = COLOR.rgb;
}

void fragment() {
	vec2 uv = rect.xy + clamp(UV, vec2(0.02), vec2(0.98)) * rect.zw;
	ALBEDO = texture(albedo_tex, uv).rgb * tint.rgb * shade;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	vec3 orm = texture(orm_tex, uv).rgb;
	ROUGHNESS = clamp(orm.g, 0.55, 1.0);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.3;
}
