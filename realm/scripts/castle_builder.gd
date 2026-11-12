extends "res://scripts/house_builder.gd"
## A great house's castle from the Meshy castle set (docs/art/castle: keep, round and square towers, wall stretches)
## laid out on the castle's plan below; the town walls (town_wall) are still the MegaKit's, as follows. Formerly:
## assembles a great house's castle from the Medieval Village MegaKit, the way
## house_builder.gd raises a townhouse: the kit's 2 m stone wall panel stacked in
## 3 m storeys makes the keep, the towers, the gatehouse and the curtain walls;
## the same panel, cut down, makes the merlons; the kit's tiled roofs and tower
## cones crown them, and its banners hang on the keep and the gate. Baked into
## one mesh. Roof tiles, trims and banners take the holder's colour through the
## team-colour shader (team_colour.gd); the stone stays as it is.
## The art thread's Blender proof (art-direction/kit.py kit_keep, kit_wall) is
## the assembly; the castle's size comes from the seat's rank (data/assets.json).
##
## Its frame: metres, the gate on +Z (toward the town's square), the keep at the
## back, y = 0 the ground.

const WALL := "Wall_UnevenBrick_Straight"
const WINDOW := "Wall_UnevenBrick_Window_Thin_Round"
const DOOR := "Wall_UnevenBrick_Door_Round"
const CONE := "Roof_Tower_RoundTiles"
const CAP := "Floor_UnevenBrick"
const SIDES := [0.0, PI / 2, PI, -PI / 2]


## spec (all in kit cells of 2 m and storeys of 3 m): w, d: the bailey across and
## deep; wall_storeys: the curtain's height; keep, keep_storeys: the keep's side and
## height; tower_storeys: the corner and wall towers; side_towers: a tower midway
## along each side wall (a royal seat); banner: the banners' size; seed.
func build_castle(spec: Dictionary) -> ArrayMesh:
	var w := int(spec.get("w", 18))
	var d := int(spec.get("d", 16))
	var wall_st := int(spec.get("wall_storeys", 2))
	var keep := int(spec.get("keep", 4))
	var keep_st := int(spec.get("keep_storeys", 5))
	var tower_st := int(spec.get("tower_storeys", wall_st + 2))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var parts := []
	var hx := w * CELL / 2.0
	var hz := d * CELL / 2.0
	var kh := keep * CELL / 2.0
	# The keep stands into the back wall, its back face a little proud of it.
	var keep_at := Vector3(0, 0, -hz + kh - 1.0)
	var gate_at := Vector3(0, 0, hz)
	# Towers: a corner tower at each corner, and on a royal seat one midway along
	# each side wall; each a 2x2 stone shaft under the kit's tiled cone.
	var towers: Array = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	if spec.get("side_towers", false):
		towers.append_array([Vector3(-hx, 0, 0), Vector3(hx, 0, 0)])
	# The castle is the Meshy castle set (docs/art/castle, data/meshy.json ck_*; castle.json meshy): a round tower at
	# each corner and either side of the gate, a square tower midway along each side wall of a royal seat, the curtain
	# as wall stretches along each run, and the keep, all in the 01-town painted stone and red tiles.
	for t in towers:
		var corner := absf(t.x) > 0.01 and absf(t.z) > 0.01
		_meshy_tower(parts, t, tower_st, "round" if corner else "square")
	_meshy_curtain(parts, spec, wall_st)
	# The gatehouse astride the front wall: Meshy's (data/meshy.json gatehouse, imported), in metres.
	var meshy_gate := meshy_gatehouse()
	if meshy_gate != "":
		# Set into the curtain, a little proud of it, between two round towers (castle.json meshy_gate; round 4:
		# 3.5 m proud with nothing either side, it stood out on its own in front of the wall).
		var mg := _meshy_gate()
		parts.append([meshy_gate, Transform3D(Basis(), gate_at + Vector3(0, 0, float(mg.get("z", 1.0))))])
		if bool(mg.get("towers", false)):
			for sx in [-1, 1]:
				_meshy_tower(parts, gate_at + Vector3(sx * gate_tower_x(), 0, 1.0), wall_st + 2, "round")
	# The keep (ck_keep: its own steps up to its door, its turrets and red roofs), stood into the back wall.
	var km: Dictionary = _meshy().get("keep", {})
	var keep_file := _meshy_file("ck_keep")
	if keep_file != "":
		var ks := float(km.get("scale", 1.0))
		parts.append([keep_file, Transform3D(Basis.from_scale(Vector3.ONE * ks), keep_at + Vector3(0, 0, float(km.get("z", 0.0))))])
	# The house's banners on the keep and the gate are castle_life.gd's (its painted arms).
	var stone := _castle_stone()
	if not stone.is_empty():
		for p in parts:
			var piece := String(p[0])
			if piece == DOOR or piece.begins_with("res://") or piece.begins_with("Stairs"):
				p.append({})  # the doors, the stairs, Meshy's gate and the banners keep their own
	return _bake(parts, stone)


