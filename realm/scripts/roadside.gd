extends Node3D
## Life along the roads between the towns (art target 06-inn): coaching inns at crossroads and a day's
## ride apart with their stable yards, signs, smoke, horses and carts; hamlets of a few cottages with
## their fields; waystones, wayside shrines, woodcutters' camps; bridges and fords; a water mill; toll
## gates on the roads out of a castle town; a gallows at a crossroads near the crown's seat. Where each
## stands is roadside_plan.gd's to decide; this raises them from the catalogue (realm/data/assets.json,
## through realistic.gd), peoples them only near the camera, and sends travellers and herds to and
## from them. Reads roads.gd's drawn paths and the towns as they stand; edits neither.
## Every number is realm/data/roadside.json's (docs/TUNING.md). On with `on: true` there.

const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")
const Plan := preload("res://scripts/roadside_plan.gd")
const Horse := preload("res://scripts/horse.gd")
const Scenes := preload("res://scripts/scenes.gd")
const Countryside := preload("res://scripts/countryside.gd")
const Mind := preload("res://scripts/npc_mind.gd")  # the people's one decider (LimboAI)
const TownLife := preload("res://scripts/town_life.gd")  # minds_on: the --limbo switch
const Rivers := preload("res://scripts/rivers.gd")  # the realm's rivers, read once by their owner

var main: Node
var _d: Dictionary
var _sig := ""
var _settle := 0.0
var _busy := false
var _root: Node3D  # every site, rebuilt when the roads change
var _sites: Array = []  # the plan's sites, each with its "node" once raised
var _rivers: Array = []
var _rng := RandomNumberGenerator.new()


## On with realm/data/roadside.json's `on`.
static func on() -> bool:
	return bool(Data.value("roadside", "on", false))


func _init(owner: Node) -> void:
	main = owner
	name = "Roadside"
	_d = Data.read("roadside")


func _ready() -> void:
	_rng.randomize()
	_read_rivers()


func _process(delta: float) -> void:
	_watch(delta)
	if _sites.is_empty():
		return
	_life(delta)
	_traffic(delta)


# --- when to lay it out ----------------------------------------------------------------------------

## The roads it follows, as their owners in roads.gd ("kings", "track:lords", "roads").
func _segs() -> Array:
	var out: Array = []
	var paths: Dictionary = main.roads.get("_paths") if main.roads else {}
	for owner in _d.get("roads", ["kings", "track:lords", "roads"]):
		for s in paths.get(owner, []):
			out.append([s[0], s[1]])
	return out


## Waits for the roads to stop changing and the towns to stand, then lays the roadside out once.
func _watch(delta: float) -> void:
	if _busy or main.roads == null or main.towns == null or main.terrain == null or not main.terrain.built:
		return
	var paths: Dictionary = main.roads.get("_paths")
	var n := 0
	for owner in _d.get("roads", []):
		n = n * 31 + paths.get(owner, []).size()
	var sig := "%d:%d" % [n, main.towns.towns.size()]
	if sig != _sig:
		_sig = sig
		_settle = float(_d.get("settle_sec", 3.0))
		return
	if _settle <= 0.0:
		return
	_settle -= delta
	if _settle <= 0.0 and n > 0:
		_lay()


func _towns() -> Array:
	var out: Array = []
	for id in main.towns.towns:
		var node: Node3D = main.towns.towns[id]["node"]
		if not is_instance_valid(node):
			continue
		out.append({"id": id, "at": Vector2(node.position.x, node.position.z),
			"reach": maxf(float(node.get_meta("reach", 6.0)), float(node.get_meta("edge_r", 0.0))),
			"castle": node.has_meta("castle_poly"), "seat": bool(node.get_meta("crown_seat", false))})
	return out


## What already stands by the roads and must not be built over: the countryside's farmsteads and
## the inns roads.gd raises along the King's road.
func _keep_off() -> Array:
	var out: Array = []
	var cs = main.get("countryside")
	if cs:
		for s in cs.get("_sites"):
			out.append([Vector2((s["at"] as Vector3).x, (s["at"] as Vector3).z), float(_d.get("farm_room", 1.6))])
	var kings = main.roads.get("_kings")
	if kings and is_instance_valid(kings):
		for c in kings.get_children():
			if c is Node3D and not (c is Decal or c is MultiMeshInstance3D or c is Label3D):
				out.append([Vector2(c.position.x, c.position.z), float(_d.get("inn_room", 1.8))])
	return out


