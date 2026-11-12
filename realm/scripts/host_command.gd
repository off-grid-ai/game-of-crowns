extends Node3D
## Commanding the King's hosts (North Star; docs/research/army-and-town-rules.md section 1). Copied from
## Warcraft III: click a unit to select it, a ring on the ground under it, and a small fixed command card
## in a corner whose orders always sit in the same cell with the same key (its "grid" hotkeys: T Y U I O,
## left to right); right-click on the ground or a town marches. From Total War's campaign map: an army is
## one thing, its banner glows when selected, and where it is ordered shows as a dotted route on the map.
##   click a host's standard   select it (the ring and the glow); click the land elsewhere to let it go
##   click one of its regiments select its host, that regiment marked (army.gd's regiments, Total War)
##   March / Attack / Besiege / Garrison   then click where (the ground, a foe's host, a town); right-click or Esc
##                             lets it go
##   Hold / Go home / Split    at once
##   right-drag                the line it marches to and forms on, facing away from the line (Total War's drag
##                             to face); a right-click marches
## It decides nothing and keeps nothing of the realm's: the hosts and their orders are the bridge's
## (bridge/hosts.js), read from the view's one mirror (awareness.gd's realm "hosts"); an order is only
## asked of the bridge (POST /host/order), and the host's standard moves as Freeciv moves its companies
## (units.gd). A regiment view that joins the group "host_views" and has select_host(host) is told
## which host is selected (the army spike's regiments, when they come).
## Numbers, the card and the switch: realm/data/host_command.json (--hosts=on / --hosts=off).

const Data := preload("res://scripts/data.gd")
const HostPick := preload("res://scripts/host_pick.gd")  # a click on a host picks it by its own body
const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const FILE := "host_command"

var main: Node
var selected := -1  # the selected host's id (bridge/hosts.js: its lowest company's id), or -1
var _aim := ""  # an order waiting for the King to click where (its row's aim: march, attack, besiege, garrison)
var _card: PanelContainer
var _title: Label
var _status: Label
var _buttons := {}  # order -> its Button on the card
var _ring: Decal
var _end: Decal  # the ring where the selected host is bound
var _glow: OmniLight3D
var _dots_sel: MultiMeshInstance3D  # the selected host's route
var _dots_rest: MultiMeshInstance3D  # every other host's route, fainter
var _right_at := Vector2.INF  # where a right-click went down while a host is selected
var _facing := false  # the right button is drawing the line the host will form on
var _ghosts: MultiMeshInstance3D  # a mark per company along that line
var _t := 0.0


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--hosts=on") or (bool(Data.value(FILE, "on", false)) and not args.has("--hosts=off"))


static func apply(m: Node) -> void:
	if not on():
		return
	var h := new()
	h.name = "HostCommand"
	h.main = m
	m.add_child(h)


func _ready() -> void:
	var tex := _ring_texture()
	_ring = _decal(tex, Data.num(FILE, "ring.energy", 1.6))
	_end = _decal(tex, Data.num(FILE, "ring.energy", 1.6) * 0.6)
	_glow = OmniLight3D.new()
	_glow.light_color = Color.from_string(String(Data.value(FILE, "glow.color", "#f0c878")), Color.GOLD)
	_glow.light_energy = Data.num(FILE, "glow.energy", 2.2)
	_glow.omni_range = Data.num(FILE, "glow.range", 0.9)
	_glow.shadow_enabled = false
	_glow.visible = false
	add_child(_glow)
	var gold := Color.from_string(String(Data.value(FILE, "route.color", "#dbb56e")), T.ACCENT)
	_dots_sel = _dots(gold)
	_dots_rest = _dots(Color(gold, Data.num(FILE, "route.others_alpha", 0.4)))
	_ghosts = _dots(Color.from_string(String(Data.value(FILE, "face.color", "#f0c878")), T.ACCENT), Data.num(FILE, "face.ghost", 0.12))
	_build_card()


# --- what the bridge says --------------------------------------------------------------------

## The crown's hosts as the mirror holds them (bridge/hosts.js list()).
func hosts() -> Array:
	if main == null or main.awareness == null:
		return []
	var v: Variant = main.awareness.realm.get_var(&"hosts", [], false)
	return v if v is Array else []


func host(id: int) -> Dictionary:
	for h in hosts():
		if int(h.get("id", -2)) == id:
			return h
	return {}


## The banner one of a host's companies carries (units.gd plants it on the first man of a tile's
## company), or null while none of its figures is up.
func _banner(h: Dictionary) -> Node3D:
	for id in h.get("units", []):
		var f: Node3D = main.units.figure_of(int(id))
		if f and is_instance_valid(f):
			var b := f.find_child("Banner", true, false) as Node3D
			if b:
				return b
	return null


