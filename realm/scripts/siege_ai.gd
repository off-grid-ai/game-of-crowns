extends Node
## A siege's assault parties, fought by the men in them rather than played from
## a timeline. Each man runs his own LimboAI state machine (LimboHSM): he waits
## in the camp, goes forward behind his shield when his party is sent, runs the
## last stretch, fights at the foot of the wall (a cut, a guard, another cut,
## each different), and falls back to the camp; or he is cut down there and
## stays down, and the camp sends a fresh man in his place for the next rush.
## His legs follow the ground he covers (motion.gd), so nobody glides.
##
## scenes.gd builds the camp and the walls and hands the parties here. It is
## loaded only when the LimboAI extension is present; without it the old
## timeline (scenes._assault's cycle) plays instead.
##
## The breach changes the fight (docs/research/world-and-siege-rules.md, wall
## rule 12; Total War: Warhammer III's lesson that a gap nobody reacts to
## doesn't read): once a stone wall near the front stands open (walls.gd
## breaches_near; the wall's wear is the bridge's damage fact), every party is
## sent at once and from then on through the gap, fanned across it, over the
## rubble ramp; and the holder's men form a block behind it, facing out, cutting
## and guarding at whoever comes through. Knobs: data/walls.json assault.

const WALK := 0.17  # a man's walk, units a second
const RUN := 0.45
const WAVE := 15.0  # seconds between one party's rushes
const AT_WALL := [3.0, 4.6]  # how long a man fights at the foot of the wall
const FALL := 0.06  # the chance a blow from above, landing, kills him outright
const Data := preload("res://scripts/data.gd")

var scenes: Node
var root: Node3D
var r: RandomNumberGenerator
var col: Color
var parties := []  # arrays of men: {home, foot, node, hsm, alive, out, ...}
var clock := 0.0
var held := Color(0.6, 0.6, 0.6)  # the holder's colours: the block behind a breach
var _held_at := {}  # breach (world, snapped) -> its defenders [{node, last, cool}]
var _look := 0.0


func start(s: Node, siege: Node3D, rng: RandomNumberGenerator, colour: Color, groups: Array, first: Array, holder := Color(0.6, 0.6, 0.6)) -> void:
	scenes = s
	root = siege
	r = rng
	col = colour
	held = holder
	parties = groups
	root.add_child(self)
	for p in parties.size():
		for m in parties[p]:
			_man(m)
		# Each party's first rush at its own time, then every WAVE seconds.
		var t := Timer.new()
		t.wait_time = WAVE
		t.timeout.connect(_send.bind(p))
		add_child(t)
		var go := get_tree().create_timer(first[p])
		go.timeout.connect(func():
			if is_instance_valid(t):
				_send(p)
				t.start())


## A fresh man in the camp, and his mind.
func _man(m: Dictionary) -> void:
	if m.has("node") and is_instance_valid(m["node"]) and m["node"].has_meta("dead"):
		m["node"].remove_from_group("people")  # the fallen stay where they fell
	var f: Node3D = scenes.people.make(r, "soldier", col, "adult")
	f.position = scenes.stand(m["home"])
	var face: Vector3 = (m["foot"] - m["home"]).normalized()
	f.rotation.y = atan2(face.x, face.z)
	root.add_child(f)
	scenes.arm(f, "sword")
	m["node"] = f
	m["alive"] = true
	m["down"] = false
	m["out"] = false
	m["last"] = ""
	var hsm := LimboHSM.new()
	var camp := LimboState.new()
	var advance := LimboState.new()
	var rush := LimboState.new()
	var fight := LimboState.new()
	var back := LimboState.new()
	var dead := LimboState.new()
	for st in [camp, advance, rush, fight, back, dead]:
		hsm.add_child(st)
	camp.call_on_enter(func():
		m["out"] = false
		f.rotation.y = atan2(face.x, face.z)
		scenes.people.play(f, "Sword_Idle"))
	advance.call_on_enter(func():
		m["out"] = true
		m["half"] = m["home"].lerp(m["foot"], 0.55)
		scenes.people.play(f, "SS_Walk"))  # on behind raised shields
	advance.call_on_update(func(dt: float): _go(m, m["half"], WALK, dt, &"rush"))
	rush.call_on_enter(func(): scenes.people.play(f, "Sprint"))
	rush.call_on_update(func(dt: float): _go(m, m["foot"], RUN, dt, &"fight"))
	fight.call_on_enter(func():
		m["until"] = clock + r.randf_range(AT_WALL[0], AT_WALL[1])
		m["cool"] = 0.0)
	fight.call_on_update(func(dt: float): _fight(m, dt))
	back.call_on_enter(func(): scenes.people.play(f, "Walk"))
	back.call_on_update(func(dt: float): _go(m, m["home"], WALK, dt, &"camp"))
	# Cut down: he stays down. Nothing leads out of it.
	dead.call_on_enter(func():
		m["down"] = true
		m["alive"] = false
		m["out"] = false
		if not f.has_meta("dead"):  # an arrow from the walls may have felled him already
			scenes.die(f, scenes.DEATHS[r.randi() % scenes.DEATHS.size()], r))
	dead.set_guard(func() -> bool: return not m.get("down", false))
	hsm.add_transition(camp, advance, &"go")
	hsm.add_transition(advance, rush, &"rush")
	hsm.add_transition(rush, fight, &"fight")
	hsm.add_transition(fight, back, &"back")
	hsm.add_transition(back, camp, &"camp")
	hsm.add_transition(hsm.ANYSTATE, dead, &"die")
	hsm.initial_state = camp
	f.add_child(hsm)
	hsm.initialize(f)
	hsm.set_active(true)
	m["hsm"] = hsm


