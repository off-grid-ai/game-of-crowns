extends Control
## The minimap: the whole realm in the corner, land and water, each house's
## territory in its colour, its seat under its sigil, pulsing rings wherever
## something is happening, and the patch of land the camera is looking at.
## Click or drag on it to go there.

const PX := 5  # map pixels per Freeciv tile (drawn smoothed)

var terrain: Node3D
var rig: Node3D
var _tex: ImageTexture
var _base: Texture2D
var _tint: ImageTexture  # each house's land in its colour (a = owner id / 64), one pixel a tile
var _tint_img: Image  # the colours as last shown, for the next flood to cross
var _floods: Array = []  # floods waiting their turn: [colours after, before, {at, reach}]
var _ids: Array = []  # the owner of every tile, as last shown
var _base_rect: TextureRect  # the painted map, under everything
var _wash: TextureRect  # the houses' colours over it, drawn by WASH
var _flood_t := -1.0
var _flood_reach := 0.0
const FLOOD_S := 1.5
## Each house's land washed in its colour, softly, with a fine line where two
## houses meet; when land changes hands the new colour floods out over it from
## where it changed.
const WASH := """
shader_type canvas_item;
uniform sampler2D realm_tex : filter_nearest, repeat_disable;
uniform sampler2D realm_prev : filter_nearest, repeat_disable;
uniform vec2 realm_size = vec2(1.0);
uniform vec2 flood_at[8];
uniform int flood_n = 0;
uniform float flood_r = 100000.0;
float flood_d(vec2 t) {
	float d = 100000.0;
	for (int i = 0; i < flood_n; i++) d = min(d, distance(t, flood_at[i]));
	return d;
}
vec4 owner(ivec2 c) {
	c = clamp(c, ivec2(0), ivec2(realm_size) - 1);
	if (flood_n > 0 && flood_d(vec2(c) + 0.5) > flood_r) return texelFetch(realm_prev, c, 0);
	return texelFetch(realm_tex, c, 0);
}
vec4 held(ivec2 c) {
	vec4 o = owner(c);
	return o.a > 0.0 ? vec4(o.rgb, 1.0) : vec4(0.0);
}
void fragment() {
	vec2 t = UV * realm_size;
	ivec2 c = ivec2(floor(t));
	vec4 own = owner(c);
	// The wash is smoothed between tiles; the borders are drawn sharp.
	vec2 g = t - 0.5;
	ivec2 b = ivec2(floor(g));
	vec2 w = fract(g);
	vec4 soft = mix(mix(held(b), held(b + ivec2(1, 0)), w.x), mix(held(b + ivec2(0, 1)), held(b + ivec2(1, 1)), w.x), w.y);
	vec2 f = fract(t);
	vec2 px = fwidth(t);
	float edge = 0.0;
	ivec2 dirs[4] = {ivec2(-1, 0), ivec2(1, 0), ivec2(0, -1), ivec2(0, 1)};
	float near[4] = {f.x / px.x, (1.0 - f.x) / px.x, f.y / px.y, (1.0 - f.y) / px.y};
	for (int i = 0; i < 4; i++) {
		if (abs(owner(c + dirs[i]).a - own.a) > 0.001 && near[i] < 0.8) edge = 1.0;
	}
	vec4 col = soft.a > 0.001 ? vec4(soft.rgb / soft.a, soft.a * 0.5) : vec4(0.0);
	float front = flood_n > 0 ? exp(-abs(flood_d(t) - flood_r) * 1.5) : 0.0;
	col = mix(col, vec4(mix(own.rgb, vec3(1.0, 0.95, 0.8), 0.3), 0.9), front * (own.a > 0.0 ? 1.0 : 0.0));
	if (edge > 0.5 && own.a > 0.0) col = vec4(own.rgb * 0.5, 0.85);
	COLOR = col;
}
"""
var _sig := ""
var _seats: Array = []  # [tile position, colour, is seat, name, sigil]
var _pings: Array = []  # [tile position, colour, label]: what's happening where
const Heraldry = preload("res://scripts/heraldry.gd")
const WAR := Color(0.95, 0.25, 0.2)
const TROUBLE := Color(1.0, 0.7, 0.2)
const CROWN := Color(1.0, 0.85, 0.45)
const LORDS := Color(0.85, 0.82, 0.95)  # what the lords do: treachery, raids, letters, a death
const PING := {"battle": WAR, "siege": WAR, "sack": WAR, "razed": WAR, "famine": TROUBLE, "plague": TROUBLE,
	"muster": CROWN, "rider": CROWN, "grain": CROWN, "tribute": CROWN, "ward": CROWN, "feast": CROWN, "handover": WAR}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# The map and the wash sit behind the minimap's own drawing (seats, rings, the view).
	_base_rect = TextureRect.new()
	_wash = TextureRect.new()
	for r in [_base_rect, _wash]:
		r.show_behind_parent = true
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(r)
	var sh := Shader.new()
	sh.code = WASH
	_wash.material = ShaderMaterial.new()
	_wash.material.shader = sh


