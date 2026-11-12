extends Node
## A battle fought by its men rather than played from a timeline. Every soldier
## and every knight runs his own LimboAI state machine (LimboHSM, MIT,
## realm/addons/limboai): soldiers advance, close, trade blows, recoil, fall or
## break and run; knights walk up, charge the open end of the wall, ride through,
## wheel round and charge again. The fight's outcome is the realm's (team 0 is
## the beaten side), but how it goes on the field comes from the men in it.
##
## scenes.gd spawns the field and hands it here. It is loaded only when the
## LimboAI extension is present; without it the old timeline plays instead.

const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Combat := preload("res://scripts/combat.gd")
const Data := preload("res://scripts/data.gd")  # the battle's numbers: realm/data/battle.json
const WALK := 0.2  # a soldier's walk, units a second (about the Walk clip's stride)
const RUN := 0.55
const REACH := 0.2  # two duelists this far apart are at sword's length
const SPACE := 0.14  # men of one side keep this far apart
# How the fight goes is data (realm/data/battle.json); today's values are the fallbacks.
static var HP := int(Data.num("battle", "hp", 2))
static var HIT := [Data.num("battle", "hit.beaten", 0.22), Data.num("battle", "hit.victors", 0.5)]  # a blow's chance to land, beaten side and victors
static var BREAK := Data.num("battle", "breakAt", 0.55)  # the beaten side runs when this share of it is left
static var LONGEST := Data.num("battle", "longest", 18.0)  # or after this long at blows, whatever is left
static var RIDE := Data.num("battle", "charge.ride", 0.85)  # a knight's charge (Horse.GALLOP is 0.9)
static var PASSES := int(Data.num("battle", "charge.passes", 3))
static var KICK_ODDS := Data.num("battle", "kickOdds", 0.08)  # how often a swordsman kicks instead of cutting
static var KICK_LANDS := Data.num("battle", "kickLands", 0.7)
static var DODGE_ODDS := Data.num("battle", "dodge", 0.25)  # a missed blow dodged rather than parried

var scenes: Node  # scenes.gd: _stand, _die, _arrows, framing, _people
var root: Node3D
var r: RandomNumberGenerator
var at: Vector3
var dir: Vector3  # the victors (team 1) advance along +dir
var side: Vector3
var view_yaw: float
var men := []  # one Dictionary per soldier
var knights := []
var bearers := []
var clock := 0.0
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
	root.add_child(self)
	# Every move a fighter makes is chosen here, so the walk-in-step keeper
	# (anim_lod.gd) leaves them alone: it would swap a cut for a walk whenever a
	# man shuffles his feet.
	for b in standards:
		b["node"].set_meta("driven", true)
	for t in 2:
		for m in teams[t]:
			m["node"].set_meta("driven", true)
			m["node"].remove_meta("in_step")
			m["agent"] = _agent(m)
			if m["kit"] == "bow":
				scenes.people.motion(m["node"]).set_ready("Bow_Idle")  # an archer rests with his bow
			m["team"] = t
			m["hp"] = HP
			m["target"] = null
			m["cool"] = r.randf_range(0.2, 0.9)
			m["vel"] = Vector3.ZERO
			men.append(m)
			_soldier(m)
	knights = horses
	for i in knights.size():
		knights[i]["i"] = i
		_knight(knights[i])


