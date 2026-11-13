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

const SIDES := [0.0, PI / 2, PI, -PI / 2]


## spec (all in kit cells of 2 m and storeys of 3 m): w, d: the bailey across and
## deep; wall_storeys: the curtain's height; keep, keep_storeys: the keep's side and
## height; tower_storeys: the corner and wall towers; side_towers: a tower midway
## along each side wall (a royal seat); banner: the banners' size; seed.
func build_castle(spec: Dictionary) -> ArrayMesh:
	var wall_st := int(spec.get("wall_storeys", 2))
	var parts := []
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	var gate_at := Vector3(0, 0, hz)
	# The castle is the Meshy castle set (docs/art/castle, data/meshy.json ck_*; castle.json meshy): a round tower at
	# each corner and either side of the gate, a square tower midway along each side wall of a royal seat, the curtain
	# as wall stretches along each run, and the keep, all in the 01-town painted stone and red tiles.
	for t in towers(spec):
		if not t.get("gate", false):
			_meshy_tower(parts, t["at"], int(t["storeys"]), String(t["kind"]))
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
	var keep_file := _meshy_file("ck_keep")
	if keep_file != "":
		parts.append([keep_file, keep_xform(spec)])
	# The house's banners on the keep and the gate are castle_life.gd's (its painted arms), placed from the spec the
	# castle carries (realistic.gd castle_spec).
	return _bake(parts)


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
func _meshy_tower(parts: Array, at: Vector3, storeys: int, kind: String, yaw := 0.0) -> void:
	var file := _meshy_file(String(_meshy().get("tower", {}).get(kind, "ck_wall_tower")))
	if file != "":
		parts.append([file, tower_xform(at, storeys, kind, yaw)])


## Where a castle-set tower stands in the castle's frame and how it is stretched (its own metres -> the castle's):
## the one placement, so what hangs on it (castle_life.gd's arms) finds its face.
## `yaw` turns its painted cloth (on the piece's +Z face) from +Z.
static func tower_xform(at: Vector3, storeys: int, kind: String, yaw := 0.0) -> Transform3D:
	var k: Dictionary = _meshy().get("tower", {})
	var sz: Array = _meshy_size(String(k.get(kind, "ck_wall_tower")))
	var h := storeys * STOREY + float(k.get("cone", 4.0))
	var across := float(k.get("width", 6.0))
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(across / float(sz[0]), h / float(sz[2]), across / float(sz[1]))), at)


## How a town wall's tower at `at` (town-local, its foot; the town's heart at the origin) is turned: its cloth out to
## the country, away from the town (01-town: the arms hang down the outer face of every wall tower).
static func tower_out(at: Vector3) -> float:
	return atan2(at.x, at.z)


## Where the keep (ck_keep) stands in the castle's frame: into the back wall, castle.json meshy.keep's scale and z.
static func keep_xform(spec: Dictionary) -> Transform3D:
	var km: Dictionary = _meshy().get("keep", {})
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	var kh := int(spec.get("keep", 4)) * CELL / 2.0
	return Transform3D(Basis.from_scale(Vector3.ONE * float(km.get("scale", 1.0))), Vector3(0, 0, -hz + kh - 1.0 + float(km.get("z", 0.0))))


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
		out.append({"at": c, "top": tower_st * STOREY + 0.12, "storeys": tower_st, "kind": "round"})
	if spec.get("side_towers", false):
		for c in [Vector3(-hx, 0, 0), Vector3(hx, 0, 0)]:
			out.append({"at": c, "top": tower_st * STOREY + 0.12, "storeys": tower_st, "kind": "square"})
	if bool(_meshy_gate().get("towers", false)):
		for sx in [-1, 1]:
			out.append({"at": Vector3(sx * gate_tower_x(), 0, hz + 1.0), "top": (wall_st + 2) * STOREY + 0.12, "storeys": wall_st + 2, "kind": "round", "gate": true})
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


## A town's stone wall (01-town's wall round the town, its towers and its gate; towns.gd _town_wall lays it out):
## the curtain's bays, each [centre (metres, town-local, its foot), yaw (its outer face toward +Z turned by yaw),
## index along its run], and cone towers at `towers` (metres, their foot), the curtain `storeys` high. The castle's
## stone, the same slits and merlons. Baked into one mesh.
func town_wall(bays: Array, towers: Array, storeys: int, seed: int) -> ArrayMesh:
	# The castle set (docs/art/castle): along each straight run of bays (consecutive, one heading) as many wall
	# stretches as fit, stretched evenly, outer face on the line; a round tower at each turn. The kit curtain is gone.
	var parts := []
	var k: Dictionary = _meshy().get("wall", {})
	var file := _meshy_file(String(k.get("piece", "ck_wall_stretch")))
	if file != "":
		var size := _meshy_size(String(k.get("piece", "ck_wall_stretch")))
		var depth := float(k.get("depth", 3.0))
		var sy := (storeys * STOREY + float(k.get("over", 1.5))) / float(size[2])
		var sz := depth / float(size[1])
		var i := 0
		while i < bays.size():
			var j := i
			while j + 1 < bays.size() and int(bays[j + 1][2]) == int(bays[j][2]) + 1 and absf(angle_difference(float(bays[j + 1][1]), float(bays[j][1]))) < 0.01:
				j += 1
			var basis := Basis(Vector3.UP, float(bays[i][1]))
			var along: Vector3 = basis * Vector3.RIGHT
			var start: Vector3 = Vector3(bays[i][0]) - along * CELL / 2.0
			var span := (j - i + 1) * CELL
			var n := maxi(1, int(round(span / float(size[0]))))
			for q in n:
				var mid := start + along * span * (q + 0.5) / n - basis * Vector3(0, 0, depth / 2.0)
				parts.append([file, Transform3D(basis * Basis.from_scale(Vector3(span / n / float(size[0]), sy, sz)), mid)])
			i = j + 1
	for t in towers:
		_meshy_tower(parts, t, storeys + 2, "round", tower_out(t))
	return _bake(parts)


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

