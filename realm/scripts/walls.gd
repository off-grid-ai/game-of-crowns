extends Node3D
## The realm's stone walls (stone_wall.gd), behind a switch: --walls=stone, or
## "walls": "stone" in data/walls.json. A walled town's ring of kit wall panels
## gives way to a ring of stacked stones in eight sections, each section drawn at
## the wear the bridge reports for it (damage.js, /world cities[].damage, read
## through the awareness mirror; the view decides nothing). When a section's wear
## rises near the camera, catapult stones bring the doomed stones down one blow at
## a time (the siege's own volleys, scenes._volley, strike the wall through aim and
## strike; between them this throws its own); away from the camera the wall jumps
## to the same breach. Each wall's open foot goes to its town's walking map
## (town_nav, meta "stone_walls"), so a breach is a way in.
## A test aid, --wall-demo: a wall across a staged siege's front (--siege) whose
## middle section each stone that strikes it wears further, without the bridge.

const StoneWall := preload("res://scripts/stone_wall.gd")
const Data := preload("res://scripts/data.gd")
const S := 0.12

var main: Node
var _rings := {}  # town id -> {wall, root, center}
var _castles := {}  # castle node -> {root, id, center, walls: [{wall, section}]}: a kit castle's stone curtains
var _demo := {}  # {wall, wear, id, center}
var _last := {}  # wall -> msec of its last blow
var _blows := {}  # wall -> blows since its wear last rose
var _thrown := {}  # wall -> a stone of its own in the air


## On for this run?
static func on() -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--walls="):
			return a.substr(8) == "stone"
	return String(Data.value("walls", "walls", "off")) == "stone"


func _init(m: Node) -> void:
	main = m
	name = "StoneWalls"


func _ready() -> void:
	Engine.set_meta("stone_walls", self)
	var t := Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)


func _exit_tree() -> void:
	if Engine.has_meta("stone_walls") and Engine.get_meta("stone_walls") == self:
		Engine.remove_meta("stone_walls")


func _tick() -> void:
	_rings_follow()
	_castles_follow()
	if OS.get_cmdline_user_args().has("--wall-demo") and _demo.is_empty():
		_demo_build()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.INF
	var near_r := float(Data.num("walls", "sim_radius", 12.0))
	for id in _rings:
		var ring: Dictionary = _rings[id]
		var wall: Node3D = ring["wall"]
		var near: bool = eye != Vector3.INF and wall.distance_to(eye) < near_r
		wall.set_hot(near or wall.busy())
		var walls: Array = (main.awareness.town(id).get_var(&"damage", {}, false) as Dictionary).get("walls", []) if main.awareness else []
		for s in mini(walls.size(), wall.sections):
			var wear := float((walls[s] as Dictionary).get("wear", 0.0))
			if absf(wear - wall.shown[s]) > 0.005:
				wall.wear_to(s, wear, near)
				_blows[wall] = 0
		_keep_striking(wall, ring["center"])
	# A kit castle's stone curtains take the wear of the town's section each faces: a siege breaches the castle too.
	for c in _castles:
		var cs: Dictionary = _castles[c]
		var cw: Array = (main.awareness.town(int(cs["id"])).get_var(&"damage", {}, false) as Dictionary).get("walls", []) if main.awareness else []
		for e in cs["walls"]:
			var wall: Node3D = e["wall"]
			if not is_instance_valid(wall):
				continue
			var near: bool = eye != Vector3.INF and wall.distance_to(eye) < near_r
			wall.set_hot(near or wall.busy())
			if int(e["section"]) < cw.size():
				var wear := float((cw[int(e["section"])] as Dictionary).get("wear", 0.0))
				if absf(wear - wall.shown[0]) > 0.005:
					wall.wear_to(0, wear, near)
					_blows[wall] = 0
			_keep_striking(wall, cs["center"])
	if not _demo.is_empty() and is_instance_valid(_demo["wall"]):
		var dw: Node3D = _demo["wall"]
		dw.set_hot(true)
		var first := float(Data.num("walls", "demo.first_s", 4.0)) * 1000.0
		if Time.get_ticks_msec() - int(_demo["at"]) > first:
			if dw.aim() == Vector3.INF:
				_demo_wear()
			_keep_striking(dw, _demo["center"])