func _read_rivers() -> void:
	for r in Rivers.lines():
		var pts := PackedVector2Array()
		var w := PackedFloat32Array()
		var lvl := PackedFloat32Array()
		for p in r["points"]:
			pts.append(Vector2(float(p[0]), float(p[2])))
			w.append(float(p[3]))
			lvl.append(float(p[1]))
		_rivers.append({"pts": pts, "w": w, "level": lvl})


func _lay() -> void:
	_busy = true
	while main.towns.building():
		await get_tree().process_frame
	var terrain: Node3D = main.terrain
	var roads: Node3D = main.roads
	var input := {
		"segs": _segs(), "towns": _towns(), "rivers": _rivers, "keep_off": _keep_off(),
		"is_land": func(v: Vector2) -> bool: return terrain.is_land(v.x, v.y),
		"tile": func(v: Vector2) -> String: return String(terrain.tile_at(int(v.x / terrain.TILE), int(v.y / terrain.TILE))),
		"on_road": func(v: Vector2, m: float) -> bool: return roads.on_path(Vector3(v.x, 0, v.y), m),
	}
	var sites := Plan.plan(input, _d)
	if _root:
		_root.queue_free()
	_alive = []
	_bridges = []
	roads.clear_tracks("roadside")
	_root = Node3D.new()
	_root.name = "Sites"
	add_child(_root)
	_sites = []
	var budget := float(_d.get("frame_ms", 4.0))
	var t0 := Time.get_ticks_msec()
	for s in sites:
		_raise(s)
		_sites.append(s)
		if Time.get_ticks_msec() - t0 > budget:
			await get_tree().process_frame
			t0 = Time.get_ticks_msec()
	_busy = false


## Where the sites of a kind stand (inn, hamlet, bridge, mill...; "" for every kind): world points on
## the ground, read only (a film frames one: autoplay.gd's `site` step).
func sites(kind := "") -> Array:
	var out: Array = []
	for s in _sites:
		if kind == "" or String(s["kind"]) == kind:
			var at: Vector2 = s["at"]
			out.append(Vector3(at.x, main.terrain.height_at(at.x, at.y), at.y))
	return out


# --- raising a site --------------------------------------------------------------------------------

func _kind(s: Dictionary) -> Dictionary:
	return _d.get("kinds", {}).get(s["kind"], {})


## Where a point given in a site's own frame (along the road, out from it) lies in the world.
func _world(s: Dictionary, a: float, o: float, from_road := true) -> Vector3:
	var base: Vector2 = s["road"] if from_road else s["at"]
	var v: Vector2 = base + (s["dir"] as Vector2) * a + (s["side"] as Vector2) * o
	return Vector3(v.x, main.terrain.height_at(v.x, v.y), v.y)


## The turn that faces a model's front (+z) toward the road, plus `deg`.
func _yaw(s: Dictionary, deg: float) -> float:
	var side: Vector2 = s["side"]
	return atan2(-side.x, -side.y) + deg_to_rad(deg)


func _raise(s: Dictionary) -> void:
	var k := _kind(s)
	var node := Node3D.new()
	node.name = String(s["kind"]).capitalize()
	_root.add_child(node)
	s["node"] = node
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"])
	var clear := float(k.get("clear", 0.0))
	if clear > 0.0 and main.terrain.forest:
		var c: Vector2 = s["at"]
		main.terrain.forest.clear(Vector3(c.x, 0, c.y), clear)
	match String(s["kind"]):
		"bridge":
			_bridge(node, s, k)
		"ford":
			_ford(node, s, k, rng)
		"hamlet":
			_hamlet(node, s, k, rng)
		_:
			for p in k.get("pieces", []):
				_piece(node, s, p, rng)
	for sm in k.get("smoke", []):
		_smoke(node, _world(s, float(sm[0]), float(sm[1])) + Vector3(0, float(sm[2]), 0))
	for f in k.get("fire", []):
		preload("res://scripts/fire.gd").hearth(node, _world(s, float(f[0]), float(f[1])))
	if k.has("sign") and bool(k["sign"].get("on", true)):
		_sign(node, s, k["sign"], rng)


