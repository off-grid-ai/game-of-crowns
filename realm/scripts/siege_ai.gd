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
##
## The storm (switch: --storm=on, on with --wall-demo, or walls.json
## assault.storm; Stronghold's and Total War's assault through the gap): the
## fight happens in the gap. Each man pairs off with a man of the other side and
## fights him with the duels' sword moves (combat.gd), blow, parry, reel, until
## one falls; the holder's back row steps up as the front falls, and a few fresh
## men come up from the town. Whoever loses falls back: a party that loses half
## of its men in the gap walks back to the camp and the next wave comes; a block
## worn down to a few with none left to come breaks and runs into the town. Then
## the besiegers pour in over the rubble, cheer, and put the town to the torch
## (fire.gd: its houses catch one after another, as the fire rules say).

const WALK := 0.17  # a man's walk, units a second
const RUN := 0.45
const WAVE := 15.0  # seconds between one party's rushes
const AT_WALL := [3.0, 4.6]  # how long a man fights at the foot of the wall
const FALL := 0.06  # the chance a blow from above, landing, kills him outright
const Data := preload("res://scripts/data.gd")
const Combat := preload("res://scripts/combat.gd")
const Fire := preload("res://scripts/fire.gd")

var scenes: Node
var root: Node3D
var r: RandomNumberGenerator
var col: Color
var parties := []  # arrays of men: {home, foot, node, hsm, alive, out, ...}
var clock := 0.0
var held := Color(0.6, 0.6, 0.6)  # the holder's colours: the block behind a breach
var town_at := Vector3.INF  # the besieged town (world): where the torch goes once it falls
var _held_at := {}  # breach key -> {gap, inward, across, men: [defenders], reserve, phase, at}
var _look := 0.0
var _storm := false


## The storm through the breach on for this run? --storm=on/off, on with the
## wall demo, else walls.json assault.storm.
static func storm_on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--storm=off"):
		return false
	if args.has("--storm=on") or args.has("--wall-demo"):
		return true
	return bool(Data.value("walls", "assault.storm", false))


func start(s: Node, siege: Node3D, rng: RandomNumberGenerator, colour: Color, groups: Array, first: Array, holder := Color(0.6, 0.6, 0.6), town := Vector3.INF) -> void:
	scenes = s
	root = siege
	r = rng
	col = colour
	held = holder
	town_at = town
	_storm = storm_on()
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
	m["fell_in_gap"] = false
	m["beaten"] = false
	var hsm := LimboHSM.new()
	var camp := LimboState.new()
	var advance := LimboState.new()
	var rush := LimboState.new()
	var fight := LimboState.new()
	var back := LimboState.new()
	var dead := LimboState.new()
	var melee := LimboState.new()  # the storm: man to man in the gap
	var inside := LimboState.new()  # the gap taken: in over the rubble
	for st in [camp, advance, rush, fight, back, dead, melee, inside]:
		hsm.add_child(st)
	camp.call_on_enter(func():
		m["out"] = false
		m["beaten"] = false
		f.rotation.y = atan2(face.x, face.z)
		scenes.people.play(f, "Sword_Idle"))
	advance.call_on_enter(func():
		m["out"] = true
		m["half"] = m["home"].lerp(m["foot"], 0.55)
		scenes.people.play(f, "SS_Walk"))  # on behind raised shields
	advance.call_on_update(func(dt: float): _go(m, m["half"], WALK, dt, &"rush"))
	rush.call_on_enter(func(): scenes.people.play(f, "Sprint"))
	rush.call_on_update(func(dt: float): _go(m, m["foot"], RUN, dt, &"melee" if _storming(m) else &"fight"))
	melee.call_on_enter(func():
		m["cool"] = r.randf_range(0.1, 0.6)
		m["busy"] = 0.0
		m["hp"] = int(Data.num("walls", "assault.hp", 2))
		m["target"] = null
		m["in_gap"] = true
		scenes.people.play(f, "SS_Block_Idle"))
	melee.call_on_update(func(dt: float): _melee(m, dt))
	melee.call_on_exit(func(): m["in_gap"] = false)
	inside.call_on_enter(func():
		m["cheered"] = false
		scenes.people.play(f, "Sprint"))
	inside.call_on_update(func(dt: float): _pour_in(m, dt))
	fight.call_on_enter(func():
		m["until"] = clock + r.randf_range(AT_WALL[0], AT_WALL[1])
		m["cool"] = 0.0)
	fight.call_on_update(func(dt: float): _fight(m, dt))
	back.call_on_enter(func(): scenes.people.play(f, "Walk" if not m.get("beaten", false) else "Injured_Walk"))
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
	hsm.add_transition(rush, melee, &"melee")
	hsm.add_transition(melee, back, &"back")
	hsm.add_transition(melee, inside, &"inside")
	hsm.add_transition(rush, inside, &"inside")
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
		if not _storm:
			_hold_the_gap()
		else:
			_morale()
	if _storm:
		_defend(dt)
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
			_held_at[key] = {"gap": gap, "inward": inward, "across": across, "men": _block(gap, inward, across, k),
				"reserve": int(k.get("reserve", 4)), "phase": "hold", "at": 0.0}
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
		out.append(_defender(p, inward, row == 0, p))
	return out


