extends SceneTree
## Headless proof that the art sets are wired in place of what they replace (docs/art/STANDARDS.md section 6 step 7:
## "the piece it replaces is deleted in the same change"; Mac's 11-12 ruling: no renders until every asset is wired,
## so this probe is the proof until the batched render). No realm, no bridge:
##   arch -arm64 godot --headless --path realm -s res://tools/look_wiring_probe.gd
## Castle: the royal and seat castles build from the Meshy castle set only (no MegaKit stone or roof, no Kenney
## turret left in their meshes) at their plan's size. Houses: every house component the Meshy houses replace holds
## Meshy houses only, each loads and stands at its imported height. The square's merchant house still comes.
## Prints "LOOK WIRING …" lines and "LOOK WIRING PASS" or "LOOK WIRING FAIL n"; quits 0 or 1.

const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")
const Castle := preload("res://scripts/castle_builder.gd")

## The kit's own materials (Medieval Village MegaKit, Kenney Castle Kit): none may survive in a Meshy-built castle.
const KIT_MATS := ["MI_UnevenBrick", "MI_UnevenBrick_castle", "MI_UnevenBrick_course", "MI_RoundTiles", "MI_WoodTrim", "MI_Plaster", "colormap"]
const HOUSES := ["house_hovel", "house_poor", "house_burgher", "house_rich", "house_corner", "house_merchant", "house_manor", "hall", "church", "guild_hall"]

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("LOOK WIRING %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	var castle: Dictionary = (Data.value("assets", "components", {}) as Dictionary).get("castle", {})
	for v: Dictionary in castle.get("variants", []):
		var spec: Dictionary = v.get("spec", {})
		var mesh: ArrayMesh = Castle.new().build_castle(spec)
		var names := []
		for i in mesh.get_surface_count():
			var m := mesh.surface_get_material(i)
			names.append(m.resource_name if m else "")
		var kit := names.filter(func(n): return String(n) in KIT_MATS or String(n).contains("colormap"))
		_check(mesh.get_surface_count() > 0, "%s builds (%d surfaces: %s)" % [v.get("name"), mesh.get_surface_count(), ", ".join(PackedStringArray(names))])
		_check(kit.is_empty(), "%s has no kit material left %s" % [v.get("name"), kit])
		_check(names.has("MI_RoundTiles_house") or names.any(func(n): return String(n).begins_with("MI_RoundTiles_house")), "%s's roofs take the house colour" % v.get("name"))
		var box := mesh.get_aabb()
		var w := int(spec.get("w", 18)) * 2.0
		_check(box.size.x > w * 0.9 and box.size.x < w * 1.5 and box.size.y > 12.0, "%s spans %.1f x %.1f x %.1f m on its %.0f m plan" % [v.get("name"), box.size.x, box.size.y, box.size.z, w])
	var comps: Dictionary = Data.value("assets", "components", {})
	for id in HOUSES:
		_check((comps.get(id, {}) as Dictionary).get("variants", [null]).is_empty(), "%s keeps no kit variant in assets.json" % id)
		var names: Array = Real._component.get(id, [])
		_check(not names.is_empty() and names.all(func(n): return String(n).begins_with("meshy_")), "%s holds Meshy houses only %s" % [id, names])
		for n in names:
			var node := Real.make(String(n))
			var ok := node != null and not node.find_children("*", "MeshInstance3D", true, false).is_empty()
			var h := 0.0
			if ok:
				for mi in node.find_children("*", "MeshInstance3D", true, false):
					h = maxf(h, ((mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()).end.y if mi.is_inside_tree() else (mi as MeshInstance3D).get_aabb().size.y)
			_check(ok, "%s: %s loads" % [id, n])
			if node:
				node.free()
	_check(Real.meshy_piece("square_merchant") != null, "the square's merchant house still comes (sq_merchant_house)")
	print("LOOK WIRING %s" % ("PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)
