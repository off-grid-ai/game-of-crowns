extends SceneTree
## Headless guard: every market stall a town sets down is the one stall, Kingsmere's Meshy stall
## (meshy.json sq_market_stall replaces assets.json market_stall). General problem: one thing in the
## world drawn by two models, the old kit's striped Stall_Empty / Stall_Cart_Empty beside the Meshy
## one, so a square reads as two games. The rule (no fallbacks): a component a Meshy piece replaces
## keeps no catalogue variants of its own, and no script loads a kit stall file by name. Asserts:
##   - Real.variants("market_stall") is the Meshy stall and nothing else;
##   - assets.json market_stall lists no variants (the shadowed kit stalls are gone, not kept);
##   - no script under res://scripts names a kit stall file (Stall_Empty, Stall_Cart_Empty).
## Exit 1 on failure.
##   arch -arm64 godot --headless --path realm -s res://tools/stall_probe.gd

const Real := preload("res://scripts/realistic.gd")
const KIT := ["Stall_Empty", "Stall_Cart_Empty"]


func _init() -> void:
	var bad := 0
	var vs: Array = Real.variants("market_stall")
	var meshy := vs.filter(func(n): return String(n).begins_with("meshy_"))
	if vs.is_empty() or meshy.size() != vs.size():
		print("STALL FAIL market_stall draws %s; want only the Meshy stall" % [vs])
		bad += 1
	var comps := _components()
	var own: Array = (comps.get("market_stall", {}) as Dictionary).get("variants", [])
	if not own.is_empty():
		print("STALL FAIL assets.json market_stall keeps %d kit variants the Meshy stall replaces" % own.size())
		bad += 1
	for path in _scripts("res://scripts"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for k in KIT:
				if lines[i].contains("\"%s\"" % k):
					print("STALL FAIL %s:%d loads the kit's %s" % [path, i + 1, k])
					bad += 1
	print("STALL %s: %d problems" % ["PASS" if bad == 0 else "FAIL", bad])
	quit(1 if bad > 0 else 0)


func _components() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/assets.json"))
	return (d as Dictionary).get("components", {}) if d is Dictionary else {}


func _scripts(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir.path_join(d)))
	return out
