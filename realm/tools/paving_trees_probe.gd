extends SceneTree
## A guard: no tree stands in a town's paving (Mac on round 11's Kingsmere square, "SUPER weird": trees planted in the
## setts, one in the crowd). The crown's square is laid the way towns.gd lays it (towns.json paving: setts
## square x square_r across, square_aspect deep, turned), then towns.gd's own shade-tree and tree-foot placers run on
## flat stand-in land over many seeds. Every tree or shrub they set down (assets.json kind garden) is tested against
## the setts rectangle; prints CHECK lines, exits 1 when any stands on the stone.
##   arch -arm64 godot --headless --path realm -s res://tools/paving_trees_probe.gd

const Towns := preload("res://scripts/towns.gd")
const Real := preload("res://scripts/realistic.gd")
const Data := preload("res://scripts/data.gd")


class FlatLand extends Node3D:
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true


func _init() -> void:
	var land := FlatLand.new()
	var pave: Dictionary = Data.value("towns", "paving", {})
	var square_r := float(Towns.market_knobs_for("crown").get("square_r", 2.1))
	var span := square_r * float(pave.get("square", 2.0))
	var size := Vector2(span, span * float(pave.get("square_aspect", 0.9)))
	var on_stone := 0
	var trees := 0
	var first := ""
	for seed in 12:
		var t: Node3D = Towns.new()
		t.terrain = land
		t.set("_rank", "crown")
		var root := Node3D.new()
		var yaw := seed * 0.7
		if t.has_method("_note_setts"):
			t.call("_note_setts", root, size, yaw)  # the build's own record of where it laid the setts
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + seed
		t.call("_square_trees", root, Vector3.ZERO, square_r, [], [[Vector3.ZERO, square_r]], rng)
		var batch: Dictionary = t.get("_batch")
		for kind in batch:
			var comp := Real.component_of(String(kind))
			if comp == "" or String(Data.value("assets", "components.%s.kind" % comp, "")) != "garden":
				continue
			for xf in batch[kind]:
				var p: Vector3 = (xf as Transform3D).origin
				trees += 1
				var l := Basis(Vector3.UP, -yaw) * Vector3(p.x, 0, p.z)
				if absf(l.x) <= size.x * 0.5 and absf(l.z) <= size.y * 0.5:
					on_stone += 1
					if first == "":
						first = "%s at (%.2f, %.2f), seed %d" % [kind, p.x, p.z, seed]
		root.free()
		t.free()
	land.free()
	print("CHECK paving trees: %d trees and shrubs set round the crown's square over 12 seeds, %d on the setts%s" % [trees, on_stone, (" (first: %s)" % first) if first != "" else ""])
	print("CHECK paving trees: %s" % ("PASS" if on_stone == 0 else "FAIL"))
	quit(1 if on_stone > 0 else 0)
