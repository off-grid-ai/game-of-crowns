extends SceneTree
## Guard for a town's rapture (the engine-visual map: "City rapture: none (celebrating covers part)"). Freeciv's
## rapture, a town celebrating (the King loved), is /world's city.celebrating (bridge view.js: c.rapture, or a feast the
## King gave there), the store's town fact celebrating, the town's feast state (works.states_bb) and, in the town,
## its feast at the tables and its revels round the bonfire (town_scenes.json feast, revels). A town without it
## stages neither. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/rapture_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var view := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../bridge/view.js"))
	_check(view.contains("celebrating: Boolean(c.rapture"), "/world's celebrating is Freeciv's rapture (bridge view.js)")
	var Awareness = load("res://scripts/awareness.gd")
	var Works = load("res://scripts/works.gd")
	var glad := {"id": 7, "x": 3, "y": 4, "size": 6, "owner": 0, "celebrating": true}
	var plain := {"id": 8, "x": 9, "y": 4, "size": 6, "owner": 0, "celebrating": false}
	_check(bool(Awareness.town_facts(glad).get("celebrating", false)), "the store's town slice carries it (town_facts celebrating)")
	var st_glad: Array = Works.states(glad, -1)
	var st_plain: Array = Works.states(plain, -1)
	_check("feast" in st_glad and not "feast" in st_plain, "a celebrating town is in the feast state, another isn't (%s / %s)" % [st_glad, st_plain])
	var scenes: Node = load("res://scripts/town_scenes.gd").new(Node.new())
	var root := Node3D.new()
	var rows := {}
	for r in (scenes._d.get("standing", []) as Array):
		rows[String(r["id"])] = r
	for id in ["feast", "revels"]:
		_check(rows.has(id) and scenes._meets(rows[id], root, st_glad, 6) and not scenes._meets(rows[id], root, st_plain, 6), "the %s stands in the celebrating town, not in the other" % id)
	print("CHECK rapture: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
