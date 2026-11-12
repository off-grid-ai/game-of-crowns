extends "res://scripts/army_melee.gd"
## A siege's assault parties, fought by the men in them (scenes.gd _siege stages the camp and the walls; the
## close fight is army_melee.gd's). Each man runs his own mind (data/army.json minds.assault_man, army_mind.gd):
## he waits in the camp, goes forward behind his shield when his party is sent, runs the last stretch, fights at
## the foot of the wall (a cut, a guard, another cut, each different), and falls back to the camp; or he is cut
## down there and stays down, and the camp sends a fresh man in his place for the next rush. Every step through
## the Mover, on the siege's own ground (army_ground.gd: round the houses, never through the wall but at a breach).
##
## The breach changes the fight (docs/research/world-and-siege-rules.md, wall rule 12; Total War: Warhammer III's
## lesson that a gap nobody reacts to doesn't read): once a stone wall near the front stands open (walls.gd
## breaches_near; the wall's wear is the bridge's damage fact), every party is sent at once and from then on
## through the gap, fanned across it, over the rubble ramp; the gap's cells open on the ground; and the holder's
## men form a block behind it, facing out (minds.gap_holder), cutting and guarding at whoever comes through.
## Knobs: data/walls.json assault.
##
## The storm (switch: --storm=on, on with --wall-demo, or walls.json assault.storm; Stronghold's and Total War's
## assault through the gap): the fight happens in the gap. Each man pairs off with a man of the other side and
## fights him in the close fight's duel until one falls; the holder's back row steps up as the front falls, and a
## few fresh men come up from the town. A party that loses half of its men in the gap walks back to the camp and
## the next wave comes; a block worn down to a few with none left to come breaks and runs into the town. Then the
## besiegers pour in over the rubble, cheer, and put the town to the torch (fire.gd). Behind them, the massed
## storm of regiments (army_field.gd's storm) follows this breach.

const WAVE := 15.0  # seconds between one party's rushes
const AT_WALL := [3.0, 4.6]  # how long a man fights at the foot of the wall
const FALL := 0.06  # the chance a blow from above, landing, kills him outright
const WALK_S := 0.17  # a man's walk at the wall, units a second
const RUN_S := 0.45
const Fire := preload("res://scripts/fire.gd")
const Field := preload("res://scripts/army_field.gd")

var col: Color
var parties := []  # arrays of men: {home, foot, node, hsm, alive, out, ...}
var held := Color(0.6, 0.6, 0.6)  # the holder's colours: the block behind a breach
var town_at := Vector3.INF  # the besieged town (world): where the torch goes once it falls
var _held_at := {}  # breach key -> {gap, inward, across, men: [defenders], reserve, phase, at}
var _look := 0.0
var _storm := false


## The storm through the breach on for this run? --storm=on/off, on with the wall demo, else walls.json
## assault.storm.
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
	reach = Combat.REACH
	_storm = storm_on()
	parties = groups
	root.add_child(self)
	var camp := Vector3.ZERO
	var wall := Vector3.ZERO
	var n := 0
	for p in parties:
		for m in p:
			camp += m["home"]
			wall += m["foot"]
			n += 1
	camp /= maxf(n, 1)
	wall /= maxf(n, 1)
	var heart: Vector3 = town_at if town_at != Vector3.INF else wall + (wall - camp)
	_field(heart, Vector2(camp.x - heart.x, camp.z - heart.z).length() + 1.5)
	for p in parties.size():
		for m in parties[p]:
			_man(m)
		# Each party's first rush at its own time, then every WAVE seconds.
		var t := Timer.new()
		t.wait_time = WAVE
		t.timeout.connect(_send_party.bind(p))
		add_child(t)
		get_tree().create_timer(first[p]).timeout.connect(func():
			if is_instance_valid(t):
				_send_party(p)
				t.start())
	# The storm as a mass: hundreds in their houses' colours behind these men (army_field.gd), driven by this
	# one's breach.
	if _storm and Field.storm_host_on() and not parties.is_empty():
		var out := Vector3(camp.x - heart.x, 0, camp.z - heart.z).normalized()
		Field.storm(self, camp + out * Data.num("siege", "storm_host.camp_back", 0.3), wall, heart, col, held)


## A fresh man in the camp, and his mind (the fallen man's stops: his body stays where it fell).
func _man(m: Dictionary) -> void:
	Mind.stop(m)
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
	_enlist(m, "assault_man")
	Mover.of(f).ground = _height


