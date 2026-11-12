extends Node3D
## The realm's gold mines: a mine on every gold seam (/world gold, through the mirror), worked by
## miners with picks while the camera is near; where a seam ran out, the old workings stand dark and
## empty (/world spentSeams). Freeciv decides where the gold lies and how long it lasts (bridge
## mines.js, bridge/data/realmrules/script.lua realm_mines); this only shows it, the way Settlers and Anno show a mine
## at its deposit. Reads the mirror (awareness.gd), edits nothing else.
## Knobs: realm/data/gold_mines.json (docs/TUNING.md). --gold-mines=off shows none.

const Data := preload("res://scripts/data.gd")
const People := preload("res://scripts/people.gd")
const Real := preload("res://scripts/realistic.gd")
const Scenes := preload("res://scripts/scenes.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const ROCKS := ["res://assets/nature/Rock_Medium_1.gltf", "res://assets/nature/Rock_Medium_2.gltf", "res://assets/nature/Rock_Medium_3.gltf"]
const PEBBLE := "res://assets/nature/Pebble_Round_1.gltf"
const MODEL := "res://assets/meshy/mine/mine.glb"

var main: Node
var _d: Dictionary
var _sig := ""
var _wait := 0.0
var _sites := {}  # Vector2i tile -> {node, spent, at: Vector3, life: Array, holder: Node3D}
var _rng := RandomNumberGenerator.new()


## The switch: --gold-mines=off for one run, else realm/data/gold_mines.json's `on`.
static func on() -> bool:
	if OS.get_cmdline_user_args().has("--gold-mines=off"):
		return false
	return bool(Data.value("gold_mines", "on", true)) and ResourceLoader.exists(MODEL)


func _init(owner: Node) -> void:
	main = owner
	name = "GoldMines"
	_d = Data.read("gold_mines")


func _ready() -> void:
	_rng.randomize()


func _process(delta: float) -> void:
	_wait -= delta
	if _wait <= 0.0:
		_wait = 1.0
		_follow()
		_people()
	for s in _sites.values():
		for m in s.get("life", []):
			m["left"] = float(m["left"]) - delta
			if float(m["left"]) <= 0.0:
				_next_clip(m)


## Brings the mines in line with the mirror: a mine raised on a new seam, a spent seam's mine
## darkened and emptied, a mine gone when its tile holds neither.
func _follow() -> void:
	var aw: Node = main.awareness
	if aw == null or main.terrain == null:
		return
	var gold: Array = aw.realm.get_var(&"gold", [], false)
	var spent: Array = aw.realm.get_var(&"spent_seams", [], false)
	var sig := str(gold) + str(spent)
	if sig == _sig:
		return
	_sig = sig
	var want := {}
	var owners := {}
	for g in gold:
		if g is Array and (g as Array).size() >= 2:
			want[Vector2i(int(g[0]), int(g[1]))] = false
			owners[Vector2i(int(g[0]), int(g[1]))] = int(g[2]) if (g as Array).size() > 2 else -1
	for s in spent:
		if s is Array and (s as Array).size() >= 2:
			var t := Vector2i(int(s[0]), int(s[1]))
			if not want.has(t):
				want[t] = true
	for t in _sites.keys():
		if not want.has(t):
			_drop(t)
	for t in want:
		if not _sites.has(t):
			_raise(t, bool(want[t]), int(owners.get(t, -1)))
		elif bool(_sites[t]["spent"]) != bool(want[t]):
			_drop(t)
			_raise(t, bool(want[t]), int(owners.get(t, -1)))


func _raise(t: Vector2i, spent: bool, owner := -1) -> void:
	var off: Array = _d.get("off", [0.0, 0.0])
	var at: Vector3 = main.terrain.world_pos(float(t.x) + float(off[0]), float(t.y) + float(off[1]))
	if not main.terrain.is_land(at.x, at.z):
		return
	var n: Node3D = (load(MODEL) as PackedScene).instantiate()
	n.scale = Vector3.ONE * Real.S * float(_d.get("scale", 1.0))
	n.rotation.y = float(hash(t) % 628) / 100.0
	add_child(n)
	n.global_position = at
	if spent:
		var shade := StandardMaterial3D.new()
		shade.albedo_color = Color(0, 0, 0, float(_d.get("spent_shade", 0.45)))
		shade.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shade.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_overlay = shade
	var dress := Node3D.new()
	dress.name = "Dressing"
	add_child(dress)
	_rocks(dress, at, hash(t))
	var g: Dictionary = _d.get("gold", {})
	var goff: Array = g.get("at", [0.3, 0.95])
	var mouth := at + Vector3(float(goff[0]), 0, float(goff[1])).rotated(Vector3.UP, n.rotation.y)
	if not spent:
		_banner(dress, at, owner)
		_gold(dress, at, n.rotation.y)
	_sites[t] = {"node": n, "dress": dress, "spent": spent, "at": at, "mouth": mouth}


## A stony outcrop round the mine, so it sits in broken ground and not on a lawn.
func _rocks(parent: Node3D, at: Vector3, seed: int) -> void:
	var r: Dictionary = _d.get("rocks", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var ring: Array = r.get("ring", [0.45, 0.95])
	var size: Array = r.get("size", [0.35, 0.9])
	for i in int(r.get("count", 7)):
		var path: String = ROCKS[rng.randi() % ROCKS.size()]
		if not ResourceLoader.exists(path):
			continue
		var rock: Node3D = (load(path) as PackedScene).instantiate()
		var a := rng.randf() * TAU
		var d := rng.randf_range(float(ring[0]), float(ring[1]))
		var p := at + Vector3(cos(a) * d, 0, sin(a) * d)
		parent.add_child(rock)
		rock.global_position = Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z)
		rock.rotation.y = rng.randf() * TAU
		rock.scale = Vector3.ONE * rng.randf_range(float(size[0]), float(size[1])) * Real.S


## The owning house's standard planted by the mine: whose gold this is, at a glance.
func _banner(parent: Node3D, at: Vector3, owner: int) -> void:
	var house: Dictionary = {}
	for p in main.awareness.realm.get_var(&"houses", [], false):
		if p is Dictionary and int(p.get("id", -2)) == owner:
			house = p.get("house", {}) if p.get("house") is Dictionary else {}
	if house.is_empty():
		return
	var b: Dictionary = _d.get("banner", {})
	var off: Array = b.get("at", [0.55, 0.35])
	var std: Node3D = Heraldry.standard(house, Heraldry.colour(house, Color.GOLD, "#d4a62a"), float(b.get("height", 0.55)))
	parent.add_child(std)
	var p := at + Vector3(float(off[0]), 0, float(off[1]))
	std.global_position = Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z)