## A party is sent: the fallen are replaced from the camp, and each man goes
## forward on his own beat.
func _send(p: int) -> void:
	# The camera comes in on the rush: low, from the camp side, on the stretch
	# of wall this party goes for (a beat of the siege, as battles call theirs).
	var men: Array = parties[p]
	if not men.is_empty():
		var foot := Vector3.ZERO
		var home := Vector3.ZERO
		for m in men:
			foot += m["foot"]
			home += m["home"]
		foot /= men.size()
		home /= men.size()
		var back: Vector3 = home - foot
		scenes.framing.emit(scenes.ground(foot.lerp(home, 0.3)), 2.0, atan2(back.x, back.z))
	for m in parties[p]:
		if not m["alive"]:
			_man(m)
		var t := get_tree().create_timer(r.randf_range(0.0, 0.8))
		t.timeout.connect(func():
			if m["alive"] and is_instance_valid(m["hsm"]):
				m["hsm"].dispatch(&"go"))


func _process(dt: float) -> void:
	clock += dt
	_look -= dt
	if _look <= 0.0:
		_look = 1.0
		_watch_breaches()
		_hold_the_gap()
	# Felled by an arrow from the walls (scenes._arrows): once he has fallen,
	# his mind goes to Dead too, and stops carrying him about.
	for p in parties:
		for m in p:
			if not m["alive"] and not m.get("down", false) and is_instance_valid(m.get("node")) and m["node"].has_meta("dead"):
				m["hsm"].dispatch(&"die")


# --- the breach (wall rule 12) -----------------------------------------------

## Once a second: a breach newly open near a party's stretch of wall turns the
## party to it (and sends it at once), and raises the block that holds it.
func _watch_breaches() -> void:
	if not Engine.has_meta("stone_walls"):
		return
	var walls: Node = Engine.get_meta("stone_walls")
	var k: Dictionary = Data.value("walls", "assault", {})
	for p in parties.size():
		var men: Array = parties[p]
		if men.is_empty():
			continue
		var foot := Vector3.ZERO
		var home := Vector3.ZERO
		for m in men:
			foot += m.get("wall_foot", m["foot"])
			home += m["home"]
		foot /= men.size()
		home /= men.size()
		var found: Array = walls.breaches_near(root.global_transform * foot, float(k.get("reach", 2.5)))
		if found.is_empty():
			continue
		var gap: Vector3 = root.global_transform.affine_inverse() * (found[0] as Vector3)
		var key := Vector3i(roundi(gap.x * 10.0), 0, roundi(gap.z * 10.0))
		var inward: Vector3 = (gap - home)
		inward.y = 0.0
		inward = inward.normalized()
		var across := Vector3(-inward.z, 0, inward.x)
		var fresh := false
		for i in men.size():
			var m: Dictionary = men[i]
			if m.get("gap", Vector3i.MAX) == key:
				continue
			fresh = true
			if not m.has("wall_foot"):
				m["wall_foot"] = m["foot"]
			var fan := (i - (men.size() - 1) * 0.5) / maxf(men.size() - 1, 1.0) * float(k.get("spread", 0.16))
			m["foot"] = gap + inward * float(k.get("through", 0.08)) + across * fan
			m["gap"] = key
		if not _held_at.has(key):
			_held_at[key] = _block(gap, inward, across, k)
		if fresh:
			_send(p)  # the gap is open: the party goes now, not at its next turn