## The castle's own stone (data/castle.json stone; 01-town: warm light-grey stone; round 5: flat grey slabs
## with dark mortar and orange course strips): the kit's stone lightened and warmed, and the timber courses
## the wall panel carries at each storey laid in a darker stone of the same, so no orange strips run round the
## walls. Its own materials, graded, so look.gd's kit tints leave them be.
func _castle_stone() -> Dictionary:
	var k: Dictionary = preload("res://scripts/data.gd").value("castle", "stone", {})
	if k.is_empty():
		return {}
	var n: Node3D = _piece(WALL)
	var brick: BaseMaterial3D = null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		for i in (mi as MeshInstance3D).mesh.get_surface_count():
			var m: Material = (mi as MeshInstance3D).get_active_material(i)
			if m is BaseMaterial3D and m.resource_name == "MI_UnevenBrick":
				brick = m
	n.free()
	if brick == null:
		return {}
	var rgb := func(a, fallback: Color) -> Color: return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else fallback
	var out := {}
	var wall: BaseMaterial3D = brick.duplicate()
	wall.resource_name = "MI_UnevenBrick_castle"
	wall.albedo_color = rgb.call(k.get("tint"), Color.WHITE)
	wall.set_meta("graded", true)
	out["MI_UnevenBrick"] = wall
	if k.has("course_tint"):
		var course: BaseMaterial3D = brick.duplicate()
		course.resource_name = "MI_UnevenBrick_course"
		course.albedo_color = rgb.call(k.get("course_tint"), Color.WHITE)
		course.set_meta("graded", true)
		out["MI_WoodTrim"] = course
	return out


## The castle set's sizes (data/castle.json meshy): keep {scale, z}; tower {round, square: the pieces; width, metres
## across; cone, metres of roof over the stone}; wall {piece; length, its metres along; depth, metres through; over,
## metres of merlons over the walk}.
static func _meshy() -> Dictionary:
	return preload("res://scripts/data.gd").value("castle", "meshy", {})


## A castle-set piece's file (realm/assets/meshy/<name>/<name>.glb, meshy_import.py), else "".
static func _meshy_file(name: String) -> String:
	var path := "res://assets/meshy/%s/%s.glb" % [name, name]
	return path if ResourceLoader.exists(path) else ""