func refresh(world: Dictionary, houses: Dictionary) -> void:
	if terrain == null or terrain.width == 0:
		return
	var owners: Array = world.get("owners", [])
	_activity(world)
	var sig := str(terrain.width) + str(hash(owners)) + str(world.get("cities", []).size())
	if sig == _sig:
		return
	_sig = sig
	var w: int = terrain.width
	var h: int = terrain.height
	# The base is the realm's painted relief map (bridge/tools/azgaar_mapimage.py),
	# at the land's full detail; each house's land is washed over it, softly.
	if _base == null:
		var base_path := "res://assets/maps/belia-map.png"
		if terrain.land and ResourceLoader.exists(base_path):
			_base = load(base_path)
	var tint := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ids := []
	for y in mini(owners.size(), h):
		var row := String(owners[y]).split(",")
		var cells := []
		for x in mini(row.size(), w):
			var o := -1 if row[x] == "-" or row[x] == "" else int(row[x])
			cells.append(o)
			if o >= 0 and houses.has(o) and not houses[o].get("wild", false):
				var hc := Color.from_string(String(houses[o].get("color", "#888")), Color.GRAY)
				tint.set_pixel(x, y, Color(hc.r, hc.g, hc.b, (o + 1) / 64.0))
		ids.append(cells)
	var stages: Array = terrain.flood_stages(_ids, ids, _tint_img, tint)
	_ids = ids
	_tint_img = tint
	_tint = ImageTexture.create_from_image(tint)
	_base_rect.texture = _base
	_wash.texture = _tint
	(_wash.material as ShaderMaterial).set_shader_parameter("realm_size", Vector2(w, h))
	if stages.is_empty():
		_wash_show(_tint, _tint, {})
	for st in stages:
		_wash_show(st[0], st[1], st[2])
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	_tex = ImageTexture.create_from_image(img)
	_seats.clear()
	for c in world.get("cities", []):
		var house: Dictionary = houses.get(int(c["owner"]), {})
		_seats.append([Vector2(float(c["x"]) + 0.5, float(c["y"]) + 0.5), Color.from_string(String(house.get("color", "#ddd")), Color.WHITE), c.get("capital", false), String(c.get("title", c["name"])), Heraldry.sigil(house) if c.get("capital", false) else null])
	queue_redraw()


## The realm's news on the map: recent scenes (battles, sieges, famine, the
## crown's riders) and towns starving or in disorder right now.
func _activity(world: Dictionary) -> void:
	_pings.clear()
	for sc in world.get("scenes", []):
		var kind := String(sc.get("kind", ""))
		if PING.has(kind):
			var col: Color = LORDS if sc.get("lord", false) and kind != "sack" and kind != "handover" else PING[kind]
			_pings.append([Vector2(float(sc.get("x", 0)) + 0.5, float(sc.get("y", 0)) + 0.5), col, kind])
	for c in world.get("cities", []):
		var at := Vector2(float(c["x"]) + 0.5, float(c["y"]) + 0.5)
		if c.get("disorder", false):
			_pings.append([at, WAR, "disorder"])
		elif c.get("famine", false) or (float(c.get("granary", 0)) > 0 and float(c.get("food", 0)) < float(c["granary"]) * 0.1):
			_pings.append([at, TROUBLE, "hunger"])


## Shows the houses' colours, flooding them in from {at, reach}, or at once
## ({}); a flood that comes while one is crossing the map waits for it.
func _wash_show(now: Texture2D, before: Texture2D, flood: Dictionary) -> void:
	if _flood_t >= 0.0:
		_floods.append([now, before if not flood.is_empty() else now, flood])
		return
	var m: ShaderMaterial = _wash.material
	m.set_shader_parameter("realm_tex", now)
	m.set_shader_parameter("realm_prev", before if not flood.is_empty() else now)
	if flood.is_empty():
		m.set_shader_parameter("flood_n", 0)
		m.set_shader_parameter("flood_r", 100000.0)
	else:
		m.set_shader_parameter("flood_at", flood["at"])
		m.set_shader_parameter("flood_n", (flood["at"] as PackedVector2Array).size())
		m.set_shader_parameter("flood_r", 0.0)
		_flood_reach = float(flood["reach"]) + 2.0
		_flood_t = 0.0


