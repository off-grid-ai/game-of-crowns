extends SceneTree
## Guard for the nature set (Mac: "major issues with the trees, the grass"; the look audit's fix plan 3, docs/art/nature):
## the woods, the ground cover, the town, orchard and castle trees, the verges' bushes, the tufts and the towns' dressing
## draw the nature set's pieces (nt_oak_a, nt_oak_b, nt_pine_a, nt_pine_b, nt_bush, nt_grass_clump, nt_cypress, nt_rock_b),
## never Quaternius' trees, bushes, grass tufts, rocks or pebbles, nor KayKit's cypress, which are gone from realm/assets.
##   1. nothing the game or its tools read names a Quaternius tree, bush, tuft, rock or pebble or KayKit's cypress
##      (realm/scripts, realm/data, realm/tools);
##   2. every nature-set file a role names is in realm/assets (woods.kit, forest.json cover, the catalogue's tree,
##      cypress and rock components, the tufts, the verges' bush, the gold mines' rocks and ore);
##   3. built from a saved realm (fixtures town_build_map.json), every mesh the woods and the cover drew is a nature-set
##      piece: no material of Quaternius' kit (Leaves_*, Leaf_*, Bark_*, Grass) and every MI_Leaves marked with its kind;
##      a pine's leaves are "pine";
##   4. the leaves turn in autumn and the trunks keep their paint.
## Prints CHECK lines; exits 1 on a fail.   arch -arm64 godot --headless --path realm -s res://tools/nature_set_probe.gd

const FIX := "res://tools/fixtures/town_build_map.json"
const GONE := "(nature/)?(CommonTree_\\d|TwistedTree_\\d|DeadTree_\\d|Pine_\\d|Bush_Common[\"./]|Bush_Common$|Fern_1|Plant_7[\"./]|Grass_Common_Short|Grass_Common_Tall|Grass_Wispy_Short|Rock_Medium_\\d|Pebble_(Round|Square)_\\d|RockPath_(Round_Small|Round_Thin|Square)|kaykit/Tree_4_)"
const OLD_MATS := ["Leaves", "Leaf_", "Bark_", "Grass"]

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 300.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _files(dir: String, out: Array) -> void:
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() in ["gd", "json", "py", "sh", "mjs", "tscn"] and f != "nature_set_probe.gd":
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if not d.begins_with("."):
			_files(dir.path_join(d), out)


func _run() -> void:
	# 1. Nothing names a Quaternius tree, bush or tuft.
	var re := RegEx.create_from_string(GONE)
	var named := []
	var files := []
	for d in ["res://scripts", "res://data", "res://tools"]:
		_files(d, files)
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		var m := re.search(text)
		if m:
			named.append("%s: %s" % [f, m.get_string()])
	_check(named.is_empty(), "nothing names a Quaternius tree, bush, tuft, rock or pebble, or KayKit's cypress %s" % [named.slice(0, 6)])

	# 2. Every nature-set file a role names is there.
	var Real := preload("res://scripts/realistic.gd")
	var Data := preload("res://scripts/data.gd")
	var paths := []
	var kit: Dictionary = Data.value("assets", "woods.kit", {})
	for role in ["pine", "oak", "bush"]:
		for m in (kit.get(role, {}) as Dictionary).get("models", []):
			paths.append("res://assets/" + String(m))
	var cover: Dictionary = Data.value("forest", "cover", {})
	for role in ["bush", "grass", "rock"]:
		for m in cover.get(role, []):
			paths.append("res://assets/" + String(m))
	for comp in ["town_tree", "orchard_tree", "castle_shrub", "town_cypress", "castle_cypress", "castle_rock", "milestone"]:
		for i in Real.variants(comp).size():
			paths.append(Real.path_of(comp, i))
	paths.append(str(load("res://scripts/roads.gd").get("BUSH")))  # the verges' bush
	var mines: GDScript = load("res://scripts/gold_mines.gd")
	paths.append_array(mines.get_script_constant_map().get("ROCKS", []))
	paths.append(str(mines.get_script_constant_map().get("PEBBLE", "")))
	paths.append("res://assets/" + String(preload("res://scripts/countryside.gd").TUFTS[0]))
	var bad := []
	for p in paths:
		if not String(p).begins_with("res://assets/meshy/nt_") or not ResourceLoader.exists(p):
			bad.append(p)
	_check(paths.size() >= 22 and bad.is_empty(), "every tree, bush, grass and rock role is a nature-set piece in realm/assets (%d paths) %s" % [paths.size(), bad])
	var oaks: Array = (kit.get("oak", {}) as Dictionary).get("models", [])
	_check(oaks.size() >= 2, "the oak role is a list (%d models)" % oaks.size())

	# 3. Built: what the woods and the cover drew.
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	map["land"]["file"] = ProjectSettings.globalize_path("res://").path_join("../" + String(map["land"]["file"])).simplify_path()
	var terrain: Node3D = load("res://scripts/terrain.gd").new()
	root.add_child(terrain)
	await terrain.build(map)
	var meshes := {}
	for mmi in terrain.find_children("*", "MultiMeshInstance3D", true, false):
		if mmi.multimesh and mmi.multimesh.mesh:
			meshes[mmi.multimesh.mesh] = true
	var old := []
	var leaves := []
	var trunks := []
	var pine_ok := false
	for mesh: Mesh in meshes:
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si) as BaseMaterial3D
			if mat == null:
				continue
			var n := mat.resource_name
			for o in OLD_MATS:
				if n.begins_with(o):
					old.append(n)
			if n.begins_with("MI_Leaves"):
				leaves.append(mat)
				pine_ok = pine_ok or String(mat.get_meta("leaf", "")) == "pine"
			elif n.begins_with("Material_0"):
				trunks.append([mat, mat.albedo_color])
	var unmarked := leaves.filter(func(m): return String(m.get_meta("leaf", "")) == "")
	_check(old.is_empty(), "no Quaternius material in the woods or the cover %s" % [old.slice(0, 6)])
	_check(leaves.size() >= 4 and unmarked.is_empty(), "the woods' and the cover's leaves are MI_Leaves, each marked with its kind (%d, %d unmarked)" % [leaves.size(), unmarked.size()])
	_check(pine_ok, "a pine's leaves take the pine's season")

	# 4. Autumn turns the leaves, not the trunks.
	var summer := {}
	for m in leaves:
		summer[m] = m.albedo_color
	terrain.set_season("summer", [], 0.05)
	await create_timer(0.3).timeout
	for m in leaves:
		summer[m] = m.albedo_color
	terrain.set_season("autumn", [], 0.05)
	await create_timer(0.3).timeout
	var turned := leaves.filter(func(m): return not m.albedo_color.is_equal_approx(summer[m]))
	var warm := leaves.filter(func(m): return m.albedo_color.r > summer[m].r and String(m.get_meta("leaf", "")) == "leaves")
	var moved := trunks.filter(func(t): return not t[0].albedo_color.is_equal_approx(t[1]))
	_check(turned.size() == leaves.size() and not warm.is_empty(), "autumn turns every leaf material (%d of %d), the broadleaves warmer (%d)" % [turned.size(), leaves.size(), warm.size()])
	_check(not trunks.is_empty() and moved.is_empty(), "the trunks keep their paint (%d trunks, %d changed)" % [trunks.size(), moved.size()])
	_end()


func _end() -> void:
	print("CHECK nature set: %s" % ("PASS" if fail == 0 else "FAIL (%d)" % fail))
	quit(1 if fail else 0)
