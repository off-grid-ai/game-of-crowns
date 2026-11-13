extends SceneTree
## READY.md line 8, "Command the army", in the game itself (casebook, War and sieges: Warcraft III's click on the unit
## and its command card). main.tscn headless in a window the size a player has (1920 x 1080; a headless window is
## 64 x 64, where the interface covers the whole view and no click can reach the land), against the running bridge
## (--bridge=..., 8787 by default; read only). Real input, as autoplay feeds it (Input.parse_input_event through the
## root's transform):
##   1. a left click on a host's standard selects that host (the milestone take: the ray met unit 250, then "host
##      selected: -1");
##   2. the command card shows for it, and each order on it, clicked as a player clicks it (and for an aimed order,
##      then a click on the land or a foe's town), asks the bridge for that host and that order: march, attack,
##      besiege, hold, go home.
## The orders go to a stand-in bridge on a local port (the probe swaps the bridge's address for that phase only), so
## nothing is given in the realm being played. Exit 1 on a fail; 2 if the realm never came up.
##   arch -arm64 godot --headless --path realm -s res://tools/host_click_probe.gd

const SPY_PORT := 8797

var main: Node
var fail := 0
var spy := TCPServer.new()
var heard: Array = []  # the bodies the stand-in bridge was asked for
var _peers: Array = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 600.0)
	_run.call_deferred()


func _check(ok: bool, text: String) -> bool:
	print("CHECK host click, %s: %s" % [text, "PASS" if ok else "FAIL"])
	if not ok:
		fail += 1
	return ok


func _wait(cond: Callable, secs: float) -> bool:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		if cond.call():
			return true
		await process_frame
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame
	await physics_frame


## A press and release at `at` (viewport space), fed as autoplay feeds them: out through the root's transform.
func _click(at: Vector2) -> void:
	var to_window: Transform2D = root.get_final_transform()
	var move := InputEventMouseMotion.new()  # onto the spot first, as a player's pointer (and autoplay._click) moves
	move.position = to_window * at
	move.global_position = move.position
	Input.parse_input_event(move)
	await _frames(1)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = to_window * at
		e.global_position = e.position
		Input.parse_input_event(e)
		await _frames(2)


func _run() -> void:
	root.size = Vector2i(1920, 1080)  # a player's window: headless, the root is 64 x 64
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.title.visible = false
	main.title.closed.emit()
	var up: bool = await _wait(func() -> bool: return main.terrain != null and main.terrain.width > 0 and main.towns != null \
			and not main.towns.towns.is_empty() and not main.towns.building(), 400.0)
	var hc: Node = main.get_node_or_null("HostCommand")
	if not up or hc == null:
		print("HOST CLICK: the realm never came up (terrain, towns or the command card): FAIL")
		quit(2)
		return
	# 1. A host whose standard stands on the map, framed as a player would come down on it, and clicked.
	var h := {}
	var pick: Area3D = null
	await _wait(func() -> bool:
		for x in hc.hosts():
			pick = _pick_of(x)
			if pick:
				h = x
				return true
		return false, 120.0)
	if not _check(pick != null, "a host of the King's with its standard on the map (%d hosts)" % (hc.hosts() as Array).size()):
		_end()
		return
	var id := int(h["id"])
	var at: Vector3 = hc._ground(h)
	main.rig.snap(at, 6.0, 0.6)
	main.rig.tilt = -25.0
	main.rig.goal_tilt = -25.0
	await create_timer(1.5).timeout
	await _frames(3)
	var cam := root.get_camera_3d()
	var cs := pick.get_child(0) as Node3D
	var s := cam.unproject_position(cs.global_position)
	var met: Dictionary = preload("res://scripts/host_pick.gd").pick(cam, s)
	print("  host %d framed; its standard at %s on screen; the ray there meets %s; the interface there: %s" % [id, s,
			("unit %d" % int(met["unit"])) if not met.is_empty() else "nothing", _control_at(s)])
	await _click(s)
	await create_timer(0.5).timeout
	if not _check(int(hc.selected) == id, "a click on host %d's standard selects it (selected %d)" % [id, int(hc.selected)]):
		_end()
		return
	_check(hc._card.visible, "the command card shows for the selected host")
	# 2. The card's orders, clicked, each asked of the (stand-in) bridge for this host.
	if spy.listen(SPY_PORT, "127.0.0.1") != OK:
		print("HOST CLICK: the stand-in bridge could not listen on %d: FAIL" % SPY_PORT)
		quit(2)
		return
	var Bridge: Script = load("res://scripts/bridge.gd")
	var real_base: String = Bridge.BASE
	Bridge.BASE = "http://127.0.0.1:%d" % SPY_PORT
	var land := Vector2(root.get_visible_rect().size.x * 0.3, root.get_visible_rect().size.y * 0.45)  # open land left of the host
	await _order(hc, "hold", id, [])
	await _order(hc, "return", id, [])
	await _order(hc, "march", id, [land])
	await _order(hc, "attack", id, [land])
	var foe := _foe_town()
	if _check(not foe.is_empty(), "a foe's town to besiege"):
		var town: Vector3 = main.terrain.world_pos(float(foe["x"]), float(foe["y"]))
		main.rig.snap(town, 8.0, main.rig.yaw)
		await create_timer(1.5).timeout
		await _frames(3)
		await _order(hc, "besiege", id, [root.get_camera_3d().unproject_position(town)], int(foe["id"]))
	Bridge.BASE = real_base
	_end()


