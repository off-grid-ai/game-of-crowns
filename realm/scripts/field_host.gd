extends "res://scripts/army.gd"
## A host on a battle's field (army_field.gd, field_cells.gd: Mac 2026-11-17, "everything is a cell"). The same host
## as any other, with the answers a battle asks of it: every troop draws a few men by its kind (troop.gd field_men:
## foot 3-3-2, horse 2-2-1), a man a cell (field.cells.size), its troops packed
## close (field.cells.packed), stood where its order puts it (no muster ground cleared around it), and each figure
## drawn where his runner stands, with no chase or sway of its own (the cell rule and his Mover already walked him).

const Troops := preload("res://scripts/troops.gd")  # each regiment as its Troop: how many men it draws, its shape


func _drawn(spec: Dictionary) -> int:
	return Troops.of({"role": String(_unit(String(spec["unit"])).get("role", "melee"))}).field_men()


func _room(r: Dictionary) -> void:
	r["sf"] = Data.num("battle", "field.cells.size", 0.2)
	r["sr"] = r["sf"]


func _line_form(r: Dictionary) -> String:
	return Troops.of(r).field_form()


func _packed() -> Vector2:
	var pk: Array = Data.value("battle", "field.cells.packed", [0.0, 0.0])
	return Vector2(float(pk[0]), float(pk[1]))


## A battle's troop holds no ground in the walk map (Mac 2026-11-17, "why does the red banner run away first"): a held
## block was a hole in the map, so each man's way to the cell ahead first led him out of it, often backward, and every
## route into a hole searched the whole realm. On the field the cells keep one man a cell (field_cells.gd).
func _claim(_r: Dictionary, _xf: Transform3D, _w := -1.0, _d := -1.0) -> void:
	pass


func _free_near(at: Vector3, _right3: Vector3, _fwd3: Vector3, _w: float, _d: float, _taken: Array, _strict: bool, _own: Variant = null) -> Vector3:
	return Vector3(at.x, 0.0, at.z)  # a battle's host stands where its order puts it (Mac 2026-11-17: no muster rules on the field)


## Each living man drawn at his mark (his runner's place, army_field.gd _follow_runners), turning toward the foe he
## fights (r.duel) or his block's facing at follow.turn. The fallen lie where they fell.
func _follow(r: Dictionary, dt: float) -> void:
	var node: Node3D = r["node"]
	var marks: PackedVector3Array = r.get("marks", PackedVector3Array())
	if marks.is_empty() or not node.is_inside_tree():
		return
	var yaws: PackedFloat32Array = r["yaws"]
	var sizes: PackedFloat32Array = r["sizes"]
	var alive: PackedByteArray = r.get("alive", PackedByteArray())
	var face: PackedFloat32Array = r.get("men_yaw", PackedFloat32Array())
	if face.size() != marks.size():
		face = yaws.duplicate()
	var duel: Dictionary = r.get("duel", {})
	var turn := minf(1.0, dt * Data.num("army", "follow.turn", 7.0))
	var vat: VATMultiMeshInstance3D = r["vat"]
	var tall := float(r.get("tall_k", 1.0))
	var still := true
	for s in marks.size():
		if s < alive.size() and alive[s] == 0:
			continue
		var goal: float = duel.get(s, yaws[s])
		face[s] = lerp_angle(face[s], goal, turn)
		if absf(angle_difference(face[s], goal)) > 0.02:
			still = false
		vat.multimesh.set_instance_transform(s, Transform3D(Basis(Vector3.UP, face[s]).scaled(Vector3.ONE * tall * sizes[s]), marks[s]))
	r["men_at"] = marks.duplicate()
	r["men_yaw"] = face
	r["men_still"] = still
