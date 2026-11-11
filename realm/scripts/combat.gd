extends RefCounted
## One fighter in a melee: the character you control or a foe. Health, a
## guard, and a few states: ready, striking, blocking, staggered, dead. Each
## fighter has a kit (sword and shield, greatsword, axe, dagger) and fights with
## that kit's own Mixamo moves; sheathed, they fight with their fists. A strike
## lands on the frame the blow arrives, on whoever is in front within reach; a
## guard turned toward the blow stops it, and a dodge takes you out of its way.
## Who is hit reels by where the blow lands (head, body, side, legs, back) and
## how hard, and bleeds there; a heavy blow can put them on the ground for a
## moment, a kick leaves them dazed or doubled over; the badly hurt limp; who
## falls, falls away from it and stains the ground.

const Weapons := preload("res://scripts/weapons.gd")
const Blood := preload("res://scripts/blood.gd")

const REACH := 0.16  # town units: about 1.3 m, a sword's length (the AI's closing distance)
const ARC := 0.75  # cos of the half-angle a strike covers (about 40 degrees each side)
const FOLLOW := 0.4  # seconds a move runs on past its blow before the fighter is ready again
const DODGE := 0.6  # metres a dodge carries you
static var FLOORED := preload("res://scripts/data.gd").num("battle", "floored", 0.3)  # chance a heavy blow that doesn't kill knocks you down (realm/data/battle.json)
# Moves heavy enough to floor someone: the big two-handed and spinning cuts.
const HEAVY := ["GS_Attack", "GS_Slash_1", "GS_Slash_3", "GS_Spin", "Axe_Down", "Axe_Spin"]
# Cuts that come down from above land on the head; the rest are a body blow
# more often than not, now and then the head or the legs.
const OVERHEAD := ["GS_Attack", "Axe_Down", "SS_Attack_3", "Sword_Attack_2"]
const HURT_FOR := 12.0  # seconds someone limps after being knocked down
const WEAK := 35.0  # health below which they limp for good
# Reactions by where the blow lands and how hard. Taken head-on unless named.
const REELS := {
	"head": ["Head_Light_1", "Head_Light_2", "Head_Light_3"],
	"head_heavy": ["Head_Big_1", "Head_Big_2"],
	"body": ["Body_Light_1", "Body_Light_2", "Body_Light_3"],
	"body_heavy": ["Body_Big_2", "Body_Big_3"],
	"side_heavy": ["Side_Big", "Kidney_Big"],
	"kick": ["Groin_2", "Stunned", "Kidney_Light"],
}
# Blows that put someone on the ground, by where they land.
const FLOORS := {"head": ["Knocked_Down"], "body": ["Knocked_Down", "Body_Big_1"], "legs": ["Legs_1", "Legs_2"]}
const WOUND_AT := {"head": 1.6, "body": 1.2, "legs": 0.55}  # metres up the body

