extends Node
## Men fighting man to man: the army layer's close fight (docs/research/army-layer-2026-11-12.md). What every
## close fight shares, whatever staged it (army_skirmish.gd a battle on the field, army_assault.gd a siege's
## parties at the wall and in the breach):
##  - the field's own ground (army_ground.gd: water, houses and walls shut) and one crowd (Godot's RVO), so every
##    man goes round the lake, the house and the man beside him;
##  - every step through the Mover (mover.gd: toward a moving mark, shifted back by a blow, off at a run);
##  - every man's mind a LimboHSM made from a data/army.json minds row (army_mind.gd);
##  - one duel: close to a sword's length, circle a little, cut when ready (never the same cut twice running, now
##    and then a kick); the other sees it start and lifts his shield or steps aside, or takes it, reels back a step
##    and comes on, or falls the way the blow drives him. The duels' own moves (combat.gd's kits and reels).
## Who wins is the realm's (Freeciv decides, the bridge tells): a staging sets each side's chance to land a blow.

const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Mind := preload("res://scripts/army_mind.gd")
const Ground := preload("res://scripts/army_ground.gd")
const Combat := preload("res://scripts/combat.gd")
const Data := preload("res://scripts/data.gd")

const WALK := 0.2  # a fighter's walk, units a second (about the walk clip's stride)
const RUN := 0.55
static var KICK_ODDS := Data.num("battle", "kickOdds", 0.08)  # how often a swordsman kicks instead of cutting
static var KICK_LANDS := Data.num("battle", "kickLands", 0.7)
static var DODGE_ODDS := Data.num("battle", "dodge", 0.25)  # a missed blow dodged rather than parried

var scenes: Node  # scenes.gd: stand, die, people, framing, arrows
var root: Node3D
var r: RandomNumberGenerator
var clock := 0.0
var ground: RefCounted  # army_ground.gd: this fight's field
var reach := 0.2  # two duelists this far apart are at sword's length
var fighters: Array = []  # every man fighting
var _bodies: Array = []  # every body that joined the crowd (the fallen too), to leave it before it goes
var _crowd := RID()


## Lays the fight's ground `span` units round `centre` (world) and opens its crowd.
func _field(centre: Vector3, span: float) -> void:
	ground = Ground.around(scenes.get_parent(), centre, span)
	_crowd = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_crowd, true)


## A man joins the fight: he stands on its ground and in its crowd, and his mind is made from the row `kind`.
## Every move a fighter makes is chosen here, so the walk-in-step keeper (anim_lod.gd) leaves him alone.
func _enlist(m: Dictionary, kind: String) -> void:
	var n: Node3D = m["node"]
	n.set_meta("driven", true)
	n.remove_meta("in_step")
	var mo: Node = Mover.of(n).on(ground)
	mo.clip = ""  # his mind plays his moves
	if _crowd.is_valid():
		mo.join(_crowd, 0.055, RUN * 1.2)
		_bodies.append(n)
	if not fighters.has(m):
		fighters.append(m)
	if kind != "":
		Mind.make(kind, m, n, self)


## Each frame a fighter's mind wants him somewhere: the Mover takes him (by the ground, round the crowd).
func _steer(m: Dictionary, goal: Vector3, speed: float, look := Vector3.ZERO) -> void:
	var n = m.get("node")
	if is_instance_valid(n):
		Mover.of(n).toward(goal, speed, look)


## Shoved back a step from a blow: routed, timed, no turn.
func _shove(n: Node3D, back: Vector3, by: float, secs: float) -> void:
	Mover.of(n).shift(ground.keep_out(n.global_position + back * by), secs)


func _send(who: Dictionary, event: StringName) -> void:
	Mind.send(who, event)


func _process(dt: float) -> void:
	clock += dt
	_mind_the_crowd()


# --- The duel --------------------------------------------------------------------------------------------

