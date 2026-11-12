extends SceneTree
## A guard for terrain.gd's parts (integration audit #13: the god object split into LandPaths, Vegetation and
## PoliticalOverlay). From a saved realm (realm/tools/fixtures: the bridge's /map and /world, no bridge) the real land
## is built, then each part is asked what the game asks of it:
##   vegetation: terrain.vegetation scatters the wild plants as its own children (none left on terrain itself), the
##     kit woods are planted as terrain.forest when the kit is here, and clear_around, settle_scatter and a change of
##     season run over them without a script error.
##   politics: terrain.politics takes the store's owners, houses and intrigue (main.gd) and draws the realm map into the
##     ground's material and its standing texture (the minimap's seams); land changing hands floods in stages
##     (PoliticalOverlay.flood_stages, the minimap's too); the marks become scars; a razed ruin's burn lasts RAZED_BURN.
##   the old way is gone: terrain itself no longer has set_realm, set_marks, flood_stages or the scatter.
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/land_parts_probe.gd

const FIX := "res://tools/fixtures/town_build_%s.json"
const WAIT_S := 150.0


class Errors extends Logger:
	var seen := []
	func _log_error(_function: String, file: String, line: int, _code: String, rationale: String, _editor_notify: bool, _error_type: int, _bt: Array[ScriptBacktrace]) -> void:
		if file.ends_with(".gd"):
			seen.append("%s:%d %s" % [file.get_file(), line, rationale])

var errors := Errors.new()
var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, WAIT_S + 30.0)
	OS.add_logger(errors)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _run() -> void:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "map"))
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX % "world"))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	var veg = terrain.get("vegetation")
	var politics = terrain.get("politics")
	_check(veg != null, "vegetation: terrain.vegetation is built")
	_check(politics != null, "politics: terrain.politics is made")
	for old in ["set_realm", "set_marks", "flood_stages", "scar_heals", "set_realm_mix", "_build_vegetation", "_woodland"]:
		_check(not terrain.has_method(old), "the old way is gone: terrain.%s" % old)
	if veg == null or politics == null:
		_end()
		return

	# Vegetation.
	var batches: Array = veg.batches
	_check(batches.size() > 0, "vegetation: wild plants scattered (%d batches)" % batches.size())
	_check(batches.all(func(b): return b.get_parent() == veg), "vegetation: its batches are its own children")
	var loose := terrain.get_children().filter(func(c): return c is MultiMeshInstance3D)
	_check(loose.is_empty(), "vegetation: none left on terrain itself (%d)" % loose.size())
	var kit: bool = preload("res://scripts/forest.gd").available()
	_check((terrain.forest != null) == kit, "vegetation: the kit woods planted as terrain.forest when the kit is here (kit %s, forest %s)" % [kit, terrain.forest != null])
	var before := errors.seen.size()
	var crown: Dictionary = {}
	for c: Dictionary in world.get("cities", []):
		if String(c.get("title", c.get("name", ""))) == "Kingsmere":
			crown = c
	var at: Vector3 = terrain.world_pos(float(crown.get("x", 10)), float(crown.get("y", 10)))
	terrain.clear_around(at, 3.0)
	await terrain.settle_scatter()
	terrain.set_season("winter", [], 0.1)
	terrain.set_season("summer", [], 0.1)
	_check(errors.seen.size() == before, "vegetation: clear_around, settle_scatter and the seasons run clean %s" % [errors.seen.slice(before)])

	# Politics.
	var owners: Array = world.get("owners", [])
	var players: Array = world.get("players", [])
	before = errors.seen.size()
	politics.set_realm(owners, players, world.get("intrigue", []))
	_check(politics.standing_tex != null, "politics: the standing texture is drawn (the minimap's seams)")
	_check(terrain._land_mat != null and terrain._land_mat.get_shader_parameter("realm_tex") != null, "politics: the realm map is in the ground's material")
	# A tile changes hands: the flood has a stage for it.
	var row := String(owners[owners.size() / 2]).split(",")
	var x := -1
	for i in row.size():
		if row[i] != "-" and row[i] != "":
			x = i
			break
	if x >= 0:
		var was: Array = politics._realm_ids.duplicate(true)
		var was_img: Image = politics._realm_img
		row[x] = str((int(row[x]) + 1) % maxi(players.size(), 2))
		var moved := owners.duplicate()
		moved[owners.size() / 2] = ",".join(row)
		politics.set_realm(moved, players, world.get("intrigue", []))
		var stages: Array = load("res://scripts/political_overlay.gd").flood_stages(was, politics._realm_ids, was_img, politics._realm_img)
		_check(stages.size() == 1, "politics: a tile changing hands floods in one stage (%d)" % stages.size())
	else:
		_check(false, "politics: the fixture has an owned tile")
	politics.set_marks(world.get("marks", []), int(world.get("turn", 0)))
	_check(politics._scar_sig != "", "politics: the marks are drawn as scars")
	var PO = load("res://scripts/political_overlay.gd")
	_check(PO.scar_heals({"kind": "razed"}) == PO.RAZED_BURN and PO.scar_heals({"kind": "battle", "seasons": 12}) == 12.0, "politics: a ruin's burn lasts RAZED_BURN, a battle's the bridge's")
	politics.set_realm_mix(0.5)
	_check(errors.seen.size() == before, "politics: runs clean %s" % [errors.seen.slice(before)])
	_end()


func _end() -> void:
	print("VERDICT %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