## A soldier's mind: wait in rank, advance, close and fight, break or cheer.
func _soldier(m: Dictionary) -> void:
	var hsm := LimboHSM.new()
	var hold := LimboState.new()
	var advance := LimboState.new()
	var fight := LimboState.new()
	var run := LimboState.new()
	var cheer := LimboState.new()
	# Three ways out of the fight, and none back: dead, yielded, or fled over
	# the rise. No transition leaves them, and the guards below keep the
	# any-state events (break, won) from reaching a man who is out.
	var dead := LimboState.new()
	var yielded := LimboState.new()
	var gone := LimboState.new()
	for s in [hold, advance, fight, run, cheer, dead, yielded, gone]:
		hsm.add_child(s)
	var still_in := func() -> bool: return m["alive"] and not m.get("out", false)
	run.set_guard(still_in)
	cheer.set_guard(still_in)
	yielded.set_guard(still_in)
	dead.set_guard(func() -> bool: return not m.get("out", false))
	dead.call_on_enter(func():
		m["out"] = true
		m["alive"] = false
		if not m["node"].has_meta("dead"):  # an arrow may have felled him already
			scenes.die(m["node"], m.get("fall", "Death_Front"), r))
	yielded.call_on_enter(func():
		m["out"] = true
		_play(m, "Defeated"))
	gone.call_on_enter(func():
		m["out"] = true
		m["alive"] = false
		m["node"].visible = false)
	fight.call_on_enter(func(): m["fighting"] = true)
	fight.call_on_exit(func(): m["fighting"] = false)
	hold.call_on_enter(func(): _play(m, "Bow_Idle" if m["kit"] == "bow" else "Sword_Idle"))
	hold.call_on_update(func(dt: float): _hold(m, dt))
	advance.call_on_enter(func(): _play(m, "Walk"))
	advance.call_on_update(func(dt: float): _advance(m, dt))
	fight.call_on_update(func(dt: float): _fight(m, dt))
	run.call_on_enter(func(): _play(m, "Sprint", r.randf_range(1.0, 1.2)))
	run.call_on_update(func(dt: float): _run(m, dt))
	cheer.call_on_enter(func(): _play(m, ["Cheering", "Battlecry", "Yelling"][r.randi() % 3]))
	cheer.call_on_update(func(dt: float): _cheer(m, dt))
	hsm.add_transition(hold, advance, &"advance")
	hsm.add_transition(hold, fight, &"fight")
	hsm.add_transition(advance, fight, &"fight")
	hsm.add_transition(fight, hold, &"hold")
	hsm.add_transition(hsm.ANYSTATE, run, &"break")
	hsm.add_transition(hsm.ANYSTATE, cheer, &"won")
	hsm.add_transition(hsm.ANYSTATE, dead, &"die")
	hsm.add_transition(hsm.ANYSTATE, yielded, &"yield")
	hsm.add_transition(run, gone, &"gone")
	hsm.initial_state = hold
	m["node"].add_child(hsm)
	hsm.initialize(m["node"])
	hsm.set_active(true)
	m["hsm"] = hsm


## A knight's mind: walk up behind the line, charge, ride through, wheel round,
## charge again; after the rout, ride a few lengths after the beaten and rein in.
func _knight(k: Dictionary) -> void:
	var h: Node3D = k["node"]
	k["passes"] = 0
	k["path"] = null
	k["along"] = 0.0
	var hsm := LimboHSM.new()
	var wait := LimboState.new()
	var charge := LimboState.new()
	var wheel := LimboState.new()
	var down := LimboState.new()
	var rein := LimboState.new()
	for s in [wait, charge, wheel, down, rein]:
		hsm.add_child(s)
	wait.call_on_update(func(dt: float): _knight_wait(k, dt))
	charge.call_on_enter(func(): _plan_charge(k))
	charge.call_on_update(func(dt: float): _knight_ride(k, dt, RIDE, true))
	wheel.call_on_enter(func(): _plan_wheel(k))
	wheel.call_on_update(func(dt: float): _knight_ride(k, dt, 0.5, false))
	down.call_on_enter(func(): _unhorse(k))
	rein.call_on_update(func(dt: float): _knight_rein(k, dt))
	hsm.add_transition(wait, charge, &"charge")
	hsm.add_transition(charge, wheel, &"wheel")
	hsm.add_transition(wheel, charge, &"charge")
	hsm.add_transition(hsm.ANYSTATE, down, &"die")
	hsm.add_transition(hsm.ANYSTATE, rein, &"won")
	hsm.initial_state = wait
	h.add_child(hsm)
	hsm.initialize(h)
	hsm.set_active(true)
	k["hsm"] = hsm


func _process(dt: float) -> void:
	clock += dt
	_mind_the_crowd()
	# The field afterwards: the fallen stay a minute, then the battle is gone.
	if routed and clock - routed_at > 65.0:
		root.queue_free()
		return
	# The order of battle: formed up, the captain's shout, the advance under
	# the archers' arrows, then every man for himself.
	if clock > 0.8 and not root.has_meta("shouted"):
		root.set_meta("shouted", true)
		var captain = _middle(1)
		if captain:
			_play(captain, "Battlecry")
		for m in men:
			if m["team"] == 1 and is_same(m, captain) == false and r.randf() < 0.3:
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
		# Felled by something outside his own mind (an arrow): his mind stops.
		# Felled by an arrow: his mind goes to Dead once the arrow has landed
		# and he has fallen (scenes._arrows), not before.
		if not m["alive"] and not m.get("out", false) and m["node"].has_meta("dead"):
			_send(m, &"die")
	_promote()
	_bearers(dt)
	_morale()
	_frame(dt)


