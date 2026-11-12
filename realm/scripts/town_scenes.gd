extends Node3D
## Town life's director: the one reducer of docs/TOWN_LIFE.md. Each town near the camera gets a day of group
## scenes from realm/data/town_scenes.json (rows, not code): what the town's state allows and favours (works.gd's
## states from the mirror: war, levy, hunger, low, prosperity, grief, feast, a ruling, a riot), at its hour, at the
## places it has (its well, market, square, gate, tavern, forge, granary), capped by its size. The director alone
## writes each town's running scenes and claimed places to the store (the mirror's town scope: `scenes`,
## `claims`). Each person in a scene gets one LimboAI tree (walk to their spot, act, leave) and dispatches back
## when they've gone; news on the bus (awareness.gd stimulus) interrupts them with the reaction its tone calls for
## (flee, gather, kneel, cheer), then they go back to their day. Everyone walks with the Mover (mover.gd).
## Copies the proven designs: Unreal's smart objects and slots, GTA's scenario points, RimWorld's moods.

const Data := preload("res://scripts/data.gd")
const People := preload("res://scripts/people.gd")
const Works := preload("res://scripts/works.gd")
const SceneKinds := preload("res://scripts/scene_kinds.gd")
const Mover := preload("res://scripts/mover.gd")

var main: Node
var _d: Dictionary
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _live := {}  # town id -> Array of running scenes {row, key, at, ends, cast: Array[Node3D], ending}
var _seq := 0


func _init(owner: Node) -> void:
	main = owner
	name = "TownScenes"
	_d = Data.read("town_scenes")


func _ready() -> void:
	_rng.randomize()
	if main.awareness:
		main.awareness.stimulus.connect(_on_stimulus)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = float(_d.get("director", {}).get("tick", 2.0))
	var cam := get_viewport().get_camera_3d()
	if cam == null or main.towns == null or main.awareness == null:
		return
	var near := float(_d.get("director", {}).get("near", 30.0))
	for id in main.towns.towns.keys():
		var t: Dictionary = main.towns.towns[id]
		var root: Node3D = t.get("node")
		if root == null or not is_instance_valid(root):
			_end_town(int(id))
			continue
		if cam.global_position.distance_to(root.global_position) > near:
			_end_town(int(id))
			continue
		_direct(int(id), root, t.get("data", {}) as Dictionary)
	for id in _live.keys():
		if not main.towns.towns.has(id):
			_end_town(int(id))


# --- the reducer ---------------------------------------------------------------------------------

## One town's tick: scenes past their time end, new ones start up to the town's cap, and the store learns it.
func _direct(id: int, root: Node3D, c: Dictionary) -> void:
	var bb: Blackboard = main.awareness.town(id)
	var states := Works.states_bb(bb)
	if String(bb.get_var(&"mood", "", false)) == "riot":
		states.append("riot")
	var now := Time.get_ticks_msec()
	var running: Array = _live.get(id, [])
	for s in running:
		if not bool(s["ending"]) and now >= int(s["ends"]):
			_end(s)
	running = running.filter(func(s): return not (s["cast"] as Array).is_empty() or not bool(s["ending"]))
	var D: Dictionary = _d.get("director", {}).get("most", {})
	var cap := mini(int(D.get("cap", 9)), int(float(D.get("base", 3)) + float(D.get("per_size", 0.5)) * float(c.get("size", 1))))
	var active := running.filter(func(s): return not bool(s["ending"])).size()
	var tries := 4
	while active < cap and tries > 0:
		tries -= 1
		var row := _pick(states, running, root)
		if row.is_empty():
			break
		var s := _start(id, root, row)
		if s.is_empty():
			continue
		running.append(s)
		active += 1
	_live[id] = running
	bb.set_var(&"scenes", running.map(func(s): return {"id": s["row"]["id"], "at": s["at"], "ending": s["ending"]}))
	bb.set_var(&"claims", running.filter(func(s): return not bool(s["ending"])).map(func(s): return s["key"]))


