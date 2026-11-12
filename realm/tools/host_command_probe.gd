extends SceneTree
## Headless check of commanding the King's host (READY.md lines 8 and 14; research army-and-town-rules.md section 1:
## Warcraft III's card and ring, Total War's regiment click and drag to face). host_command.gd on a stub realm (the
## mirror's one host, a bridge that records what it is asked, a town, flat ground under a camera looking down), every
## click through the viewport (push_input), as a player's. Asserts:
##   - the card has march, attack, besiege, hold and go home, each with its key;
##   - Attack waits for a click, then asks the bridge {order attack, host, x, y} where the foe stands (never a town);
##   - Besiege waits for a click, then asks the bridge's {order march, host, city} for the town clicked (a march on a
##     foe's town lays siege on arrival: bridge/hosts.js, campaigns.js; tools/besiege_order_probe.mjs takes it on);
##   - Hold and Go home are asked at once;
##   - a right-drag asks {order march, x, y, face}: the line's middle, facing up the screen for a left-to-right drag;
##     a right-click still marches, with no face;
##   - a click on one of a host view's regiments selects its host and marks that regiment;
##   - an order goes to the one selected host and no other (army command item 5; the milestone take's Besiege went to
##     a host nobody selected): with a second host in the field selected, the card's and the play step's (autoplay
##     `order`) Besiege ask for it alone; with none selected, nothing is asked; the play step gives orders only
##     through the card (host_command.order), never its own /host/order.
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/host_command_probe.gd

const HostCommand := preload("res://scripts/host_command.gd")
const Keys := preload("res://scripts/keys.gd")
const HOST := 7
const OTHER := 20  # a second host in the field, far from the first
const TOWN := {"id": 3, "x": 4.0, "y": 0.0}  # its centre at (4, 0, 0) on the ground


class Realm:
	var hosts: Array = [{"id": HOST, "x": 0, "y": 0, "companies": 4, "men": 2000, "units": [HOST, 8, 9, 10], "order": null},
		{"id": OTHER, "x": 9, "y": 9, "companies": 2, "men": 1000, "units": [OTHER, 21], "order": null}]
	func get_var(_k: StringName, _d: Variant = null, _c := false) -> Variant:
		return hosts


class Awareness:
	var realm := Realm.new()


class Bridge:
	var asked: Array = []
	var world := {}
	func _post(_path: String, body: Dictionary, cb: Callable) -> void:
		asked.append(body)
		cb.call(200, {"ok": true, "text": ""})
	func _poll() -> void:
		pass


class Towns:
	func nearest(p: Vector3, reach := INF) -> Dictionary:
		return TOWN if Vector2(p.x - 4.0, p.z).length() < reach else {}


class Terrain:
	var paths = self  # the overland paths (terrain.paths, land_paths.gd): this stand-in answers them itself
	func tile_of(p: Vector3) -> Vector2i:
		return Vector2i(floori(p.x / 4.0), floori(p.z / 4.0))
	func world_pos(x: float, y: float) -> Vector3:
		return Vector3(x * 4.0, 0, y * 4.0)
	func height_at(_x: float, _z: float) -> float:
		return 0.0


class Units:
	func figure_of(_id: int) -> Node3D:
		return null


class Rig:
	var cam: Camera3D
	func _ground_under(screen: Vector2) -> Vector3:
		var o := cam.project_ray_origin(screen)
		var d := cam.project_ray_normal(screen)
		return o + d * (-o.y / d.y) if d.y < -0.01 else Vector3.INF


class Sound:
	func ordered(_k: String) -> void:
		pass


class FakeMain extends Node:
	var awareness := Awareness.new()
	var bridge := Bridge.new()
	var towns := Towns.new()
	var terrain := Terrain.new()
	var units := Units.new()
	var rig := Rig.new()
	var sound := Sound.new()
	var ui: Node = null


## A host view with its regiments (army.gd's command hooks: regiments(), select(id), select_host(h)).
class View extends Node3D:
	var marked := 0
	var told := {}
	func regiments() -> Array:
		return [{"id": 9, "host": HOST, "at": Vector3(-3, 0, 2)}]
	func select(id: int) -> bool:
		marked = id
		return true
	func select_host(h: Dictionary) -> void:
		told = h