## `a` fights `e`: closes to a sword's length at a walk or a run, footwork and a little circling once there, and
## cuts when ready; `hit` is the chance his cut lands (the realm's outcome for his side).
func _duel(a: Dictionary, e: Dictionary, dt: float, hit: float) -> void:
	var n: Node3D = a["node"]
	var foe: Node3D = e["node"]
	if not is_instance_valid(n) or not is_instance_valid(foe):
		return
	var to: Vector3 = foe.global_position
	var off := Vector3(to.x - n.global_position.x, 0, to.z - n.global_position.z)
	var gap := off.length()
	var away := -off.normalized() if gap > 0.001 else Vector3.BACK
	# Out of reach: he walks (or runs) to his man, guard down, and fights on arrival.
	if gap > reach * 1.6:
		var far := gap > 0.5
		if a.get("closing", "") != ("run" if far else "walk"):
			a["closing"] = "run" if far else "walk"
			a["guarding"] = false
			_play(a, "Sprint" if far else "SS_Walk", r.randf_range(0.95, 1.1))
		_steer(a, to + away * reach, RUN if far else WALK)
		return
	if a.get("closing", "") != "":
		a["closing"] = ""
		a["cool"] = minf(float(a.get("cool", 0.0)), r.randf_range(0.1, 0.5))
	# Footwork: close to sword's length, back off when too near, and circle a little so a pair never stands
	# nailed to one spot.
	var want: Vector3 = to + away * reach + Vector3(-off.z, 0, off.x).normalized() * sin(clock * 0.7 + float(a.get("file", 0))) * 0.03
	_steer(a, want, WALK * 0.8 if gap > reach * 1.5 else WALK * 0.35, off)
	a["cool"] = float(a.get("cool", 0.0)) - dt
	if float(a["cool"]) > 0.0 or gap > reach * 1.4 or float(e.get("busy", 0.0)) > clock or float(a.get("busy", 0.0)) > clock:
		# Between blows: guard up, or sword ready, never frozen on one clip.
		if float(a["cool"]) > 0.0 and float(a.get("busy", 0.0)) < clock and not a.get("guarding", false):
			a["guarding"] = true
			_play(a, "SS_Block_Idle" if r.randf() < 0.5 else "Sword_Idle")
		return
	var moves: Array = Combat.KITS["sword"]["attacks"].filter(func(x): return x != a.get("last", "") and x != "Sword_Attack_2")
	var move: String = Combat.KITS["sword"]["kick"] if r.randf() < KICK_ODDS else moves[r.randi() % moves.size()]
	if a.get("kit", "sword") == "spear":
		move = "Spear_Thrust"
	a["last"] = move
	var length := _play(a, move, r.randf_range(1.0, 1.2))
	a["guarding"] = false
	a["busy"] = clock + length
	a["cool"] = length + r.randf_range(0.3, 1.1)
	# The other man answers the blow as it comes: he sees it start and lifts his shield or steps aside, or takes
	# it. Resolved the moment it lands.
	var blow: float = length * float(Combat.BLOW_AT.get(move, 0.45))
	var t := n.create_tween()
	t.tween_interval(maxf(0.05, blow - 0.25))
	t.tween_callback(func(): _answer(a, e, move, hit))
	t.tween_interval(0.25)
	t.tween_callback(func(): _land(a, e, move))


## The man being cut at decides in the last instant: shield or dodge if he will turn it, so his move meets the
## blow on the same frame.
func _answer(a: Dictionary, e: Dictionary, move: String, hit: float) -> void:
	if not a["alive"] or not e["alive"] or float(e.get("busy", 0.0)) > clock or not is_instance_valid(e.get("node")):
		return
	var kick: bool = move == Combat.KITS["sword"]["kick"]
	var lands: bool = r.randf() < (KICK_LANDS if kick else hit)
	e["fate"] = lands
	if lands:
		return
	var parry: Array = Combat.KITS["sword"]["parry"]
	var clip: String = parry[r.randi() % parry.size()]
	if r.randf() < DODGE_ODDS:
		clip = ["Dodge_Back", "Dodge_Left", "Dodge_Right"][r.randi() % 3]
	e["guarding"] = false
	e["busy"] = clock + _play(e, clip, r.randf_range(1.0, 1.2)) * 0.8
	e["cool"] = maxf(float(e.get("cool", 0.0)), 0.25)  # and he may cut back at once


func _land(a: Dictionary, e: Dictionary, move: String) -> void:
	if not a["alive"] or not e["alive"] or not e.get("fate", false) or not is_instance_valid(e.get("node")) or not is_instance_valid(a.get("node")):
		return
	e["fate"] = false
	var n: Node3D = e["node"]
	var off: Vector3 = n.global_position - (a["node"] as Node3D).global_position
	off.y = 0.0
	if off.length() > reach * 1.8:
		return
	var back := off.normalized()
	if move == Combat.KITS["sword"]["kick"]:
		# Kicked: doubled over or dazed, guard broken for a moment.
		e["busy"] = clock + _play(e, Combat.REELS["kick"][r.randi() % 3], 1.0) * 0.9
		_shove(n, back, 0.06, 0.4)
		return
	e["hp"] = int(e.get("hp", 1)) - 1
	if int(e["hp"]) <= 0:
		_kill(e, move in Combat.OVERHEAD)
		return
	# Struck but standing: he reels by where the blow fell, back a step, and comes on again.
	var where := "head" if move in Combat.OVERHEAD else ("body" if r.randf() < 0.7 else "head")
	var reels: Array = Combat.REELS[where] + Combat.KITS["sword"]["hurt"]
	e["guarding"] = false
	e["busy"] = clock + _play(e, reels[r.randi() % reels.size()], 1.0) * 0.85
	e["cool"] = maxf(float(e.get("cool", 0.0)), 0.6)
	_shove(n, back, 0.05, 0.35)


