extends Node3D
## Commanding the King's hosts (North Star; docs/research/army-and-town-rules.md section 1). Copied from
## Warcraft III: click a unit to select it, a ring on the ground under it, and a small fixed command card
## in a corner whose orders always sit in the same cell with the same key (its "grid" hotkeys: T Y U I O,
## left to right); right-click on the ground or a town marches. From Total War's campaign map: an army is
## one thing, its banner glows when selected, and where it is ordered shows as a dotted route on the map.
##   click a host's standard   select it (the ring and the glow); click the land elsewhere to let it go;
##                             shift- or Cmd-click another to add it (or take it out): every order goes to them all
##   Cmd-drag on the land      a box: every one of the King's hosts whose standard is inside is selected (Shift with
##                             it adds them to those already selected). A plain left-drag still moves the view.
##   double-click a standard   every one of the King's hosts on screen; F2 (host_all) every one of them in the realm
##   click one of its regiments select its host, that regiment marked (army.gd's regiments, Total War)
##   March / Attack / Besiege / Garrison   then click where (the ground, a foe's host, a town); right-click or Esc
##                             lets it go
##   Hold / Go home / Split    at once
##   right-drag                the line it marches to and forms on, facing away from the line (Total War's drag
##                             to face); a right-click gives the order what it lands on asks for (_intent): the
##                             ground marches, a foe's men are attacked, a foe's town besieged, a friendly town relieved
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
const Terrain := preload("res://scripts/terrain.gd")  # its GROUND_LAYER: the ring is painted on the land alone
const TeamColour := preload("res://scripts/team_colour.gd")  # the ring in the crown's own colour, as its men wear it
const FILE := "host_command"

signal ordered(kind: String)  # an order given (the one way, order()): the Hand's tour waits for it (hand_prompts.gd)
signal selection_changed  # a host selected, added, taken out or let go: the armies bar reads it again (army_bar.gd)

var main: Node
var selected := -1  # the selected host's id (bridge/hosts.js: its lowest company's id), or -1
var also: Array[int] = []  # hosts shift- or Cmd-clicked or boxed in beside it: each takes the same orders (Warcraft III's group)
var _also_rings := {}  # id -> its ring
var _aim := ""  # an order waiting for the King to click where (its row's aim: march, attack, besiege, garrison)
var _card: PanelContainer
var _title: Label
var _status: Label
var _buttons := {}  # order -> its Button on the card
var _left: Label  # how many orders are left this season
var _doing_l: Label  # its current order, on a line of its own
var _kinds: Label  # its companies by kind and its morale (Warcraft III's unit panel; Total War's unit cards)
var _ring: Decal
var _end: Decal  # the ring where the selected host is bound
var _glow: OmniLight3D
var _dots_sel: MultiMeshInstance3D  # the selected host's route
var _dots_rest: MultiMeshInstance3D  # every other host's route, fainter
var _right_at := Vector2.INF  # where a right-click went down while a host is selected
var _facing := false  # the right button is drawing the line the host will form on
var _ghosts: MultiMeshInstance3D  # a mark per company along that line
var _t := 0.0
var _box_from := Vector2.INF  # where a Cmd- or Shift-press went down on the land: a drag from here is a selection box
var _box_to := Vector2.INF
var _boxing := false  # the drag went far enough to be a box, not a click
var _box_add := false  # Shift was held: the box adds to those selected
var _boxed := false  # the box was let go: the camera's click on its release is not a click on the land
var _eat_release := false  # a double-click on a standard took its press: its release is no click either
var _press_add := false  # the press under the coming click held Shift or Cmd: add or take out, not select anew
var _overlay: Control  # the box and the word by the pointer, over the world
var _word: Label  # what a right-click will do here, by the pointer (Warcraft III's cursor; words, not a colour)
var _hint: Label  # the card's line: what a right-click will do right now
var _hover := []  # [kind, words] of a right-click where the pointer is, or []
var _hover_px := Vector2.INF  # where it was last read
var _pending := {}  # host id -> {to, kind, ms}: an order given, drawn at once until /world shows it (or it is refused)
var _groups := {}  # 1..9 -> the host ids Cmd+number put in it (StarCraft's control groups); in memory, for this sitting
var _group_last := -1  # the group number last pressed, and when (msec): pressed twice quickly, the view goes there
var _group_ms := 0
var _idle_last := -1  # the idle host the idle key went to last: the next press goes on from it


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
	# The interface is raised after the realm (the title, then the chronicle's start): the card waits for it, or it
	# was never built and a selected host showed no orders (Mac: "I've selected the host, what do I do now?").
	while main.ui == null:
		await get_tree().process_frame
	_build_card()
	_build_overlay()
	add_child(load("res://scripts/battle_card.gd").new(main))  # the King's battles, when they are over (battle_card.gd)
	if main and main.ui and main.ui.get("army_bar"):
		main.ui.army_bar.attach(self)  # the armies bar down the left edge (army_bar.gd)


# --- what the bridge says --------------------------------------------------------------------

## The crown's hosts as the mirror holds them (bridge/hosts.js list()).
func hosts() -> Array:
	if main == null or main.awareness == null:
		return []
	return main.awareness.hosts()


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


## Where a host stands in the world (its banner, its lead man, else its tile).
func ground_of(id: int) -> Vector3:
	return _ground(host(id))


