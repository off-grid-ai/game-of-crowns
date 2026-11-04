extends Node3D
## The scene director: turns what just happened in Freeciv into something you
## can watch where it happened. Battles clash and leave the fallen; sacked
## towns burn while their people flee; famine sends families onto the roads;
## the King's grain goes out by wagon under escort.

var terrain: Node3D
var towns: Node3D
var _nav = preload("res://scripts/town_nav.gd").new()  # where people may stand, and the streets they walk
var _people = preload("res://scripts/people.gd").new()
const Heraldry = preload("res://scripts/heraldry.gd")
const Realistic = preload("res://scripts/realistic.gd")
var _seen := {}  # scene key -> true, so each event plays once
var _wagon: Mesh
var _sieges := {}  # city id -> {root, until}: one camp per besieged town, kept while the host stays
var _timber: StandardMaterial3D
var _engines := [preload("res://assets/castle/siege-catapult.glb"), preload("res://assets/castle/siege-trebuchet.glb")]


func _ready() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	_wagon = builder.piece_mesh("Prop_Wagon")


## Whether the towns stand: scenes are set out against their buildings, so
## none is staged while a realm just opened is still putting them up.
func _towns_up() -> bool:
	if towns == null:
		towns = get_parent().get("towns")
	return towns == null or not towns.has_method("building") or not (towns.building() or towns.towns.is_empty())


## The top node under `sys` that `n` belongs to: a scene's name, for the gate.
func sync(world: Dictionary, houses: Dictionary) -> void:
	if not _towns_up():
		get_tree().create_timer(1.0).timeout.connect(sync.bind(world, houses))
		return
	var played_battle := {}
	for s in world.get("scenes", []):
		var key := "%s:%d:%d:%d:%d" % [s["kind"], int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]
		if _seen.has(key):
			continue
		_seen[key] = true
		var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
		match String(s["kind"]):
			"battle":
				# Many deaths on one tile in one turn are one battle.
				var tile := "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s["turn"])]
				if played_battle.has(tile):
					continue
				played_battle[tile] = true
				_battle(at, houses.get(int(s.get("owner", -1)), {}), houses.get(_victor(world, s), {}))
			"sack":
				_burn(at, 45.0)
				_refugees(at, 7)
			"razed":
				_burn(at, 70.0, 2.0)
				_refugees(at, 10)
			"famine":
				_refugees(at, 5)
			"plague":
				_refugees(at, 3)
			"siege":
				var city: Dictionary = {}
				for c in world.get("cities", []):
					if int(c["id"]) == int(s["city"]):
						city = c
				var approach: Vector3 = terrain.world_pos(float(s.get("ax", s["x"])), float(s.get("ay", s["y"])))
				_siege(int(s["city"]), at, approach, int(city.get("size", 4)), int(s.get("engines", 0)), houses.get(int(s.get("owner", -1)), {}), houses.get(int(s.get("defender", -1)), {}), float(world.get("turnSeconds", 20.0)))
			"grain", "tribute":
				_convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), s["kind"] == "grain")
			"muster":
				var goal: Vector3 = terrain.world_pos(float(s.get("tx", s["x"])), float(s.get("ty", s["y"])))
				_muster(at, goal)
			"ward":
				_convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), false, "A ward for the King's court")
			"rider":
				_rider(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), String(s.get("label", "The King's word")))
			"feast":
				_feast(at, houses.get(int(s.get("owner", -1)), {}))
			"handover":
				var town := "The town"
				for c in world.get("cities", []):
					if int(c["id"]) == int(s.get("city", -1)):
						town = String(c.get("title", c["name"]))
				_handover(at, houses.get(int(s.get("from", -1)), {}), houses.get(int(s.get("to", -1)), {}), town)


## Who won a fight: the house with men standing on or next to the tile where
## the loser's died. -1 if no one is there.
func _victor(world: Dictionary, s: Dictionary) -> int:
	var best := -1
	var near := INF
	for u in world.get("units", []):
		if int(u["owner"]) == int(s.get("owner", -1)):
			continue
		var d := Vector2(float(u["x"]) - float(s["x"]), float(u["y"]) - float(s["y"])).length()
		if d <= 1.5 and d < near:
			near = d
			best = int(u["owner"])
	return best


func _rng(at: Vector3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(at) + Time.get_ticks_msec()
	return r


## Where a person may stand nearest `p`: on the ground and in no building
## (town_nav.gd, the realm's one answer). Every person or horse a scene places
## or moves is set down through here; things (standards, fires, wagons' dust)
## use _ground.
func _stand(p: Vector3, body := 0.0) -> Vector3:
	if towns == null:
		towns = get_parent().get("towns")
	_nav.terrain = terrain
	return _nav.stand(towns, p, body)


## A horse is set down with its whole body clear, nose to tail.
const HORSE_BODY := 0.17


## The way a scene's people go from one place to another: through a town's
## streets, never through its houses, and over open land between.
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	_stand(from)  # finds the towns and the ground
	return _nav.route(towns, from, to)


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


# --- arms ----------------------------------------------------------------------

const Horse := preload("res://scripts/horse.gd")
const SWORD := preload("res://assets/props/Sword_Bronze.gltf")
const SHIELD := preload("res://assets/props/Shield_Wooden.gltf")
# Where a weapon sits in the hand, in the hand bone's own space (metres).
static var SWORD_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)).scaled(Vector3.ONE * 0.8), Vector3(0, 0.08, 0.02))
static var SPEAR_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), Vector3(0, 0.08, 0.02))
static var SHIELD_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)).scaled(Vector3.ONE * 0.9), Vector3(0, 0.06, 0))
const DEATHS := ["Death01", "Death_Front", "Death_Back", "Sword_Death"]


## A company's standard as its bearer carries it, beside him and about 0.4
## world units tall (a man stands 0.22), whatever scale the bearer is drawn at:
## a man on foot is scaled to the towns, a horse is not.
const CARRIED := 0.4
static func carried_standard(bearer: Node3D, house: Dictionary, color: Color) -> Node3D:
	var k := maxf(bearer.global_transform.basis.get_scale().y if bearer.is_inside_tree() else bearer.scale.y, 0.001)
	var b: Node3D = Heraldry.standard(house, color, CARRIED / k)
	b.position = Vector3(0.042, 0, -0.012) / k
	bearer.add_child(b)
	return b


## Puts arms in a soldier's hands, held on the hand bones so they swing with
## every move: "sword" (sword and shield), "spear" (spear and shield), "lance"
## (a knight's shield; the lance is the horse's to carry, see horse.gd), or
## "bow" (archers keep their hands free; there is no bow model yet).
static func arm(person: Node3D, kit: String) -> void:
	var skel: Skeleton3D = person.get_node_or_null("Armature/GeneralSkeleton")
	if skel == null or kit == "bow":
		return
	_hold(skel, "LeftHand", SHIELD.instantiate(), SHIELD_GRIP)
	if kit == "lance":
		var h: Node = person.get_meta("mounted", null)
		if h:
			h.bear_lance()
		return
	_hold(skel, "RightHand", SWORD.instantiate() if kit == "sword" else _spear(), SWORD_GRIP if kit == "sword" else SPEAR_GRIP)


static func _hold(skel: Skeleton3D, bone: String, item: Node3D, grip: Transform3D) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	skel.add_child(at)
	item.transform = grip
	at.add_child(item)


## An ash shaft about 2.4 m long with a bronze blade for its head, held a
## third of the way up.
static func _spear() -> Node3D:
	var s := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.014
	cyl.bottom_radius = 0.016
	cyl.height = 2.4
	cyl.radial_segments = 6
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.18)
	wood.roughness = 0.9
	shaft.material_override = wood
	shaft.position.y = 0.4
	s.add_child(shaft)
	var head: Node3D = SWORD.instantiate()
	head.scale = Vector3.ONE * 0.22
	head.position.y = 1.62
	s.add_child(head)
	return s


