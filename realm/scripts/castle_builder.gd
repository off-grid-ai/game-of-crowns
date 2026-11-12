extends "res://scripts/house_builder.gd"
## Assembles a great house's castle from the Medieval Village MegaKit, the way
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
const ARCH := "DoorFrame_Round_Brick"  # the kit's stone round door frame, at twice size the gate's arch
const BARS := "Prop_MetalFence_Simple"  # the kit's iron railing, stood up tall: the portcullis
const LEAF := "Door_8_Round"  # the kit's iron-bound plank door: the gate's two leaves
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
	var banner := float(spec.get("banner", 1.6))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.get("seed", 1))
	var parts := []
	var hx := w * CELL / 2.0
	var hz := d * CELL / 2.0
	var kh := keep * CELL / 2.0
	var gate_w := 4  # the gatehouse, cells across
	var gh := gate_w * CELL / 2.0
	# The keep stands into the back wall, its back face a little proud of it.
	var keep_at := Vector3(0, 0, -hz + kh - 1.0)
	var gate_at := Vector3(0, 0, hz)
	# Towers: a corner tower at each corner, and on a royal seat one midway along
	# each side wall; each a 2x2 stone shaft under the kit's tiled cone.
	var towers: Array = [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(hx, 0, hz), Vector3(-hx, 0, hz)]
	if spec.get("side_towers", false):
		towers.append_array([Vector3(-hx, 0, 0), Vector3(hx, 0, 0)])
	for t in towers:
		_block(parts, t, 2, 2, tower_st, rng, {"cone": true, "windows": 0.3})
	# Curtain walls between them: front (gate on it), right, back (keep in it), left. With stone walls on
	# (walls.gd, --walls=stone) they're left out: walls.gd stands stone walls that can breach in their place.
	if not stone_curtains():
		var bays := curtain_bays(spec)
		for side in 4:
			var half := (hz if side % 2 == 0 else hx)
			var frame := Transform3D(Basis(Vector3.UP, SIDES[side]), Basis(Vector3.UP, SIDES[side]) * Vector3(0, 0, half))
			for off in bays[side]:
				_curtain(parts, frame, off, wall_st)
	# The gatehouse, astride the front wall, its gate through two storeys; with --landmarks=meshy and Meshy's
	# gatehouse imported (data/meshy.json gatehouse: castle), that piece in its place instead, in metres.
	var meshy_gate := meshy_gatehouse()
	if meshy_gate != "":
		# Set into the curtain, a little proud of it, between two cone towers (castle.json meshy_gate; round 4:
		# 3.5 m proud with nothing either side, it stood out on its own in front of the wall).
		var mg := _meshy_gate()
		parts.append([meshy_gate, Transform3D(Basis(), gate_at + Vector3(0, 0, float(mg.get("z", 1.0))))])
		if bool(mg.get("towers", false)):
			for sx in [-1, 1]:
				_block(parts, gate_at + Vector3(sx * gate_tower_x(), 0, 1.0), 2, 2, wall_st + 2, rng, {"cone": true, "windows": 0.5})
	else:
		_block(parts, gate_at, gate_w, 3, wall_st + 1, rng, {"gate": true, "crenel": true, "windows": 0.5, "portcullis": float(spec.get("gate_portcullis", 2.4))})
		for sx in [-1, 1]:
			_block(parts, gate_at + Vector3(sx * (gh + 1.0), 0, 1.0), 2, 2, wall_st + 2, rng, {"cone": true, "windows": 0.5})
	# The keep: tall, crenellated, a tiled roof over its leads, a turret at each corner. On a seat's castle it
	# stands on a stone podium, a broad flight of steps up to its door (01-town: the steps up to the keep, the
	# red carpet down them; castle_life.gd lays the carpet): the kit's exterior stairs, a metre a flight.
	var up := podium()
	if up > 0:
		_block(parts, keep_at, keep, keep, up, rng, {})
		var kf := keep_at.z + kh
		var rises := up * int(STOREY)
		for i in rises:
			var y := float(rises - 1 - i)
			var z := kf + 1.0 + 2.0 * i
			for sx in [-1.0, 1.0]:
				parts.append(["Stairs_Exterior_Straight", Transform3D(Basis(), Vector3(sx, y, z))])
				for j in int(y):
					parts.append(["Stairs_Exterior_Sides", Transform3D(Basis(), Vector3(sx, float(j), z))])
	var lift := Vector3(0, up * STOREY, 0)
	# Its face windowed (castle.json keep_roof.windows; round 4: at 0.45 the keep read as a flat grey wall).
	var kwin := float((preload("res://scripts/data.gd").value("castle", "keep_roof", {}) as Dictionary).get("windows", 0.45))
	_block(parts, keep_at + lift, keep, keep, keep_st, rng, {"door": true, "crenel": true, "windows": kwin, "roof": true})
	for k in 4:
		var c := Vector3((-1 if k in [0, 3] else 1) * (kh + 0.3), 0, (-1 if k < 2 else 1) * (kh + 0.3))
		_block(parts, keep_at + c, 2, 2, keep_st + up + (1 if k % 2 == 0 else 0), rng, {"cone": true, "windows": 0.4})
	# Banners: down the keep's face over its door and either side of the gate. With the castle lived in
	# (castle_life.gd, --castle-life=on) it hangs the house's painted arms in these places instead.
	if not load("res://scripts/castle_life.gd").on():
		var top := (keep_st + up) * STOREY
		var b := Basis(Vector3.UP, 0.0).scaled(Vector3.ONE * banner)
		parts.append(["res://assets/props/Banner_1.gltf", Transform3D(b, keep_at + Vector3(-0.8 * banner, top - 2.0 - 0.84 * banner, kh + 0.15))])
		for sx in [-1, 1]:
			parts.append(["res://assets/props/Banner_2.gltf", Transform3D(b.scaled(Vector3.ONE * 0.8), gate_at + Vector3(sx * (gh - 0.9) - 0.65 * banner, (wall_st + 1) * STOREY - 0.6 - 0.7 * banner, 3.0 + 0.15))])
	var stone := _castle_stone()
	if not stone.is_empty():
		for p in parts:
			var piece := String(p[0])
			if piece in [LEAF, BARS, DOOR] or piece.begins_with("res://") or piece.begins_with("Stairs"):
				p.append({})  # the gate's leaves, its portcullis, the doors, the stairs, Meshy's gate and the banners keep their own
	return _bake(parts, stone)