## Between the siege's own volleys, a stone of our own at a wall whose wear has
## doomed stones still standing; after strike.max blows the rest give way.
func _keep_striking(wall: Node3D, center: Vector3) -> void:
	var target: Vector3 = wall.aim()
	if target == Vector3.INF or _thrown.get(wall, false):
		return
	# The demo wall is battered at its own, quicker pace (demo.every_s, demo.max), so a short take sees it
	# crack, notch and breach; a real siege keeps strike.*.
	var demo: bool = not _demo.is_empty() and wall == _demo["wall"]
	if Time.get_ticks_msec() - int(_last.get(wall, 0)) < float(Data.num("walls", "demo.every_s" if demo else "strike.every_s", 2.6)) * 1000.0:
		return
	if not wall.hot:
		return
	if int(_blows.get(wall, 0)) >= int(Data.num("walls", "demo.max" if demo else "strike.max", 10)):
		wall.give_way()
		return
	# Engines standing near (siege_camp.gd) throw the stones themselves: none from nowhere.
	for e in get_tree().get_nodes_in_group("siege_engines"):
		if is_instance_valid(e) and wall.distance_to((e as Node3D).global_position) < float(Data.num("walls", "strike.from_m", 70.0)) * S * 1.5:
			return
	var out := Vector3(target.x - center.x, 0, target.z - center.z).normalized()
	var from := target + out * float(Data.num("walls", "strike.from_m", 70.0)) * S + Vector3.UP * 0.4
	_throw(wall, from, target)


## A catapult stone arcs from `from` to the wall and strikes it.
func _throw(wall: Node3D, from: Vector3, to: Vector3) -> void:
	_thrown[wall] = true
	_last[wall] = Time.get_ticks_msec()
	var stone := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.045
	sm.height = 0.08
	stone.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.36, 0.33)
	stone.material_override = mat
	add_child(stone)
	stone.global_position = from
	var top := maxf(from.y, to.y) + from.distance_to(to) * 0.3
	var tw := stone.create_tween()
	tw.tween_method(func(t: float):
		var p := from.lerp(to, t)
		p.y = lerpf(from.y, to.y, t) + (top - maxf(from.y, to.y)) * 4.0 * t * (1.0 - t)
		stone.global_position = p, 0.0, 1.0, float(Data.num("walls", "demo.flight_s" if not _demo.is_empty() and wall == _demo["wall"] else "strike.flight_s", 1.7)))
	tw.tween_callback(func():
		stone.queue_free()
		_thrown[wall] = false
		if is_instance_valid(wall):
			strike(to, (to - from).normalized()))


# --- the siege's volleys (scenes._volley) ------------------------------------

## Where a stone thrown from `from` should land to strike a wall: a doomed stone
## of the nearest wall within reach, on its outer face, or INF (over the wall as
## before). The demo wall takes a little more wear for each stone thrown at it.
func aim(from: Vector3) -> Vector3:
	var best: Node3D = null
	var bd := 9.0
	for w in _walls():
		var d: float = w.distance_to(from)
		if d < bd:
			bd = d
			best = w
	if best == null:
		return Vector3.INF
	if not _demo.is_empty() and best == _demo["wall"] and best.aim() == Vector3.INF:
		_demo_wear()
	return best.aim()


## The outer face of the nearest wall to `from` (within 9 units), straight in front of it and `out` metres
## off the face, on the wall's own line (world; its y the wall's base), or INF. Where a ram stops to batter
## and a siege tower rolls up to (siege_camp.gd).
func face_toward(from: Vector3, out := 0.3) -> Vector3:
	var best: Node3D = null
	var bd := 9.0
	for w in _walls():
		var d: float = w.distance_to(from)
		if d < bd:
			bd = d
			best = w
	if best == null:
		return Vector3.INF
	return best._world_at(best.along(from), best._thick * 0.5 + out)


## A stone lands at `at` (world) on a wall, flying along `along`.
func strike(at: Vector3, along: Vector3) -> void:
	for w in _walls():
		if w.distance_to(at) < 0.4:
			_blows[w] = int(_blows.get(w, 0)) + 1
			_last[w] = Time.get_ticks_msec()
			w.strike(at, along)
			return


## The breaches open now within `reach` (world units) of `at`, nearest first: each gap's middle on the
## ground (world). The siege's men stream to them (siege_ai.gd).
func breaches_near(at: Vector3, reach: float) -> Array:
	var out := []
	for w in _walls():
		if w.distance_to(at) > reach + 1.0:
			continue
		for b in w.breaches():
			var p: Vector3 = b
			if Vector2(p.x - at.x, p.z - at.z).length() < reach:
				out.append(p)
	out.sort_custom(func(x, y): return Vector2(x.x - at.x, x.z - at.z).length() < Vector2(y.x - at.x, y.z - at.z).length())
	return out


## The top of any wall's rubble under a world point (world y), or -INF: the ramp
## a breach leaves, which men storming it climb (siege_ai.gd).
func rubble_height(at: Vector3) -> float:
	var top := -INF
	for w in _walls():
		if w.distance_to(at) < 0.6:
			top = maxf(top, w.rubble_height(at))
	return top