## The host's men on screen: the rectangle round where each company stands, widened by a company's own breadth
## (host_command.json company_reach, world units) as the lens sees it; empty when none is in view. Positions, not
## mesh bounds: a host drawn in bulk has one mesh whose bounds span the land (Mac: "where is the host?").
func screen_rect_of(id: int, cam: Camera3D) -> Rect2:
	var out := Rect2()
	var any := false
	var reach := Data.num(FILE, "company_reach", 3.0)
	for u in host(id).get("units", []):
		var f: Node3D = main.units.figure_of(int(u))
		if f == null or not is_instance_valid(f) or not f.is_visible_in_tree():
			continue
		var at := f.global_position
		if cam.is_position_behind(at):
			continue
		var c := cam.unproject_position(at)
		var r := c.distance_to(cam.unproject_position(at + cam.global_transform.basis.x * reach))
		var box := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		out = box if not any else out.merge(box)
		any = true
	return out


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
	if _boxed:
		_boxed = false
		return true  # the release of a selection box
	if _aim != "":
		var kind := _aim
		_set_aim("")
		var foe := _pressed_foe
		if kind == "attack" and foe.is_empty():
			# Attack, then open ground: Warcraft III's attack-move. The host advances there and falls on any foe it meets
			# on the road, then marches on (bridge hosts.js advance).
			kind = "advance"
		order(kind, {"ground": _foe_at(foe, ground) if kind == "attack" else ground})
		return true
	var got := _pressed
	_pressed = {}
	var h := _host_of(int(got.get("unit", -1))) if not got.is_empty() else {}
	if not h.is_empty() and selected >= 0 and _press_add:
		_toggle(int(h["id"]))  # shift- or Cmd-click: in beside the selected host, or out again
		return true
	if not h.is_empty():
		select(int(h["id"]))
		main.barks.host("select", int(h["id"]))  # its captain answers, curt by the fourth click (barks.gd; Warcraft II)
		var view: Variant = got.get("view")
		if view is Node and (view as Node).has_method("select"):
			(view as Node).select(int(got["unit"]))  # army.gd: that regiment's rectangle and banner
		return true
	if selected >= 0 and not _press_add:
		select(-1)  # the land elsewhere: the host is let go, and the click picks a town as before (Shift or Cmd keeps them)
	return false


## What the press under a left click met (host_pick.gd: the physics ray at the press, the camera as it was then, or
## the King's standard nearest it within pick_px): {unit, view}, or {} for the land. take_click uses it once.
var _pressed := {}
var _pressed_foe := {}  # the foe's men nearest the same press within foe_px, for an Attack waiting for its place


## One of the King's hosts added beside those selected, or taken out again (Warcraft III's shift-click). The selected
## one taken out hands the lead to the next.
func _toggle(id: int) -> void:
	if id == selected:
		if also.is_empty():
			select(-1)
			return
		var rest := also.duplicate()
		select(int(rest.pop_front()))
		also.assign(rest)
	elif also.has(id):
		also.erase(id)
	else:
		also.append(id)
		main.barks.host("select", id)
	_refresh()
	selection_changed.emit()


## One host selected from the interface (the armies bar): as a click on its standard, its captain answering.
func pick(id: int) -> void:
	select(id)
	if selected == id:
		main.barks.host("select", id)


## Shift- or Cmd-click from the interface: in beside those selected, or out again; with none selected, selected.
func toggle(id: int) -> void:
	if selected < 0:
		pick(id)
	else:
		_toggle(id)


## The King's own click to go (the armies bar's double-click): the view glides to where these hosts stand, their middle.
func fly_to(ids: Array) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for id in ids:
		var h := host(int(id))
		if not h.is_empty():
			sum += _ground(h)
			n += 1
	if n > 0 and main.rig:
		main.rig.focus(sum / float(n))


## Several of the King's hosts at once (a box, a double-click, F2): the first leads (`selected`), the rest beside it
## (`also`); with `add`, in beside those already selected. None given: nothing changes.
func select_many(ids: Array, add := false) -> void:
	var group: Array[int] = []
	if add and selected >= 0:
		group.append(selected)
		group.append_array(also)
	for id in ids:
		if not group.has(int(id)) and not host(int(id)).is_empty():
			group.append(int(id))
	if group.is_empty():
		return
	var lead := group[0]
	if lead != selected:
		select(lead)
		main.barks.host("select", lead)
	also.assign(group.slice(1))
	_refresh()
	selection_changed.emit()


## The King's hosts whose standard stands inside `rect` on screen (in front of the lens), largest first as listed.
func _hosts_in(rect: Rect2) -> Array:
	var cam := get_viewport().get_camera_3d()
	var out := []
	if cam == null:
		return out
	for h in hosts():
		var b := _banner(h)
		var at: Vector3 = b.global_position if b else _ground(h)
		if not cam.is_position_behind(at) and rect.has_point(cam.unproject_position(at)):
			out.append(int(h.get("id", -1)))
	return out


## A unit of the King's own hosts (a left click looks for these).
func _is_mine(unit: int) -> bool:
	return not _host_of(unit).is_empty()


## A unit of another's, not the crown's own (a right-click falls on these; the bridge says no to a sworn house's).
func _is_foe(unit: int) -> bool:
	var u := _unit(unit)
	return not u.is_empty() and int(u.get("owner", -1)) != int(main.awareness.rec("crownId", -1)) and not _is_mine(unit)


