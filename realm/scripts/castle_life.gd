extends Node3D
## A seat's kit castle lived in (North Star docs/art/target/01-town.jpg; Stronghold's walls walked by their
## guards, Total War's banners on the towers): the lord's standard on every corner and gate tower (towns.gd's
## standards, so they rise and fall with the house's favour as its other banners do), a guard walking each
## curtain's walk, turning at the towers to look out, two torches lit either side of the gate from dusk to
## dawn, and the bailey's well. Only castles our builder raises (--castles=kit): their frame is
## castle_builder.gd's (towers, curtain_runs), read off the castle's own size.
## Knobs: data/castle.json.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Data := preload("res://scripts/data.gd")
const Builder := preload("res://scripts/castle_builder.gd")
const Real := preload("res://scripts/realistic.gd")
const Fire := preload("res://scripts/fire.gd")
const Works := preload("res://scripts/works.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const S := Units.M  # world units a metre

var main: Node
var _done := {}  # castle node -> its dressing {torches: [lights and flames]}
var _rng := RandomNumberGenerator.new()


static func apply(m: Node) -> void:
	var c := new()
	c.name = "CastleLife"
	c.main = m
	m.add_child(c)


func _ready() -> void:
	_rng.seed = 4021
	var t := Timer.new()
	t.wait_time = 1.0
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)


## Once a second: a newly raised castle is dressed (one a tick: the frame never waits); the gates' torches
## follow the hour.
func _tick() -> void:
	for c in _done.keys():
		if not is_instance_valid(c):
			for n in _done[c]["nodes"]:
				if is_instance_valid(n):
					n.queue_free()
			_done.erase(c)
	var lit := Works.within(Works.hour(), "lit") and Works.dark()  # lit only when the sky is dark
	var st: Node = preload("res://scripts/awareness.gd").store()
	var units: Array = st.rec("units", []) if st else []
	var Aw := preload("res://scripts/awareness.gd")
	for c in _done:
		for t in _done[c]["torches"]:
			if is_instance_valid(t):
				t.visible = lit
		# The training yard drills as many lines as the lord has companies standing in the town (castle_folk.gd).
		if (_done[c] as Dictionary).has("drill") and st:
			var town: Dictionary = st.city(int(_done[c].get("city", -1)))
			preload("res://scripts/castle_folk.gd").show_lines(_done[c], preload("res://scripts/castle_folk.gd").garrison_lines(units, Aw.civilian, Aw.ships, town, (_done[c]["drill"] as Array).size()))
	if main == null or main.get("towns") == null:
		return
	for id in main.towns.towns:
		var root: Node3D = main.towns.towns[id].get("node")
		if root == null or not is_instance_valid(root):
			continue
		var castle: Node3D = root.get_node_or_null("Castle")
		if castle and not _done.has(castle) and castle.is_inside_tree():
			_dress(int(id), root, castle)
			return


## A castle's spec, read off its own size (the kit's spec whose bailey matches), or {} if our builder
## didn't raise it.
static func spec_of(castle: Node3D) -> Dictionary:
	var model: MeshInstance3D = castle.find_child("Model", true, false) as MeshInstance3D
	if model == null or model.mesh == null:
		return {}
	var hx := model.mesh.get_aabb().end.x - Builder.CELL  # the corner towers stand a cell past the curtain
	var kit: Array = (Data.value("assets", "components", {}).get("castle", {}) as Dictionary).get("kit", [])
	for v in kit:
		var sp: Dictionary = v.get("spec", {})
		if absf(int(sp.get("w", 0)) * Builder.CELL / 2.0 - hx) < 0.6:
			return sp
	return {}


## The castle's frame, metres to the world (through its model, which the castle's scale carries).
static func frame_of(castle: Node3D) -> Transform3D:
	var model: Node3D = castle.find_child("Model", true, false)
	return model.global_transform if model else castle.global_transform


