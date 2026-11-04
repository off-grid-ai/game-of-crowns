extends Node3D
## Armies, settlers and wild beasts: one small figure per unit, coloured by house,
## gliding between tiles as Freeciv moves them.

var terrain: Node3D
var _figures := {}  # unit id -> {node, target}
var _body := CapsuleMesh.new()
var _beast := BoxMesh.new()
var _mats := {}
var _people = preload("res://scripts/people.gd").new()
var turn_seconds := 12.0

const BEASTS := ["Bear", "Wolf", "Lion", "Tiger", "Elephant", "Crocodile", "Polar Bear", "Snake", "Mammoth", "Jaguar", "Kraken", "Giant Squid", "Dragon", "Monkey", "Moose", "Deer", "Buffalo"]


func _ready() -> void:
	_body.radius = 0.12
	_body.height = 0.5
	_beast.size = Vector3(0.45, 0.28, 0.22)


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.8
		_mats[key] = m
	return _mats[key]


var _town_tiles := {}


func sync(world: Dictionary, houses: Dictionary) -> void:
	turn_seconds = float(world.get("turnSeconds", 12))
	var seen := {}
	var per_tile := {}
	_town_tiles.clear()
	for c in world.get("cities", []):
		_town_tiles["%d,%d" % [int(c["x"]), int(c["y"])]] = true
	for u in world.get("units", []):
		var id := int(u["id"])
		seen[id] = true
		var key := "%d,%d" % [int(u["x"]), int(u["y"])]
		var slot: int = per_tile.get(key, 0)
		per_tile[key] = slot + 1
		if slot >= 6:
			continue
		var house: Dictionary = houses.get(int(u["owner"]), {})
		var wild := bool(house.get("wild", false)) or String(u["type"]) in BEASTS
		# Garrisons stand guard at the town's edge, not in its square; armies in
		# the field stand in a loose ring around their banner.
		var in_town: bool = _town_tiles.has(key)
		var ang := slot * 1.05 + (0.4 if in_town else 0.0)
		var ring := 1.6 + slot * 0.08 if in_town else (0.0 if slot == 0 else 0.55)
		var target: Vector3 = terrain.world_pos(float(u["x"]), float(u["y"])) + Vector3(cos(ang), 0, sin(ang)) * ring
		target.y = terrain.height_at(target.x, target.z)
		if not _figures.has(id):
			var node: Node3D
			if wild:
				var mi := MeshInstance3D.new()
				mi.mesh = _beast
				mi.material_override = _mat(Color(0.35, 0.27, 0.2))
				node = mi
			else:
				var rng := RandomNumberGenerator.new()
				rng.seed = id
				node = _people.make(rng, "soldier", Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.35), "adult")
			node.position = target
			add_child(node)
			if not wild and slot == 0:
				_banner(node, Color.from_string(String(house.get("color", "#888")), Color.GRAY), house)
			_figures[id] = {"node": node, "target": target, "wild": wild, "from": target, "t": 1.0, "bow": String(u["type"]) in ["Archers", "Longbowmen", "Crossbowmen"]}
		if _figures[id]["target"].distance_to(target) > 0.01:
			_figures[id]["from"] = _figures[id]["node"].position
			_figures[id]["path"] = terrain.land_path(_figures[id]["node"].position, target)
			_figures[id]["t"] = 0.0
		_figures[id]["target"] = target
	for id in _figures.keys():
		if not seen.has(id):
			_figures[id]["node"].queue_free()
			_figures.erase(id)


## A company's standard: the house's banner on a pole.
func _banner(soldier: Node3D, color: Color, house: Dictionary) -> void:
	var b: Node3D = preload("res://scripts/heraldry.gd").standard(house, color, 3.4)
	b.position = Vector3(0.35, 0, -0.1)
	soldier.add_child(b)


func _process(delta: float) -> void:
	for id in _figures:
		var f: Dictionary = _figures[id]
		var n: Node3D = f["node"]
		var t: Vector3 = f["target"]
		if f["wild"]:
			n.position = n.position.lerp(t + Vector3(0, 0.14, 0), clampf(delta * 1.5, 0.0, 1.0))
			continue
		# March across the whole turn, so armies are always visibly on the move.
		if f["t"] < 1.0:
			f["t"] = minf(1.0, f["t"] + delta / maxf(2.0, turn_seconds * 0.9))
			var path: PackedVector3Array = f.get("path", PackedVector3Array([f["from"], t]))
			var p: Vector3 = terrain.along(path, f["t"])
			var dir: Vector3 = terrain.along(path, minf(1.0, f["t"] + 0.02)) - p
			if Vector2(dir.x, dir.z).length() > 0.05:
				n.rotation.y = atan2(dir.x, dir.z)
			n.position = Vector3(p.x, terrain.height_at(p.x, p.z), p.z)
			_people.play(n, "Walk")
		else:
			_people.play(n, "Bow_Idle" if f.get("bow", false) else "Sword_Idle")