func _unit(id: int) -> Dictionary:
	for u in main.awareness.rec("units", []):
		if int((u as Dictionary).get("id", -2)) == id:
			return u
	return {}


## Where the picked foe's men stand (else `g`, the land under the pointer).
func _foe_at(picked: Dictionary, g: Vector3) -> Vector3:
	var f: Node3D = main.units.figure_of(int(picked.get("unit", -1))) if not picked.is_empty() else null
	return f.global_position if f and is_instance_valid(f) else g


## Whose men a foe's unit is, in the card's words (host_command.json hover.foe / hover.raiders).
func _foe_words(unit: int) -> String:
	var k: Dictionary = Data.value(FILE, "hover", {})
	if main.awareness.rival_raiders().has(unit):
		return String(k.get("raiders", "the raiders"))
	var house: Dictionary = main.awareness.houses_by_id().get(int(_unit(unit).get("owner", -1)), {})
	if house.is_empty() or bool(house.get("wild", false)):
		return String(k.get("raiders", "the raiders"))
	return String(k.get("foe", "{house}'s men")).format({"house": String(house.get("name", ""))})


## The host a company belongs to ({} when it is in none of the King's).
func _host_of(unit: int) -> Dictionary:
	for h in hosts():
		if (h.get("units", []) as Array).has(unit) or int(h.get("id", -2)) == unit:
			return h
	return {}


## Selects a host (or none, -1): the ring, the glow and the card follow it.
func select(id: int) -> void:
	selected = id
	also.clear()
	_set_aim("")
	var h := host(id)
	if h.is_empty():
		selected = -1
	for n in get_tree().get_nodes_in_group(&"host_views"):
		if n.has_method("select_host"):
			n.select_host(h)
	if selected < 0 and _word:
		_show_hover([], Vector2.ZERO)
	_hover_px = Vector2.INF
	_refresh()
	selection_changed.emit()


## A left press: what it met is kept for take_click (host_pick.gd). With Cmd or Shift held on the land, a drag is a
## selection box (StarCraft's, Warcraft III's), drawn and taken here ahead of the camera, whose plain left-drag still
## grabs and moves the view (Mac plays on a trackpad: click-drag and the two-finger swipe pan). A double-click on one
## of the King's standards takes every one of his hosts on screen. The right button while a host is selected, ahead of
## the camera (whose right-drag turns the view): a click gives the order what it lands on asks for (_intent; or lets a
## waiting order go, Warcraft III), a drag draws the line the host forms on (Total War). Over the interface it is the
## interface's. With a host selected and no button held, the pointer says what a right-click would do (_hover_read).
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_boxed = false
			var cam := get_viewport().get_camera_3d()
			_pressed = HostPick.pick(cam, event.position, Data.num(FILE, "pick_px", 24.0), _is_mine)  # resolved at its press
			_pressed_foe = HostPick.pick(cam, event.position, Data.num(FILE, "foe_px", 40.0), _is_foe) if _aim == "attack" else {}
			_press_add = event.shift_pressed or event.is_command_or_control_pressed()
			if get_viewport().gui_get_hovered_control() != null:
				return
			if event.double_click and not _pressed.is_empty():
				select_many(_hosts_in(get_viewport().get_visible_rect()), _press_add)  # every one of the King's hosts on screen
				_pressed = {}
				_eat_release = true
				get_viewport().set_input_as_handled()
				return
			if _press_add and _aim == "":
				_box_from = event.position  # a drag from here is a box; a click stays a click (add or take out)
				_box_to = event.position
				_boxing = false
				_box_add = event.shift_pressed  # Shift adds to those selected; Cmd alone selects anew
			return
		if _eat_release:
			_eat_release = false
			get_viewport().set_input_as_handled()
			return
		if _box_from != Vector2.INF:
			var rect := Rect2(_box_from, Vector2.ZERO).expand(event.position).grow(Data.num(FILE, "box.grow_px", 6.0))
			var was_box := _boxing
			_box_from = Vector2.INF
			_boxing = false
			_overlay.queue_redraw()
			if was_box:
				# The camera still hears the release (it ends its own press) and calls it a click: take_click lets it pass.
				_boxed = true
				select_many(_hosts_in(rect), _box_add)
			return
	if event is InputEventMouseMotion and _box_from != Vector2.INF and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_box_from = Vector2.INF  # let go where this view never heard it (outside the window): no box left hanging
		_boxing = false
		_overlay.queue_redraw()
	if event is InputEventMouseMotion and _box_from != Vector2.INF:
		get_viewport().set_input_as_handled()  # a Cmd- or Shift-drag never moves the view
		_box_to = event.position
		if not _boxing and _box_from.distance_to(event.position) >= Data.num(FILE, "box.drag_px", 6.0):
			_boxing = true
		_overlay.queue_redraw()
		return
	if selected < 0:
		return
	if event is InputEventMouseMotion and _right_at == Vector2.INF:
		_hover_read(event.position)
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
				order("march", {"ground": line[0], "face": line[1]})
			return
		if _aim != "":
			_set_aim("")
			return
		var g: Vector3 = main.rig._ground_under(event.position)
		if g != Vector3.INF:
			var smart := _intent(HostPick.pick(get_viewport().get_camera_3d(), event.position, Data.num(FILE, "foe_px", 40.0), _is_foe), g)
			order(String(smart[0]), {"ground": smart[1]})
	elif event is InputEventMouseMotion and _right_at != Vector2.INF:
		get_viewport().set_input_as_handled()
		if not _facing and _right_at.distance_to(event.position) < Data.num(FILE, "face.drag_px", 14.0):
			return
		_facing = true
		_show_line(_right_at, event.position)