## One catalogue piece: {c: component, at: [along, out], yaw: degrees, chance, squash: [x, y, z],
## road: true (it may stand on the road: a toll's bar, a bridge's rail), lift: units}.
func _piece(node: Node3D, s: Dictionary, p: Dictionary, rng: RandomNumberGenerator, at := Vector3.INF, yaw := INF) -> Node3D:
	if rng.randf() > float(p.get("chance", 1.0)):
		return null
	var vs := Real.variants(String(p.get("c", "")))
	if vs.is_empty():
		return null
	var at_v: Array = p.get("at", [0, 0])
	var j := float(p.get("jitter", 0.0))
	var w: Vector3 = at if at != Vector3.INF else _world(s, float(at_v[0]) + rng.randf_range(-j, j), float(at_v[1]) + rng.randf_range(-j, j), not p.get("from_site", false))
	if not main.terrain.is_land(w.x, w.z):
		return null
	if not p.get("road", false) and main.roads.on_path(w, float(_d.get("road_margin", 0.04))):
		return null
	var model := String(vs[rng.randi() % vs.size()])
	var n: Node3D = Real.make(model)
	if n == null:
		return null
	n.position = Vector3(w.x, (main.terrain.height_at(w.x, w.z) if at == Vector3.INF else w.y) - float(_d.get("sink", 0.02)) + float(p.get("lift", 0.0)), w.z)
	n.rotation.y = (yaw if yaw != INF else _yaw(s, float(p.get("yaw", 0.0)))) + deg_to_rad(rng.randf_range(-1.0, 1.0) * float(p.get("turn", 0.0)))
	if p.has("squash"):
		var q: Array = p["squash"]
		n.scale = Vector3(float(q[0]), float(q[1]), float(q[2]))
	if p.has("tilt"):
		n.rotation.x = deg_to_rad(float(p["tilt"]))
	var foot := Real.footprint(model)
	_fade(n, maxf(maxf(foot.x, foot.y), Real.height(model)))
	node.add_child(n)
	return n


## Out in the country a sack or a stool is a speck past a short walk, a house past a valley.
func _fade(n: Node3D, size: float) -> void:
	var f: Dictionary = _d.get("fade", {})
	var end := float(f.get("big", 70.0)) if size > float(f.get("big_from", 0.6)) else float(f.get("small", 22.0))
	for g in n.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = end
		(g as GeometryInstance3D).visibility_range_end_margin = end * 0.15


## A thread of chimney smoke: the towns' own smoke (towns.gd smoke_material), thin and drifting.
func _smoke(node: Node3D, at: Vector3) -> void:
	var k: Dictionary = _d.get("smoke", {})
	var p := CPUParticles3D.new()
	p.amount = int(k.get("amount", 10))
	p.lifetime = float(k.get("life", 4.0))
	p.direction = Vector3(0.3, 1, 0)
	p.spread = 10
	p.initial_velocity_min = float(k.get("rise", [0.1, 0.2])[0])
	p.initial_velocity_max = float(k.get("rise", [0.1, 0.2])[1])
	p.gravity = Vector3(0.05, 0.01, 0)
	p.scale_amount_min = float(k.get("size", [0.08, 0.16])[0])
	p.scale_amount_max = float(k.get("size", [0.08, 0.16])[1])
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(1, 1.2))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.6, 0.59, 0.57, float(k.get("alpha", 0.22))))
	grad.set_color(1, Color(0.55, 0.55, 0.55, 0.0))
	p.color_ramp = grad
	p.angle_min = -180.0
	p.angle_max = 180.0
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = preload("res://scripts/towns.gd").smoke_material()
	p.mesh = q
	var gpu: GPUParticles3D = preload("res://scripts/particles.gd").to_gpu(p, float(k.get("far", 45.0)))
	gpu.position = at
	node.add_child(gpu)


## The inn's name over its door, read only close by (roads.gd's inns wear the same).
func _sign(node: Node3D, s: Dictionary, k: Dictionary, rng: RandomNumberGenerator) -> void:
	var names: Array = k.get("names", [])
	if names.is_empty():
		return
	var at_v: Array = k.get("at", [0, 0.4])
	var w := _world(s, float(at_v[0]), float(at_v[1]))
	var l := Label3D.new()
	l.text = String(names[rng.randi() % names.size()])
	l.font_size = int(k.get("font", 34))
	l.pixel_size = float(k.get("pixel", 0.003))
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.modulate = Color(0.95, 0.85, 0.6)
	l.position = w + Vector3(0, float(k.get("lift", 1.1)), 0)
	l.visibility_range_begin = float(k.get("near", 1.6))
	l.visibility_range_end = float(k.get("far", 14.0))
	node.add_child(l)
	preload("res://scripts/camera_rig.gd").sign_over(l, node)  # clarity: over its roofs, hidden behind others


