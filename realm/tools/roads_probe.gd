extends SceneTree
## Headless guard for the painted roads' records (clip4: 694 "previously freed" errors from roads.gd _paint_run).
## General problem: a cache keeps nodes it does not own; when their owner frees them (a town rebuilt as it grows), the
## cache hands the dead node back. The rule: whoever keeps a record of someone else's node drops it once the node is
## gone, before using it. Here: a road stretch painted under a town (towns.gd lays its tracks under its own root), the
## town freed as a rebuild does, then the town's square paved (clear_in) and another road laid (which trims against
## every paved square). Asserts: no painted record still holds the freed town, nothing is painted onto it, and the
## stretches under the realm itself are kept and trimmed. Exit 1 on failure.
##   arch -arm64 godot --headless --path realm -s res://tools/roads_probe.gd

const Roads := preload("res://scripts/roads.gd")

## The little of the terrain that painting a road asks for: flat dry land, decals and tiles.
class FlatLand extends Node3D:
	func is_land(_x: float, _z: float) -> bool:
		return true
	func in_river(_x: float, _z: float) -> bool:
		return false
	func ford(_a: Vector3, _b: Vector3, _half: float) -> void:
		pass
	func road_bow(a: Vector3, b: Vector3) -> Vector3:
		return a.lerp(b, 0.5)
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func tiled(_path: String, _nx: int, _ny: int, _edge := "") -> Texture2D:
		return ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	func paint(parent: Node3D, tex: Texture2D, at: Vector3, size: Vector2, yaw := 0.0, tint := Color.WHITE, depth := 1.5, _fade := 40.0) -> Decal:
		var d := Decal.new()
		d.texture_albedo = tex
		d.modulate = tint
		d.size = Vector3(size.x, depth, size.y)
		d.position = at
		d.rotation.y = yaw
		parent.add_child(d)
		return d

var land: FlatLand
var roads
var town: Node3D
var frame := 0
var fails: Array[String] = []


func _process(_d: float) -> bool:
	frame += 1
	if frame == 1:
		preload("res://tools/watchdog.gd").arm(self)
		land = FlatLand.new()
		get_root().add_child(land)
		roads = Roads.new()
		roads.terrain = land
		get_root().add_child(roads)
		town = Node3D.new()
		town.name = "Town"
		get_root().add_child(town)
		roads._segment(Vector3(-3, 0, 0), Vector3(3, 0, 0), town)  # a town's own track, under its root
		roads._segment(Vector3(0, 0, -3), Vector3(0, 0, 3))  # a realm road, under the roads node
		town.free()  # the town rebuilt: its old root and everything under it gone
		return false
	if frame == 2:
		roads.clear_in(Vector2.ZERO, 1.0)  # the new town's square paved over the crossing
		roads._segment(Vector3(-3, 0, 2), Vector3(3, 0, 2))  # a road laid after it
		return false
	var dead := 0
	var realm := 0
	for st in roads._painted:
		if not is_instance_valid(st[4]):
			dead += 1
		elif st[4] == roads:
			realm += 1
	print("ROADS %d painted records, %d holding a freed node, %d under the realm" % [roads._painted.size(), dead, realm])
	if dead > 0:
		fails.append("%d painted records still hold a freed town" % dead)
	if realm < 2:
		fails.append("the realm's own road was lost (%d stretches kept)" % realm)
	for f in fails:
		print("ROADS FAIL " + f)
	print("ROADS VERDICT: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
	return true