# How each kit fights. attacks: the cuts it varies between. kick: a shove now
# and then that goes through a guard. guard: held while blocking (a looping
# clip, or a one-off held on its last frame). parry: played when a blow is
# turned. hurt: reeling from a blow in front. fall_back / fall_forward: deaths,
# by the way the body goes. reach in town units; harm scales the blow; pace
# the moves' speed.
const KITS := {
	"sword": {"weapon": "sword", "shield": true, "idle": "Sword_Idle", "walk": "SS_Walk",
		"attacks": ["SS_Slash_1", "SS_Slash_3", "SS_Slash_4", "SS_Slash_5", "SS_Attack_3", "SS_Attack_4"],
		"kick": "SS_Kick", "guard": "SS_Block_Idle", "parry": ["SS_Block_1", "SS_Block_2", "Shield_Block"],
		"hurt": ["SS_Impact_1", "SS_Impact_2", "SS_Impact_3"],
		"fall_back": ["SS_Death_1", "Sword_Death"], "fall_forward": ["SS_Death_2", "Death_Back"],
		"reach": 0.17, "harm": 1.0, "pace": 1.15},
	"greatsword": {"weapon": "greatsword", "shield": false, "idle": "GS_Idle", "walk": "GS_Walk",
		"attacks": ["GS_Attack", "GS_Slash_1", "GS_Slash_3", "GS_Spin"],
		"kick": "GS_Kick", "guard": "GS_Block_2", "parry": ["GS_Block_1"],
		"hurt": ["GS_Impact_1", "GS_Impact_2", "GS_Impact_3"],
		"fall_back": ["GS_Death_1"], "fall_forward": ["GS_Death_2"],
		"reach": 0.21, "harm": 1.4, "pace": 1.0},
	"axe": {"weapon": "axe", "shield": false, "idle": "Axe_Idle", "walk": "Axe_Walk",
		"attacks": ["Axe_Down", "Axe_Horizontal", "Axe_Backhand", "Axe_Spin"],
		"kick": "Axe_Kick", "guard": "Axe_Block_Idle", "parry": ["Axe_Block_React"],
		"hurt": ["React_Gut", "React_Front", "React_Head"],
		"fall_back": ["Sword_Death", "SS_Death_1"], "fall_forward": ["Death_Back", "SS_Death_2"],
		"reach": 0.17, "harm": 1.2, "pace": 1.3},
	"dagger": {"weapon": "dagger", "shield": false, "idle": "Boxing", "walk": "Walk",
		"attacks": ["Punch_1", "Punch_2", "Punch_3", "Punch_Jab"],
		"kick": "Kick_Front", "guard": "", "parry": [],
		"hurt": ["React_Front", "React_Head", "Hit"],
		"fall_back": ["Death01", "Sword_Death"], "fall_forward": ["Death_Back"],
		"reach": 0.13, "harm": 0.8, "pace": 1.1},
	"fists": {"weapon": "", "shield": false, "idle": "Boxing", "walk": "Walk",
		"attacks": ["Punch_1", "Punch_2", "Punch_3", "Punch_Jab"],
		"kick": "Kick_Front", "guard": "Body_Block", "parry": ["Body_Block"],
		"hurt": ["React_Head", "React_Front", "Hit"],
		"fall_back": ["Death01", "Fall_Back_Death"], "fall_forward": ["Death_Back"],
		"reach": 0.12, "harm": 0.35, "pace": 1.1},
}
# When the blow arrives, as a fraction of each move: the moment the striking
# hand (or foot) moves fastest, measured from the clips themselves.
const BLOW_AT := {
	"SS_Slash_1": 0.40, "SS_Slash_3": 0.50, "SS_Slash_4": 0.55, "SS_Slash_5": 0.44,
	"SS_Attack_3": 0.43, "SS_Attack_4": 0.43, "SS_Kick": 0.40, "Sword_Attack": 0.49, "Sword_Attack_2": 0.45,
	"GS_Attack": 0.39, "GS_Slash_1": 0.45, "GS_Slash_3": 0.44, "GS_Spin": 0.61, "GS_Kick": 0.36,
	"Axe_Down": 0.37, "Axe_Horizontal": 0.40, "Axe_Backhand": 0.33, "Axe_Spin": 0.33, "Axe_Kick": 0.30,
	"Punch_1": 0.48, "Punch_2": 0.29, "Punch_3": 0.33, "Punch_Jab": 0.28, "Kick_Front": 0.36,
}

var node: Node3D
var people  # people.gd
var kit := "sword"
var health := 100.0
var state := "ready"  # ready | striking | blocking | dodging | staggered | down | dead
var armed := false
var _timer := 0.0
var _swing_at := -1.0
var _last := ""
var _kicking := false
var _hurt_until := 0.0  # seconds (ticks clock) until a knockdown stops showing
var threatened := false  # a foe close by: set by whoever runs the fight (control.gd)
var on_land := Callable()  # (attacker) -> void: asked to resolve a strike that just arrived


func _init(body: Node3D, p, with := "sword") -> void:
	node = body
	people = p
	kit = with


func alive() -> bool:
	return state != "dead"


func facing() -> Vector3:
	return Vector3(sin(node.rotation.y), 0, cos(node.rotation.y))