## A heap of gold ore by the cart, catching the light: what comes out of this hill.
func _gold(parent: Node3D, at: Vector3, yaw: float) -> void:
	if not ResourceLoader.exists(PEBBLE):
		return
	var g: Dictionary = _d.get("gold", {})
	var off: Array = g.get("at", [0.25, 0.42])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.75, 0.2)
	mat.metallic = 0.9
	mat.roughness = 0.3
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = float(g.get("glow", 0.6))
	var base := at + Vector3(float(off[0]), 0, float(off[1])).rotated(Vector3.UP, yaw)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	for i in int(g.get("pieces", 6)):
		var piece: Node3D = (load(PEBBLE) as PackedScene).instantiate()
		parent.add_child(piece)
		var p := base + Vector3(rng.randf_range(-0.08, 0.08), 0, rng.randf_range(-0.08, 0.08))
		piece.global_position = Vector3(p.x, main.terrain.height_at(p.x, p.z) + 0.01 * i, p.z)
		piece.scale = Vector3.ONE * float(g.get("size", 0.06)) * rng.randf_range(0.7, 1.3)
		for mi in piece.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).material_override = mat


func _drop(t: Vector2i) -> void:
	var s: Dictionary = _sites[t]
	_unpeople(s)
	for k in ["node", "dress"]:
		if s.has(k) and is_instance_valid(s[k]):
			s[k].queue_free()
	_sites.erase(t)


## Miners only where the eye is: at a live seam within `near` of the camera.
func _people() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := float(_d.get("near", 40.0))
	for s in _sites.values():
		var close: bool = not bool(s["spent"]) and cam.global_position.distance_to(s["at"]) < near
		if close and not s.has("holder"):
			_people_in(s)
		elif not close and s.has("holder"):
			_unpeople(s)


func _people_in(s: Dictionary) -> void:
	var scenes: Node = main.scenes
	if scenes == null:
		return
	var holder := Node3D.new()
	holder.name = "Miners"
	add_child(holder)
	var life: Array = []
	var ring: Array = _d.get("ring", [0.2, 0.45])
	var cloth: Array = People.cloth_of("peasant")
	var jobs: Array = _d.get("jobs", [])
	var mouth: Vector3 = s["mouth"]
	for i in int(_d.get("miners", 4)):
		var job: Dictionary = jobs[i % jobs.size()] if not jobs.is_empty() else {}
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(float(ring[0]), float(ring[1]))
		var p: Vector3 = scenes.stand(mouth + Vector3(cos(a), 0, sin(a)) * r)
		var n: Node3D = scenes.people.make(_rng, "peasant", cloth[_rng.randi() % cloth.size()] if not cloth.is_empty() else Color.WHITE)
		if n == null:
			continue
		if String(job.get("hold", "")) != "":
			_hold(n, String(job["hold"]))
		holder.add_child(n)
		n.global_position = p
		var face: Vector3 = s["at"] if String(job.get("face", "rock")) == "rock" else mouth
		n.rotation.y = atan2(face.x - p.x, face.z - p.z)
		var m := {"node": n, "left": _rng.randf_range(0.3, 2.0), "last": "", "clips": job.get("clips", _d.get("clips", ["Idle"]))}
		life.append(m)
	s["holder"] = holder
	s["life"] = life


func _unpeople(s: Dictionary) -> void:
	if s.has("holder") and is_instance_valid(s["holder"]):
		s["holder"].queue_free()
	s.erase("holder")
	s.erase("life")


func _next_clip(m: Dictionary) -> void:
	var clips: Array = m.get("clips", _d.get("clips", ["Idle"]))
	var pool: Array = clips.filter(func(c): return c != m["last"])
	if pool.is_empty():
		pool = clips
	var clip := String(pool[_rng.randi() % pool.size()])
	m["last"] = clip
	var sw: Array = _d.get("swap_sec", [4.0, 9.0])
	m["left"] = _rng.randf_range(float(sw[0]), float(sw[1]))
	if is_instance_valid(m["node"]):
		People.play(m["node"], clip, _rng.randf_range(0.9, 1.1))


## A tool in a miner's right hand, held as a soldier holds his sword (as roadside.gd's woodcutters).
func _hold(person: Node3D, component: String) -> void:
	var skel: Skeleton3D = person.get_node_or_null("Armature/GeneralSkeleton")
	var path := Real.path_of(component)
	if skel == null or path == "" or not ResourceLoader.exists(path):
		return
	Scenes._hold(skel, "RightHand", (load(path) as PackedScene).instantiate(), Scenes.SWORD_GRIP)
