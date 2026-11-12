extends SceneTree
## Guard for the bailey's men being the house's own (the engine-visual map: "Castle folk: generic guards and servants,
## not the house's men"). The training yard drills one line for each of the lord's companies Freeciv has standing in
## the town (castle_folk.garrison_lines: the store's units on the town's tile, its owner's, neither civilian nor a ship,
## never more lines than the yard holds), and castle_life shows that many each tick (show_lines): a town that raises
## men fills its yard, a garrison that marches out leaves it empty. /world names the hulls (ships) as it names the
## civilian kinds. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/garrison_drill_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var Folk = load("res://scripts/castle_folk.gd")
	_check(Folk.has_method("garrison_lines") and Folk.has_method("show_lines"), "castle_folk counts the garrison and shows that many lines")
	if Folk.has_method("garrison_lines"):
		var town := {"x": 3, "y": 4, "owner": 0}
		var units := [
			{"x": 3, "y": 4, "owner": 0, "type": "Pikemen"}, {"x": 3, "y": 4, "owner": 0, "type": "Archers"},
			{"x": 3, "y": 4, "owner": 0, "type": "Workers"}, {"x": 3, "y": 4, "owner": 0, "type": "Trireme"},
			{"x": 3, "y": 4, "owner": 1, "type": "Knights"}, {"x": 8, "y": 4, "owner": 0, "type": "Pikemen"}]
		var civ := ["Workers", "Settlers"]
		var ships := ["Trireme", "Galleon"]
		_check(Folk.garrison_lines(units, civ, ships, town, 3) == 2, "two of the lord's companies in the town: two lines (not the workers, the ship, a foe's knights or a company elsewhere): %d" % Folk.garrison_lines(units, civ, ships, town, 3))
		_check(Folk.garrison_lines(units + units, civ, ships, town, 3) == 3, "never more lines than the yard holds")
		_check(Folk.garrison_lines([], civ, ships, town, 3) == 0, "a garrison marched out: no line")
		var d := {"drill": []}
		for l in 3:
			d["drill"].append([Node3D.new(), Node3D.new()])
		Folk.show_lines(d, 2)
		_check(d["drill"][0][0].visible and d["drill"][1][1].visible and not d["drill"][2][0].visible, "two lines drill, the third stood down")
		Folk.show_lines(d, 0)
		_check(not d["drill"][0][0].visible, "none with no garrison")
	var life := FileAccess.get_file_as_string("res://scripts/castle_life.gd")
	_check(life.contains("garrison_lines(") and life.contains("show_lines(") and life.contains('"city": id'), "castle_life shows each castle's garrison every tick")
	var view := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../bridge/view.js"))
	_check(view.contains("ships: [...SHIPS]") and FileAccess.get_file_as_string("res://scripts/awareness.gd").contains("static var ships"), "/world names the hulls and the store keeps them")
	print("CHECK garrison drill: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