## The castle's own stone (data/castle.json stone; 01-town: warm light-grey stone; round 5: flat grey slabs
## with dark mortar and orange course strips): the kit's stone lightened and warmed, and the timber courses
## the wall panel carries at each storey laid in a darker stone of the same, so no orange strips run round the
## walls. Its own materials, graded, so look.gd's kit tints leave them be. --castle-stone=kit: the kit's.
func _castle_stone() -> Dictionary:
	var k: Dictionary = preload("res://scripts/data.gd").value("castle", "stone", {})
	if k.is_empty() or not bool(k.get("on", true)) or OS.get_cmdline_user_args().has("--castle-stone=kit"):
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
	if meshy_gatehouse() == "" or bool(_meshy_gate().get("towers", false)):
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
	if meshy_gatehouse() != "":
		return float(_meshy_gate().get("half_w", 7.35)) + 1.0
	return 4 * CELL / 2.0 + 1.0


## The gatehouse's front face, the castle's frame (metres, +z the town): torches, the arms and the gate's
## walkers stand by it (castle_life.gd).
static func gate_front(spec: Dictionary) -> float:
	var hz := int(spec.get("d", 16)) * CELL / 2.0
	if meshy_gatehouse() != "":
		var mg := _meshy_gate()
		return hz + float(mg.get("z", 1.0)) + float(mg.get("half_d", 2.53))
	return hz + 3.0


## Meshy's gatehouse, if it stands in for the kit's (--landmarks=meshy, meshy.json pieces.gatehouse.replaces
## "castle_gate", and imported): its file, else "".
static func meshy_gatehouse() -> String:
	var Real = load("res://scripts/realistic.gd")
	if Real.landmarks() != "meshy":
		return ""
	var g: Dictionary = (preload("res://scripts/data.gd").value("meshy", "pieces", {}) as Dictionary).get("gatehouse", {})
	var path := "res://assets/meshy/gatehouse/gatehouse.glb"
	return path if String(g.get("replaces", "")) == "castle_gate" and ResourceLoader.exists(path) else ""


