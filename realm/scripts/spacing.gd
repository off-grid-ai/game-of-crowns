extends Node
## No two people on one spot and nobody a statue: one rule for every person in sight, whoever cast them (Mac
## 2026-11-17: "just do it once and for all"). Scenes, castles, squares and camps each place their people their own
## way; this pass is the one check after all of them, as a crowd sim's separation rule (Reynolds' boids, RVO) keeps
## any two agents apart whatever sent them there.
##
## Each beat it looks at the people anim_lod.gd has in sight that stand (their Mover not on its way):
## - one closer than people.json spacing.apart to anyone for spacing.after_s steps aside: he makes way for a walker on
##   his spot, and of two standing the later-made one moves;
## - one held in an idle clip for spacing.still_s: he shuffles a step (forward, then back toward where he first
##   stood, so he never drifts off), takes another idle and his mind, if he has one, is woken to choose again.
## - two walking in step, one inside the other: the later-made one stands spacing.give_s and lets the other on.
## Every step goes through his Mover (step_aside): routed, never set. Men in a fight or a formed block keep their
## place (their host's own rules space them: field_cells.gd, army_formation.gd).
const AnimLOD := preload("res://scripts/anim_lod.gd")
const People := preload("res://scripts/people.gd")
const Data := preload("res://scripts/data.gd")

static var APART: float = Data.num("people", "spacing.apart", 0.06)  # world units: closer than this is one spot
static var AFTER_S: float = Data.num("people", "spacing.after_s", 0.3)  # seconds two may share a spot (a pass-by)
static var STILL_S: float = Data.num("people", "spacing.still_s", 4.0)  # seconds in one idle before a shuffle
static var STEP: float = Data.num("people", "spacing.step", 0.08)  # world units of a step aside
static var BEAT_S: float = Data.num("people", "spacing.beat_s", 0.1)  # seconds between looks
static var GIVE_S: float = Data.num("people", "spacing.give_s", 0.6)  # seconds a walker stands to let one on his spot on
static var REST_S: float = Data.num("people", "spacing.rest_s", 3.0)  # seconds a man who stepped is left alone
## The idle clips: standing doing nothing. Guards and archers keep to their own stances.
const IDLE := ["Idle", "Weight_Shift", "Breathing_Idle", "Bored", "Relieved_Sigh", "Looking_Around", "Thinking",
	"Look_Away", "Standing_Idle", "Standing_Idle_2", "Arm_Stretching", "Crossed_Arms", "Drunk_Idle"]
const GUARD := ["Sword_Idle", "SS_Idle_2", "SS_Block_Idle"]
const BOW := ["Bow_Idle"]

var _t := 0.0
var _close := {}  # body instance id -> seconds sharing a spot
var _idle := {}  # body instance id -> seconds in an idle clip
var _home := {}  # body instance id -> where he first stood still (his shuffles keep near it)
var _rest := {}  # body instance id -> Time msec until which he is left alone


func _process(delta: float) -> void:
	_t += delta
	if _t < BEAT_S:
		return
	var dt := _t
	_t = 0.0
	var now := Time.get_ticks_msec()
	var stood: Array[Node3D] = []
	var still := {}  # instance ids of those standing
	var walking: Array[Node3D] = []  # on a plain walk
	var grid := {}  # Vector2i cell -> [bodies in sight]
	for id in AnimLOD.live.keys():
		var p := (AnimLOD.live[id] as WeakRef).get_ref() as Node
		var body := p.get_parent() as Node3D if p else null
		if body == null or not body.is_in_group("people") or not body.is_visible_in_tree():
			continue
		var bid := body.get_instance_id()
		var mo := People.motion(body)
		if mo == null or mo.dead():
			continue
		var c := _cell(body.global_position)
		if not grid.has(c):
			grid[c] = []
		(grid[c] as Array).append(body)  # everyone in sight: a walker on a man's spot counts too
		if not _stands(body):
			_idle.erase(bid)
			_home.erase(bid)
			var mv := body.get_node_or_null("Mover")
			if mv and mv.travels() and not mv.fighting and mv.wheel <= 0.0:
				walking.append(body)
			else:
				_close.erase(bid)
			continue
		stood.append(body)
		still[bid] = true
	for body in stood:
		var bid := body.get_instance_id()
		if not _home.has(bid):
			_home[bid] = body.global_position
		var clip := People.clip(body)
		_idle[bid] = float(_idle.get(bid, 0.0)) + dt if (clip in IDLE or clip in GUARD or clip in BOW) else 0.0
		var other := _sharing(body, grid)
		# He makes way for a walker on his spot; of two standing, the later-made one steps.
		var yields := other != null and (not still.has(other.get_instance_id()) or other.get_instance_id() < bid)
		_close[bid] = float(_close.get(bid, 0.0)) + dt if yields else 0.0
		if int(_rest.get(bid, 0)) > now:
			continue
		if float(_close[bid]) >= AFTER_S:
			_step(body, other.global_position, grid, clip)
		elif float(_idle[bid]) >= STILL_S:
			_step(body, Vector3.INF, grid, clip)
	# Two walking one route in step, one inside the other: the later-made one stands a moment and lets the other on.
	for body in walking:
		var bid := body.get_instance_id()
		var other := _sharing(body, grid)
		var behind := other != null and not still.has(other.get_instance_id()) and other.get_instance_id() < bid
		_close[bid] = float(_close.get(bid, 0.0)) + dt if behind else 0.0
		if float(_close[bid]) >= AFTER_S and int(_rest.get(bid, 0)) <= now:
			_close[bid] = 0.0
			_rest[bid] = now + int(REST_S * 1000.0)
			body.get_node("Mover").give_way(GIVE_S)
	for k in _rest.keys():
		if int(_rest[k]) <= now:
			_rest.erase(k)