## One of the holder's men, standing at `at` and keeping `slot`, facing out.
func _defender(at: Vector3, inward: Vector3, front: bool, slot: Vector3) -> Dictionary:
	var f: Node3D = scenes.people.make(r, "soldier", held, "adult")
	f.position = _stand(at)
	f.rotation.y = atan2(-inward.x, -inward.z)
	root.add_child(f)
	scenes.arm(f, "sword")
	scenes.people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
	return {"node": f, "last": "", "cool": r.randf_range(0.0, 1.0), "front": front, "slot": slot, "alive": true,
		"hp": int(Data.num("walls", "assault.hp", 2)), "busy": 0.0, "target": null, "guarding": false}


## The front row of each block cuts and guards at the attackers in the gap; the
## rows behind brace (Sword_Idle) until a man ahead of them falls.
func _hold_the_gap() -> void:
	var near := []
	for p in parties:
		for m in p:
			if m["alive"] and m.get("gap", null) != null and is_instance_valid(m.get("node")):
				near.append(m["node"].position)
	for key in _held_at:
		for d in _held_at[key]["men"]:
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


# --- the storm (Stronghold, Total War: the fight is in the gap) ---------------

## Storming a breach: the storm is on and his party has turned to an open gap.
func _storming(m: Dictionary) -> bool:
	return _storm and m.has("gap") and _held_at.has(m["gap"])


## Where a man stands at `p` (the siege's frame): on the ground, or on the
## rubble a breach left where it lies higher (walls.gd rubble_height).
func _stand(p: Vector3) -> Vector3:
	var q: Vector3 = scenes.stand(p)
	if Engine.has_meta("stone_walls"):
		var w := root.global_transform * q
		var top: float = Engine.get_meta("stone_walls").rubble_height(w)
		if top > w.y:
			w.y = top
			q = root.global_transform.affine_inverse() * w
	return q


## An attacker in the gap: he takes on the nearest of the holder's men and
## fights him; with the gap taken, he goes in.
func _melee(m: Dictionary, dt: float) -> void:
	var st: Dictionary = _held_at[m["gap"]]
	if st["phase"] != "hold":
		m["hsm"].dispatch(&"inside")
		return
	var e = m["target"]
	if e == null or not e["alive"]:
		e = _nearest(m["node"].position, st["men"], 0.9)
		m["target"] = e
	if e == null:
		# None to fight yet: shield up in the gap, facing in.
		_turn(m["node"], st["inward"], dt)
		return
	_duel(m, e, dt, float(Data.num("walls", "assault.hit_in", 0.45)))


