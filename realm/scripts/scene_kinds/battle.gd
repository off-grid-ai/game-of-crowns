extends "res://scripts/scene_kind.gd"
## A battle (scene_kinds.gd "battle"), where Freeciv says men died: the army layer's field battle (army_field.gd)
## when the bridge sends who fought, else the skirmish of two lines below. Many deaths on one tile in one turn are
## one battle. The field is open ground found near it (battlefield), never in a town or on a farm.

const ArmyField := preload("res://scripts/army_field.gd")
const ArmySkirmish := preload("res://scripts/army_skirmish.gd")
const Awareness := preload("res://scripts/awareness.gd")
const Horse := preload("res://scripts/horse.gd")

## The skirmish (army_skirmish.gd), a pitched battle where Freeciv says men died, staged like film. The losing
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
## The most the ground may rise or fall across a field, from its centre.
const FIELD_RISE := 0.3
## How far out (in rings 0.8 apart) the field is looked for.
const RINGS := 40
## How far a field's edge keeps from a town's reach, and its centre from a farmstead.
const TOWN_CLEAR := 0.4
const FARM_CLEAR := FIELD + 4.8  # a farmstead's fields reach up to 4.6 from it (countryside._farmstead)
## What the land itself costs a battle, per sample: woods hide it, hills break the lines.
const ROUGH_GROUND := {"Forest": 12.0, "Jungle": 12.0, "Swamp": 8.0, "Hills": 4.0, "Mountains": 50.0, "Glacier": 50.0}

var _played := {}  # "x,y,turn" -> true: the battles staged already
var _fighting: Array = []  # [centre, battle root] of every battle on the field now
var last_view_yaw := 0.0  # the side the last battle is watched from (its trees cleared); the film takes use it


func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	# Many deaths on one tile in one turn are one battle.
	var tile := "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s["turn"])]
	if _played.has(tile):
		return null
	_played[tile] = true
	# The bridge says who won and how many fought (battles.js); a field battle when it can be staged
	# (army_field.gd, field.play.on), else the small skirmish.
	var victor := int(s["victor"]) if s.get("victor") != null else -1
	if victor < 0:
		victor = victor_of(s)  # the bridge didn't see who: whoever stands beside it
	var staged_field: Node = null
	if s.get("kinds") != null and ArmyField.in_play():
		staged_field = ArmyField.stage(stage.get_parent(), s, houses, battlefield(at))
	if staged_field == null:
		fight(at, houses.get(int(s.get("owner", -1)), {}), houses.get(victor, {}))
	return null


