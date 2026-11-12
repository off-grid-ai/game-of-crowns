extends SceneTree
## A guard (integration audit #9, docs/research/integration-audit-2026-11-12.md): towns.gd is split at its seams, one
## job a script. Each row names a job, the script that owns it now, and the functions that left towns.gd for it:
## towns.gd defines none of them and the owner defines each. A seam split later adds its row here. Prints CHECK lines;
## exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/towns_split_probe.gd

const SEAMS := [
	["fields and orchards out past the plots", "res://scripts/town_fields.gd",
		["_fields_beyond", "_mill_wheat", "_orchards", "_dry_all_over", "_fields", "_field_at", "_hedgerow"],
		["beyond", "ring", "mill_wheat", "orchards", "dry_all_over", "field_at", "hedgerow"]],
	["a house's banners, raised as high as its favour", "res://scripts/town_banners.gd",
		["_banner", "banner_height", "_hoist", "_raise_banners", "_fringe"],
		["stand", "height_for", "hoist", "raise", "fringe"]],
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
	print("CHECK towns split: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
