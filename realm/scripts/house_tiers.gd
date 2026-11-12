extends RefCounted
## One house of a tier, composed from the Medieval Village kit's pieces (house_builder.gd bakes it):
## a hovel, a cottage, a townhouse, a merchant's house, a burgher's hall, a manor, and the town's
## working buildings (the inn, the alehouse, the guild hall, the forge, the stables, the armoury,
## the granary, the tannery). Each tier (data/assets.json house_kit.tiers) gives its ranges and
## chances; the house's own seed rolls them, so the same seed is the same house every run.
##
## Who solved this: modular-kit house assembly is how Quaternius ships the kit (its demo scenes
## are built from these pieces), and how Anno 1800 and Foundation vary a tier: one footprint and
## storey rule per tier, then the roof, the wall mix and the extras rolled per building.
## Manor Lords' burgage houses are gable to the street with a yard behind; a merchant's turns its
## eaves to the street with dormers; Foundation's upgraded houses add jetties, chimneys, signs.
## Our code only reads the tier and lays the pieces.

const Data := preload("res://scripts/data.gd")
const CELL := 2.0
const STOREY := 3.0

var _b  # house_builder.gd: loads the pieces and bakes them
var _parts: Array = []
var _rng := RandomNumberGenerator.new()
var _t: Dictionary = {}  # the tier, with the spec's own keys on top
var _k: Dictionary = {}  # house_kit
static var _mats := {}  # "<kit material>|<look>" -> a material made once and shared


func _init(builder) -> void:
	_b = builder


## A number or a [lowest, highest] range from the tier, rolled.
func _roll(key: String, fallback: float) -> float:
	var v = _t.get(key, fallback)
	if v is Array and (v as Array).size() >= 2:
		return _rng.randf_range(float(v[0]), float(v[1]))
	return float(v)


func _rolli(key: String, fallback: int) -> int:
	var v = _t.get(key, fallback)
	if v is Array and (v as Array).size() >= 2:
		return _rng.randi_range(int(v[0]), int(v[1]))
	return int(v)


## One key of a {key: weight} table, by weight.
func _pick(table, fallback: String) -> String:
	if not table is Dictionary or (table as Dictionary).is_empty():
		return fallback
	var total := 0.0
	for key in table:
		total += float(table[key])
	var r := _rng.randf() * total
	for key in table:
		r -= float(table[key])
		if r <= 0.0:
			return String(key)
	return String(table.keys()[-1])


func _chance(key: String) -> bool:
	return _rng.randf() < float((_t.get("extras", {}) as Dictionary).get(key, 0.0))


func _add(piece: String, xf: Transform3D) -> void:
	_parts.append([piece, xf])


static func _roof_name(slope_cells: int, ridge_cells: int) -> String:
	return "Roof_RoundTiles_%dx%d" % [slope_cells * 2, ridge_cells * 2]


static func _has(piece: String) -> bool:
	return ResourceLoader.exists("res://assets/village/%s.gltf" % piece)


## A kit material re-made for this house's look (a plaster's wash, a roof's covering), once per look.
## Its name keeps the kit's (team_colour.gd keys on the prefix) and says the look after it.
func _look(kit_mat: String, look: String, tint: Color) -> Material:
	var key := kit_mat + "|" + look
	if _mats.has(key):
		return _mats[key]
	var src: Material = _kit_material(kit_mat)
	if not src is BaseMaterial3D:
		return src
	var m: BaseMaterial3D = src.duplicate()
	m.resource_name = "%s_%s" % [kit_mat, look]
	m.albedo_color = tint
	m.set_meta("graded", true)  # its look is final: look.gd's kit_tints leave it be (a roadside house is a lone mesh)
	_mats[key] = m
	return m


