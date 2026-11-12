extends "res://scripts/army_melee.gd"
## A battle on the field fought by its men (the small battle, scenes.gd _battle stages it; the massed one is
## army_field.gd's). Every soldier and knight runs his own mind (data/army.json minds line_soldier and knight,
## army_mind.gd): soldiers wait in rank, advance, close and trade blows (army_melee.gd's duel), recoil, fall or
## break and run; knights walk up, charge the open end of the wall, ride through, wheel round and charge again.
## The fight's outcome is the realm's (team 0 is the beaten side), but how it goes on the field comes from the
## men in it. Every step through the Mover, on the field's own ground.

static var HP := int(Data.num("battle", "hp", 2))
static var HIT := [Data.num("battle", "hit.beaten", 0.22), Data.num("battle", "hit.victors", 0.5)]  # a blow's chance to land, beaten side and victors
static var BREAK := Data.num("battle", "breakAt", 0.55)  # the beaten side runs when this share of it is left
static var LONGEST := Data.num("battle", "longest", 18.0)  # or after this long at blows, whatever is left
static var RIDE := Data.num("battle", "charge.ride", 0.85)  # a knight's charge (Horse.GALLOP is 0.9)
static var PASSES := int(Data.num("battle", "charge.passes", 3))
const ROW := 0.2
const SPAN := 7.0  # the field's ground reaches this far round the clash: the lines, the knights' wing, the rout

var at: Vector3
var dir: Vector3  # the victors (team 1) advance along +dir
var side: Vector3
var view_yaw: float
var men := []  # one Dictionary per soldier
var knights := []
var bearers := []
var clash := -1.0  # when the lines met
var routed := false
var routed_at := 0.0
var _frame_t := 0.0
var _volley_t := 0.0


func start(s: Node, battle: Node3D, rng: RandomNumberGenerator, centre: Vector3, d: Vector3, sd: Vector3, yaw: float, teams: Array, horses: Array, standards: Array) -> void:
	scenes = s
	root = battle
	r = rng
	at = centre
	dir = d
	side = sd
	view_yaw = yaw
	bearers = standards
	reach = 0.2
	root.add_child(self)
	_field(at, SPAN)
	for b in standards:
		var bn: Node3D = b["node"]
		bn.set_meta("driven", true)
		for carried in [bn, b["flag"]]:
			var mo: Node = Mover.of(carried).on(ground)
			mo.clip = ""
	for t in 2:
		for m in teams[t]:
			if m["kit"] == "bow":
				scenes.people.motion(m["node"]).set_ready("Bow_Idle")  # an archer rests with his bow
			m["team"] = t
			m["hp"] = HP
			m["target"] = null
			m["cool"] = r.randf_range(0.2, 0.9)
			men.append(m)
			_enlist(m, "line_soldier")
	knights = horses
	for i in knights.size():
		var k: Dictionary = knights[i]
		k["i"] = i
		k["passes"] = 0
		var mo: Node = Mover.of(k["node"]).on(ground)
		mo.clip = ""  # the horse's gait follows how it is moved
		Mind.make("knight", k, k["node"], self)


func _process(dt: float) -> void:
	super(dt)
	# The field afterwards: the fallen stay a minute, then the battle is gone.
	if routed and clock - routed_at > 65.0:
		root.queue_free()
		return
	# The order of battle: formed up, the captain's shout, the advance under the archers' arrows, then every man
	# for himself.
	if clock > 0.8 and not root.has_meta("shouted"):
		root.set_meta("shouted", true)
		var captain = _middle(1)
		if captain:
			_play(captain, "Battlecry")
		for m in men:
			if m["team"] == 1 and not is_same(m, captain) and r.randf() < 0.3:
				_play(m, "Battlecry" if r.randf() < 0.5 else "Yelling", r.randf_range(0.9, 1.1))
	if clock > 3.0 and not root.has_meta("advanced"):
		root.set_meta("advanced", true)
		for m in men:
			if m["team"] == 1 and m["alive"]:
				_send(m, &"advance")
	if clash < 0.0:
		_volley_t -= dt
		if clock > 3.5 and _volley_t <= 0.0:
			_volley_t = 1.8
			if not _side(1).is_empty():
				scenes._arrows(root, _side(0), _side(1), r)
	for m in men:
		# Felled by an arrow (scenes._arrows): his mind goes to its fall once the arrow has landed and he has
		# fallen, not before.
		if not m["alive"] and not m.get("out", false) and m["node"].has_meta("dead"):
			_send(m, &"die")
	_promote()
	_bearers()
	_morale()
	_frame(dt)