## A town wall's gatehouse (walls.gd: where a road runs through a town's ring wall; 01-town's arched gate in
## the town wall): the castle's own gate, its passage through and a cone tower either side, or Meshy's
## gatehouse with --landmarks=meshy; in metres, the way out on +Z, the wall's line at z 0, y 0 the road.
func town_gate(wall_st: int, seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var parts := []
	var gh := 4 * CELL / 2.0
	var meshy_gate := meshy_gatehouse()
	if meshy_gate != "":
		parts.append([meshy_gate, Transform3D()])
	else:
		_block(parts, Vector3.ZERO, 4, 3, wall_st + 1, rng, {"gate": true, "crenel": true, "windows": 0.5, "portcullis": 2.4})
		for sx in [-1, 1]:
			_block(parts, Vector3(sx * (gh + 1.0), 0, 0), 2, 2, wall_st + 2, rng, {"cone": true, "windows": 0.5})
	return _bake(parts)


## How many storeys of stone podium the keep stands on, with its steps up the front (data/castle.json
## steps.storeys; --keep-steps=off for none). 0: the keep on the bailey's floor, as before.
static func podium() -> int:
	var args := OS.get_cmdline_user_args()
	if args.has("--keep-steps=off"):
		return 0
	var k: Dictionary = preload("res://scripts/data.gd").value("castle", "steps", {})
	if args.has("--keep-steps=on") or bool(k.get("on", false)):
		return int(k.get("storeys", 1))
	return 0


## Stone curtains (walls.gd's switch, --walls=stone): the kit curtain is left out of the castle.
static func stone_curtains() -> bool:
	return load("res://scripts/walls.gd").on()


## A stone block (tower, keep, gatehouse) standing on `at`: its four faces of
## panels in storeys, stretched a hair so its corners close, capped with stone,
## and as opts say: windows (a share of the upper panels), a door or a gate in
## its front, merlons, the tiled cone (a 2x2 tower) or a tiled roof (the keep).
func _block(parts: Array, at: Vector3, wc: int, dc: int, storeys: int, rng: RandomNumberGenerator, opts: Dictionary) -> void:
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
				var front: bool = side == 0 or (side == 2 and bool(opts.get("gate", false)))
				if opts.get("gate", false) and front and f < 2 and absf(off) < CELL:
					# The gate: one door panel at twice the size fills the two middle cells, two storeys up, its
					# arch dressed in cut stone (the kit's round door frame), front and back; the passage runs
					# through between them (art target 01-town: an arched gate, not a door).
					if f == 0 and off < 0.0:
						var g := basis.scaled(Vector3(2.0, 2.0, 1.0))
						parts.append([DOOR, Transform3D(g, at + basis * Vector3(0, 0, half))])
						parts.append([ARCH, Transform3D(basis * Basis.from_scale(Vector3(2.0, 2.0, 1.5)), at + basis * Vector3(0, 0, half + 0.05))])
						if side == 0:
							_passage(parts, at, half, opts)
					continue
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


## The gate's passage through the gatehouse (the front face at +half, the back at -half): stone walls
## either side, a vaulted stone ceiling, a paved floor, the portcullis hanging half raised just inside the
## arch, and behind it the two plank leaves swung open against the walls. The arch at twice the kit's
## door is about 2.2 m wide and 4.6 m high. spec gate_portcullis: how high its foot hangs, in metres.
func _passage(parts: Array, at: Vector3, half: float, opts: Dictionary) -> void:
	const W := 1.1  # half the arch's width
	const H := 4.6  # the arch's crown
	var depth := half * 2.0
	var n := maxi(1, int(round(depth / CELL)))
	var step := depth / n
	var tall := Basis.from_scale(Vector3(step / CELL, H / STOREY, 1.0))
	for i in n:
		var z := half - step * (i + 0.5)
		parts.append([WALL, Transform3D(Basis(Vector3.UP, PI / 2) * tall, at + Vector3(-W, 0, z))])
		parts.append([WALL, Transform3D(Basis(Vector3.UP, -PI / 2) * tall, at + Vector3(W, 0, z))])
		var sc := Basis.from_scale(Vector3(W, 1.0, step / CELL))
		parts.append([CAP, Transform3D(Basis(Vector3.RIGHT, PI) * sc, at + Vector3(0, H, z))])
		parts.append([CAP, Transform3D(sc, at + Vector3(0, 0.03, z))])
	var up := float(opts.get("portcullis", 2.4))
	parts.append([BARS, Transform3D(Basis.from_scale(Vector3(W * 2.0 / 1.95, H / 2.87, 1.0)), at + Vector3(0, up, half - 0.7))])
	var leaf := Basis(Vector3.UP, PI / 2) * Basis.from_scale(Vector3(W / 1.1, H / 2.36, 1.0))
	for sx in [-1, 1]:
		parts.append([LEAF, Transform3D(leaf, at + Vector3(sx * (W - 0.12), 0.03, half - 1.4))])


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