func _walls() -> Array:
	var out := []
	for id in _rings:
		if is_instance_valid(_rings[id]["wall"]):
			out.append(_rings[id]["wall"])
	for c in _castles:
		for e in _castles[c]["walls"]:
			if is_instance_valid(e["wall"]):
				out.append(e["wall"])
	if not _demo.is_empty() and is_instance_valid(_demo["wall"]):
		out.append(_demo["wall"])
	return out


# --- town rings --------------------------------------------------------------

## Every walled town gets its ring (one a tick); a rebuilt or gone town's goes.
func _rings_follow() -> void:
	if main.towns == null:
		return
	var panel: Mesh = main.towns.get("_wall_panel")
	for id in _rings.keys():
		var r: Dictionary = _rings[id]
		var t: Dictionary = main.towns.towns.get(id, {})
		if t.is_empty() or t.get("node") != r["root"] or not is_instance_valid(r["root"]):
			if is_instance_valid(r["wall"]):
				r["wall"].queue_free()
			_rings.erase(id)
	for id in main.towns.towns:
		if _rings.has(id):
			continue
		var root: Node3D = main.towns.towns[id].get("node")
		if root == null or not is_instance_valid(root) or not root.is_inside_tree():
			continue
		var panels: Array = root.get_children().filter(func(n): return n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh == panel)
		if panels.is_empty() or root.get_meta("walls", []).is_empty():
			continue
		_ring(id, root, panels)
		return  # one ring a tick: the frame never waits on more


func _ring(id: int, root: Node3D, panels: Array) -> void:
	# The ring's radius, from the panels' outlines towns.gd keeps (meta "walls").
	var shells: Array = root.get_meta("walls", [])
	var r := 0.0
	for sh in shells:
		var q: PackedVector2Array = sh[0]
		r += ((q[0] + q[1] + q[2] + q[3]) / 4.0).length()
	r /= maxf(shells.size(), 1)
	if r < 0.5:
		return
	var center := root.global_position
	var ring: Dictionary = Data.value("walls", "ring", {})
	var sections := int(ring.get("sections", 8))
	var chords := sections * int(ring.get("chords_per_section", 3))
	var pts := PackedVector3Array()
	for k in chords + 1:
		var a := -PI / sections + TAU * k / chords  # section 0 faces north, then clockwise (bridge damage.js)
		var p := center + Vector3(sin(a), 0, -cos(a)) * r
		p.y = main.terrain.height_at(p.x, p.z)
		pts.append(p)
	var wall := StoneWall.build_along(pts, float(ring.get("height_m", 6.0)), Color.WHITE, {
		"sections": sections, "outer": 1.0, "seed": id,
		"ground": func(p: Vector3) -> float: return main.terrain.height_at(p.x, p.z)})
	add_child(wall)
	for p in panels:
		p.visible = false  # the stones stand in the kit panels' place
	_rings[id] = {"wall": wall, "root": root, "center": center}
	wall.opened.connect(_publish.bind(wall, root))
	_publish(wall, root)