## What a right-click at `screen` would do now, read as the pointer moves (Warcraft III's cursor over a foe, Age of
## Empires' too): the card's line says it in full, the word by the pointer in one, and over a foe's men or town the
## pointer is the order's icon. Over the interface the pointer is the interface's; the card's line keeps the last.
func _hover_read(screen: Vector2) -> void:
	if _hover_px != Vector2.INF and _hover_px.distance_to(screen) < 3.0:
		_word.position = screen + Vector2(18, 14)
		return
	_hover_px = screen
	var g: Vector3 = main.rig._ground_under(screen) if get_viewport().gui_get_hovered_control() == null else Vector3.INF
	if g == Vector3.INF:
		_show_hover([], screen)
		return
	var picked := HostPick.pick(get_viewport().get_camera_3d(), screen, Data.num(FILE, "foe_px", 40.0), _is_foe)
	var smart := _intent(picked, g)
	if _aim != "":  # an order waiting for its place: the click is that order's (an attack on open ground advances)
		var kind := ("advance" if picked.is_empty() else "attack") if _aim == "attack" else _aim
		var town_words := String(smart[2]) if String(smart[0]) in ["relieve", "besiege"] else ""
		smart = [kind, g, String(smart[2]) if kind == "attack" else (town_words if kind != "march" else "")]
	_show_hover([String(smart[0]), String(smart[2])], screen)


func _show_hover(now: Array, screen: Vector2) -> void:
	var k: Dictionary = Data.value(FILE, "hover", {})
	var kind := String(now[0]) if not now.is_empty() else ""
	_word.visible = kind != ""
	_word.position = screen + Vector2(18, 14)
	if kind != "":
		_word.text = String((k.get("word", {}) as Dictionary).get(kind, kind.capitalize()))
		var line := String((k.get("aim_line" if _aim != "" else "line", {}) as Dictionary).get(kind, "")).format({"who": String(now[1])})
		if _hint.text != line:
			_hint.text = line
	var was := String(_hover[0]) if not _hover.is_empty() else ""
	_hover = now
	if _aim == "" and kind != was:
		var icon_kind := kind if kind in ["attack", "besiege"] else ""  # over a foe the pointer is the sword or the tower
		Input.set_custom_mouse_cursor(_cursor(icon_kind) if icon_kind != "" else null, Input.CURSOR_ARROW, _cursor_hot())


## What a right-click on `g` asks of the selected host, read from what stands there (Warcraft III's smart order: no
## menu, the target decides): a foe's company or raiders under the pointer (`picked`, host_pick.gd) is attacked where it
## stands; a town of the crown's or a sworn house's is relieved; any other town is besieged (bridge hosts.js relieve and
## besiege, 4cbad5ff); the open ground is marched to. [order, the world point it is given at, whom or where in words].
func _intent(picked: Dictionary, g: Vector3) -> Array:
	if not picked.is_empty() and _is_foe(int(picked["unit"])):
		return ["attack", _foe_at(picked, g), _foe_words(int(picked["unit"]))]
	var town: Dictionary = main.towns.nearest(g, Data.num(FILE, "town_reach", 3.0))
	if town.is_empty():
		return ["march", g, ""]
	return ["relieve" if _friendly(int(town.get("owner", -1)), int(town.get("id", -1))) else "besiege", g, String(town.get("name", ""))]


## A town the King's men may enter as friends: the crown's own, or the seat of a bannerman sworn to it (/world vassals).
func _friendly(owner: int, town: int) -> bool:
	if owner == int(main.awareness.rec("crownId", -1)):
		return true
	for vs in main.awareness.rec("vassals", []):
		if int((vs as Dictionary).get("town", -2)) == town:
			return true
	return false


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
	if not event.is_pressed() or event.is_echo():
		return
	for n in range(1, 10):
		if event.is_action_pressed(StringName("group_%d" % n)):
			if event is InputEventWithModifiers and (event as InputEventWithModifiers).is_command_or_control_pressed():
				_make_group(n)
			else:
				_call_group(n)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed(&"next_idle"):
		_next_idle()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"host_all"):
		var ids := []
		for h in hosts():
			ids.append(int(h.get("id", -1)))
		select_many(ids)  # every one of the King's hosts (StarCraft II's select army); the view stays where it is
		get_viewport().set_input_as_handled()
		return
	if selected < 0:
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


## Cmd+number: the hosts selected now are group n (none selected: the group is emptied). A host may be in several.
func _make_group(n: int) -> void:
	var ids: Array[int] = []
	if selected >= 0:
		ids.append(selected)
		ids.append_array(also)
	_groups[n] = ids
	var k: Dictionary = Data.value("army_bar", "groups", {})
	if main.ui:
		var words := String(k.get("cleared", "")) if ids.is_empty() else String(k.get("one" if ids.size() == 1 else "some", ""))
		main.ui.toast(words.format({"n": n, "count": ids.size()}))
	selection_changed.emit()  # the armies bar shows the number on each host's button