## A party is sent: the fallen are replaced from the camp, and each man goes forward on his own beat.
## No camera move on a rush (camera never steals): the siege shows from wherever the King looks.
func _send_party(p: int) -> void:
	for m in parties[p]:
		if not m["alive"]:
			_man(m)
		get_tree().create_timer(r.randf_range(0.0, 0.8)).timeout.connect(func():
			if m["alive"]:
				_send(m, &"go"))


func _process(dt: float) -> void:
	super(dt)
	_look -= dt
	if _look <= 0.0:
		_look = 1.0
		_watch_breaches()
		if _storm:
			_morale()
	# Felled by an arrow from the walls (scenes._arrows): once he has fallen, his mind goes to its fall too.
	for p in parties:
		for m in p:
			if not m["alive"] and not m.get("down", false) and is_instance_valid(m.get("node")) and m["node"].has_meta("dead"):
				_send(m, &"die")


## Where a man stands at a point (world): on the ground, or on the rubble a breach left where it lies higher
## (walls.gd rubble_height).
func _height(p: Vector3) -> float:
	var y: float = scenes.terrain.height_at(p.x, p.z)
	if Engine.has_meta("stone_walls"):
		y = maxf(y, Engine.get_meta("stone_walls").rubble_height(p))
	return y


# --- An attacker's mind (data/army.json minds.assault_man) ------------------------------------------------

func _camp_in(m: Dictionary) -> void:
	m["out"] = false
	m["beaten"] = false
	var face: Vector3 = (m["foot"] - m["home"]).normalized()
	m["node"].rotation.y = atan2(face.x, face.z)
	scenes.people.play(m["node"], "Sword_Idle")


func _advance_in(m: Dictionary) -> void:
	m["out"] = true
	m["half"] = m["home"].lerp(m["foot"], 0.55)
	scenes.people.play(m["node"], "SS_Walk")  # on behind raised shields


func _advance(m: Dictionary, _dt: float) -> void:
	_go(m, m["half"], WALK_S, &"rush")


func _rush_in(m: Dictionary) -> void:
	scenes.people.play(m["node"], "Sprint")


func _rush(m: Dictionary, _dt: float) -> void:
	_go(m, m["foot"], RUN_S, &"melee" if _storming(m) else &"fight")


func _wall_in(m: Dictionary) -> void:
	m["until"] = clock + r.randf_range(AT_WALL[0], AT_WALL[1])
	m["cool"] = 0.0


## At the foot of the wall: a cut, a guard, another cut, never the same twice running; what comes down from
## above may kill him.
func _at_wall(m: Dictionary, dt: float) -> void:
	if not is_instance_valid(m.get("node")):
		return
	var n: Node3D = m["node"]
	_turn(n, m["foot"] - m["home"], dt)
	if clock > m["until"]:
		_send(m, &"back")
		return
	m["cool"] -= dt
	if m["cool"] > 0.0:
		return
	var move: String = scenes.cut(r, m["last"]) if r.randf() < 0.6 else scenes.guard(r)
	m["last"] = move
	var length := _play(m, move, r.randf_range(0.95, 1.15))
	m["cool"] = length + r.randf_range(0.2, 0.6)
	if r.randf() < FALL:
		get_tree().create_timer(length * 0.5).timeout.connect(func():
			if m["alive"]:
				_send(m, &"die"))


func _back_in(m: Dictionary) -> void:
	scenes.people.play(m["node"], "Walk" if not m.get("beaten", false) else "Injured_Walk")


func _back(m: Dictionary, _dt: float) -> void:
	_go(m, m["home"], WALK_S, &"camp")


func _melee_in(m: Dictionary) -> void:
	m["cool"] = r.randf_range(0.1, 0.6)
	m["busy"] = 0.0
	m["hp"] = int(Data.num("walls", "assault.hp", 2))
	m["target"] = null
	m["in_gap"] = true
	scenes.people.play(m["node"], "SS_Block_Idle")


func _melee_out(m: Dictionary) -> void:
	m["in_gap"] = false


## An attacker in the gap: he takes on the nearest of the holder's men and fights him; with the gap taken, he
## goes in.
func _melee(m: Dictionary, dt: float) -> void:
	if not is_instance_valid(m.get("node")):
		return
	var st: Dictionary = _held_at[m["gap"]]
	if st["phase"] != "hold":
		_send(m, &"inside")
		return
	var e = m["target"]
	if e == null or not e["alive"]:
		e = _nearest(m["node"].global_position, st["men"], 0.9)
		m["target"] = e
	if e == null:
		_turn(m["node"], st["inward"], dt)  # none to fight yet: shield up in the gap, facing in
		return
	_duel(m, e, dt, float(Data.num("walls", "assault.hit_in", 0.45)))