## A piece's size as imported, metres [across, deep, tall] (its import.json size_m).
static func _meshy_size(name: String) -> Array:
	var f := FileAccess.open("res://assets/meshy/%s/import.json" % name, FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f else null
	return (j as Dictionary).get("size_m", [7.4, 7.4, 14.0]) if j is Dictionary else [7.4, 7.4, 14.0]


## A tower of the castle set at `at` (its foot): its stone `storeys` high under its roof, its width castle.json
## meshy.tower.width (the import's own across, about 7-8 m, would crowd the curtain's 2 m bays).
func _meshy_tower(parts: Array, at: Vector3, storeys: int, kind: String) -> void:
	var k: Dictionary = _meshy().get("tower", {})
	var name := String(k.get(kind, "ck_wall_tower"))
	var file := _meshy_file(name)
	if file == "":
		return
	var sz: Array = _meshy_size(name)
	var h := storeys * STOREY + float(k.get("cone", 4.0))
	var across := float(k.get("width", 6.0))
	parts.append([file, Transform3D(Basis.from_scale(Vector3(across / float(sz[0]), h / float(sz[2]), across / float(sz[1]))), at)])


## The curtain: along each run (curtain_runs) as many wall stretches as fit their length, each stretched to share
## the run evenly, its outer face on the run's line, as tall as the curtain's storeys and its merlons.
func _meshy_curtain(parts: Array, spec: Dictionary, storeys: int) -> void:
	var k: Dictionary = _meshy().get("wall", {})
	var file := _meshy_file(String(k.get("piece", "ck_wall_stretch")))
	if file == "":
		return
	var size := _meshy_size(String(k.get("piece", "ck_wall_stretch")))
	var length := float(size[0])
	var depth := float(k.get("depth", 3.0))
	var tall := storeys * STOREY + float(k.get("over", 1.5))
	var sy := tall / float(size[2])
	var sz := depth / float(size[1])
	for run in curtain_runs(spec):
		var a: Vector3 = run["a"]
		var b: Vector3 = run["b"]
		var out: Vector3 = run["out"]
		var span := a.distance_to(b)
		var n := maxi(1, int(round(span / length)))
		var basis := Basis.looking_at(-out, Vector3.UP)  # its front (+Z) outward
		for i in n:
			var mid := a.lerp(b, (i + 0.5) / n) - out * depth / 2.0
			parts.append([file, Transform3D(basis * Basis.from_scale(Vector3(span / n / length, sy, sz)), mid)])


## The curtain's 2 m bays on each side (front, right, back, left), as offsets along the side's frame: all
## but where a corner tower, a side tower, the gatehouse or the keep stands. One rule, read by the build
## and by curtain_runs.
static func curtain_bays(spec: Dictionary) -> Array:
	var w := int(spec.get("w", 18))
	var d := int(spec.get("d", 16))
	var gh := 4 * CELL / 2.0
	var kh := int(spec.get("keep", 4)) * CELL / 2.0
	var gaps := {0: [-gh, gh], 2: [-kh, kh]}
	var out := []
	for side in 4:
		var along := w if side % 2 == 0 else d
		var cut: Array = gaps.get(side, [])
		var offs := []
		for i in along:
			var off := (i - (along - 1) / 2.0) * CELL
			if absf(off) > along * CELL / 2.0 - 2.0:
				continue  # inside a corner tower
			if spec.get("side_towers", false) and side % 2 == 1 and absf(off) < 2.0:
				continue  # inside the side tower
			if not cut.is_empty() and off > float(cut[0]) - 1.0 and off < float(cut[1]) + 1.0:
				continue  # the gatehouse or the keep stands here
			offs.append(off)
		out.append(offs)
	return out


## The curtain as straight runs between towers, in the castle's own frame (metres): [{a, b, out}], a and b
## the run's ends on its outer face line at the ground, out its outward normal. Stone walls (walls.gd) and
## the guards on the walks (castle_life.gd) follow these.
static func curtain_runs(spec: Dictionary) -> Array:
	var hx := int(spec.get("w", 18)) * CELL / 2.0
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	var bays := curtain_bays(spec)
	var runs := []
	for side in 4:
		var basis := Basis(Vector3.UP, SIDES[side])
		var half := hz if side % 2 == 0 else hx
		var offs: Array = bays[side]
		var i := 0
		while i < offs.size():
			var j := i
			while j + 1 < offs.size() and absf(float(offs[j + 1]) - float(offs[j]) - CELL) < 0.01:
				j += 1
			runs.append({"a": basis * Vector3(float(offs[i]) - CELL / 2.0, 0, half), "b": basis * Vector3(float(offs[j]) + CELL / 2.0, 0, half), "out": basis * Vector3(0, 0, 1), "side": side})
			i = j + 1
	return runs


## The towers (corner, side and the gate's two), in the castle's frame: [{at, top}] (metres, top: its top course).
static func towers(spec: Dictionary) -> Array:
	var hx := int(spec.get("w", 18)) * CELL / 2.0
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	var wall_st := int(spec.get("wall_storeys", 2))
	var tower_st := int(spec.get("tower_storeys", wall_st + 2))
	var out := []
	for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]:
		out.append({"at": c, "top": tower_st * STOREY + 0.12})
	if spec.get("side_towers", false):
		for c in [Vector3(-hx, 0, 0), Vector3(hx, 0, 0)]:
			out.append({"at": c, "top": tower_st * STOREY + 0.12})
	if bool(_meshy_gate().get("towers", false)):
		for sx in [-1, 1]:
			out.append({"at": Vector3(sx * gate_tower_x(), 0, hz + 1.0), "top": (wall_st + 2) * STOREY + 0.12, "gate": true})
	return out


