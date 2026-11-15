extends SceneTree
## Guard for a host that vanishes from the field as the King watches (Mac 2026-11-16, twice: a blue house's host
## standing in the fields by Bitterford beside the King's red host was gone in a moment; earlier a host vanished and
## its banners stayed). The cause: units.gd field_hosts drew a house's column only while the bridge listed its road
## order (/world warhosts, banners), and freed it the sync that order ended (bridge hosts.js warpath: at the walls,
## "no nearer", its goal changed hands), though its men stood where they were, left as a few lone figures (hidden at
## FAR); and any column whose companies changed was freed at once and raised afresh over many frames (a gap).
## No realm: a stub store and land, the real units.gd and army.gd (left unraised: no land to stand on, so no GPU).
##   1. a house's war host on the road, then its order over with its men still on the same tile: the column stays;
##   2. one of its companies falls: a new column is raised under the same key and the old one stands until the new
##      one has (army.gd raised), then goes;
##   3. its companies scatter beyond map.together tiles of the lead: the lead's stays, and gone entirely, it goes;
##   4. a King's host whose companies change: the old column stands until the new one is raised.
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/host_vanish_probe.gd

const UnitsView := preload("res://scripts/units.gd")

const STORE := """extends Node
var units: Array = []
var war: Array = []
var road: Array = []
var crown: Array = []
func banners() -> Array:
	return road
func war_hosts() -> Array:
	return war
func hosts() -> Array:
	return crown
func houses_by_id() -> Dictionary:
	return {6: {"name": "House Highfell", "color": "#4a7bb7"}}
func rec(kind: String, d: Variant = null) -> Variant:
	return units if kind == "units" else d
"""

const LAND := """extends Node3D
var width := 0
var built := false
func world_pos(tx: float, ty: float) -> Vector3:
	return Vector3(tx, 0, ty)
"""

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _alive(v: Variant) -> bool:
	return is_instance_valid(v) and not (v as Node).is_queued_for_deletion()


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var store := Node.new()
	store.set_script(_script(STORE))
	var land := Node3D.new()
	land.set_script(_script(LAND))
	var main := Node3D.new()
	main.set_script(_script("extends Node3D\nvar terrain: Node3D\nvar towns: Node3D\n"))
	main.set("terrain", land)
	root.add_child(main)
	main.add_child(land)
	var view: Node3D = UnitsView.new()
	view.terrain = land
	main.add_child(view)
	await process_frame
	var u := func(id: int, x: int, y: int, owner := 6) -> Dictionary:
		return {"id": id, "owner": owner, "type": "Pikemen", "x": x, "y": y}

	# 1. On the road, then its order over: the men stand where they were.
	store.units = [u.call(10, 5, 5), u.call(11, 5, 5), u.call(12, 5, 5)]
	store.war = [{"owner": 6, "units": [10, 11, 12], "city": 1, "x": 5, "y": 5, "rebel": false}]
	var drawn: Dictionary = view.field_hosts(store)
	var hosts: Dictionary = view.get("_hosts")
	var key: Variant = hosts.keys()[0] if hosts.size() == 1 else null
	var a: Variant = hosts.get(key)
	_check(_alive(a) and drawn.has(10), "a house's war host on the road is drawn as one column")
	store.war = []
	drawn = view.field_hosts(store)
	await process_frame
	_check(_alive(a) and hosts.get(key) == a and drawn.has(10) and drawn.has(12), "its order over, its men still in the field: the same column still stands")

	# 2. A company falls: raised again under the same key, the old one standing until the new one is raised.
	store.units = [u.call(10, 5, 5), u.call(11, 5, 5)]
	drawn = view.field_hosts(store)
	await process_frame
	var b: Variant = hosts.get(key)
	_check(_alive(b) and b != a, "a company fell: a new column is raised for the same host")
	_check(_alive(a), "the old column stands while the new one is being raised (no gap)")
	(b as Node).emit_signal("raised")
	await process_frame
	await process_frame
	_check(not _alive(a), "once the new column stands, the old one goes")

	# 3. Scattered beyond map.together: the lead's company stays the column; all gone, it goes.
	store.units = [u.call(10, 5, 5), u.call(11, 12, 12)]
	drawn = view.field_hosts(store)
	await process_frame
	_check(drawn.has(10) and not drawn.has(11), "a company far from its lead leaves the column (drawn as its own figure)")
	store.units = []
	drawn = view.field_hosts(store)
	await process_frame
	_check(hosts.is_empty(), "its companies all gone: the column goes")

	# 4. A King's host whose companies change.
	store.units = [u.call(1, 3, 3, 7), u.call(2, 3, 3, 7)]
	store.crown = [{"id": 1, "x": 3, "y": 3, "units": [1, 2], "at": null, "aboard": false, "order": null}]
	view.field_hosts(store)
	var c: Variant = hosts.get(1)
	store.units = [u.call(1, 3, 3, 7)]
	store.crown = [{"id": 1, "x": 3, "y": 3, "units": [1], "at": null, "aboard": false, "order": null}]
	view.field_hosts(store)
	await process_frame
	var d: Variant = hosts.get(1)
	_check(_alive(c) and _alive(d) and c != d, "a King's host's companies changed: the old column stands until the new one is raised")
	(d as Node).emit_signal("raised")
	await process_frame
	await process_frame
	_check(not _alive(c), "the new King's column raised: the old one goes")

	print("HOST-VANISH %s (%d fails)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	quit(1 if _fails > 0 else 0)


static func _script(src: String) -> GDScript:
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s
