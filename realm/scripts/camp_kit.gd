extends RefCounted
## The pieces every camp in the field is made of, one place for both (the besiegers' camp, siege_camp.gd; a host's
## camp where it holds, army_camp.gd): the house's canvas and a cook fire with men sat round it. The props kit's
## banner cloth and fire pit, fire.gd's flames.

const Real := preload("res://scripts/realistic.gd")
const Fire := preload("res://scripts/fire.gd")


## The props kit's banner cloth in `c`, in triplanar (a woven canvas, not a flat colour).
static func cloth(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = null
	var path := "res://assets/props/Banner_1.gltf"
	if ResourceLoader.exists(path):
		var n: Node = (load(path) as PackedScene).instantiate()
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var msh: Mesh = (mi as MeshInstance3D).mesh
			for s in (msh.get_surface_count() if msh else 0):
				var src := (mi as MeshInstance3D).get_active_material(s)
				if src is StandardMaterial3D and String(src.resource_name) == "MI_Banner":
					m = (src as StandardMaterial3D).duplicate()
		n.free()
	if m == null:
		m = StandardMaterial3D.new()
	m.albedo_color = c
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 4.0
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## A cook fire at `p` under `root`: the kit's pit, flames, and `sitters` soldiers in `col` sat round it facing it.
static func fire(scenes: Node, root: Node3D, p: Vector3, col: Color, sitters: int, r: RandomNumberGenerator) -> void:
	var pit := Real.one("fire_pit")
	var model: Node3D = Real.make(pit) if pit != "" else null
	if model:
		model.position = p
		root.add_child(model)
	Fire.hearth(root, p)
	for j in sitters:
		var ang := r.randf() * TAU
		var q := p + Vector3(cos(ang), 0, sin(ang)) * 0.12
		var f: Node3D = scenes.people.make(r, "soldier", col, "adult")
		f.position = scenes.stand(q)
		f.rotation.y = atan2(p.x - q.x, p.z - q.z)
		root.add_child(f)
		scenes.people.play(f, ["Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged"][r.randi() % 3], r.randf_range(0.9, 1.1))
