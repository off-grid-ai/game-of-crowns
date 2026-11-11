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
	if Time.get_ticks_msec() - int(_last.get(wall, 0)) < float(Data.num("walls", "strike.every_s", 2.6)) * 1000.0:
		return
	if not wall.hot:
		return
	if int(_blows.get(wall, 0)) >= int(Data.num("walls", "strike.max", 10)):
		wall.give_way()
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
		stone.global_position = p, 0.0, 1.0, float(Data.num("walls", "strike.flight_s", 1.7)))
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


## A stone lands at `at` (world) on a wall, flying along `along`.
func strike(at: Vector3, along: Vector3) -> void:
	for w in _walls():
		if w.distance_to(at) < 0.4:
			_blows[w] = int(_blows.get(w, 0)) + 1
			_last[w] = Time.get_ticks_msec()
			w.strike(at, along)
			return


func _walls() -> Array:
	var out := []
	for id in _rings:
		if is_instance_valid(_rings[id]["wall"]):
			out.append(_rings[id]["wall"])
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


## A wall's standing foot goes to its town's walking map: a breach is a way in.
func _publish(wall: Node3D, root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var local := []
	for q in wall.foot():
		var o := PackedVector2Array()
		for v in q:
			o.append(v - Vector2(root.global_position.x, root.global_position.z))
		local.append(o)
	root.set_meta("stone_walls", local)
	root.set_meta("stone_walls_rev", int(root.get_meta("stone_walls_rev", 0)) + 1)


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
