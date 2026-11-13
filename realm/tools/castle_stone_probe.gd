extends SceneTree
## Headless proof that the castle's stone keeps its own colour and its banners wear the house's (target
## docs/art/target/01-town.jpg: grey stone, red roofs, red eagle banners; render pass 2243's castle frame: the
## keep's stone splashed with red triangles, the towers' cloth hanging cream). No realm, no bridge, no GPU:
##   arch -arm64 godot --headless --path realm -s res://tools/castle_stone_probe.gd
## For each castle-set piece (realm/assets/meshy/ck_*/<name>.glb, meshy_import.py), every face it gives the house
## colour (material MI_RoundTiles_house*) is sampled in its own painted texture over its whole area: a face whose
## texels are mostly grey stone is stone dyed red. Fails when more than STONE_MAX of a piece's house faces (by area)
## are stone. Then the castle's banners: castle_life.gd hangs the house's arms on every front tower and the keep.
## Then the same over the castle as it is baked (castle_builder.gd, every variant in assets.json components.castle):
## each piece keeps its own painted atlas (house_builder.gd _bake merged surfaces by material name, and every
## Meshy piece names its atlas "Material_0", so the towers drew with the keep's atlas: pass 2243's red triangles).
## Prints "CASTLE STONE …" lines and "CASTLE STONE PASS" or "CASTLE STONE FAIL n"; quits 0 or 1.

const Data := preload("res://scripts/data.gd")
const Castle := preload("res://scripts/castle_builder.gd")
const Life := preload("res://scripts/castle_life.gd")
const PIECES := ["ck_keep", "ck_wall_tower", "ck_corner_tower", "ck_wall_stretch"]
const BAKED := ["ck_keep", "ck_wall_tower", "ck_wall_stretch"]  # in every castle (a seat has no square towers)
const STONE_MAX := 0.1  # the share of a piece's house-coloured area that may be grey stone (edges of a roof)
const STONE_SAT := 0.22  # a texel this grey or greyer is stone, not paint

var _fails := 0


