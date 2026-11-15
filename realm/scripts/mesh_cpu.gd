extends RefCounted
## A mesh's own arrays (vertices, indices) on the CPU, for whoever measures a mesh (nav_ground's feet, people's
## dress, roadside's hamlets). The renderer is never asked for them during play: a mesh's maker hands its plain arrays
## over (keep: house_builder's ImporterMesh), and a model loaded from a file is read back once and kept here, never
## per copy (supervisor, run 3: each surface_get_arrays waits on the GPU, 'timeout waiting for fence' in people._front_at
## and nav_ground._foot_of).

static var _of := {}  # mesh instance id -> its maker's ImporterMesh, or the surfaces' arrays read once


## `mesh`'s arrays are `plain`'s (an ImporterMesh with the same surfaces): nothing is read back for it.
static func keep(mesh: Mesh, plain: ImporterMesh) -> void:
	_of[mesh.get_instance_id()] = plain


## The maker's plain arrays `mesh` was made from (keep), or null: what a kept mesh is written from (kept.gd).
static func plain(mesh: Mesh) -> ImporterMesh:
	var got: Variant = _of.get(mesh.get_instance_id())
	return got if got is ImporterMesh else null


## Surface `s` of `mesh`, as Mesh.ARRAY_* arrays.
static func arrays(mesh: Mesh, s: int) -> Array:
	var id := mesh.get_instance_id()
	var got: Variant = _of.get(id)
	if got == null:
		var read: Array = []
		for i in mesh.get_surface_count():
			read.append(mesh.surface_get_arrays(i))
		_of[id] = read
		got = read
	if got is ImporterMesh:
		return (got as ImporterMesh).get_surface_arrays(s)
	return got[s]
