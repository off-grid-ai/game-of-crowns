extends SceneTree
## Headless guard: a town changing hands redraws only its own road (combined run 6, 2026-11-15: every King's and lord's
## road and its roadside redrawn on each capture of a battle, kings_road.paint 578 ms a call, triangles 5.4M -> 8.2M,
## 1 fps). A realm of Kingsmere, two great houses' seats and four towns; one town's owner changes ten times, the roads
## drawn after each (routes handed back as the navigation's worker would, straight). Asserts after each change: only
## that town's lord's road was drawn anew (every other road keeps its node), no stretch was painted for the others,
## and the roads' nodes don't grow; and drawing paints nothing at once (a stretch at a time on the frame's budget).
## Exit 1 on failure.
##   arch -arm64 godot --headless --path realm -s res://tools/roads_change_probe.gd

const Roads := preload("res://scripts/roads.gd")
const RoadsProbe := preload("res://tools/roads_probe.gd")


## The realm's store as roads.gd reads it (awareness.gd rec): its cities.
class Store extends Node:
	var cities: Array = []
	func rec(key: String, default: Variant = null) -> Variant:
		return cities if key == "cities" else default


class Land extends RoadsProbe.FlatLand:
	func world_pos(x: float, y: float) -> Vector3:
		return Vector3(x, 0.0, y)


var roads
var store := Store.new()
var _bad := 0


func _initialize() -> void:
	preload("res://tools/watchdog.gd").arm(self, 120.0)
	root.add_child(store)
	Engine.set_meta("awareness", store)
	var land := Land.new()
	root.add_child(land)
	roads = Roads.new()
	roads.terrain = land
	root.add_child(roads)
	store.cities = [
		{"id": 1, "title": "Kingsmere", "x": 0, "y": 0, "owner": 1, "capital": true},
		{"id": 2, "title": "Ashford", "x": 20, "y": 0, "owner": 2, "capital": true},
		{"id": 3, "title": "Brackwater", "x": 0, "y": 20, "owner": 3, "capital": true},
		{"id": 4, "title": "Dunmere", "x": 10, "y": 10, "owner": 2},
		{"id": 5, "title": "Elmstead", "x": 20, "y": 10, "owner": 2},
		{"id": 6, "title": "Fallow", "x": 10, "y": 20, "owner": 3},
		{"id": 7, "title": "Greyholt", "x": 5, "y": 15, "owner": 3},
	]
	_run.call_deferred()


func _run() -> void:
	await _draw()
	var nodes0 := _count(roads)
	var keys0: Array = roads._ways.keys()
	_check(keys0.size() == 6, "the realm's roads drawn: %s" % str(keys0))
	var whole := 0
	for n in 10:
		var town: Dictionary = store.cities[3]
		town["owner"] = 3 if int(town["owner"]) == 2 else 2  # Dunmere taken, and taken back
		var before := {}
		for k in roads._ways:
			before[k] = roads._ways[k]["node"]
		var painted0: int = roads._painted.size()
		whole = maxi(whole, await _draw())
		var fresh: Array = []
		for k in roads._ways:
			if before.get(k) != roads._ways[k]["node"]:
				fresh.append(k)
		var want := "lords:4:%d" % (2 if int(town["owner"]) == 2 else 3)
		_check(fresh == [want], "change %d: only Dunmere's road drawn anew (%s)" % [n + 1, str(fresh)])
		_check(roads._painted.size() - painted0 <= 2, "change %d: only its stretches painted (%d records more)" % [n + 1, roads._painted.size() - painted0])
	var nodes1 := _count(roads)
	_check(nodes1 <= nodes0, "the roads' nodes don't grow (%d after the first drawing, %d after ten changes)" % [nodes0, nodes1])
	_check(whole == 0, "drawing asks nothing painted at once: the stretches go on the frame's budget (%d painted in the call)" % whole)
	print("ROADS CHANGE %s" % ("PASS" if _bad == 0 else "FAIL (%d)" % _bad))
	quit(0 if _bad == 0 else 1)


## Draws the roads as main does and hands back each asked route (straight) until all are painted: how many stretches
## kings_road() itself painted (none: each is painted by _process on the budget).
func _draw() -> int:
	var p_call: int = roads._painted.size()
	roads.kings_road()
	var most: int = roads._painted.size() - p_call
	for f in 600:
		for a: Array in roads._asks:
			roads._routed.append([a[2], PackedVector3Array([a[0], a[0].lerp(a[1], 0.5), a[1]]), 0])
		roads._asks.clear()
		await process_frame
		await process_frame  # nodes queued for freeing gone
		if roads._routed.is_empty() and roads._paint_jobs.is_empty() and roads._asks.is_empty():
			break
	return most


func _count(n: Node) -> int:
	var c := 1
	for k in n.get_children():
		c += _count(k)
	return c


func _check(ok: bool, what: String) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_bad += 1
