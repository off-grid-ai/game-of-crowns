extends SceneTree
## Guard for town trees in the camera's sight lines (camera_rig asks forest.blocking for the line to what it looks
## at; art target 01-town: the square's, edge and orchard trees are what stand between the lens and the houses).
## towns.gd hands every town tree's crown to the woods (_crown -> forest.add_crown); forest.gd must take it: a crown
## added at the line's middle blocks it, a line beside it stays clear, and clearing the ground there (forest.clear,
## a town's plot) takes it away again. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/town_crown_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var towns_src := FileAccess.get_file_as_string("res://scripts/towns.gd")
	_check(towns_src.contains("woods.add_crown("), "towns.gd hands a town tree's crown to the woods")
	var woods: Node3D = load("res://scripts/forest.gd").new()
	_check(woods.has_method("add_crown"), "forest.gd takes a town tree's crown (add_crown)")
	if woods.has_method("add_crown"):
		var eye := Vector3(3.0, 0.6, 0.0)
		var at := Vector3(-3.0, 0.6, 0.0)
		_check(woods.blocking(eye, at) == 0, "a bare line is clear")
		woods.add_crown(Vector3.ZERO, 1.0)  # a 1-unit tree at the line's middle: its crown from 0.3 to 1.0 up
		_check(woods.blocking(eye, at) == 1, "the town tree's crown blocks the line through it (%d)" % woods.blocking(eye, at))
		_check(woods.blocking(Vector3(3.0, 0.6, 2.0), Vector3(-3.0, 0.6, 2.0)) == 0, "a line beside it stays clear")
		woods.clear(Vector3.ZERO, 0.5)
		_check(woods.blocking(eye, at) == 0, "clearing the ground there takes it away")
	woods.free()
	print("VERDICT %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