## The kit in use: the weapon drawn, or fists when it is sheathed.
func style() -> Dictionary:
	return KITS[kit if armed else "fists"]


## Badly hurt: low on health, or not long up off the ground.
func hurt() -> bool:
	return alive() and (health < WEAK or Time.get_ticks_msec() / 1000.0 < _hurt_until)


func idle_clip() -> String:
	if hurt():
		return "Injured_Idle"
	# Sword sheathed, nobody to fight: they stand as themselves, not in a boxer's guard.
	return "Idle" if not armed and not threatened else style()["idle"]


func walk_clip(running := false) -> String:
	if hurt():
		return "Injured_Walk"
	if running:
		return "Sprint" if armed else "Running"
	return style()["walk"]


func reach() -> float:
	return style()["reach"]


func draw(on: bool) -> void:
	if not alive():
		return
	armed = on
	var k: Dictionary = KITS[kit]
	if on and k["weapon"] != "":
		Weapons.arm(node, k["weapon"], k["shield"])
	else:
		Weapons.disarm(node)
	people.play(node, idle_clip(), 1.0)


## Swing (or punch, when sheathed). Varies the cut, and now and then kicks.
func strike() -> bool:
	if not alive() or state != "ready" and state != "blocking":
		return false
	var s := style()
	var pool: Array = s["attacks"].filter(func(c): return c != _last)
	var move: String = pool[randi() % pool.size()]
	_kicking = randf() < 0.15
	if _kicking:
		move = s["kick"]
	_last = move
	state = "striking"
	var length := _once(move, s["pace"])
	var at: float = length * float(BLOW_AT.get(move, 0.45)) / float(s["pace"])
	_swing_at = at
	_timer = at + FOLLOW
	return true


func block(on: bool) -> void:
	if not alive() or not state in ["ready", "blocking"] or style()["guard"] == "":
		return
	state = "blocking" if on else "ready"
	if on:
		_guard()
	else:
		people.play(node, idle_clip(), 1.0)