## The kit's own material by name, from the piece that carries it.
func _kit_material(name: String) -> Material:
	var from := {"MI_Plaster": "Wall_Plaster_Straight", "MI_RoundTiles": "Roof_RoundTiles_4x4", "MI_UnevenBrick": "Wall_UnevenBrick_Straight", "MI_WoodTrim": "Wall_Plaster_WoodGrid"}
	var n: Node3D = _b._piece(from.get(name, "Wall_Plaster_Straight"))
	var found: Material = null
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		for s in (mi as MeshInstance3D).mesh.get_surface_count():
			var m: Material = (mi as MeshInstance3D).get_active_material(s)
			if m and m.resource_name == name:
				found = m
	n.free()
	return found


static func _rgb(a, fallback: Color) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and (a as Array).size() >= 3 else fallback


## spec: {tier: a key of house_kit.tiers, seed}; any tier key in the spec overrides the tier's.
func build(spec: Dictionary) -> ArrayMesh:
	_k = Data.value("assets", "house_kit", {})
	var tiers: Dictionary = _k.get("tiers", {})
	_t = (tiers.get(String(spec["tier"]), {}) as Dictionary).duplicate(true)
	for key in spec:
		_t[key] = spec[key]
	_rng.seed = int(spec.get("seed", 1)) * 7717 + String(spec["tier"]).hash()
	_parts = []
	var w := _rolli("w", 2)
	var d := _rolli("d", 3)
	var floors := _rolli("floors", 2)
	var ridge := _pick(_t.get("ridge", {}), "along")  # along: gable to the street (Manor Lords' burgage); across: eaves to it
	# The kit's roofs come in set sizes: turn the ridge, then shorten the house, until one fits.
	for _try in 6:
		if ridge == "along" and _has(_roof_name(w, d)) and _has("Roof_Front_Brick%d" % (w * 2)):
			break
		if ridge == "across" and _has(_roof_name(d, w)) and _has("Roof_Front_Brick%d" % (d * 2)):
			break
		var other := "across" if ridge == "along" else "along"
		if (other == "along" and _has(_roof_name(w, d))) or (other == "across" and _has(_roof_name(d, w))):
			ridge = other
			break
		if d > 2:
			d -= 1
		elif w > 2:
			w -= 1
	var roof_kind := _pick(_t.get("roofs", {}), "tile")
	var mix := _pick(_t.get("walls", {}), "timber")
	var washes: Array = _k.get("washes", [[1, 1, 1]])
	var allowed: Array = _t.get("washes", range(washes.size()))
	var wash_i := int(allowed[_rng.randi() % allowed.size()]) if not allowed.is_empty() else 0
	var remap := {
		"MI_Plaster": _look("MI_Plaster", "wash%d" % wash_i, _rgb(washes[wash_i % washes.size()], Color.WHITE)),
		"MI_RoundTiles": _look("MI_RoundTiles", roof_kind, _rgb((_k.get("roof_tints", {}) as Dictionary).get(roof_kind), Color.WHITE)),
		# Honey stone and honey timber (house_kit stone_tint, timber_tint; art target town-b): the kit's own read near black.
		"MI_UnevenBrick": _look("MI_UnevenBrick", "honey", _rgb(_k.get("stone_tint"), Color.WHITE)),
		"MI_WoodTrim": _look("MI_WoodTrim", "honey", _rgb(_k.get("timber_tint"), Color.WHITE)),
	}
	for key in remap.keys():
		if remap[key] == null:
			remap.erase(key)  # a kit without that material keeps its own
	var hw := w * CELL / 2.0
	var hd := d * CELL / 2.0
	var jet := float(_k.get("jetty_m", 0.45)) if floors >= 2 and _rng.randf() < float(_t.get("jetty", 0.0)) else 0.0
	var round_win := _rng.randf() < float(_t.get("round_windows", 0.5))
	var shutter_open := _rng.randf()
	var door_i := (w - 1) / 2 if w % 2 == 1 or _rng.randf() < 0.5 else w / 2
	var win: Dictionary = _t.get("windows", {})
	var arcade := _rng.randf() < float(_t.get("arcade", 0.0))  # the ground floor's front open in arches (a guild hall, a forge, stables)
	var shop := not arcade and _rng.randf() < float(_t.get("shop", 0.0))  # a shop front: wide windows either side of the door
	var back_door := _rng.randf() < 0.4
	var stair := floors >= 2 and w >= 3 and _chance("outside_stair")  # steps up the back wall to the upper floor's own door
	var fronts: Array = []  # each storey's front line (z)
	for f in floors:
		fronts.append(hd + jet * f)
	var back := -hd
	for f in floors:
		var y := f * STOREY
		var front: float = fronts[f]
		var fam := "UnevenBrick"
		match mix:
			"stone":
				fam = "UnevenBrick"
			"stone_timber":
				fam = "UnevenBrick" if f == 0 else "Plaster"
			_:
				fam = "Plaster"
		var stone := fam == "UnevenBrick"
		for side in 4:
			var along := w if side % 2 == 0 else d
			var rot: float = [0.0, PI / 2, PI, -PI / 2][side]
			var run := front - back  # a side wall's length: a jetty lengthens the upper storeys
			for i in along:
				var off := (i - (along - 1) / 2.0) * CELL
				var pos: Vector3
				var basis := Basis(Vector3.UP, rot)
				match side:
					0: pos = Vector3(off, y, front)
					2: pos = Vector3(-off, y, back)
					_:
						var pl := run / along
						var z := back + (i + 0.5) * pl
						pos = Vector3(hw if side == 1 else -hw, y, z)
						basis = basis * Basis.from_scale(Vector3(pl / CELL, 1, 1))
				var xf := Transform3D(basis, pos)
				var piece := ""
				var share := float(win.get("front_ground" if side == 0 and f == 0 else ("front" if side == 0 else ("back" if side == 2 else "sides")), 0.5))
				if side == 0 and f == 0 and i == door_i and not arcade:
					piece = "Wall_%s_Door_%s" % [fam, "Round" if round_win else "Flat"]
					_add(piece, xf)
					_add("Door_%d_%s" % [[1, 2][_rng.randi() % 2], "Round" if round_win else "Flat"], xf)
					continue
				if side == 0 and f == 0 and arcade:
					_add("Wall_Arch", xf)
					continue
				if side == 2 and f == 1 and i == 2 and stair:
					_add("Wall_%s_Door_Flat" % fam, xf)
					_add("Door_1_Flat", xf)
					continue
				if side == 2 and f == 0 and i == w - 1 and back_door:
					_add("Wall_%s_Door_Flat" % fam, xf)
					_add("Door_1_Flat", xf)
					continue
				if (side == 0 and f == 0 and shop) or _rng.randf() < share:
					var kind := "Wide_Flat" if (shop and side == 0 and f == 0) else ("Wide_Round" if round_win else "Wide_Flat")
					if not shop and _rng.randf() < 0.35:
						kind = "Thin_Round"
					_add("Wall_%s_Window_%s" % [fam, kind], xf)
					_add({"Wide_Round": "Window_Wide_Round1", "Wide_Flat": "Window_Wide_Flat1", "Thin_Round": "Window_Thin_Round1"}[kind], xf)
					var shut_kind := kind
					if (shop and side == 0 and f == 0) or _rng.randf() < float(_t.get("shutters", 0.5)):
						_add("WindowShutters_%s_%s" % [shut_kind, "Open" if (shop and f == 0) or _rng.randf() < shutter_open else "Closed"], xf)
					# A window box under an upper window on the street side (art target 01-town).
					if side == 0 and f > 0 and _chance("window_boxes"):
						_add("Prop_Crate", Transform3D(basis.scaled_local(Vector3(0.85, 0.2, 0.26)), pos + basis * Vector3(0, 0.82, 0.24)))
						# Flowers in the box (01-town: red flower boxes under the windows), the nature kit's flower group
						# cut down to the box's size (house_kit.window_flowers: its file and scale), sitting on its top.
						var wf: Array = _k.get("window_flowers", ["res://assets/nature/Flower_3_Group.gltf", [0.6, 0.16, 0.18]])
						var fs: Array = wf[1]
						_add(String(wf[0]), Transform3D(basis.scaled_local(Vector3(float(fs[0]), float(fs[1]), float(fs[2]))), pos + basis * Vector3(0.1, 1.02, 0.24)))
					continue
				if stone:
					piece = "Wall_UnevenBrick_Straight"
				elif f == 0:
					piece = "Wall_Plaster_Straight_Base" if mix == "timber" else "Wall_Plaster_Straight"
				else:
					piece = "Wall_Plaster_WoodGrid" if mix != "plaster" and _rng.randf() < 0.8 else "Wall_Plaster_Straight"
				_add(piece, xf)
		for cx in [-hw, hw]:
			for cz in [back, front]:
				var c: Array = _b.corner("Corner_Exterior_Brick" if stone else "Corner_Exterior_Wood", cx, cz - (front + back) * 0.5, y)
				var cxf: Transform3D = c[1]
				cxf.origin = Vector3(cx, y, cz)  # turned by which corner it is, standing where it is
				_add(String(c[0]), cxf)
		var stretch := (front - back) / (d * CELL)
		for ix in w:
			for iz in d:
				var fp := Vector3((ix - (w - 1) / 2.0) * CELL, y, back + (iz + 0.5) * CELL * stretch)
				_add("Floor_UnevenBrick" if f == 0 else "Floor_WoodDark", Transform3D(Basis.from_scale(Vector3(1, 1, stretch)), fp))
		# The jetty: the storey's beam end along the street, braced at each post (Foundation's upgraded houses).
		if f > 0 and jet > 0.0:
			for i in w:
				_add("Wall_BottomCover", Transform3D(Basis(), Vector3((i - (w - 1) / 2.0) * CELL, y, front)))
			for i in w + 1:
				_add("Roof_Support2", Transform3D(Basis(), Vector3(-hw + i * CELL, y, fronts[f - 1])))
	var top := floors * STOREY
	_roof(w, d, hw, back, fronts[floors - 1], top, ridge, roof_kind)
	_extras(w, d, hw, hd, back, fronts, floors, door_i, stair)
	return _b._bake(_parts, remap)


