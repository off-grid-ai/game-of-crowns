extends SceneTree
## Fails (exit 1) when a world component stands at the wrong size: each kit model is
## measured as the game scales it (realistic.gd: its true length) and its height held
## against its component's heightRange in realm/data/assets.json (metres). The shape is
## a build-time asset validation pass, as engines run on import (Unreal's asset audit).
##   arch -arm64 godot --headless --path realm -s res://tools/scale_check.gd

const Real := preload("res://scripts/realistic.gd")
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	var comps: Dictionary = Data.value("assets", "components", {})
	var bad := 0
	var checked := 0
	for id in comps:
		if not comps[id] is Dictionary or not (comps[id] as Dictionary).has("heightRange"):
			continue
		var r: Array = comps[id]["heightRange"]
		for n in Real.variants(id):
			if not Real.KIT.has(n):
				continue
			var h: float = Real.height(n) / Real.S
			checked += 1
			if h <= 0.0:
				print("SCALE FAIL %s %s: no model (missing file?)" % [id, n])
				bad += 1
			elif h < float(r[0]) or h > float(r[1]):
				# What its true length would have to be to stand mid-range: the fix is a data edit.
				var mid := (float(r[0]) + float(r[1])) / 2.0
				print("SCALE FAIL %s %s: %.1f m tall, wants %s-%s m (length %.2f -> about %.2f)" % [id, n, h, r[0], r[1], float(Real.KIT[n][1]), float(Real.KIT[n][1]) * mid / h])
				bad += 1
	# The kit woods' grown trees, one to two houses tall (realm/data/assets.json woods.tree_range).
	var tr: Array = Data.value("assets", "woods.tree_range", [])
	if tr.size() == 2:
		for role in ["pine", "oak"]:
			var th: float = Data.num("assets", "woods.kit.%s.height" % role, 0.0)
			checked += 1
			if th < float(tr[0]) or th > float(tr[1]):
				print("SCALE FAIL woods %s: %.1f m tall, wants %s-%s m (one to two houses)" % [role, th, tr[0], tr[1]])
				bad += 1
	print("SCALE %s: %d of %d models out of range" % ["PASS" if bad == 0 else "FAIL", bad, checked])
	quit(1 if bad > 0 else 0)
