shader_type canvas_item;
// The studio seal's light: a warm band of light that sweeps across the metal
// (sweep runs from -0.3 to 1.3 across the face), and a flash on the whole seal
// as it is struck (flash 0..1). Only where the seal is opaque.

uniform float sweep = -1.0;
uniform float flash = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = (UV.x * 0.8 + UV.y * 0.2) - sweep;
	float band = smoothstep(0.14, 0.0, abs(d));
	c.rgb += (band * 0.55 + flash * 0.45) * vec3(1.0, 0.9, 0.72) * c.a;
	COLOR = c;
}