## A scene row the town may play now, drawn by weight: in its hours, its needs met, under its own cap.
func _pick(states: Array, running: Array, root: Node3D) -> Dictionary:
	var h := Works.hour()
	var pool: Array = []
	var total := 0.0
	for row in _d.get("scenes", []):
		var hours: Array = row.get("hours", [0, 24])
		var a := float(hours[0])
		var b := float(hours[1])
		if not ((h >= a and h < b) if a <= b else (h >= a or h < b)):
			continue
		var needs: Array = row.get("needs", [])
		if not needs.is_empty() and not needs.any(func(n): return n in states):
			continue
		if running.filter(func(s): return s["row"]["id"] == row["id"] and not bool(s["ending"])).size() >= int(row.get("most", 1)):
			continue
		if _object_at(root, String(row.get("at", "square"))) == Vector3.INF:
			continue
		var w := float(row.get("weight", 1.0))
		for st in states:
			w *= float((row.get("moods", {}) as Dictionary).get(st, 1.0))
		if w <= 0.0:
			continue
		pool.append([row, w])
		total += w
	if pool.is_empty():
		return {}
	var r := _rng.randf() * total
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return pool[-1][0]


## Where an object stands in this town (world), from what the town records; INF if it has none.
func _object_at(root: Node3D, key: String) -> Vector3:
	var o: Dictionary = _d.get("objects", {}).get(key, {})
	var centre := root.global_position
	if o.is_empty():
		return Vector3.INF
	if bool(o.get("square", false)):
		return centre
	if o.has("place"):
		var places: Dictionary = root.get_meta("places", {})
		return centre + Vector3(places[o["place"]]) if places.has(o["place"]) else Vector3.INF
	if bool(o.get("gate", false)):
		var g := Works.gate(root, Vector3.ZERO)
		return centre + g if g != Vector3.INF else Vector3.INF
	if o.has("works"):
		var b := Works.find(root, String(o["works"]))
		if not b.is_empty():
			return centre + Vector3(b["at"])
		if o.has("or"):
			return _object_at(root, String(o["or"]))
	return Vector3.INF


# --- a scene's cast ------------------------------------------------------------------------------

func _start(id: int, root: Node3D, row: Dictionary) -> Dictionary:
	var at := _object_at(root, String(row.get("at", "square")))
	if at == Vector3.INF or main.scenes == null:
		return {}
	var last: Array = row.get("last", [30, 60])
	_seq += 1
	var s := {"row": row, "key": "%s:%d" % [row["id"], _seq], "at": at, "cast": [], "ending": false,
		"ends": Time.get_ticks_msec() + int(_rng.randf_range(float(last[0]), float(last[1])) * 1000.0), "town": id}
	var axis := _rng.randf() * TAU
	var first := Vector3.INF
	for role in row.get("roles", []):
		var n: Array = role.get("n", [1, 1])
		var count := _rng.randi_range(int(n[0]), int(n[1]))
		for i in count:
			var spot := _spot(at, role, i, count, axis)
			var face := at
			if bool(role.get("face", false)) and first != Vector3.INF:
				face = first
			var p := _cast(s, role, main.scenes.stand(spot), face)
			if p and first == Vector3.INF:
				first = main.scenes.stand(spot)
	return s


## A person's spot by the role's form: a ring round the object, a line out from it, a pair facing each other.
func _spot(at: Vector3, role: Dictionary, i: int, count: int, axis: float) -> Vector3:
	var form := String(role.get("form", "ring"))
	var r: Array = role.get("r", [0.4, 0.6])
	match form:
		"line":
			var gap := float(role.get("gap", 0.2))
			var dir := Vector3(cos(axis), 0, sin(axis))
			return at + dir * (0.35 + gap * i)
		"pair":
			var d := _rng.randf_range(float(r[0]), float(r[1]))
			var side := 1.0 if i % 2 == 0 else -1.0
			return at + Vector3(cos(axis), 0, sin(axis)) * d * 0.5 * side + Vector3(-sin(axis), 0, cos(axis)) * 0.15 * float(i / 2)
		_:
			var a := axis + TAU * float(i) / float(maxi(count, 1)) + _rng.randf_range(-0.2, 0.2)
			var d2 := _rng.randf_range(float(r[0]), float(r[1]))
			return at + Vector3(cos(a), 0, sin(a)) * d2


