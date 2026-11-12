extends SceneTree
## Guard for a house's gold where the player looks at a house (the engine-visual map, docs/research/
## engine-visual-map-2026-11-12.md: every house's income and gold were never shown, only the crown's net). The store
## takes a /world whose houses carry Freeciv's books (players[].gold, players[].income by source: bridge treasury.js);
## the house card opened on one house shows its purse as it is now and its last season, net, with each source on hover.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/house_purse_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 60.0)
	_run.call_deferred()


func _run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/fixtures/town_build_world.json"))
	var pid := int((world["players"][1] as Dictionary)["id"])
	world["players"][1]["gold"] = 437
	world["players"][1]["income"] = {"towns": 52, "mines": 9, "tithe": -14, "court": 0, "dealings": 3, "purse": 437}
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	store.dispatch(store.SYNC, {"world": world})
	var ui: Node = load("res://scripts/ui.gd").new()
	root.add_child(ui)
	await process_frame
	ui.show_house({"id": pid, "name": "House Probe", "history": [{"gold": 100, "souls": 1, "armies": 1, "grain": 1, "towns": 1}]})
	await process_frame
	var texts: Array = []
	var tips: Array = []
	for l in ui.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
		tips.append((l as Label).tooltip_text)
	var UI = load("res://scripts/ui.gd")
	var purse_now: String = UI.real("gold", 437)
	var net_now: String = "+" + UI.real("gold", 50)
	var upper := texts.map(func(t): return String(t).to_upper())
	_check(texts.has(purse_now) and not texts.has(UI.real("gold", 100)), "the card shows the house's purse as the books have it now (%s), not the history's (%s)" % [purse_now, UI.real("gold", 100)])
	_check(upper.has("LAST SEASON") and texts.has(net_now), "the card shows last season's gold, net (%s)" % net_now)
	var tip := "\n".join(PackedStringArray(tips))
	_check(tip.contains("Towns  +" + UI.real("gold", 52)) and tip.contains("Tithe  −" + UI.real("gold", 14)) and tip.contains("Mines  +" + UI.real("gold", 9)), "each source on hover, in the card's own money: %s" % tip.strip_edges().replace("\n", " | ").substr(0, 160))
	print("CHECK house purse: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