## The roof, its gables, dormers and chimneys. The roof is laid in its own frame (local x: down
## the slopes, local z: along the ridge), turned to the house: along, the gable to the street;
## across, the eaves to it.
func _roof(w: int, d: int, hw: float, back: float, front: float, top: float, ridge: String, roof_kind: String) -> void:
	var across := ridge == "across"
	var depth := front - back
	var zc := (front + back) * 0.5
	var slope_cells := d if across else w
	var ridge_cells := w if across else d
	var frame := Transform3D(Basis(Vector3.UP, PI / 2 if across else 0.0), Vector3(0, top, zc))
	var sx := depth / (d * CELL) if across else 1.0  # a jetty lengthens the slope axis (across) or the ridge (along)
	var sz := 1.0 if across else depth / (d * CELL)
	var half := (w * CELL if across else depth) * 0.5  # half the ridge's length
	var pitch := float((_k.get("pitch", {}) as Dictionary).get(roof_kind, 1.0)) * _roll("pitch", 1.0)
	var roof := _roof_name(slope_cells, ridge_cells)
	_add(roof, frame * Transform3D(Basis.from_scale(Vector3(sx, pitch, sz)), Vector3.ZERO))
	_b.verges(_parts, frame, roof, sx, pitch, sz)
	var gable := "Roof_Front_Brick%d" % (slope_cells * 2)
	for e in [1.0, -1.0]:
		_add(gable, frame * Transform3D(Basis(Vector3.UP, 0.0 if e > 0 else PI).scaled_local(Vector3(sx, pitch, 1)), Vector3(0, 0, e * half)))
	var box: AABB = _b.roof_box(roof)
	var ridge_y := box.end.y * pitch
	var eave_y := box.position.y * pitch
	var run := box.size.x * 0.5 * sx
	var slope := (ridge_y - eave_y) / maxf(run, 0.1)
	# Dormers on the street slope (across) or both side slopes (along), spaced along the ridge.
	var n := mini(_rolli("dormers", 0), int(floor(half * 2.0 / 2.6)))
	if n > 0:
		var b := 0.5
		var x_front := (ridge_y - b) / slope
		var x_o := x_front - 1.9
		if x_o > 0.15 and b + 2.7 <= ridge_y - slope * x_o + 0.25:
			var slopes: Array = [-1.0] if across else [1.0, -1.0]  # across: local -x is the street side
			if across and _rng.randf() < float(_t.get("dormers_back", 0.0)):
				slopes.append(1.0)
			for sgn in slopes:
				for i in n:
					var z := -half + (i + 0.5) * (half * 2.0 / n)
					_add("Roof_Dormer_RoundTile", frame * Transform3D(Basis(Vector3.UP, 0.0 if sgn > 0 else PI), Vector3(x_o * sgn, b, z)))
	# Chimneys: a stone stack up the outside of one gable end (art target 01-town), and on bigger
	# houses one or two through the ridge.
	if _rng.randf() < float(_t.get("chimney", 0.7)):
		var e := -1.0 if not across or _rng.randf() < 0.5 else 1.0  # along: the back gable
		var cz := e * (half + 0.48)
		var cx := 0.0 if _rng.randf() < 0.5 else _rng.randf_range(-0.6, 0.6) * (run / 2.0)
		# From the ground (nothing may go below it: the model stands on its lowest point) to a metre
		# above the ridge, its capped top piece last; each 3 m piece stretched a little to fit.
		var tall := top + ridge_y + 0.9
		var stacks := maxi(1, int(round(tall / 3.0)))
		var k := tall / (3.0 * stacks)
		for i in stacks:
			_add("Prop_Chimney" if i == stacks - 1 else "Prop_Chimney2", frame * Transform3D(Basis.from_scale(Vector3(1, k, 1)), Vector3(cx, -top + 3.0 * k * i, cz)))
	for i in _rolli("ridge_chimneys", 0):
		var z := (-0.55 if i % 2 == 0 else 0.55) * half
		_add("Prop_Chimney" if i % 2 == 0 else "Prop_Chimney2", frame * Transform3D(Basis(), Vector3(0, ridge_y - 1.8, z)))


