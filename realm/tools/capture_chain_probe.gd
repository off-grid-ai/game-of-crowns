extends SceneTree
## READY.md line 7, "Capture a town", the whole chain in the game itself (casebook, War and sieges: a siege is a
## season, Total War: Attila; the town changes hands in Freeciv and on screen). Run by capture_chain_probe.sh against
## a private bridge (--bridge=...): main.tscn headless, as Mac would play it. Each link is a CHECK line:
##   1. the King's host is in the field and is selected (host_command.select, as a click on its standard does);
##   2. Besiege on a foe's town is given through host_command.order, the one way an order is given (b30bad7f), and
##      the bridge takes it (200);
##   3. the siege is laid (the city's besieged flag: campaigns.js), then Freeciv takes the town: the store's
##      city owner (awareness.gd, the mirror of /world) is the crown's;
##   4. the town stands built for its new house: towns.gd's root has the crown as owner and every banner on it is the
##      crown's cloth (heraldry.cloth: the house's painted arms, or its colour);
##   5. the town card (town_panel.gd, through main._show_selected) names the crown's house.
## Exit 1 on a fail; 2 if the realm never came up.
##   zsh realm/tools/capture_chain_probe.sh

const SEASONS := 45  # the most seasons the capture may take after the order (besiege_order_probe: 5 on bare Freeciv)
const Heraldry := preload("res://scripts/heraldry.gd")

var main: Node
var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 1200.0)
	_run.call_deferred()


func _check(ok: bool, text: String) -> bool:
	print("CHECK capture chain, %s: %s" % [text, "PASS" if ok else "FAIL"])
	if not ok:
		fail += 1
	return ok