## The number: group n selected; pressed again quickly (army_bar.json groups.twice_s), the view goes to it as well.
func _call_group(n: int) -> void:
	var ids := []
	for id in _groups.get(n, []):
		if not host(int(id)).is_empty():
			ids.append(int(id))
	if ids.is_empty():
		if main.ui:
			main.ui.toast(String((Data.value("army_bar", "groups", {}) as Dictionary).get("empty", "")).format({"n": n}))
		return
	var now := Time.get_ticks_msec()
	var twice := _group_last == n and now - _group_ms <= int(Data.num("army_bar", "groups.twice_s", 0.4) * 1000.0)
	_group_last = n
	_group_ms = now
	select_many(ids)
	if twice:
		fly_to(ids)


## The idle key (Age of Empires' idle soldier): the next of the King's hosts with no orders, after the one it went to
## last, is selected and the view goes to it. None idle: the King is told so.
func _next_idle() -> void:
	var idle := []
	for h in hosts():
		if not (h.get("order") is Dictionary) and not _pending.has(int(h.get("id", -1))):  # an order just given is not idle
			idle.append(int(h.get("id", -1)))
	if idle.is_empty():
		if main.ui:
			main.ui.toast(String((Data.value("army_bar", "idle", {}) as Dictionary).get("none", "")))
		return
	var at := idle.find(_idle_last)
	_idle_last = int(idle[(at + 1) % idle.size()])
	pick(_idle_last)
	fly_to([_idle_last])


## The lowest group a host is in (its number on the armies bar), or 0.
func group_of(id: int) -> int:
	for n in range(1, 10):
		if (_groups.get(n, []) as Array).has(id):
			return n
	return 0


## An order from the card (a click or its key).
func _press(kind: String) -> void:
	if selected < 0:
		return
	if _row(kind).get("aim", false):
		_set_aim("" if _aim == kind else kind)
		return
	_set_aim("")
	order(kind)


## Orders the King may still give the selected host this season (each host its own: /world hosts[].ordersLeft, the
## bridge reads hosts.json ordersPerHost), -1 while the bridge hasn't said or none is selected.
func orders_left() -> int:
	var h: Dictionary = host(selected) if selected >= 0 else {}
	return int(h.get("ordersLeft", -1)) if h.get("ordersLeft") != null else -1


## An order's row on the card (host_command.json orders), or {}.
static func _row(kind: String) -> Dictionary:
	for o in Data.value(FILE, "orders", []):
		if String(o.get("order", "")) == kind:
			return o
	return {}


## The one way an order is given (the card, its keys, a right-click or a drag, the film's play step): to the
## selected host, never another; with none selected nothing is asked (false). at: where, as {city} or {x, y} (tiles),
## or {ground} (a world point: into the town there when one is near, else its tile; an attack is on what stands there,
## so always the tile: the bridge finds the foe on it), and {face}. done(code, said) once the bridge has answered.
func order(kind: String, at := {}, done := Callable()) -> bool:
	if selected < 0 or host(selected).is_empty() or orders_left() == 0:
		return false
	var body := {"host": selected, "order": String(_row(kind).get("send", kind))}  # the bridge's name for it
	if at.has("ground"):
		var ground: Vector3 = at["ground"]
		_mark(ground, kind)
		var town: Dictionary = {} if kind == "attack" else main.towns.nearest(ground, Data.num(FILE, "town_reach", 3.0))
		if not town.is_empty():
			body["city"] = int(town.get("id", -1))
		else:
			var tile: Vector2i = main.terrain.paths.tile_of(ground)
			body["x"] = tile.x
			body["y"] = tile.y
	for k in ["city", "x", "y"]:
		if at.has(k):
			body[k] = int(at[k])
	if at.has("face"):
		body["face"] = at["face"]
	if at.get("defend", false):
		body["defend"] = true  # to a raided town's aid, never a siege of it (bridge hosts.js march)
	ordered.emit(kind)
	main.barks.host("order", selected)  # its captain answers at once, as Warcraft III's do (barks.gd)
	_ask(body, done)
	_routes()
	for id in also:  # the hosts shifted in beside it: the same order, each asked for itself (its own orders this season)
		var h := host(id)
		if not h.is_empty() and int(h.get("ordersLeft", 1)) != 0:
			var b := body.duplicate()
			b["host"] = id
			_ask(b)
	return true


## Asks the bridge; it decides, and says so (the toast), and the next /world shows the host's order.
func _ask(body: Dictionary, done := Callable()) -> void:
	main.bridge._post("/host/order", body, func(code: int, d: Dictionary) -> void:
		var said := String(d.get("text", d.get("error", "")))
		if said != "" and main.ui:
			main.ui.toast(said)
		if code != 200:
			_pending.erase(int(body.get("host", -1)))  # refused: the road drawn for it goes
		if code == 200:
			main.sound.ordered(String(body.get("order", "")))  # heard as it sets off (sounds.json orders)
			main.units.ack(int(body.get("host", -1)))  # and its men raise a cry where they stand (army.gd ack)
			main.bridge._poll()
		if done.is_valid():
			done.call(code, said))