func _dress(id: int, root: Node3D, castle: Node3D) -> void:
	var sp := spec_of(castle)
	var d := {"nodes": [], "torches": [], "city": id}
	_done[castle] = d
	if sp.is_empty():
		return  # not our builder's castle (the downloaded one): nothing to read its frame from
	var xf := frame_of(castle)
	var scale := xf.basis.get_scale().x / S  # 1 at full size, less for a lesser hold
	var house := _house(root)
	var colour := Heraldry.colour(house, Color(0.6, 0.15, 0.15))
	# The lord's standard on each corner and gate tower, over its cone.
	var bk: Dictionary = Data.value("castle", "banners", {})
	for t in Builder.towers(sp):
		var top: Vector3 = xf * (t["at"] + Vector3(0, float(t["top"]) + float(bk.get("lift", 2.6)), 0))
		if main.towns.has_method("_banner"):
			main.towns.banners.stand(root, root.to_local(top), colour, house, float(bk.get("size", 0.32)) * scale)
	# The house's painted arms where the kit hung plain cloth: down the keep's face, either side of the gate.
	_arms(xf, sp, house, colour, d)
	# A guard on each curtain's walk.
	var gk: Dictionary = Data.value("castle", "guards", {})
	var walk := int(sp.get("wall_storeys", 2)) * Builder.STOREY + 0.12
	for run in Builder.curtain_runs(sp):
		for g in int(gk.get("per_side", 1)):
			var inset: Vector3 = -(run["out"] as Vector3) * 0.6  # behind the merlons
			var a: Vector3 = xf * (run["a"] + inset + Vector3(0, walk, 0))
			var b: Vector3 = xf * (run["b"] + inset + Vector3(0, walk, 0))
			if a.distance_to(b) < 0.3:
				continue
			d["nodes"].append(_guard(a, b, colour, gk, scale))
	# Torches either side of the gate's arch, lit at dusk.
	var tk: Dictionary = Data.value("castle", "torches", {})
	var front := Builder.gate_front(sp) + 0.25  # the gatehouse's front face, a hand proud
	for sx in [-1.0, 1.0]:
		var local := Vector3(sx * float(tk.get("out", 1.7)), float(tk.get("height", 3.0)), front)
		var torch: Node3D = _torch(xf * local, xf.basis.get_rotation_quaternion(), tk, scale)
		d["nodes"].append(torch)
		d["torches"].append(torch)
	# Folk through the gate (Meshy's gatehouse stands open; the kit's has a door in its arch): townsfolk and
	# a guard walk in from the road, through the passage into the bailey, and out again.
	if Builder.meshy_gatehouse() != "":
		var wk: Dictionary = Data.value("castle", "gate_walkers", {})
		var hz := int(sp.get("d", 16)) * Builder.CELL / 2.0
		var path: Array = []
		for z in [front + float(wk.get("out", 3.0)), front - 0.3, hz - 1.0, hz - float(wk.get("inside", 4.0))]:
			var q: Vector3 = xf * Vector3(0, 0, z)
			if z > front or z < hz - 1.5:  # on open ground: on the land itself; in the passage, its floor
				q.y = main.terrain.height_at(q.x, q.z)
			path.append(q)
		for i in int(wk.get("count", 3)):
			d["nodes"].append(_walker(path, colour, wk, scale, i))
	# The red carpet up the keep's steps and across the bailey to the gate, a guard either side of the door
	# at the top (01-town: the steps up to the keep, the carpet, the halberdiers).
	if Builder.podium() > 0:
		_carpet(xf, sp, colour, d)
	# The bailey's buildings, their backs to the curtain wall: stables, the forge, the armoury, the stores.
	_bailey_buildings(xf, sp, d)
	# The rock it stands on (01-town: the castle raised on its outcrop, shrubs and cypresses on the rock).
	_outcrop(xf, sp, d)
	# The bailey lived in: drill, the butts, the gate's guards, the smith, the stores' cart, servants and grooms
	# (castle_folk.gd, the people layer's).
	preload("res://scripts/castle_folk.gd").dress(self, main, xf, sp, colour, d)
	# The bailey's well, at its heart.
	var w: Array = Data.value("castle", "well", [0.75, 0.0, 0.45])
	var well_kind := Real.one("well")
	if well_kind != "":
		var well: Node3D = Real.make(well_kind)
		if well:
			var yaw := castle.global_rotation.y
			var p: Vector3 = castle.global_position + Basis(Vector3.UP, yaw) * Vector3(float(w[0]), 0, float(w[2]))
			p.y = main.terrain.height_at(p.x, p.z)
			well.position = p
			well.rotation.y = yaw
			add_child(well)
			d["nodes"].append(well)