## One person for a role: made at the edge of view, given their tree, walked to their spot by the Mover.
func _cast(s: Dictionary, role: Dictionary, spot: Vector3, face: Vector3) -> Node3D:
	var who := String(role.get("who", "townsfolk"))
	var age := ""
	if who == "child":
		who = "townsfolk"
		age = "child"
	var cloth: Array = People.cloth_of(who)
	var person: Node3D = main.scenes.people.make(_rng, who, cloth[_rng.randi() % cloth.size()] if not cloth.is_empty() else Color.WHITE, age)
	if person == null:
		return null
	add_child(person)
	var D: Dictionary = _d.get("director", {})
	var enter: Array = D.get("enter", [1.2, 2.0])
	var a := _rng.randf() * TAU
	person.global_position = main.scenes.stand(spot + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(float(enter[0]), float(enter[1])))
	var mover: Node = Mover.of(person)
	mover.speed = float(D.get("pace", 0.17))
	var bt := BehaviorTree.new()
	bt.root_task = _tree()
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(person)
	player.behavior_tree = bt
	var bb := player.blackboard
	bb.set_var(&"slot", spot)
	bb.set_var(&"face", face)
	bb.set_var(&"clips", role.get("clips", ["Idle"]))
	bb.set_var(&"leaving", false)
	bb.set_var(&"exit", person.global_position)
	bb.set_var(&"react", {})
	bb.set_var(&"done", _done.bind(s, person))
	person.add_child(player)
	(s["cast"] as Array).append(person)
	return person


## A person's day in a scene: a reaction first whenever there is one, else walk to the spot, act until the
## scene ends, walk off. Re-checked every tick (a dynamic selector), so news cuts in at once.
func _tree() -> BTTask:
	var life := BTDynamicSelector.new()
	var react := BTSequence.new()
	react.add_child(HasReact.new())
	react.add_child(DoReact.new())
	life.add_child(react)
	var day := BTSequence.new()
	day.add_child(GoTo.new())
	day.add_child(Act.new())
	day.add_child(Leave.new())
	life.add_child(day)
	return life


## The scene's time is up: its people leave (their trees walk them off and dispatch back).
func _end(s: Dictionary) -> void:
	s["ending"] = true
	for p in s["cast"]:
		var m := (p as Node).get_node_or_null("Mind") as BTPlayer
		if m:
			m.blackboard.set_var(&"leaving", true)


## A person has walked off: the only way a cast member leaves the store.
func _done(s: Dictionary, person: Node3D) -> void:
	(s["cast"] as Array).erase(person)
	if is_instance_valid(person):
		person.queue_free()


## Out of range: the town's scenes are put away at once (nobody watches them go).
func _end_town(id: int) -> void:
	if not _live.has(id):
		return
	for s in _live[id]:
		for p in s["cast"]:
			if is_instance_valid(p):
				p.queue_free()
	_live.erase(id)
	if main.awareness:
		var bb: Blackboard = main.awareness.town(id)
		bb.set_var(&"scenes", [])
		bb.set_var(&"claims", [])


# --- news: the reactions ---------------------------------------------------------------------------

func _on_stimulus(kind: String, pos: Vector3, radius: float, _house: String, _strength: float) -> void:
	var row: Dictionary = _d.get("reactions", {}).get(SceneKinds.tone(kind), {})
	if row.is_empty() or radius <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(float(row.get("last", 20)) * 1000.0)
	for scenes in _live.values():
		for s in scenes:
			for p in s["cast"]:
				if not is_instance_valid(p):
					continue
				var d := (p as Node3D).global_position.distance_to(pos)
				if d > radius:
					continue
				var act: Dictionary = row.get("near_act", {}) if d / radius <= float(row.get("near", 1.0)) else row.get("far_act", row.get("near_act", {}))
				var m := (p as Node).get_node_or_null("Mind") as BTPlayer
				if m and not act.is_empty():
					m.blackboard.set_var(&"react", {"act": act.get("act", "gather"), "at": pos, "r": float(act.get("r", 1.0)), "clips": act.get("clips", ["Looking_Around"]), "until": until})