func _wait(cond: Callable, secs: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > secs * 1000.0:
			return false
		await process_frame
	return true


func _turn() -> int:
	return int(main.awareness.rec("turn", 0))


func _run() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	current_scene = main  # as the game runs it: views ask the current scene for main (map_labels.gd)
	await process_frame
	# Continue on the title menu, as Mac does: the menu closes and the realm wakes (main.gd title.closed).
	main.title.visible = false
	main.title.closed.emit()
	var up: bool = await _wait(func() -> bool: return main.awareness != null and main.terrain != null and main.terrain.built and main.towns != null and not main.towns.towns.is_empty(), 400.0)
	if not up:
		print("CAPTURE CHAIN: the realm never came up in the game (terrain or towns not built): FAIL")
		quit(2)
		return
	var crown := -1
	var houses: Dictionary = main.awareness.houses_by_id()
	for id in houses:
		if bool((houses[id] as Dictionary).get("crown", false)):
			crown = int(id)
	# 1. The King's host, selected.
	var hc: Node = main.get_node_or_null("HostCommand")
	var have: bool = await _wait(func() -> bool: return hc != null and not (hc.hosts() as Array).is_empty(), 120.0)
	var host := {}
	if have:  # the King's largest host (hosts.js lists only the crown's)
		for h in hc.hosts():
			if host.is_empty() or int((h as Dictionary).get("men", 0)) > int(host.get("men", 0)):
				host = h
	if not _check(crown >= 0 and not host.is_empty(), "the King's host in the field (crown %d, hosts %d)" % [crown, (hc.hosts() as Array).size() if hc else -1]):
		_end()
		return
	hc.select(int(host["id"]))
	_check(int(hc.selected) == int(host["id"]), "host %d selected (%d men at %d,%d)" % [int(host["id"]), int(host.get("men", 0)), int(host.get("x", 0)), int(host.get("y", 0))])
	# 2. Besiege, through the card's one order, as a King with a small host chooses: the foe's towns held by the
	# fewest soldiers first, then the nearest, tried in turn until the bridge takes one and lays siege (a town the
	# crown may only march for, a sworn house's, is not a siege).
	var here := Vector2(float(host.get("x", 0)), float(host.get("y", 0)))
	var guard := func(c: Dictionary) -> int:
		return (main.awareness.rec("units", []) as Array).filter(func(u) -> bool: return int(u.get("owner", -1)) == int(c.get("owner", -2)) and int(u.get("x", -1)) == int(c["x"]) and int(u.get("y", -1)) == int(c["y"]) and not String(u.get("type", "")) in preload("res://scripts/awareness.gd").civilian).size()
	var theirs: Array = (main.awareness.rec("cities", []) as Array).filter(func(c): return int(c.get("owner", -1)) != crown)
	theirs.sort_custom(func(a, b):
		var ga: int = guard.call(a)
		var gb: int = guard.call(b)
		return ga < gb if ga != gb else here.distance_to(Vector2(float(a["x"]), float(a["y"]))) < here.distance_to(Vector2(float(b["x"]), float(b["y"]))))
	var target := -1
	var said := ""
	for c in theirs.slice(0, 8):
		var res: Array = []
		if not hc.order("besiege", {"city": int(c["id"])}, func(code: int, s: String) -> void: res.append([code, s])):
			break
		await _wait(func() -> bool: return not res.is_empty(), 60.0)
		said = String(res[0][1]) if not res.is_empty() else "no answer"
		if not res.is_empty() and int(res[0][0]) == 200 and said.contains("siege"):
			target = int(c["id"])
			print("  besiege %s (%d soldiers inside): %s" % [String(c.get("name", "")), int(guard.call(c)), said])
			break
		print("  besiege %s: %s" % [String(c.get("name", "")), said])
	var from := _turn()
	if not _check(target >= 0, "Besiege given through host_command.order and taken by the bridge (%s)" % said):
		_end()
		return
	var tname := String(main.awareness.city(target).get("name", ""))
	# 3. The siege laid, then Freeciv takes the town; the store's city owner is the crown's.
	var sieged := [-1]
	var seen := [-1]
	var taken: bool = await _wait(func() -> bool:
		var c: Dictionary = main.awareness.city(target)
		if _turn() != seen[0]:  # one line a season: where the chain stands
			seen[0] = _turn()
			var h: Dictionary = hc.host(int(host["id"]))
			var dmg = c.get("damage")
			var wear := 0.0
			if dmg is Dictionary:
				for w in (dmg as Dictionary).get("walls", []):
					wear = maxf(wear, float((w as Dictionary).get("wear", 0.0)) if w is Dictionary else 0.0)
			print("  season %d: %s owner %s, besieged %s, walls worn %.2f; host %s at %s,%s order %s, %d hosts" % [_turn() - from, tname, str(c.get("owner")), str(c.get("besieged")), wear, str(h.get("id", "gone")), str(h.get("x", "")), str(h.get("y", "")), JSON.stringify(h.get("order")), (hc.hosts() as Array).size()])
		if sieged[0] < 0:
			if bool(c.get("besieged", false)) or int(c.get("owner", -1)) == crown:  # the bridge's campaign on it (campaigns.js)
				sieged[0] = _turn()
		var lost: bool = hc.host(int(host["id"])).is_empty() and sieged[0] >= 0 and not bool(c.get("besieged", false))  # the host fell and the siege broke
		return int(c.get("owner", -1)) == crown or c.is_empty() or lost or _turn() - from > SEASONS, SEASONS * 30.0)
	var c_now: Dictionary = main.awareness.city(target)
	_check(sieged[0] >= 0, "the siege of %s laid (season %d after the order)" % [tname, sieged[0] - from if sieged[0] >= 0 else -1])
	if not _check(int(c_now.get("owner", -1)) == crown, "Freeciv took %s and the store's owner is the crown's (owner %s, %d seasons after the order%s)" % [tname, str(c_now.get("owner")), _turn() - from, "" if taken else ", timed out"]):
		_end()
		return
	# 4. The town as it stands now: built for the crown, with the crown's banners.
	main.towns.ensure(target)
	var built: bool = await _wait(func() -> bool:
		var t: Dictionary = main.towns.towns.get(target, {})
		var n = t.get("node")
		return n != null and is_instance_valid(n) and int((n as Node3D).get_meta("owner", -1)) == crown, 60.0)
	var node: Node3D = main.towns.towns.get(target, {}).get("node") if built else null
	var house: Dictionary = houses.get(crown, {})
	var cloth: Material = Heraldry.cloth(house, Heraldry.colour(house, Color.GRAY, "#888888"))
	var flags: Array = (node.get_meta("banners", []) as Array).filter(func(f) -> bool: return is_instance_valid(f)) if node else []
	var theirs_flags := flags.filter(func(f) -> bool: return (f as GeometryInstance3D).material_override != cloth)
	_check(built, "%s rebuilt for its new house (towns.gd root owner %s)" % [tname, str(node.get_meta("owner", -1)) if node else "none"])
	_check(not flags.is_empty() and theirs_flags.is_empty(), "%s flies the crown's banners (%d banners, %d not the crown's cloth)" % [tname, flags.size(), theirs_flags.size()])
	# 5. The town card names the crown's house.
	main.set("_selected", target)
	main.call("_show_selected")
	var title: String = String(main.ui.town_card._town_title.text) if main.ui and main.ui.get("town_card") else ""
	var hname := String(house.get("name", ""))
	_check(hname != "" and title.contains(hname), "the town card reads \"%s\" (want %s)" % [title, hname])
	_end()


func _end() -> void:
	print("CAPTURE CHAIN %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
