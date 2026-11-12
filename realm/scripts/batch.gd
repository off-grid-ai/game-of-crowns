extends MultiMeshInstance3D
## One mesh set down many times in one draw (a town's dressing: its bushes, crates and planters). It owns where each
## copy stands (`xfs`, its own frame) and fills its MultiMesh from them, so whoever needs the copies' places (the walk
## map, nav_ground.gd; a probe) reads them here. The MultiMesh can't be read back for them: Godot's headless renderer
## keeps no instance data, and every copy there reads as standing at the batch's origin.

## Where each copy stands, in this node's frame. Set through make(); read by everyone else.
var xfs: Array[Transform3D] = []


## A batch of `mesh` standing at each of `at` (Transform3Ds, the batch's frame), named `name`.
static func make(name_: String, mesh: Mesh, at: Array) -> MultiMeshInstance3D:
	var b: MultiMeshInstance3D = (load("res://scripts/batch.gd") as GDScript).new()
	b.name = name_
	b.xfs.assign(at)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, at[i])
	b.multimesh = mm
	return b
