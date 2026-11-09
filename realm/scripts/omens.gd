extends ColorRect
## Signs at the edge of the screen when the reign goes badly: blood and soot
## creep in from the edges as the realm's peace falls, and the colour drains out
## of the world as the royal treasury starves. Never in the middle of the view,
## never over the interface (it sits under every card): the world itself
## darkens at its edges, so the King feels a bad reign before he reads it.

## 0 at peace, 1 when the realm is all war.
var blood := 0.0
## 0 with a full treasury, 1 when it is empty.
var drain := 0.0
var _blood := 0.0
var _drain := 0.0

const SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float blood = 0.0;
uniform float drain = 0.0;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen, uv).rgb;
	// A starving treasury: the colour leaches out of the world, toward a cold grey.
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g) * vec3(0.94, 0.97, 1.02), drain * 0.8);
	// How near the edge, ragged so it reads as smoke and stain, not a lens.
	vec2 c = (uv - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0) * 1.6;
	float r = length(c);
	float ragged = (fbm(uv * 5.0) - 0.5) * 0.35;
	// The more the war, the further in it comes.
	float soot = smoothstep(0.95 - blood * 0.35, 1.3, r + ragged) * blood;
	// The stains come from the same noise, read further out: one pass, not two.
	float stain = smoothstep(0.62, 0.74, fbm(uv * 5.0) + noise(uv * 23.0) * 0.25) * smoothstep(0.85 - blood * 0.25, 1.15, r + ragged * 0.5) * blood;
	col = mix(col, vec3(0.05, 0.04, 0.035), soot * 0.85);
	col = mix(col, vec3(0.32, 0.02, 0.015), stain * 0.85);
	col *= 1.0 - drain * smoothstep(0.7, 1.4, r) * 0.45;
	COLOR = vec4(col, 1.0);
}
"""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sh := Shader.new()
	sh.code = SHADER
	material = ShaderMaterial.new()
	material.shader = sh
	visible = false


## Read from the realm: its peace (0-1) and the royal treasury against what a
## season of rule costs (-1: not known yet, or no crown: nothing drains). A
## healthy realm shows nothing at all.
func read(peace: float, purse: float) -> void:
	blood = 1.0 - smoothstep(0.1, 0.55, peace)
	drain = 0.0 if purse < 0.0 else 1.0 - smoothstep(0.0, 150.0, purse)


func _process(delta: float) -> void:
	# The signs creep in and out over a few seconds, never in a jump.
	_blood = move_toward(_blood, blood, delta * 0.25)
	_drain = move_toward(_drain, drain, delta * 0.25)
	visible = _blood > 0.01 or _drain > 0.01
	if visible:
		(material as ShaderMaterial).set_shader_parameter("blood", _blood)
		(material as ShaderMaterial).set_shader_parameter("drain", _drain)