## Scales a model so it stands `height` tall, measured through its own node
## transforms (an armature's import scale included), before it is in the tree.
static func _fit_static(n: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (mi as Node3D).transform
		var up: Node = mi.get_parent()
		while up != n and up is Node3D:
			xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		n.scale = Vector3.ONE * (height / box.size.y)


# --- battle -----------------------------------------------------------------------

## A pitched battle where Freeciv says men died, staged like film. The losing
## house (team 0) holds a shield wall: swords and locked shields in front,
## spears over their shoulders, archers behind. The victors (team 1) form
## under their banner while their captain shouts them on, advance at a walk
## under the archers' arrows, then charge home as their knights gallop round the
## end of the wall into its flank. Front-rank men duel the man opposite; men fall, those behind step
## up. The defenders' standard-bearer goes down, the banner falls, and the
## wall breaks and scatters. The victors cheer under their own standard.
const RANKS := 3
const FILES := 9
const GAP := 0.2  # between files: about 1.7 m, room for each pair to fight
const ROW := 0.2  # between ranks: about 1.7 m
const REACH := 0.11  # half the distance between two duelists: 1.8 m apart
const KNIGHTS := 5
const FIELD := 3.4  # how far the fight reaches from its centre: lines, the attackers' approach, the knights' wing

## Camera beats for whoever holds the camera (the director, or a shot):
## where to look, from how far, and from which side.
signal framing(pos: Vector3, dist: float, yaw: float)


func _battle(at: Vector3, loser: Dictionary, victor := {}) -> void:
	var root := Node3D.new()
	root.name = "Battle"
	add_child(root)
	var r := _rng(at)
	var lost := Color.from_string(String(loser.get("color", "#777")), Color.GRAY)
	var won := Color.from_string(String(victor.get("color", "#7f2b26")), Color(0.5, 0.17, 0.15))
	# Two houses in like colours (or victors unknown, in blood red, against a red
	# house): the victors go in steel blue, so you can tell the sides apart.
	if absf(wrapf(lost.h - won.h, -0.5, 0.5)) < 0.08 and lost.s > 0.25 and won.s > 0.25:
		won = Color(0.22, 0.3, 0.46)
	var cols := [lost.lerp(Color.WHITE, 0.3), won.lerp(Color.WHITE, 0.15)]
	# Battles are fought on open ground: out past the town, off its roads and
	# fields, on land flat enough to hold a line. No trees stand in the fight.
	# The field is chosen against the towns as they stand: while they are
	# still going up (a realm just opened), wait for them.
	if not _towns_up():
		root.queue_free()
		get_tree().create_timer(0.5).timeout.connect(_battle.bind(at, loser, victor))
		return
	at = _battlefield(at)
	if at == Vector3.INF:
		root.queue_free()
		return  # no open ground near: the battle is told, not shown
	terrain.clear_around(at, FIELD)
	# The lines meet across the view, so you watch the clash from the side.
	var dir := Vector3(cos(r.randf() * TAU), 0, 0)
	dir.z = sqrt(1.0 - dir.x * dir.x)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		dir = Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	# One side of the field for the whole battle: moving round it puts houses
	# and trees between you and the fighting.
	var view_yaw := atan2(side.x, side.z) + 0.35
	# The camera watches low across the field from that side: fell the trees
	# between it and the fight, in a cone opening toward where it stands.
	var toward_cam := Vector3(sin(view_yaw), 0, cos(view_yaw))
	for k in 6:
		terrain.clear_around(at + toward_cam * (FIELD + k * 1.2), 1.4 + k * 0.35)
	var teams := [[], []]
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		for rank in RANKS:
			for file in FILES:
				# Where this man will stand once the lines meet. The wall holds
				# its ground a little forward; the attackers start well back.
				var slot: Vector3 = at - face * (REACH + rank * ROW) + side * ((file - (FILES - 1) / 2.0) * GAP)
				slot += side * r.randf_range(-0.015, 0.015) - face * r.randf_range(0.0, 0.02)
				var f: Node3D = _people.make(r, "soldier", cols[team], "adult")
				var back := 0.25 if team == 0 else 1.5
				f.position = _stand(slot - face * back)
				f.rotation.y = atan2(face.x, face.z)
				root.add_child(f)
				var kit := "sword"
				if team == 0 and rank == 1:
					kit = "spear"
				elif team == 0 and rank == 2:
					kit = "bow"
				arm(f, kit)
				_people.play(f, "Bow_Idle" if kit == "bow" else "Sword_Idle", r.randf_range(0.9, 1.1))
				teams[team].append({"node": f, "rank": rank, "file": file, "face": face, "slot": slot, "alive": true, "engaged": false, "kit": kit})
	# Each side's standard, carried by a bearer behind the middle of its line.
	var bearers := []
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		var p: Vector3 = at - face * (REACH + RANKS * ROW + (0.3 if team == 0 else 1.6))
		var bearer: Node3D = _people.make(r, "soldier", cols[team], "adult")
		bearer.position = _stand(p)
		bearer.rotation.y = atan2(face.x, face.z)
		root.add_child(bearer)
		arm(bearer, "bow")
		_people.play(bearer, "Sword_Idle")
		var house: Dictionary = loser if team == 0 else victor
		# A standard needs its house's arms; men of no known house fight without one.
		var flag: Node3D = _standard(root, p + side * 0.06, cols[team], face, house)
		bearers.append({"node": bearer, "flag": flag, "face": face})
	var knights := _flank_company(root, at, dir, side, cols[1], r)
	framing.emit(_ground(at), 5.5, view_yaw)
	# 1. Formed up (0-3 s): the attackers' captain shouts them on.
	var captain: Dictionary = teams[1][FILES / 2]
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(func():
		_people.play(captain["node"], "Yelling", 1.0)
		for m in teams[0]:
			if m["rank"] == 0:
				_people.play(m["node"], "Shield_Block", r.randf_range(0.9, 1.1)))
	tw.tween_interval(2.2)
	# 2. The advance (3-8 s) at a walk, in step, under the archers' arrows;
	# the wall closes up and braces behind its shields.
	tw.tween_callback(func():
		_advance(teams[1], 0.0, 5.0, 0.45, "Walk", r)
		for m in teams[0]:
			if m["rank"] < 2:
				_walk_to(m, m["slot"], 2.5, "Walk", "Shield_Block" if m["rank"] == 0 else "Sword_Idle", r)
		_follow(bearers[1], 1.15, 7.0, r))
	for v in 3:
		tw.tween_callback(func(): _arrows(root, teams[0], teams[1], r))
		tw.tween_interval(1.7)
	# 3. The charge (8-10 s): the horn, and they run the last stretch.
	tw.tween_callback(func():
		_people.play(captain["node"], "Yelling", 1.2)
		_advance(teams[1], 0.0, 2.0, 0.0, "Sprint", r)
		# Toward the wing, where the knights are wheeling in on the wall's end.
		framing.emit(_ground(at + side * 0.6), 3.4, view_yaw))
	tw.tween_interval(2.1)
	# 4. The clash (10-21 s): front pairs duel; men fall, those behind step up;
	# the knights hit the open end of the wall.
	tw.tween_callback(func():
		_dust(root, _ground(at) + Vector3(0, 0.01, 0), side, FILES * GAP)
		for team in teams:
			for m in team:
				if m["rank"] == 0:
					m["engaged"] = true
					_people.play(m["node"], "Sword_Attack" if team == teams[1] else "Shield_Block", r.randf_range(0.85, 1.15))
		framing.emit(_ground(at), 2.8, view_yaw))
	_brace(teams, 12.0, r)
	_charge_flank(knights, teams[0], at, dir, side, 8.0, r)
	for beat in 11:
		tw.tween_interval(1.0)
		tw.tween_callback(func():
			# The losing side falls three times as often.
			if r.randf() < 0.75:
				_fall(teams[0], r)
			if r.randf() < 0.25:
				_fall(teams[1], r)
			for team in teams:
				for m in team:
					if m["alive"] and m["engaged"]:
						_duel_step(m, r, team == teams[0]))
	# 5. The rout (21 s): the standard-bearer is cut down and the banner goes
	# over; the beaten turn and run; the victors chase a few paces, then cheer
	# under their standard.
	tw.tween_callback(func():
		_die(bearers[0]["node"], "Death_Back", r)
		_drop_banner(bearers[0]["flag"], bearers[0]["face"])
		for m in teams[0]:
			if not m["alive"]:
				continue
			var n: Node3D = m["node"]
			var away: Vector3 = (-m["face"] + side * r.randf_range(-0.7, 0.7)).normalized()
			n.rotation.y = atan2(away.x, away.z)
			_people.play(n, "Sprint", r.randf_range(1.0, 1.2))
			_walk(n, n.position + away * r.randf_range(2.0, 3.0), r.randf_range(5.0, 7.0), true)
		for m in teams[1]:
			if not m["alive"]:
				continue
			var n: Node3D = m["node"]
			if m["rank"] == 0 and r.randf() < 0.6:
				_walk_to(m, n.position + m["face"] * r.randf_range(0.3, 0.6), 1.5, "Sprint", "Cheering", r)
			else:
				_people.play(n, "Cheering" if r.randf() < 0.6 else "Yelling", r.randf_range(0.9, 1.1))
		_follow(bearers[1], 0.5, 2.0, r)
		framing.emit(_ground(at + dir * 0.3), 3.4, view_yaw))
	tw.tween_interval(5.0)
	tw.tween_callback(func():
		for m in teams[1]:
			if m["alive"]:
				_people.play(m["node"], "Sword_Idle", 1.0))
	# 6. The field (afterwards): the fallen stay a minute.
	tw.tween_interval(65.0)
	tw.tween_callback(root.queue_free)


## Moves each living soldier toward his slot, stopping `short` before it, over
## about `secs` from `start`. The ranks walk in step, each man a beat apart, so
## no line moves like a single block.
func _advance(team: Array, start: float, secs: float, short: float, anim: String, r: RandomNumberGenerator) -> void:
	var phase := r.randf()
	for m in team:
		var delay: float = start + r.randf_range(0.0, 0.25) + m["rank"] * 0.12
		var n: Node3D = m["node"]
		var tw := n.create_tween()
		tw.tween_interval(delay)
		tw.tween_callback(func():
			if not m["alive"]:
				return
			_in_step(n, anim, phase)
			var from := n.position
			var to: Vector3 = m["slot"] - m["face"] * short
			var mt := n.create_tween()
			mt.tween_method(func(k: float):
				if is_instance_valid(n) and m["alive"]:
					n.position = _stand(from.lerp(to, k)), 0.0, 1.0, secs * r.randf_range(0.95, 1.03)))


## Plays a move with everyone at the same point in it: a rank marching in step,
## or drilling as one.
func _in_step(n: Node3D, anim_name: String, phase: float, speed := 1.0) -> void:
	n.set_meta("tempo", 1.0)
	_people.play(n, anim_name, speed)
	var ap: AnimationPlayer = n.get_node_or_null("Anim")
	if ap and ap.has_animation(anim_name):
		ap.seek(phase * ap.get_animation(anim_name).length, true)


## One man walks or runs to a spot, facing the way he goes, then takes up `then`.
func _walk_to(m: Dictionary, to: Vector3, secs: float, anim: String, then: String, r: RandomNumberGenerator) -> void:
	var n: Node3D = m["node"]
	var from := n.position
	_people.play(n, anim, r.randf_range(0.9, 1.1))
	var mt := n.create_tween()
	mt.tween_method(func(k: float):
		if is_instance_valid(n) and m["alive"]:
			n.position = _stand(from.lerp(to, k)), 0.0, 1.0, secs)
	mt.tween_callback(func():
		if m["alive"]:
			_people.play(n, then, r.randf_range(0.9, 1.1)))


## A duelist's footwork between blows: a cut, a second cut, or a shield raised
## against the man opposite, with a step in, back or aside.
func _duel_step(m: Dictionary, r: RandomNumberGenerator, wall := false) -> void:
	var n: Node3D = m["node"]
	var face: Vector3 = m["face"]
	var across := Vector3(-face.z, 0, face.x)
	var home: Vector3 = m["slot"]
	var to: Vector3 = home + face * r.randf_range(-0.04, 0.03) + across * r.randf_range(-0.025, 0.025)
	var mt := n.create_tween()
	mt.tween_property(n, "position", _stand(to), r.randf_range(0.35, 0.6)).set_trans(Tween.TRANS_SINE)
	var roll := r.randf()
	var move := "Sword_Attack" if roll < 0.4 else ("Sword_Attack_2" if roll < 0.7 else "Shield_Block")
	if wall and roll < 0.25:
		move = "Shield_Block"
	if m["kit"] == "bow":
		move = "Sword_Attack"
	if roll > 0.93:
		move = "Hit"
	_people.play(n, move, r.randf_range(0.85, 1.2))


## A standard-bearer walks forward `dist` behind his line over `secs`, his banner with him.
func _follow(b: Dictionary, dist: float, secs: float, r: RandomNumberGenerator) -> void:
	var n: Node3D = b["node"]
	var to: Vector3 = n.position + b["face"] * dist
	_people.play(n, "Walk", r.randf_range(0.9, 1.0))
	var flag: Node3D = b["flag"]
	var off: Vector3 = flag.position - n.position if flag else Vector3.ZERO
	var tw := n.create_tween()
	tw.tween_method(func(k: float):
		if is_instance_valid(n) and not n.has_meta("dead"):
			var p := _stand(n.position.lerp(to, k * 0.2))
			n.position = p
			if flag:
				flag.position = _ground(p + off), 0.0, 1.0, secs)
	tw.tween_callback(func():
		if not n.has_meta("dead"):
			_people.play(n, "Sword_Idle", 1.0))


## The ranks behind hold their places through the fight: shields up in the
## second rank of the wall, spears thrusting over the front men's shoulders,
## the rest braced, each in his own file until the man in front falls.
func _brace(teams: Array, at_time: float, r: RandomNumberGenerator) -> void:
	var tw := create_tween()
	tw.tween_interval(at_time)
	tw.tween_callback(func():
		for team in teams:
			for m in team:
				if m["alive"] and not m["engaged"] and m["kit"] != "bow":
					_people.play(m["node"], "Sword_Attack" if m["kit"] == "spear" else "Shield_Block", r.randf_range(0.8, 1.0)))


func _fall(team: Array, r: RandomNumberGenerator) -> void:
	var front := team.filter(func(m): return m["alive"] and m["engaged"])
	if front.is_empty():
		return
	var m: Dictionary = front[r.randi() % front.size()]
	m["alive"] = false
	_die(m["node"], DEATHS[r.randi() % DEATHS.size()], r)
	# The man behind steps over the body into the gap, at his own pace.
	for back in team:
		if back["alive"] and not back["engaged"] and back["file"] == m["file"] and back["rank"] > 0:
			back["rank"] -= 1
			back["engaged"] = true
			# He stands beside the body, not on it: to one side of the file, then
			# the other, so up to three dead lie apart (files are 1.7 m wide).
			var across := Vector3(-back["face"].z, 0, back["face"].x)
			var home: Vector3 = m.get("home", m["slot"])
			var steps: int = m.get("stepped", 0) + 1
			back["home"] = home
			back["stepped"] = steps
			back["slot"] = home + across * (0.07 if steps % 2 == 1 else -0.07)
			var mt: Tween = back["node"].create_tween()
			mt.tween_interval(r.randf_range(0.2, 0.8))
			mt.tween_callback(func(): _walk_to(back, back["slot"], 0.8, "Walk", "Sword_Attack", r))
			break


## A man goes down and stays down: the death plays once and holds its last frame.
func _die(n: Node3D, how: String, r: RandomNumberGenerator) -> void:
	n.set_meta("dead", true)
	var ap: AnimationPlayer = n.get_node_or_null("Anim")
	if ap == null or not ap.has_animation(how):
		return
	ap.get_animation(how).loop_mode = Animation.LOOP_NONE
	ap.speed_scale = r.randf_range(0.9, 1.1)
	ap.play(how, 0.1)


## Archers loose a volley: an arrow from each living archer arcs onto the
## advancing ranks, and now and then one finds its man.
func _arrows(root: Node3D, archers_team: Array, targets: Array, r: RandomNumberGenerator) -> void:
	for m in archers_team:
		if not m["alive"] or m["kit"] != "bow":
			continue
		var n: Node3D = m["node"]
		var tw := n.create_tween()
		tw.tween_interval(r.randf_range(0.0, 0.3))
		tw.tween_callback(func(): _people.play(n, "Bow_Draw", 1.2))
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			if not m["alive"]:
				return
			_people.play(n, "Bow_Shoot", 1.0)
			var mark: Dictionary = targets[r.randi() % targets.size()]
			var land: Vector3 = mark["node"].position + Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12))
			_arrow(root, n.position + Vector3(0, 0.17, 0), land, r)
			if mark["alive"] and mark["rank"] > 0 and r.randf() < 0.08:
				mark["alive"] = false
				var hit: Tween = mark["node"].create_tween()
				hit.tween_interval(1.1)
				hit.tween_callback(func(): _die(mark["node"], "Death_Front", r)))
		tw.tween_interval(0.5)
		tw.tween_callback(func():
			if m["alive"] and not m["engaged"]:
				_people.play(n, "Bow_Idle", 1.0))


