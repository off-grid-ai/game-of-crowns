extends Node3D
## Paths worn by real feet (Foundation, Manor Lords): where townsfolk and carters
## walk, the grass thins to bare earth; where nobody goes any more it grows back.
## The ground's one wear record (finesse catalogue's shared facts: ground wear),
## later read for snow tracks and mud in rain too.
##
## Terrain3D's own maps hold one value per vertex (a game unit, ~8 m): too coarse
## for a footpath. So the wear is a small image per patch of land people use
## (TILE units square, ~0.5 m a pixel), stamped from the people's positions a few
## times a second on the CPU, uploaded every few seconds, and drawn as a soft
## earth-coloured decal under the roads (the decals the roads and squares use).
## On with realm/data/ground.json wear.on.

const Data := preload("res://scripts/data.gd")
static var ON: bool = bool(Data.value("ground", "wear.on", false))

const TILE := 8.0  # game units a patch spans
const PX := 128  # its image's side (TILE units over PX pixels: ~0.5 m a pixel)
var STEP: float = Data.num("ground", "wear.step", 0.012)  # wear a stamp adds (0..1)
var GROW: float = Data.num("ground", "wear.growBack", 0.002)  # wear lost each upload, where nobody walks
var EVERY: float = Data.num("ground", "wear.stampEvery", 0.25)  # seconds between stamps
var UPLOAD: float = Data.num("ground", "wear.uploadEvery", 3.0)  # seconds between uploads
var COLOUR: Color = (func():
	var c: Array = Data.value("ground", "wear.colour", [0.47, 0.38, 0.27])
	return Color(float(c[0]), float(c[1]), float(c[2]))).call()

var terrain: Node3D
var _tiles := {}  # Vector2i -> {img, tex, decal, dirty}
var _stamp_t := 0.0
var _up_t := 0.0
var _was := {}  # a person (instance id) -> where they stood at the last stamp
var WALK: float = Data.num("ground", "wear.walkMin", 0.01)
var STONE: bool = bool(Data.value("ground", "wear.onStone", false))  # wear earth into laid stone too (it read as a mud band across the square)
var _stone: Array = []  # [a, b, half] in the world: each town's paved square, streets and forecourt (towns.gd meta paved)
var _stone_t := -1  # when the list was last read (msec)  # moved at least this far (units) since the last stamp to wear the ground


func _process(delta: float) -> void:
	_stamp_t += delta
	_up_t += delta
	if _stamp_t >= EVERY:
		_stamp_t = 0.0
		# Paths, not pads: only feet that moved since the last stamp wear the ground. A man standing at
		# the drill or a stall stamped the same pixels four times a second and wore a 1.5 m square of bare
		# earth under himself (batch 7 review #13: the bailey's figures on brown blob pads).
		var seen := {}
		for n in get_tree().get_nodes_in_group("people"):
			var p := n as Node3D
			if p and p.is_visible_in_tree() and not p.has_meta("mounted"):
				var id := p.get_instance_id()
				var at := p.global_position
				seen[id] = at
				if _was.has(id) and Vector2(at.x - (_was[id] as Vector3).x, at.z - (_was[id] as Vector3).z).length() >= WALK and not _on_stone(at):
					_stamp(at)
		_was = seen
	if _up_t >= UPLOAD:
		_up_t = 0.0
		_facts()
		_upload()


# --- the realm's own traffic: hosts and roads (ground.json wear.hosts, wear.roads) ------------------------------
# 03-army: dusty bare earth under the column and its camp, the verges of the roads worn. From the facts, not painted
# on: the hosts in the field as the awareness mirror holds them (every house's: realm armies, from /world's units),
# the land route each one moved by between two readings (land_paths, roads cheap), and Freeciv's roads (rec roads).
var HOSTS: Dictionary = Data.value("ground", "wear.hosts", {})
var ROADS: Dictionary = Data.value("ground", "wear.roads", {})
var _hosts_was: Array = []  # [owner, world point] of each host at the last reading
var _roads_sig := -1  # the road list's size when last laid
var _road_queue: Array = []  # road links still to wear: [a, its bow, b]