## A timber bridge over a narrow river: kit planks laid across at the height of the higher bank, a
## rail along each side. Travellers still follow the ground (scenes.gd); roadside.deck_at() says how
## high the deck stands, for the one-line hook that would carry them over it.
func _bridge(node: Node3D, s: Dictionary, k: Dictionary) -> void:
	var w := float(s["width"])
	var span := w * float(k.get("span", 1.6)) + 2.0 * float(k.get("apron", 0.25))
	var plank := Real.footprint(Real.one("plank"))
	var step := maxf(plank.x, 0.05)
	var n := maxi(1, ceili(span / step))
	var across := maxi(1, int(k.get("across", 2)))
	var a0 := -span * 0.5 + step * 0.5
	var h := maxf(_world(s, -span * 0.5, 0).y, _world(s, span * 0.5, 0).y) + float(k.get("lift", 0.03))
	s["deck"] = h
	_bridges.append(s)
	var yaw := atan2((s["dir"] as Vector2).x, (s["dir"] as Vector2).y)
	var rng := RandomNumberGenerator.new()
	for i in n:
		for c in across:
			var o := (c - (across - 1) * 0.5) * step
			var w3 := _world(s, a0 + i * step, o)
			_piece(node, s, {"c": "plank", "road": true}, rng, Vector3(w3.x, h, w3.z), yaw)
	var rail := Real.footprint(Real.one("rail"))
	var rstep := maxf(maxf(rail.x, rail.y), 0.05)
	var half := across * step * 0.5
	for sgn in [-1.0, 1.0]:
		var m := maxi(1, ceili(span / rstep))
		for i in m:
			var w3 := _world(s, -span * 0.5 + rstep * (i + 0.5), sgn * half)
			_piece(node, s, {"c": "rail", "road": true}, rng, Vector3(w3.x, h, w3.z), yaw + PI / 2)


## A ford over a broad river: stepping stones across beside the road's way, boulders on the banks.
func _ford(node: Node3D, s: Dictionary, k: Dictionary, rng: RandomNumberGenerator) -> void:
	var w := float(s["width"])
	var span := w * float(k.get("span", 1.4))
	var gap := float(k.get("stone_gap", 0.12))
	var o := float(k.get("stones_out", 0.32))
	var t := -span * 0.5
	while t <= span * 0.5:
		var w3 := _world(s, t, o + rng.randf_range(-0.03, 0.03))
		# a stepping stone: the nature set's small boulder laid flat
		_piece(node, s, {"c": "stepping_stone", "road": true, "turn": 180, "squash": [1.0, 0.12, 1.0]}, rng, Vector3(w3.x, maxf(w3.y, _level(s)) - 0.01, w3.z))
		t += gap
	for p in k.get("pieces", []):
		_piece(node, s, p, rng)


## The water's level where a site meets its river (rivers.json), or -INF.
func _level(s: Dictionary) -> float:
	var best := INF
	var lvl := -INF
	for r in _rivers:
		var pts: PackedVector2Array = r["pts"]
		for i in range(0, pts.size(), 2):
			var d: float = pts[i].distance_squared_to(s["road"])
			if d < best:
				best = d
				lvl = r["level"][i]
	return lvl


