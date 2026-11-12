extends SceneTree
## Guard for a sick town (the engine-visual map, docs/research/engine-visual-map-2026-11-12.md: a plagued town looked
## well between the plague scenes). Freeciv's plague (bridge view.js city.plague: the seasons after it struck) is a
## fact of the store's town slice (awareness.town_facts plague), a state of the town (works.states: plague, first of
## works.json priority), and what its life stages (town_scenes.json): the sick laid out at the sept with a few
## kneeling, while gossip, children at play, beggars and the market day keep away. A well town stages none of it.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/plague_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var Awareness = load("res://scripts/awareness.gd")
	var Works = load("res://scripts/works.gd")
	var sick := {"id": 7, "x": 3, "y": 4, "size": 8, "owner": 0, "plague": true}
	var well := {"id": 8, "x": 9, "y": 4, "size": 8, "owner": 0, "plague": false}
	_check(bool(Awareness.town_facts(sick).get("plague", false)), "the store's town slice carries the plague (town_facts)")
	var st_sick: Array = Works.states(sick, -1)
	var st_well: Array = Works.states(well, -1)
	_check("plague" in st_sick and not "plague" in st_well, "a sick town is in the plague state, a well one isn't (%s / %s)" % [st_sick, st_well])
	var prio: Array = preload("res://scripts/data.gd").value("works", "priority", [])
	_check(not prio.is_empty() and prio[0] == "plague", "the plague comes first in works.json priority (%s)" % [prio.slice(0, 3)])
	var scenes: Node = load("res://scripts/town_scenes.gd").new(Node.new())
	var root := Node3D.new()
	root.set_meta("crown_seat", true)
	var rows: Dictionary = {}
	for r in (scenes._d.get("standing", []) as Array):
		rows[String(r["id"])] = r
	_check(rows.has("plague"), "town_scenes.json has a plague scene")
	if rows.has("plague"):
		_check(scenes._meets(rows["plague"], root, st_sick, 8) and not scenes._meets(rows["plague"], root, st_well, 8), "the plague scene stands in a sick town and not in a well one")
	var k := {"rng": RandomNumberGenerator.new(), "states": st_sick, "size": 8}
	for id in ["gossip", "chase", "beggars"]:
		var role: Dictionary = (rows[id]["roles"] as Array)[0]
		_check(scenes._count(role["n"], k) == 0, "%s keep away from a sick town (%d)" % [id, scenes._count(role["n"], k)])
	if rows.has("market_day"):
		_check(not scenes._meets(rows["market_day"], root, st_sick, 8), "no market day in a sick town")
	print("CHECK plague: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
