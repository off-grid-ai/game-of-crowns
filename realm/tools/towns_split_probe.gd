extends SceneTree
## A guard (integration audit #9, docs/research/integration-audit-2026-11-12.md): towns.gd is split at its seams, one
## job a script. Each row names a job, the script that owns it now, and the functions that left towns.gd for it:
## towns.gd defines none of them and the owner defines each. A seam split later adds its row here. Prints CHECK lines;
## exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/towns_split_probe.gd

const SEAMS := [
	["orchards out past the plots", "res://scripts/town_fields.gd",
		["_fields_beyond", "_mill_wheat", "_orchards", "_dry_all_over", "_fields", "_field_at", "_hedgerow"],
		["edge", "orchards"]],
	["a house's banners, raised as high as its favour", "res://scripts/town_banners.gd",
		["_banner", "banner_height", "_hoist", "_raise_banners", "_fringe"],
		["stand", "height_for", "hoist", "raise", "fringe"]],
	["the town's layout: its ways, lanes, square ring and plots, and the houses on them", "res://scripts/town_layout.gd",
		["_real_lots", "_square_ring", "_lay_ways", "_great_ways", "_lay_lanes", "_keep_ways", "_back_lane", "_paint_way", "_plot_lots", "_probe_dump", "_plot_one", "_buildings_standing", "_area", "_plot_body", "_body_on_road"],
		["real_lots", "square_ring", "lay_ways", "great_ways", "lay_lanes", "keep_ways", "back_lane", "paint_way", "plot_lots", "probe_dump", "plot_one", "buildings_standing", "area", "plot_body", "body_on_road"]],
]


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var towns: Script = load("res://scripts/towns.gd")
	var left: Array = towns.get_script_method_list().map(func(m): return String(m["name"]))
	var fail := 0
	for seam in SEAMS:
		var still: Array = (seam[2] as Array).filter(func(f): return left.has(f))
		var owner: Script = load(String(seam[1])) if ResourceLoader.exists(String(seam[1])) else null
		var has: Array = owner.get_script_method_list().map(func(m): return String(m["name"])) if owner else []
		var missing: Array = (seam[3] as Array).filter(func(f): return not has.has(f))
		var ok := still.is_empty() and owner != null and missing.is_empty()
		print("CHECK towns split, %s: still in towns.gd %s; %s %s: %s" % [seam[0], still, String(seam[1]).get_file(), "missing " + str(missing) if owner else "absent", "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
	# One crowd in the bailey: castle_folk.gd's (the people layer). towns.gd lays the yard's ground and things only; the
	# groom who warmed himself at its fire is castle_folk's (castle_folk.json fire_groom), beside the fire towns.gd lays.
	var consts: Dictionary = towns.get_script_constant_map()
	var folk: Dictionary = preload("res://scripts/data.gd").read("castle_folk")
	var one_crowd: bool = not consts.has("BAILEY_FOLK") and folk.has("fire_groom") and consts.has("BAILEY") \
		and (consts["BAILEY"] as Array).any(func(r): return String(r[0]) == "ph/stone_fire_pit")
	print("CHECK towns split, the bailey's crowd: towns.gd's own crowd %s, castle_folk's groom at the fire %s: %s" % [
		"gone" if not consts.has("BAILEY_FOLK") else "still there", "there" if folk.has("fire_groom") else "missing", "PASS" if one_crowd else "FAIL"])
	if not one_crowd:
		fail += 1
	print("CHECK towns split: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
