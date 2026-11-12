extends SceneTree
## Headless check that the square's crowd has one owner (top supervisor, 2026-11-12; casebook, Living towns: "The crowd
## is the census"): how many stand on a town's square is towns.json square.targets.per_100m2 x its open setts (01-town's
## density), worked out once by town_scenes.gd square_budget(root), and read by both the scene cast's census
## (town_scenes _census_cap) and the villagers' square cap (village_slots square_cap). Before, the census asked 69 for
## Kingsmere's film square (1154 m2) while the villagers stopped at crowd.json square_agents.square_holds 28, beside
## two more square_holds knobs (towns.json market.crown 14, crowd.json villagers 10, and crowd.json off 20): four
## numbers for one fact. On a staged square of a known size (no headless Kingsmere: a headless game builds it smaller
## than the film; One store is on it):
##   - square_budget(root) == round(open m2 / 100 * per_100m2), for a 10 m and a 17.5 m square;
##   - village_slots square_cap for a villager of that town gives the same number, the crown's seat or not;
##   - no square_holds knob is left in data/crowd.json or data/towns.json, and no SQUARE_HOLDS in village_slots.gd.
## Exit 1 on a failure.  arch -arm64 godot --headless --path realm -s res://tools/square_crowd_probe.gd

const Data := preload("res://scripts/data.gd")


class Towns extends Node:
	var towns := {}
	func building() -> bool:
		return false


class Vill extends Node:
	var towns: Node
	var TownLife = preload("res://scripts/town_life.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var TownScenes: Script = load("res://scripts/town_scenes.gd")
	var has_budget: bool = TownScenes.get_script_method_list().any(func(m: Dictionary) -> bool: return m["name"] == "square_budget")
	var um: float = load("res://scripts/towns.gd").S  # world units a metre
	var per := float(Data.num("towns", "square.targets.per_100m2", 6.0))
	var vill := Vill.new()
	vill.towns = Towns.new()
	get_root().add_child(vill)
	var slots: Object = load("res://scripts/village_slots.gd").new(vill)
	var id := 0
	for r_m in [10.0, 17.5]:
		for crown in [false, true]:
			id += 1
			var root := Node3D.new()
			root.set_meta("paved", [[Vector2.ZERO, Vector2.ZERO, r_m * um]])
			root.set_meta("crown_seat", crown)
			root.set_meta("square_r", r_m * um)
			get_root().add_child(root)
			vill.towns.towns[id] = {"node": root, "data": {"id": id, "size": 6 if crown else 3}}
			var m2: float = TownScenes.call("open_setts_m2", root)
			var want := int(round(m2 / 100.0 * per))
			if not has_budget:
				print("FAIL town_scenes.gd has no square_budget(root): the square's crowd has no one owner")
				fails += 1
				break
			var got: int = TownScenes.call("square_budget", root)
			var cap: int = slots.square_cap({"town": id})
			print("square %.1f m (%s): %.0f m2 open, want %d; square_budget %d, villagers' cap %d" % [r_m, "crown" if crown else "town", m2, want, got, cap])
			if got != want:
				print("FAIL square_budget %d, not per_100m2 x open setts (%d)" % [got, want])
				fails += 1
			if cap != want:
				print("FAIL the villagers' square cap is %d, not the square's one budget (%d)" % [cap, want])
				fails += 1
		if not has_budget:
			break
	for f in ["crowd", "towns"]:
		var src := FileAccess.get_file_as_string("res://data/%s.json" % f)
		if src.contains("\"square_holds\""):
			print("FAIL data/%s.json keeps a square_holds knob (a second owner of the square's crowd)" % f)
			fails += 1
	if FileAccess.get_file_as_string("res://scripts/village_slots.gd").contains("SQUARE_HOLDS"):
		print("FAIL village_slots.gd keeps SQUARE_HOLDS")
		fails += 1
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