func fight(at: Vector3, loser: Dictionary, victor := {}) -> void:
	var root := Node3D.new()
	root.name = "Battle"
	stage.add_child(root)
	var r: RandomNumberGenerator = stage.rng(at)
	var lost := Color.from_string(String(loser.get("color", "#777")), Color.GRAY)
	var won := Color.from_string(String(victor.get("color", "#7f2b26")), Color(0.5, 0.17, 0.15))
	# Two houses in like colours (or victors unknown, in blood red, against a red
	# house): the victors go in steel blue, so you can tell the sides apart.
	if absf(wrapf(lost.h - won.h, -0.5, 0.5)) < 0.12 and lost.s > 0.25 and won.s > 0.25:
		won = Color(0.22, 0.3, 0.46)
	var cols := [lost.lerp(Color.WHITE, 0.3), won.lerp(Color.WHITE, 0.15)]
	# Battles are fought on open ground: out past the town, off its roads and
	# fields, on land flat enough to hold a line. No trees stand in the fight.
	# The field is chosen against the towns as they stand: while they are
	# still going up (a realm just opened), wait for them.
	if not stage._towns_up():
		root.queue_free()
		stage.get_tree().create_timer(0.5).timeout.connect(fight.bind(at, loser, victor))
		return
	at = battlefield(at)
	if at == Vector3.INF:
		root.queue_free()
		return  # no open ground near: the battle is told, not shown
	_fighting.append([at, root])
	stage.terrain.clear_around(at, FIELD)
	# The lines meet across the view, so you watch the clash from the side.
	var dir := Vector3(cos(r.randf() * TAU), 0, 0)
	dir.z = sqrt(1.0 - dir.x * dir.x)
	var cam: Camera3D = stage.get_viewport().get_camera_3d() if stage.is_inside_tree() else null
	if cam:
		dir = Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	# One side of the field for the whole battle: moving round it puts houses
	# and trees between you and the fighting.
	var view_yaw := atan2(side.x, side.z) + 0.35
	last_view_yaw = view_yaw
	# The camera watches low across the field from that side: fell the trees
	# between it and the fight, in a cone opening toward where it stands.
	var toward_cam := Vector3(sin(view_yaw), 0, cos(view_yaw))
	for k in 6:
		stage.terrain.clear_around(at + toward_cam * (FIELD + k * 1.2), 1.4 + k * 0.35)
	var teams := [[], []]
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		for rank in RANKS:
			for file in FILES:
				# Where this man will stand once the lines meet. The wall holds
				# its ground a little forward; the attackers start well back.
				var slot: Vector3 = at - face * (REACH + rank * ROW) + side * ((file - (FILES - 1) / 2.0) * GAP)
				slot += side * r.randf_range(-0.015, 0.015) - face * r.randf_range(0.0, 0.02)
				var f: Node3D = stage.people.make(r, "soldier", cols[team], "adult")
				var back := 0.25 if team == 0 else 1.5
				f.position = stage.stand(slot - face * back)
				f.rotation.y = atan2(face.x, face.z)
				root.add_child(f)
				var kit := "sword"
				if team == 0 and rank == 1:
					kit = "spear"
				elif team == 0 and rank == 2:
					kit = "bow"
				stage.arm(f, kit, cols[team])
				stage.people.play(f, "Bow_Idle" if kit == "bow" else "Sword_Idle", r.randf_range(0.9, 1.1))
				teams[team].append({"node": f, "rank": rank, "file": file, "face": face, "slot": slot, "alive": true, "engaged": false, "kit": kit})
	# Each side's standard, carried by a bearer behind the middle of its line.
	var bearers := []
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		var p: Vector3 = at - face * (REACH + RANKS * ROW + (0.3 if team == 0 else 1.6))
		var bearer: Node3D = stage.people.make(r, "soldier", cols[team], "adult")
		bearer.position = stage.stand(p)
		bearer.rotation.y = atan2(face.x, face.z)
		root.add_child(bearer)
		stage.arm(bearer, "bow")
		stage.people.play(bearer, "Sword_Idle")
		var house: Dictionary = loser if team == 0 else victor
		# A standard needs its house's arms; men of no known house fight without one.
		var flag: Node3D = stage.standard(root, p + side * 0.06, cols[team], face, house)
		bearers.append({"node": bearer, "flag": flag, "face": face})
	var knights := _flank_company(root, at, dir, side, cols[1], r)
	root.set_meta("fallen", [])
	stage.framing.emit(stage.ground(at), 5.5, view_yaw)
	# Fought by the men in it: each soldier and knight runs his own mind (army_skirmish.gd, the army layer's
	# close fight), every step through his Mover on the field's own ground.
	ArmySkirmish.new().start(stage, root, r, at, dir, side, view_yaw, teams, knights, bearers)


## The victors' knights: horsemen waiting on open ground out on the wing, well
## behind their own line (the victors form on the -dir side), to walk up during
## the advance.
func _flank_company(root: Node3D, at: Vector3, dir: Vector3, side: Vector3, col: Color, r: RandomNumberGenerator) -> Array:
	var knights := []
	for i in KNIGHTS:
		var h: Node3D = Horse.new(r.randi() % 5)
		root.add_child(h)
		h.mount(stage.people.make(r, "soldier", col, "adult"))
		stage.arm(h.rider, "lance", col)
		var wing: Vector3 = at + side * ((FILES / 2.0) * GAP + 0.55 + (i / 2) * 0.24) - dir * ((i % 2) * 0.22)
		h.position = stage.stand(wing - dir * (REACH + RANKS * ROW + 1.8), stage.HORSE_BODY)
		h.rotation.y = atan2(dir.x, dir.z)
		knights.append({"node": h, "wing": wing, "alive": true})
	return knights