func _inside_in(m: Dictionary) -> void:
	m["cheered"] = false
	scenes.people.play(m["node"], "Sprint")


## The gap taken: in over the rubble to a spot inside, a cheer, and the town is put to the torch (once, a little
## after the first man is in).
func _pour_in(m: Dictionary, _dt: float) -> void:
	var st: Dictionary = _held_at[m["gap"]]
	if not m.has("inside_at"):
		m["inside_at"] = st["gap"] + st["inward"] * float(Data.num("walls", "assault.in", 0.9)) + st["across"] * r.randf_range(-0.35, 0.35)
	if not is_instance_valid(m.get("node")):
		return
	var n: Node3D = m["node"]
	if Vector2(m["inside_at"].x - n.global_position.x, m["inside_at"].z - n.global_position.z).length() > 0.03:
		_steer(m, m["inside_at"], RUN_S)
		return
	if not m["cheered"]:
		m["cheered"] = true
		_play(m, ["Cheering", "Sword_Idle", "Cheering"][r.randi() % 3], r.randf_range(0.9, 1.1))
		if not st.has("torched"):
			st["torched"] = true
			get_tree().create_timer(float(Data.num("walls", "assault.torch_s", 3.0))).timeout.connect(_torch)


func _not_down(m: Dictionary) -> bool:
	return not m.get("down", false)


## Cut down: he stays down. Nothing leads out of it.
func _down_in(m: Dictionary) -> void:
	m["down"] = true
	m["alive"] = false
	m["out"] = false
	_fall_body(m)


## Cut down in the gap: counted against his party (a defender just falls).
func _kill(m: Dictionary, back := true) -> void:
	if m.has("home"):
		m["fell_in_gap"] = true
	super(m, back)


## Walks or runs toward `to`; there, the next state.
func _go(m: Dictionary, to: Vector3, speed: float, then: StringName) -> void:
	var body = m.get("node")
	if not is_instance_valid(body):
		return  # his body was cleared away: nothing to move
	var n: Node3D = body
	if Vector2(to.x - n.global_position.x, to.z - n.global_position.z).length() < 0.02:
		_send(m, then)
		return
	_steer(m, to, speed)


# --- The breach (wall rule 12) -----------------------------------------------------------------------------

## Once a second: a breach newly open near a party's stretch of wall turns the party to it (and sends it at once),
## opens the gap on the ground, and raises the block that holds it.
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
		var found: Array = walls.breaches_near(foot, float(k.get("reach", 2.5)))
		if found.is_empty():
			continue
		var gap: Vector3 = found[0]
		var key := Vector3i(roundi(gap.x * 10.0), 0, roundi(gap.z * 10.0))
		var inward: Vector3 = gap - home
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
			ground.open(gap, float(k.get("spread", 0.16)) + 0.15)  # the gap stands open on the ground
			_held_at[key] = {"gap": gap, "inward": inward, "across": across, "men": [], "reserve": int(k.get("reserve", 4)), "phase": "hold", "at": 0.0}
			_block(_held_at[key], k)
		if fresh:
			_send_party(p)  # the gap is open: the party goes now, not at its next turn


## The holder's men behind a breach: a block in rows, facing out at it.
func _block(st: Dictionary, k: Dictionary) -> void:
	var n := int(k.get("defenders", 8))
	var rows := maxi(1, int(k.get("rows", 2)))
	var per := ceili(float(n) / rows)
	for i in n:
		var row := i / per
		var col_i := i % per
		var p: Vector3 = st["gap"] + st["inward"] * (float(k.get("back", 0.28)) + row * 0.1) + st["across"] * ((col_i - (per - 1) * 0.5) * 0.09)
		st["men"].append(_defender(st, p, row == 0, p))


## One of the holder's men, standing at `at` and keeping `slot`, facing out, and his mind.
func _defender(st: Dictionary, at: Vector3, front: bool, slot: Vector3) -> Dictionary:
	var f: Node3D = scenes.people.make(r, "soldier", held, "adult")
	f.position = scenes.stand(at)
	f.rotation.y = atan2(-st["inward"].x, -st["inward"].z)
	root.add_child(f)
	scenes.arm(f, "sword")
	scenes.people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
	var d := {"node": f, "last": "", "cool": r.randf_range(0.0, 1.0), "front": front, "slot": slot, "alive": true,
		"hp": int(Data.num("walls", "assault.hp", 2)), "busy": 0.0, "target": null, "guarding": false, "held": st}
	_enlist(d, "gap_holder")
	Mover.of(f).ground = _height
	return d


