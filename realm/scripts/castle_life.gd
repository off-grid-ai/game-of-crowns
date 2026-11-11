extends Node3D
## A seat's kit castle lived in (North Star docs/art/target/01-town.jpg; Stronghold's walls walked by their
## guards, Total War's banners on the towers): the lord's standard on every corner and gate tower (towns.gd's
## standards, so they rise and fall with the house's favour as its other banners do), a guard walking each
## curtain's walk, turning at the towers to look out, two torches lit either side of the gate from dusk to
## dawn, and the bailey's well. Only castles our builder raises (--castles=kit): their frame is
## castle_builder.gd's (towers, curtain_runs), read off the castle's own size.
## Knobs: data/castle.json. Switch: --castle-life=on|off, or castle.json on.

const Data := preload("res://scripts/data.gd")
const Builder := preload("res://scripts/castle_builder.gd")
const Real := preload("res://scripts/realistic.gd")
const Fire := preload("res://scripts/fire.gd")
const Works := preload("res://scripts/works.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const S := 0.12  # world units a metre

var main: Node
var _done := {}  # castle node -> its dressing {torches: [lights and flames]}
var _rng := RandomNumberGenerator.new()


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--castle-life=off"):
		return false
	return args.has("--castle-life=on") or bool(Data.value("castle", "on", false))


static func apply(m: Node) -> void:
	if not on():
		return
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
	var lit := Works.within(Works.hour(), "lit")
	for c in _done:
		for t in _done[c]["torches"]:
			if is_instance_valid(t):
				t.visible = lit
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
	var d := {"nodes": [], "torches": []}
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
			main.towns._banner(root, root.to_local(top), colour, house, float(bk.get("size", 0.32)) * scale)
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
	var front := int(sp.get("d", 16)) * Builder.CELL / 2.0 + 3.0 + 0.25  # the gatehouse's front face, a hand proud
	for sx in [-1.0, 1.0]:
		var local := Vector3(sx * float(tk.get("out", 1.7)), float(tk.get("height", 3.0)), front)
		var torch: Node3D = _torch(xf * local, xf.basis.get_rotation_quaternion(), tk, scale)
		d["nodes"].append(torch)
		d["torches"].append(torch)
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


## The town's holder as the bridge reports it.
func _house(root: Node3D) -> Dictionary:
	var owner := int(root.get_meta("owner", -1))
	for h in main.bridge.world.get("houses", []):
		if int(h.get("id", -2)) == owner:
			return h
	return {}


## A guard walking a curtain's walk from a to b and back, looking out at each end.
func _guard(a: Vector3, b: Vector3, colour: Color, k: Dictionary, scale: float) -> Node3D:
	var f: Node3D = main.scenes.people.make(_rng, "soldier", colour.lerp(Color.WHITE, 0.3), "adult")
	add_child(f)
	main.scenes.arm(f, "spear")
	f.global_position = a
	var leg := a.distance_to(b) / maxf(float(k.get("pace", 0.9)) * S * scale, 0.001)
	var look := float(k.get("look_s", 3.0))
	var tw := f.create_tween().set_loops()
	tw.tween_interval(_rng.randf_range(0.0, look * 2.0))  # each on his own beat
	for end in [b, a]:
		tw.tween_callback(func():
			var dir: Vector3 = end - f.global_position
			f.rotation.y = atan2(dir.x, dir.z)
			main.scenes.people.play(f, "Walk", _rng.randf_range(0.9, 1.05)))
		tw.tween_property(f, "global_position", end, leg)
		tw.tween_callback(func(): main.scenes.people.play(f, ["Looking_Around", "Weight_Shift", "Idle"][_rng.randi() % 3], 1.0))
		tw.tween_interval(look)
	return f


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
