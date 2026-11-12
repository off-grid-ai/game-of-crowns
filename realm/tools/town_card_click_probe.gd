extends SceneTree
## Headless check that the town card closes on a click away from it (Mac, 2026-11-12: today only Esc, an order, or
## panning the town off screen close it; CK3's and Anno 1800's info cards close on a click elsewhere). The game's own
## click on the world (main.gd _on_ground_clicked, which the camera rig's left click calls) with the real interface
## (ui.gd and its town card, town_panel.gd) and a stand-in for the towns that records whether the click acted on the
## world. Asserts:
##   - with the card open, a click on the ground puts it away through its one close path (town_closed is heard);
##   - that click acts on nothing else: no town is looked up or opened;
##   - with the card shut, a click on the ground is the world's again (it looks up the nearest town, as before).
## (A click on the card itself never reaches main: the interface takes it before the rig's _unhandled_input.)
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/town_card_click_probe.gd

const Main := preload("res://scripts/main.gd")


class Towns extends Node3D:
	var asked := 0
	func nearest(_p: Vector3, _reach := INF) -> Dictionary:
		asked += 1
		return {}


## The real interface and town card, but a town shown is only noted (the full interface isn't built here).
class ProbeUI extends "res://scripts/ui.gd":
	func show_town(_c: Dictionary, _h: Dictionary, _p: Dictionary) -> void:
		pass


class Store extends Node:
	func rec(_k: String, d: Variant = null) -> Variant:
		return d


var fails: Array[String] = []


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails.append(what)


func _run() -> void:
	var ui: Node = ProbeUI.new()
	var card := PanelContainer.new()
	root.add_child(card)
	ui.town_card._town_panel = card
	ui.town_card._town_id = 3
	card.visible = true
	var closed := [0]
	ui.town_closed.connect(func(): closed[0] += 1)
	var main: Node = Main.new()
	var towns := Towns.new()
	main.ui = ui
	main.towns = towns
	main.awareness = Store.new()

	main._on_ground_clicked(Vector3(1, 0, 1))
	_check(not card.visible, "a click on the ground puts the open town card away")
	_check(closed[0] == 1, "through its one close path (town_closed heard %d times)" % closed[0])
	_check(towns.asked == 0, "and acts on nothing else: no town looked up (%d)" % towns.asked)

	main._on_ground_clicked(Vector3(1, 0, 1))
	_check(towns.asked == 1, "with the card shut, a click on the ground is the world's again (towns asked %d)" % towns.asked)

	for f in fails:
		print("TOWN CARD CLICK FAIL " + f)
	print("TOWN CARD CLICK %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
