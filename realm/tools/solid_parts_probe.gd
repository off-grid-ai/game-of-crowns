extends SceneTree
## A guard: every part a builder stretches into a solid has sides (round 9: the King's plinth and steps were the
## kit's floor tile, a flat plane, stretched upward, and drew only squares floating in the air). For every
## catalogue variant built from pieces (assets.json components.<id>.variants[].spec.pieces), each part made a
## block out of a plane (its own mesh under 5% as thick on an axis as it is long, and that axis scaled more than
## twice the others) is measured: the area of its faces that look sideways (normal within 60 degrees of level)
## against its box's four sides. Under half is a fail: a plane drawn as a slab, not a solid. A part thin by its
## nature and kept thin (a cloth, a washing line) is not a solid and is not measured.
## Prints CHECK lines; exits 1 on any fail.
##   arch -arm64 godot --headless --path realm -s res://tools/solid_parts_probe.gd [-- <assets.json path>]

const HB := preload("res://scripts/house_builder.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := args[0] if args.size() > 0 else "res://data/assets.json"
	var comps: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary).get("components", {})
	var hb := HB.new()
	var checked := 0
	var failed := 0
	for id in comps:
		if not comps[id] is Dictionary:
			continue
		for v in (comps[id] as Dictionary).get("variants", []):
			var pieces: Array = ((v as Dictionary).get("spec", {}) as Dictionary).get("pieces", [])
			for p in pieces:
				if not p is Array or (p as Array).size() < 4:
					continue
				var sc: Vector3 = Vector3(float(p[3][0]), float(p[3][1]), float(p[3][2])) if p[3] is Array else Vector3.ONE * float(p[3])
				if is_equal_approx(sc.y, sc.x) and is_equal_approx(sc.y, sc.z):
					continue  # scaled whole: it keeps its own shape
				var name := String(p[0])
				if name.begins_with("res://") and not ResourceLoader.exists(name):
					continue
				var n: Node3D = hb._piece(name)
				# Its own shape, unscaled: is any axis a plane's (under 5% of its longest), stretched up into a block?
				var own := AABB()
				var own_first := true
				for mi0 in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
					if (mi0 as MeshInstance3D).mesh == null:
						continue
					var a0: AABB = (mi0 as Node3D).transform * (mi0 as MeshInstance3D).mesh.get_aabb()
					own = a0 if own_first else own.merge(a0)
					own_first = false
				var longest := maxf(own.size.x, maxf(own.size.y, own.size.z))
				var made_solid := false
				for ax in 3:
					var others := [sc.x, sc.y, sc.z]
					others.remove_at(ax)
					if longest > 0.0 and own.size[ax] < 0.05 * longest and sc[ax] > 2.0 * maxf(float(others[0]), float(others[1])):
						made_solid = true
				if not made_solid:
					n.free()
					continue
				var side := 0.0
				var box := AABB()
				var first := true
				for mi in n.find_children("*", "MeshInstance3D", true, false) + ([n] if n is MeshInstance3D else []):
					var mesh: Mesh = (mi as MeshInstance3D).mesh
					if mesh == null:
						continue
					var xf := Transform3D(Basis.from_scale(sc), Vector3.ZERO) * (mi as Node3D).transform
					var f: PackedVector3Array = mesh.get_faces()
					for t in f.size() / 3:
						var a: Vector3 = xf * f[t * 3]
						var b: Vector3 = xf * f[t * 3 + 1]
						var c: Vector3 = xf * f[t * 3 + 2]
						var cr := (b - a).cross(c - a)
						var area := cr.length() * 0.5
						if area > 0.0 and absf(cr.normalized().y) < 0.5:
							side += area
						for q in [a, b, c]:
							box = AABB(q, Vector3.ZERO) if first else box.expand(q)
							first = false
				n.free()
				var want := 2.0 * (box.size.x + box.size.z) * box.size.y
				var ok := want <= 0.0001 or side >= 0.5 * want
				checked += 1
				if not ok:
					failed += 1
				print("CHECK solid part %s %s: %s, sides %.2f m2 of its box's %.2f m2 (%s)" % [id, name, "ok" if ok else "FAIL", side, want, str(box.size)])
	print("CHECK solid parts: %d planes made blocks, %d fail" % [checked, failed])
	quit(1 if failed > 0 else 0)