## A hamlet: a few cottages round a green with its well, their fields beyond, a haystack and a pen,
## and a track down to the road.
func _hamlet(node: Node3D, s: Dictionary, k: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Vector2 = s["at"]
	var centre := Vector3(c.x, main.terrain.height_at(c.x, c.y), c.y)
	var nr: Array = k.get("cottages", [3, 6])
	var count := rng.randi_range(int(nr[0]), int(nr[1]))
	var house_kind := String(k.get("house", "house_poor"))
	# However big the catalogue's cottage is (a kit cottage, or the pack's whole thatched cluster), the
	# ring grows to fit them shoulder to shoulder, and the fields move out with it.
	var foot := Real.footprint(Real.one(house_kind))
	var ring := maxf(float(k.get("ring", 0.9)), maxf(foot.x, foot.y) * count / TAU * float(k.get("ring_room", 1.15)))
	var grown := ring - float(k.get("ring", 0.9))
	var start := rng.randf() * TAU
	var homes: Array = []
	for i in count:
		var ang := start + TAU * i / count + rng.randf_range(-0.25, 0.25)
		var at := centre + Vector3(sin(ang), 0, cos(ang)) * ring * rng.randf_range(0.9, 1.15)
		# Never a cottage in the road's way: the side toward the road stays open as the green's mouth.
		if Vector2(sin(ang), cos(ang)).dot(-(s["side"] as Vector2)) > float(k.get("mouth", 0.7)):
			continue
		var house := _piece(node, s, {"c": house_kind}, rng, Vector3(at.x, main.terrain.height_at(at.x, at.z), at.z), atan2(centre.x - at.x, centre.z - at.z))
		if house:
			homes.append(at)
	if homes.is_empty():
		node.queue_free()
		s.erase("node")
		return
	s["homes"] = homes
	for i in mini(homes.size(), int(k.get("smoking", 2))):
		var h: Vector3 = homes[i]
		_smoke(node, h + Vector3(0, float(k.get("smoke_lift", 0.55)), 0))
	for p in k.get("pieces", []):
		_piece(node, s, p, rng)
	# Fields beyond the cottages, on the side away from the road (the countryside's own crops and soil).
	var fields: Array = []
	var fr: Array = k.get("fields", [2, 4])
	var far: Array = k.get("field_ring", [2.0, 2.8])
	var size_lo: Array = k.get("field_min", [1.2, 0.7])
	var size_hi: Array = k.get("field_max", [2.0, 1.1])
	var away := atan2((s["side"] as Vector2).x, (s["side"] as Vector2).y)
	var kinds: Array = k.get("field_kinds", ["field-wheat", "field-green"])  # countryside.json field_ground paints each kind
	for i in rng.randi_range(int(fr[0]), int(fr[1])):
		var ang := away + rng.randf_range(-1.3, 1.3)
		var f := centre + Vector3(sin(ang), 0, cos(ang)) * (grown + rng.randf_range(float(far[0]), float(far[1])))
		var size := Vector2(rng.randf_range(float(size_lo[0]), float(size_hi[0])), rng.randf_range(float(size_lo[1]), float(size_hi[1])))
		if not main.terrain.is_land(f.x, f.z) or main.roads.on_path(f, maxf(size.x, size.y) * 0.5):
			continue
		var kind := String(kinds[rng.randi() % kinds.size()])
		var tx: String = Countryside.field_ground(kind)
		var yaw := ang + rng.randf_range(-0.2, 0.2)
		f = Countryside.on_furrows(main.terrain, f, size)
		var crop: Decal = main.terrain.paint(node, main.terrain.tiled(tx, roundi(size.x * 1.5), roundi(size.y * 1.5)), Vector3(f.x, main.terrain.height_at(f.x, f.z), f.z), size, yaw)
		if main.terrain.land3d and main.terrain.land3d.land:
			Countryside.plough(main.terrain, f, size, yaw)
			crop.albedo_mix = 0.55
		Countryside.mark_field(crop, kind, f)
		Countryside.sow(node, main.terrain, Vector3.ZERO, Countryside.crop_for(kind, rng), f, size, yaw, rng)
		fields.append(f)
	s["fields"] = fields
	if bool(k.get("track", true)):
		var r: Vector2 = s["road"]
		main.roads.track(centre, Vector3(r.x, main.terrain.height_at(r.x, r.y), r.y), main.roads.WIDTH * float(k.get("track_width", 0.45)), "roadside")


## How high a bridge's deck stands at a world spot, or -INF where there is none: for the walkers'
## ground (scenes.gd ground()) to take, so travellers cross over the deck and not through the river.
var _bridges: Array = []  # the bridge sites raised, for deck_at (asked at every step of a traveller's road)
func deck_at(x: float, z: float) -> float:
	for s in _bridges:
		var rel := Vector2(x, z) - (s["road"] as Vector2)
		var span := float(s["width"]) * float(_kind(s).get("span", 1.6)) * 0.5 + float(_kind(s).get("apron", 0.25))
		if absf(rel.dot(s["dir"])) <= span and absf(rel.dot(s["side"])) <= float(_kind(s).get("half_width", 0.3)):
			return float(s["deck"])
	return -INF


# --- the people, horses and beasts, near the camera only -------------------------------------------

var _life_wait := 0.0
var _alive: Array = []  # sites peopled now


func _life(delta: float) -> void:
	_life_wait -= delta
	if _life_wait > 0.0:
		return
	var L: Dictionary = _d.get("life", {})
	_life_wait = float(L.get("every_sec", 0.5))
	var cam := get_viewport().get_camera_3d()
	if cam == null or main.get("scenes") == null:
		return
	var eye := Vector2(cam.global_position.x, cam.global_position.z)
	var reach := float(L.get("reach", 16.0))
	var keep := float(L.get("keep", 22.0))
	for s in _alive.duplicate():
		if not is_instance_valid(s.get("node")) or eye.distance_to(s["at"]) > keep:
			_unpeople(s)
	var near: Array = []
	for s in _sites:
		if s.has("node") and not s.has("life") and not _kind(s).get("life", []).is_empty() and eye.distance_to(s["at"]) < reach:
			near.append(s)
	near.sort_custom(func(a, b): return eye.distance_to(a["at"]) < eye.distance_to(b["at"]))
	for s in near:
		if _alive.size() >= int(L.get("most_sites", 6)):
			break
		_people(s)
	# Each one moves on to another thing to do now and then, never the same twice running.
	for s in _alive:
		for m in s["life"]:
			m["left"] -= _life_wait
			if m["left"] <= 0.0 and m.has("clips"):
				_next_clip(m)


func _people(s: Dictionary) -> void:
	var scenes: Node = main.scenes
	var holder := Node3D.new()
	holder.name = "Life"
	s["node"].add_child(holder)
	var life: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(s["seed"]) + Time.get_ticks_msec()
	var spots: Array = _kind(s).get("life", [])
	for spec in spots:
		if rng.randf() > float(spec.get("chance", 1.0)):
			continue
		var at := _spot(s, spec, rng)
		if at == Vector3.INF:
			continue
		var face: Vector3 = at + Vector3(-(s["side"] as Vector2).x, 0, -(s["side"] as Vector2).y)
		if spec.has("face"):
			var fv: Array = spec["face"]
			face = _world(s, float(fv[0]), float(fv[1]))
		var who := String(spec.get("who", "folk"))
		var n: Node3D
		if who == "horse":
			n = Horse.new()
			n.ready.connect(n.live_idle.bind(rng), CONNECT_ONE_SHOT)  # head down to graze at the rail now and then (animals.gd), once it stands
		elif who == "animal":
			n = _animal(String(spec.get("animal", "sheep")), rng)
		else:
			var role := String(spec.get("role", "peasant"))
			var cloth: Array = preload("res://scripts/people.gd").cloth_of(role)
			n = scenes.people.make(rng, role, cloth[rng.randi() % cloth.size()] if not cloth.is_empty() else Color.WHITE)
			if spec.has("kit"):
				Scenes.arm(n, String(spec["kit"]))
			if spec.has("hold"):
				_hold(n, String(spec["hold"]))
		if n == null:
			continue
		holder.add_child(n)
		n.global_position = at
		n.rotation.y = atan2(face.x - at.x, face.z - at.z)
		var m := {"node": n, "left": rng.randf_range(0.5, 3.0)}
		# One decider for what people do: a spec naming a post (an inn's host, its yard's drinkers, a
		# woodcutter, a pilgrim) gets the townsfolk's mind on LimboAI (npc_mind.gd); the site is a work
		# site like a town's. Without one, or with minds off (--limbo=none), the old clip timer.
		if (who == "folk" or who == "soldier") and spec.has("post") and TownLife.minds_on(-1) \
				and Mind.give(n, String(spec["post"]), func(q: Vector3) -> float: return main.terrain.height_at(q.x, q.z), rng.randi()):
			pass
		elif who == "folk" or who == "soldier":
			m["clips"] = spec.get("clips", ["Idle"])
			m["last"] = ""
			_next_clip(m)
		life.append(m)
	s["life"] = life
	s["holder"] = holder
	_alive.append(s)


## Where one of a site's people stands: their spot in the site's frame, set down where a person may
## stand (scenes.stand: on the ground and in no building); a hamlet's folk by its homes or fields.
func _spot(s: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> Vector3:
	var p: Vector3
	var near := String(spec.get("near", ""))
	if near != "" and s.has(near) and not (s[near] as Array).is_empty():
		var base: Vector3 = s[near][rng.randi() % (s[near] as Array).size()]
		var r := float(spec.get("spread", 0.4))
		p = base + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r))
	else:
		var a: Array = spec.get("at", [0, 0.5])
		var j := float(spec.get("jitter", 0.06))
		p = _world(s, float(a[0]) + rng.randf_range(-j, j), float(a[1]) + rng.randf_range(-j, j))
	if not main.terrain.is_land(p.x, p.z):
		return Vector3.INF
	if String(spec.get("who", "folk")) in ["folk", "soldier"]:
		return main.scenes.stand(p)
	return Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z)