## Open ground for a pitched battle, as near `near` as there is. A field is
## never in or beside a town or a farmstead: one whose fighting ground (FIELD
## and a margin) comes within any town's reach or near a farm is refused
## outright, and the search widens ring by ring until a clear one is found.
## Among the clear fields of the nearest ring, the driest, flattest and most
## open wins. Vector3.INF if the land has none (no battle is staged then).
func battlefield(near: Vector3) -> Vector3:
	var main: Node = stage.get_parent()
	if stage.towns == null:
		stage.towns = main.get("towns")
	var towns: Node3D = stage.towns
	var roads = main.get("roads")
	var country = main.get("countryside")
	var span := RINGS * 0.8 + FIELD
	var walls := []  # [centre, reach] of every town that could touch a field
	if towns:
		for id in stage.towns.towns:
			var t: Node3D = stage.towns.towns[id]["node"]
			var reach := float(t.get_meta("reach", 6.0)) if is_instance_valid(t) else 0.0
			if reach > 0.0 and stage._flat_gap(t.global_position, near) < span + reach:
				walls.append([t.global_position, reach])
	# A field already being fought over is taken: the next battle finds its own.
	_fighting = _fighting.filter(func(b): return is_instance_valid(b[1]))
	for b in _fighting:
		walls.append([b[0], FIELD])
	var farms := []
	for f in (country.get("_sites") if country else []):
		if stage._flat_gap(f["at"], near) < span + FARM_CLEAR:
			farms.append(f["at"])
	for ring in RINGS:
		var best := Vector3.INF
		var best_score := INF
		var n := maxi(1, ring * 8)
		for i in n:
			var a := TAU * i / n
			var p: Vector3 = stage.ground(near + Vector3(cos(a), 0, sin(a)) * ring * 0.8)
			if not _clear_field(p, walls, farms):
				continue
			var score := _field_cost(p, roads)
			if score < best_score:
				best_score = score
				best = p
		if best != Vector3.INF:
			return best
	return Vector3.INF


## Whether a field centred at `c` is clear of every town and farm.
func _clear_field(c: Vector3, walls: Array, farms: Array) -> bool:
	for w in walls:
		if stage._flat_gap(c, w[0]) < float(w[1]) + FIELD + TOWN_CLEAR:
			return false
	for f in farms:
		if stage._flat_gap(c, f) < FARM_CLEAR:
			return false
	return true


## What's wrong with fighting at `c`: water, slope, rough ground and roads
## across the field, sampled at its centre and on three rings to its edge.
func _field_cost(c: Vector3, roads) -> float:
	var cost := 0.0
	for k in 25:
		var ring := int(ceil(k / 8.0))
		var q := c + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * FIELD * ring / 3.0 if k > 0 else c
		# Men stand everywhere out to the field's edge: none of it may be water.
		if not stage.terrain.is_land(q.x, q.z):
			return INF
		var rise := absf(stage.terrain.height_at(q.x, q.z) - c.y)
		var tile: Vector2i = stage.terrain.paths.tile_of(q)
		var kind := String(stage.terrain.tile_at(tile.x, tile.y))
		# A mountainside is never a battlefield: the lines can't stand on it.
		if rise > FIELD_RISE or kind == "Mountains" or kind == "Glacier":
			return INF
		cost += rise * 30.0
		cost += float(ROUGH_GROUND.get(kind, 0.0))
		if roads and roads.on_path(q, 0.05):
			cost += 3.0
	return cost


## Who won a fight: the house with men standing on or next to the tile where
## the loser's died. -1 if no one is there.
func victor_of(s: Dictionary) -> int:
	var store: Node = Awareness.store()
	var best := -1
	var near := INF
	for u in store.rec("units", []):
		if int(u["owner"]) == int(s.get("owner", -1)):
			continue
		var d := Vector2(float(u["x"]) - float(s["x"]), float(u["y"]) - float(s["y"])).length()
		if d <= 1.5 and d < near:
			near = d
			best = int(u["owner"])
	return best