# --- A soldier's mind (data/army.json minds.line_soldier) ------------------------------------------------

func _still_in(m: Dictionary) -> bool:
	return m["alive"] and not m.get("out", false)


func _not_out(m: Dictionary) -> bool:
	return not m.get("out", false)


func _dead_in(m: Dictionary) -> void:
	m["out"] = true
	m["alive"] = false
	_fall_body(m)


func _yield_in(m: Dictionary) -> void:
	m["out"] = true
	Mover.of(m["node"]).stop()
	_play(m, "Defeated")


func _gone_in(m: Dictionary) -> void:
	m["out"] = true
	m["alive"] = false
	Mover.of(m["node"]).stop()
	m["node"].visible = false


func _fight_in(m: Dictionary) -> void:
	m["fighting"] = true


func _fight_out(m: Dictionary) -> void:
	m["fighting"] = false


func _hold_in(m: Dictionary) -> void:
	_play(m, "Bow_Idle" if m["kit"] == "bow" else "Sword_Idle")


func _advance_in(m: Dictionary) -> void:
	_play(m, "Walk")


func _run_in(m: Dictionary) -> void:
	_play(m, "Sprint", r.randf_range(1.0, 1.2))


func _cheer_in(m: Dictionary) -> void:
	_play(m, ["Cheering", "Battlecry", "Yelling"][r.randi() % 3])


## Stand in rank; the front of the wall takes on whoever comes within reach. Stepping up into a gap is a walk,
## not a glide.
func _hold(m: Dictionary, dt: float) -> void:
	var n: Node3D = m["node"]
	var off: float = Vector2(m["slot"].x - n.global_position.x, m["slot"].z - n.global_position.z).length()
	if off > 0.05 and not m.get("stepping", false):
		m["stepping"] = true
		_play(m, "SS_Walk")
	elif off < 0.02 and m.get("stepping", false):
		m["stepping"] = false
		_play(m, "SS_Block_Idle" if m["kit"] != "bow" else "Bow_Idle")
	_steer(m, m["slot"], WALK * 0.6, m["face"])
	if m["rank"] == 0:
		var e = _nearest(n.global_position, _foes(m), reach * 2.2, m, men)
		if e:
			m["target"] = e
			_send(m, &"fight")
	elif m["kit"] != "bow" and clash >= 0.0 and _join(m):
		return
	elif m["kit"] != "bow" and clash >= 0.0:
		m["cool"] -= dt
		if m["cool"] <= 0.0:
			# The ranks behind lean in, shields up, spears over shoulders.
			m["cool"] = r.randf_range(1.2, 2.4)
			var roll := r.randf()
			var clip := "SS_Block_Idle" if roll < 0.45 else ("Sword_Idle" if roll < 0.8 else ("Battlecry" if roll < 0.9 else "Yelling"))
			if m["kit"] == "spear":
				clip = "Spear_Thrust" if roll < 0.5 else "Sword_Idle"
			_play(m, clip, r.randf_range(0.85, 1.1))
	if m["kit"] == "bow" and clash >= 0.0 and m["rank"] == 0:
		m["kit"] = "sword"


## A man of the ranks behind, on his own count after the lines meet, pushes into the fight: he picks a foe nobody
## else is on yet (or the one fewest are on) and goes for him. Returns whether he went.
func _join(m: Dictionary) -> bool:
	if not m.has("join_at"):
		m["join_at"] = clash + r.randf_range(1.0, 7.0) + m["rank"] * 1.5
	if clock < m["join_at"]:
		return false
	var best = null
	var bd := INF
	for o in _foes(m):
		if not o["alive"] or o.get("out", false):
			continue
		var on := men.filter(func(x): return x["alive"] and is_same(x["target"], o)).size()
		var d := _gap(m["node"], o["node"]) + on * 0.6
		if d < bd:
			bd = d
			best = o
	if best == null:
		return false
	m["target"] = best
	_send(m, &"fight")
	return true