func _next_clip(m: Dictionary) -> void:
	var pool: Array = (m["clips"] as Array).filter(func(c): return c != m["last"])
	if pool.is_empty():
		pool = m["clips"]
	var clip := String(pool[randi() % pool.size()])
	m["last"] = clip
	var sw: Array = _d.get("life", {}).get("swap_sec", [5.0, 11.0])
	m["left"] = randf_range(float(sw[0]), float(sw[1]))
	if is_instance_valid(m["node"]):
		preload("res://scripts/people.gd").play(m["node"], clip, randf_range(0.9, 1.1))


func _unpeople(s: Dictionary) -> void:
	if s.has("holder") and is_instance_valid(s["holder"]):
		s["holder"].queue_free()
	s.erase("holder")
	s.erase("life")
	_alive.erase(s)


## A tool in a worker's right hand (an axe at the woodcutters'), held as a soldier holds his sword.
func _hold(person: Node3D, component: String) -> void:
	var skel: Skeleton3D = person.get_node_or_null("Armature/GeneralSkeleton")
	var path := Real.path_of(component)
	if skel == null or path == "" or not ResourceLoader.exists(path):
		return
	Scenes._hold(skel, "RightHand", (load(path) as PackedScene).instantiate(), Scenes.SWORD_GRIP)