## The bailey's buildings against the curtain wall (data/castle.json bailey_buildings; Mac on Kingsmere from
## above: "the emptiness looks kinda weird"; 01-town and Stronghold's yard ringed with lean-tos): kit houses of a
## tier (house_tiers.gd: the stables' open arcade, the forge's chimney, the armoury's stone, the granary's stores)
## built narrow, back to the wall, front to the yard. Built in the castle's metres, so a lesser hold's are smaller.
## On with bailey_buildings.on.
static var _house_builder: RefCounted


func _bailey_buildings(xf: Transform3D, sp: Dictionary, d: Dictionary) -> void:
	var k: Dictionary = Data.value("castle", "bailey_buildings", {})
	if not bool(k.get("on", false)):
		return
	if _house_builder == null:
		_house_builder = preload("res://scripts/house_builder.gd").new()
	var hx := int(sp.get("w", 18)) * Builder.CELL / 2.0
	var hz := int(sp.get("d", 16)) * Builder.CELL / 2.0
	var wall_in := float(k.get("wall_in", 1.2))
	var size := float(k.get("scale", 0.85))
	for r: Dictionary in k.get("rows", []):
		var spec := {"tier": String(r.get("tier", "stables")), "seed": int(r.get("seed", 1)), "extras": {}, "props": []}
		for key in ["w", "d", "floors"]:
			if r.has(key):
				spec[key] = int(r[key])
		var mesh: ArrayMesh = _house_builder.build(spec)
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		var deep := box.size.z * size
		var at := float(r.get("at", 0.0))
		# The house's front (+z) turned to the yard; its back half its depth off the wall's inner face.
		var turn := 0.0
		var p := Vector3.ZERO
		match String(r.get("side", "left")):
			"left":
				turn = PI / 2
				p = Vector3(-hx + wall_in + deep / 2.0, 0, at * hz)
			"right":
				turn = -PI / 2
				p = Vector3(hx - wall_in - deep / 2.0, 0, at * hz)
			_:
				p = Vector3(at * hx, 0, -hz + wall_in + deep / 2.0)
		var b := Basis(Vector3.UP, turn).scaled(Vector3.ONE * size)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		add_child(mi)
		var w: Vector3 = xf * p
		w.y = main.terrain.height_at(w.x, w.z)
		# The box's own middle onto the spot, its floor on the ground.
		mi.global_transform = Transform3D(xf.basis * b, w) * Transform3D(Basis(), -Vector3(box.get_center().x, box.position.y, box.get_center().z))
		d["nodes"].append(mi)


## The castle's rock (data/castle.json outcrop; 01-town: the castle up on a rocky outcrop, shrubs and dark cypresses
## growing out of it): grey rocks banked against the outer foot of every curtain, shrubs among them and a slim
## cypress now and then, clear of the gate's approach and never on water. The keep's stair climbs inside as before.
func _outcrop(xf: Transform3D, sp: Dictionary, d: Dictionary) -> void:
	var k: Dictionary = Data.value("castle", "outcrop", {})
	if k.is_empty() or not bool(k.get("on", false)):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = int(k.get("seed", 91))
	var scale := xf.basis.get_scale().x / S
	var rocks: Array = Real.variants("castle_rock")
	var out_r: Array = k.get("out", [0.4, 1.3])
	var size_r: Array = k.get("size", [0.7, 1.3])
	var clear := Builder.gate_tower_x() + float(k.get("front_clear", 3.0))
	var put := func(kind: String, local: Vector3, s: Vector3, sink: float) -> void:
		var n: Node3D = Real.make(kind)
		if n == null:
			return
		var w: Vector3 = xf * local
		if not main.terrain.is_land(w.x, w.z):
			n.free()
			return
		w.y = main.terrain.height_at(w.x, w.z) - sink * S * scale
		add_child(n)
		n.global_position = w
		n.rotation.y = rng.randf() * TAU
		n.scale = s * scale
		d["nodes"].append(n)
	for run in Builder.curtain_runs(sp):
		var a: Vector3 = run["a"]
		var b: Vector3 = run["b"]
		var o: Vector3 = run["out"]
		var length := a.distance_to(b)
		var t := 0.0
		var since_bush := 0.0
		var since_tree := float(k.get("cypress_every", 9.0)) * 0.5
		while t < length:
			var at: Vector3 = a.lerp(b, t / maxf(length, 0.01))
			var step := float(k.get("every", 2.6)) * rng.randf_range(0.8, 1.2)
			t += step
			since_bush += step
			since_tree += step
			if int(run["side"]) == 0 and absf(at.x) < clear:
				continue  # the gate's approach stays open
			if not rocks.is_empty():
				put.call(String(rocks[rng.randi() % rocks.size()]), at + o * rng.randf_range(float(out_r[0]), float(out_r[1])), Vector3.ONE * rng.randf_range(float(size_r[0]), float(size_r[1])), float(k.get("sink", 0.5)))
			if since_bush >= float(k.get("bush_every", 5.0)):
				since_bush = 0.0
				put.call(Real.one("castle_shrub"), at + o * (float(out_r[1]) + 0.3) + (b - a).normalized() * rng.randf_range(-0.8, 0.8), Vector3.ONE * rng.randf_range(0.8, 1.2), 0.1)
			if since_tree >= float(k.get("cypress_every", 9.0)):
				since_tree = 0.0
				var sq := float(k.get("cypress_squash", 0.45))
				put.call(Real.one("castle_cypress"), at + o * float(out_r[1]), Vector3(sq, 1.0, sq) * rng.randf_range(0.85, 1.15), 0.1)