## Where a host stands on the ground: under its banner as it marches, else its lead company, else its tile.
func _ground(h: Dictionary) -> Vector3:
	var at := Vector3.INF
	var b := _banner(h)
	if b:
		at = b.global_position
	else:
		var f: Node3D = main.units.figure_of(int(h.get("id", -1)))
		at = f.global_position if f and is_instance_valid(f) else main.terrain.world_pos(float(h.get("x", 0)), float(h.get("y", 0)))
	return Vector3(at.x, main.terrain.height_at(at.x, at.z), at.z)


# --- the King's hand -------------------------------------------------------------------------

## A left click on the land (main._on_ground_clicked asks first): true when it was the host's to take.
func take_click(ground: Vector3) -> bool:
	if _aim != "":
		var kind := _aim
		_set_aim("")
		_order_at(kind, ground)
		return true
	var got := _pressed
	_pressed = {}
	var h := _host_of(int(got.get("unit", -1))) if not got.is_empty() else {}
	if not h.is_empty():
		select(int(h["id"]))
		var view: Variant = got.get("view")
		if view is Node and (view as Node).has_method("select"):
			(view as Node).select(int(got["unit"]))  # army.gd: that regiment's rectangle and banner
		return true
	if selected >= 0:
		select(-1)  # the land elsewhere: the host is let go, and the click picks a town as before
	return false


## What the press under a left click met (host_pick.gd: the physics ray at the press, the camera as it was then):
## {unit, view}, or {} for the land. take_click uses it once.
var _pressed := {}


## The host a company belongs to ({} when it is in none of the King's).
func _host_of(unit: int) -> Dictionary:
	for h in hosts():
		if (h.get("units", []) as Array).has(unit) or int(h.get("id", -2)) == unit:
			return h
	return {}


## Selects a host (or none, -1): the ring, the glow and the card follow it.
func select(id: int) -> void:
	selected = id
	_set_aim("")
	var h := host(id)
	if h.is_empty():
		selected = -1
	for n in get_tree().get_nodes_in_group(&"host_views"):
		if n.has_method("select_host"):
			n.select_host(h)
	_refresh()


## A left press: what it met is kept for take_click (host_pick.gd). The right button while a host is selected,
## ahead of the camera (whose right-drag turns the view): a click marches
## there (or lets a waiting order go, Warcraft III), a drag draws the line the host forms on (Total War). Over the
## interface it is the interface's.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_pressed = HostPick.pick(get_viewport().get_camera_3d(), event.position)  # the click is resolved at its press
	if selected < 0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			if get_viewport().gui_get_hovered_control() != null:
				return
			_right_at = event.position
			_facing = false
			get_viewport().set_input_as_handled()
			return
		if _right_at == Vector2.INF:
			return
		var was := _right_at
		_right_at = Vector2.INF
		get_viewport().set_input_as_handled()
		_ghosts.multimesh.instance_count = 0
		if _facing:
			_facing = false
			var line := _line(was, event.position)
			if not line.is_empty():
				_ask(_place_body("march", line[0]).merged({"face": line[1]}))
			return
		if _aim != "":
			_set_aim("")
			return
		var g: Vector3 = main.rig._ground_under(event.position)
		if g != Vector3.INF:
			_order_at("march", g)
	elif event is InputEventMouseMotion and _right_at != Vector2.INF:
		get_viewport().set_input_as_handled()
		if not _facing and _right_at.distance_to(event.position) < Data.num(FILE, "face.drag_px", 14.0):
			return
		_facing = true
		_show_line(_right_at, event.position)


## A dragged line on the ground, from screen `a` to `b`: [its middle, the way the host faces (a yaw, atan2 of x and
## z, as the camera and the army measure it)], or [] off the land. The host faces away from the line as dragged:
## a left-to-right drag faces up the screen (the screen's drag turned a quarter, then read on the ground).
func _line(a: Vector2, b: Vector2) -> Array:
	var mid := (a + b) * 0.5
	var ahead := (b - a).normalized()
	var up_screen := Vector2(ahead.y, -ahead.x)
	var g0: Vector3 = main.rig._ground_under(mid)
	var g1: Vector3 = main.rig._ground_under(mid + up_screen * 20.0)
	if g0 == Vector3.INF or g1 == Vector3.INF:
		return []
	var way := Vector2(g1.x - g0.x, g1.z - g0.z)
	return [g0, atan2(way.x, way.y)]


