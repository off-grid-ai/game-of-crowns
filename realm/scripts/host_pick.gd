extends RefCounted
## Picking a host by its own body (READY.md line 8, "Command the army"; Warcraft III's and Total War's click on
## the unit itself). Every company's standard-bearer on the map (units.gd) and every regiment of a massed host
## (army.gd) carries a pick proxy: an Area3D on PICK_LAYER alone, the company's Freeciv unit id on it (and the
## view that drew it, which can mark that regiment). A click is resolved by Godot's physics ray from the camera at
## the moment of the press, so a tall standard or a lens still moving never mis-picks, as a screen-distance guess
## did (the milestone's command take: "host selected: -1"). host_command.gd turns the unit into its host.

const PICK_LAYER := 1 << 17  # the hosts' pick proxies only (the lens's buildings 19, props 18)


## A pick proxy on `on`: a box `size` (world units, across, up, along) standing on its foot, for unit `unit`,
## drawn by `view`. Sized in the world whatever `on`'s own scale. Returns it, to be resized as the body changes.
static func proxy(on: Node3D, unit: int, size: Vector3, view: Node = null) -> Area3D:
	var a := Area3D.new()
	a.name = "Pick"
	a.collision_layer = PICK_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.set_meta("unit", unit)
	if view:
		a.set_meta("view", view)
	var cs := CollisionShape3D.new()
	cs.shape = BoxShape3D.new()
	a.add_child(cs)
	on.add_child(a)
	fit(a, size)
	return a


## The proxy fitted to a body `size` (world units), its foot on the body's.
static func fit(a: Area3D, size: Vector3) -> void:
	var on := a.get_parent() as Node3D
	var k := Vector3.ONE
	if on:
		var s := on.global_basis.get_scale() if on.is_inside_tree() else on.scale
		k = Vector3(maxf(s.x, 0.001), maxf(s.y, 0.001), maxf(s.z, 0.001))
	var cs := a.get_child(0) as CollisionShape3D
	(cs.shape as BoxShape3D).size = size / k
	cs.position = Vector3(0.0, size.y * 0.5 / k.y, 0.0)


## The host body under `screen` as `cam` sees it now: {unit, view} of the nearest proxy the ray meets, or {}.
static func pick(cam: Camera3D, screen: Vector2) -> Dictionary:
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 4000.0, PICK_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var a: Object = hit.get("collider")
	if a == null or not a.has_meta("unit"):
		return {}
	return {"unit": int(a.get_meta("unit")), "view": a.get_meta("view") if a.has_meta("view") else null}
