extends "res://scripts/scene_kind.gd"
## A battle (scene_kinds.gd "battle"), where Freeciv says men died: the army layer's field battle (army_field.gd), its
## men drawn by regiment on Godot's MultiMesh (army.gd's VAT regiments), the one way a battle is fought on the map
## (the old skirmish, a scene node per man, is gone: 560 men at 1-6 fps, 11-12). Many deaths on one tile in one turn
## are one battle. The field is open ground found near it (battlefield), never in a town or on a farm.

const ArmyField := preload("res://scripts/army_field.gd")
const Ground := preload("res://scripts/ground.gd")  # the one answer to where a body may stand
const Awareness := preload("res://scripts/awareness.gd")
const Data := preload("res://scripts/data.gd")

var _played := {}  # "x,y,turn" -> true: the battles staged already
var _fighting: Array = []  # [centre, field battle] of every battle on the field now
var last_view_yaw := 0.0  # the side the last battle is watched from (across its lines); the film takes use it
var _waiting: Array = []  # [scene, at, houses] of every crown battle waiting for room on the field, first first (_wait)
var _retrying := false  # a retry of the waiting is on its timer


func play(s: Dictionary, at: Vector3, houses: Dictionary) -> Node3D:
	# Many deaths on one tile in one turn are one battle.
	var tile := "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s["turn"])]
	if _played.has(tile):
		return null
	_played[tile] = true
	var sc := s.duplicate()
	if sc.get("victor") == null or int(sc["victor"]) < 0:
		sc["victor"] = victor_of(s)  # the bridge didn't see who: whoever stands beside it
	_stage(sc, at, houses)
	return null


## A battle staged where no scene told of one (the film's battle clip, the shot harness): `loser`'s men against
## `victor`'s (another house when none is named), on open ground near `near`, as a scene of the bridge's would be.
func stage_at(near: Vector3, loser: Dictionary, victor := {}) -> void:
	var houses: Dictionary = stage.get_parent().get("_houses")
	var lid := -1
	var vid := -1
	for pid in houses:
		if houses[pid] == loser:
			lid = int(pid)
		elif victor.is_empty() and vid < 0 and not houses[pid].get("wild", false):
			vid = int(pid)
		elif not victor.is_empty() and houses[pid] == victor:
			vid = int(pid)
	var kinds: Array = Data.value("battle", "field.play.kinds", [["Pikemen", "Archers"], ["Pikemen", "Knights"]])
	_stage({"x": 0, "y": 0, "turn": 0, "id": "film", "owner": lid, "victor": vid, "kinds": kinds, "men": [600, 600]}, near, houses)


func _stage(s: Dictionary, at: Vector3, houses: Dictionary, queued := false) -> void:
	if not stage._towns_up():
		stage.get_tree().create_timer(0.5).timeout.connect(_stage.bind(s, at, houses, queued))
		return
	# The King's battles first (Mac 2026-11-17: war in formation is the crux): while a crown battle waits for the
	# field, a lord's battle is told, not shown, and a later crown battle waits behind it.
	var crown := is_crown(s, houses)
	if not queued and not _waiting.is_empty():
		if crown:
			_wait(s, at, houses, false)
		return
	var field := battlefield(at, crown)
	if field == Vector3.INF:
		return  # no open ground near (for a crown battle, none out to ground.crown.rings): the battle is told, not shown
	if not (s.get("kinds") is Array):
		s["kinds"] = Data.value("battle", "field.play.kinds", [["Pikemen"], ["Pikemen"]])
	s["crown"] = crown
	if not ArmyField.has_room(stage.get_parent(), crown):
		if crown:
			_wait(s, at, houses, queued)  # only crown battles on the field: this one waits its turn
		return
	var b: Node = ArmyField.stage(stage.get_parent(), s, houses, field)
	if b == null:
		return  # no victor known: told, not shown
	_fighting.append([field, b])
	var face: float = b.play["face"]
	last_view_yaw = face + PI * 0.5 + 0.35  # across the lines, the clash seen from the side


