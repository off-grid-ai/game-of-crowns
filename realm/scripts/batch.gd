extends MultiMeshInstance3D
## One mesh set down many times in one draw (a town's houses, its far stand-ins, its crops). It owns where each copy
## stands (`xfs`, its own frame) and fills its MultiMesh from them, so whoever needs the copies' places (the walk map,
## nav_ground.gd; a burnt house, fire.gd; a kept town, town_store.gd) reads them here. The MultiMesh is never read
## back for them: Godot's headless renderer keeps no instance data, and with the lens's temporal upscaling (MetalFX,
## motion vectors) the renderer keeps two copies of it, the older of which a read can return (supervisor: Mac 10:42's
## torn Kingsmere, read from kept towns). A kept town stores the list, not the renderer's copy, and refills from it.

## Where each copy stands, in this node's frame. Set through make(); read by everyone else; kept with a kept town.
@export var xfs: Array[Transform3D] = []


func _ready() -> void:
	if multimesh and multimesh.instance_count != xfs.size():
		fill()  # read back from a kept town: its MultiMesh was kept empty (town_store.gd)


## The MultiMesh filled from `xfs`.
func fill() -> void:
	multimesh.instance_count = xfs.size()
	for i in xfs.size():
		multimesh.set_instance_transform(i, xfs[i])


## A batch of `mesh` standing at each of `at` (Transform3Ds, the batch's frame), named `name`.
static func make(name_: String, mesh: Mesh, at: Array) -> MultiMeshInstance3D:
	var b: MultiMeshInstance3D = (load("res://scripts/batch.gd") as GDScript).new()
	if name_ != "":
		b.name = name_  # unnamed, it takes Godot's own when added
	b.xfs.assign(at)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	b.multimesh = mm
	b.fill()
	return b