var _arrow_mesh: BoxMesh


func _arrow(root: Node3D, from: Vector3, to: Vector3, r: RandomNumberGenerator) -> void:
	if _arrow_mesh == null:
		_arrow_mesh = BoxMesh.new()
		_arrow_mesh.size = Vector3(0.0025, 0.0025, 0.09)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.2, 0.15)
		_arrow_mesh.material = mat
	var a := MeshInstance3D.new()
	a.mesh = _arrow_mesh
	root.add_child(a)
	var top := from.distance_to(to) * 0.35
	var path := func(t: float) -> Vector3:
		var p := from.lerp(to, t)
		p.y += top * 4.0 * t * (1.0 - t)
		return p
	var tw := a.create_tween()
	tw.tween_method(func(t: float):
		var p: Vector3 = path.call(t)
		var q: Vector3 = path.call(minf(t + 0.02, 1.0))
		a.position = p
		if q.distance_to(p) > 0.0001:
			a.look_at(q, Vector3.UP), 0.0, 1.0, r.randf_range(1.0, 1.2))
	# Arrows that miss stand in the ground a while.
	tw.tween_interval(6.0)
	tw.tween_callback(a.queue_free)


## The victors' knights: horsemen waiting on open ground out on the wing, well
## behind their own line (the victors form on the -dir side), to walk up during
## the advance.
func _flank_company(root: Node3D, at: Vector3, dir: Vector3, side: Vector3, col: Color, r: RandomNumberGenerator) -> Array:
	var knights := []
	for i in KNIGHTS:
		var h: Node3D = Horse.new(r.randi() % 5)
		root.add_child(h)
		h.mount(_people.make(r, "soldier", col, "adult"))
		arm(h.rider, "lance")
		var wing: Vector3 = at + side * ((FILES / 2.0) * GAP + 0.55 + (i / 2) * 0.24) - dir * ((i % 2) * 0.22)
		h.position = _stand(wing - dir * (REACH + RANKS * ROW + 1.8), HORSE_BODY)
		h.rotation.y = atan2(dir.x, dir.z)
		knights.append({"node": h, "wing": wing, "alive": true})
	return knights