## The holder's men, each frame: the front fights whoever is in the gap, the
## rows behind hold their places; the back row steps up as the front falls, and
## fresh men come up from the town while any are left.
func _defend(dt: float) -> void:
	var k: Dictionary = Data.value("walls", "assault", {})
	for key in _held_at:
		var st: Dictionary = _held_at[key]
		if st["phase"] != "hold":
			continue
		var attackers := []
		for p in parties:
			for m in p:
				if m["alive"] and m.get("in_gap", false) and m.get("gap") == key:
					attackers.append(m)
		for d in st["men"]:
			if not d["alive"]:
				continue
			var n: Node3D = d["node"]
			if not is_instance_valid(n) or n.has_meta("dead"):
				d["alive"] = false
				continue
			var e = d["target"]
			if e == null or not e["alive"] or not e.get("in_gap", false):
				e = _nearest(n.position, attackers, 0.5 if d["front"] else 0.22)
				d["target"] = e
			if e != null:
				_duel(d, e, dt, float(k.get("hit_out", 0.5)))
				continue
			# Back to his place, facing out, guard up.
			var to: Vector3 = d["slot"] - n.position
			to.y = 0.0
			if to.length() > 0.02:
				n.position = _stand(n.position + to.normalized() * minf(WALK * dt, to.length()))
				if not d.get("walking", false):
					d["walking"] = true
					d["guarding"] = false
					scenes.people.play(n, "SS_Walk")
			else:
				if d.get("walking", false) or not d.get("guarding", false):
					d["walking"] = false
					d["guarding"] = true
					scenes.people.play(n, "SS_Block_Idle" if d["front"] else "Sword_Idle", r.randf_range(0.9, 1.1))
				_turn(n, -st["inward"], dt)


## Once a second: the side losing the gap falls back. A party that has lost
## assault.fall_back_at of its men there walks back to the camp (beaten); a
## block worn to assault.break_at of its men with none left to come breaks and
## runs into the town, and the gap is taken.
func _morale() -> void:
	var k: Dictionary = Data.value("walls", "assault", {})
	for key in _held_at:
		var st: Dictionary = _held_at[key]
		var men: Array = st["men"]
		var standing := men.filter(func(d): return d["alive"])
		if st["phase"] == "hold":
			# The back row steps up into a fallen front man's place.
			for d in men:
				if d["front"] and not d["alive"] and not d.get("filled", false):
					var up = _nearest(d["slot"], standing.filter(func(x): return not x["front"]), 9.0)
					if up != null:
						up["front"] = true
						up["slot"] = d["slot"]
						d["filled"] = true
			# Fresh men from the town into the gaps in the rows.
			var full := int(k.get("defenders", 8))
			while standing.size() < full and int(st["reserve"]) > 0:
				st["reserve"] = int(st["reserve"]) - 1
				var dead_slot: Dictionary = {}
				for d in men:
					if not d["alive"] and not d.get("refilled", false) and not d["front"]:
						dead_slot = d
						break
				var slot: Vector3 = dead_slot.get("slot", st["gap"] + st["inward"] * (float(k.get("back", 0.14)) + 0.2))
				if not dead_slot.is_empty():
					dead_slot["refilled"] = true
				var fresh := _defender(st["gap"] + st["inward"] * 1.2 + st["across"] * r.randf_range(-0.2, 0.2), st["inward"], false, slot)
				men.append(fresh)
				standing.append(fresh)
			if standing.size() <= ceili(full * float(k.get("break_at", 0.25))) and int(st["reserve"]) <= 0:
				st["phase"] = "broken"
				st["at"] = clock
				for d in standing:
					_rout(d, st["inward"])
		elif st["phase"] == "broken" and clock - float(st["at"]) > 1.5:
			st["phase"] = "taken"
	# A party beaten in the gap falls back to the camp.
	for p in parties:
		var there: Array = p.filter(func(m): return m.get("gap") != null and m.get("in_gap", false) and m["alive"])
		if there.is_empty():
			continue
		var lost: int = p.filter(func(m): return m.get("fell_in_gap", false)).size()
		if lost >= ceili(p.size() * float(k.get("fall_back_at", 0.5))):
			for m in p:
				m["fell_in_gap"] = false
				if m["alive"] and m.get("in_gap", false):
					m["beaten"] = true
					m["hsm"].dispatch(&"back")