static func _cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x / APART), floori(at.z / APART))


## Standing, and his to move: his Mover not on its way, not in a fight or a formed block, not carried by
## something that moves (a rider, a man on a cart).
static func _stands(body: Node3D) -> bool:
	return held(body) == ""


## Why the pass leaves a body be ("" when it is his to move): read by the motion probe beside a statue.
static func held(body: Node3D) -> String:
	var mv := body.get_node_or_null("Mover")
	if mv:
		if mv.travels():
			return "on his way"
		if mv.fighting:
			return "fighting"
		if mv.wheel > 0.0 or mv.nav == &"host":
			return "formed block"
	var up := body.get_parent()
	for _k in 3:
		if up == null:
			break
		if up.get_node_or_null("Mover") != null:
			return "carried by %s" % up.name
		up = up.get_parent()
	return ""


## Another standing body on his spot, or null.
static func _sharing(body: Node3D, grid: Dictionary) -> Node3D:
	var at := body.global_position
	var c := _cell(at)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for o in grid.get(c + Vector2i(dx, dz), []):
				if o != body and Vector2(o.global_position.x - at.x, o.global_position.z - at.z).length() < APART:
					return o
	return null


## Whether anyone standing is on `at`'s spot besides `body`.
static func _taken(at: Vector3, body: Node3D, grid: Dictionary) -> bool:
	var c := _cell(at)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			for o in grid.get(c + Vector2i(dx, dz), []):
				if o != body and Vector2(o.global_position.x - at.x, o.global_position.z - at.z).length() < APART:
					return true
	return false


## One step aside through his Mover: away from `from` (the man on his spot), or a shuffle near where he first stood
## (`from` INF). The first free spot round him, from that way; then another idle, and his mind chooses again.
func _step(body: Node3D, from: Vector3, grid: Dictionary, clip: String) -> void:
	var bid := body.get_instance_id()
	var at := body.global_position
	var home: Vector3 = _home.get(bid, at)
	var aim: float
	if from != Vector3.INF:
		aim = atan2(at.x - from.x, at.z - from.z) if Vector2(at.x - from.x, at.z - from.z).length() > 0.001 else randf() * TAU
	elif Vector2(home.x - at.x, home.z - at.z).length() > STEP * 0.5:
		aim = atan2(home.x - at.x, home.z - at.z)  # back toward where he stood
	else:
		aim = body.global_rotation.y + randf_range(-0.8, 0.8)  # a shuffle about the way he faces
	for k in 8:
		var a := aim + (k + 1) / 2 * PI / 4.0 * (1 if k % 2 == 0 else -1)
		var to := at + Vector3(sin(a), 0.0, cos(a)) * STEP
		if _taken(to, body, grid):
			continue
		_rest[bid] = Time.get_ticks_msec() + int(REST_S * 1000.0)
		_idle[bid] = 0.0
		_close[bid] = 0.0
		var mv: Node = preload("res://scripts/mover.gd").of(body)
		mv.step_aside(to, func(): _settle(body, clip))
		return


## Arrived from a step: another stance of the same kind, and his mind (if any) chooses afresh.
static func _settle(body: Node3D, was: String) -> void:
	if not is_instance_valid(body):
		return
	var kind: Array = GUARD if was in GUARD else (BOW if was in BOW else People.IDLES)
	var pick := String(kind.pick_random())
	if kind.size() > 1:
		while pick == was:
			pick = String(kind.pick_random())
	People.play(body, pick)
	var mind := body.get_node_or_null("Mind") as BTPlayer
	if mind:
		AnimLOD.wake(mind)
