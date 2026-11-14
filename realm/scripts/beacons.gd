extends Node
## Beacons on the town walls (casebook, War and sieges: the threat is seen coming; the beacons of Gondor, Stronghold's
## and Warcraft III's alarm when a foe nears a town; every action gets a reaction). When a host of another house (or
## raiders) comes within walls.json beacons.reach of a walled town, a fire is lit on its wall walk on the side the
## host comes from: the kit's fire pit and flames, its glow, a column of dark smoke, a watchman of the town's house
## beside it pointing out at the host. It burns while the host is near and beacons.linger seconds after. One per town.
## The hosts are the mirror's (awareness `armies`, /world units); the wall walk is walls.gd's (walk_of). Knobs:
## data/walls.json beacons.

const Data := preload("res://scripts/data.gd")
const CampKit := preload("res://scripts/camp_kit.gd")  # the fire pit and flames, as every camp's
const Fire := preload("res://scripts/fire.gd")  # the fire's glow
const Heraldry := preload("res://scripts/heraldry.gd")  # the watchman's house colour

var walls: Node
var _lit := {}  # town id -> {node, until}
var _rng := RandomNumberGenerator.new()


func _init(w: Node) -> void:
	walls = w
	name = "Beacons"


func _ready() -> void:
	var t := Timer.new()
	t.wait_time = Data.num("walls", "beacons.every", 2.0)
	t.autostart = true
	t.timeout.connect(_tick)
	add_child(t)


func _tick() -> void:
	var main: Node = walls.main
	if main == null or main.awareness == null or main.terrain == null:
		return
	var k: Dictionary = Data.value("walls", "beacons", {})
	var reach := float(k.get("reach", 16.0))
	var now := Time.get_ticks_msec() / 1000.0
	var hosts: Array = main.awareness.realm.get_var(&"armies", [], false)
	for id in walls.walled():
		var root: Node3D = walls.root_of(id)
		var owner := int(root.get_meta("owner", -1))
		var near := Vector3.INF
		var bd := reach
		for g in hosts:
			if int(g.get("owner", -1)) == owner:
				continue
			var p: Vector3 = main.terrain.world_pos(float(g["x"]), float(g["y"]))
			var d := Vector2(p.x - root.global_position.x, p.z - root.global_position.z).length()
			if d < bd:
				bd = d
				near = p
		var b: Dictionary = _lit.get(id, {})
		if near != Vector3.INF:
			if b.is_empty() or not is_instance_valid(b["node"]):
				b = _light(id, root, near, k)
				if b.is_empty():
					continue
				_lit[id] = b
			b["until"] = now + float(k.get("linger", 30.0))
		elif not b.is_empty() and (now > float(b["until"]) or not is_instance_valid(b["node"])):
			if is_instance_valid(b["node"]):
				(b["node"] as Node).queue_free()
			_lit.erase(id)
	for id in _lit.keys():
		if not walls.walled().has(id):
			_lit.erase(id)  # its town (and the beacon on it) is gone


## The beacon on town `id`'s wall walk nearest the host at `toward`, or {} (no walk standing on that side).
func _light(id: int, root: Node3D, toward: Vector3, k: Dictionary) -> Dictionary:
	var main: Node = walls.main
	var p: Vector3 = walls.walk_of(id, toward)
	if p == Vector3.INF:
		return {}
	var holder := Node3D.new()
	holder.name = "Beacon"
	root.add_child(holder)  # it goes with its town
	holder.global_position = p
	CampKit.fire(main.scenes, holder, Vector3.ZERO, Color.WHITE, 0, _rng)
	Fire.hearth_light(holder, Vector3.ZERO)
	var smoke: CPUParticles3D = main.scenes.puffs(Data.colour(k.get("smoke"), Color(0.25, 0.24, 0.23, 0.7)), int(k.get("puffs", 16)), float(k.get("rise_s", 5.0)), 0.12, 0.3)
	smoke.position = Vector3(0, 0.08, 0)
	holder.add_child(smoke)
	smoke.emitting = true
	var house: Dictionary = main.awareness.houses_by_id().get(int(root.get_meta("owner", -1)), {})
	var man: Node3D = main.scenes.people.make(_rng, "soldier", Heraldry.colour(house, Color(0.5, 0.5, 0.5)), "adult")
	holder.add_child(man)
	var inward := (root.global_position - p) * Vector3(1, 0, 1)
	man.global_position = p + inward.normalized() * float(k.get("watch_in", 0.1)) + inward.normalized().cross(Vector3.UP) * 0.08
	man.global_rotation.y = atan2(toward.x - man.global_position.x, toward.z - man.global_position.z)
	main.scenes.people.play(man, String(k.get("clip", "Pointing_Forward")), 1.0)
	return {"node": holder, "until": 0.0}
