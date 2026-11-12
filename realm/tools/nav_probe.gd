extends SceneTree
## Headless guard for the towns' walk maps (Mac: "the cart just moved through the well"). General problem: walkers in
## a town must path round everything that stands there, whoever set it down; the proven block is Godot's
## NavigationServer2D bake, fed from the town's own geometry (nav_ground.gd), never from lists a placer must remember
## to fill. A made-up town: a house, a well put down with no footprint registered, a stall, a town wall ring built as
## one mesh, a man (skinned) and a box hung in the air. Asserts:
##   1. the well, the house and the stall are obstacles though none registered a footprint;
##   2. the wall ring is traced as cells, not one box over the whole town;
##   3. the man and the hung box are no obstacles;
##   4. the walk map baked from them (town_nav.blocks_of, Godot's NavigationServer2D bake) lays no walkable ground on
##      anything standing, and still has ground to walk. (Headless Godot never syncs a navigation map, so its paths
##      can't be asked here; in the game the play line `navprobe Kingsmere 200` walks them.)
## It also prints what the old footprint lists would have blocked in the same town (nothing was registered: none).
## Exit 1 on any failure.
##   arch -arm64 godot --headless --path realm -s res://tools/nav_probe.gd

const NavGround := preload("res://scripts/nav_ground.gd")
const TownNav := preload("res://scripts/town_nav.gd")

## Flat dry land at height 0, all the walk map asks of the terrain.
class FlatLand extends Node3D:
	var built := true
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true
	func walkable(_x: float, _z: float) -> bool:
		return true

var town: Node3D
var land: FlatLand
var frame := 0
var fails: Array[String] = []


func _process(_delta: float) -> bool:
	frame += 1
	if frame == 1:
		_build()
		return false
	_check()
	for f in fails:
		print("NAV FAIL " + f)
	print("NAV VERDICT: %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
	return true


func _box(size: Vector3, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	parent.add_child(mi)
	mi.position = at + Vector3(0, size.y * 0.5, 0)
	return mi


func _build() -> void:
	land = FlatLand.new()
	get_root().add_child(land)
	town = Node3D.new()
	town.name = "Town"
	town.set_meta("reach", 3.0)
	get_root().add_child(town)
	_box(Vector3(0.6, 0.5, 0.4), Vector3(1.0, 0, 0), town).name = "House"
	var well := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.2
	cm.height = 0.15
	well.mesh = cm
	well.name = "Well"
	town.add_child(well)
	well.position = Vector3(0, 0.075, 0)
	_box(Vector3(0.36, 0.3, 0.18), Vector3(-1.0, 0, 0.6), town).name = "Stall"
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.5
	tm.outer_radius = 2.7
	ring.mesh = tm
	ring.name = "TownWall"
	town.add_child(ring)
	ring.position = Vector3(0, 0.1, 0)
	var man := Skeleton3D.new()
	man.name = "Man"
	town.add_child(man)
	_box(Vector3(0.1, 0.3, 0.1), Vector3(-0.5, 0, -0.5), man)
	_box(Vector3(0.1, 0.1, 0.1), Vector3(0.5, 3.0, -0.5), town).name = "Hung"


func _covers(outlines: Array, p: Vector2) -> bool:
	for fp: PackedVector2Array in outlines:
		if Geometry2D.is_point_in_polygon(p, fp):
			return true
	return false


func _check() -> void:
	var o: Dictionary = NavGround.outlines(town, land)
	var all: Array = o["town"]
	# 1. What stands there is in the way, registered or not.
	for t in [["the well", Vector2(0, 0)], ["the house", Vector2(1.0, 0)], ["the stall", Vector2(-1.0, 0.6)]]:
		if not _covers(all, t[1]):
			fails.append("%s is no obstacle" % t[0])
	# 2. The ring is cells, the ground inside it open.
	var biggest := 0.0
	var ring_cells := 0
	for fp: PackedVector2Array in all:
		biggest = maxf(biggest, absf(NavGround._area(fp)))
		var mid: Vector2 = (fp[0] + fp[2]) * 0.5
		if mid.length() > 2.3:
			ring_cells += 1
	if biggest > 1.5:
		fails.append("an outline %.2f units square: a big mesh drawn as one box" % biggest)
	if ring_cells < 50:
		fails.append("the wall ring traced as %d cells (expected many)" % ring_cells)
	if _covers(all, Vector2(0, 1.6)):
		fails.append("open ground inside the ring is blocked")
	# 3. Movers and hung things are not walls.
	if _covers(all, Vector2(-0.5, -0.5)):
		fails.append("the man is an obstacle")
	if _covers(all, Vector2(0.5, -0.5)):
		fails.append("the box hung in the air is an obstacle")
	# 4. The baked walk map lays no ground on anything standing.
	var outline := PackedVector2Array()
	for k in 24:
		outline.append(Vector2.from_angle(TAU * k / 24) * 3.0)
	var poly := NavigationPolygon.new()
	poly.agent_radius = TownNav.AGENT
	poly.cell_size = TownNav.CELL
	var src := NavigationMeshSourceGeometryData2D.new()
	src.add_traversable_outline(outline)
	for b in TownNav.blocks_of(town, land):
		src.add_obstruction_outline(b)
	NavigationServer2D.bake_from_source_geometry_data(poly, src)
	var verts := poly.get_vertices()
	var on := 0
	for k in poly.get_polygon_count():
		var ids := poly.get_polygon(k)
		var mid := Vector2.ZERO
		for v in ids:
			mid += verts[v] / ids.size()
		if _covers(all, mid):
			on += 1
	var old := (town.get_meta("footprints", []) as Array).size()
	print("NAV %d outlines (%d ring cells); baked %d walkable polygons, %d of them on something standing; the old footprint lists held %d of the 3 things in the way" % [all.size(), ring_cells, poly.get_polygon_count(), on, mini(old, 3)])
	if poly.get_polygon_count() == 0:
		fails.append("the walk map baked no ground at all")
	if on > 0:
		fails.append("%d walkable polygons lie on something standing" % on)