## A crown battle the bridge told of: the King's own host or a house sworn to him fought it (either side).
func is_crown(s: Dictionary, houses: Dictionary) -> bool:
	var pids := [int(s.get("owner", -1)), int(s.get("victor", -1))]
	for pid in pids:
		if (houses.get(pid, {}) as Dictionary).get("crown", false):
			return true
	for p in Awareness.store().rec("players", []):
		if pids.has(int(p.get("id", -2))) and (p.get("sworn") != null or String(p.get("band", "")) == "sworn"):
			return true
	return false


## A crown battle with no room on the field (only crown battles fighting): it waits, asked again every
## field.play.crown.retry seconds, at most field.play.crown.wait seconds (then it is told, not shown).
func _wait(s: Dictionary, at: Vector3, houses: Dictionary, front: bool) -> void:
	var retry := maxf(0.5, Data.num("battle", "field.play.crown.retry", 2.0))
	if not s.has("tries"):
		s["tries"] = int(ceil(Data.num("battle", "field.play.crown.wait", 90.0) / retry))
	s["tries"] = int(s["tries"]) - 1
	if int(s["tries"]) < 0:
		return
	if front:
		_waiting.push_front([s, at, houses])
	else:
		_waiting.push_back([s, at, houses])
	if not _retrying:
		_retrying = true
		stage.get_tree().create_timer(retry, false).timeout.connect(_retry)


func _retry() -> void:
	_retrying = false
	if _waiting.is_empty():
		return
	var w: Array = _waiting.pop_front()
	_stage(w[0], w[1], w[2], true)  # back at the front of the queue if the field is still full
	if not _waiting.is_empty() and not _retrying:
		_retrying = true
		stage.get_tree().create_timer(maxf(0.5, Data.num("battle", "field.play.crown.retry", 2.0)), false).timeout.connect(_retry)


## Open ground for a pitched battle, as near `near` as there is. A field is
## never in or beside a town or a farmstead: one whose fighting ground (field
## and a margin) comes within any town's reach or near a farm is refused
## outright, and the search widens ring by ring until a clear one is found.
## Among the clear fields of the nearest ring, the driest, flattest and most
## open wins. Vector3.INF if the land has none (no battle is staged then). `wide` (a crown battle: the King's
## nearly always play, Mac 2026-11-17) looks on past ground.rings, rings ground.crown.apart apart out to ground.crown.rings,
## once the near ground has none at every share of ground.shrink.
func battlefield(near: Vector3, wide := false) -> Vector3:
	var field := Data.num("battle", "ground.field", 3.4)
	var rings := int(Data.num("battle", "ground.rings", 40))
	var passes := [[0, rings, 0.8]]  # [first ring, rings, apart]
	if wide:
		var apart := maxf(0.8, Data.num("battle", "ground.crown.apart", 1.6))
		passes.append([int(rings * 0.8 / apart), int(Data.num("battle", "ground.crown.rings", 100)), apart])
	var main: Node = stage.get_parent()
	if stage.towns == null:
		stage.towns = main.get("towns")
	var towns: Node3D = stage.towns
	var roads = main.get("roads")
	var span: float = float(passes[-1][1]) * float(passes[-1][2]) + field
	var walls := []  # [centre, reach] of every town that could touch a field
	if towns:
		for id in stage.towns.towns:
			var t: Node3D = stage.towns.towns[id]["node"]
			var reach := float(t.get_meta("reach", 6.0)) if is_instance_valid(t) else 0.0
			if reach > 0.0 and stage._flat_gap(t.global_position, near) < span + reach:
				walls.append([t.global_position, reach])
	# A town the store names but not yet raised (far towns stream in) counts too, at its size's reach (towns.gd's own
	# rule, +3 as its built reach): Mac 2026-11-16, a battle set against a walled town still streaming in.
	var terrain = main.get("terrain")
	for c in Awareness.store().rec("cities", []):
		if towns and stage.towns.towns.has(int(c["id"])) or terrain == null:
			continue
		var at: Vector3 = terrain.world_pos(float(c["x"]), float(c["y"]))
		var reach := clampf(1.6 + int(c.get("size", 1)) * 0.32, 2.0, 6.0) + 3.0
		if stage._flat_gap(at, near) < span + reach:
			walls.append([at, reach])
	# A field already being fought over is taken: the next battle finds its own.
	_fighting = _fighting.filter(func(b): return is_instance_valid(b[1]) and not (b[1] as Node).is_queued_for_deletion())
	for b in _fighting:
		walls.append([b[0], field])
	var why := {"town": 0, "ground": 0, "ploughland": 0, "a building or water": 0}
	# The clear ground asked for (ground.stand), then less of it (ground.shrink): a tighter field on open ground beats
	# the seat's muster ground among its houses (near some seats no place had all of it clear).
	# The near ground first, at every share; a crown battle's wider rings only then.
	for pass_ in passes:
		for room in Data.value("battle", "ground.shrink", [1.0, 0.8, 0.6]):
			for ring in range(int(pass_[0]), int(pass_[1])):
				var found: Array = []  # [score, place] of this ring's places clear of every town and farm, on ground that can be fought on
				var n := maxi(1, ring * 8)
				for i in n:
					var a := TAU * i / n
					var p: Vector3 = stage.ground(near + Vector3(cos(a), 0, sin(a)) * ring * float(pass_[2]))
					if not _clear_field(p, walls):
						why["town"] += 1
						continue
					var score := _field_cost(p, roads)
					if score == INF:
						why["ground"] += 1
						continue
					found.append([score, p])
				# The best few of the ring asked of the ground itself, best first (the costly question, asked of few).
				found.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
				for k in mini(found.size(), int(Data.num("battle", "ground.asked", 4))):
					var reason := _stands_on(found[k][1], float(room))
					if reason == "":
						return found[k][1]
					why[reason] += 1
	if OS.get_cmdline_user_args().has("--where"):
		print("BATTLE no field within %.0f of %s: places turned down for %s" % [span - field, str(near), str(why)])
	return Vector3.INF