## Clicks the card's button for `kind`, then each of `then` (screen points), and checks the bridge was asked for
## that order (its send name) for host `id` (and `city`, when one is wanted).
func _order(hc: Node, kind: String, id: int, then: Array, city := -1) -> void:
	heard.clear()
	var b: Button = hc._buttons.get(kind)
	if not _check(b != null and b.is_visible_in_tree() and not b.disabled, "the card's %s button is there and live" % kind):
		return
	await _click(b.get_global_rect().get_center())
	for p in then:
		await _click(p)
	var send := String(hc._row(kind).get("send", kind))
	await _wait(func() -> bool: _serve(); return not heard.is_empty(), 5.0)
	var got: Dictionary = heard[0] if not heard.is_empty() else {}
	var ok := int(got.get("host", -1)) == id and String(got.get("order", "")) == send
	if city >= 0:
		ok = ok and int(got.get("city", -1)) == city
	_check(ok, "the card's %s asks the bridge for host %d (%s)" % [kind, id, JSON.stringify(got) if not got.is_empty() else "nothing asked"])


## The stand-in bridge: every POST's body is heard and answered 200.
func _serve() -> void:
	while spy.is_connection_available():
		_peers.append({"peer": spy.take_connection(), "buf": PackedByteArray()})
	for p in _peers.duplicate():
		var peer: StreamPeerTCP = p["peer"]
		peer.poll()
		var n := peer.get_available_bytes()
		if n > 0:
			p["buf"].append_array(peer.get_data(n)[1])
		var text: String = (p["buf"] as PackedByteArray).get_string_from_utf8()
		var head_end := text.find("\r\n\r\n")
		if head_end < 0:
			continue
		var length := 0
		for line in text.substr(0, head_end).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.substr(15).strip_edges())
		var body := text.substr(head_end + 4)
		if body.to_utf8_buffer().size() < length:
			continue
		var status := "503 Service Unavailable"  # a world poll in this phase: the mirror keeps the realm it has
		if text.begins_with("POST /host/order"):
			status = "200 OK"
			var d: Variant = JSON.parse_string(body)
			if d is Dictionary:
				heard.append(d)
		var reply := "{\"text\":\"ok\"}" if status.begins_with("200") else "{}"
		peer.put_data(("HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [status, reply.length(), reply]).to_utf8_buffer())
		peer.disconnect_from_host()
		_peers.erase(p)


## A visible pick proxy (host_pick.gd) of one of the host's companies or regiments, or null.
func _pick_of(h: Dictionary) -> Area3D:
	var units: Array = h.get("units", [])
	for a in root.find_children("Pick", "Area3D", true, false):
		if a.has_meta("unit") and units.has(int(a.get_meta("unit"))) and (a as Node3D).is_visible_in_tree():
			return a
	return null


## A town of another house (not the crown's), or {}.
func _foe_town() -> Dictionary:
	var crown := -1
	var houses: Dictionary = main.awareness.houses_by_id()
	for hid in houses:
		if bool((houses[hid] as Dictionary).get("crown", false)):
			crown = int(hid)
	for c in main.awareness.rec("cities", []):
		if int(c.get("owner", -1)) != crown:
			return c
	return {}


## The interface control under `at`, by name, or "none" (what would take a click there ahead of the land).
func _control_at(at: Vector2) -> String:
	var best: Control = null
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and c.get_global_rect().has_point(at):
			best = c
	return "%s (%s)" % [best.name, best.get_path()] if best else "none"


func _end() -> void:
	print("HOST CLICK %s" % ("PASS" if fail == 0 else "FAIL %d" % fail))
	quit(1 if fail > 0 else 0)