func _process(delta: float) -> void:
	queue_redraw()  # the view marker follows the camera
	if _flood_t >= 0.0:
		_flood_t += delta
		var k := clampf(_flood_t / FLOOD_S, 0.0, 1.0)
		var m: ShaderMaterial = _wash.material
		m.set_shader_parameter("flood_r", _flood_reach * (1.0 - pow(1.0 - k, 2.0)))
		if k >= 1.0:
			# Done: the flood's loop leaves the shader, and the next waiting flood begins.
			_flood_t = -1.0
			m.set_shader_parameter("flood_n", 0)
			# An instant change shows and the queue goes on; a flood plays and waits its turn.
			while not _floods.is_empty() and _flood_t < 0.0:
				var f: Array = _floods.pop_front()
				_wash_show(f[0], f[1], f[2])


func _scale() -> Vector2:
	return size / Vector2(terrain.width, terrain.height) if terrain and terrain.width > 0 else Vector2.ONE


func _draw() -> void:
	if _base == null and _tint == null:
		return
	var k := _scale()
	# Activity first, under the sigils: a ring that swells and fades, over and over.
	var t := Time.get_ticks_msec() / 1000.0
	for p in _pings:
		var phase := fmod(t * 0.8 + p[0].x * 0.37, 1.0)
		var col: Color = p[1]
		draw_circle(p[0] * k, 3.0, col)
		draw_arc(p[0] * k, 3.0 + phase * 7.0, 0.0, TAU, 24, Color(col.r, col.g, col.b, 1.0 - phase), 1.5, true)
	var font := get_theme_default_font()
	for s in _seats:
		var big: bool = s[2]
		if big and s[4] != null:
			# The house's sigil marks its seat.
			var r := Rect2(s[0] * k - Vector2(7, 7), Vector2(14, 14))
			draw_circle(s[0] * k, 8.0, Color(0.04, 0.04, 0.04, 0.7))
			draw_texture_rect(s[4], r, false, s[1].lerp(Color.WHITE, 0.3))
		else:
			draw_circle(s[0] * k, 4.5 if big else 2.6, Color(0.04, 0.04, 0.04))
			draw_circle(s[0] * k, 3.2 if big else 1.6, Color(1, 0.97, 0.9) if big else s[1])
		if big and font:
			var label: String = s[3]
			var at: Vector2 = s[0] * k + Vector2(9, 3)
			# Near the right edge, the name goes on the left of the sigil instead.
			var wide := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
			if at.x + wide > size.x - 4:
				at.x = s[0].x * k.x - 9 - wide
			draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.8))
			draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 0.97, 0.9))
	if rig == null:
		return
	# Where you're looking: the ground the camera sees, as a turned box.
	var tile: float = terrain.TILE
	var c: Vector2 = Vector2(rig.target.x, rig.target.z) / tile * k
	var half: float = rig.distance * 0.55 / tile
	var span := Vector2(half * 1.6, half) * k
	span = span.max(Vector2(9, 6))  # never smaller than a thumbnail you can see
	var fwd := Vector2(-sin(rig.yaw), -cos(rig.yaw))
	var right := Vector2(-fwd.y, fwd.x)
	var quad := PackedVector2Array([c - right * span.x * 0.7 + fwd * span.y, c + right * span.x * 0.7 + fwd * span.y, c + right * span.x * 1.3 - fwd * span.y, c - right * span.x * 1.3 - fwd * span.y])
	draw_colored_polygon(quad, Color(1, 0.92, 0.7, 0.18))
	quad.append(quad[0])
	draw_polyline(quad, Color(1, 0.92, 0.7, 1.0), 2.0, true)
	draw_circle(c, 2.5, Color(1, 0.92, 0.7))
	draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.15), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	var go := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		go = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		go = true
	if go and rig and terrain and terrain.width > 0:
		var t: Vector2 = event.position / _scale()
		var p: Vector3 = terrain.world_pos(t.x - 0.5, t.y - 0.5)
		# A click on a town's mark frames that town; anywhere else, just go there.
		var hit = null
		if event is InputEventMouseButton:
			for s in _seats:
				if (s[0] - t).length() < 1.2:
					hit = s
		if hit != null:
			rig.frame_town(terrain.world_pos(hit[0].x - 0.5, hit[0].y - 0.5), 6 if hit[2] else 4)
		else:
			rig.focus(p)
		accept_event()