# --- A holder's mind (data/army.json minds.gap_holder) -------------------------------------------------

## Behind the gap. In the storm the front fights whoever is in the gap and the rows behind hold their places;
## without it the front cuts and guards at the attackers who come near, the rows behind brace.
func _holder(d: Dictionary, dt: float) -> void:
	var n = d.get("node")
	if not is_instance_valid(n) or (n as Node3D).has_meta("dead"):
		d["alive"] = false
		return
	var st: Dictionary = d["held"]
	if not _storm:
		_brace(d, n, dt)
		return
	if st["phase"] != "hold":
		return
	var e = d["target"]
	if e == null or not e["alive"] or not e.get("in_gap", false):
		e = _nearest(n.global_position, _in_gap(st), 0.5 if d["front"] else 0.22)
		d["target"] = e
	if e != null:
		_duel(d, e, dt, float(Data.num("walls", "assault.hit_out", 0.5)))
		return
	# Back to his place, facing out, guard up.
	if Vector2(d["slot"].x - n.global_position.x, d["slot"].z - n.global_position.z).length() > 0.02:
		_steer(d, d["slot"], WALK_S)
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


## Without the storm: the front row cuts and guards at the attackers in the gap; the rows behind brace until a
## man ahead of them falls.
func _brace(d: Dictionary, n: Node3D, dt: float) -> void:
	d["cool"] = float(d["cool"]) - dt
	if float(d["cool"]) > 0.0:
		return
	d["cool"] = 0.0
	var close := false
	for p in parties:
		for m in p:
			if m["alive"] and m.get("gap", null) != null and is_instance_valid(m.get("node")) and _gap(m["node"], n) < 0.4:
				close = true
	if not close:
		d["cool"] = 1.0
		return
	var move: String = scenes.cut(r, d["last"]) if (d["front"] and r.randf() < 0.6) else scenes.guard(r)
	d["last"] = move
	d["cool"] = _play(d, move, r.randf_range(0.95, 1.15)) + r.randf_range(0.2, 0.8)


## A beaten holder runs for the town and is gone.
func _rout_in(d: Dictionary) -> void:
	var n = d.get("node")
	d["alive"] = false  # out of the fight
	d["target"] = null
	if not is_instance_valid(n):
		return
	var inward: Vector3 = d["held"]["inward"]
	scenes.people.play(n, "Sprint")
	n.rotation.y = atan2(inward.x, inward.z)
	var to: Vector3 = (n as Node3D).global_position + (inward + Vector3(-inward.z, 0, inward.x) * r.randf_range(-0.4, 0.4)).normalized() * 1.8
	var mo: Node = Mover.of(n)
	mo.speed = RUN_S
	mo.go(ground.keep_out(to), (n as Node).queue_free)


func _holder_down(d: Dictionary) -> void:
	d["alive"] = false
	_fall_body(d)


# --- The storm: who's winning the gap ------------------------------------------------------------------

## Storming a breach: the storm is on and his party has turned to an open gap.
func _storming(m: Dictionary) -> bool:
	return _storm and m.has("gap") and _held_at.has(m["gap"])


func _in_gap(st: Dictionary) -> Array:
	var out := []
	for p in parties:
		for m in p:
			if m["alive"] and m.get("in_gap", false) and is_same(_held_at.get(m.get("gap")), st):
				out.append(m)
	return out


## Once a second: the side losing the gap falls back. A party that has lost assault.fall_back_at of its men there
## walks back to the camp (beaten); a block worn to assault.break_at of its men with none left to come breaks and
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
				var fresh := _defender(st, st["gap"] + st["inward"] * 1.2 + st["across"] * r.randf_range(-0.2, 0.2), false, slot)
				men.append(fresh)
				standing.append(fresh)
			if standing.size() <= ceili(full * float(k.get("break_at", 0.25))) and int(st["reserve"]) <= 0:
				st["phase"] = "broken"
				st["at"] = clock
				for d in standing:
					_send(d, &"rout")
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
					_send(m, &"back")


## The gap the storm is fought at (the first breach opened), or {} while the wall stands.
func breach() -> Dictionary:
	for key in _held_at:
		return _held_at[key]
	return {}


## The town put to the torch: its houses catch one after another (fire.gd, with --fire=v2), for assault.burn_s.
func _torch() -> void:
	if town_at == Vector3.INF:
		return
	Fire.ignite(town_at, float(Data.num("walls", "assault.burn_s", 90.0)), false)