## On toward the wall at a walk, breaking into a run for the last stretch; the ranks behind keep their place
## behind their file's front man.
func _advance(m: Dictionary, _dt: float) -> void:
	var n: Node3D = m["node"]
	var e = _nearest(n.global_position, _foes(m), 99.0, m, men)
	if e == null:
		return
	var gap: float = _gap(n, e["node"])
	if m["rank"] == 0:
		if gap < reach * 1.3:
			m["target"] = e
			if clash < 0.0:
				_clash()
			_send(m, &"fight")
			return
		var fast := gap < 0.55
		if fast and not m.get("running", false):
			m["running"] = true
			_play(m, "Sprint", r.randf_range(1.0, 1.15))
		_steer(m, e["node"].global_position, RUN if fast else WALK)
		return
	var lead = _file_front(m)
	var goal: Vector3 = (lead["node"].global_position if lead else m["slot"]) - m["face"] * ROW * (m["rank"] - (lead["rank"] if lead else 0))
	_steer(m, goal, RUN if m.get("running", false) or (lead and lead.get("running", false)) else WALK, m["face"])
	if lead and lead.get("running", false) and not m.get("running", false):
		m["running"] = true
		_play(m, "Sprint", r.randf_range(1.0, 1.15))
	if clash >= 0.0 and gap < reach * 1.3:
		m["target"] = e
		_send(m, &"fight")
	elif clash >= 0.0:
		_join(m)


## At blows: his man, else the next (the victors go looking across the field, the beaten take on whoever comes
## near); the duel itself is the close fight's (army_melee.gd).
func _fight(m: Dictionary, dt: float) -> void:
	var e = m["target"]
	if e == null or not e["alive"]:
		e = _nearest(m["node"].global_position, _foes(m), 99.0 if m["team"] == 1 else 1.0, m, men)
		m["target"] = e
		if e == null:
			if m["team"] == 0:
				_send(m, &"hold")
			return
	_duel(m, e, dt, float(HIT[m["team"]]))


## Running from the victors (the beaten stand on the +dir side), over the rise and out of the fight.
func _run(m: Dictionary, dt: float) -> void:
	var n: Node3D = m["node"]
	if not m.has("away"):
		m["away"] = (dir + side * r.randf_range(-0.7, 0.7)).normalized()
		m["gone"] = r.randf_range(5.0, 7.0)
	_steer(m, n.global_position + m["away"] * 0.5, RUN * 1.1, m["away"])
	m["gone"] -= dt
	if m["gone"] <= 0.0:
		_send(m, &"gone")


## A few paces after the beaten, then cheer under the standard, then rest.
func _cheer(m: Dictionary, dt: float) -> void:
	m["cool"] -= dt
	if not m.has("chase"):
		m["chase"] = r.randf_range(0.6, 1.8) if m["rank"] == 0 and r.randf() < 0.6 else 0.0
		m["cool"] = r.randf_range(4.0, 6.0)
		if m["chase"] > 0.0:
			_play(m, "Sprint", 1.0)
	if m["chase"] > 0.0:
		m["chase"] -= dt
		_steer(m, m["node"].global_position + dir * 0.5, RUN * 0.6, dir)
		if m["chase"] <= 0.0:
			_play(m, ["Cheering", "Battlecry", "Yelling"][r.randi() % 3])
	elif m["cool"] <= 0.0 and m["cool"] > -1.0:
		m["cool"] = -2.0
		_play(m, "Sword_Idle")


## Fills a gap: when the front man of a file falls, the next man of his file steps up to the front.
func _promote() -> void:
	for m in men:
		if not m["alive"] or m["rank"] == 0:
			continue
		var ahead := men.filter(func(o): return o["alive"] and o["team"] == m["team"] and o["file"] == m["file"] and o["rank"] < m["rank"])
		if ahead.is_empty():
			m["rank"] = 0
			m["slot"] = m["slot"] + m["face"] * ROW * 0.5
			if clash >= 0.0 and not routed:
				m["target"] = _nearest(m["node"].global_position, _foes(m), 99.0, m, men)
				_send(m, &"fight")


# --- A knight's mind (data/army.json minds.knight) -------------------------------------------------------

## Up at a walk behind the line during the advance, then hold for the horn.
func _knight_wait(k: Dictionary, dt: float) -> void:
	if clock < 3.0:
		return
	var h: Node3D = k["node"]
	var poised: Vector3 = k["wing"] - dir * (reach + 3 * ROW + 0.4)
	if Vector2(poised.x - h.global_position.x, poised.z - h.global_position.z).length() > 0.02:
		Mover.of(h).toward(poised, 0.18)
	if clash >= 0.0 and clock > clash + 0.6 + k["i"] * 0.15:
		if k["i"] == 0 and not k.get("reared", false):
			k["reared"] = true
			h.rear()
			k["delay"] = 1.2
		k["delay"] = k.get("delay", 0.0) - dt
		if k["delay"] <= 0.0:
			_send(k, &"charge")