## A beast of the farm, standing about living its idle life or walking (animals.gd make, the one
## place a beast is made).
func _animal(kind: String, rng: RandomNumberGenerator, walking := false) -> Node3D:
	return preload("res://scripts/animals.gd").make(kind, rng, walking)


## [scale, lift] for an animated beast: its skinned meshes measured as they stand at rest, each
## vertex carried by its bones (skin bind poses times the skeleton's rest), not by their bind-pose
## boxes, which the Quaternius rigs' armature turn and hundredfold scale throw out. Scale fits its
## longest side to `metres`; lift stands its lowest point on the ground. Needs no scene tree.
static func beast_fit(kind: String, metres: float, model_path := "") -> Array:
	var path := model_path if model_path != "" else Real.path_of(kind)
	if path == "" or not ResourceLoader.exists(path):
		return [0.0, 0.0]
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var lo := Vector3.INF
	var hi := -Vector3.INF
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _rel(model, m)
		var skel := m.get_node_or_null(m.skeleton) as Skeleton3D if m.skin else null
		var bones: Array[Transform3D] = []
		if skel:
			var sx := _rel(model, skel)
			for b in m.skin.get_bind_count():
				var bi := m.skin.get_bind_bone(b)
				if bi < 0:
					bi = skel.find_bone(m.skin.get_bind_name(b))
				bones.append(sx * (skel.get_bone_global_rest(bi) if bi >= 0 else Transform3D.IDENTITY) * m.skin.get_bind_pose(b))
		for sf in m.mesh.get_surface_count():
			var a := m.mesh.surface_get_arrays(sf)
			var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var bi: Variant = a[Mesh.ARRAY_BONES]
			var wt: Variant = a[Mesh.ARRAY_WEIGHTS]
			var per := 0 if bones.is_empty() or bi == null or wt == null else (bi as PackedInt32Array).size() / maxi(verts.size(), 1)
			for v in verts.size():
				var p: Vector3
				if per > 0:
					p = Vector3.ZERO
					for k in per:
						var w: float = (wt as PackedFloat32Array)[v * per + k]
						var bone: int = (bi as PackedInt32Array)[v * per + k]
						if w > 0.0 and bone < bones.size():
							p += (bones[bone] * verts[v]) * w
				else:
					p = xf * verts[v]
				lo = lo.min(p)
				hi = hi.max(p)
	model.free()
	var size := hi - lo
	var longest := maxf(size.x, size.z)
	if lo == Vector3.INF or longest <= 0.0:
		return [0.0, 0.0]
	var k := metres * Real.S / longest
	return [k, -lo.y * k]