## Meshy's gatehouse in the curtain (data/castle.json meshy_gate): z, metres its middle stands out from the
## wall's line; half_w and half_d, its half width and depth (its import's size); towers, the kit's cone towers
## either side of it.
static func _meshy_gate() -> Dictionary:
	return preload("res://scripts/data.gd").value("castle", "meshy_gate", {})


## How far either side of the middle the gate's two towers stand (metres): beside the kit's gatehouse, or
## beside Meshy's, which is wider.
static func gate_tower_x() -> float:
	return float(_meshy_gate().get("half_w", 7.35)) + 1.0
	return 4 * CELL / 2.0 + 1.0


## The gatehouse's front face, the castle's frame (metres, +z the town): torches, the arms and the gate's
## walkers stand by it (castle_life.gd).
static func gate_front(spec: Dictionary) -> float:
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	var mg := _meshy_gate()
	return hz + float(mg.get("z", 1.0)) + float(mg.get("half_d", 2.53))


## Meshy's gatehouse (meshy.json pieces.gatehouse.replaces "castle_gate"), once imported: its file, else "".
static func meshy_gatehouse() -> String:
	var g: Dictionary = (preload("res://scripts/data.gd").value("meshy", "pieces", {}) as Dictionary).get("gatehouse", {})
	var path := "res://assets/meshy/gatehouse/gatehouse.glb"
	return path if String(g.get("replaces", "")) == "castle_gate" and ResourceLoader.exists(path) else ""


## Round turrets (01-town's round towers under red cones; castle.json turrets): the castle's four corner towers, the
## two flanking its gate (and a town gate's) and the town wall's towers at its turns (a _block with round), as Kenney's
## hexagonal tower (Castle Kit, CC0: its base, as
## many middles as its height takes, its pointed roof) at castle size, its stone the castle's (the kit's stone laid
## world-free, warmed as castle.json stone.tint), its roof the kit's terracotta tiles.
func _round_tower(parts: Array, at: Vector3, storeys: int) -> void:
	var k: Dictionary = preload("res://scripts/data.gd").value("castle", "turrets", {})
	var sc := float(k.get("scale", 4.4))
	var Real := preload("res://scripts/realistic.gd")
	var dummy := StandardMaterial3D.new()
	var st: Dictionary = preload("res://scripts/data.gd").value("castle", "stone", {})
	var stone_dye := {"like": "Floor_UnevenBrick", "triplanar": float(k.get("triplanar", 0.5))}
	if st.get("tint") is Array:
		stone_dye["tint"] = st["tint"]
	var stone := {"colormap": Real.dyed(dummy, stone_dye)}
	var tiles := {"colormap": Real.dyed(dummy, {"like": "Roof_RoundTiles_4x4", "material": "MI_RoundTiles", "triplanar": float(k.get("tile_triplanar", 0.7)), "tint": k.get("roof_tint", [0.88, 0.78, 0.72])})}
	var h := storeys * STOREY + 0.12
	var base_h := 1.31 * sc  # tower-hexagon-base.glb is 1.31 tall at 1
	var mid_h := 0.46 * sc  # tower-hexagon-mid.glb 0.46
	if h <= base_h:
		parts.append(["res://assets/castle/tower-hexagon-base.glb", Transform3D(Basis.from_scale(Vector3(sc, h / 1.31, sc)), at), stone])
	else:
		parts.append(["res://assets/castle/tower-hexagon-base.glb", Transform3D(Basis.from_scale(Vector3.ONE * sc), at), stone])
		var n := maxi(1, int(ceil((h - base_h) / mid_h)))
		var sy := (h - base_h) / (n * 0.46)
		for i in n:
			parts.append(["res://assets/castle/tower-hexagon-mid.glb", Transform3D(Basis.from_scale(Vector3(sc, sy, sc)), at + Vector3(0, base_h + i * (h - base_h) / n, 0)), stone])
	parts.append(["res://assets/castle/tower-hexagon-roof.glb", Transform3D(Basis.from_scale(Vector3(sc, sc * float(k.get("roof_tall", 1.3)), sc)), at + Vector3(0, h, 0)), tiles])