func _facts() -> void:
	var aw: Variant = get_tree().current_scene.get("awareness") if get_tree().current_scene else null
	if aw == null or terrain == null:
		return
	if not HOSTS.is_empty():
		var now: Array = []
		for h in (aw.realm.get_var(&"armies", [], false) as Array):
			var at: Vector3 = terrain.world_pos(float(h["x"]), float(h["y"]))
			var men := float(h.get("men", 0))
			var r := minf(float(HOSTS.get("camp_max", 2.4)), float(HOSTS.get("camp", 0.6)) + float(HOSTS.get("camp_per_men", 0.12)) * sqrt(men))
			_brush(at, r, float(HOSTS.get("step", 0.05)))
			# Where it came from: the nearest of the house's hosts at the last reading, if it has moved since.
			var best: Variant = null
			for w in _hosts_was:
				if int(w[0]) == int(h["owner"]) and (best == null or (w[1] as Vector3).distance_to(at) < (best as Vector3).distance_to(at)):
					best = w[1]
			if best != null and (best as Vector3).distance_to(at) > 0.5 and (best as Vector3).distance_to(at) < float(HOSTS.get("track_most", 24.0)):
				var route: PackedVector3Array = terrain.paths.land_path(best, at)
				for i in route.size() - 1:
					_band(route[i], route[i + 1], r * float(HOSTS.get("track", 0.5)), float(HOSTS.get("step", 0.05)) * 3.0, false)
			now.append([int(h["owner"]), at])
		_hosts_was = now
	if not ROADS.is_empty():
		var roads: Array = aw.rec("roads", [])
		if roads.size() != _roads_sig:
			_roads_sig = roads.size()
			_road_queue.clear()
			var on := {}
			for r in roads:
				on[Vector2i(int(r[0]), int(r[1]))] = true
			for t: Vector2i in on:
				for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
					if on.has(t + d):
						var a: Vector3 = terrain.world_pos(t.x, t.y)
						var b: Vector3 = terrain.world_pos(t.x + d.x, t.y + d.y)
						_road_queue.append([a, terrain.paths.road_bow(a, b), b])
		# A few road links each reading, never the whole network in one frame.
		var w := float(ROADS.get("width", 0.5))
		for i in mini(int(ROADS.get("per_reading", 12)), _road_queue.size()):
			var e: Array = _road_queue.pop_back()
			_band(e[0], e[1], w, float(ROADS.get("worn", 0.45)), true)
			_band(e[1], e[2], w, float(ROADS.get("worn", 0.45)), true)


## Wear along a segment, `half` units either side, soft at its edges; `hold` also raises the patch's floor there (a
## road's verges stay worn: growing back stops at the floor).
func _band(a: Vector3, b: Vector3, half: float, amount: float, hold: bool) -> void:
	var n := maxi(1, ceili(a.distance_to(b) / maxf(half * 0.7, 0.1)))
	for i in n + 1:
		_brush(a.lerp(b, float(i) / n), half, amount / sqrt(float(n) * 0.2 + 1.0), hold)


## Soft round wear, `r` units across its radius, strongest at its middle, never into laid stone.
func _brush(at: Vector3, r: float, amount: float, hold := false) -> void:
	if _on_stone(at):
		return
	var rp := maxi(1, int(r / TILE * PX))
	for oy in range(-rp, rp + 1, 1):
		for ox in range(-rp, rp + 1, 1):
			var d := Vector2(ox, oy).length() / float(rp)
			if d > 1.0:
				continue
			var p := at + Vector3(float(ox) / PX * TILE, 0.0, float(oy) / PX * TILE)
			var key := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
			var t: Dictionary = _tiles.get(key, {})
			if t.is_empty():
				t = _new_tile(key)
			var x := clampi(int((p.x / TILE - key.x) * PX), 0, PX - 1)
			var y := clampi(int((p.z / TILE - key.y) * PX), 0, PX - 1)
			var k := amount * (1.0 - d * d)
			var img: Image = t["img"]
			var c := img.get_pixel(x, y)
			c.a = minf(1.0, c.a + k)
			img.set_pixel(x, y, c)
			if hold:
				var fl: PackedByteArray = t["floor"]
				fl[y * PX + x] = maxi(fl[y * PX + x], int(minf(1.0, k * 2.0) * 255.0 * float(ROADS.get("floor", 0.6))))
			t["dirty"] = true