func _set_aim(kind: String) -> void:
	_aim = kind
	_hover = []  # the pointer's word and icon are read again for what the click now does
	_hover_px = Vector2.INF
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if kind != "" else Input.CURSOR_ARROW)
	# Warcraft III's order cursor: while an order waits for its place, the pointer is that order's own icon (the card's),
	# in the accent for a march or a garrison, red for an attack or a siege, so the King sees what his next click does.
	Input.set_custom_mouse_cursor(_cursor(kind) if kind != "" else null, Input.CURSOR_ARROW, _cursor_hot())
	Input.set_custom_mouse_cursor(_cursor(kind) if kind != "" else null, Input.CURSOR_CROSS, _cursor_hot())
	for k in _buttons:
		(_buttons[k] as Button).set_pressed_no_signal(k == kind)


# --- in the world ----------------------------------------------------------------------------

func _process(delta: float) -> void:
	var h := host(selected) if selected >= 0 else {}
	if selected >= 0 and h.is_empty() and not hosts().is_empty():
		select(-1)  # the host is no more (fallen, or joined another)
	_ring.visible = not h.is_empty()
	_rings_also()
	_glow.visible = false
	if not h.is_empty():
		var at := _ground(h)
		var r := minf(Data.num(FILE, "ring.max", 1.6), Data.num(FILE, "ring.radius", 0.55) + Data.num(FILE, "ring.per_company", 0.06) * float(h.get("companies", 1)))
		r = maxf(r, _seen_at(Data.num(FILE, "ring.screen", 0.0)))  # never smaller than so much of the view: read at play zoom
		_ring.global_position = at
		_ring.modulate = _crown_colour()
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


## A ring under each host shifted in beside the selected one, in the same colour, a little fainter; gone hosts drop out.
func _rings_also() -> void:
	for id in also.duplicate():
		if host(id).is_empty():
			also.erase(id)
	for id in _also_rings.keys():
		if not also.has(id):
			(_also_rings[id] as Decal).queue_free()
			_also_rings.erase(id)
	for id in also:
		var d: Decal = _also_rings.get(id)
		if d == null:
			d = _decal(_ring_texture(), Data.num(FILE, "ring.energy", 1.6) * 0.75)
			_also_rings[id] = d
		var h := host(id)
		var r := maxf(minf(Data.num(FILE, "ring.max", 1.6), Data.num(FILE, "ring.radius", 0.55) + Data.num(FILE, "ring.per_company", 0.06) * float(h.get("companies", 1))), _seen_at(Data.num(FILE, "ring.screen", 0.0)))
		d.global_position = _ground(h)
		d.size = Vector3(r * 2.0, 1.2, r * 2.0)
		d.modulate = _crown_colour()
		d.visible = true


## The dotted road to where each host is bound: bright for the selected one, faint for the rest.
func _routes() -> void:
	var sel: Array[Vector3] = []
	var rest: Array[Vector3] = []
	var every := maxf(0.1, Data.num(FILE, "route.every", 0.55))
	var lift := Data.num(FILE, "route.lift", 0.04)
	_end.visible = false
	var fresh := Time.get_ticks_msec() - int(Data.num(FILE, "route.pending_s", 4.0) * 1000.0)
	for id in _pending.keys():
		if int(_pending[id]["ms"]) < fresh:
			_pending.erase(id)
	for h in hosts():
		var o: Variant = h.get("order")
		var given: Dictionary = _pending.get(int(h.get("id", -1)), {})
		if not given.is_empty():
			o = {"kind": given["kind"], "x": 0, "y": 0}  # just ordered: drawn to where the King pointed until /world has it
		if not (o is Dictionary) or o.get("x") == null or o.get("y") == null:
			continue
		var to: Vector3 = given["to"] if not given.is_empty() else main.terrain.world_pos(float(o["x"]), float(o["y"]))
		var from := _ground(h)
		var flat := Vector2(to.x - from.x, to.z - from.z)
		if flat.length() < every:
			continue
		var mine := int(h.get("id", -1)) == selected
		if mine:
			var r := maxf(Data.num(FILE, "route.end_ring", 0.35), _seen_at(Data.num(FILE, "route.end_screen", 0.0)))
			_end.global_position = to
			_end.modulate = _order_colour(String(o.get("kind", "march")))
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


var _cursors := {}  # order -> its cursor image


## An order's cursor (host_command.json cursor): its card icon at size px, filled in the accent (red for an attack or a
## siege, as its marker), on a dark rim so it reads on grass and on snow.
func _cursor(kind: String) -> Texture2D:
	if _cursors.has(kind):
		return _cursors[kind]
	var k: Dictionary = Data.value(FILE, "cursor", {})
	var px := int(k.get("size", 32))
	var tex: Texture2D = main.ui.icon(String(_row(kind).get("icon", "play")))
	var src: Image = tex.get_image() if tex else null
	if src == null:
		return null
	src = src.duplicate()
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var rim := int(k.get("rim", 2))
	src.resize(px - rim * 2, px - rim * 2, Image.INTERPOLATE_BILINEAR)
	var fill: Color = T.DANGER if kind in ["attack", "besiege"] else T.ACCENT
	var out := Image.create(px, px, false, Image.FORMAT_RGBA8)
	for y in px:
		for x in px:
			var a := 0.0
			var near := 0.0
			for dy in range(-rim, rim + 1):
				for dx in range(-rim, rim + 1):
					var sx := x - rim + dx
					var sy := y - rim + dy
					if sx >= 0 and sy >= 0 and sx < src.get_width() and sy < src.get_height():
						near = maxf(near, src.get_pixel(sx, sy).a)
			if x - rim >= 0 and y - rim >= 0 and x - rim < src.get_width() and y - rim < src.get_height():
				a = src.get_pixel(x - rim, y - rim).a
			var c := Color(0.08, 0.06, 0.05, near).lerp(Color(fill, 1.0), a)
			out.set_pixel(x, y, c)
	var made := ImageTexture.create_from_image(out)
	_cursors[kind] = made
	return made