## A town's stone wall (01-town's wall round the town, its towers and its gate; towns.gd _town_wall lays it out):
## the curtain's bays, each [centre (metres, town-local, its foot), yaw (its outer face toward +Z turned by yaw),
## index along its run], and cone towers at `towers` (metres, their foot), the curtain `storeys` high. The castle's
## stone, the same slits and merlons. Baked into one mesh.
func town_wall(bays: Array, towers: Array, storeys: int, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts := []
	for b in bays:
		var basis := Basis(Vector3.UP, float(b[1]))
		var off := (int(b[2]) + 0.5) * CELL  # its place along the run: every third bay slit, as the castle's
		_curtain(parts, Transform3D(basis, Vector3(b[0]) - basis * Vector3(off, 0, 0)), off, storeys)
	for t in towers:
		_block(parts, t, 2, 2, storeys + 2, rng, {"cone": true, "windows": 0.3, "round": true})
	var stone := _castle_stone()
	if not stone.is_empty():
		for p in parts:
			if String(p[0]).begins_with("res://"):
				p.append({})
	return _bake(parts, stone)


## A town wall's gatehouse (walls.gd and towns.gd _town_wall: where a road runs through a town's wall; 01-town's
## arched gate in the town wall): Meshy's gatehouse, in metres, the way out on +Z, the wall's line at z 0, y 0 the
## road. Empty until it is imported.
func town_gate(_wall_st: int, _seed: int) -> ArrayMesh:
	var parts := []
	var meshy_gate := meshy_gatehouse()
	if meshy_gate != "":
		parts.append([meshy_gate, Transform3D()])
	return _bake(parts)


## How many storeys of stone podium the keep stands on, with its steps up the front (data/castle.json
## steps.storeys).
static func podium() -> int:
	return int((preload("res://scripts/data.gd").value("castle", "steps", {}) as Dictionary).get("storeys", 1))


## A stone block (tower, keep, gatehouse) standing on `at`: its four faces of
## panels in storeys, stretched a hair so its corners close, capped with stone,
## and as opts say: windows (a share of the upper panels), a door or a gate in
## its front, merlons, the tiled cone (a 2x2 tower) or a tiled roof (the keep).
func _block(parts: Array, at: Vector3, wc: int, dc: int, storeys: int, rng: RandomNumberGenerator, opts: Dictionary) -> void:
	if opts.get("cone", false) and bool(opts.get("round", false)) and wc == 2 and dc == 2:
		_round_tower(parts, at, storeys)
		return
	var hw := wc * CELL / 2.0
	var hd := dc * CELL / 2.0
	for f in storeys:
		var y := f * STOREY
		for side in 4:
			var along := wc if side % 2 == 0 else dc
			var half := hd if side % 2 == 0 else hw
			var stretch := (along * CELL + 0.2) / (along * CELL)
			var basis := Basis(Vector3.UP, SIDES[side])
			for i in along:
				var off := (i - (along - 1) / 2.0) * CELL * stretch
				var pos := at + basis * Vector3(off, y, half)
				var piece := WALL
				if opts.get("door", false) and side == 0 and f == 0 and i == along / 2:
					piece = DOOR
					parts.append(["Door_1_Round", Transform3D(basis, pos)])
				elif f > 0 and rng.randf() < float(opts.get("windows", 0.0)):
					piece = WINDOW
					parts.append(["Window_Thin_Round1", Transform3D(basis, pos)])
				parts.append([piece, Transform3D(basis.scaled(Vector3(stretch, 1, 1)), pos)])
	var top := storeys * STOREY + 0.12
	if opts.get("cone", false):
		parts.append([CONE, Transform3D(Basis.from_scale(Vector3(hw / 2.0, 1.0, hd / 2.0) * 0.85), at + Vector3(0, top, 0))])
		return
	for ix in wc:
		for iz in dc:
			parts.append([CAP, Transform3D(Basis(), at + Vector3((ix - (wc - 1) / 2.0) * CELL, top - 0.02, (iz - (dc - 1) / 2.0) * CELL))])
	if opts.get("crenel", false):
		for side in 4:
			_merlons(parts, Transform3D(Basis(Vector3.UP, SIDES[side]), at + Basis(Vector3.UP, SIDES[side]) * Vector3(0, 0, hd if side % 2 == 0 else hw)), wc if side % 2 == 0 else dc, top)
	if opts.get("roof", false):
		# A tiled roof over the leads, set in from the parapet, gabled to the town (data/castle.json keep_roof: in,
		# cells in from the walls; lift, metres over the leads). Two cells in, the keep's roof hid behind its
		# parapet and the keep read as a flat slab (round 3); one cell in, its red gable shows over the merlons.
		var kr: Dictionary = preload("res://scripts/data.gd").value("castle", "keep_roof", {})
		var rc := maxi(wc - int(kr.get("in", 2)), 2)
		var roof := "Roof_RoundTiles_%dx%d" % [rc * 2, rc * 2]
		var lift := float(kr.get("lift", 0.3))
		if not ResourceLoader.exists(DIR % roof):
			rc = maxi(wc - 2, 2)  # the kit has no roof that size: the smaller one, as before
			roof = "Roof_RoundTiles_%dx%d" % [rc * 2, rc * 2]
		if ResourceLoader.exists(DIR % roof):
			parts.append([roof, Transform3D(Basis(), at + Vector3(0, top + lift, 0))])
			var gable := "Roof_Front_Brick%d" % (rc * 2)
			if ResourceLoader.exists(DIR % gable):
				parts.append([gable, Transform3D(Basis(), at + Vector3(0, top + lift, rc * CELL / 2.0))])
				parts.append([gable, Transform3D(Basis(Vector3.UP, PI), at + Vector3(0, top + lift, -rc * CELL / 2.0))])


## One 2 m bay of curtain wall, `off` along the run's frame (+Z outward): stone
## both faces, a walk along its top, a merlon on its outer edge every other metre.
func _curtain(parts: Array, frame: Transform3D, off: float, storeys: int) -> void:
	# An arrow slit in the top storey's outer face every few bays (castle.json stone.slit_every; round 5: the
	# curtain a flat grey slab).
	var every := int((preload("res://scripts/data.gd").value("castle", "stone", {}) as Dictionary).get("slit_every", 0))
	var slit := every > 0 and posmod(int(round(off / CELL)), every) == 0
	for f in storeys:
		parts.append([WINDOW if slit and f == storeys - 1 else WALL, frame * Transform3D(Basis(), Vector3(off, f * STOREY, 0))])
		parts.append([WALL, frame * Transform3D(Basis(Vector3.UP, PI), Vector3(off, f * STOREY, -0.4))])
	var top := storeys * STOREY + 0.12
	parts.append([CAP, frame * Transform3D(Basis.from_scale(Vector3(1.0, 1.0, 0.3)), Vector3(off, top - 0.02, -0.2))])
	parts.append([WALL, frame * Transform3D(Basis.from_scale(Vector3(0.42, 0.4, 1.6)), Vector3(off - 0.5, top - 0.05, 0))])


## Merlons along one face's top: a cut-down panel every other metre, the corners closed.
func _merlons(parts: Array, frame: Transform3D, cells: int, top: float) -> void:
	var n := cells * 2
	for k in n:
		if k % 2 == 0 or k == n - 1:
			parts.append([WALL, frame * Transform3D(Basis.from_scale(Vector3(0.42, 0.4, 1.6)), Vector3(-cells + 0.5 + k, top - 0.05, 0))])