## The house's painted banners (assets/heraldry/banner-<house>.png; else a cloth in its colour) hung flat on
## the castle where the kit's plain ones hung (castle_builder.gd leaves those out while this is on): one long
## down the keep's face, one either side of the gate (batch 8b: plain yellow cloth with no arms).
func _arms(xf: Transform3D, sp: Dictionary, house: Dictionary, colour: Color, d: Dictionary) -> void:
	var k: Dictionary = Data.value("castle", "arms", {})
	var size := float(sp.get("banner", 1.6)) * float(k.get("size", 1.0))
	var cell := Builder.CELL
	var hz := int(sp.get("d", 16)) * cell / 2.0
	var kh := int(sp.get("keep", 4)) * cell / 2.0
	var keep_z := -hz + kh - 1.0 + kh + 0.12
	var keep_top := (int(sp.get("keep_storeys", 5)) + Builder.podium()) * Builder.STOREY - 1.0
	var gate_top := (int(sp.get("wall_storeys", 2)) + 1) * Builder.STOREY - 0.4
	var gate_z := Builder.gate_front(sp) + 0.12
	var gh := 4 * cell / 2.0
	var mat := _arms_material(house, colour)
	var hangs := [[Vector3(0, keep_top, keep_z), Vector2(1.2, 3.0) * size]]
	# 01-town: two great banners either side of the keep's door, not one down its middle (castle.json
	# arms.keep_pair: [out, a share of the keep's half-width; width; height] times size).
	var kp: Array = k.get("keep_pair", [])
	if kp.size() >= 3:
		hangs = []
		for sx in [-1.0, 1.0]:
			hangs.append([Vector3(sx * float(kp[0]) * kh, keep_top, keep_z), Vector2(float(kp[1]), float(kp[2])) * size])
	for sx in [-1.0, 1.0]:
		hangs.append([Vector3(sx * (gh - 0.6), gate_top, gate_z), Vector2(0.9, 2.2) * size])
	# Along the front curtain, facing the square, every arms.curtain_every metres (01-town: the arms all along
	# the wall; round 5: none on the curtain), clear of the gatehouse.
	var every := float(k.get("curtain_every", 0.0))
	if every > 0.0:
		var wall_top := int(sp.get("wall_storeys", 2)) * Builder.STOREY - 0.3
		for run in Builder.curtain_runs(sp):
			if int(run["side"]) != 0:
				continue
			var a: Vector3 = run["a"]
			var b: Vector3 = run["b"]
			var out: Vector3 = run["out"]
			var n := int(floor(a.distance_to(b) / every))
			for i in n:
				var at: Vector3 = a.lerp(b, (i + 0.5) / float(n))
				if absf(at.x) < Builder.gate_tower_x() + 1.5:
					continue
				hangs.append([at + out * 0.15 + Vector3(0, wall_top, 0), Vector2(0.9, 2.2) * size * float(k.get("curtain_size", 0.8))])
	# One down the town-facing face of each front and gate tower (01-town: the arms on every tower).
	for t in Builder.towers(sp):
		var at: Vector3 = t["at"]
		if at.z <= 0.0:
			continue
		hangs.append([Vector3(at.x, float(t["top"]) - float(k.get("tower_below", 1.2)), at.z + Builder.CELL + 0.12), Vector2(0.9, 2.4) * size * float(k.get("tower_size", 0.9))])
	for h in hangs:
		var q := QuadMesh.new()
		q.size = h[1]
		q.center_offset = Vector3(0, -(h[1] as Vector2).y * 0.5, 0)  # hung from its top edge
		var m := MeshInstance3D.new()
		m.mesh = q
		m.material_override = mat
		add_child(m)
		m.global_transform = xf * Transform3D(Basis(), h[0])
		d["nodes"].append(m)