# ---- soldiers ---------------------------------------------------------------

func _hold(m: Dictionary, dt: float) -> void:
	# Stand in rank; the front of the wall takes on whoever comes within reach.
	# Stepping up into a gap is a walk, not a glide.
	var off: float = Vector2(m["slot"].x - m["node"].position.x, m["slot"].z - m["node"].position.z).length()
	if off > 0.05 and not m.get("stepping", false):
		m["stepping"] = true
		_play(m, "SS_Walk")
	elif off < 0.02 and m.get("stepping", false):
		m["stepping"] = false
		_play(m, "SS_Block_Idle" if m["kit"] != "bow" else "Bow_Idle")
	_steer(m, m["slot"], WALK * 0.6, dt, m["face"])
	if m["rank"] == 0:
		var e = _nearest_enemy(m, REACH * 2.2)
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


## A man of the ranks behind, on his own count after the lines meet, pushes
## into the fight: he picks a foe nobody else is on yet (or the nearest) and
## goes for him. Returns whether he went.
func _join(m: Dictionary) -> bool:
	if not m.has("join_at"):
		m["join_at"] = clash + r.randf_range(1.0, 7.0) + m["rank"] * 1.5
	if clock < m["join_at"]:
		return false
	var e = _free_enemy(m)
	if e == null:
		return false
	m["target"] = e
	_send(m, &"fight")
	return true


## The nearest foe nobody is fighting yet, else the one fewest are on.
func _free_enemy(m: Dictionary):
	var best = null
	var bd := INF
	for o in men:
		if o["team"] == m["team"] or not o["alive"] or o.get("out", false):
			continue
		var on := men.filter(func(x): return x["alive"] and is_same(x["target"], o)).size()
		var d := _gap(m["node"], o["node"]) + on * 0.6
		if d < bd:
			bd = d
			best = o
	return best


func _advance(m: Dictionary, dt: float) -> void:
	# On toward the wall at a walk, breaking into a run for the last stretch.
	var e = _nearest_enemy(m, 99.0)
	if e == null:
		return
	var gap: float = _gap(m["node"], e["node"])
	if m["rank"] == 0:
		if gap < REACH * 1.3:
			m["target"] = e
			if clash < 0.0:
				_clash()
			_send(m, &"fight")
			return
		var fast := gap < 0.55
		if fast and not m.get("running", false):
			m["running"] = true
			_play(m, "Sprint", r.randf_range(1.0, 1.15))
		_steer(m, e["node"].position, RUN if fast else WALK, dt)
	else:
		# The ranks behind keep their place behind their file's front man.
		var lead = _file_front(m)
		var goal: Vector3 = (lead["node"].position if lead else m["slot"]) - m["face"] * ROW * (m["rank"] - (lead["rank"] if lead else 0))
		_steer(m, goal, RUN if m.get("running", false) or (lead and lead.get("running", false)) else WALK, dt, m["face"])
		if lead and lead.get("running", false) and not m.get("running", false):
			m["running"] = true
			_play(m, "Sprint", r.randf_range(1.0, 1.15))
		if clash >= 0.0 and _gap(m["node"], e["node"]) < REACH * 1.3:
			m["target"] = e
			_send(m, &"fight")
		elif clash >= 0.0:
			_join(m)


