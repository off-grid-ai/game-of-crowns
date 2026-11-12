extends Node3D
## The realm's town walls, one owner (integration audit #7). towns.gd plans a walled town's wall (meta town_wall:
## its curtain bays along the town's edge, towers at the turns, gatehouses where the main roads run out); this builds
## it and keeps it at the wear the bridge reports for each of its eight sections (damage.js, /world cities[].damage,
## read through the awareness mirror; the view decides nothing). Whole, a section stands as the castle kit's curtain
## (castle_builder.gd town_wall: its arrow slits and merlons, the look of round 11); cracked or breached, that
## section's kit face gives way to stacked stones (stone_wall.gd) at its wear, mended back to the kit when the realm
## rebuilds it. When a section's wear rises near the camera, catapult stones bring the doomed stones down one blow at
## a time (the siege camp's engines strike the wall through aim and strike; between them this throws its own); away
## from the camera the wall jumps to the same breach. Each stone run's open foot goes to its town's walking map
## (town_nav, meta "stone_walls"), so a breach is a way in. A castle's curtains are castle_builder.gd's kit for now.
## A test aid, --wall-demo: a wall across a staged siege's front (--siege) whose
## middle section each stone that strikes it wears further, without the bridge.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const StoneWall := preload("res://scripts/stone_wall.gd")
const Data := preload("res://scripts/data.gd")
const S := Units.M

var main: Node
var _town_walls := {}  # town id -> {root, center, kits: {section: kit curtain}, bays: {section: [bay]}, stones: {section: [stone runs]}, storeys, seed}
var _demo := {}  # {wall, wear, id, center}
var _last := {}  # wall -> msec of its last blow
var _blows := {}  # wall -> blows since its wear last rose
var _thrown := {}  # wall -> a stone of its own in the air


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
	_towns_follow()
	if OS.get_cmdline_user_args().has("--wall-demo") and _demo.is_empty():
		_demo_build()
	var cam := get_viewport().get_camera_3d()
	var eye := cam.global_position if cam else Vector3.INF
	var near_r := float(Data.num("walls", "sim_radius", 12.0))
	for id in _town_walls:
		_wear(int(id), _town_walls[id], eye, near_r)
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
## ground (world). The siege's men stream to them (army_assault.gd).
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
## a breach leaves, which men storming it climb (army_assault.gd).
func rubble_height(at: Vector3) -> float:
	var top := -INF
	for w in _walls():
		if w.distance_to(at) < 0.6:
			top = maxf(top, w.rubble_height(at))
	return top


func _walls() -> Array:
	var out := []
	for id in _town_walls:
		for runs in (_town_walls[id]["stones"] as Dictionary).values():
			for w in runs:
				if is_instance_valid(w):
					out.append(w)
	if not _demo.is_empty() and is_instance_valid(_demo["wall"]):
		out.append(_demo["wall"])
	return out


# --- a town's wall -------------------------------------------------------------

## Every walled town's wall (towns.gd plans it: meta town_wall), one a tick; a rebuilt or gone town's goes with it.
func _towns_follow() -> void:
	if main.towns == null:
		return
	for id in _town_walls.keys():
		var tw: Dictionary = _town_walls[id]
		var t: Dictionary = main.towns.towns.get(id, {})
		if t.is_empty() or t.get("node") != tw["root"] or not is_instance_valid(tw["root"]):
			for runs in (tw["stones"] as Dictionary).values():
				for w in runs:
					if is_instance_valid(w):
						w.queue_free()
			_town_walls.erase(id)
	for id in main.towns.towns:
		if _town_walls.has(id):
			continue
		var root: Node3D = main.towns.towns[id].get("node")
		if root == null or not is_instance_valid(root) or not root.is_inside_tree() or not root.has_meta("town_wall"):
			continue
		_build(int(id), root, root.get_meta("town_wall"))
		return  # one wall a tick: the frame never waits on more


## The damage section a point (town-local) faces: section 0 north, then clockwise (bridge damage.js sectionFacing).
static func section_of(p: Vector2, sections: int) -> int:
	var ang := fposmod(atan2(p.x, -p.y) + PI / sections, TAU)
	return int(floor(ang / (TAU / sections))) % sections


## A town's wall as towns.gd planned it: the kit curtain, one piece a damage section (each stretch's bays in that
## section, in the line's order), its towers and gatehouses; whole until the damage fact says otherwise.
func _build(id: int, root: Node3D, plan: Dictionary) -> void:
	var Builder := preload("res://scripts/castle_builder.gd")
	var builder = Builder.new()
	var storeys := int(plan.get("storeys", 2))
	var seed := int(plan.get("seed", id))
	var sections := int(Data.num("walls", "ring.sections", 8))
	var fade: float = main.towns._reach("castle", 220.0)
	var by := {}
	for b in plan.get("bays", []):
		var p: Vector3 = (b[0] as Vector3) * S
		var s := section_of(Vector2(p.x, p.z), sections)
		if not by.has(s):
			by[s] = []
		(by[s] as Array).append(b)
	var kits := {}
	for s in by:
		kits[s] = _kit(root, "TownWall%d" % s, builder.town_wall(by[s], [], storeys, seed), fade)
	if not (plan.get("towers", []) as Array).is_empty():
		_kit(root, "TownWallTowers", builder.town_wall([], plan["towers"], storeys, seed), fade)
	for g in plan.get("gates", []):
		var q: Vector2 = g[0]
		var n: Vector2 = g[1]
		var gm := _kit(root, "TownGate", builder.town_gate(storeys, int(q.x * 100.0)), fade)
		gm.position = Vector3(q.x, main.towns._ground_y(root.global_position, Vector3(q.x, 0, q.y)) - 0.02, q.y)
		gm.rotation.y = atan2(n.x, n.y)
	_town_walls[id] = {"root": root, "center": root.global_position, "kits": kits, "bays": by, "stones": {}, "storeys": storeys, "seed": seed}