## He falls the way the blow drives him (his mind goes to its fall).
func _kill(m: Dictionary, back := true) -> void:
	if not m["alive"]:
		return
	var falls: Array = Combat.KITS["sword"]["fall_back" if back else "fall_forward"] + ["Fall_Back_Death" if back else "Death01"]
	m["fall"] = falls[r.randi() % falls.size()]
	_send(m, &"die")


## His body falls (unless an arrow felled it already), and stops where it lies.
func _fall_body(m: Dictionary) -> void:
	var n = m.get("node")
	if not is_instance_valid(n):
		return
	Mover.of(n).stop()
	if not (n as Node3D).has_meta("dead"):
		scenes.die(n, String(m.get("fall", scenes.DEATHS[r.randi() % scenes.DEATHS.size()])), r)


# --- Helpers ---------------------------------------------------------------------------------------------

## The nearest living one of `among` within `within` of `at` (world); with `me`, a man nobody else of `mine` is on
## yet preferred.
func _nearest(at: Vector3, among: Array, within: float, me: Dictionary = {}, mine: Array = []):
	var best = null
	var bd := within
	for x in among:
		if not x["alive"] or x.get("out", false) or not is_instance_valid(x.get("node")):
			continue
		var p: Vector3 = (x["node"] as Node3D).global_position
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if not me.is_empty():
			d += mine.filter(func(o): return o["alive"] and not is_same(o, me) and is_same(o.get("target"), x)).size() * 0.08
		if d < bd:
			bd = d
			best = x
	return best


func _gap(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


## Turns a standing man toward `way`, a little each frame.
func _turn(n: Node3D, way: Vector3, dt: float) -> void:
	if Vector2(way.x, way.z).length() > 0.001:
		n.rotation.y = lerp_angle(n.rotation.y, atan2(way.x, way.z), minf(1.0, dt * 6.0))


## Plays a move and says how long it runs, in seconds (each man plays at his own tempo too).
func _play(m: Dictionary, anim: String, speed := -1.0) -> float:
	var n = m.get("node")
	if not is_instance_valid(n):
		return 1.0
	var pace := speed if speed > 0.0 else r.randf_range(0.9, 1.1)
	scenes.people.play(n, anim, pace)
	var mo: AnimationTree = scenes.people.motion(n)
	if mo and mo.has_animation(anim):
		return mo.get_animation(anim).length / (pace * float((n as Node).get_meta("tempo", 1.0)))
	return 1.0


# --- The crowd -------------------------------------------------------------------------------------------

## A fight too far off to make out its men (past people.gd's SEEN_TO, where they aren't drawn) needs no
## avoidance: its map stops, and each man walks his own way until the camera comes near again. Its every agent
## answering every physics tick was what froze the frame when a battle began across the realm.
static var CROWD_SEEN: float = preload("res://scripts/data.gd").num("battle", "crowd_seen", 24.0)  # world units, a little past where men are drawn (battle.json crowd_seen)
var _crowd_on := true
var _crowd_check := 0.0


func _mind_the_crowd() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or not _crowd.is_valid() or fighters.is_empty():
		return
	_crowd_check -= get_process_delta_time()
	if _crowd_check > 0.0:
		return
	_crowd_check = 0.5
	var mid := Vector3.ZERO
	var n := 0
	for m in fighters:
		if is_instance_valid(m.get("node")):
			mid += (m["node"] as Node3D).global_position
			n += 1
	if n == 0:
		return
	var on := cam.global_position.distance_to(mid / n) < (CROWD_SEEN if not _crowd_on else CROWD_SEEN + 4.0)
	if on != _crowd_on:
		_crowd_on = on
		NavigationServer3D.map_set_active(_crowd, on)


func _exit_tree() -> void:
	for n in _bodies:
		if is_instance_valid(n):
			Mover.of(n).leave()  # out of the crowd before the crowd goes
	if _crowd.is_valid():
		NavigationServer3D.free_rid(_crowd)
		_crowd = RID()