func _fight(m: Dictionary, dt: float) -> void:
	var e = m["target"]
	if e == null or not e["alive"]:
		# The next man: the victors go looking across the field, the beaten
		# take on whoever comes near.
		e = _nearest_enemy(m, 99.0 if m["team"] == 1 else 1.0)
		m["target"] = e
		if e == null:
			if m["team"] == 0:
				_send(m, &"hold")
			return
	var n: Node3D = m["node"]
	var to: Vector3 = e["node"].position
	var gap := _gap(n, e["node"])
	# Out of reach: he walks (or runs) to his man, guard up, and fights on arrival.
	if gap > REACH * 1.6:
		var far := gap > 0.5
		if m.get("closing", "") != ("run" if far else "walk"):
			m["closing"] = "run" if far else "walk"
			m["guarding"] = false
			_play(m, "Sprint" if far else "SS_Walk", r.randf_range(0.95, 1.1))
		_steer(m, to + (n.position - to).normalized() * REACH, RUN if far else WALK, dt)
		return
	if m.get("closing", "") != "":
		m["closing"] = ""
		m["cool"] = minf(m["cool"], r.randf_range(0.1, 0.5))
	# Footwork: close to sword's length, back off when too near, and circle a
	# little so a pair never stands nailed to one spot.
	var want: Vector3 = to + (n.position - to).normalized() * REACH
	want += Vector3(-(to - n.position).z, 0, (to - n.position).x).normalized() * sin(clock * 0.7 + m["file"]) * 0.03
	_steer(m, want, WALK * 0.8 if gap > REACH * 1.5 else WALK * 0.35, dt, to - n.position)
	m["cool"] -= dt
	if m["cool"] > 0.0 or gap > REACH * 1.4 or e.get("busy", 0.0) > clock:
		# Between blows: guard up, or sword ready, never frozen on one clip.
		if m["cool"] > 0.0 and m.get("busy", 0.0) < clock and not m.get("guarding", false):
			m["guarding"] = true
			_play(m, "SS_Block_Idle" if r.randf() < 0.5 else "Sword_Idle")
		return
	# A cut from the sword-and-shield set the duels use (combat.gd), never the
	# same one twice running; now and then a kick to break the other's guard.
	var moves: Array = Combat.KITS["sword"]["attacks"].filter(func(x): return x != m.get("last", "") and x != "Sword_Attack_2")
	var move: String = Combat.KITS["sword"]["kick"] if r.randf() < KICK_ODDS else moves[r.randi() % moves.size()]
	if m["kit"] == "spear":
		move = "Spear_Thrust"
	m["last"] = move
	var pace := r.randf_range(1.0, 1.2)
	var length := _play(m, move, pace)
	m["guarding"] = false
	m["busy"] = clock + length
	m["cool"] = length + r.randf_range(0.3, 1.1)
	# The other man answers the blow as it comes: he sees it start and lifts
	# his shield or steps aside, or takes it. Resolved the moment it lands.
	var at: float = length * float(Combat.BLOW_AT.get(move, 0.45))
	var t := n.create_tween()
	t.tween_interval(maxf(0.05, at - 0.25))
	t.tween_callback(func(): _answer(m, e, move))
	t.tween_interval(0.25)
	t.tween_callback(func(): _land(m, e, move))


## The man being cut at decides in the last instant: shield or dodge if he
## will turn it, so his move meets the blow on the same frame.
func _answer(m: Dictionary, e: Dictionary, move: String) -> void:
	if not m["alive"] or not e["alive"] or e.get("busy", 0.0) > clock:
		return
	var kick: bool = move == Combat.KITS["sword"]["kick"]
	var lands: bool = r.randf() < (KICK_LANDS if kick else float(HIT[m["team"]]))
	e["fate"] = lands
	if lands:
		return
	var parry: Array = Combat.KITS["sword"]["parry"]
	var clip: String = parry[r.randi() % parry.size()]
	if r.randf() < DODGE_ODDS:
		clip = ["Dodge_Back", "Dodge_Left", "Dodge_Right"][r.randi() % 3]
	e["guarding"] = false
	e["busy"] = clock + _play(e, clip, r.randf_range(1.0, 1.2)) * 0.8
	e["cool"] = maxf(e["cool"], 0.25)  # and he may cut back at once


