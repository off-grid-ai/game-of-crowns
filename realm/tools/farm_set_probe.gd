extends SceneTree
## A guard: the town's working buildings come from the Meshy farm set (docs/research/meshy-farm-set.md; Mac's next
## Meshy wave after the square): the armoury, the farm barn, the granary and the yard's livestock pen, and the trades'
## wave (alehouse, stables, windmill, tannery, dyer; docs/research/meshy-trades-set.md) each resolve to
## their Meshy piece in place of the kit's, and none carries house-colour patches (the square's lesson: a face-by-face
## mask out of Meshy's baked atlas reads as smears). Prints each piece's footprint in metres (the kit's it replaced:
## docs/research/meshy-farm-set.md). Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/farm_set_probe.gd

const Real := preload("res://scripts/realistic.gd")
const SET := {"armoury": "fs_armoury", "barn": "fs_barn", "granary": "fs_granary", "yard_pen": "fs_pen",
	"alehouse": "ts_alehouse", "town_stables": "ts_stables", "windmill": "ts_windmill", "tannery": "ts_tannery", "dyer": "ts_dyer"}


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var fail := 0
	for comp in SET:
		var got := Real.one(comp)
		var ok := got == "meshy_" + String(SET[comp])
		var f := Real.footprint(got)
		print("CHECK farm set %s -> %s (footprint %.1f x %.1f m): %s" % [comp, got, f.x / 0.12, f.y / 0.12, "meshy" if ok else "KIT: FAIL"])
		if not ok:
			fail += 1
		var piece := String(SET[comp])
		var path := "res://assets/meshy/%s/%s.glb" % [piece, piece]
		var patches := 0
		var n: Node = (load(path) as PackedScene).instantiate() if ResourceLoader.exists(path) else null
		if n:
			for mi in n.find_children("*", "MeshInstance3D", true, false):
				var mesh: Mesh = (mi as MeshInstance3D).mesh
				for i in (mesh.get_surface_count() if mesh else 0):
					var m := mesh.surface_get_material(i)
					if m and m.resource_name.ends_with("_house"):
						patches += 1
			n.free()
		elif ok:
			print("CHECK farm set %s: %s missing: FAIL" % [comp, path])
			fail += 1
		if patches > 0:
			print("CHECK farm set %s: %d house-colour patches: FAIL" % [comp, patches])
			fail += 1
	print("CHECK farm set: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