func _cursor_hot() -> Vector2:
	var px := float((Data.value(FILE, "cursor", {}) as Dictionary).get("size", 32))
	return Vector2(px, px) * 0.5


## Where an order was given, a ring flashed on the ground that closes and fades (Warcraft III's command marker):
## green for a march, red for an attack or a siege, gold for a relief (host_command.json marker colors).
func _mark(at: Vector3, kind: String) -> void:
	var k: Dictionary = Data.value(FILE, "marker", {})
	var d := _decal(_ring_texture(), float(k.get("energy", 2.0)))
	d.modulate = _order_colour(kind)
	d.global_position = at
	d.visible = true
	var from := maxf(float(k.get("from", 0.7)), _seen_at(float(k.get("screen", 0.0))))  # as wide on screen at any zoom
	var to := from * float(k.get("to", 0.25)) / maxf(0.01, float(k.get("from", 0.7)))
	d.size = Vector3(from, 1.2, from)
	var tw := d.create_tween().set_parallel()
	tw.tween_property(d, "size", Vector3(to, 1.2, to), float(k.get("secs", 0.6))).set_ease(Tween.EASE_OUT)
	tw.tween_property(d, "modulate:a", 0.0, float(k.get("secs", 0.6))).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(d.queue_free)


## An order's colour (host_command.json marker.colors: green to march, red to attack or besiege, Warcraft III).
func _order_colour(kind: String) -> Color:
	var k: Dictionary = Data.value(FILE, "marker", {})
	return Color.from_string(String((k.get("colors", {}) as Dictionary).get(kind, k.get("color", "#dbb56e"))), T.ACCENT)


## The crown's colour (team_colour.gd, as its men and roofs wear it), else the ring's own.
func _crown_colour() -> Color:
	var house: Dictionary = main.awareness.houses_by_id().get(int(main.awareness.rec("crownId", -1)), {})
	return TeamColour.house_colour(house) if not house.is_empty() else Color.from_string(String(Data.value(FILE, "ring.color", "#dbb56e")), T.ACCENT)


## A world size that is `share` of the lens's distance (camera_rig.distance): a mark that keeps its size on screen.
func _seen_at(share: float) -> float:
	return share * float(main.rig.distance) if main.rig else 0.0


## A ground ring painted on the land as it lies (a decal: it follows hills and roads).
func _decal(tex: Texture2D, energy: float) -> Decal:
	var d := Decal.new()
	d.texture_albedo = tex
	d.texture_emission = tex
	d.emission_energy = energy
	d.modulate = Color.from_string(String(Data.value(FILE, "ring.color", "#dbb56e")), T.ACCENT)
	d.cull_mask = Terrain.GROUND_LAYER  # on the land alone, never on the men it rings (army.gd's rectangle does the same)
	d.upper_fade = 0.15
	d.lower_fade = 0.3
	d.visible = false
	add_child(d)
	return d


## A thin bright ring on a clear field, drawn from a radial gradient (no art file). The clear field is black as well as
## transparent: the decal's emission reads the texture's colour and not its alpha, so a white clear field lit the whole
## decal box (group test g1's command frame: a gold square over the host, its figure washed out inside it).
static func _ring_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.76, 0.82, 0.93, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(0, 0, 0, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 256
	t.height = 256
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	return t


# --- the command card (bottom right, over the minimap) ---------------------------------------

## The selection box and the word by the pointer, over the world and under the panels (screen space).
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_box)
	layer.add_child(_overlay)
	_word = T.label("", T.TEXT)
	_word.add_theme_font_size_override("font_size", T.SIZE_DESC)
	_word.add_theme_color_override("font_outline_color", Color(0.06, 0.05, 0.04, 0.9))
	_word.add_theme_constant_override("outline_size", 5)
	_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_word.visible = false
	_overlay.add_child(_word)


## A thin white rectangle on a dark outline (host_command.json box), from where the drag began to the pointer.
func _draw_box() -> void:
	if not _boxing or _box_from == Vector2.INF:
		return
	var k: Dictionary = Data.value(FILE, "box", {})
	var r := Rect2(_box_from, Vector2.ZERO).expand(_box_to)
	_overlay.draw_rect(r, Color(0.05, 0.04, 0.03, float(k.get("outline_alpha", 0.8))), false, float(k.get("outline", 3.0)))
	_overlay.draw_rect(r, Color(1, 1, 1, float(k.get("alpha", 0.95))), false, float(k.get("line", 1.0)))