func _land(m: Dictionary, e: Dictionary, move: String) -> void:
	if not m["alive"] or not e["alive"] or _gap(m["node"], e["node"]) > REACH * 1.6:
		return
	if not e.get("fate", false):
		return
	e["fate"] = false
	var n: Node3D = e["node"]
	var back: Vector3 = (n.position - m["node"].position).normalized()
	if move == Combat.KITS["sword"]["kick"]:
		# Kicked: doubled over or dazed, guard broken for a moment.
		e["busy"] = clock + _play(e, Combat.REELS["kick"][r.randi() % 3], 1.0) * 0.9
		Mover.of(n).shift((n.get_parent() as Node3D).to_global(scenes.stand(n.position + back * 0.06)), 0.4)
		return
	e["hp"] -= 1
	if e["hp"] <= 0:
		_kill(e, move in Combat.OVERHEAD)
		return
	# Struck but standing: he reels by where the blow fell, back a step, and
	# comes on again.
	var where := "head" if move in Combat.OVERHEAD else ("body" if r.randf() < 0.7 else "head")
	var reels: Array = Combat.REELS[where] + Combat.KITS["sword"]["hurt"]
	e["guarding"] = false
	e["busy"] = clock + _play(e, reels[r.randi() % reels.size()], 1.0) * 0.85
	e["cool"] = maxf(e["cool"], 0.6)
	Mover.of(n).shift((n.get_parent() as Node3D).to_global(scenes.stand(n.position + back * 0.05)), 0.35)


func _kill(m: Dictionary, back := true) -> void:
	if not m["alive"]:
		return
	# He falls the way the blow drives him.
	var falls: Array = Combat.KITS["sword"]["fall_back" if back else "fall_forward"] + ["Fall_Back_Death" if back else "Death01"]
	m["fall"] = falls[r.randi() % falls.size()]
	_send(m, &"die")


func _run(m: Dictionary, dt: float) -> void:
	var n: Node3D = m["node"]
	if not m.has("away"):
		# Away from the victors: the beaten stand on the +dir side.
		m["away"] = (dir + side * r.randf_range(-0.7, 0.7)).normalized()
		m["gone"] = r.randf_range(5.0, 7.0)
	n.position = scenes.stand(n.position + m["away"] * RUN * 1.1 * dt)
	n.rotation.y = lerp_angle(n.rotation.y, atan2(m["away"].x, m["away"].z), minf(1.0, dt * 8.0))
	m["gone"] -= dt
	if m["gone"] <= 0.0:
		# Out of the fight and over the rise.
		_send(m, &"gone")


func _cheer(m: Dictionary, dt: float) -> void:
	# A few paces after the beaten, then cheer under the standard, then rest.
	m["cool"] -= dt
	if not m.has("chase"):
		m["chase"] = r.randf_range(0.6, 1.8) if m["rank"] == 0 and r.randf() < 0.6 else 0.0
		m["cool"] = r.randf_range(4.0, 6.0)
		if m["chase"] > 0.0:
			_play(m, "Sprint", 1.0)
	if m["chase"] > 0.0:
		m["chase"] -= dt
		var n: Node3D = m["node"]
		n.position = scenes.stand(n.position + dir * RUN * 0.6 * dt)
		if m["chase"] <= 0.0:
			_play(m, ["Cheering", "Battlecry", "Yelling"][r.randi() % 3])
	elif m["cool"] <= 0.0 and m["cool"] > -1.0:
		m["cool"] = -2.0
		_play(m, "Sword_Idle")


## Fills a gap: when the front man of a file falls, the next man of his file
## steps up to the front.
func _promote() -> void:
	for m in men:
		if not m["alive"] or m["rank"] == 0:
			continue
		var ahead := men.filter(func(o): return o["alive"] and o["team"] == m["team"] and o["file"] == m["file"] and o["rank"] < m["rank"])
		if ahead.is_empty():
			m["rank"] = 0
			m["slot"] = m["slot"] + m["face"] * ROW * 0.5
			if clash >= 0.0 and not routed:
				m["target"] = _nearest_enemy(m, 99.0)
				_send(m, &"fight")


# ---- knights ----------------------------------------------------------------

func _knight_wait(k: Dictionary, dt: float) -> void:
	# Up at a walk behind the line during the advance, then hold for the horn.
	var h: Node3D = k["node"]
	if clock < 3.0:
		return
	var poised: Vector3 = k["wing"] - dir * (REACH + 3 * ROW + 0.4)
	var to := poised - h.position
	to.y = 0
	if to.length() > 0.02:
		var step := minf(to.length(), 0.18 * dt)
		h.position = scenes.stand(h.position + to.normalized() * step, scenes.HORSE_BODY)
		h.rotation.y = lerp_angle(h.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 3.0))
	if clash >= 0.0 and clock > clash + 0.6 + k["i"] * 0.15:
		if k["i"] == 0 and not k.get("reared", false):
			k["reared"] = true
			h.rear()
			k["delay"] = 1.2
		k["delay"] = k.get("delay", 0.0) - dt
		if k["delay"] <= 0.0:
			_send(k, &"charge")