## The knights walk up behind the line during the advance; at the horn their
## captain's horse rears, and they gallop round the end of the wall and ride
## into its flank. The men there are ridden down, and a horse or two falls.
func _charge_flank(knights: Array, wall: Array, at: Vector3, dir: Vector3, side: Vector3, start: float, r: RandomNumberGenerator) -> void:
	# The open end of the losers' wall (they stand on the +dir side).
	var flank: Vector3 = at + dir * (REACH + ROW) + side * ((FILES / 2.0) * GAP + 0.1)
	for i in knights.size():
		var k: Dictionary = knights[i]
		var h: Node3D = k["node"]
		var poised: Vector3 = k["wing"] - dir * (REACH + RANKS * ROW + 0.4)
		# Out wide past the wall's end, wheel in onto its flank, and ride on through.
		var wide: Vector3 = flank + side * (0.55 + (i % 2) * 0.15) - dir * 0.2
		var into: Vector3 = flank - side * (0.25 + (i / 2) * 0.12) + dir * ((i % 2) * 0.14)
		var through: Vector3 = into - side * 0.6 + dir * 0.15
		var curve := Curve3D.new()
		curve.add_point(poised)
		curve.add_point(wide, (poised - wide) * 0.4, (into - wide) * 0.35)
		curve.add_point(into)
		var length := curve.get_baked_length()
		var tw := h.create_tween()
		# Up at a walk during the advance (3-7.5 s).
		var from: Vector3 = h.position
		tw.tween_interval(3.0 + r.randf_range(0.0, 0.3))
		tw.tween_method(func(t: float): h.position = _stand(from.lerp(poised, t), HORSE_BODY), 0.0, 1.0, 4.4)
		tw.tween_interval(start - 7.7 + i * 0.15)
		if i == 0:
			tw.tween_callback(h.rear)
			tw.tween_interval(1.2)
		# The charge: off at a canter, lances coming down, into a gallop.
		tw.tween_method(func(t: float):
			var p := curve.sample_baked(t * length)
			var q := curve.sample_baked(minf(t + 0.02, 1.0) * length)
			h.position = _stand(p, HORSE_BODY)
			if q.distance_to(p) > 0.0001:
				h.rotation.y = atan2(q.x - p.x, q.z - p.z), 0.0, 1.0, length / Horse.GALLOP * 1.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			# The men on the end of the wall are ridden down.
			var near := wall.filter(func(w): return w["alive"] and w["node"].global_position.distance_to(h.global_position) < 0.3)
			for w in near.slice(0, 2):
				w["alive"] = false
				_die(w["node"], "Death_Back", r)
			# A horse or two is brought down in the press, its rider thrown.
			if i % 3 == 1 and r.randf() < 0.75:
				k["alive"] = false
				h.fall()
				var thrown: Node3D = h.dismount()
				if thrown:
					thrown.global_position = _stand(thrown.global_position)
					_die(thrown, "Death_Front", r))
		# The rest ride on through the broken flank and slow to a walk.
		tw.tween_method(func(t: float):
			if k["alive"]:
				h.position = _stand(into.lerp(through, t), HORSE_BODY), 0.0, 1.0, 2.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## A standard planted behind a line or at a muster: a little taller than one carried.
const PLANTED := 0.45


func _standard(root: Node3D, p: Vector3, color: Color, face: Vector3, house := {}) -> Node3D:
	var b: Node3D = Heraldry.standard(house, color, PLANTED)
	b.position = _ground(p)
	b.rotation.y = atan2(face.x, face.z)
	root.add_child(b)
	return b


## A standard goes over: it sways, then topples backward from the line and
## lies on the field. `face` is the way its line faced.
func _drop_banner(b: Node3D, face := Vector3.ZERO) -> void:
	# The cloth turns to face you about its pole while it stands; once it falls
	# it must go down with the pole, so it gets a cloth of its own that doesn't.
	var cloth: MeshInstance3D = b.get_node_or_null("Banner")
	if cloth and cloth.material_override is BaseMaterial3D:
		var m: BaseMaterial3D = cloth.material_override.duplicate()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		cloth.material_override = m
	var tw := b.create_tween()
	if face == Vector3.ZERO:
		tw.tween_property(b, "rotation:x", deg_to_rad(80), 1.2).set_ease(Tween.EASE_IN)
		return
	# Topple about the axis along the line, away from the fighting.
	var axis := Vector3(-face.z, 0, face.x).normalized()
	var start := b.transform.basis
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.0, 0.12, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.12, 0.04, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.04, 1.0, 1.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 1.0, 0.96, 0.15)


func _dust(root: Node3D, p: Vector3, along: Vector3, width: float) -> void:
	# A thin haze kicked up along the line where the ranks meet, low and faint.
	var d := _puffs(Color(0.58, 0.52, 0.42, 0.07), 8, 1.6, 0.04, 0.09)
	d.direction = Vector3(0, 0.2, 0)
	d.spread = 70
	d.initial_velocity_min = 0.02
	d.initial_velocity_max = 0.06
	d.gravity = Vector3(0, -0.01, 0)
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = Vector3(width * 0.5, 0.01, 0.05)
	d.position = p
	d.rotation.y = atan2(along.x, along.z) - PI / 2
	d.emitting = true
	root.add_child(d)
	var tw := d.create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(func(): d.emitting = false)


# --- sieges ------------------------------------------------------------------------------

