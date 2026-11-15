extends RefCounted
## Picking a host by its own body (READY.md line 8, "Command the army"; Warcraft III's and Total War's click on
## the unit itself). Every company's standard-bearer on the map (units.gd) and every regiment of a massed host
## (army.gd) carries a pick proxy: an Area3D on PICK_LAYER alone, the company's Freeciv unit id on it (and the
## view that drew it, which can mark that regiment). A click is resolved by Godot's physics ray from the camera at
## the moment of the press, so a tall standard or a lens still moving never mis-picks, as a screen-distance guess
## did (the milestone's command take: "host selected: -1"). host_command.gd turns the unit into its host.
## A body is small on screen at play zoom (a bearer's box is 0.22 world units across: a few pixels at the strategic
## distance), so a press the ray misses takes the nearest proxy within so many pixels of the pointer instead
## (Warcraft III's and Age of Empires' generous unit pick), still read at the press, from the camera as it is then.

const PICK_LAYER := 1 << 17  # the hosts' pick proxies only (the lens's buildings 19, props 18)
const GROUP := &"host_pick"  # every proxy, for the pick by nearness on screen


## A pick proxy on `on`: a box `size` (world units, across, up, along) standing on its foot, for unit `unit`,
## drawn by `view`. Sized in the world whatever `on`'s own scale. Returns it, to be resized as the body changes.
static func proxy(on: Node3D, unit: int, size: Vector3, view: Node = null) -> Area3D:
	var a := Area3D.new()
	a.name = "Pick"
	a.collision_layer = PICK_LAYER
	a.collision_mask = 0
	a.monitoring = false
	a.monitorable = true
	a.add_to_group(GROUP)
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


## The host body under `screen` as `cam` sees it now: {unit, view} of the nearest proxy the ray meets, else of the
## proxy nearest the pointer within `px` pixels on screen, or {}. `want` (unit id -> bool), when given, passes over
## any other body (a right-click looks for a foe, a click for the King's own).
static func pick(cam: Camera3D, screen: Vector2, px := 0.0, want := Callable()) -> Dictionary:
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.project_ray_origin(screen)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(screen) * 4000.0, PICK_LAYER)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(q)
	var a: Object = hit.get("collider")
	if a != null and a.has_meta("unit") and (not want.is_valid() or want.call(int(a.get_meta("unit")))):
		return _of(a)
	return near(cam, screen, px, want) if px > 0.0 else {}


## The proxy nearest `screen` within `px` pixels as `cam` sees it (its middle, half way up the body), or {}.
static func near(cam: Camera3D, screen: Vector2, px: float, want := Callable()) -> Dictionary:
	var best: Area3D = null
	var best_d := px
	for n in cam.get_tree().get_nodes_in_group(GROUP):
		var a := n as Area3D
		if a == null or not a.is_visible_in_tree() or not a.has_meta("unit"):
			continue
		var cs := a.get_child(0) as CollisionShape3D
		var mid: Vector3 = cs.global_position if cs else a.global_position
		if cam.is_position_behind(mid):
			continue
		var d := cam.unproject_position(mid).distance_to(screen)
		if d < best_d and (not want.is_valid() or want.call(int(a.get_meta("unit")))):
			best_d = d
			best = a
	return _of(best) if best else {}


static func _of(a: Object) -> Dictionary:
	return {"unit": int(a.get_meta("unit")), "view": a.get_meta("view") if a.has_meta("view") else null}
