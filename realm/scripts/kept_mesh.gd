extends ArrayMesh
## A kept mesh as its file holds it (kept.gd): its surfaces' plain arrays (Godot's ImporterMesh: vertices, every
## custom array, UV2, bones, each detail level's index list, its materials), never the renderer's copy. Saving a plain
## ArrayMesh asks the renderer for its surfaces back (mesh_get_surface: a GPU read and a fence wait; on the main thread
## a 1.2 s beach ball in Mac's battle run, kept.write; on a worker it tore the GPU's copies). This one is written from
## the arrays its maker already had, on a worker, and made a whole mesh again from them when it is read back.

var _plain: ImporterMesh  # the arrays to write: held from hold() until the write, never kept after a read


## Ready to be written for `mesh`, whose surfaces are `plain`'s (the maker's ImporterMesh): its arrays and levels from
## `plain`, its materials, names, box and metas from `mesh` as it is drawn (a crop's wind, a model's fade).
func hold(mesh: ArrayMesh, plain: ImporterMesh) -> void:
	var same := mesh.get_surface_count() == plain.get_surface_count()
	var im := ImporterMesh.new()
	for b in plain.get_blend_shape_count():
		im.add_blend_shape(plain.get_blend_shape_name(b))
	im.set_blend_shape_mode(plain.get_blend_shape_mode())
	for s in plain.get_surface_count():
		var blends: Array = []
		for b in plain.get_blend_shape_count():
			blends.append(plain.get_surface_blend_shape_arrays(s, b))
		var lods := {}
		for l in plain.get_surface_lod_count(s):
			lods[plain.get_surface_lod_size(s, l)] = plain.get_surface_lod_indices(s, l)
		im.add_surface(plain.get_surface_primitive_type(s), plain.get_surface_arrays(s), blends, lods,
			mesh.surface_get_material(s) if same else plain.get_surface_material(s),
			mesh.surface_get_name(s) if same else plain.get_surface_name(s), plain.get_surface_format(s))
	_plain = im
	custom_aabb = mesh.custom_aabb
	for m in mesh.get_meta_list():
		set_meta(m, mesh.get_meta(m))


## The arrays let go once written (kept.gd), so the CPU copy lives no longer than the write.
func written() -> void:
	_plain = null


func _get_property_list() -> Array:
	return [{"name": "plain", "type": TYPE_OBJECT, "hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "ImporterMesh",
		"usage": PROPERTY_USAGE_STORAGE}]


func _get(property: StringName) -> Variant:
	if property == &"plain":
		return _plain
	return null


func _set(property: StringName, value: Variant) -> bool:
	if property != &"plain":
		return false
	if value is ImporterMesh:
		_build(value)
	return true


## Read back: the surfaces made from the file's arrays, the way ImporterMesh.get_mesh makes them (every level kept).
func _build(im: ImporterMesh) -> void:
	clear_surfaces()
	clear_blend_shapes()
	for b in im.get_blend_shape_count():
		add_blend_shape(im.get_blend_shape_name(b))
	blend_shape_mode = im.get_blend_shape_mode()
	for s in im.get_surface_count():
		var blends: Array = []
		for b in im.get_blend_shape_count():
			blends.append(im.get_surface_blend_shape_arrays(s, b))
		var lods := {}
		for l in im.get_surface_lod_count(s):
			lods[im.get_surface_lod_size(s, l)] = im.get_surface_lod_indices(s, l)
		add_surface_from_arrays(im.get_surface_primitive_type(s), im.get_surface_arrays(s), blends, lods, im.get_surface_format(s))
		var at := get_surface_count() - 1
		surface_set_material(at, im.get_surface_material(s))
		if im.get_surface_name(s) != "":
			surface_set_name(at, im.get_surface_name(s))