## A host at a town's walls: its camp spreads in an arc on the side it came
## from, engines throw stones over the walls, assault parties rush the walls
## and fall back, and the defenders hold the line. The camp stays while the
## bridge keeps reporting the siege, and breaks up a turn and a half after.
func _siege(id: int, at: Vector3, approach: Vector3, size: int, engines: int, foe: Dictionary, held: Dictionary, turn_secs: float) -> void:
	if _sieges.has(id) and is_instance_valid(_sieges[id]["root"]):
		_sieges[id]["until"] = Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5
		return
	if not _towns_up():
		# Pitched once the town stands; until then, where it will be.
		_sieges[id] = {"root": null, "until": 0.0, "front": _ground(approach)}
		get_tree().create_timer(1.0).timeout.connect(_siege.bind(id, at, approach, size, engines, foe, held, turn_secs))
		return
	var root := Node3D.new()
	root.name = "Siege"
	add_child(root)
	_sieges[id] = {"root": root, "until": Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5}
	var r := _rng(at)
	var foe_col := Color.from_string(String(foe.get("color", "#7a2222")), Color.DARK_RED).lerp(Color.WHITE, 0.2)
	var held_col := Color.from_string(String(held.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.3)
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0)
	var wall := reach + 0.35
	var out := Vector3(approach.x - at.x, 0, approach.z - at.z)
	var want := atan2(out.z, out.x) if out.length() > 0.01 else r.randf() * TAU
	var camp_r := wall + 1.3
	var base := _camp_side(at, want, wall, camp_r)
	var arc := func(a: float, rad: float) -> Vector3:
		return _ground(at + Vector3(cos(base + a), 0, sin(base + a)) * rad)
	_sieges[id]["front"] = arc.call(0.0, wall + 0.6)
	# Seen from behind the camp, on the open ground it was pitched on, over the
	# engines and companies to the walls.
	framing.emit(_sieges[id]["front"], 4.5, PI / 2 - base)
	# The camp: companies under their standards.
	for g in 5:
		var a := (g - 2) * 0.32 + r.randf_range(-0.06, 0.06)
		var c: Vector3 = arc.call(a, camp_r)
		var inward := (at - c).normalized()
		inward.y = 0
		_standard(root, c - inward * 0.45, foe_col, inward, foe)
		for i in 5:
			var p := c + Vector3(r.randf_range(-0.35, 0.35), 0, r.randf_range(-0.35, 0.35))
			if not _footing(p):
				continue
			var f: Node3D = _people.make(r, "soldier", foe_col, "adult")
			f.position = _stand(p)
			f.rotation.y = atan2(inward.x, inward.z) + r.randf_range(-0.6, 0.6)
			root.add_child(f)
			arm(f, "spear" if i % 2 == 0 else "sword")
			_people.play(f, "Sword_Idle" if r.randf() < 0.6 else "Idle", r.randf_range(0.8, 1.1))
	# The engines, set back behind the camp line, and their stones.
	for e in clampi(maxi(engines, 1), 1, 3):
		var a := (e - 1) * 0.45 + r.randf_range(-0.05, 0.05)
		var ep: Vector3 = arc.call(a, camp_r + 0.75)
		var engine: Node3D = _engines[e % 2].instantiate()
		root.add_child(engine)
		_fit(engine, 0.7)
		_weather(engine)
		engine.position = ep
		var to_town := at - ep
		engine.rotation.y = atan2(to_town.x, to_town.z) + PI
		_volley(root, ep + Vector3(0, 0.35, 0), at, reach * 0.8, r, 4.0 + e * 1.3)
	# The defenders on the walls, facing out toward the host: archers and
	# spearmen turn about.
	var archers := []
	for i in 9:
		var a := (i - 4) * 0.13
		var p: Vector3 = _stand(arc.call(a, wall - 0.3))
		if not _footing(p):
			continue
		var f: Node3D = _people.make(r, "soldier", held_col, "adult")
		f.position = p
		var face := (p - at).normalized()
		f.rotation.y = atan2(face.x, face.z)
		root.add_child(f)
		var bow := i % 2 == 0
		arm(f, "bow" if bow else "spear")
		_people.play(f, "Bow_Idle" if bow else "Sword_Idle", r.randf_range(0.9, 1.1))
		if bow:
			archers.append({"node": f, "alive": true, "kit": "bow", "engaged": false})
	# Assault parties rush the walls in turn under the archers' arrows, fight
	# there, and fall back.
	var parties := []
	for party in 2:
		parties.append(_assault(root, arc, (party - 0.5) * 0.5, camp_r, wall, foe_col, r, 3.0 + party * 6.0))
	var loose := Timer.new()
	loose.wait_time = 2.6
	loose.autostart = true
	loose.timeout.connect(func():
		var marks := []
		for men in parties:
			marks.append_array(men.filter(func(m): return m.get("out", false) and m["alive"]))
		if not marks.is_empty():
			_arrows(root, archers, marks, r))
	root.add_child(loose)
	_siege_watch(id)


## The side a host camps on: open, dry, gentle ground, as near as possible to
## the way it came. Each direction is scored by how far it turns from that way
## and by the water and slope along its arc.
func _camp_side(at: Vector3, want: float, wall: float, camp_r: float) -> float:
	var best := want
	var best_score := INF
	for i in 24:
		var a := want + TAU * i / 24.0
		var score := absf(wrapf(a - want, -PI, PI)) * 0.6
		for k in 5:
			var aa := a + (k - 2) * 0.3
			var d := Vector3(cos(aa), 0, sin(aa))
			var p := at + d * camp_r
			if not terrain.is_land(p.x, p.z):
				score += 3.0
			score += absf(terrain.height_at(p.x, p.z) - terrain.height_at(at.x + d.x * wall, at.z + d.z * wall)) * 1.5
		if score < best_score:
			best_score = score
			best = a
	return best


## Whether a man could stand here: dry land, not a crag.
func _footing(p: Vector3) -> bool:
	if not terrain.is_land(p.x, p.z):
		return false
	return absf(terrain.height_at(p.x + 0.15, p.z) - terrain.height_at(p.x - 0.15, p.z)) < 0.12 and absf(terrain.height_at(p.x, p.z + 0.15) - terrain.height_at(p.x, p.z - 0.15)) < 0.12


## Open ground for a pitched battle, as near `near` as there is. A field is
## never in or beside a town or a farmstead: one whose fighting ground (FIELD
## and a margin) comes within any town's reach or near a farm is refused
## outright, and the search widens ring by ring until a clear one is found.
## Among the clear fields of the nearest ring, the driest, flattest and most
## open wins. Vector3.INF if the land has none (no battle is staged then).
func _battlefield(near: Vector3) -> Vector3:
	var main := get_parent()
	if towns == null:
		towns = main.get("towns")
	var roads = main.get("roads")
	var country = main.get("countryside")
	var span := RINGS * 0.8 + FIELD
	var walls := []  # [centre, reach] of every town that could touch a field
	if towns:
		for id in towns.towns:
			var t: Node3D = towns.towns[id]["node"]
			var reach := float(t.get_meta("reach", 6.0)) if is_instance_valid(t) else 0.0
			if reach > 0.0 and _flat_gap(t.global_position, near) < span + reach:
				walls.append([t.global_position, reach])
	var farms := []
	for f in (country.get("_sites") if country else []):
		if _flat_gap(f["at"], near) < span + FARM_CLEAR:
			farms.append(f["at"])
	for ring in RINGS:
		var best := Vector3.INF
		var best_score := INF
		var n := maxi(1, ring * 8)
		for i in n:
			var a := TAU * i / n
			var p := _ground(near + Vector3(cos(a), 0, sin(a)) * ring * 0.8)
			if not _clear_field(p, walls, farms):
				continue
			var score := _field_cost(p, roads)
			if score < best_score:
				best_score = score
				best = p
		if best != Vector3.INF:
			return best
	return Vector3.INF


## How far out (in rings 0.8 apart) the field is looked for.
const RINGS := 40
## How far a field's edge keeps from a town's reach, and its centre from a farmstead.
const TOWN_CLEAR := 0.4
const FARM_CLEAR := FIELD + 0.6
## What the land itself costs a battle, per sample: woods hide it, hills break the lines.
const ROUGH_GROUND := {"Forest": 12.0, "Jungle": 12.0, "Swamp": 8.0, "Hills": 4.0, "Mountains": 50.0, "Glacier": 50.0}


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Whether a field centred at `c` is clear of every town and farm.
static func _clear_field(c: Vector3, walls: Array, farms: Array) -> bool:
	for w in walls:
		if _flat_gap(c, w[0]) < float(w[1]) + FIELD + TOWN_CLEAR:
			return false
	for f in farms:
		if _flat_gap(c, f) < FARM_CLEAR:
			return false
	return true