func _arms_material(house: Dictionary, colour: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.roughness = 0.95
	var path := "res://assets/heraldry/banner-%s.png" % Heraldry.slug(house)
	if Heraldry.slug(house) != "" and ResourceLoader.exists(path):
		m.albedo_texture = load(path)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	else:
		m.albedo_color = colour
	return m


## The town's holder's house (name, colour, sigil), from the store.
func _house(root: Node3D) -> Dictionary:
	return main.awareness.houses_by_id().get(int(root.get_meta("owner", -1)), {})


## A guard walking a curtain's walk from a to b and back, looking out at each end.
func _guard(a: Vector3, b: Vector3, colour: Color, k: Dictionary, scale: float) -> Node3D:
	var f: Node3D = main.scenes.people.make(_rng, "soldier", colour.lerp(Color.WHITE, 0.3), "adult")
	add_child(f)
	main.scenes.arm(f, "spear")
	f.global_position = a
	var m: Node = Mover.of(f)
	m.speed = maxf(float(k.get("pace", 0.9)) * S * scale, 0.001)
	var look := float(k.get("look_s", 3.0))
	rounds(f, [PackedVector3Array([b]), PackedVector3Array([a])], [look, look], _rng.randf_range(0.0, look * 2.0))  # each on his own beat
	return f


## The carpet: a strip down the keep's steps from its door (the podium's top) to their foot, then on along the
## bailey's floor to the gate's inner face (castle-local metres; castle_builder.gd lays the steps).
func _carpet(xf: Transform3D, sp: Dictionary, colour: Color, d: Dictionary) -> void:
	var k: Dictionary = Data.value("castle", "steps", {})
	var hz := int(sp.get("d", 16)) * Builder.CELL / 2.0
	var kh := int(sp.get("keep", 4)) * Builder.CELL / 2.0
	var kf := -hz + kh - 1.0 + kh
	var top := Builder.podium() * Builder.STOREY
	var foot := kf + 2.0 * Builder.podium() * int(Builder.STOREY)
	var half := float(k.get("carpet_w", 1.6)) * 0.5
	var lift := float(k.get("carpet_lift", 0.06))
	var to_gate := hz - float(k.get("gate_in", 3.2))
	var pts := [Vector3(0, top + lift, kf + 0.25), Vector3(0, lift, foot), Vector3(0, lift * 0.5, to_gate)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var quad := [a + Vector3(-half, 0, 0), a + Vector3(half, 0, 0), b + Vector3(half, 0, 0), b + Vector3(-half, 0, 0)]
		var n := (b - a).cross(Vector3.RIGHT).normalized()
		if n.y < 0.0:
			n = -n
		for t in [[0, 1, 2], [0, 2, 3]]:
			for v in t:
				st.set_normal(n)
				st.add_vertex(quad[v])
	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	var c: Array = k.get("carpet", [0.6, 0.07, 0.06])
	mat.albedo_color = Color(float(c[0]), float(c[1]), float(c[2]))
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.material_override = mat
	add_child(m)
	m.global_transform = xf
	d["nodes"].append(m)
	# The door's guards at the top of the steps.
	for sx in [-1.0, 1.0]:
		var g: Node3D = main.scenes.people.make(_rng, "soldier", colour.lerp(Color.WHITE, 0.3), "adult")
		add_child(g)
		main.scenes.arm(g, "spear")
		g.global_position = xf * Vector3(sx * (half + 0.7), top, kf + 0.9)
		var out: Vector3 = xf.basis * Vector3(0, 0, 1)  # facing down the steps, toward the gate
		g.global_rotation.y = atan2(out.x, out.z)
		main.scenes.people.play(g, "Idle", 1.0)
		d["nodes"].append(g)


## One of the folk going in and out by the gate: along `path` (the road outside, the gate, the passage's
## inner end, the bailey) and back, a while in the bailey and a while out on the road between.
func _walker(path: Array, colour: Color, k: Dictionary, scale: float, i: int) -> Node3D:
	var guard := i == 0
	var f: Node3D = main.scenes.people.make(_rng, "soldier" if guard else "peasant", colour.lerp(Color.WHITE, 0.3) if guard else Color.WHITE, "adult")
	add_child(f)
	if guard:
		main.scenes.arm(f, "spear")
	var through: Vector3 = (path[path.size() - 1] - path[0]) * Vector3(1, 0, 1)
	var side := Vector3(-through.z, 0, through.x).normalized() * (float(k.get("abreast", 0.4)) * (i - 1)) * scale  # across the gate
	var pts: Array = path.map(func(p): return p + side)
	f.global_position = pts[0]
	var pace := maxf(float(k.get("pace", 0.8)) * S * scale, 0.001)
	var wait: Array = k.get("wait_s", [4.0, 10.0])
	Mover.of(f).speed = pace
	var back: Array = pts.duplicate()
	back.reverse()
	rounds(f, [PackedVector3Array(pts.slice(1)), PackedVector3Array(back.slice(1))], [wait, wait], _rng.randf_range(0.0, float(wait[1])) + i * 2.0)  # in, then out; each on his own beat
	return f


## A round walked for ever with the Mover (CLAUDE.md, one way to move): each leg in turn (a way the castle lays,
## a wall walk, the gate's road or a carrier's trip across the bailey, followed as given), then a pause for its wait
## ([least, most] or seconds) playing one of `rest` (a look about by default; a carrier sets his load down), then the
## next; the first start held back `first` seconds so nobody keeps step with anyone. `led`: a beast led at the
## walker's side (a groom's horse), walking each leg beside him at his pace with its own Mover. The castle's folk
## (castle_folk.gd) walk their rounds here too: one round for the bailey.
func rounds(f: Node3D, legs: Array, waits: Array, first: float, at := 0, rest: Array = REST, led: Node3D = null) -> void:
	get_tree().create_timer(first).timeout.connect(func():
		if not is_instance_valid(f):
			return
		var leg: PackedVector3Array = legs[at % legs.size()]
		if led and is_instance_valid(led) and not leg.is_empty():
			var way := leg[leg.size() - 1] - f.global_position
			var side := Basis(Vector3.UP, atan2(way.x, way.z)) * LED_SIDE * float(Data.num("people", "readable", 1.0))
			var lm: Node = Mover.of(led)
			lm.speed = Mover.of(f).speed
			lm.clip = ""  # a beast animates itself
			lm.walk(PackedVector3Array(Array(leg).map(func(p: Vector3): return p + side)))
		Mover.of(f).walk(leg, func():
			if not is_instance_valid(f):
				return
			main.scenes.people.play(f, String(rest[_rng.randi() % rest.size()]), 1.0)
			var w: Variant = waits[at % waits.size()]
			var secs: float = _rng.randf_range(float(w[0]), float(w[1])) if w is Array else float(w)
			rounds(f, legs, waits, secs, at + 1, rest, led)))


const REST := ["Looking_Around", "Weight_Shift", "Idle"]  # a look about at the end of a leg
const LED_SIDE := Vector3(0.12, 0, -0.05)  # where a led beast walks beside its walker (his right, half a step back), game units at readable 1


## A torch on the gate: the kit's iron torch, a small flame (fire.gd's), a warm short light.
func _torch(at: Vector3, turn: Quaternion, k: Dictionary, scale: float) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.global_position = at
	n.quaternion = turn
	if ResourceLoader.exists("res://assets/props/Torch_Metal.gltf"):
		var t: Node3D = load("res://assets/props/Torch_Metal.gltf").instantiate()
		t.scale = Vector3.ONE * S * scale
		n.add_child(t)
	Fire.hearth(n, Vector3(0, 0.06 * scale, 0))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.light_energy = float(k.get("energy", 0.6))
	l.omni_range = float(k.get("range", 0.45)) * scale
	l.position = Vector3(0, 0.08 * scale, 0.05)
	l.shadow_enabled = false
	n.add_child(l)
	n.visible = false
	return n