## A piece of the kit wall on its town, at our scale, faded out past its reach as the town's buildings are.
func _kit(root: Node3D, name_: String, mesh: Mesh, fade: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name_
	mi.mesh = mesh
	mi.scale = Vector3.ONE * S
	root.add_child(mi)
	main.towns._fade_beyond(mi, fade)
	return mi


## Each section at the wear the damage fact gives it: whole, the kit curtain; cracked or breached, stacked stones in
## its place at that wear (and the kit again once the realm has mended it).
func _wear(id: int, tw: Dictionary, eye: Vector3, near_r: float) -> void:
	var dmg: Array = (main.awareness.town(id).get_var(&"damage", {}, false) as Dictionary).get("walls", []) if main.awareness else []
	var stones: Dictionary = tw["stones"]
	for s in tw["kits"]:
		var d: Dictionary = dmg[s] if s < dmg.size() and dmg[s] is Dictionary else {}
		var wear := float(d.get("wear", 0.0))
		if String(d.get("stage", "whole")) == "whole":
			if stones.has(s):
				for w in stones[s]:
					if is_instance_valid(w):
						w.queue_free()
				stones.erase(s)
				(tw["kits"][s] as Node3D).visible = true
				_publish(null, tw["root"])
			continue
		if not stones.has(s):
			stones[s] = _stone_runs(id, tw, s)
			(tw["kits"][s] as Node3D).visible = false
			_publish(null, tw["root"])
		for w in stones[s]:
			if not is_instance_valid(w):
				continue
			var near: bool = eye != Vector3.INF and w.distance_to(eye) < near_r
			w.set_hot(near or w.busy())
			if absf(wear - w.shown[0]) > 0.005:
				w.wear_to(0, wear, near)
				_blows[w] = 0
			_keep_striking(w, tw["center"])


## A section's bays as stacked stones: one run for each unbroken stretch of them (a gate or a lane's gap splits a
## section), as long, as high and on the same line as the kit curtain it stands in for, its merlons outward.
func _stone_runs(id: int, tw: Dictionary, s: int) -> Array:
	var root: Node3D = tw["root"]
	var bays: Array = tw["bays"][s]
	var half := 1.0 * S  # half a 2 m bay
	var runs := []
	var run := []
	for b in bays:
		var p: Vector3 = root.global_transform * ((b[0] as Vector3) * S)
		if not run.is_empty() and Vector2(p.x - run[-1][0].x, p.z - run[-1][0].z).length() > half * 3.2:
			runs.append(run)
			run = []
		run.append([p, float(b[1])])
	if not run.is_empty():
		runs.append(run)
	var out := []
	for r in runs.size():
		var bs: Array = runs[r]
		var yaw: float = bs[0][1]
		var along := Vector3(cos(yaw), 0, -sin(yaw))  # a bay's own +x, as towns.gd laid it
		var first: Vector3 = bs[0][0]
		var last: Vector3 = bs[-1][0]
		if bs.size() > 1 and (last - first).dot(along) < 0.0:
			along = -along
		var pts := PackedVector3Array([first - along * half])
		for b in bs:
			pts.append(b[0])
		pts.append(last + along * half)
		for i in pts.size():
			pts[i].y = main.terrain.height_at(pts[i].x, pts[i].z)
		var outward := Vector3(sin(yaw), 0, cos(yaw))  # the bay's outer face
		var d: Vector3 = pts[pts.size() - 1] - pts[0]
		var right := Vector3(-d.z, 0, d.x)
		var wall := StoneWall.build_along(pts, int(tw["storeys"]) * 3.0, Color.WHITE, {
			"sections": 1, "outer": 1.0 if right.dot(outward) >= 0.0 else -1.0, "seed": int(tw["seed"]) * 31 + s * 7 + r,
			"ground": func(p: Vector3) -> float: return main.terrain.height_at(p.x, p.z)})
		add_child(wall)
		wall.opened.connect(_publish.bind(wall, root))
		out.append(wall)
	return out


## A wall's standing foot goes to its town's walking map: a breach is a way in. Every stone run of the town
## together, so one never writes over another's.
func _publish(_by: Node3D, root: Node3D) -> void:
	if not is_instance_valid(root):
		return
	var all := []
	for id in _town_walls:
		if _town_walls[id]["root"] == root:
			for runs in (_town_walls[id]["stones"] as Dictionary).values():
				for w in runs:
					if is_instance_valid(w):
						all.append(w)
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