## What's wrong with fighting at `c`: water, slope, rough ground and roads
## across the field, sampled at its centre and on three rings to its edge.
func _field_cost(c: Vector3, roads) -> float:
	var cost := 0.0
	for k in 25:
		var ring := int(ceil(k / 8.0))
		var q := c + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * FIELD * ring / 3.0 if k > 0 else c
		if not terrain.is_land(q.x, q.z):
			cost += 50.0
			continue
		cost += absf(terrain.height_at(q.x, q.z) - c.y) * 30.0
		var tile: Vector2i = terrain.tile_of(q)
		cost += float(ROUGH_GROUND.get(terrain.tile_at(tile.x, tile.y), 0.0))
		if roads and roads.on_path(q, 0.05):
			cost += 3.0
	return cost


## Stones in flight on a loop: each arcs from the engine to a point inside the
## walls, lands with a puff of dust, and now and then sets a roof alight.
func _volley(root: Node3D, from: Vector3, at: Vector3, spread: float, r: RandomNumberGenerator, every: float) -> void:
	var stone := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	stone.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	stone.material_override = mat
	stone.visible = false
	root.add_child(stone)
	var shoot := func():
		var land := _ground(at + Vector3(r.randf_range(-spread, spread), 0, r.randf_range(-spread, spread)))
		var top := maxf(from.y, land.y) + from.distance_to(land) * 0.45
		stone.visible = true
		var tw := stone.create_tween()
		tw.tween_method(func(t: float):
			var p := from.lerp(land, t)
			p.y = lerpf(from.y, land.y, t) + (top - maxf(from.y, land.y)) * 4.0 * t * (1.0 - t)
			stone.position = p, 0.0, 1.0, 1.6)
		tw.tween_callback(func():
			stone.visible = false
			var d := _puffs(Color(0.5, 0.45, 0.38, 0.22), 6, 1.0, 0.04, 0.1)
			d.one_shot = true
			d.explosiveness = 0.9
			d.position = land + Vector3(0, 0.05, 0)
			root.add_child(d)
			d.emitting = true)
	var t := Timer.new()
	t.wait_time = every
	t.autostart = true
	t.timeout.connect(shoot)
	root.add_child(t)


## Six men leave the camp behind their raised shields, run the last stretch,
## fight at the foot of the walls and fall back, leaving a man or two there.
## The camp sends a fresh man in each one's place before the next rush.
func _assault(root: Node3D, arc: Callable, a: float, camp_r: float, wall: float, col: Color, r: RandomNumberGenerator, first: float) -> Array:
	var men := []
	for i in 6:
		var off := (i - 2.5) * 0.06
		var home: Vector3 = arc.call(a + off, camp_r - 0.35)
		var m := {"home": home, "foot": arc.call(a + off, wall + 0.12), "alive": true, "kit": "sword", "rank": 1}
		_assault_man(root, m, col, r)
		men.append(m)
	var cycle := func():
		for m in men:
			if not m["alive"]:
				_assault_man(root, m, col, r)  # a fresh man from the camp
			var n: Node3D = m["node"]
			var face: Vector3 = (m["foot"] - m["home"]).normalized()
			var half: Vector3 = m["home"].lerp(m["foot"], 0.55)
			var tw := n.create_tween()
			tw.tween_interval(r.randf_range(0.0, 0.6))
			tw.tween_callback(func():
				m["out"] = true
				n.rotation.y = atan2(face.x, face.z)
				_people.play(n, "Shield_Block", r.randf_range(0.9, 1.1)))
			tw.tween_method(func(k: float): if m["alive"]: n.position = _stand(m["home"].lerp(half, k)), 0.0, 1.0, 2.4)
			tw.tween_callback(func(): if m["alive"]: _people.play(n, "Sprint", r.randf_range(0.9, 1.1)))
			tw.tween_method(func(k: float): if m["alive"]: n.position = _stand(half.lerp(m["foot"], k)), 0.0, 1.0, 1.4)
			tw.tween_callback(func(): if m["alive"]: _people.play(n, "Sword_Attack" if r.randf() < 0.5 else "Sword_Attack_2", r.randf_range(0.85, 1.15)))
			tw.tween_interval(r.randf_range(3.0, 4.5))
			tw.tween_callback(func():
				if not m["alive"]:
					return
				if r.randf() < 0.18:
					m["alive"] = false
					_die(n, DEATHS[r.randi() % DEATHS.size()], r)
					return
				n.rotation.y = atan2(-face.x, -face.z)
				_people.play(n, "Walk", 1.0))
			tw.tween_method(func(k: float): if m["alive"]: n.position = _stand(m["foot"].lerp(m["home"], k)), 0.0, 1.0, 3.0)
			tw.tween_callback(func():
				m["out"] = false
				if m["alive"]:
					n.rotation.y = atan2(face.x, face.z)
					_people.play(n, "Sword_Idle", 1.0))
	var t := Timer.new()
	t.wait_time = 15.0
	t.timeout.connect(cycle)
	root.add_child(t)
	var start := create_tween()
	start.tween_interval(first)
	start.tween_callback(func():
		if is_instance_valid(t):
			cycle.call()
			t.start())
	return men


func _assault_man(root: Node3D, m: Dictionary, col: Color, r: RandomNumberGenerator) -> void:
	var f: Node3D = _people.make(r, "soldier", col, "adult")
	f.position = _stand(m["home"])
	root.add_child(f)
	arm(f, "sword")
	_people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
	m["node"] = f
	m["alive"] = true
	m["out"] = false


## Re-skins a bright toy-kit model in weathered timber, like the town's beams.
func _weather(n: Node3D) -> void:
	if _timber == null:
		_timber = StandardMaterial3D.new()
		_timber.albedo_texture = load("res://assets/village/T_WoodTrim_BaseColor.png")
		_timber.normal_enabled = true
		_timber.normal_texture = load("res://assets/village/T_WoodTrim_Normal.png")
		_timber.uv1_triplanar = true
		_timber.uv1_world_triplanar = true
		_timber.uv1_scale = Vector3.ONE * 3.0
		_timber.albedo_color = Color(0.62, 0.5, 0.4)
		_timber.roughness = 0.95
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _timber


## Scales an imported model so it stands `height` tall, feet on the ground.
func _fit(n: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		n.scale = Vector3.ONE * (height / box.size.y)


## Breaks a camp up once the host has moved on.
func _siege_watch(id: int) -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(func():
		if not _sieges.has(id):
			return
		var s: Dictionary = _sieges[id]
		if Time.get_ticks_msec() / 1000.0 > s["until"]:
			_sieges.erase(id)
			if is_instance_valid(s["root"]):
				s["root"].queue_free())
	_sieges[id]["root"].add_child(t)


# --- fire, smoke and flight ---------------------------------------------------------

func _puffs(color: Color, amount: int, life: float, smin: float, smax: float, additive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 18
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.03, 0.04, 0)
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	return p


func _burn(at: Vector3, seconds: float, scale := 1.0) -> void:
	var root := Node3D.new()
	root.name = "Burn"
	add_child(root)
	var r := _rng(at)
	for i in int(5 * scale):
		var off := Vector3(r.randf_range(-1.2, 1.2), 0, r.randf_range(-1.2, 1.2)) * scale
		var p := _ground(at + off)
		# Flames as lit particles, not additive glow: additive fire blooms into
		# white orbs at this scale.
		var fire := _puffs(Color(1.0, 0.45, 0.1, 0.85), 18, 0.7, 0.05, 0.12)
		fire.initial_velocity_min = 0.15
		fire.initial_velocity_max = 0.35
		fire.position = p + Vector3(0, 0.2, 0)
		root.add_child(fire)
		var smoke := _puffs(Color(0.12, 0.11, 0.1, 0.75), 30, 6.0, 0.3, 0.8)
		smoke.position = p + Vector3(0, 0.6, 0)
		root.add_child(smoke)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.2)
		light.light_energy = 0.6
		light.omni_range = 1.0
		light.position = p + Vector3(0, 0.4, 0)
		root.add_child(light)
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func():
		for c in root.get_children():
			if c is CPUParticles3D:
				c.emitting = false
			elif c is OmniLight3D:
				c.queue_free())
	tw.tween_interval(8.0)
	tw.tween_callback(root.queue_free)


