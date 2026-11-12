extends SceneTree
## Guards where rain leaves its marks on a town (weather_fx.gd _puddles / spots; round 12: dark puddle blobs on
## Kingsmere's setts read as stray shadows, mud smeared where the road meets the paving). A stand-in town: the square's
## setts (turned), one paved street out of it, two dirt roads crossing at the heart, uneven ground. Fails (exit 1) when
## any puddle's centre is on laid stone (towns.gd _paved_at, the one owner) or off both a dirt road and the paving's
## gutter, any mud's centre is on laid stone or off a dirt road, or none of either is laid.
##   arch -arm64 godot --headless --path realm -s res://tools/puddle_probe.gd [-- --fx=<another weather_fx.gd>]
## (--fx: a copy of weather_fx.gd from before a change, for the before run; it loads from any path.)

const Towns := preload("res://scripts/towns.gd")
const Data := preload("res://scripts/data.gd")

var _bad := 0
var _done := false


## Two dirt roads through the town's heart at (10, 10): along x and along z, 0.15 either side.
class Roads extends Node:
	func on_path(p: Vector3, margin := 0.0) -> bool:
		return (absf(p.z - 10.0) < 0.15 + margin and absf(p.x - 10.0) < 6.0) or (absf(p.x - 10.0) < 0.15 + margin and absf(p.z - 10.0) < 6.0)


class Ground extends Node:
	func height_at(wx: float, wz: float) -> float:
		return 0.05 * sin(wx * 1.3) * cos(wz * 1.7)


class Main extends Node:
	var terrain: Node
	var roads: Node
	var towns: Node


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var main := Main.new()
	main.terrain = Ground.new()
	main.roads = Roads.new()
	main.towns = Towns.new()
	var root := Node3D.new()
	get_root().add_child(root)
	root.position = Vector3(10, 0, 10)
	root.set_meta("setts", [Vector2(1.35, 1.24), 0.3])  # Kingsmere's square: 2.7 across, a little turned
	root.set_meta("paved", [[Vector2(0, 0), Vector2(0, 4), 0.5]])  # the crown's paved street, out along +z
	var src := "res://scripts/weather_fx.gd"
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--fx="):
			src = String(a).substr(5)
	var WeatherFx: GDScript = load(src)
	var fx: Node = WeatherFx.new()
	var k: Dictionary = Data.value("weather", "puddles", {})
	var n: Node3D = fx.call("_puddles", 7, root, k, main)
	var mud_tex: Texture2D = WeatherFx.call("_blob", "mud")
	var gutter := float(k.get("gutter", 0.35))
	var puddles := 0
	var muds := 0
	for d in n.get_children():
		var p: Vector3 = (d as Decal).global_position
		var local := root.to_local(p)
		var on_stone: bool = main.towns._paved_at(root, local, 0.0)
		var on_dirt: bool = main.roads.on_path(p)
		if (d as Decal).texture_albedo == mud_tex:
			muds += 1
			_check(not on_stone, "mud on the paving at %s" % local)
			_check(on_dirt, "mud off the dirt roads at %s" % local)
		else:
			puddles += 1
			_check(not on_stone, "puddle on the paving at %s" % local)
			_check(on_dirt or main.towns._paved_at(root, local, 0.5 + gutter), "puddle neither on a dirt road nor in the gutter at %s" % local)
	_check(puddles > 0, "no puddles laid")
	_check(muds > 0, "no mud laid")
	print("PUDDLES %s: %d puddles, %d mud, %d problems" % ["PASS" if _bad == 0 else "FAIL", puddles, muds, _bad])
	for x in [main.terrain, main.roads, main.towns, main, fx]:
		x.free()
	root.free()
	quit(1 if _bad > 0 else 0)
	return true


func _check(ok: bool, what: String) -> void:
	if not ok:
		_bad += 1
		print("PUDDLES FAIL ", what)