func _build_card() -> void:
	if main == null or main.ui == null:
		return
	# What is selected, in the control plane's middle (Mac 2026-11-16: "we need a control plane, where I can take action
	# ... bottom of the screen"; Warcraft III's console: the selected unit's name and state, its command card beside).
	_card = main.ui.ControlPlane.bare(PanelContainer.new())
	main.ui.plane.select_slot.add_child(_card)
	var both := HBoxContainer.new()
	both.add_theme_constant_override("separation", T.GAP * 2)
	_card.add_child(both)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_TIGHT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	both.add_child(v)
	_title = T.label("The royal host", T.TEXT_2)
	v.add_child(_title)
	_status = T.prose("", T.SIZE_DESC, T.TEXT)
	v.add_child(_status)
	_doing_l = T.prose("", T.SIZE_DESC, T.ACCENT)  # what it is doing now, in the accent: the order at first sight
	v.add_child(_doing_l)
	_kinds = T.label("", T.TEXT_2)
	v.add_child(_kinds)
	_left = T.label("", T.TEXT_3)
	v.add_child(_left)
	_hint = T.label("", T.TEXT)  # what a right-click on the land does right now (_hover_read), in words
	v.add_child(_hint)
	# Its orders, a grid beside it (Warcraft III's command card).
	var row := GridContainer.new()
	row.columns = int(Data.num(FILE, "order_columns", 4.0))
	row.add_theme_constant_override("h_separation", T.GAP_TIGHT)
	row.add_theme_constant_override("v_separation", T.GAP_TIGHT)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	both.add_child(row)
	for o in Data.value(FILE, "orders", []):
		var kind := String(o.get("order", ""))
		var action := "host_" + kind
		var key := Keys.label(action) if InputMap.has_action(StringName(action)) else ""
		var b: Button = main.ui.icon_btn(String(o.get("icon", "play")), String(o.get("tip", kind.capitalize())) + ("  (%s)" % key if key != "" else ""))
		# Its word under its icon (Age of Empires IV's command grid): Mac reads the order, not a glyph; its key in the tip.
		b.text = String(o.get("word", kind.capitalize()))
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_font_size_override("font_size", T.SIZE_LABEL)
		b.add_theme_constant_override("icon_max_width", 20)
		b.custom_minimum_size = Vector2(Data.num(FILE, "order_size.x", 68.0), Data.num(FILE, "order_size.y", 52.0))
		b.set_meta("tip", b.tooltip_text)
		b.toggle_mode = bool(o.get("aim", false))
		b.pressed.connect(_press.bind(kind))
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
	_status.text = String(Data.value(FILE, "troops", "{men} troops")).format({"men": main.ui.heads(int(h.get("men", 0)))})
	var doing := _doing(h)
	_doing_l.text = doing.left(1).to_upper() + doing.substr(1)
	var o: Variant = h.get("order")
	_doing_l.add_theme_color_override("font_color", _order_colour(String(o.get("kind", ""))) if o is Dictionary else T.TEXT_2)
	_card.tooltip_text = "%d companies" % int(h.get("companies", 0))
	_kinds.text = _makeup(h)
	if not also.is_empty():  # several selected: how many, and all their men and companies (Warcraft III's group card)
		var men := int(h.get("men", 0))
		var kinds: Dictionary = (h.get("kinds", {}) as Dictionary).duplicate() if h.get("kinds") is Dictionary else {}
		for id in also:
			var o2 := host(id)
			men += int(o2.get("men", 0))
			var k2: Variant = o2.get("kinds")
			if k2 is Dictionary:
				for t in k2:
					kinds[t] = int(kinds.get(t, 0)) + int(k2[t])
		_title.text = String(Data.value(FILE, "group", "{n} hosts")).format({"n": also.size() + 1}).to_upper()
		_status.text = String(Data.value(FILE, "troops", "{men} troops")).format({"men": main.ui.heads(men)})
		_kinds.text = _makeup({"kinds": kinds, "morale": h.get("morale")})
	if _hint.text == "":
		_hint.text = String((Data.value(FILE, "hover", {}) as Dictionary).get("idle", ""))
	# The host's orders this season (bridge hosts.json ordersPerHost): the card says how many it has left, and with none its
	# buttons are greyed with the reason rather than looking live and refusing.
	var left := orders_left()
	var texts: Dictionary = Data.value(FILE, "left", {})
	_left.visible = left >= 0
	_left.text = String(texts.get("none" if left == 0 else ("one" if left == 1 else "some"), "")).replace("{n}", str(left))
	for k in _buttons:
		var b: Button = _buttons[k]
		b.disabled = left == 0
		b.tooltip_text = String(texts.get("why", "")) if left == 0 else String(b.get_meta("tip", b.tooltip_text))


## The host's companies by kind (/world hosts[].kinds, {Freeciv type: companies}, bridge ad5b638a; host_command.json
## card.kinds naming each) and its morale in a word (/world hosts[].morale 0..1; card.morale bands, highest first).
func _makeup(h: Dictionary) -> String:
	var k: Dictionary = Data.value(FILE, "card", {})
	var names: Dictionary = k.get("kinds", {})
	var count: Dictionary = h.get("kinds", {}) if h.get("kinds") is Dictionary else {}
	var parts := PackedStringArray()
	for t in count:
		var n := int(count[t])
		parts.append(String((k.get("company", ["{n} company of {kind}", "{n} companies of {kind}"]) as Array)[0 if n == 1 else 1]).format({"n": n, "kind": String(names.get(t, t))}))
	var m: float = float(h.get("morale", 1.0)) if h.get("morale") != null else -1.0
	var word := ""
	for band in k.get("morale", []):
		if m >= float(band[0]):
			word = String(band[1])
			break
	return " · ".join(parts) + ("  —  %s" % word if word != "" else "")


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