func _refugees(at: Vector3, count: int) -> void:
	var r := _rng(at)
	# Flee toward land: try directions until one leads somewhere walkable.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 5.5
		if terrain.is_land(probe.x, probe.z):
			break
		ang += TAU / 12.0
	for i in count:
		var f: Node3D = _people.make(r, "peasant", Color(0.75, 0.72, 0.68))
		var start := at + Vector3(cos(ang), 0, sin(ang)) * (2.0 + i * 0.12) + Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))
		var goal := start + Vector3(cos(ang), 0, sin(ang)) * 4.0
		add_child(f)
		f.look_at_from_position(_stand(start), _ground(goal) + Vector3(0, _ground(start).y - terrain.height_at(goal.x, goal.z), 0), Vector3.UP)
		f.rotate_y(PI)
		# Some flee at a run, the rest trudge with what they could carry.
		var running := i % 3 == 0
		_people.play(f, "Running" if running else "Walk", 1.0 if running else 0.7)
		_walk(f, goal, 14.0 if running else 30.0, true)


func _walk(n: Node3D, goal: Vector3, seconds: float, fade: bool) -> void:
	var route: PackedVector3Array = _route(n.position, goal)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(n):
			return
		var p: Vector3 = terrain.along(route, t)
		if not terrain.is_land(p.x, p.z):
			return  # never step into water; stop at the shore
		n.position = _stand(p), 0.0, 1.0, seconds)
	if fade:
		tw.tween_callback(n.queue_free)


## The royal host musters in Kingsmere's square: spearmen in ranks under the
## crown's banners, a sergeant out in front. They drill as one at his shout
## (thrust, thrust, salute), then march out in step, two abreast behind their
## captain and the banners, along the road and out through the gate
## toward where they are sent, and halt there in formation.
func _muster(at: Vector3, goal: Vector3) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	root.name = "Muster"
	add_child(root)
	var col := Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.25)
	var crown := {"name": "The Crown", "crown": true}
	var route: PackedVector3Array = _route(at, goal)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var start_dir: Vector3 = (terrain.along(route, minf(1.0, 0.6 / maxf(length, 0.6))) - at)
	start_dir.y = 0
	start_dir = start_dir.normalized() if start_dir.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-start_dir.z, 0, start_dir.x)
	var men := []
	const FILES := 4
	const RANKS := 5
	for rank in RANKS:
		for file in FILES:
			var f: Node3D = _people.make(r, "soldier", col, "adult")
			f.position = _stand(at + side * ((file - 1.5) * 0.13) - start_dir * (rank * 0.15))
			f.rotation.y = atan2(start_dir.x, start_dir.z)
			root.add_child(f)
			arm(f, "spear")
			_people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
			men.append({"node": f, "slot": rank * FILES + file})
	# The sergeant faces his men; the captain stands at the head.
	var sergeant: Node3D = _people.make(r, "soldier", col, "adult")
	sergeant.position = _stand(at + start_dir * 0.3 + side * 0.32)
	sergeant.rotation.y = atan2(-start_dir.x, -start_dir.z) - 0.5
	root.add_child(sergeant)
	arm(sergeant, "sword")
	_people.play(sergeant, "Sword_Idle")
	var captain: Node3D = _people.make(r, "soldier", col, "adult")
	captain.position = _stand(at + start_dir * 0.32)
	captain.rotation.y = atan2(start_dir.x, start_dir.z)
	root.add_child(captain)
	arm(captain, "sword")
	_people.play(captain, "Sword_Idle")
	var banners := []
	for i in 2:
		var b: Node3D = Heraldry.standard(crown, col, PLANTED)
		b.position = _ground(at + side * (i * 0.36 - 0.18) + start_dir * 0.16)
		root.add_child(b)
		banners.append(b)
	var yaw := atan2(side.x, side.z) - 0.5
	framing.emit(_ground(at), 2.6, yaw)
	# The drill (1-7 s): at each shout the ranks thrust their spears as one,
	# then salute the banners.
	var tw := create_tween()
	for drill in ["Sword_Attack", "Sword_Attack", "Salute"]:
		tw.tween_interval(0.6)
		tw.tween_callback(func(): _people.play(sergeant, "Yelling", 1.3))
		tw.tween_interval(0.9)
		tw.tween_callback(func():
			for m in men:
				_in_step(m["node"], drill, 0.0))
	tw.tween_interval(1.6)
	# Formed for the march: everyone in step, the captain leading.
	var seconds := clampf(length / 0.25, 12.0, 80.0)
	var spacing := 0.12 / maxf(length, 0.5)
	tw.tween_callback(func():
		_people.play(sergeant, "Yelling", 1.0)
		var phase := r.randf()
		for m in men:
			_in_step(m["node"], "Walk", phase)
		_people.play(captain, "Walk", 1.0)
		framing.emit(_ground(at + start_dir * 1.2), 3.4, yaw))
	tw.tween_method(func(t: float):
		for m in men:
			var row := int(m["slot"]) / 2
			_on_route(m["node"], route, t - (row + 3) * spacing, 0.05 if int(m["slot"]) % 2 == 0 else -0.05)
		_on_route(sergeant, route, t - 14 * spacing, 0.08)
		_on_route(captain, route, t, 0.0)
		for i in banners.size():
			_on_route(banners[i], route, t - (1 + i) * spacing, 0.05 if i == 0 else -0.05)
		, 0.0, 1.0 + 16 * spacing, seconds)
	tw.tween_callback(func():
		for m in men:
			_people.play(m["node"], "Sword_Idle", 1.0)
		_people.play(sergeant, "Sword_Idle", 1.0)
		_people.play(captain, "Sword_Idle", 1.0))
	tw.tween_interval(40.0)
	tw.tween_callback(root.queue_free)


## Places a marcher at `t` along a route (held at the start before his turn
## comes, and at the end once there), facing along it, `offset` to the side.
func _on_route(n: Node3D, route: PackedVector3Array, t: float, offset: float) -> void:
	var k := clampf(t, 0.0, 1.0)
	var p: Vector3 = terrain.along(route, k)
	var ahead: Vector3 = terrain.along(route, minf(1.0, k + 0.01))
	var dir := Vector3(ahead.x - p.x, 0, ahead.z - p.z)
	if dir.length() > 0.0001:
		dir = dir.normalized()
		n.rotation.y = atan2(dir.x, dir.z)
	if t <= 0.0:
		return  # still formed up, waiting for the column to reach him
	n.position = _stand(p + Vector3(-dir.z, 0, dir.x) * offset)


