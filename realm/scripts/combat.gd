extends RefCounted
## One fighter in a melee: the character you control or a foe. Health, a
## guard, and a few states: ready, striking, blocking, staggered, dead. A strike
## lands partway through its swing on whoever is in front within reach; a
## raised shield turned toward the blow stops it. The moves are the townsfolk's
## own Mixamo clips, so a fight looks like the rest of the world.

const REACH := 0.16  # town units: about 1.3 m, a sword's length
const ARC := 0.75  # cos of the half-angle a strike covers (about 40 degrees each side)
const SWING := 0.42  # seconds into a strike when the blade arrives
const RECOVER := 0.9  # seconds before the next strike
const STAGGER := 0.6

var node: Node3D
var people  # people.gd
var health := 100.0
var state := "ready"  # ready | striking | blocking | staggered | dead
var armed := false
var _timer := 0.0
var _swing_at := -1.0
var _alt := false
var on_land := Callable()  # (attacker) -> void: asked to resolve a strike that just arrived


func _init(body: Node3D, p) -> void:
	node = body
	people = p


func alive() -> bool:
	return state != "dead"


func facing() -> Vector3:
	return Vector3(sin(node.rotation.y), 0, cos(node.rotation.y))


func draw(on: bool) -> void:
	if not alive():
		return
	armed = on
	people.play(node, "Sword_Idle" if on else "Idle", 1.0)


func strike() -> bool:
	if not alive() or state in ["striking", "staggered"] or not armed:
		return false
	state = "striking"
	_timer = RECOVER
	_swing_at = SWING
	_alt = not _alt
	people.play(node, "Sword_Attack_2" if _alt else "Sword_Attack", 1.25)
	return true


func block(on: bool) -> void:
	if not alive() or not armed or state in ["striking", "staggered"]:
		return
	state = "blocking" if on else "ready"
	people.play(node, "Shield_Block" if on else "Sword_Idle", 1.0)


## Called by an attacker's strike: true if the blow was turned aside.
func take(from: Node3D, damage: float) -> bool:
	if not alive():
		return false
	var to_attacker := (from.global_position - node.global_position)
	to_attacker.y = 0
	if state == "blocking" and facing().dot(to_attacker.normalized()) > 0.3:
		people.play(node, "Shield_Block", 1.4)
		return true
	health -= damage
	if health <= 0.0:
		state = "dead"
		var fall := "Sword_Death" if armed else "Death01"
		people.play(node, fall, 1.0)
		# Clips are shared and loop; this one plays through once, then holds still.
		var a: AnimationPlayer = node.get_node_or_null("Anim")
		if a and a.has_animation(fall):
			a.seek(0.0, true)
			node.get_tree().create_timer(a.get_animation(fall).length * 0.97).timeout.connect(func():
				if is_instance_valid(a):
					a.pause())
		return false
	state = "staggered"
	_timer = STAGGER
	people.play(node, "Hit", 1.2)
	return false


## Advance the fighter's own clock; resolves its strike when the blade arrives.
func tick(delta: float) -> void:
	if not alive():
		return
	if _swing_at >= 0.0:
		_swing_at -= delta
		if _swing_at < 0.0 and on_land.is_valid():
			on_land.call(self)
	if _timer > 0.0:
		_timer -= delta
		if _timer <= 0.0 and state in ["striking", "staggered"]:
			state = "ready"
			people.play(node, "Sword_Idle" if armed else "Idle", 1.0)


## Is this fighter in the arc of a blow from `attacker`?
func in_reach_of(attacker) -> bool:
	if not alive():
		return false
	var d: Vector3 = node.global_position - attacker.node.global_position
	d.y = 0
	return d.length() < REACH and attacker.facing().dot(d.normalized()) > ARC