## The holder's men behind a breach: a block in rows, facing out at it.
func _block(gap: Vector3, inward: Vector3, across: Vector3, k: Dictionary) -> Array:
	var out := []
	var n := int(k.get("defenders", 8))
	var rows := maxi(1, int(k.get("rows", 2)))
	var per := ceili(float(n) / rows)
	for i in n:
		var row := i / per
		var col_i := i % per
		var p: Vector3 = gap + inward * (float(k.get("back", 0.28)) + row * 0.1) + across * ((col_i - (per - 1) * 0.5) * 0.09)
		var f: Node3D = scenes.people.make(r, "soldier", held, "adult")
		f.position = scenes.stand(p)
		f.rotation.y = atan2(-inward.x, -inward.z)
		root.add_child(f)
		scenes.arm(f, "spear" if row == 0 else "sword")
		scenes.people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
		out.append({"node": f, "last": "", "cool": r.randf_range(0.0, 1.0), "front": row == 0})
	return out


## The front row of each block cuts and guards at the attackers in the gap; the
## rows behind brace (Sword_Idle) until a man ahead of them falls.
func _hold_the_gap() -> void:
	var near := []
	for p in parties:
		for m in p:
			if m["alive"] and m.get("gap", null) != null and is_instance_valid(m.get("node")):
				near.append(m["node"].position)
	for key in _held_at:
		for d in _held_at[key]:
			var f: Node3D = d["node"]
			if not is_instance_valid(f) or f.has_meta("dead"):
				continue
			d["cool"] = float(d["cool"]) - 1.0
			if float(d["cool"]) > 0.0:
				continue
			var close := near.any(func(q): return Vector2(q.x - f.position.x, q.z - f.position.z).length() < 0.4)
			if not close:
				continue
			var move: String = scenes.cut(r, d["last"]) if (d["front"] and r.randf() < 0.6) else scenes.guard(r)
			d["last"] = move
			scenes.people.play(f, move, r.randf_range(0.95, 1.15))
			var mo: AnimationTree = scenes.people.motion(f)
			d["cool"] = (mo.get_animation(move).length if mo and mo.has_animation(move) else 1.0) + r.randf_range(0.2, 0.8)


## Walks or runs toward `to`; there, the next state.
func _go(m: Dictionary, to: Vector3, speed: float, dt: float, then: StringName) -> void:
	var n: Node3D = m["node"]
	var d := to - n.position
	d.y = 0
	if d.length() < 0.02:
		m["hsm"].dispatch(then)
		return
	n.position = scenes.stand(n.position + d.normalized() * minf(speed * dt, d.length()))
	n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.z), minf(1.0, dt * 6.0))


## At the foot of the wall: a cut, a guard, another cut, never the same twice
## running; what comes down from above may kill him.
func _fight(m: Dictionary, dt: float) -> void:
	var n: Node3D = m["node"]
	var face: Vector3 = (m["foot"] - m["home"]).normalized()
	n.rotation.y = lerp_angle(n.rotation.y, atan2(face.x, face.z), minf(1.0, dt * 6.0))
	if clock > m["until"]:
		m["hsm"].dispatch(&"back")
		return
	m["cool"] -= dt
	if m["cool"] > 0.0:
		return
	var move: String = scenes.cut(r, m["last"]) if r.randf() < 0.6 else scenes.guard(r)
	m["last"] = move
	var mo: AnimationTree = scenes.people.motion(n)
	var length: float = mo.get_animation(move).length if mo and mo.has_animation(move) else 1.0
	scenes.people.play(n, move, r.randf_range(0.95, 1.15))
	m["cool"] = length + r.randf_range(0.2, 0.6)
	if r.randf() < FALL:
		var t := get_tree().create_timer(length * 0.5)
		t.timeout.connect(func():
			if m["alive"] and is_instance_valid(m["hsm"]):
				m["hsm"].dispatch(&"die"))