func _initialize() -> void:
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CASTLE STONE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	for p: String in PIECES:
		var path := "res://assets/meshy/%s/%s.glb" % [p, p]
		if not ResourceLoader.exists(path):
			_check(false, "%s: not imported (%s)" % [p, path])
			continue
		var root: Node = (load(path) as PackedScene).instantiate()
		var house_area := 0.0
		var stone_area := 0.0
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			var mesh := mi.mesh
			for s in mesh.get_surface_count():
				var m := mesh.surface_get_material(s)
				if m == null or not String(m.resource_name).begins_with("MI_RoundTiles_house"):
					continue
				var tex: Texture2D = (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null
				if tex == null:
					continue
				var img := tex.get_image()
				if img.is_compressed():
					img.decompress()
				var a := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				var n := idx.size() if idx.size() > 0 else v.size()
				for t in range(0, n, 3):
					var i0 := idx[t] if idx.size() > 0 else t
					var i1 := idx[t + 1] if idx.size() > 0 else t + 1
					var i2 := idx[t + 2] if idx.size() > 0 else t + 2
					var area := (v[i1] - v[i0]).cross(v[i2] - v[i0]).length() * 0.5
					house_area += area
					stone_area += area * _grey_share(img, uv[i0], uv[i1], uv[i2])
		var share := stone_area / maxf(house_area, 1e-6)
		_check(house_area == 0.0 or share <= STONE_MAX, "%s: %.0f%% of its house-coloured area is grey stone (max %.0f%%)" % [p, share * 100.0, STONE_MAX * 100.0])
		root.free()
	_baked()
	_banners()
	_wall_towers()
	print("CASTLE STONE %s" % ("PASS" if _fails == 0 else "FAIL %d" % _fails))
	quit(0 if _fails == 0 else 1)


## The baked castle: every piece's own atlas is drawn, and its house-coloured surfaces are paint, not stone.
func _baked() -> void:
	var castle: Dictionary = (Data.value("assets", "components", {}) as Dictionary).get("castle", {})
	for v: Dictionary in castle.get("variants", []):
		var spec: Dictionary = v.get("spec", {})
		var mesh: ArrayMesh = Castle.new().build_castle(spec)
		# castle_life dresses it (its arms, standards, guards, torches) from the spec it reads back (g2: it read none, the
		# cloth hung cream).
		var node := Node3D.new()
		var model := MeshInstance3D.new()
		model.name = "Model"
		model.mesh = mesh
		node.add_child(model)
		_check(Life.spec_of(node) == spec, "castle %s: castle_life reads back the spec it was built from" % String(v.get("name", spec.get("seed", "?"))))
		node.free()
		var drawn := {}
		var house_area := 0.0
		var stone_area := 0.0
		for s in mesh.get_surface_count():
			var m := mesh.surface_get_material(s)
			var tex: Texture2D = (m as BaseMaterial3D).albedo_texture if m is BaseMaterial3D else null
			if tex == null:
				continue
			drawn[tex.resource_path.get_file()] = true
			if not String(m.resource_name).begins_with("MI_RoundTiles_house"):
				continue
			var img := tex.get_image()
			if img.is_compressed():
				img.decompress()
			var a := mesh.surface_get_arrays(s)
			var vx: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			var n := idx.size() if idx.size() > 0 else vx.size()
			for t in range(0, n, 3):
				var i0 := idx[t] if idx.size() > 0 else t
				var i1 := idx[t + 1] if idx.size() > 0 else t + 1
				var i2 := idx[t + 2] if idx.size() > 0 else t + 2
				var area := (vx[i1] - vx[i0]).cross(vx[i2] - vx[i0]).length() * 0.5
				house_area += area
				stone_area += area * _grey_share(img, uv[i0], uv[i1], uv[i2])
		var name := String(v.get("name", spec.get("seed", "?")))
		for p: String in BAKED:
			_check(drawn.has("%s_Image_0.jpg" % p), "castle %s: %s draws with its own atlas" % [name, p])
		var share := stone_area / maxf(house_area, 1e-6)
		_check(share <= STONE_MAX, "castle %s: %.0f%% of its house-coloured area is grey stone (max %.0f%%)" % [name, share * 100.0, STONE_MAX * 100.0])


## The share of a face's texels (sampled on a barycentric grid) that are grey stone.
func _grey_share(img: Image, a: Vector2, b: Vector2, c: Vector2) -> float:
	var grey := 0
	var all := 0
	var w := img.get_width()
	var h := img.get_height()
	const K := 4
	for i in K + 1:
		for j in K + 1 - i:
			var l1 := float(i) / K
			var l2 := float(j) / K
			var p := a * (1.0 - l1 - l2) + b * l1 + c * l2
			var px := img.get_pixel(clampi(int(fposmod(p.x, 1.0) * w), 0, w - 1), clampi(int(fposmod(p.y, 1.0) * h), 0, h - 1))
			all += 1
			if px.s < STONE_SAT:
				grey += 1
	return float(grey) / maxf(all, 1)


## The castle's banners (castle_life.gd _arms; castle.json arms.keep, arms.tower, in the piece's own metres): each
## hangs in front of its piece's face (nothing of the piece stands in front of it), and a tower's covers the cream
## cloth the tower is painted with (pass 2243: cream cloth, no arms; the kit-sized hangs sat inside the pieces).
func _banners() -> void:
	var k: Dictionary = Data.value("castle", "arms", {})
	for pair in [["ck_keep", "keep", true], ["ck_wall_tower", "tower", false]]:
		var h: Dictionary = k.get(pair[1], {})
		if h.is_empty():
			_check(false, "castle.json arms.%s: the house's arms on %s" % [pair[1], pair[0]])
			continue
		var root: Node = (load("res://assets/meshy/%s/%s.glb" % [pair[0], pair[0]]) as PackedScene).instantiate()
		var mesh: Mesh = (root.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).mesh
		var x0 := float(h["x"]) - float(h["w"]) / 2.0
		var x1 := float(h["x"]) + float(h["w"]) / 2.0
		var y0 := float(h["top"]) - float(h["h"])
		var y1 := float(h["top"])
		var mirrors: Array = [1.0, -1.0] if pair[2] else [1.0]
		for sx: float in mirrors:
			var lo := minf(sx * x0, sx * x1)
			var hi := maxf(sx * x0, sx * x1)
			var front := -INF
			var cream := 0
			var covered := 0
			for s in mesh.get_surface_count():
				var a := mesh.surface_get_arrays(s)
				var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
				for q in v:
					if q.x > lo and q.x < hi and q.y > y0 and q.y < y1:
						front = maxf(front, q.z)
				var m := mesh.surface_get_material(s)
				var img: Image = (m as BaseMaterial3D).albedo_texture.get_image() if m is BaseMaterial3D and (m as BaseMaterial3D).albedo_texture else null
				if img == null or pair[2]:
					continue
				if img.is_compressed():
					img.decompress()
				var uv: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
				var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
				for t in range(0, idx.size(), 3):
					var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
					if c.z < 2.0:
						continue  # the town-facing side only
					var u := (uv[idx[t]] + uv[idx[t + 1]] + uv[idx[t + 2]]) / 3.0
					var px := img.get_pixel(clampi(int(u.x * img.get_width()), 0, img.get_width() - 1), clampi(int(u.y * img.get_height()), 0, img.get_height() - 1))
					if px.v > 0.78 and px.s > 0.06 and px.s < 0.3 and px.h > 0.08 and px.h < 0.18:
						cream += 1
						if c.x > lo and c.x < hi and c.y > y0 and c.y < y1:
							covered += 1
			_check(float(h["z"]) > front, "%s arms (x %.1f): hang at z %.2f, in front of its face (%.2f)" % [pair[0], sx * float(h["x"]), float(h["z"]), front])
			if not pair[2]:
				_check(cream > 0 and covered >= cream * 0.85, "%s arms cover its painted cream cloth (%d of %d faces)" % [pair[0], covered, cream])
		root.free()


## A town wall's towers (castle_builder.gd town_wall, walls.gd _arms): each turned with its cloth, and the arms over
## it, out to the country, away from the town's heart (g2: every tower's cloth faced the town's +Z, cream).
func _wall_towers() -> void:
	for t: Vector3 in [Vector3(30, 0, 0), Vector3(-20, 0, 20), Vector3(0, 0, -25)]:
		var face := Castle.tower_xform(t, 4, "round", Castle.tower_out(t)).basis.orthonormalized() * Vector3(0, 0, 1)
		var out := Vector3(t.x, 0, t.z).normalized()
		_check(face.dot(out) > 0.99, "town wall tower at %s: its cloth faces out (%.2f)" % [t, face.dot(out)])