## Out wide past the wall's end, wheel in onto its flank, and ride on through.
func _plan_charge(k: Dictionary) -> void:
	var h: Node3D = k["node"]
	var i: int = k["i"]
	var wall := _side(0)
	var end := at + dir * (reach + ROW) + side * (4.5 * 0.2 + 0.1)
	if not wall.is_empty():
		# The open end of whatever is left of the wall, on the knights' side.
		var best := -INF
		for m in wall:
			var s: float = (m["node"].global_position - at).dot(side)
			if s > best:
				best = s
				end = m["node"].global_position
	var wide: Vector3 = end + side * (0.55 + (i % 2) * 0.15) - dir * 0.2
	var into: Vector3 = end - side * (0.1 + (i / 2) * 0.12) + dir * ((i % 2) * 0.14)
	var through: Vector3 = into - side * 0.7 + dir * 0.2
	var c := Curve3D.new()
	c.add_point(h.global_position)
	c.add_point(wide, (h.global_position - wide) * 0.4, (into - wide) * 0.35)
	c.add_point(into, (wide - into) * 0.3, (through - into) * 0.3)
	c.add_point(through)
	k["rode"] = []
	k["passes"] += 1
	_ride(k, c, true)


## Round in a wide loop at a canter, back out past the wing for another go.
func _plan_wheel(k: Dictionary) -> void:
	var h: Node3D = k["node"]
	var out: Vector3 = h.global_position - side * 0.3 - dir * 0.8
	var back: Vector3 = at + side * (1.6 + k["i"] * 0.12) - dir * (0.9 + (k["i"] % 2) * 0.2)
	var c := Curve3D.new()
	c.add_point(h.global_position)
	c.add_point(out, (h.global_position - out) * 0.5, (back - out) * 0.4)
	c.add_point(back)
	_ride(k, c, false)


## The horse rides the curve's way (the Mover follows it on the ground); at its end the next pass.
func _ride(k: Dictionary, c: Curve3D, charging: bool) -> void:
	k["along"] = 0.0
	k["charging"] = charging
	c.bake_interval = 0.05
	Mover.of(k["node"]).follow(c.get_baked_points(), func():
		if not k["alive"]:
			return
		if charging:
			_send(k, &"wheel")
		elif k["passes"] < PASSES and not routed:
			_send(k, &"charge"))


## Off at a canter, into the gallop; men in the horse's path are ridden down, and a horse may be brought down in
## the press.
func _knight_charge(k: Dictionary, dt: float) -> void:
	_pace(k, dt, RIDE)
	if not k["alive"]:
		return
	var h: Node3D = k["node"]
	for m in men:
		if m["alive"] and m["team"] == 0 and not k["rode"].has(m["node"]) and _gap(h, m["node"]) < 0.12:
			k["rode"].append(m["node"])
			if r.randf() < 0.55:
				_kill(m)
			else:
				_play(m, ["Body_Big_2", "Side_Big", "Kidney_Big"][r.randi() % 3], 1.0)
			if k["i"] % 3 == 1 and k["passes"] == 1 and r.randf() < 0.3:
				_send(k, &"die")
				return


func _knight_wheel(k: Dictionary, dt: float) -> void:
	_pace(k, dt, 0.5)


## The horse's pace on its ride: from a canter into the full pace over its first lengths.
func _pace(k: Dictionary, dt: float, pace: float) -> void:
	var speed := pace * clampf(0.45 + float(k["along"]) / 0.8, 0.45, 1.0)
	k["along"] = float(k["along"]) + speed * dt
	var mo: Node = Mover.of(k["node"])
	mo.speed = speed


func _unhorse(k: Dictionary) -> void:
	var h: Node3D = k["node"]
	k["alive"] = false
	Mover.of(h).stop()
	h.fall()
	scenes._lie_clear(h, 0.17, scenes.HORSE_BODY)
	var thrown: Node3D = h.dismount()
	if thrown:
		var fwd := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
		thrown.global_position = scenes.stand(h.global_position + fwd * 0.25)  # thrown from the saddle, not a walk
		scenes.die(thrown, "Death_Front", r)