var fails: Array[String] = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _screen(cam: Camera3D, p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _push(e: InputEvent) -> void:
	root.push_input(e)


func _button(at: Vector2, button: MouseButton, down: bool) -> void:
	var m := InputEventMouseMotion.new()
	m.position = at
	m.global_position = at
	_push(m)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.position = at
	e.global_position = at
	_push(e)


func _click(at: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	_button(at, button, true)
	_button(at, button, false)


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	Keys.apply()
	root.size = Vector2i(1280, 720)  # headless opens a 64 px window: every click would be within a few pixels of every other
	var main := FakeMain.new()
	root.add_child(main)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 12, 0)
	cam.rotation_degrees = Vector3(-90, 0, 0)
	cam.current = true
	main.rig.cam = cam
	var view := View.new()
	view.add_to_group(&"host_views")
	root.add_child(view)
	var hc: Node = HostCommand.new()
	hc.main = main
	main.add_child(hc)
	await process_frame
	var asked: Array = main.bridge.asked

	# The card's orders, each with its key.
	var orders: Array = (preload("res://scripts/data.gd").value("host_command", "orders", []) as Array).map(func(o): return String(o["order"]))
	for k in ["march", "attack", "besiege", "hold", "return"]:
		_check(orders.has(k) and InputMap.has_action(StringName("host_" + k)), "the card has %s with its key" % k)

	hc.select(HOST)
	_check(int(hc.selected) == HOST, "the host is selected")

	# Attack: aim, then a click on the foe's ground.
	hc._press("attack")
	_check(hc._aim == "attack", "Attack waits for a click (aim %s)" % hc._aim)
	var foe := Vector3(-2.5, 0, -2.5)
	hc.take_click(foe)
	var a: Dictionary = asked.back() if not asked.is_empty() else {}
	_check(a.get("order") == "attack" and int(a.get("host", -1)) == HOST and a.has("x") and not a.has("city"), "Attack asks for the foe's ground: %s" % a)

	# Besiege: aim, then a click on the town.
	hc._press("besiege")
	_check(hc._aim == "besiege", "Besiege waits for a click")
	hc.take_click(Vector3(4.3, 0, 0.2))
	var b: Dictionary = asked.back()
	_check(b.get("order") == "march" and int(b.get("city", -1)) == int(TOWN["id"]), "Besiege asks the bridge's march on the town (it lays siege on arrival): %s" % b)

	# Hold and Go home at once.
	for k in ["hold", "return"]:
		var n := asked.size()
		hc._press(k)
		_check(asked.size() == n + 1 and asked.back().get("order") == k, "%s is asked at once" % k)

	# Drag to face: left to right across the screen, so the host faces up the screen.
	var s0 := _screen(cam, Vector3(-2, 0, 1))
	var s1 := _screen(cam, Vector3(2, 0, 1))
	var n0 := asked.size()
	_button(s0, MOUSE_BUTTON_RIGHT, true)
	for i in 6:
		var m := InputEventMouseMotion.new()
		m.position = s0.lerp(s1, (i + 1) / 6.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_RIGHT
		_push(m)
	var ghosts: int = hc._ghosts.multimesh.instance_count
	_button(s1, MOUSE_BUTTON_RIGHT, false)
	var f: Dictionary = asked.back() if asked.size() > n0 else {}
	var mid := (s0 + s1) * 0.5
	var g_up: Vector3 = main.rig._ground_under(mid + Vector2(0, -50)) - main.rig._ground_under(mid)  # the ground's way up the screen
	var want := atan2(g_up.x, g_up.z)
	_check(ghosts == 4, "the drag shows a ghost per company (%d of 4)" % ghosts)
	_check(f.get("order") == "march" and f.has("face") and absf(angle_difference(float(f.get("face", 99.0)), want)) < 0.05, "a right-drag marches to the line facing up the screen: %s (want face %.2f)" % [f, want])
	_check(f.get("x") == 0 and f.get("y") == 0, "it marches to the line's middle (tile 0,0): %s" % f)

	# A plain right-click still marches, with no face.
	_click(_screen(cam, Vector3(-5, 0, -5)), MOUSE_BUTTON_RIGHT)
	var r: Dictionary = asked.back()
	_check(r.get("order") == "march" and not r.has("face"), "a right-click marches: %s" % r)

	# A regiment: a click on it selects its host and marks it.
	hc.select(-1)
	hc._pressed = {"unit": 9, "view": view}  # what host_pick.gd's physics ray met at the press (army_probe 12 tests the ray)
	hc.take_click(Vector3(-3, 0, 2))
	_check(int(hc.selected) == HOST and view.marked == 9, "a click on a regiment selects its host and marks it (host %d, regiment %d)" % [int(hc.selected), view.marked])

	# One order, one host: the selected one (the second here), from the card and from the play step.
	hc.select(OTHER)
	hc._press("besiege")
	hc.take_click(Vector3(4.3, 0, 0.2))
	var o: Dictionary = asked.back()
	_check(int(o.get("host", -1)) == OTHER, "the card's Besiege goes to the selected host only: %s" % o)
	var by_card: bool = hc.has_method("order")
	_check(by_card, "the card has one way to give an order (host_command.order)")
	if by_card:
		var n1 := asked.size()
		hc.order("besiege", {"city": int(TOWN["id"])})
		var p: Dictionary = asked.back() if asked.size() > n1 else {}
		_check(asked.size() == n1 + 1 and int(p.get("host", -1)) == OTHER and p.get("order") == "march" and int(p.get("city", -1)) == int(TOWN["id"]), "an order given by name goes to the selected host only: %s" % p)
		hc.select(-1)
		var n2 := asked.size()
		hc.order("besiege", {"city": int(TOWN["id"])})
		_check(asked.size() == n2, "with no host selected no order is asked")
	var play := FileAccess.get_file_as_string("res://scripts/autoplay.gd")
	_check(not play.contains("\"/host/order\"") and not play.contains("else all[0]"), "the play step orders only the selected host, through the card")

	for x in fails:
		print("HOST COMMAND FAIL " + x)
	print("HOST COMMAND %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