## A royal rider carries the King's ruling to the petitioner's seat on a
## horse, the crown's standard in hand, with what was decided written above
## him. He sets off at a walk, rides the road at a gallop and draws up at a walk.
func _rider(from: Vector3, to: Vector3, label: String) -> void:
	var r := _rng(to)
	var horse: Node3D = Horse.new(r.randi() % Horse.COATS.size())
	add_child(horse)
	horse.position = _stand(from, HORSE_BODY)
	var rider: Node3D = _people.make(r, "soldier", Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.3), "adult")
	horse.mount(rider)
	carried_standard(rider, {"name": "The Crown", "crown": true}, Color(0.72, 0.13, 0.16))
	var tag := _caption(self, label, _ground(from) + Vector3(0, 0.45, 0))
	var route: PackedVector3Array = _route(from, to)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	# Eased in and out, the pace peaks at about pi/2 the average: a gallop
	# (horse.gd) over the open road, a walk at either end.
	var secs := clampf(length / (Horse.GALLOP * 0.63), 8.0, 90.0)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := _stand(terrain.along(route, t), HORSE_BODY)
		var ahead := _ground(terrain.along(route, minf(1.0, t + 0.01)))
		if ahead.distance_to(p) > 0.0001:
			horse.rotation.y = lerp_angle(horse.rotation.y, atan2(ahead.x - p.x, ahead.z - p.z), 0.2)
		horse.position = p
		_place_tag(tag, p + Vector3(0, 0.45, 0)), 0.0, 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(3.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(func():
		horse.queue_free()
		tag.queue_free())


# --- the King's convoys ------------------------------------------------------------------

func _convoy(from: Vector3, to: Vector3, grain: bool, label := "") -> void:
	var r := _rng(from)
	var root := Node3D.new()
	root.name = "Convoy"
	add_child(root)
	var wagon := MeshInstance3D.new()
	wagon.mesh = _wagon
	wagon.scale = Vector3.ONE * 0.12
	root.add_child(wagon)
	var crown_col := Color(0.72, 0.13, 0.16)
	var escort := []
	for i in 3:
		var s: Node3D = _people.make(r, "soldier", crown_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		_people.play(s, "Walk")
		escort.append(s)
	var route: PackedVector3Array = _route(from, to)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var seconds := clampf(length / 0.35, 12.0, 70.0)
	var tag := _caption(root, label if label != "" else ("The King's grain" if grain else "The King's gold"), _ground(from) + Vector3(0, 0.45, 0))
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := _stand(terrain.along(route, t))
		var ahead := _ground(terrain.along(route, minf(1.0, t + 0.01)))
		var dir := (ahead - p).normalized() if ahead.distance_to(p) > 0.0001 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0, dir.x)
		wagon.position = p
		wagon.rotation.y = atan2(dir.x, dir.z) + PI
		_place_tag(tag, p + Vector3(0, 0.45, 0))
		for i in escort.size():
			var e: Node3D = escort[i]
			var trail := _stand(terrain.along(route, maxf(0.0, t - (0.004 + i * 0.003))))
			e.position = trail + side * (0.05 if i % 2 == 0 else -0.05)
			e.rotation.y = atan2(dir.x, dir.z), 0.0, 1.0, seconds)
	tw.tween_interval(1.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)


# --- feasts and handovers ----------------------------------------------------------

## A wedding feast in the town square: a fire, barrels broached, the town
## dancing in a ring around it and talking in knots at the edges.
func _feast(at: Vector3, house: Dictionary) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	root.name = "Feast"
	add_child(root)
	var centre := _ground(at)
	var fire: Node3D = Realistic.make("ph/stone_fire_pit")
	if fire:
		fire.position = centre + Vector3(0.0, 0.0, 0.0)
		root.add_child(fire)
	# A roasting fire: seen by day as its smoke, a thin grey column.
	var flame := _puffs(Color(0.55, 0.53, 0.5, 0.5), 10, 3.0, 0.06, 0.14)
	flame.position = centre + Vector3(0, 0.08, 0)
	root.add_child(flame)
	for i in 3:
		var cask: Node3D = Realistic.make("ph/wine_barrel_01")
		if cask:
			var a := TAU * (0.1 + i * 0.07)
			cask.position = _ground(at + Vector3(cos(a), 0, sin(a)) * 0.95)
			cask.rotation.y = r.randf() * TAU
			root.add_child(cask)
	var col := Color.from_string(String(house.get("color", "#b08a4a")), Color(0.7, 0.55, 0.3))
	if not house.is_empty():
		_standard(root, at + Vector3(0.0, 0, -0.9), col, Vector3(0, 0, 1), house)
	# The ring of dancers, turning slowly about the fire, in their own village
	# clothes: the house shows in its standard, not on the dancers (in its
	# colours they read as two companies brawling).
	var ring := Node3D.new()
	ring.position = centre
	root.add_child(ring)
	var n := 12
	for i in n:
		var a := TAU * i / n
		var f: Node3D = _people.make(r, "peasant")
		ring.add_child(f)
		var p := Vector3(cos(a), 0, sin(a)) * 0.42
		f.position = _stand(centre + p) - centre
		f.rotation.y = a + PI * 0.5
		_people.play(f, "Dance", r.randf_range(0.9, 1.1))
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 40.0).as_relative()
	# Knots of talkers at the edge of the square.
	for k in 3:
		var a := TAU * (0.35 + k * 0.22)
		var spot := at + Vector3(cos(a), 0, sin(a)) * 1.05
		for j in 3:
			var f: Node3D = _people.make(r)
			root.add_child(f)
			var off := Vector3(cos(j * 2.1), 0, sin(j * 2.1)) * 0.09
			f.position = _stand(spot + off)
			f.rotation.y = atan2(-off.x, -off.z)
			_people.play(f, "Idle_Talking")
	var tag := _caption(root, "A wedding feast", centre + Vector3(0, 1.3, 0))
	_fade_out(root, 75.0, tag)


## A town changing hands by treaty or by its own will: the old lord's banner
## comes down, a file of the new lord's men marches in, and his goes up.
func _handover(at: Vector3, old_house: Dictionary, new_house: Dictionary, town: String) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	root.name = "Handover"
	add_child(root)
	var old_col := Color.from_string(String(old_house.get("color", "#777")), Color.GRAY)
	var new_col := Color.from_string(String(new_house.get("color", "#ccc")), Color.WHITE)
	var spot := at + Vector3(0.35, 0, -0.35)
	var old_b := _standard(root, spot, old_col, Vector3(0, 0, 1), old_house)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(_drop_banner.bind(old_b))
	# The new lord's men come up the road from outside the walls.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 4.0
		if terrain.is_land(probe.x, probe.z):
			break
		ang += TAU / 12.0
	var dir := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-dir.z, 0, dir.x)
	for i in 6:
		var s: Node3D = _people.make(r, "soldier", new_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		var start := at + dir * (4.0 + (i / 2) * 0.22) + side * ((i % 2) * 0.16 - 0.08)
		var goal := spot + dir * (0.35 + (i / 2) * 0.16) + side * ((i % 2) * 0.16 - 0.08)
		s.position = _stand(start)
		s.rotation.y = atan2(-dir.x, -dir.z)
		_people.play(s, "Walk")
		var mt := s.create_tween()
		var from := s.position
		mt.tween_method(func(k: float): s.position = _stand(from.lerp(goal, k)), 0.0, 1.0, 14.0)
		mt.tween_callback(_people.play.bind(s, "Sword_Idle", 1.0))
	tw.tween_interval(13.0)
	tw.tween_callback(func():
		var b := _standard(root, spot + Vector3(0.12, 0, 0), new_col, Vector3(0, 0, 1), new_house)
		b.scale = Vector3(1, 0.05, 1)
		b.create_tween().tween_property(b, "scale", Vector3.ONE, 2.5).set_ease(Tween.EASE_OUT))
	var tag := _caption(root, "%s passes to %s" % [town, String(new_house.get("name", "a new lord"))], _ground(spot) + Vector3(0, 1.3, 0))
	_fade_out(root, 60.0, tag)


## Captions in the world now, oldest first: a new one near an older one goes a
## line above it, so two never print over each other.
var _tags: Array[Label3D] = []
const LINE := 0.17  # one caption's height, in world units
const NEAR := 0.8  # captions closer than this (across the ground) share a place


## A caption over the world: what a scene is, or what a rider carries. `root`
## must sit at the world's origin (the scene roots and this node do).
func _caption(root: Node3D, text: String, at: Vector3) -> Label3D:
	var tag := Label3D.new()
	tag.visibility_range_begin = 1.6  # gone when you're walking right past it
	tag.text = text
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.85, 0.6)
	root.add_child(tag)
	_tags.append(tag)
	tag.tree_exiting.connect(func(): _tags.erase(tag))
	_place_tag(tag, at)
	return tag


## Sets a caption at `at`, lifted a line for each older caption in the same place.
func _place_tag(tag: Label3D, at: Vector3) -> void:
	var lift := 0
	for o in _tags:
		if o == tag:
			break
		var p: Vector3 = o.get_meta("at", o.position)
		if Vector2(p.x - at.x, p.z - at.z).length() < NEAR:
			lift += 1
	tag.set_meta("at", at)
	tag.position = at + Vector3(0, lift * LINE, 0)


## The caption fades after `seconds`, and the scene it names ends with it: the
## whole of `root` (the feast's tables, the handover's standards) is freed.
func _fade_out(root: Node3D, seconds: float, tag: Label3D) -> void:
	var tw := root.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