## After the beaten at a canter, out past the field, easing to a walk and a halt there, clear of the men cheering
## behind.
func _knight_rein(k: Dictionary, dt: float) -> void:
	if not k["alive"]:
		return
	var h: Node3D = k["node"]
	if not k.has("chase"):
		k["chase"] = (dir + side * r.randf_range(-0.4, 0.4)).normalized()
		k["rein"] = r.randf_range(4.5, 6.0)
		var mo: Node = Mover.of(h)
		mo.turn_rate = 2.5
	k["rein"] -= dt
	if k["rein"] > 0.0:
		Mover.of(h).toward(h.global_position + k["chase"] * 0.5, 0.6 * clampf(k["rein"] / 3.0, 0.15, 1.0))


# --- The whole field ---------------------------------------------------------------------------------------

func _clash() -> void:
	clash = clock
	scenes.dust(root, scenes.ground(at) + Vector3(0, 0.01, 0), side, 9 * 0.2)
	scenes.framing.emit(scenes.ground(at), 2.8, view_yaw)


## The beaten side breaks when too few are left or the fight has gone on too long: their standard goes down and
## they run; the victors cheer.
func _morale() -> void:
	if routed or clash < 0.0:
		return
	var left := _side(0).size()
	var total := men.filter(func(m): return m["team"] == 0).size()
	if float(left) / maxf(1.0, total) > BREAK and clock - clash < LONGEST:
		return
	routed = true
	routed_at = clock
	if bearers.size() > 0 and is_instance_valid(bearers[0]["node"]):
		Mover.of(bearers[0]["node"]).stop()
		scenes.die(bearers[0]["node"], "Death_Back", r)
		scenes.drop_banner(bearers[0]["flag"], bearers[0]["face"])
	for m in men:
		if not m["alive"]:
			continue
		if m["team"] == 0 and m["hp"] < HP and r.randf() < 0.4:
			_send(m, &"yield")  # the wounded don't run: they go down on their knees and yield
			continue
		_send(m, &"break" if m["team"] == 0 else &"won")
	for k in knights:
		_send(k, &"won")
	scenes.framing.emit(scenes.ground(at + dir * 0.3), 3.4, view_yaw)


## Standards stay with their line: each bearer walks a little behind his side's middle, never faster than a
## walk, his flag beside him.
func _bearers() -> void:
	for t in bearers.size():
		var b: Dictionary = bearers[t]
		var n: Node3D = b["node"]
		if n == null or not is_instance_valid(n) or n.has_meta("dead"):
			continue
		var mine := _side(t)
		if mine.is_empty():
			continue
		var mid := Vector3.ZERO
		for m in mine:
			mid += m["node"].global_position
		mid /= mine.size()
		var goal: Vector3 = mid - b["face"] * 0.55
		var moving := Vector2(goal.x - n.global_position.x, goal.z - n.global_position.z).length() > 0.05
		if moving:
			Mover.of(n).toward(goal, WALK * 0.9)
			var flag: Node3D = b["flag"]
			if flag and is_instance_valid(flag):
				Mover.of(flag).toward(flag.global_position + (goal - n.global_position), WALK * 0.9, b["face"])
		if moving != b.get("moving", false):
			b["moving"] = moving
			scenes.people.play(n, "Walk" if moving else "Sword_Idle", 0.95)


## The camera stays on the thick of it: wherever most men are fighting, in close on the blows, then back out on
## the whole melee, by turns (one distance and the whole fight reads as a blob of small men).
var _close := false


func _frame(dt: float) -> void:
	_frame_t -= dt
	if _frame_t > 0.0 or clash < 0.0 or routed:
		return
	_frame_t = 3.0
	var mid := Vector3.ZERO
	var n := 0
	for m in men:
		if m["alive"] and m.get("fighting", false):
			mid += m["node"].global_position
			n += 1
	if n > 3:
		_close = not _close
		scenes.framing.emit(scenes.ground(mid / n), 1.6 if _close else 2.8, view_yaw + (0.35 if _close else 0.0))


# --- Who's where -----------------------------------------------------------------------------------------

func _foes(m: Dictionary) -> Array:
	return men.filter(func(o): return o["team"] != m["team"])


func _file_front(m: Dictionary):
	var best = null
	for o in men:
		if o["alive"] and o["team"] == m["team"] and o["file"] == m["file"] and o["rank"] < m["rank"]:
			if best == null or o["rank"] < best["rank"]:
				best = o
	return best


func _middle(team: int):
	for m in men:
		if m["team"] == team and m["rank"] == 0 and m["file"] == 4:
			return m
	return null


func _side(team: int) -> Array:
	return men.filter(func(m): return m["alive"] and m["team"] == team)