## What makes a house its own: a porch over the door, a lean-to at the back, an outside stair,
## a signboard, a balcony, the holder's banner, ivy, and anything the tier bakes in (a forge's anvil, a stable's racks).
func _extras(w: int, d: int, hw: float, hd: float, back: float, fronts: Array, floors: int, door_i: int, stair: bool) -> void:
	var front0: float = fronts[0]
	var door_x := (door_i - (w - 1) / 2.0) * CELL
	if _chance("porch"):
		_add("Overhang_Roof_Plaster", Transform3D(Basis(), Vector3(door_x, 2.85, front0 + 1.0)))
		for e in [-0.9, 0.9]:
			_add("Prop_Support", Transform3D(Basis(), Vector3(door_x + e, -0.05, front0)))
	if _chance("sign"):
		# A signboard on an iron-and-timber arm beside the door, square to the street (Anno's shops,
		# 01-town's inn): the arm out from the wall, the board hung under its end.
		var sx := door_x + (1.0 if door_i < w - 1 else -1.0)
		_add("Prop_Support", Transform3D(Basis.from_scale(Vector3(1, 1, 0.5)), Vector3(sx, -0.25, front0)))
		_add("Floor_WoodLight", Transform3D(Basis(Vector3(0, 0, 1), PI / 2) * Basis.from_scale(Vector3(0.32, 1, 0.24)), Vector3(sx, 2.15, front0 + 0.72)))
	if not stair and _chance("lean_to"):
		# A lean-to against the back wall: a pent roof on two posts, a crate or two under it.
		var span := mini(w, 2)
		for i in span:
			var x := (i - (span - 1) / 2.0) * CELL
			_add("Roof_Wooden_2x1", Transform3D(Basis(Vector3.UP, PI), Vector3(x, 1.9, back)))
		for e in [-1.0, 1.0]:
			_add("Corner_Exterior_Wood", Transform3D(Basis.from_scale(Vector3(1, 0.64, 1)), Vector3(e * span * CELL * 0.5, 0, back - 1.45)))
		_add("Prop_Crate", Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled_local(Vector3.ONE * 0.6), Vector3(-0.4, 0, back - 0.6)))
	if stair:
		# Three flights rising along the back wall (the kit's flight climbs a metre over two, toward its -z),
		# to the upper floor's door at the far end (a lodger's, a workshop loft's).
		for i in 3:
			_add("Stairs_Exterior_Straight", Transform3D(Basis(Vector3.UP, -PI / 2), Vector3(-hw + 1.0 + i * CELL, i * 1.0 + 0.2, back - 1.0)))  # its foot 0.2 below its origin: kept above ground
	if floors >= 2 and _chance("balcony"):
		var bx := ((_rng.randi() % w) - (w - 1) / 2.0) * CELL
		var fz: float = fronts[1]
		_add("Floor_WoodDark", Transform3D(Basis.from_scale(Vector3(1, 1, 0.55)), Vector3(bx, STOREY, fz + 0.55)))
		_add("Balcony_Simple_Straight" if _rng.randf() < 0.5 else "Balcony_Cross_Straight", Transform3D(Basis(), Vector3(bx, STOREY, fz)))
	if floors >= 2 and _chance("banner"):
		# The holder's banner hung down the street front of the upper storey, by a corner (art target
		# town-b: the lion banners on the square's houses; its cloth takes the house's colour, MI_Banner).
		var sc := float(_k.get("banner_scale", 0.7))
		var bx := (hw - 0.62) * (1.0 if _rng.randf() < 0.5 else -1.0) - 0.8 * sc  # the cloth hangs from its left edge
		var fz: float = fronts[1]
		_add("res://assets/props/Banner_1.gltf", Transform3D(Basis.from_scale(Vector3.ONE * sc), Vector3(bx, 2.0 * STOREY - 0.35 - 0.84 * sc, fz + 0.1 * sc + 0.04)))
	if _chance("vines"):
		var vx := (hw - 0.4) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_add("Prop_Vine1" if _rng.randf() < 0.5 else "Prop_Vine4", Transform3D(Basis(), Vector3(vx, minf(floors * STOREY, 5.5) - 0.3, front0 + 0.1)))
	# What the tier bakes in, in the house's frame (metres; +z the street): [piece, [x, y, z], yaw, scale].
	# A piece name without a path is the village kit's; res:// paths load any glTF (the props kit's anvil).
	for p in _t.get("props", []):
		if not p is Array or (p as Array).size() < 2:
			continue
		var at: Array = p[1]
		var pos := Vector3(float(at[0]), float(at[1]), float(at[2]))
		var yaw := float(p[2]) if (p as Array).size() > 2 else 0.0
		var sc := float(p[3]) if (p as Array).size() > 3 else 1.0
		var anchor := String(p[4]) if (p as Array).size() > 4 else "centre"
		if anchor == "front":
			pos.z += front0
		elif anchor == "back":
			pos.z += back
		var name := String(p[0])
		if name.begins_with("res://") and not ResourceLoader.exists(name):
			continue
		_add(name, Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3.ONE * sc), pos))