## Where a node stands within `top` (its transforms multiplied up), with no scene tree needed.
static func _rel(top: Node, n: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


# --- travellers to and from the roadside -----------------------------------------------------------

var _travel_wait := 6.0
var _out := 0


## Now and then someone sets out between a town and an inn, hamlet, mill or camp near the camera.
## Who goes is traffic.gd's rule (_who: soldiers only in war, refugees from grief, thin roads in
## winter and hunger, wagons between thriving places); scenes.gd builds and walks them.
func _traffic(delta: float) -> void:
	_travel_wait -= delta
	if _travel_wait > 0.0:
		return
	var T: Dictionary = _d.get("traffic", {})
	var gap: Array = T.get("gap", [6.0, 12.0])
	_travel_wait = _rng.randf_range(float(gap[0]), float(gap[1]))
	if _out >= int(T.get("most", 4)):
		return
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	var traffic: Node = main.get_node_or_null("Traffic")
	var cam := get_viewport().get_camera_3d()
	if aw == null or traffic == null or cam == null or main.scenes == null:
		return
	var eye := Vector2(cam.global_position.x, cam.global_position.z)
	var stops: Array = _sites.filter(func(s): return s.has("node") and bool(_kind(s).get("stop", false)) and eye.distance_to(s["at"]) < float(T.get("reach", 20.0)))
	if stops.is_empty():
		return
	var s: Dictionary = stops[_rng.randi() % stops.size()]
	# The nearest town by road to it, as the mirror knows it.
	var best: Blackboard = null
	var best_at := Vector3.ZERO
	var best_d := float(T.get("town_reach", 24.0))
	for id in aw.realm.get_var(&"towns", [], false):
		var bb: Blackboard = aw.town(int(id))
		var tile: Vector2i = bb.get_var(&"tile", Vector2i(-1, -1))
		if tile.x < 0:
			continue
		var at: Vector3 = main.terrain.world_pos(float(tile.x), float(tile.y))
		var dd := Vector2(at.x, at.z).distance_to(s["road"])
		if dd < best_d:
			best_d = dd
			best = bb
			best_at = at
	if best == null:
		return
	var kind: String = traffic._who(best, best, String(aw.realm.get_var(&"season", "", false)))
	if kind == "":
		return
	var r: Vector2 = s["road"]
	var stop := Vector3(r.x, main.terrain.height_at(r.x, r.y), r.y)
	var home := _rng.randf() < 0.5
	if s["kind"] == "hamlet" and kind in ["walker", "cart"] and _rng.randf() < float(T.get("herd_chance", 0.3)):
		# A herd stops at the town's edge (batch 8b #15: boxy cows walked through the market): driven to the
		# road's end short of the town by herd.stop_short (world units), never into its square.
		var edge := best_at + (stop - best_at).normalized() * float((T.get("herd", {}) as Dictionary).get("stop_short", 3.2))
		if _herd(stop if home else edge, edge if home else stop):
			return
	if traffic.go(stop if home else best_at, best_at if home else stop, kind, func(): _out -= 1):
		_out += 1


## A herd driven along the road between a hamlet and its market town: a herder in front, his beasts
## strung out behind, all on the road's own curve (Godot's PathFollow3D, as travellers ride it).
func _herd(from: Vector3, to: Vector3) -> bool:
	var H: Dictionary = _d.get("traffic", {}).get("herd", {})
	var way: PackedVector3Array = main.roads.route(from, to)
	if way.size() <= 2:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_msec()
	var kinds: Array = H.get("beasts", ["cow"])
	var beast := String(kinds[rng.randi() % kinds.size()])
	var n := rng.randi_range(int(H.get("count", [3, 6])[0]), int(H.get("count", [3, 6])[1]))
	var gap := float(H.get("gap", 0.1))
	var lead := gap * (n + 1)
	var herder: Node3D = main.scenes.people.make(rng, "peasant", Color(0.5, 0.44, 0.36))
	preload("res://scripts/people.gd").play(herder, "Walk", rng.randf_range(0.85, 0.95))
	var members: Array = [[herder, lead]]
	for i in n:
		var a := _animal(beast, rng, true)
		if a == null:
			break
		members.append([a, gap * (n - i) + rng.randf_range(-0.03, 0.03), rng.randf_range(-0.05, 0.05)])
	# The herd in file behind its herder, along the road the navigation gave (Mover.road).
	if Mover.road(self, way, members, float(H.get("pace", 0.16)), {"name": "Herd", "min": 15.0, "max": 120.0}, func(): _out -= 1) == null:
		return false
	_out += 1
	return true