## How worn the ground is at a world point, 0..1 (snow tracks and mud read this).
func wear_at(at: Vector3) -> float:
	var key := Vector2i(floori(at.x / TILE), floori(at.z / TILE))
	if not _tiles.has(key):
		return 0.0
	var x := clampi(int((at.x / TILE - key.x) * PX), 0, PX - 1)
	var y := clampi(int((at.z / TILE - key.y) * PX), 0, PX - 1)
	return (_tiles[key]["img"] as Image).get_pixel(x, y).a


func _stamp(at: Vector3) -> void:
	var key := Vector2i(floori(at.x / TILE), floori(at.z / TILE))
	var t: Dictionary = _tiles.get(key, {})
	if t.is_empty():
		t = _new_tile(key)
	var img: Image = t["img"]  # the store itself: a stamp sets a few pixels, nothing is copied
	var cx := int((at.x / TILE - key.x) * PX)
	var cy := int((at.z / TILE - key.y) * PX)
	# A footprint a pixel or two across, strongest in the middle.
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or y < 0 or x >= PX or y >= PX:
				continue
			var c := img.get_pixel(x, y)
			c.a = minf(1.0, c.a + STEP * (1.0 if dx == 0 and dy == 0 else 0.4))
			img.set_pixel(x, y, c)
	t["dirty"] = true


## A patch's wear: luminance-alpha bytes (white, how worn), drawn tinted the earth's colour.
func _new_tile(key: Vector2i) -> Dictionary:
	var data := PackedByteArray()
	data.resize(PX * PX * 2)
	for i in PX * PX:
		data[i * 2] = 255
	var img := Image.create_from_data(PX, PX, false, Image.FORMAT_LA8, data)
	var tex := ImageTexture.create_from_image(img)
	var centre := Vector3((key.x + 0.5) * TILE, 0.0, (key.y + 0.5) * TILE)
	centre.y = terrain.height_at(centre.x, centre.z) if terrain else 0.0
	var decal: Decal = terrain.paint(self, tex, centre, Vector2(TILE, TILE), 0.0, COLOUR, 12.0, 120.0)
	decal.sorting_offset = -2.0  # under the roads, the squares and their verges
	var fl := PackedByteArray()
	fl.resize(PX * PX)  # the least wear each pixel keeps (a road's verges, _brush hold)
	var t := {"img": img, "tex": tex, "decal": decal, "dirty": false, "floor": fl}
	_tiles[key] = t
	_order.append(key)
	return t


## Changed patches to the GPU; and one patch a time grows back a little (each patch every
## few uploads), so the cost stays a few milliseconds whatever the town's size.
var _order: Array[Vector2i] = []
var _next := 0
func _upload() -> void:
	if GROW > 0.0 and not _order.is_empty():
		_next = (_next + 1) % _order.size()
		var t: Dictionary = _tiles[_order[_next]]
		var img: Image = t["img"]
		var data := img.get_data()  # one copy a turn
		var less := int(GROW * 255.0 * _order.size()) + 1  # this patch's share of the growth since its last turn
		var fl: PackedByteArray = t["floor"]
		for i in range(1, data.size(), 2):
			if data[i] > 0:
				data[i] = maxi(fl[i >> 1], data[i] - less)
		img.set_data(PX, PX, false, Image.FORMAT_LA8, data)
		t["dirty"] = true
	for key in _tiles:
		var t: Dictionary = _tiles[key]
		if t["dirty"]:
			(t["tex"] as ImageTexture).update(t["img"])
			t["dirty"] = false


## Whether a world point lies on a town's laid stone (towns.gd _note_paved): no earth is worn into setts. The list is
## read again every few seconds, as towns are built.
func _on_stone(at: Vector3) -> bool:
	if STONE:
		return false
	var now := Time.get_ticks_msec()
	if _stone_t < 0 or now - _stone_t > 5000:
		_stone_t = now
		_stone = []
		for t in get_tree().get_nodes_in_group("town_roots"):
			var o := Vector2((t as Node3D).global_position.x, (t as Node3D).global_position.z)
			for p in (t as Node3D).get_meta("paved", []):
				_stone.append([o + (p[0] as Vector2), o + (p[1] as Vector2), float(p[2])])
	var q := Vector2(at.x, at.z)
	for p in _stone:
		if q.distance_to(Geometry2D.get_closest_point_to_segment(q, p[0], p[1])) <= float(p[2]):
			return true
	return false
