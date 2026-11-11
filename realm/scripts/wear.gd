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
## On with realm/data/ground.json wear.on, or --wear=on.

const Data := preload("res://scripts/data.gd")
static var ON: bool = OS.get_cmdline_user_args().has("--wear=on") or (bool(Data.value("ground", "wear.on", false)) and not OS.get_cmdline_user_args().has("--wear=off"))

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
var WALK: float = Data.num("ground", "wear.walkMin", 0.01)  # moved at least this far (units) since the last stamp to wear the ground


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
				if _was.has(id) and Vector2(at.x - (_was[id] as Vector3).x, at.z - (_was[id] as Vector3).z).length() >= WALK:
					_stamp(at)
		_was = seen
	if _up_t >= UPLOAD:
		_up_t = 0.0
		_upload()


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
	var t := {"img": img, "tex": tex, "decal": decal, "dirty": false}
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
		for i in range(1, data.size(), 2):
			if data[i] > 0:
				data[i] = maxi(0, data[i] - less)
		img.set_data(PX, PX, false, Image.FORMAT_LA8, data)
		t["dirty"] = true
	for key in _tiles:
		var t: Dictionary = _tiles[key]
		if t["dirty"]:
			(t["tex"] as ImageTexture).update(t["img"])
			t["dirty"] = false