## Step out of the way: "left", "right" or "back". Nothing lands while you
## move; you are carried about a stride along the dodge.
func dodge(way: String) -> bool:
	if not alive() or not state in ["ready", "blocking"]:
		return false
	var clip: String = {"left": "Dodge_Left", "right": "Dodge_Right"}.get(way, "Dodge_Back")
	state = "dodging"
	_swing_at = -1.0
	var length := _once(clip, 1.5)
	_timer = minf(length / 1.5, 1.1)
	var f := facing()
	var left := Vector3(f.z, 0, -f.x)
	var dir: Vector3 = {"left": left, "right": -left}.get(way, -f)
	var go := node.create_tween()
	go.tween_property(node, "position", node.position + dir * DODGE * node.scale.x, _timer * 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	return true


## How hard this fighter's blow falls, from a base for who is striking.
func harm(base: float) -> float:
	return base * float(style()["harm"]) * (0.4 if _kicking else 1.0)


## Called by an attacker's strike: true if the blow was turned aside.
func take(attacker, damage: float) -> bool:
	if not alive() or state in ["dodging", "down"]:
		return state == "dodging"
	var from: Node3D = attacker.node
	var to_attacker := from.global_position - node.global_position
	to_attacker.y = 0
	to_attacker = to_attacker.normalized()
	var front := facing().dot(to_attacker)
	var kicked: bool = attacker._kicking
	if state == "blocking" and front > 0.3 and not kicked:
		var parry: Array = style()["parry"]
		if not parry.is_empty():
			_once(parry[randi() % parry.size()], 1.3)
			node.get_tree().create_timer(0.5).timeout.connect(func():
				if state == "blocking":
					_guard())
		return true
	var blow: float = attacker.harm(damage)
	health -= blow
	var heavy: bool = attacker._last in HEAVY or blow >= 30.0
	var zone := _zone(attacker._last, kicked)
	var bladed: bool = attacker.armed and not kicked
	var unit := node.scale.x  # world units per metre, here
	if bladed:
		var wound := node.global_position + Vector3.UP * float(WOUND_AT[zone]) * unit + to_attacker * 0.12 * unit
		Blood.spray(node.get_parent(), wound, -to_attacker, node.global_position.y, unit)
	var s: Dictionary = KITS[kit] if armed else KITS["fists"]
	if health <= 0.0:
		state = "dead"
		_swing_at = -1.0
		# Struck from the front they go over backwards; from behind, onto their face.
		var falls: Array = s["fall_back"] if front > -0.2 else s["fall_forward"]
		# Into the Dead state of their machine (motion.gd), which nothing leaves.
		people.die(node, falls[randi() % falls.size()], 1.0)
		if bladed or attacker.armed:
			var at := node.global_position
			var parent := node.get_parent()
			node.get_tree().create_timer(1.4).timeout.connect(func():
				if is_instance_valid(parent):
					Blood.pool(parent, at, -to_attacker, unit))
		return false
	_swing_at = -1.0
	if heavy and not kicked and randf() < FLOORED:
		var floors: Array = FLOORS[zone]
		_floor(floors[randi() % floors.size()])
		return false
	state = "staggered"
	# Reel by where it landed and which way it came: from behind, a stumble
	# forward; from the side, thrown that way; head-on, by head, body or legs.
	var left := Vector3(cos(node.rotation.y), 0, -sin(node.rotation.y))
	var side := left.dot(to_attacker)
	var pick: Array
	if front < -0.3:
		pick = ["Back_Head"] if zone == "head" else ["Back_Hit"]
	elif kicked:
		pick = REELS["kick"]
	elif absf(side) > 0.6:
		pick = REELS["side_heavy"] if heavy else ["React_Left" if side > 0.0 else "React_Right"]
	elif zone == "head":
		pick = REELS["head_heavy" if heavy else "head"]
	elif heavy:
		pick = REELS["body_heavy"]
	else:
		pick = REELS["body"] + s["hurt"]  # the kit's own impacts keep the weapon up
	var length := _once(pick[randi() % pick.size()], 1.2)
	_timer = minf(length / 1.2 * 0.8, 1.2)
	return false


## Where a blow from `move` lands: "head", "body" or "legs".
func _zone(move: String, kicked: bool) -> String:
	if kicked:
		return "body"
	if move in OVERHEAD:
		return "head"
	var roll := randf()
	return "head" if roll < 0.3 else "legs" if roll > 0.82 else "body"


## Advance the fighter's own clock; resolves its strike when the blow arrives.
func tick(delta: float) -> void:
	if not alive():
		return
	if _swing_at >= 0.0:
		_swing_at -= delta
		if _swing_at < 0.0 and on_land.is_valid():
			on_land.call(self)
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0 and state in ["striking", "staggered", "dodging", "down"]:
			state = "ready"
			_kicking = false
			people.play(node, idle_clip(), 1.0)


## Is this fighter in the arc of a blow from `attacker`?
func in_reach_of(attacker) -> bool:
	if not alive():
		return false
	var d: Vector3 = node.global_position - attacker.node.global_position
	d.y = 0
	return d.length() < attacker.reach() and attacker.facing().dot(d.normalized()) > ARC


## Knocked off your feet by `clip`: down, then up again, slowly, and limping
## for a while after.
func _floor(clip := "Knocked_Down") -> void:
	state = "down"
	_hurt_until = Time.get_ticks_msec() / 1000.0 + HURT_FOR
	var fall := _once(clip, 1.2) / 1.2
	_timer = fall + 8.33 / 2.2
	node.get_tree().create_timer(fall).timeout.connect(func():
		if state == "down":
			_once("Getting_Up", 2.2))


## Raise the kit's guard and keep it up.
func _guard() -> void:
	var g: String = style()["guard"]
	if g.ends_with("Idle"):
		people.play(node, g, 1.0)
	else:
		_once(g, 1.4)  # a one-off: it holds on its last frame


## Plays a move once from its start, holding its last frame when done (the
## shared clips loop for the townsfolk; these don't). Returns its length.
func _once(clip: String, speed := 1.0) -> float:
	# Through the person's state machine (motion.gd): played once, held on its
	# last frame; a dead fighter's machine refuses it.
	return people.once(node, clip, speed)