func _plan_charge(k: Dictionary) -> void:
	# Out wide past the wall's end, wheel in onto its flank, and ride on through.
	var h: Node3D = k["node"]
	var i: int = k["i"]
	var wall := _side(0)
	var end := at + dir * (REACH + ROW) + side * (4.5 * 0.2 + 0.1)
	if not wall.is_empty():
		# The open end of whatever is left of the wall, on the knights' side.
		var best := -INF
		for m in wall:
			var s: float = (m["node"].position - at).dot(side)
			if s > best:
				best = s
				end = m["node"].position
	var wide: Vector3 = end + side * (0.55 + (i % 2) * 0.15) - dir * 0.2
	var into: Vector3 = end - side * (0.1 + (i / 2) * 0.12) + dir * ((i % 2) * 0.14)
	var through: Vector3 = into - side * 0.7 + dir * 0.2
	var c := Curve3D.new()
	c.add_point(h.position)
	c.add_point(wide, (h.position - wide) * 0.4, (into - wide) * 0.35)
	c.add_point(into, (wide - into) * 0.3, (through - into) * 0.3)
	c.add_point(through)
	k["path"] = c
	k["along"] = 0.0
	k["rode"] = []
	k["passes"] += 1


func _plan_wheel(k: Dictionary) -> void:
	# Round in a wide loop at a canter, back out past the wing for another go.
	var h: Node3D = k["node"]
	var out: Vector3 = h.position - side * 0.3 - dir * 0.8
	var back: Vector3 = at + side * (1.6 + k["i"] * 0.12) - dir * (0.9 + (k["i"] % 2) * 0.2)
	var c := Curve3D.new()
	c.add_point(h.position)
	c.add_point(out, (h.position - out) * 0.5, (back - out) * 0.4)
	c.add_point(back)
	k["path"] = c
	k["along"] = 0.0


func _knight_ride(k: Dictionary, dt: float, pace: float, charging: bool) -> void:
	if not k["alive"]:
		return
	var h: Node3D = k["node"]
	var c: Curve3D = k["path"]
	var length := c.get_baked_length()
	# Off at a canter, into the gallop.
	var speed := pace * clampf(0.45 + k["along"] / 0.8, 0.45, 1.0)
	k["along"] = minf(k["along"] + speed * dt, length)
	var p := c.sample_baked(k["along"])
	var q := c.sample_baked(minf(k["along"] + 0.04, length))
	h.position = scenes.stand(p, scenes.HORSE_BODY)
	if q.distance_to(p) > 0.0001:
		h.rotation.y = lerp_angle(h.rotation.y, atan2(q.x - p.x, q.z - p.z), minf(1.0, dt * 6.0))
	if charging:
		# Men in the horse's path are ridden down; a horse may be brought down in the press.
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
	if k["along"] >= length - 0.001:
		if charging:
			_send(k, &"wheel")
		elif k["passes"] < PASSES and not routed:
			_send(k, &"charge")
		else:
			k["path"] = null


func _unhorse(k: Dictionary) -> void:
	var h: Node3D = k["node"]
	k["alive"] = false
	h.fall()
	scenes._lie_clear(h, 0.17, scenes.HORSE_BODY)
	var thrown: Node3D = h.dismount()
	if thrown:
		var fwd := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
		thrown.global_position = scenes.stand(h.global_position + fwd * 0.25)
		scenes.die(thrown, "Death_Front", r)


func _knight_rein(k: Dictionary, dt: float) -> void:
	# After the beaten at a canter, out past the field, easing to a walk and a
	# halt there, clear of the men cheering behind.
	if not k["alive"]:
		return
	var h: Node3D = k["node"]
	if not k.has("chase"):
		k["chase"] = (dir + side * r.randf_range(-0.4, 0.4)).normalized()
		k["rein"] = r.randf_range(4.5, 6.0)
	k["rein"] -= dt
	if k["rein"] > 0.0:
		var to: Vector3 = k["chase"]
		h.rotation.y = lerp_angle(h.rotation.y, atan2(to.x, to.z), minf(1.0, dt * 2.5))
		var fwd := Vector3(sin(h.rotation.y), 0, cos(h.rotation.y))
		h.position = scenes.stand(h.position + fwd * 0.6 * clampf(k["rein"] / 3.0, 0.15, 1.0) * dt, scenes.HORSE_BODY)