## The ghost marks along the line being dragged: one per company, evenly from end to end (Total War's ghosts).
func _show_line(a: Vector2, b: Vector2) -> void:
	var ga: Vector3 = main.rig._ground_under(a)
	var gb: Vector3 = main.rig._ground_under(b)
	if ga == Vector3.INF or gb == Vector3.INF:
		return
	var n := maxi(1, int(host(selected).get("companies", 1)))
	var marks: Array[Vector3] = []
	for i in n:
		var p := ga.lerp(gb, (i + 0.5) / n)
		marks.append(Vector3(p.x, main.terrain.height_at(p.x, p.z) + Data.num(FILE, "route.lift", 0.04), p.z))
	_fill(_ghosts, marks)


func _unhandled_key_input(event: InputEvent) -> void:
	if selected < 0 or not event.is_pressed() or event.is_echo():
		return
	if event.is_action_pressed(&"back"):
		if _aim != "":
			_set_aim("")
		else:
			select(-1)
		get_viewport().set_input_as_handled()
		return
	for o in Data.value(FILE, "orders", []):
		var kind := String(o.get("order", ""))
		if InputMap.has_action(StringName("host_" + kind)) and event.is_action_pressed(StringName("host_" + kind)):
			_press(kind)
			get_viewport().set_input_as_handled()
			return


## An order from the card (a click or its key).
func _press(kind: String) -> void:
	if selected < 0:
		return
	if _row(kind).get("aim", false):
		_set_aim("" if _aim == kind else kind)
		return
	_set_aim("")
	_ask({"host": selected, "order": kind})


## An order's row on the card (host_command.json orders), or {}.
static func _row(kind: String) -> Dictionary:
	for o in Data.value(FILE, "orders", []):
		if String(o.get("order", "")) == kind:
			return o
	return {}


## An order to a place: into the town there when one is near, else to the ground (an attack is on what stands
## there, so always the ground: the bridge finds the foe on it).
func _order_at(kind: String, ground: Vector3) -> void:
	_ask(_place_body(kind, ground))


func _place_body(kind: String, ground: Vector3) -> Dictionary:
	var body := {"host": selected, "order": String(_row(kind).get("send", kind))}  # the bridge's name for it
	var town: Dictionary = {} if kind == "attack" else main.towns.nearest(ground, Data.num(FILE, "town_reach", 3.0))
	if not town.is_empty():
		body["city"] = int(town.get("id", -1))
	else:
		var tile: Vector2i = main.terrain.paths.tile_of(ground)
		body["x"] = tile.x
		body["y"] = tile.y
	return body


## Asks the bridge; it decides, and says so (the toast), and the next /world shows the host's order.
func _ask(body: Dictionary) -> void:
	main.bridge._post("/host/order", body, func(code: int, d: Dictionary) -> void:
		var said := String(d.get("text", d.get("error", "")))
		if said != "" and main.ui:
			main.ui.toast(said)
		if code == 200:
			main.sound.ordered(String(body.get("order", "")))  # heard as it sets off (sounds.json orders)
			main.bridge._poll())


func _set_aim(kind: String) -> void:
	_aim = kind
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if kind != "" else Input.CURSOR_ARROW)
	for k in _buttons:
		(_buttons[k] as Button).set_pressed_no_signal(k == kind)


# --- in the world ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	var h := host(selected) if selected >= 0 else {}
	if selected >= 0 and h.is_empty() and not hosts().is_empty():
		select(-1)  # the host is no more (fallen, or joined another)
	_ring.visible = not h.is_empty()
	_glow.visible = false
	if not h.is_empty():
		var at := _ground(h)
		var r := minf(Data.num(FILE, "ring.max", 1.6), Data.num(FILE, "ring.radius", 0.55) + Data.num(FILE, "ring.per_company", 0.06) * float(h.get("companies", 1)))
		_ring.global_position = at
		_ring.size = Vector3(r * 2.0, 1.2, r * 2.0)
		var b := _banner(h)
		if b:
			_glow.global_position = b.global_position + Vector3(0, 0.05, 0)
			_glow.visible = true
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		_routes()
		_refresh()
		_place_card()


## The dotted road to where each host is bound: bright for the selected one, faint for the rest.
func _routes() -> void:
	var sel: Array[Vector3] = []
	var rest: Array[Vector3] = []
	var every := maxf(0.1, Data.num(FILE, "route.every", 0.55))
	var lift := Data.num(FILE, "route.lift", 0.04)
	_end.visible = false
	for h in hosts():
		var o: Variant = h.get("order")
		if not (o is Dictionary) or o.get("x") == null or o.get("y") == null:
			continue
		var to: Vector3 = main.terrain.world_pos(float(o["x"]), float(o["y"]))
		var from := _ground(h)
		var flat := Vector2(to.x - from.x, to.z - from.z)
		if flat.length() < every:
			continue
		var mine := int(h.get("id", -1)) == selected
		if mine:
			var r := Data.num(FILE, "route.end_ring", 0.35)
			_end.global_position = to
			_end.size = Vector3(r * 2.0, 1.2, r * 2.0)
			_end.visible = true
		var n := int(flat.length() / every)
		for i in range(1, n):
			var p := from.lerp(to, float(i) / float(n))
			p.y = main.terrain.height_at(p.x, p.z) + lift
			(sel if mine else rest).append(p)
	_fill(_dots_sel, sel)
	_fill(_dots_rest, rest)