## Whether a field centred at `c` is clear of every town (its ploughland and farm buildings are asked of the ground
## itself, _stands_on, where they really stand).
func _clear_field(c: Vector3, walls: Array) -> bool:
	var field := Data.num("battle", "ground.field", 3.4)
	var town_clear := Data.num("battle", "ground.town_clear", 0.4)
	for w in walls:
		if stage._flat_gap(c, w[0]) < float(w[1]) + field + town_clear:
			return false
	return true


## What stands on a field centred at `c`, asked of the ground itself (ground.gd, the one answer to where a body may
## stand): "" if nothing, else what (Mac 2026-11-16: battles set among ploughland, a tavern and a village's houses,
## "walking through walls": a town's reach and 25 points across the field missed all three). The lines' own ground
## (ground.stand, the middle of the field) must be clear of every ploughed strip, building and water.
func _stands_on(c: Vector3, share := 1.0) -> String:
	var r := Data.num("battle", "ground.stand", 4.0) * share
	if not Ground.claims_in(Rect2(c.x - r, c.z - r, r * 2.0, r * 2.0), ["field"]).is_empty():
		return "ploughland"
	var edge := PackedVector2Array()
	for k in 8:
		edge.append(Vector2(c.x + cos(TAU * k / 8.0) * r, c.z + sin(TAU * k / 8.0) * r))
	return "" if Ground.area_free(edge, false, null, ["field", "host", "body"]) else "a building or water"


## What's wrong with fighting at `c`: water, slope, rough ground and roads
## across the field, sampled at its centre and on three rings to its edge.
func _field_cost(c: Vector3, roads) -> float:
	var field := Data.num("battle", "ground.field", 3.4)
	var most_rise := Data.num("battle", "ground.rise", 0.3)
	var rough: Dictionary = Data.value("battle", "ground.rough", {})
	var cost := 0.0
	for k in 25:
		var ring := int(ceil(k / 8.0))
		var q := c + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * field * ring / 3.0 if k > 0 else c
		# Men stand everywhere out to the field's edge: none of it may be water.
		if not Ground.is_clear(q):
			return INF
		var rise := absf(stage.terrain.height_at(q.x, q.z) - c.y)
		var tile: Vector2i = stage.terrain.paths.tile_of(q)
		var kind := String(stage.terrain.tile_at(tile.x, tile.y))
		# A mountainside is never a battlefield: the lines can't stand on it.
		if rise > most_rise or kind == "Mountains" or kind == "Glacier":
			return INF
		cost += rise * 30.0
		cost += float(rough.get(kind, 0.0))
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