# ---- the whole field --------------------------------------------------------

func _clash() -> void:
	clash = clock
	scenes.dust(root, scenes.ground(at) + Vector3(0, 0.01, 0), side, 9 * 0.2)
	scenes.framing.emit(scenes.ground(at), 2.8, view_yaw)


## The beaten side breaks when too few are left or the fight has gone on too
## long: their standard goes down and they run; the victors cheer.
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
		scenes.die(bearers[0]["node"], "Death_Back", r)
		scenes._drop_banner(bearers[0]["flag"], bearers[0]["face"])
	for m in men:
		if not m["alive"]:
			continue
		if m["team"] == 0 and m["hp"] < HP and r.randf() < 0.4:
			# The wounded don't run: they go down on their knees and yield.
			_send(m, &"yield")
			continue
		_send(m, &"break" if m["team"] == 0 else &"won")
	for k in knights:
		_send(k, &"won")
	scenes.framing.emit(scenes.ground(at + dir * 0.3), 3.4, view_yaw)


## Standards stay with their line: each bearer walks a little behind his side's
## middle, never faster than a walk.
func _bearers(dt: float) -> void:
	for t in bearers.size():
		var b: Dictionary = bearers[t]
		var n: Node3D = b["node"]
		if n == null or n.has_meta("dead"):
			continue
		var mine := _side(t)
		if mine.is_empty():
			continue
		var mid := Vector3.ZERO
		for m in mine:
			mid += m["node"].position
		mid /= mine.size()
		var goal: Vector3 = mid - b["face"] * 0.55
		var to := goal - n.position
		to.y = 0
		var moving := to.length() > 0.05
		if moving:
			var step := to.normalized() * minf(to.length(), WALK * 0.9 * dt)
			n.position = scenes.stand(n.position + step)
			var flag: Node3D = b["flag"]
			if flag:
				flag.position = scenes.ground(flag.position + step)
		if moving != b.get("moving", false):
			b["moving"] = moving
			scenes.people.play(n, "Walk" if moving else "Sword_Idle", 0.95)


## The camera stays on the thick of it: wherever most men are fighting.
var _close := false  # this beat in close on the blows, or out on the melee


func _frame(dt: float) -> void:
	_frame_t -= dt
	if _frame_t > 0.0 or clash < 0.0 or routed:
		return
	_frame_t = 3.0
	var mid := Vector3.ZERO
	var n := 0
	for m in men:
		if m["alive"] and m.get("fighting", false):
			mid += m["node"].position
			n += 1
	if n > 3:
		# In close on the blows, then back out on the whole melee, by turns:
		# one distance the whole fight reads as a blob of small men.
		_close = not _close
		scenes.framing.emit(scenes.ground(mid / n), 1.6 if _close else 2.8, view_yaw + (0.35 if _close else 0.0))


# ---- helpers ----------------------------------------------------------------

## Moves a man toward `goal` at `speed`, kept apart from his own side, turning
## to face `look` (or the way he goes).
func _steer(m: Dictionary, goal: Vector3, speed: float, dt: float, look := Vector3.ZERO) -> void:
	var n: Node3D = m["node"]
	var to := goal - n.position
	to.y = 0
	var want := Vector3.ZERO
	if to.length() > 0.015:
		want = to.normalized() * minf(speed, to.length() * 4.0)
	# The crowd is the engine's: Godot's avoidance (NavigationAgent3D, RVO)
	# turns where he wants to go into a way through the men around him, friend,
	# foe and the fallen, so nobody walks into or through another.
	if m.has("agent") and _crowd_on:
		NavigationServer3D.agent_set_position(m["agent"], n.global_position)
		NavigationServer3D.agent_set_velocity(m["agent"], want)
		var safe: Vector3 = m.get("safe", want)
		# A man the avoidance holds stock-still while he means to move, for a
		# whole second, is flagged (CHECK) and let through: a crowd must never
		# freeze silently, as it did once.
		m["held"] = m.get("held", 0.0) + get_process_delta_time() if want.length() > 0.05 and safe.length() < 0.005 else 0.0
		if m["held"] > 1.0:
			if not m.get("flagged", false):
				m["flagged"] = true
				print("CHECK avoidance held a fighter still for a second")
		else:
			want = safe
	m["vel"] = m["vel"].lerp(want, minf(1.0, dt * 6.0))
	n.position = scenes.stand(n.position + m["vel"] * dt)
	var face: Vector3 = look if look.length() > 0.001 else m["vel"]
	face.y = 0
	if face.length() > 0.001:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(face.x, face.z), minf(1.0, dt * 5.0))