# --- the tasks: one tree each, the person's only decider ----------------------------------------

## What every task does the same way: play clips in turn, face a point.
class Kit:
	## Plays a person's clips in turn, never the same twice running, a new one every few seconds.
	static func _cycle(agent: Node, bb: Blackboard, clips: Array, delta: float) -> void:
		var left := float(bb.get_var(&"clip_left", 0.0)) - delta
		if left > 0.0:
			bb.set_var(&"clip_left", left)
			return
		var last := String(bb.get_var(&"clip", ""))
		var pool := clips.filter(func(c): return c != last)
		if pool.is_empty():
			pool = clips
		var clip := String(pool[randi() % pool.size()]) if not pool.is_empty() else "Idle"
		bb.set_var(&"clip", clip)
		bb.set_var(&"clip_left", randf_range(3.0, 7.0))
		People.play(agent, clip, randf_range(0.9, 1.1))


	static func _face(agent: Node3D, at: Vector3) -> void:
		var f := Vector2(at.x - agent.global_position.x, at.z - agent.global_position.z)
		if f.length() > 0.01:
			agent.rotation.y = atan2(f.x, f.y)


class HasReact extends BTCondition:
	func _tick(_delta: float) -> Status:
		var r: Dictionary = blackboard.get_var(&"react", {})
		if r.is_empty():
			return FAILURE
		if Time.get_ticks_msec() > int(r.get("until", 0)):
			blackboard.set_var(&"react", {})
			return FAILURE
		return SUCCESS


class DoReact extends BTAction:
	func _enter() -> void:
		var r: Dictionary = blackboard.get_var(&"react", {})
		var me := agent as Node3D
		var at: Vector3 = r.get("at", me.global_position)
		var mover: Node = Mover.of(me)
		match String(r.get("act", "gather")):
			"flee":
				var away := (me.global_position - at)
				away.y = 0
				mover.go(me.global_position + away.normalized() * 1.5 if away.length() > 0.01 else me.global_position)
			"gather":
				var a := randf() * TAU
				mover.go(at + Vector3(cos(a), 0, sin(a)) * float(r.get("r", 1.0)))
			_:
				mover.stop()
		blackboard.set_var(&"clip_left", 0.0)

	func _tick(delta: float) -> Status:
		var r: Dictionary = blackboard.get_var(&"react", {})
		if r.is_empty() or Time.get_ticks_msec() > int(r.get("until", 0)):
			blackboard.set_var(&"react", {})
			return SUCCESS
		if not Mover.of(agent as Node3D).moving():
			Kit._face(agent as Node3D, r.get("at", Vector3.ZERO))
			Kit._cycle(agent, blackboard, r.get("clips", ["Looking_Around"]), delta)
		return RUNNING

	func _exit() -> void:
		Mover.of(agent as Node3D).stop()


class GoTo extends BTAction:
	func _enter() -> void:
		Mover.of(agent as Node3D).go(blackboard.get_var(&"slot", (agent as Node3D).global_position))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		Kit._face(agent as Node3D, blackboard.get_var(&"face", Vector3.ZERO))
		blackboard.set_var(&"clip_left", 0.0)
		return SUCCESS

	func _exit() -> void:
		Mover.of(agent as Node3D).stop()


class Act extends BTAction:
	func _tick(delta: float) -> Status:
		if bool(blackboard.get_var(&"leaving", false)):
			return SUCCESS
		Kit._cycle(agent, blackboard, blackboard.get_var(&"clips", ["Idle"]), delta)
		return RUNNING


class Leave extends BTAction:
	func _enter() -> void:
		Mover.of(agent as Node3D).go(blackboard.get_var(&"exit", (agent as Node3D).global_position))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		var done: Callable = blackboard.get_var(&"done", Callable())
		if done.is_valid():
			done.call()
		return SUCCESS
