extends MultiMeshInstance3D
## One mesh set down many times in one draw (a town's houses, its far stand-ins, its crops). It owns where each copy
## stands (`xfs`, its own frame) and fills its MultiMesh from them, so whoever needs the copies' places (the walk map,
## nav_ground.gd; a burnt house, fire.gd; a kept town, town_store.gd) reads them here. The MultiMesh is never read
## back for them: Godot's headless renderer keeps no instance data, and with the lens's temporal upscaling (MetalFX,
## motion vectors) the renderer keeps two copies of it, the older of which a read can return (supervisor: Mac 10:42's
## torn Kingsmere, read from kept towns). A kept town stores the list, not the renderer's copy, and refills from it.

## Where each copy stands, in this node's frame. Set through make(); read by everyone else; kept with a kept town.
@export var xfs: Array[Transform3D] = []
## Simpler versions this much sooner than Godot's own pick: Smooth's towns.json batch_lod_bias (Mac 2026-11-15, the fps
## round: "I don't think we need as much detail"), Beautiful and Finest batch_lod_bias_rich (Mac 2026-11-20: "I want the
## game fully high quality"; the fps drag was the towns being built again, now baked). Set when the batch stands, so a
## kept town takes it without being made again, and on every batch standing when the choice changes (use_graphics).
static var LOD_BIAS: float = preload("res://scripts/data.gd").num("towns", "batch_lod_bias", 1.0)
const GROUP := "town_batches"


## The graphics choice made (main.gd apply_graphics): the bias for it, on every batch standing. A batch that sets its
## own (countryside.gd, meta lod_bias) keeps it.
static func use_graphics(smooth: bool, tree: SceneTree) -> void:
	var D := preload("res://scripts/data.gd")
	LOD_BIAS = D.num("towns", "batch_lod_bias" if smooth else "batch_lod_bias_rich", 1.0)
	if tree == null:
		return
	for b in tree.get_nodes_in_group(GROUP):
		if not b.has_meta("lod_bias"):
			(b as GeometryInstance3D).lod_bias = LOD_BIAS


func _ready() -> void:
	add_to_group(GROUP)
	lod_bias = LOD_BIAS
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


## The MultiMesh a kept scene packs in a batch's place (town_store.gd, people_store.gd): empty, of the same make, so
## the file keeps the batch's own list (xfs), never the renderer's copy; it refills itself when read (_ready).
static func packed(mm: MultiMesh) -> MultiMesh:
	var empty := MultiMesh.new()
	empty.transform_format = mm.transform_format
	empty.use_colors = mm.use_colors
	empty.use_custom_data = mm.use_custom_data
	empty.mesh = mm.mesh
	return empty