## A battle too far off to make out its men (past people.gd's SEEN_TO, where
## they aren't drawn) needs no avoidance: its map stops, and each man walks his
## own way until the camera comes near again. Its every agent answering every
## physics tick was what froze the frame when a battle began across the realm.
const CROWD_SEEN := 24.0  # world units, a little past where men are drawn
var _crowd_on := true
var _crowd_check := 0.0


func _mind_the_crowd() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or not _crowd.is_valid() or men.is_empty():
		return
	_crowd_check -= get_process_delta_time()
	if _crowd_check > 0.0:
		return
	_crowd_check = 0.5
	# Where the fight is: the middle of its men (the scene's root sits at the world's origin).
	var mid := Vector3.ZERO
	for m in men:
		mid += (m["node"] as Node3D).global_position
	mid /= men.size()
	var d: float = cam.global_position.distance_to(mid)
	var on := d < (CROWD_SEEN if not _crowd_on else CROWD_SEEN + 4.0)
	if on != _crowd_on:
		_crowd_on = on
		NavigationServer3D.map_set_active(_crowd, on)


## A fighter's place in the crowd, as Godot's avoidance (NavigationServer3D,
## RVO) sees it: about a man's width, looking a few paces about him. The dead
## keep theirs, so the living step round them. One avoidance map per battle.
var _crowd := RID()


func _agent(m: Dictionary) -> RID:
	if not _crowd.is_valid():
		_crowd = NavigationServer3D.map_create()
		NavigationServer3D.map_set_active(_crowd, true)
	var a := NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(a, _crowd)
	NavigationServer3D.agent_set_avoidance_enabled(a, true)
	NavigationServer3D.agent_set_radius(a, 0.055)
	NavigationServer3D.agent_set_neighbor_distance(a, 0.6)
	NavigationServer3D.agent_set_max_neighbors(a, 12)
	NavigationServer3D.agent_set_time_horizon_agents(a, 0.5)
	NavigationServer3D.agent_set_max_speed(a, RUN * 1.2)
	NavigationServer3D.agent_set_position(a, m["node"].global_position)
	NavigationServer3D.agent_set_avoidance_callback(a, func(v: Vector3): m["safe"] = Vector3(v.x, 0, v.z))
	return a


func _exit_tree() -> void:
	for m in men:
		if m.has("agent"):
			NavigationServer3D.free_rid(m["agent"])
	if _crowd.is_valid():
		NavigationServer3D.free_rid(_crowd)


func _nearest_enemy(m: Dictionary, within: float):
	var best = null
	var bd := within
	for o in men:
		if o["team"] == m["team"] or not o["alive"]:
			continue
		var d := _gap(m["node"], o["node"])
		# Prefer a man nobody else is already on.
		var taken := men.filter(func(x): return x["alive"] and not is_same(x, m) and is_same(x["target"], o)).size()
		d += taken * 0.08
		if d < bd:
			bd = d
			best = o
	return best


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


func _gap(a: Node3D, b: Node3D) -> float:
	var d := a.position - b.position
	d.y = 0
	return d.length()


## Plays a move and says how long it runs, in seconds.
func _play(m: Dictionary, anim: String, speed := -1.0) -> float:
	var pace := speed if speed > 0.0 else r.randf_range(0.9, 1.1)
	scenes.people.play(m["node"], anim, pace)
	# How long it really runs: each man plays at his own tempo too.
	var mo: AnimationTree = scenes.people.motion(m["node"])
	if mo and mo.has_animation(anim):
		return mo.get_animation(anim).length / (pace * float(m["node"].get_meta("tempo", 1.0)))
	return 1.0


func _send(who: Dictionary, event: StringName) -> void:
	var hsm: LimboHSM = who.get("hsm")
	if hsm and is_instance_valid(hsm):
		hsm.dispatch(event)


const ROW := 0.2