func _fill(mmi: MultiMeshInstance3D, points: Array[Vector3]) -> void:
	var mm := mmi.multimesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, points[i]))


func _dots(color: Color, size := -1.0) -> MultiMeshInstance3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dot := SphereMesh.new()
	var r := size if size > 0.0 else Data.num(FILE, "route.dot", 0.07)
	dot.radius = r
	dot.height = r * 0.8  # a flattened stud, lying on the land
	dot.radial_segments = 8
	dot.rings = 4
	dot.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## A ground ring painted on the land as it lies (a decal: it follows hills and roads).
func _decal(tex: Texture2D, energy: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = energy
	d.modulate = Color.from_string(String(Data.value(FILE, "ring.color", "#dbb56e")), T.ACCENT)
	d.upper_fade = 0.15
	d.lower_fade = 0.3
	d.visible = false
	add_child(d)
	return d


## A thin bright ring on a clear field, drawn from a radial gradient (no art file).
static func _ring_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.76, 0.82, 0.93, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t


# --- the command card (bottom right, over the minimap) ---------------------------------------

func _build_card() -> void:
	if main == null or main.ui == null:
		return
	_card = main.ui.glass_panel()
	_card.anchor_left = 1.0
	_card.anchor_right = 1.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_right = -12
	_card.offset_bottom = -12
	_card.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_TIGHT)
	_card.add_child(v)
	_title = T.label("The royal host", T.TEXT_2)
	v.add_child(_title)
	_status = T.datum("", T.SIZE_DESC, T.TEXT)
	v.add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", T.GAP_TIGHT)
	v.add_child(row)
	for o in Data.value(FILE, "orders", []):
		var kind := String(o.get("order", ""))
		var action := "host_" + kind
		var key := Keys.label(action) if InputMap.has_action(StringName(action)) else ""
		var b: Button = main.ui.icon_btn(String(o.get("icon", "play")), String(o.get("tip", kind.capitalize())) + ("  (%s)" % key if key != "" else ""))
		b.toggle_mode = bool(o.get("aim", false))
		b.pressed.connect(_press.bind(kind))
		if key != "":
			# The key in the button's corner, as Warcraft III's card shows it.
			var k := T.label(key, T.TEXT_3)
			k.add_theme_font_size_override("font_size", T.SIZE_LABEL - 2)
			k.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			k.position = Vector2(30, 28)
			k.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(k)
		row.add_child(b)
		_buttons[kind] = b
	_card.visible = false


## The card says what the host is and what it is doing, in the realm's words.
func _refresh() -> void:
	if _card == null:
		return
	var h := host(selected) if selected >= 0 else {}
	_card.visible = not h.is_empty()
	if h.is_empty():
		return
	var at: Variant = h.get("at")
	_title.text = ("The royal host at %s" % String(at.get("name", ""))).to_upper() if at is Dictionary else "THE ROYAL HOST"
	_status.text = "%s men · %s" % [main.ui.heads(int(h.get("men", 0))), _doing(h)]
	_card.tooltip_text = "%d companies" % int(h.get("companies", 0))


## What the host is doing, in the card's words: its order's row in host_command.json doing ({to}, {road}), the
## "there" row once it has arrived (seasons 0), "at ease" with no order.
static func _doing(h: Dictionary) -> String:
	var o: Variant = h.get("order")
	var rows: Dictionary = Data.value(FILE, "doing", {})
	if not (o is Dictionary):
		return String(rows.get("ease", "at ease"))
	var kind := String(o.get("kind", ""))
	var seasons := int(o.get("seasons", 0))
	var row: Variant = rows.get(kind, kind)
	var line := String((row.get("there", row.get("road", kind)) if seasons == 0 else row.get("road", kind)) if row is Dictionary else row)
	var road := "a season away" if seasons == 1 else "%d seasons away" % seasons
	return line.format({"to": String(o.get("to")) if o.get("to") != null else "the place you named", "road": road})


## Stacked over the minimap and its camera pad, its right edge with theirs.
func _place_card() -> void:
	if _card == null or not _card.visible:
		return
	var mm: Control = main.ui.get("_minimap_frame")
	var h := get_viewport().get_visible_rect().size.y
	_card.offset_bottom = -(h - mm.get_global_rect().position.y + 8.0) if mm and mm.is_visible_in_tree() else -12.0