## A beaten defender runs for the town and is gone.
func _rout(d: Dictionary, inward: Vector3) -> void:
	var n: Node3D = d["node"]
	d["alive"] = false  # out of the fight
	d["target"] = null
	scenes.people.play(n, "Sprint")
	n.rotation.y = atan2(inward.x, inward.z)
	var to: Vector3 = n.position + (inward + Vector3(-inward.z, 0, inward.x) * r.randf_range(-0.4, 0.4)).normalized() * 1.8
	var tw := n.create_tween()
	tw.tween_property(n, "position", _stand(to), 1.8 / RUN)
	tw.tween_callback(n.queue_free)


## The gap taken: in over the rubble to a spot inside, a cheer, and the town is
## put to the torch (once, a little after the first man is in).
func _pour_in(m: Dictionary, dt: float) -> void:
	var st: Dictionary = _held_at[m["gap"]]
	if not m.has("inside_at"):
		var k: Dictionary = Data.value("walls", "assault", {})
		m["inside_at"] = st["gap"] + st["inward"] * float(k.get("in", 0.9)) + st["across"] * r.randf_range(-0.35, 0.35)
	var n: Node3D = m["node"]
	var to: Vector3 = m["inside_at"] - n.position
	to.y = 0.0
	if to.length() > 0.03:
		n.position = _stand(n.position + to.normalized() * minf(RUN * dt, to.length()))
		_turn(n, to, dt)
		return
	if not m["cheered"]:
		m["cheered"] = true
		scenes.people.play(n, ["Cheering", "Sword_Idle", "Cheering"][r.randi() % 3], r.randf_range(0.9, 1.1))
		if not st.has("torched"):
			st["torched"] = true
			var t := get_tree().create_timer(float(Data.num("walls", "assault.torch_s", 3.0)))
			t.timeout.connect(_torch)


## The town put to the torch: its houses catch one after another (fire.gd, with
## --fire=v2), for assault.burn_s.
func _torch() -> void:
	if town_at == Vector3.INF:
		return
	Fire.ignite(town_at, float(Data.num("walls", "assault.burn_s", 90.0)), false)


## One man fights another: he closes to a sword's length, circles a little, and
## cuts when he's ready, never the same cut twice running; the other parries or
## takes it, reels, and falls at his last hit. `hit`: the chance a cut lands.
## The duels' own moves and reels (combat.gd), as battle_ai.gd fights its line.
func _duel(a: Dictionary, e: Dictionary, dt: float, hit: float) -> void:
	var n: Node3D = a["node"]
	var foe: Node3D = e["node"]
	if not is_instance_valid(n) or not is_instance_valid(foe):
		return
	var off: Vector3 = foe.position - n.position
	off.y = 0.0
	var gap := off.length()
	_turn(n, off, dt)
	if float(a.get("busy", 0.0)) > clock:
		return
	if gap > Combat.REACH * 1.3:
		var want: Vector3 = foe.position - off.normalized() * Combat.REACH
		n.position = _stand(n.position + (want - n.position).normalized() * minf(WALK * 1.2 * dt, (want - n.position).length()))
		if a.get("closing", false) == false:
			a["closing"] = true
			a["guarding"] = false
			scenes.people.play(n, "SS_Walk")
		return
	a["closing"] = false
	a["cool"] = float(a.get("cool", 0.0)) - dt
	if float(a["cool"]) > 0.0 or float(e.get("busy", 0.0)) > clock:
		if not a.get("guarding", false):
			a["guarding"] = true
			scenes.people.play(n, "SS_Block_Idle" if r.randf() < 0.5 else "Sword_Idle")
		return
	var moves: Array = Combat.KITS["sword"]["attacks"].filter(func(x): return x != a.get("last", ""))
	var move: String = moves[r.randi() % moves.size()]
	a["last"] = move
	a["guarding"] = false
	var length := _play(n, move, r.randf_range(1.0, 1.2))
	a["busy"] = clock + length
	a["cool"] = length + r.randf_range(0.4, 1.2)
	var t := n.create_tween()
	t.tween_interval(length * float(Combat.BLOW_AT.get(move, 0.45)))
	t.tween_callback(func(): _land(a, e, move, hit))


