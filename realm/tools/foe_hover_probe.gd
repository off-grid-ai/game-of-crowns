extends SceneTree
## Guard for "I have no way to attack the people attacking me" (Mac 2026-11-16, a foe's column marching past his
## selected host: no "Attack" by the pointer over them, only "March"). In the game itself (main.tscn headless at a
## player's window size, against the running bridge, read only; nothing is ordered): one of the King's hosts is
## selected, then the camera comes down over every foe's men on the map as a player would, at play height, and the
## pointer is put on them. It proves:
##   1. every foe's company under arms on the map (not workers, settlers or ships) can be picked: a pick proxy with
##      its unit id stands where its men are drawn (a lone figure, a column, a field host);
##   2. the pointer on them, with a host selected, reads "attack" (host_command.gd _hover_read: Warcraft III's sword
##      over a foe), at play height and from the strategic height.
## Prints CHECK lines and, per foe, what the pick met; exits 1 on a fail, 2 if the realm never came up.
##   arch -arm64 godot --headless --path realm -s res://tools/foe_hover_probe.gd

const HostPick := preload("res://scripts/host_pick.gd")
const NOT_ARMS := ["Workers", "Settlers", "Trireme", "Caravel", "Galleon", "Explorer", "Migrants", "Engineers"]

var main: Node
var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 600.0)
	_run.call_deferred()


func _check(ok: bool, text: String) -> bool:
	print("CHECK foe hover, %s: %s" % [text, "PASS" if ok else "FAIL"])
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


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	main.title.visible = false
	main.title.closed.emit()
	var up: bool = await _wait(func() -> bool: return main.terrain != null and main.terrain.width > 0 and main.towns != null \
			and not main.towns.towns.is_empty() and not main.towns.building(), 400.0)
	var hc: Node = main.get_node_or_null("HostCommand")
	if not up or hc == null or (hc.hosts() as Array).is_empty():
		print("FOE HOVER: the realm, the command card or a host of the King's never came up: FAIL")
		quit(2)
		return
	await create_timer(8.0).timeout  # the columns and figures raised on the frame budget
	hc.select(int((hc.hosts() as Array)[0]["id"]))
	var crown := int(main.awareness.rec("crownId", -1))
	var proxies := {}
	for n in get_nodes_in_group(HostPick.GROUP):
		if n.has_meta("unit"):
			proxies[int(n.get_meta("unit"))] = n
	var foes := []
	for u in main.awareness.rec("units", []):
		if int(u.get("owner", -1)) != crown and not NOT_ARMS.has(String(u.get("type", ""))) and hc._is_foe(int(u["id"])):
			foes.append(u)
	print("  crown %d; %d foe companies under arms; %d pick proxies on the map" % [crown, foes.size(), proxies.size()])
	var picked := 0
	var attack := 0
	for u in foes:
		var uid := int(u["id"])
		var at: Vector3 = main.terrain.world_pos(float(u["x"]), float(u["y"]))
		var p: Node = proxies.get(uid)
		if p:
			at = ((p as Area3D).get_child(0) as Node3D).global_position
		for dist in [14.0, 40.0]:
			main.rig.snap(at, dist, 0.6)
			await create_timer(0.8).timeout
			await _frames(3)
			var cam := root.get_camera_3d()
			var s := cam.unproject_position(at)
			var met := HostPick.pick(cam, s, Data_px(), hc._is_foe)
			hc._hover_px = Vector2.INF
			hc._hover_read(s)
			var word := String(hc._hover[0]) if not (hc._hover as Array).is_empty() else ""
			print("  %s %d (owner %d) at %d,%d, lens %d: proxy %s, visible %s, pick met %s, word '%s'" % [u.get("type"), uid,
					int(u.get("owner", -1)), int(u["x"]), int(u["y"]), int(dist), "yes" if p else "NONE",
					str((p as Area3D).is_visible_in_tree()) if p else "-", str(met.get("unit", "nothing")), word])
			if dist == 14.0:
				picked += 1 if p else 0
				attack += 1 if word == "attack" else 0
	if not foes.is_empty():
		_check(picked == foes.size(), "every foe company has a pick proxy (%d of %d)" % [picked, foes.size()])
		_check(attack == foes.size(), "the pointer on each reads Attack with a host selected (%d of %d)" % [attack, foes.size()])
	quit(1 if fail > 0 else 0)


func Data_px() -> float:
	return float(preload("res://scripts/data.gd").num("host_command", "foe_px", 40.0))