## A wall's standing foot goes to its town's walking map: a breach is a way in. Every stone wall of the
## town together (its ring and its castle's curtains), so one never writes over another's.
func _publish(_by: Node3D, root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var all := []
	for id in _rings:
		if _rings[id]["root"] == root and is_instance_valid(_rings[id]["wall"]):
			all.append(_rings[id]["wall"])
	for c in _castles:
		if _castles[c]["root"] == root:
			for e in _castles[c]["walls"]:
				if is_instance_valid(e["wall"]):
					all.append(e["wall"])
	if not _demo.is_empty() and is_instance_valid(_demo["wall"]) and (main.towns.towns.get(int(_demo["id"]), {}) as Dictionary).get("node") == root:
		all.append(_demo["wall"])
	var local := []
	var feet := []
	for w in all:
		feet.append_array(w.foot())
	for q in feet:
		var o := PackedVector2Array()
		for v in q:
			o.append(v - Vector2(root.global_position.x, root.global_position.z))
		local.append(o)
	root.set_meta("stone_walls", local)
	root.set_meta("stone_walls_rev", int(root.get_meta("stone_walls_rev", 0)) + 1)


# --- a kit castle's curtains ---------------------------------------------------

## Every kit castle (castle_builder.gd, --castles=kit) gets stone curtains along its curtain runs, one a
## tick; the castle itself leaves its kit curtains out while stone walls are on (castle_builder
## stone_curtains). A castle rebuilt or gone takes its curtains with it.
func _castles_follow() -> void:
	for c in _castles.keys():
		if not is_instance_valid(c):
			for e in _castles[c]["walls"]:
				if is_instance_valid(e["wall"]):
					e["wall"].queue_free()
			_castles.erase(c)
	if main.towns == null:
		return
	var Life: GDScript = load("res://scripts/castle_life.gd")
	for id in main.towns.towns:
		var root: Node3D = main.towns.towns[id].get("node")
		if root == null or not is_instance_valid(root) or not root.is_inside_tree():
			continue
		var castle: Node3D = root.get_node_or_null("Castle")
		if castle == null or _castles.has(castle):
			continue
		var sp: Dictionary = Life.spec_of(castle)
		if sp.is_empty():
			_castles[castle] = {"root": root, "id": int(id), "center": root.global_position, "walls": []}
			continue
		_castle_curtains(int(id), root, castle, sp)
		return


func _castle_curtains(id: int, root: Node3D, castle: Node3D, sp: Dictionary) -> void:
	var xf: Transform3D = load("res://scripts/castle_life.gd").frame_of(castle)
	var scale := xf.basis.get_scale().x / S
	var center := root.global_position
	var sections := int(Data.num("walls", "ring.sections", 8))
	var height := int(sp.get("wall_storeys", 2)) * 3.0 * scale
	var walls := []
	for run in preload("res://scripts/castle_builder.gd").curtain_runs(sp):
		var a: Vector3 = xf * (run["a"] as Vector3)
		var b: Vector3 = xf * (run["b"] as Vector3)
		a.y = main.terrain.height_at(a.x, a.z)
		b.y = main.terrain.height_at(b.x, b.z)
		var out: Vector3 = (xf.basis * (run["out"] as Vector3)).normalized()
		var d := b - a
		var right := Vector3(-d.z, 0, d.x)
		var wall := StoneWall.build_along(PackedVector3Array([a, b]), height, Color.WHITE, {
			"sections": 1, "outer": 1.0 if right.dot(out) >= 0.0 else -1.0, "seed": id * 31 + int(run["side"]),
			"ground": func(p: Vector3) -> float: return main.terrain.height_at(p.x, p.z)})
		add_child(wall)
		# The town's wall section it faces (damage.js: section 0 faces north, then clockwise).
		var mid := (a + b) * 0.5 - center
		var ang := fposmod(atan2(mid.x, -mid.z) + PI / sections, TAU)
		walls.append({"wall": wall, "section": int(floor(ang / (TAU / sections))) % sections})
		wall.opened.connect(_publish.bind(wall, root))
	_castles[castle] = {"root": root, "id": id, "center": center, "walls": walls}
	_publish(null, root)


# --- the demo (test aid) -----------------------------------------------------

## A wall across a staged siege's front: between the defenders and the foot of
## the assault, an arc facing the camp.
func _demo_build() -> void:
	var sieges: Dictionary = main.scenes.get("_sieges")
	for id in sieges:
		var s: Dictionary = sieges[id]
		if s.get("root") == null or not is_instance_valid(s["root"]) or not main.awareness:
			continue
		var tile: Vector2i = main.awareness.town(int(id)).get_var(&"tile", Vector2i.ZERO, false)
		var center: Vector3 = main.terrain.world_pos(float(tile.x), float(tile.y))
		var front: Vector3 = s["front"]
		var out := Vector3(front.x - center.x, 0, front.z - center.z)
		var r := out.length() - 0.6 - 0.12
		var base := atan2(out.z, out.x)
		var span := float(Data.num("walls", "demo.span_rad", 0.5))
		var pts := PackedVector3Array()
		for k in 7:
			var a := base - span + span * 2.0 * k / 6.0
			var p := center + Vector3(cos(a), 0, sin(a)) * r
			p.y = main.terrain.height_at(p.x, p.z)
			pts.append(p)
		var wall := StoneWall.build_along(pts, float(Data.num("walls", "demo.height_m", 7.0)), Color.WHITE, {
			"sections": int(Data.num("walls", "demo.sections", 3)), "outer": 1.0, "seed": int(id),
			"ground": func(p: Vector3) -> float: return main.terrain.height_at(p.x, p.z)})
		add_child(wall)
		_demo = {"wall": wall, "wear": 0.0, "id": int(id), "center": center, "at": Time.get_ticks_msec()}
		var t: Dictionary = main.towns.towns.get(int(id), {})
		if is_instance_valid(t.get("node")):
			wall.opened.connect(_publish.bind(wall, t["node"]))
		return


## The demo's staged wear: each stone at it takes the middle section further.
func _demo_wear() -> void:
	var w: Node3D = _demo["wall"]
	_demo["wear"] = minf(1.0, float(_demo["wear"]) + float(Data.num("walls", "demo.wear_per_hit", 0.12)))
	_blows[w] = 0
	w.wear_to(1, float(_demo["wear"]), true)
	print("WALL demo wear=%.2f (cracked from 0.2, breached to the ground at %.2f) at %.1f s" % [float(_demo["wear"]), float(Data.num("walls", "breach.full_at", 0.75)), (Time.get_ticks_msec() - int(_demo["at"])) / 1000.0])