## A cut arrives: parried, or it lands; at his last hit he falls.
func _land(a: Dictionary, e: Dictionary, move: String, hit: float) -> void:
	if not a["alive"] or not e["alive"] or not is_instance_valid(e["node"]):
		return
	var n: Node3D = e["node"]
	if (n.position - a["node"].position).length() > Combat.REACH * 1.8:
		return
	if r.randf() >= hit:
		var parry: Array = Combat.KITS["sword"]["parry"]
		e["busy"] = clock + _play(n, parry[r.randi() % parry.size()], r.randf_range(1.0, 1.2)) * 0.8
		e["guarding"] = false
		return
	e["hp"] = int(e.get("hp", 1)) - 1
	if int(e["hp"]) <= 0:
		_down(e)
		return
	var where := "head" if move in Combat.OVERHEAD else "body"
	var reels: Array = Combat.REELS[where] + Combat.KITS["sword"]["hurt"]
	e["busy"] = clock + _play(n, reels[r.randi() % reels.size()], 1.0) * 0.85
	e["guarding"] = false
	var back: Vector3 = (n.position - a["node"].position).normalized()
	n.create_tween().tween_property(n, "position", _stand(n.position + back * 0.05), 0.35).set_trans(Tween.TRANS_SINE)


## Cut down in the gap: an attacker's mind goes to Dead (he is counted against
## his party); a defender falls where he stood.
func _down(x: Dictionary) -> void:
	if x.has("hsm"):
		x["fell_in_gap"] = true
		x["hsm"].dispatch(&"die")
		return
	x["alive"] = false
	if is_instance_valid(x["node"]) and not x["node"].has_meta("dead"):
		scenes.die(x["node"], scenes.DEATHS[r.randi() % scenes.DEATHS.size()], r)


func _nearest(at: Vector3, among: Array, within: float):
	var best = null
	var bd := within
	for x in among:
		if not x["alive"] or not is_instance_valid(x.get("node")):
			continue
		var d: float = Vector2(x["node"].position.x - at.x, x["node"].position.z - at.z).length()
		if d < bd:
			bd = d
			best = x
	return best


func _turn(n: Node3D, way: Vector3, dt: float) -> void:
	if Vector2(way.x, way.z).length() > 0.001:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(way.x, way.z), minf(1.0, dt * 6.0))


## Plays a move; how long it runs (1 s if the body hasn't it).
func _play(n: Node3D, move: String, speed := 1.0) -> float:
	scenes.people.play(n, move, speed)
	var mo: AnimationTree = scenes.people.motion(n)
	return (mo.get_animation(move).length / speed) if mo and mo.has_animation(move) else 1.0


## Walks or runs toward `to`; there, the next state.
func _go(m: Dictionary, to: Vector3, speed: float, dt: float, then: StringName) -> void:
	var n: Node3D = m["node"]
	var d := to - n.position
	d.y = 0
	if d.length() < 0.02:
		m["hsm"].dispatch(then)
		return
	n.position = _stand(n.position + d.normalized() * minf(speed * dt, d.length()))
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
