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


func _stage(s: Dictionary, at: Vector3, houses: Dictionary) -> void:
	if not stage._towns_up():
		stage.get_tree().create_timer(0.5).timeout.connect(_stage.bind(s, at, houses))
		return
	var field := battlefield(at)
	if field == Vector3.INF:
		return  # no open ground near: the battle is told, not shown
	if not (s.get("kinds") is Array):
		s["kinds"] = Data.value("battle", "field.play.kinds", [["Pikemen"], ["Pikemen"]])
	var b: Node = ArmyField.stage(stage.get_parent(), s, houses, field)
	if b == null:
		return  # field.play.most already fighting, or no victor known: told, not shown
	_fighting.append([field, b])
	var face: float = b.play["face"]
	last_view_yaw = face + PI * 0.5 + 0.35  # across the lines, the clash seen from the side


## Open ground for a pitched battle, as near `near` as there is. A field is
## never in or beside a town or a farmstead: one whose fighting ground (field
## and a margin) comes within any town's reach or near a farm is refused
## outright, and the search widens ring by ring until a clear one is found.
## Among the clear fields of the nearest ring, the driest, flattest and most
## open wins. Vector3.INF if the land has none (no battle is staged then).
func battlefield(near: Vector3) -> Vector3:
	var field := Data.num("battle", "ground.field", 3.4)
	var rings := int(Data.num("battle", "ground.rings", 40))
	var farm_clear: float = field + Data.num("battle", "ground.farm_clear", 4.8)
	var main: Node = stage.get_parent()
	if stage.towns == null:
		stage.towns = main.get("towns")
	var towns: Node3D = stage.towns
	var roads = main.get("roads")
	var country = main.get("countryside")
	var span := rings * 0.8 + field
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
		walls.append([b[0], field])
	var farms := []
	for f in (country.get("_sites") if country else []):
		if stage._flat_gap(f["at"], near) < span + farm_clear:
			farms.append(f["at"])
	for ring in rings:
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
	var field := Data.num("battle", "ground.field", 3.4)
	var town_clear := Data.num("battle", "ground.town_clear", 0.4)
	var farm_clear: float = field + Data.num("battle", "ground.farm_clear", 4.8)
	for w in walls:
		if stage._flat_gap(c, w[0]) < float(w[1]) + field + town_clear:
			return false
	for f in farms:
		if stage._flat_gap(c, f) < farm_clear:
			return false
	return true


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
