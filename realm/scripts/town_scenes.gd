extends Node3D
## Town life's director: the one reducer of docs/TOWN_LIFE.md. Every person and beast in a town's scenes is cast
## here from the rows of realm/data/town_scenes.json; nothing else places them.
## - The town's standing scenes (`standing` rows): staged whenever the town is dressed (town_life.gd update, the
##   town's Life rebuilt when its state turns), for as long as their needs hold: the riot at the keep's door and
##   the watch holding it, the hungry camped at the edge, the stall keepers, the crown's market day, the feast's
##   ring round the bonfire and its tables, the muster and the levy marching out, the gallows' onlookers, the dole,
##   the funeral round the square, and the square's own life (the crier, beggars, the watch's beat, dogs, children
##   chasing, gossip, guards at the forge and the castle, carriers, the market cart, a gardener in the yards).
##   town_life.gd lays only the props (its dress_* functions) and says where they stand (anchors).
## - The town's passing scenes (`scenes` rows): near the camera, picked by hour, needs and mood weights, capped by
##   the town's size; their people walk in, act and walk off. The director alone writes each town's running
##   scenes and claimed places to the store (the mirror's town scope: `scenes`, `claims`).
## Everyone is an agent on LimboAI: a posted person gets their post's mind (npc_mind.gd), a walker one of the
## tasks below (a beat, an errand, a chase, a dog's day, the cart's round, a funeral's file, a march out), and
## every walk goes by the Mover (mover.gd). News on the bus (awareness.gd stimulus) turns the passing scenes' people
## (flee, gather, kneel, cheer); posted minds hear it themselves (npc_mind React).
## Copies the proven designs: Unreal's smart objects and slots, GTA's scenario points, RimWorld's moods.

const Data := preload("res://scripts/data.gd")
const People := preload("res://scripts/people.gd")
const Works := preload("res://scripts/works.gd")
const SceneKinds := preload("res://scripts/scene_kinds.gd")
const Mover := preload("res://scripts/mover.gd")
const Mind := preload("res://scripts/npc_mind.gd")
const Animals := preload("res://scripts/animals.gd")
const SEEN := Vector3(-0.5736, 0, -0.8192)  # the side of a square the town camera looks across as it comes down
static var READ: float = Data.num("people", "readable", 1.0)  # drawn larger: they cover ground as their legs do

var main: Node
var _d: Dictionary
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _live := {}  # town id -> Array of running passing scenes {row, key, at, ends, cast: Array[Node3D], ending}
var _seq := 0
var _marches: Array = []  # levies marching out: {root, life, every, wait, file, spacing, most, gone, pace, rng}


func _init(owner: Node) -> void:
	main = owner
	name = "TownScenes"
	_d = Data.read("town_scenes")


func _ready() -> void:
	_rng.randomize()
	if main and main.awareness:
		main.awareness.stimulus.connect(_on_stimulus)


func _process(delta: float) -> void:
	_march(delta)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = float(_d.get("director", {}).get("tick", 2.0))
	var cam := get_viewport().get_camera_3d()
	if cam == null or main == null or main.towns == null or main.awareness == null:
		return
	var near := float(_d.get("director", {}).get("near", 30.0))
	for id in main.towns.towns.keys():
		var t: Dictionary = main.towns.towns[id]
		var root: Node3D = t.get("node")
		if root == null or not is_instance_valid(root):
			_end_town(int(id))
			continue
		if cam.global_position.distance_to(root.global_position) > near:
			_end_town(int(id))
			continue
		_direct(int(id), root, t.get("data", {}) as Dictionary)
	for id in _live.keys():
		if not main.towns.towns.has(id):
			_end_town(int(id))


# --- the standing scenes: staged when the town is dressed --------------------------------------------

## Stages a town's standing scenes into its fresh Life (town_life.gd update calls this once the props and the
## working buildings are set): every `standing` row whose needs the town's states meet, its props laid by
## town_life's dress_<name>, then each role cast at its anchor in its form. `tl` is the town_life that dresses
## the town (its placing, people and props); `states` the town's (works.gd states, and riot in disorder).
func stage(root: Node3D, life: Node3D, c: Dictionary, states: Array, tl: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("id", 0)) * 7919 + 17
	var size := int(c.get("size", 1))
	var tally := {"cast": 0, "no_room": {}, "no_place": []}  # said in the play log: an empty walk map shows as a number
	for row in _d.get("standing", []):
		if not _meets(row, root, states, size):
			continue
		var anchors: Dictionary = (life.get_meta("anchors", {}) as Dictionary).duplicate()  # where town_life's own dressing stands
		for dress in row.get("dress", []):
			var got: Variant = tl.call("dress_" + String(dress), root, life, row, rng)
			if got is Dictionary:
				anchors.merge(got, true)
		var k := {"root": root, "life": life, "tl": tl, "states": states, "size": size, "rng": rng, "row": row, "lead": null, "cast": [], "tally": tally}
		for role in row.get("roles", []):
			_stage_role(k, role, anchors)
		if row.has("march") and _meets(row["march"], root, states, size):
			_begin_march(root, life, row["march"], rng)
	print("CHECK town scenes: %s: %d cast; no room for %s; rows whose place wasn't there: %s" % [String(root.get_meta("title", root.name)), int(tally["cast"]), str(tally["no_room"]), str(tally["no_place"])])


## Whether a row's conditions hold: any of `needs`, none of `not`, the square's own life (`square`: a market
## town big enough, or the crown's seat, and no riot), the crown's seat (`crown`).
func _meets(row: Dictionary, root: Node3D, states: Array, size: int) -> bool:
	var needs: Array = row.get("needs", [])
	if not needs.is_empty() and not needs.any(func(n): return n in states):
		return false
	if (row.get("not", []) as Array).any(func(n): return n in states):
		return false
	var crown := bool(root.get_meta("crown_seat", false))
	if bool(row.get("crown", false)) and not crown:
		return false
	if bool(row.get("square", false)):
		if "riot" in states or not bool(Data.value("crowd", "on", true)):
			return false
		if size < int(_d.get("director", {}).get("square_size", 6)) and not crown:
			return false
	return true


## A number from a row: a number; [least, most] drawn; or by the town's state ({base, <state>: n, per_size, most,
## or works: a works.json count}), the first of works.json priority the town is in, else base (+ per_size a size).
func _val(v: Variant, k: Dictionary) -> float:
	if v is float or v is int:
		return float(v)
	var rng: RandomNumberGenerator = k["rng"]
	if v is Array and (v as Array).size() >= 2:
		return rng.randf_range(float(v[0]), float(v[1]))
	if v is Dictionary:
		if (v as Dictionary).has("works"):
			return float(Works.count(String(v["works"]), k["states"], int(k["size"])))
		for st in Data.value("works", "priority", []):
			if st in k["states"] and (v as Dictionary).has(st):
				return float(v[st])
		var n := float(v.get("base", 0.0)) + float(v.get("per_size", 0.0)) * float(k["size"])
		return minf(n, float(v["most"])) if (v as Dictionary).has("most") else n
	return 0.0


func _count(v: Variant, k: Dictionary) -> int:
	if v is Array and (v as Array).size() >= 2:
		return (k["rng"] as RandomNumberGenerator).randi_range(int(v[0]), int(v[1]))
	return int(floor(_val(v, k)))


## Where a role stands: a town's place or one town_life's props set down. An anchor is {at (town-local), dir
## (the way it faces), side, r, points: [{at, dir}] for each of many (stalls, seats, carts, gardens)}.
func _anchor(name: String, k: Dictionary, anchors: Dictionary) -> Dictionary:
	if anchors.has(name):
		return anchors[name]
	var root: Node3D = k["root"]
	var row: Dictionary = k["row"]
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var r := float(root.get_meta("square_r", 1.0))
	match name:
		"heart":
			return {"at": Vector3.ZERO, "dir": SEEN, "r": r}
		"market":
			return {"at": places["market"], "dir": SEEN, "r": 0.5} if places.has("market") else {}
		"well":
			return {"at": well, "dir": SEEN, "r": r}
		"seen":
			return {"at": Vector3.ZERO, "dir": SEEN, "r": r}
		"sept":
			return {"at": places["sept"], "dir": SEEN} if places.has("sept") else {}
		"crier":
			return {"at": well + SEEN * Data.num("works", "crier.from_well", 0.35), "dir": SEEN}
		"muster", "kin":
			# On the seen half, turned off the crier's line so the two crowds stand apart.
			var toward := Basis(Vector3.UP, 1.0) * SEEN
			return {"at": well + toward * float(row.get("from_well", 0.45)), "dir": toward}
		"forge":
			var wk: Dictionary = root.get_meta("works", {})
			if not wk.has("forge"):
				return {}
			var ff := Basis(Vector3.UP, float(wk["forge"].get("yaw", 0.0))) * Vector3(0, 0, 1)
			return {"at": (wk["forge"]["at"] as Vector3) + ff * float(row.get("forge_out", 0.55)), "dir": ff}
		"castle":
			return _castle(root, r, row)
		"beat":
			return {"at": Vector3.ZERO, "dir": SEEN, "r": r}
		"stops":
			return _stops(k)
		"streets":
			return {"at": Vector3.ZERO, "dir": SEEN, "r": r}
	return {}


## Along the castle's side that faces the square, a little out from it (only when the castle stands near).
func _castle(root: Node3D, r: float, row: Dictionary) -> Dictionary:
	var poly: Variant = root.get_meta("castle_poly") if root.has_meta("castle_poly") else null
	if not (poly is PackedVector2Array) or (poly as PackedVector2Array).size() < 3:
		return {}
	var cp := poly as PackedVector2Array
	var best := Vector2.INF
	var seg := [Vector2.ZERO, Vector2.ZERO]
	for i in cp.size():
		var q := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, cp[i], cp[(i + 1) % cp.size()])
		if q.length() < best.length():
			best = q
			seg = [cp[i], cp[(i + 1) % cp.size()]]
	if best.length() >= r * float(row.get("castle_within", 4.0)):
		return {}
	var along := ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized()
	var out := -best.normalized()
	var at := best + out * float(row.get("castle_out", 0.14))
	return {"at": Vector3(at.x, 0, at.y), "dir": Vector3(out.x, 0, out.y), "side": Vector3(along.x, 0, along.y)}


## The square's places a carrier goes between (the market, well, tavern, sept and the forge's yard), each on open
## ground by it, and a way up each main street (stops.streets square radii out).
func _stops(k: Dictionary) -> Dictionary:
	var root: Node3D = k["root"]
	var tl: Object = k["tl"]
	var places: Dictionary = root.get_meta("places", {})
	var r := float(root.get_meta("square_r", 1.0))
	var pts: Array = []
	for key in ["market", "well", "tavern", "sept"]:
		if places.has(key):
			pts.append(places[key])
	var wk: Dictionary = root.get_meta("works", {})
	if wk.has("forge"):
		pts.append((wk["forge"]["at"] as Vector3) + Basis(Vector3.UP, float(wk["forge"].get("yaw", 0.0))) * Vector3(0, 0, 1) * 0.45)
	var open: Array = []
	for p in pts:
		var q: Vector3 = tl.place(root, p, 0.4, false)
		if not is_nan(q.x):
			open.append({"at": q})
	var streets: Array = []
	var far := float((k["row"] as Dictionary).get("streets", 0.0))
	if far > 0.0:
		for w in root.get_meta("ways_main", []):
			for q in w as PackedVector2Array:
				if q.length() > r * far:
					streets.append(Vector3(q.x, 0, q.y))
					break
	return {"at": Vector3.ZERO, "dir": SEEN, "points": open, "streets": streets}


## The spots a role's people stand on, by its form round its anchor: [{at, face}] (face: a point, or INF to be
## settled once placed).
func _spots(role: Dictionary, a: Dictionary, n: int, k: Dictionary) -> Array:
	var rng: RandomNumberGenerator = k["rng"]
	var at: Vector3 = a.get("at", Vector3.ZERO)
	var dir: Vector3 = a.get("dir", SEEN)
	var side: Vector3 = a.get("side", Vector3(-dir.z, 0, dir.x))
	var room := 0.11 * READ if bool(role.get("room", false)) else 1.0  # a shoulder's room (town_life.gd ROOM)
	var out: Array = []
	var ang0 := atan2(dir.x, dir.z) + float(role.get("turn", 0.0))
	match String(role.get("form", "at")):
		"at":
			for i in n:
				out.append({"at": at + dir * float(role.get("out", 0.0)) + side * float(role.get("side", 0.0))})
		"box":
			var o: Array = role.get("out", [0.0, 0.0])
			var s: Array = role.get("side", [0.0, 0.0])
			for i in n:
				out.append({"at": at + dir * rng.randf_range(float(o[0]), float(o[1])) + side * rng.randf_range(float(s[0]), float(s[1]))})
		"across":
			var gap := float(role.get("gap", 0.14))
			for i in n:
				out.append({"at": at + dir * float(role.get("out", 0.0)) + side * (i - (n - 1) * 0.5) * gap})
		"flank":
			var gap2 := float(role.get("gap", 0.2))
			for i in n:
				out.append({"at": at + dir * float(role.get("out", 0.0)) + side * (gap2 if i % 2 == 0 else -gap2) * (1 + i / 2)})
		"line":
			for i in n:
				out.append({"at": at + dir * (float(role.get("start", 0.0)) + float(role.get("gap", 0.2)) * room * i)})
		"rows":
			var rows := maxi(1, int(role.get("rows", 2)))
			var cols := ceili(float(n) / rows)
			var gaps: Array = role.get("gaps", [1.25, 1.15])
			for i in n:
				out.append({"at": at + dir * (float(role.get("start", 0.2)) + (i / cols) * float(gaps[0]) * room) + side * ((i % cols) - (cols - 1) * 0.5) * float(gaps[1]) * room})
		"ring":
			var spin := rng.randf() * TAU
			var rr: Array = role.get("r", [0.4, 0.6])
			for i in n:
				var t := spin + TAU * i / maxf(n, 1) + rng.randf_range(-float(role.get("jitter_a", 0.1)), float(role.get("jitter_a", 0.1)))
				out.append({"at": at + Vector3(sin(t), 0, cos(t)) * (float(a.get("r", 0.0)) + rng.randf_range(float(rr[0]), float(rr[1])))})
		"arc":
			var span: Array = role.get("span", [-0.9, 0.9])
			var rr2: Array = role.get("r", [0.3, 0.4])
			for i in n:
				var t := ang0 + lerpf(float(span[0]), float(span[1]), (i + 0.5) / maxf(1.0, n)) + rng.randf_range(-float(role.get("jitter_a", 0.0)), float(role.get("jitter_a", 0.0)))
				out.append({"at": at + Vector3(sin(t), 0, cos(t)) * rng.randf_range(float(rr2[0]), float(rr2[1]))})
		"knots":
			# Knots of a few spread round the town's edge, never one crowd at a door.
			var knot := maxi(1, int(role.get("knot", 3)))
			var knots := maxi(1, ceili(n / float(knot)))
			var rr3: Array = role.get("r", [1.0, 1.4])
			var j := float(role.get("spread", 0.09))
			for i in n:
				var t := ang0 + TAU * float(i / knot) / knots + rng.randf_range(-0.15, 0.15)
				var hub := Vector3(sin(t), 0, cos(t)) * rng.randf_range(float(rr3[0]), float(rr3[1]))
				out.append({"at": hub + Vector3(rng.randf_range(-j, j), 0, rng.randf_range(-j, j))})
		"knots_arc":
			# Knots of neighbours, each in its own share of an arc of the square's open cobble on the seen side.
			var sq := float(a.get("r", 1.0))
			var reach: Array = role.get("reach_r", [0.5, 0.85])
			var size: Array = role.get("knot", [2, 3])
			for kn in n:
				var t := ang0 + lerpf(-float(role.get("arc", 1.4)), float(role.get("arc", 1.4)), (kn + rng.randf_range(0.2, 0.8)) / maxf(n, 1))
				var mid := Vector3(sin(t), 0, cos(t)) * sq * rng.randf_range(float(reach[0]), float(reach[1]))
				var m := rng.randi_range(int(size[0]), int(size[1]))
				for jj in m:
					var b := TAU * jj / m + rng.randf_range(-0.3, 0.3)
					out.append({"at": mid + Vector3(cos(b), 0, sin(b)) * float(role.get("apart", 0.085)), "face": mid})
		"scatter":
			var sp := float(a.get("r", 1.0)) * float(role.get("spread", 0.5))
			for i in n:
				out.append({"at": at + Vector3(rng.randf_range(-sp, sp), 0, rng.randf_range(-sp, sp))})
		"each":
			for p in a.get("points", []):
				var pd: Vector3 = p.get("dir", dir)
				var ps: Vector3 = Vector3(-pd.z, 0, pd.x)
				var m2 := _count(role.get("each", 1), k)
				for jj in m2:
					if rng.randf() >= float(role.get("chance", 1.0)):
						continue
					out.append({"at": (p["at"] as Vector3) + pd * float(role.get("out", 0.0)) + ps * float(role.get("side", 0.0)), "point": p["at"], "dir": pd, "si": p.get("si", -1)})
		"brawl":
			# Pairs at blows in the press: each pair face to face, a step apart.
			var o2: Array = role.get("out", [0.6, 0.8])
			for i in n:
				var p0 := at + dir * rng.randf_range(float(o2[0]), float(o2[1])) + side * float(role.get("side", 0.4)) * (1.0 if i % 2 == 0 else -1.0)
				var p1 := p0 + side * float(role.get("apart", 0.2))
				out.append({"at": p0, "face": p1, "pair": 0})
				out.append({"at": p1, "face": p0, "pair": 1})
	return out


## Shorthand for town_life's constants without a cycle in the preloads.
static func TownLife() -> GDScript:
	return load("res://scripts/town_life.gd")


## Who a role casts for its i-th person: a station; a list taken in turn; or odds ({station: share, ...}, the
## last takes the rest; a share may be by state).
func _who(role: Dictionary, i: int, k: Dictionary) -> String:
	var w: Variant = role.get("who", "townsfolk")
	if w is Array:
		return String(w[i % (w as Array).size()])
	if w is Dictionary:
		var r := (k["rng"] as RandomNumberGenerator).randf()
		var keys: Array = (w as Dictionary).keys()
		for key in keys:
			r -= _val(w[key], k)
			if r < 0.0:
				return String(key)
		return String(keys[-1])
	return String(w)


func _pick(list: Variant, i: int, k: Dictionary, random := false) -> String:
	if not (list is Array) or (list as Array).is_empty():
		return String(list) if list is String else ""
	if random:
		return String(list[(k["rng"] as RandomNumberGenerator).randi() % (list as Array).size()])
	return String(list[i % (list as Array).size()])


## Casts one role of a standing scene: who, how many, where, facing what, and their mind.
func _stage_role(k: Dictionary, role: Dictionary, anchors: Dictionary) -> void:
	var a := _anchor(String(role.get("at", "heart")), k, anchors)
	if a.is_empty():
		(k["tally"]["no_place"] as Array).append("%s.%s" % [k["row"]["id"], role.get("at", "heart")])
		return
	var does := String(role.get("does", "post"))
	if does == "errand" or does == "cart" or does == "beat":
		_stage_walkers(k, role, a, does)
		return
	var n := 0 if String(role.get("form", "")) == "each" else _count(role.get("n", 1), k)
	if bool(role.get("pairs", false)):
		n *= 2
	var spots := _spots(role, a, n, k)
	var root: Node3D = k["root"]
	var life: Node3D = k["life"]
	var tl: Object = k["tl"]
	var rng: RandomNumberGenerator = k["rng"]
	var first: Node3D = null
	var placed: Array = []
	var group: Array = []  # a pair walking together (the chase), a funeral's file
	var i := -1
	for s in spots:
		i += 1
		var want: Vector3 = s["at"]
		if bool(role.get("off_centre", false)):
			want = tl.off_centre(root, want, Data.num("moods", "centre.mourners", 0.08))
		var pos := want
		if not bool(role.get("exact", false)):
			pos = tl.place(root, want, float(role.get("reach", 0.2)), bool(role.get("inside", false)))
			if is_nan(pos.x):
				var nr: Dictionary = k["tally"]["no_room"]
				nr[k["row"]["id"]] = int(nr.get(k["row"]["id"], 0)) + 1
				continue  # no room: the scene is what fits
		else:
			pos.y = tl.ground_at(root, pos)
		var body: Node3D
		if role.has("beast"):
			body = tl.beast(root, String(role["beast"]), pos, role.get("tints", []), i, rng)
		else:
			var tint := Color.WHITE
			var tv: Variant = role.get("tint", null)
			if tv is String and tv == "house":
				tint = tl.house_colour(root)
			elif tv is Array:
				tint = Color(float(tv[0]), float(tv[1]), float(tv[2]))
			var clips: Array = role.get("clips", ["Idle"])
			if bool(role.get("can_play", false)):
				clips = clips.filter(func(c): return preload("res://scripts/weapons.gd").can_play(String(c))).slice(0, 1)  # a lute only once there's a lute
				if clips.is_empty():
					return  # nothing they could play in their hands: they aren't there
			body = tl.cast(root, pos, _who(role, i, k), _pick(clips, i, k, bool(role.get("random", false))), rng.randi(), tint, String(role.get("cast_post", "")), String(role.get("age", "")))
		if body == null:
			continue
		body.set_meta("scene", String((k["row"] as Dictionary)["id"]))
		k["tally"]["cast"] = int(k["tally"]["cast"]) + 1
		if not bool(role.get("exact", false)):
			body.set_meta("spot", true)
		for m in role.get("meta", []):
			body.set_meta(String(m), true)
		if bool(role.get("watch", false)):
			tl.watch(body)
		var arm: Dictionary = role.get("arm", {})
		if not arm.is_empty() and rng.randf() < float(arm.get("odds", 1.0)):
			preload("res://scripts/weapons.gd").arm(body, String(arm.get("kind", "dagger")))
		_face_to(body, role, s, a, k, first)
		if first == null:
			first = body
		if k["lead"] == null:
			k["lead"] = body
		placed.append([body, s])
		group.append(body)
		if bool(role.get("by_day", false)):
			var tick: Node = life.get_node_or_null("Works")
			if tick:
				tick.by_day.append(body)
		if String(role.get("register", "")) == "keepers":
			var keepers: Dictionary = root.get_meta("keepers", {})
			var si := int(s.get("si", -1))
			keepers[si] = body
			if si > 0 and not keepers.has(si - 1):
				keepers[si - 1] = body  # the stall before had no keeper of its own: this one keeps both
			root.set_meta("keepers", keepers)
	# Their minds: a posted person's post (npc_mind.gd), a walker's task.
	for pi in placed.size():
		var body: Node3D = placed[pi][0]
		var s: Dictionary = placed[pi][1]
		match does:
			"post":
				var opening: Array = []
				if role.has("blows"):
					var bl: Array = role["blows"]
					var blows := rng.randi_range(int(bl[0]), int(bl[1]))
					opening = [Mind.run([_pick(role.get("clips", []), int(s.get("pair", pi)), k)], blows, blows)]
				tl.mind(body, _pick(role.get("post", "listener"), pi, k), root, opening)
			"dog":
				_walker(body, Dog.new(), {"life": life, "follow": float(role.get("walk", {}).get("follow", 0.12))}, "", float(role.get("walk", {}).get("trot", 0.2)))
			"chase":
				if pi % 2 == 1:
					var W: Dictionary = role.get("walk", {})
					var pair := {"kids": [placed[pi - 1][0], body], "goal": Vector3.INF, "until": 0, "W": W, "r": float(root.get_meta("square_r", 1.0)) * float(W.get("r", 0.8)), "root": root, "tl": tl}
					for kid in pair["kids"]:
						kid.set_meta("pair", pi / 2)
						_walker(kid, Chase.new(), {"pair": pair, "root": root}, "Running", float(W.get("pace", 0.32)))
				elif pi == placed.size() - 1:
					body.queue_free()  # no one found room to chase him: he isn't there
			"live":
				Animals.live(body, String(role.get("beast", "")), rng)  # its own idle life (a hen pecking about)
			"procession":
				pass
	if does == "procession":
		_procession(k, role, group, a)


func _face_to(body: Node3D, role: Dictionary, s: Dictionary, a: Dictionary, k: Dictionary, first: Node3D) -> void:
	var at: Vector3 = a.get("at", Vector3.ZERO)
	var dir: Vector3 = s.get("dir", a.get("dir", SEEN))
	var rng: RandomNumberGenerator = k["rng"]
	var to := Vector3.INF
	match String(role.get("face", "anchor")):
		"anchor":
			to = at
		"point":
			to = s.get("point", at)
		"ahead":
			to = body.position + dir.rotated(Vector3.UP, rng.randf_range(-float(role.get("wobble", 0.0)), float(role.get("wobble", 0.0))))
		"behind":
			to = body.position - dir
		"heart":
			var j := float(role.get("jitter", 0.0))
			to = Vector3(rng.randf_range(-j, j), 0, rng.randf_range(-j, j))
		"lead":
			to = (k["lead"] as Node3D).position if k["lead"] != null else at
		"mid", "pair":
			to = s.get("face", at)
		"half":  # half of them to the heart, the rest anywhere (the hungry waiting about)
			if rng.randf() < 0.5:
				body.rotation.y = rng.randf() * TAU
				return
			to = Vector3.ZERO
		"random":
			body.rotation.y = rng.randf() * TAU
			return
	if s.has("face") and String(role.get("face", "")) in ["mid", "pair"]:
		to = s["face"]
	var flat := Vector2(to.x - body.position.x, to.z - body.position.z)
	if flat.length() > 0.001:
		body.rotation.y = atan2(flat.x, flat.y)


# --- the walkers' rounds -----------------------------------------------------------------------------

## Gives a body its walker's mind: one LimboAI task, repeated, on its own clock; it walks with the Mover.
func _walker(body: Node3D, task: BTTask, vars: Dictionary, clip: String, pace := 0.15) -> void:
	body.set_meta("walker", true)
	var m: Node = Mover.of(body)
	m.speed = pace * READ
	m.clip = clip
	var rootseq := BTSequence.new()
	var first := BTRandomWait.new()
	first.min_duration = 0.1
	first.max_duration = 2.0
	rootseq.add_child(first)
	var forever := BTRepeat.new()
	forever.forever = true
	forever.add_child(task)
	rootseq.add_child(forever)
	var bt := BehaviorTree.new()
	bt.root_task = rootseq
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(body)
	player.behavior_tree = bt
	for key in vars:
		player.blackboard.set_var(StringName(key), vars[key])
	body.add_child(player)


## The beat, the errands and the cart: walkers going round places of the square in turn.
func _stage_walkers(k: Dictionary, role: Dictionary, a: Dictionary, does: String) -> void:
	var root: Node3D = k["root"]
	var life: Node3D = k["life"]
	var tl: Object = k["tl"]
	var rng: RandomNumberGenerator = k["rng"]
	var W: Dictionary = role.get("walk", {})
	var n := _count(role.get("n", 1), k)
	var r := float(root.get_meta("square_r", 1.0))
	for i in n:
		match does:
			"beat":
				var route := _beat(root, tl, r, i, rng, W)
				if route.size() < 2:
					continue
				var plan := {"goal": Vector3.INF, "until": 0, "leg": 1}
				for j in 2:
					var at: Vector3 = route[0] + Vector3(0.07 * j, 0, 0)
					at.y = tl.ground_at(root, at)
					var g: Node3D = tl.cast(root, at, String(role.get("who", "soldier")), "Sword_Idle", rng.randi(), tl.house_colour(root) if role.get("tint", "") == "house" else Color.WHITE, "", "")
					g.set_meta("scene", String(k["row"]["id"]))
					for m in role.get("meta", []):
						g.set_meta(String(m), true)
					if bool(role.get("watch", false)):
						tl.watch(g)
					if j == 0:
						_walker(g, Round.new(), {"route": route.map(func(q): return root.to_global(q)), "plan": plan, "lead": true, "side": 0.0,
							"pause": W.get("pause", [3.0, 7.0]), "rest": W.get("rest", ["Looking_Around"]), "waits": []}, "Walk", float(W.get("pace", 0.14)))
						plan["lead_body"] = g
					else:
						# His mate walks at his side and stops when he stops.
						_walker(g, Follow.new(), {"after": plan["lead_body"], "gap": 0.0, "side": float(W.get("abreast", 0.1)), "rest": W.get("rest", ["Looking_Around"])}, "Walk", float(W.get("pace", 0.14)) * 1.2)
			"errand":
				var stops: Array = a.get("points", [])
				if stops.size() < 2:
					return
				var loads: Array = role.get("loads", [["Carrying", "townsfolk", "female"]])
				var ld: Array = loads[i % loads.size()]
				var start: Vector3 = stops[rng.randi() % stops.size()]["at"]
				var p: Vector3 = tl.place(root, start + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), 0.3, false)
				if is_nan(p.x):
					continue
				var man: Node3D = tl.cast(root, p, String(ld[1]), String(ld[0]), rng.randi(), Color.WHITE, "", "", String(ld[2]) if ld.size() > 2 else "")
				man.set_meta("scene", String(k["row"]["id"]))
				man.set_meta("spot", true)
				for m in role.get("meta", []):
					man.set_meta(String(m), true)
				if ld.size() > 3 and String(ld[3]) == "shoulder":
					TownLife().shoulder_sack(man, true)  # a sack on his shoulder, carried through every move
				# Each carrier his own place at each stop, an open spot claimed like anyone's standing: never on another.
				var order: Array = []
				for st in stops:
					var q: Vector3 = tl.place(root, st["at"], 0.25, false)
					if not is_nan(q.x):
						order.append(q)
				if order.size() < 2:
					man.queue_free()
					continue
				order.shuffle()
				var streets: Array = a.get("streets", [])
				if not streets.is_empty() and rng.randf() < float(role.get("street_share", 0.6)):
					# Up one street and back: between two places on the square, never street to street across the houses.
					order.insert(1 + rng.randi() % (order.size() - 1), streets[i % streets.size()])
				_walker(man, Round.new(), {"route": order.map(func(q): return root.to_global(q)), "plan": {"goal": Vector3.INF, "until": 0, "leg": 0}, "lead": true, "side": 0.0,
					"pause": W.get("pause", [2.0, 6.0]), "rest": [String(W.get("set_down", "PickUp_Table"))], "waits": []}, String(ld[0]), float(W.get("pace", 0.15)))
			"cart":
				_cart(k, role, W, r)


## A guard pair's beat: from one main street's mouth across the square past the well to another's, a stop at
## each to look about, then on; with the castle by the square, from its gate. A ring round the square without them.
func _beat(root: Node3D, tl: Object, r: float, k: int, rng: RandomNumberGenerator, W: Dictionary) -> Array:
	var mouths: Array = []
	for w in root.get_meta("ways_main", []):
		for q in w as PackedVector2Array:
			if q.length() > r * float(W.get("mouth", 0.95)):
				mouths.append(Vector3(q.x, 0, q.y))
				break
	if mouths.size() < 2:
		var ring: Array = []
		var a0 := rng.randf() * TAU
		for i in 8:
			var a := a0 + TAU * i / 8.0 * (1.0 if k % 2 == 0 else -1.0)
			ring.append(Vector3(cos(a), 0, sin(a)) * r * float(W.get("ring", 0.85)))
		return ring
	var places: Dictionary = root.get_meta("places", {})
	var mid: Vector3 = places.get("well", Vector3.ZERO)
	var by_well: Vector3 = tl.place(root, mid + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.3, 0.4, false)
	var gate := Vector3.INF
	var castle: Array = root.get_meta("castle_frame", [])
	if castle.size() >= 3 and bool(W.get("gate", true)):
		var cp: Vector3 = castle[0]
		var cb := Basis(Vector3.UP, float(castle[1]))
		var half := float((castle[2] as Vector2).y) * 0.5 + float(W.get("gate_out", 0.2))
		var g1: Vector3 = cp + cb * Vector3(0, 0, half)
		var g2: Vector3 = cp - cb * Vector3(0, 0, half)
		var g := g1 if g1.length() < g2.length() else g2  # the castle's end toward the square
		if g.length() < r * 3.0:
			var q: Vector3 = tl.place(root, g, 0.4, false)
			if not is_nan(q.x):
				gate = q
	var route: Array = []
	if gate != Vector3.INF:
		route.append(gate)
	route.append(mouths[k % mouths.size()])
	if not is_nan(by_well.x):
		route.append(by_well)
	route.append(mouths[(k + 1) % mouths.size()])
	if not is_nan(by_well.x) and gate == Vector3.INF:
		route.append(by_well)
	return route


## A horse and cart rolling in along one main street's own line to the market, out along the other and back,
## waiting only at the market (its tail a porter's slot meanwhile) and at the streets' ends.
func _cart(k: Dictionary, role: Dictionary, W: Dictionary, r: float) -> void:
	var root: Node3D = k["root"]
	var life: Node3D = k["life"]
	var tl: Object = k["tl"]
	var ways: Array = root.get_meta("ways_main", [])
	if ways.size() < 2:
		return
	var ends: Array = []
	var lanes: Array = []
	for w in ways.slice(0, 2):
		var line := w as PackedVector2Array
		var far := line[line.size() - 1]
		var lane: Array = []
		for q in line:
			if q.length() > r * 0.9:
				lane.append(Vector3(q.x, 0, q.y))
			if q.length() > r * float(W.get("from", 1.3)):
				far = q
				break
		ends.append(Vector3(far.x, 0, far.y))
		if lane.is_empty() or (lane[0] as Vector3).length() > (lane[lane.size() - 1] as Vector3).length():
			lane.reverse()  # the square's end first
		lanes.append(lane)
	var rig: Node3D = TownLife().horse_cart(tl._people, k["rng"])
	if rig == null:
		return
	rig.position = Vector3(ends[0].x, tl.ground_at(root, ends[0]), ends[0].z)
	life.add_child(rig)
	rig.set_meta("scene", String(k["row"]["id"]))
	rig.set_meta("cart", true)
	var mkt: Vector3 = (root.get_meta("places", {}) as Dictionary).get("market", Vector3.ZERO) * float(W.get("market_in", 0.7))
	var out_b: Array = (lanes[1] as Array).duplicate()
	var in_b: Array = out_b.duplicate()
	in_b.reverse()
	var out_a: Array = (lanes[0] as Array).duplicate()
	var in_a: Array = out_a.duplicate()
	in_a.reverse()
	var route: Array = in_a + [mkt] + out_b + [ends[1]] + in_b + [mkt] + out_a + [ends[0]]
	var waits: Array = route.map(func(q): return q == mkt or q == ends[0] or q == ends[1])
	Mover.of(rig).turn_radius = float(W.get("turn_radius", 0.45))  # a cart steers round, never spins
	_walker(rig, Round.new(), {"route": route.map(func(q): return root.to_global(q)), "plan": {"goal": Vector3.INF, "until": 0, "leg": 0}, "lead": true, "side": 0.0,
		"pause": W.get("stop", [6.0, 12.0]), "rest": [], "waits": waits, "market": root.to_global(mkt), "tail": float(W.get("tail", 0.22)), "town": root,
		"carter": rig.get_meta("carter", null)}, "", float(W.get("pace", 0.16)))


## The funeral round the square: its head (the priest) walks the ring; each behind follows the one before at
## `spacing`, so the column keeps its shape round the bends; the bier rides on the bearers' shoulders.
func _procession(k: Dictionary, role: Dictionary, group: Array, a: Dictionary) -> void:
	var ring: Array = a.get("route", [])
	if group.is_empty() or ring.is_empty():
		return
	var root: Node3D = k["root"]
	var W: Dictionary = (k["row"] as Dictionary).get("walk", {})
	var pace := float(W.get("pace", 0.07))
	# The whole file, in the order the row casts it (priest, bearers, mourners), across this row's roles.
	var file: Array = (k.get("file", []) as Array)
	file.append_array(group)
	k["file"] = file
	if role != (k["row"]["roles"] as Array)[-1]:
		return
	var behind: Vector3 = ((ring[0] as Vector3) - (ring[1 % ring.size()] as Vector3)).normalized()
	var spacing := float(W.get("spacing", 0.11))
	for i in file.size():
		var w: Node3D = file[i]
		var at: Vector3 = (ring[0] as Vector3) + behind * spacing * i  # in file behind the head, not on one spot
		w.position = Vector3(at.x, (k["tl"] as Object).ground_at(root, at), at.z)
		People.play(w, "Walk", 0.7)
		if i == 0:
			w.set_meta("head", true)
			_walker(w, Round.new(), {"route": ring.map(func(q): return root.to_global(q)), "plan": {"goal": Vector3.INF, "until": 0, "leg": 1}, "lead": true, "side": 0.0,
				"pause": [0.0, 0.0], "rest": [], "waits": []}, "Walk", pace)
		else:
			_walker(w, Follow.new(), {"after": file[i - 1], "gap": spacing}, "Walk", pace * 1.4)
		Mover.of(w).stride = true
	var bier: Node3D = a.get("bier", null)
	var bearers := file.filter(func(n): return n.has_meta("bearer"))
	if bier and bearers.size() >= 2:
		# Carried: it rides on the second bearer's shoulders, the file's spacing keeping the others under it.
		var under: Node3D = bearers[1]
		var s := bier.scale / maxf(under.scale.x, 0.001)
		bier.get_parent().remove_child(bier)
		under.add_child(bier)
		bier.position = Vector3(0, 0.15 / maxf(under.scale.x, 0.001), 0)
		bier.rotation = Vector3.ZERO
		bier.scale = s


# --- the levy marching out ----------------------------------------------------------------------------

## A levy's men leave the muster file by file (town_scenes.json muster march), along the road nearest them.
func _begin_march(root: Node3D, life: Node3D, m: Dictionary, rng: RandomNumberGenerator) -> void:
	var marker := Node3D.new()
	marker.name = "Leaving"  # the drum and the boots are heard by it (sound_v2.gd)
	life.add_child(marker)
	var every: Array = m.get("every", [7.0, 13.0])
	var e := {"root": root, "life": life, "marker": marker, "every": every, "file": int(m.get("file", 1)), "spacing": float(m.get("spacing", 0.13)),
		"most": int(m.get("most", 5)), "pace": float(m.get("pace", 0.15)), "gone": 0, "rng": RandomNumberGenerator.new()}
	(e["rng"] as RandomNumberGenerator).seed = rng.randi()
	e["wait"] = (e["rng"] as RandomNumberGenerator).randf_range(2.0, float(every[0]))
	_marches.append(e)


func _march(delta: float) -> void:
	for e in _marches.duplicate():
		if not is_instance_valid(e["root"]) or not is_instance_valid(e["life"]) or (e["life"] as Node).is_queued_for_deletion():
			_marches.erase(e)
			continue
		e["wait"] = float(e["wait"]) - delta
		if float(e["wait"]) > 0.0 or int(e["gone"]) >= int(e["most"]):
			continue
		var rng: RandomNumberGenerator = e["rng"]
		e["wait"] = rng.randf_range(float(e["every"][0]), float(e["every"][1]))
		var life: Node3D = e["life"]
		var men := life.get_children().filter(func(n): return n.has_meta("levy_man") and not n.has_meta("leaving"))
		if men.is_empty():
			continue
		var path := _road_out(e["root"], men[0])
		if path.is_empty():
			continue  # a town with no roads: they stay in the muster
		var first: Vector3 = path[0]
		men.sort_custom(func(a, b): return (a as Node3D).position.distance_to(first) < (b as Node3D).position.distance_to(first))  # the file leaves from the muster's edge nearest the road, never through its ranks
		for k in mini(int(e["file"]), men.size()):
			if int(e["gone"]) >= int(e["most"]):
				break
			var p: Node3D = men[k]
			p.set_meta("leaving", true)
			var mind := p.get_node_or_null("Mind")
			if mind:
				p.remove_child(mind)
				mind.queue_free()  # his post put by: he marches now
			e["gone"] = int(e["gone"]) + 1
			var root: Node3D = e["root"]
			if k == 0:
				_walker(p, MarchOut.new(), {"route": path.map(func(q): return root.to_global(q))}, "Carrying", float(e["pace"]))
			else:
				# In file behind the man before him, and gone with the column at the road's end.
				_walker(p, Follow.new(), {"after": men[k - 1], "gap": float(e["spacing"]), "with": true}, "Carrying", float(e["pace"]) * 1.2)
		var marker: Node3D = e["marker"]
		var walking: Array = (marker.get_meta("walking", []) as Array).filter(func(w): return is_instance_valid(w[0]) and not (w[0] as Node).is_queued_for_deletion())
		for p in life.get_children().filter(func(n): return n.has_meta("leaving")):
			if not walking.any(func(w): return w[0] == p):
				walking.append([p])
		marker.set_meta("walking", walking)  # the drum and the boots go with the first of them (sound_v2.gd)


## The way out along the nearest main road, heart outward, from near `p`; [] with no roads.
func _road_out(root: Node3D, p: Node3D) -> Array:
	var best: Array = []
	var near := INF
	for w in root.get_meta("ways_main", []):
		var path := PackedVector2Array(w)
		for i in path.size():
			var dd := path[i].distance_to(Vector2(p.position.x, p.position.z))
			if dd < near:
				near = dd
				best = Array(path.slice(i)).map(func(q: Vector2) -> Vector3: return Vector3(q.x, 0, q.y))
	return best


# --- the passing scenes: near the camera ---------------------------------------------------------------

## One town's tick: scenes past their time end, new ones start up to the town's cap, and the store learns it.
func _direct(id: int, root: Node3D, c: Dictionary) -> void:
	var bb: Blackboard = main.awareness.town(id)
	var states := Works.states_bb(bb)
	if String(bb.get_var(&"mood", "", false)) == "riot":
		states.append("riot")
	var now := Time.get_ticks_msec()
	var running: Array = _live.get(id, [])
	for s in running:
		if not bool(s["ending"]) and now >= int(s["ends"]):
			_end(s)
	running = running.filter(func(s): return not (s["cast"] as Array).is_empty() or not bool(s["ending"]))
	var D: Dictionary = _d.get("director", {}).get("most", {})
	var cap := mini(int(D.get("cap", 9)), int(float(D.get("base", 3)) + float(D.get("per_size", 0.5)) * float(c.get("size", 1))))
	var active := running.filter(func(s): return not bool(s["ending"])).size()
	var tries := 4
	while active < cap and tries > 0:
		tries -= 1
		var row := _choose(states, running, root)
		if row.is_empty():
			break
		var s := _start(id, root, row)
		if s.is_empty():
			continue
		running.append(s)
		active += 1
	_live[id] = running
	bb.set_var(&"scenes", running.map(func(s): return {"id": s["row"]["id"], "at": s["at"], "ending": s["ending"]}))
	bb.set_var(&"claims", running.filter(func(s): return not bool(s["ending"])).map(func(s): return s["key"]))


## A passing scene the town may play now, drawn by weight: in its hours, its needs met, under its own cap.
func _choose(states: Array, running: Array, root: Node3D) -> Dictionary:
	var h := Works.hour()
	var pool: Array = []
	var total := 0.0
	for row in _d.get("scenes", []):
		var hours: Array = row.get("hours", [0, 24])
		var a := float(hours[0])
		var b := float(hours[1])
		if not ((h >= a and h < b) if a <= b else (h >= a or h < b)):
			continue
		var needs: Array = row.get("needs", [])
		if not needs.is_empty() and not needs.any(func(n): return n in states):
			continue
		if running.filter(func(s): return s["row"]["id"] == row["id"] and not bool(s["ending"])).size() >= int(row.get("most", 1)):
			continue
		if _object_at(root, String(row.get("at", "square"))) == Vector3.INF:
			continue
		var w := float(row.get("weight", 1.0))
		for st in states:
			w *= float((row.get("moods", {}) as Dictionary).get(st, 1.0))
		if w <= 0.0:
			continue
		pool.append([row, w])
		total += w
	if pool.is_empty():
		return {}
	var r := _rng.randf() * total
	for p in pool:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return pool[-1][0]


## Where an object stands in this town (world), from what the town records; INF if it has none.
func _object_at(root: Node3D, key: String) -> Vector3:
	var o: Dictionary = _d.get("objects", {}).get(key, {})
	var centre := root.global_position
	if o.is_empty():
		return Vector3.INF
	if bool(o.get("square", false)):
		return centre
	if o.has("place"):
		var places: Dictionary = root.get_meta("places", {})
		return centre + Vector3(places[o["place"]]) if places.has(o["place"]) else Vector3.INF
	if bool(o.get("gate", false)):
		var g := Works.gate(root, Vector3.ZERO)
		return centre + g if g != Vector3.INF else Vector3.INF
	if o.has("works"):
		var b := Works.find(root, String(o["works"]))
		if not b.is_empty():
			return centre + Vector3(b["at"])
		if o.has("or"):
			return _object_at(root, String(o["or"]))
	return Vector3.INF


func _start(id: int, root: Node3D, row: Dictionary) -> Dictionary:
	var at := _object_at(root, String(row.get("at", "square")))
	if at == Vector3.INF or main.scenes == null:
		return {}
	var last: Array = row.get("last", [30, 60])
	_seq += 1
	var s := {"row": row, "key": "%s:%d" % [row["id"], _seq], "at": at, "cast": [], "ending": false,
		"ends": Time.get_ticks_msec() + int(_rng.randf_range(float(last[0]), float(last[1])) * 1000.0), "town": id}
	var axis := _rng.randf() * TAU
	var first := Vector3.INF
	for role in row.get("roles", []):
		var n: Array = role.get("n", [1, 1])
		var count := _rng.randi_range(int(n[0]), int(n[1]))
		for i in count:
			var spot := _passing_spot(at, role, i, count, axis)
			var face := at
			if bool(role.get("face", false)) and first != Vector3.INF:
				face = first
			var p := _cast(s, role, main.scenes.stand(spot), face)
			if p and first == Vector3.INF:
				first = main.scenes.stand(spot)
	return s


## A passing person's spot by the role's form: a ring round the object, a line out from it, a pair facing.
func _passing_spot(at: Vector3, role: Dictionary, i: int, count: int, axis: float) -> Vector3:
	var form := String(role.get("form", "ring"))
	var r: Array = role.get("r", [0.4, 0.6])
	match form:
		"line":
			var gap := float(role.get("gap", 0.2))
			var dir := Vector3(cos(axis), 0, sin(axis))
			return at + dir * (0.35 + gap * i)
		"pair":
			var d := _rng.randf_range(float(r[0]), float(r[1]))
			var side := 1.0 if i % 2 == 0 else -1.0
			return at + Vector3(cos(axis), 0, sin(axis)) * d * 0.5 * side + Vector3(-sin(axis), 0, cos(axis)) * 0.15 * float(i / 2)
		_:
			var a := axis + TAU * float(i) / float(maxi(count, 1)) + _rng.randf_range(-0.2, 0.2)
			var d2 := _rng.randf_range(float(r[0]), float(r[1]))
			return at + Vector3(cos(a), 0, sin(a)) * d2


## One person for a passing role: made at the edge of view, given their tree, walked to their spot by the Mover.
func _cast(s: Dictionary, role: Dictionary, spot: Vector3, face: Vector3) -> Node3D:
	var who := String(role.get("who", "townsfolk"))
	var age := ""
	if who == "child":
		who = "townsfolk"
		age = "child"
	var cloth: Array = People.cloth_of(who)
	var person: Node3D = main.scenes.people.make(_rng, who, cloth[_rng.randi() % cloth.size()] if not cloth.is_empty() else Color.WHITE, age)
	if person == null:
		return null
	add_child(person)
	person.set_meta("scene", String(s["row"]["id"]))
	var D: Dictionary = _d.get("director", {})
	var enter: Array = D.get("enter", [1.2, 2.0])
	var a := _rng.randf() * TAU
	person.global_position = main.scenes.stand(spot + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(float(enter[0]), float(enter[1])))
	var mover: Node = Mover.of(person)
	mover.speed = float(D.get("pace", 0.17))
	var bt := BehaviorTree.new()
	bt.root_task = _tree()
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(person)
	player.behavior_tree = bt
	var bb := player.blackboard
	bb.set_var(&"slot", spot)
	bb.set_var(&"face", face)
	bb.set_var(&"clips", role.get("clips", ["Idle"]))
	bb.set_var(&"leaving", false)
	bb.set_var(&"exit", person.global_position)
	bb.set_var(&"react", {})
	bb.set_var(&"clip", "")  # every var a task reads, declared as the person is made: no read misses
	bb.set_var(&"clip_left", 0.0)
	bb.set_var(&"done", _done.bind(s, person))
	person.add_child(player)
	(s["cast"] as Array).append(person)
	return person


## A passing person's day in a scene: a reaction first whenever there is one, else walk to the spot, act until
## the scene ends, walk off. Re-checked every tick (a dynamic selector), so news cuts in at once.
func _tree() -> BTTask:
	var life := BTDynamicSelector.new()
	var react := BTSequence.new()
	react.add_child(HasReact.new())
	react.add_child(DoReact.new())
	life.add_child(react)
	var day := BTSequence.new()
	day.add_child(GoTo.new())
	day.add_child(Act.new())
	day.add_child(Leave.new())
	life.add_child(day)
	return life


## The scene's time is up: its people leave (their trees walk them off and dispatch back).
func _end(s: Dictionary) -> void:
	s["ending"] = true
	for p in s["cast"]:
		var m := (p as Node).get_node_or_null("Mind") as BTPlayer
		if m:
			m.blackboard.set_var(&"leaving", true)


## A person has walked off: the only way a cast member leaves the store.
func _done(s: Dictionary, person: Node3D) -> void:
	(s["cast"] as Array).erase(person)
	if is_instance_valid(person):
		person.queue_free()


## Out of range: the town's passing scenes are put away at once (nobody watches them go).
func _end_town(id: int) -> void:
	if not _live.has(id):
		return
	for s in _live[id]:
		for p in s["cast"]:
			if is_instance_valid(p):
				p.queue_free()
	_live.erase(id)
	if main and main.awareness:
		var bb: Blackboard = main.awareness.town(id)
		bb.set_var(&"scenes", [])
		bb.set_var(&"claims", [])


# --- news: the reactions ---------------------------------------------------------------------------

func _on_stimulus(kind: String, pos: Vector3, radius: float, _house: String, _strength: float) -> void:
	var row: Dictionary = _d.get("reactions", {}).get(SceneKinds.tone(kind), {})
	if row.is_empty() or radius <= 0.0:
		return
	var until := Time.get_ticks_msec() + int(float(row.get("last", 20)) * 1000.0)
	for scenes in _live.values():
		for s in scenes:
			for p in s["cast"]:
				if not is_instance_valid(p):
					continue
				var d := (p as Node3D).global_position.distance_to(pos)
				if d > radius:
					continue
				var act: Dictionary = row.get("near_act", {}) if d / radius <= float(row.get("near", 1.0)) else row.get("far_act", row.get("near_act", {}))
				var m := (p as Node).get_node_or_null("Mind") as BTPlayer
				if m and not act.is_empty():
					m.blackboard.set_var(&"react", {"act": act.get("act", "gather"), "at": pos, "r": float(act.get("r", 1.0)), "clips": act.get("clips", ["Looking_Around"]), "until": until})


# --- the tasks: one tree each, the person's only decider ----------------------------------------

## What every task does the same way: play clips in turn, face a point.
class Kit:
	## Plays a person's clips in turn, never the same twice running, a new one every few seconds.
	static func _cycle(agent: Node, bb: Blackboard, clips: Array, delta: float) -> void:
		var left := float(bb.get_var(&"clip_left", 0.0, false)) - delta
		if left > 0.0:
			bb.set_var(&"clip_left", left)
			return
		var last := String(bb.get_var(&"clip", "", false))
		var pool := clips.filter(func(c): return c != last)
		if pool.is_empty():
			pool = clips
		var clip := String(pool[randi() % pool.size()]) if not pool.is_empty() else "Idle"
		bb.set_var(&"clip", clip)
		bb.set_var(&"clip_left", randf_range(3.0, 7.0))
		People.play(agent, clip, randf_range(0.9, 1.1))


	static func _face(agent: Node3D, at: Vector3) -> void:
		var f := Vector2(at.x - agent.global_position.x, at.z - agent.global_position.z)
		if f.length() > 0.01:
			agent.rotation.y = atan2(f.x, f.y)


class HasReact extends BTCondition:
	func _tick(_delta: float) -> Status:
		var r: Dictionary = blackboard.get_var(&"react", {})
		if r.is_empty():
			return FAILURE
		if Time.get_ticks_msec() > int(r.get("until", 0)):
			blackboard.set_var(&"react", {})
			return FAILURE
		return SUCCESS


class DoReact extends BTAction:
	func _enter() -> void:
		var r: Dictionary = blackboard.get_var(&"react", {})
		var me := agent as Node3D
		var at: Vector3 = r.get("at", me.global_position)
		var mover: Node = Mover.of(me)
		match String(r.get("act", "gather")):
			"flee":
				var away := (me.global_position - at)
				away.y = 0
				mover.go(me.global_position + away.normalized() * 1.5 if away.length() > 0.01 else me.global_position)
			"gather":
				var a := randf() * TAU
				mover.go(at + Vector3(cos(a), 0, sin(a)) * float(r.get("r", 1.0)))
			_:
				mover.stop()
		blackboard.set_var(&"clip_left", 0.0)

	func _tick(delta: float) -> Status:
		var r: Dictionary = blackboard.get_var(&"react", {})
		if r.is_empty() or Time.get_ticks_msec() > int(r.get("until", 0)):
			blackboard.set_var(&"react", {})
			return SUCCESS
		if not Mover.of(agent as Node3D).moving():
			Kit._face(agent as Node3D, r.get("at", Vector3.ZERO))
			Kit._cycle(agent, blackboard, r.get("clips", ["Looking_Around"]), delta)
		return RUNNING

	func _exit() -> void:
		Mover.of(agent as Node3D).stop()


class GoTo extends BTAction:
	func _enter() -> void:
		Mover.of(agent as Node3D).go(blackboard.get_var(&"slot", (agent as Node3D).global_position))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		Kit._face(agent as Node3D, blackboard.get_var(&"face", Vector3.ZERO))
		blackboard.set_var(&"clip_left", 0.0)
		return SUCCESS

	func _exit() -> void:
		Mover.of(agent as Node3D).stop()


class Act extends BTAction:
	func _tick(delta: float) -> Status:
		if bool(blackboard.get_var(&"leaving", false)):
			return SUCCESS
		Kit._cycle(agent, blackboard, blackboard.get_var(&"clips", ["Idle"]), delta)
		return RUNNING


class Leave extends BTAction:
	func _enter() -> void:
		Mover.of(agent as Node3D).go(blackboard.get_var(&"exit", (agent as Node3D).global_position))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		var done: Callable = blackboard.get_var(&"done", Callable())
		if done.is_valid():
			done.call()
		return SUCCESS


## A round of places in turn (route, world points), looping: the watch's beat (a pair: the lead decides, the other
## walks at his side and stops when he stops), a carrier's errands (set down a while at each), the cart (waiting
## only where `waits` says; drawn up at the market its tail is a porter's slot), the funeral's head. At each stop it
## rests `pause` seconds playing one of `rest`.
class Round extends BTAction:
	var _goal := Vector3.INF

	func _tick(_delta: float) -> Status:
		var me := agent as Node3D
		var m: Node = Mover.of(me)
		var plan: Dictionary = blackboard.get_var(&"plan", {}, false)
		var route: Array = blackboard.get_var(&"route", [], false)
		if route.is_empty():
			return RUNNING
		var now := Time.get_ticks_msec()
		var lead := bool(blackboard.get_var(&"lead", true, false))
		var side := float(blackboard.get_var(&"side", 0.0, false))
		if now < int(plan.get("until", 0)):
			return RUNNING  # resting at a stop
		var goal: Vector3 = route[int(plan["leg"]) % route.size()]
		if not lead:
			goal = plan.get("goal", goal)
		if lead:
			plan["yaw"] = me.rotation.y
		var off := Basis(Vector3.UP, float(plan.get("yaw", me.rotation.y))) * Vector3(side, 0, 0)  # abreast on the lead's heading
		if _goal != goal:
			_goal = goal
			_set_tail(false)
			_carter(true)
			m.go(goal + off)
			if lead:
				plan["goal"] = goal
			return RUNNING
		if m.moving() or not lead:
			return RUNNING
		# There: on to the next, after a rest where this stop is one.
		var here := int(plan["leg"]) % route.size()
		plan["leg"] = int(plan["leg"]) + 1
		var waits: Array = blackboard.get_var(&"waits", [], false)
		if not waits.is_empty() and not bool(waits[here]):
			return RUNNING  # a bend in the street: on without stopping
		var pause: Array = blackboard.get_var(&"pause", [0.0, 0.0], false)
		var secs := randf_range(float(pause[0]), float(pause[1]))
		if secs > 0.0:
			plan["until"] = now + int(secs * 1000.0)
			var rest: Array = blackboard.get_var(&"rest", [], false)
			if not rest.is_empty():
				People.play(me, String(rest[randi() % rest.size()]))
			if blackboard.has_var(&"market") and (blackboard.get_var(&"market") as Vector3).distance_to(goal) < 0.02:
				_set_tail(true)
			_carter(false)
		return RUNNING

	func _set_tail(on: bool) -> void:
		if not blackboard.has_var(&"town"):
			return
		var town: Node3D = blackboard.get_var(&"town")
		if not is_instance_valid(town):
			return
		var me := agent as Node3D
		if on:
			var back := Vector3(sin(me.rotation.y), 0, cos(me.rotation.y))
			var at := town.to_local(me.global_position)
			town.set_meta("cart_tail", [at - back * float(blackboard.get_var(&"tail", 0.22, false)), at])
		elif town.has_meta("cart_tail"):
			town.remove_meta("cart_tail")  # rolling: nothing to unload

	func _carter(walking: bool) -> void:
		var c: Variant = blackboard.get_var(&"carter", null, false) if blackboard.has_var(&"carter") else null
		if c is Node3D and is_instance_valid(c):
			People.play(c, "Walk" if walking else ["Idle", "Looking_Around", "Idle_Talking"][randi() % 3])


## Walks after someone at `gap` behind them (and `side` to their right), asked again once they've moved a stride:
## a mourner in the funeral's file behind the one before, a guard at his mate's side on the beat. Stood still
## together, they play one of `rest`.
class Follow extends BTAction:
	var _asked := Vector3.INF
	var _rested := false

	func _tick(_delta: float) -> Status:
		var who: Variant = blackboard.get_var(&"after", null, false)
		if not (who is Node3D) or not is_instance_valid(who) or (who as Node).is_queued_for_deletion():
			if bool(blackboard.get_var(&"with", false, false)):
				agent.queue_free()  # the column's head is gone up the road: so is he
			return RUNNING
		var them := who as Node3D
		var back := Vector3(sin(them.rotation.y), 0, cos(them.rotation.y))
		var right := Vector3(back.z, 0, -back.x)
		var to := them.global_position - back * float(blackboard.get_var(&"gap", 0.11, false)) + right * float(blackboard.get_var(&"side", 0.0, false))
		var me := agent as Node3D
		var m: Node = Mover.of(me)
		if Vector2(to.x - me.global_position.x, to.z - me.global_position.z).length() < 0.02:
			var rest: Array = blackboard.get_var(&"rest", [], false)
			if not _rested and not rest.is_empty() and not Mover.of(them).moving():
				_rested = true
				People.play(me, String(rest[randi() % rest.size()]))
			return RUNNING
		_rested = false
		if _asked == Vector3.INF or _asked.distance_to(to) > 0.03 or not m.moving():
			_asked = to
			m.go(to)
		return RUNNING


## A town dog: lies about a while, then trots after someone near (a child at play by choice) for a while.
class Dog extends BTAction:
	var _after: Node3D
	var _for := 0.0
	var _rest := 0.0
	var _asked := Vector3.INF

	func _enter() -> void:
		_rest = randf_range(2.0, 8.0)

	func _tick(delta: float) -> Status:
		var dog := agent as Node3D
		var m: Node = Mover.of(dog)
		if _after == null or not is_instance_valid(_after):
			_rest -= delta
			Animals.walk(dog, m.moving())
			if _rest > 0.0:
				return RUNNING
			var life: Node3D = blackboard.get_var(&"life")
			if not is_instance_valid(life):
				return RUNNING
			var folk := life.get_children().filter(func(n): return n is Node3D and n != dog and n.has_node("Anim") and (n as Node3D).position.distance_to(dog.position) < 1.2)
			var kids := folk.filter(func(n): return n.has_meta("chasing"))
			var pool := kids if not kids.is_empty() and randf() < 0.6 else folk
			if pool.is_empty():
				_rest = randf_range(3.0, 8.0)
				return RUNNING
			_after = pool[randi() % pool.size()]
			_for = randf_range(6.0, 14.0)
			return RUNNING
		_for -= delta
		if _for <= 0.0:
			_after = null
			m.stop()
			_rest = randf_range(4.0, 12.0)  # it lies about, sniffs, scratches (its idle life)
			Animals.walk(dog, false)
			return RUNNING
		var to := _after.global_position
		if dog.global_position.distance_to(to) <= float(blackboard.get_var(&"follow", 0.12, false)):
			m.stop()
		elif _asked == Vector3.INF or _asked.distance_to(to) > 0.05 or not m.moving():
			_asked = to
			m.go(to)
		Animals.walk(dog, m.moving())
		return RUNNING


## Two children playing tag round the square's open cobble: the runner makes for a spot away from the chaser, the
## chaser after him; caught, they swap and the new chaser counts a beat while the other runs off; now and then they
## stop for a breather first (laughing, bent over, pointing).
class Chase extends BTAction:
	var _asked := Vector3.INF

	func _tick(_delta: float) -> Status:
		var pair: Dictionary = blackboard.get_var(&"pair")
		var kids: Array = pair["kids"]
		if kids.size() < 2 or not is_instance_valid(kids[0]) or not is_instance_valid(kids[1]):
			return RUNNING
		var me := agent as Node3D
		var m: Node = Mover.of(me)
		var now := Time.get_ticks_msec()
		var W: Dictionary = pair["W"]
		if now < int(pair["until"]):
			return RUNNING  # a breather: both stand
		if bool(pair.get("resting", false)):
			pair["resting"] = false
			for kd in kids:
				People.play(kd, "Running")
		var root: Node3D = pair["root"]
		if me == kids[0]:
			if pair["goal"] == Vector3.INF or (not m.moving() and _asked == pair["goal"]):
				pair["goal"] = _open_cobble(pair)
				if pair["goal"] == Vector3.INF:
					pair["until"] = now + 1000  # no open cobble just now: a breather, then look again
					return RUNNING
			if _asked != pair["goal"]:
				_asked = pair["goal"]
				m.go(root.to_global(pair["goal"]))
			return RUNNING
		if now < int(pair.get("count", 0)):
			return RUNNING  # the chaser counts while the runner makes off
		var runner: Node3D = kids[0]
		if me.global_position.distance_to(runner.global_position) <= float(W.get("catch", 0.06)):
			m.stop()
			Mover.of(runner).stop()
			pair["kids"] = [me, runner]  # caught: now the other one runs
			pair["goal"] = Vector3.INF
			pair["from"] = runner  # he makes off away from the one who caught him
			pair["count"] = now + int(float(W.get("count", 1.0)) * 1000.0)  # the new chaser counts a beat while the other runs
			if randf() < float(W.get("stop", 0.5)):
				var span: Array = W.get("rest", [2.0, 4.0])
				pair["until"] = now + int(randf_range(float(span[0]), float(span[1])) * 1000.0)
				pair["count"] = int(pair["until"]) + int(float(W.get("count", 1.0)) * 1000.0)
				pair["resting"] = true
				for kd in kids:
					People.play(kd, ["Laughing", "Crouch_Idle", "Pointing_Forward", "Waving"][randi() % 4])
			return RUNNING
		var short := runner.global_position + (me.global_position - runner.global_position).normalized() * float(W.get("catch", 0.1)) * 0.9
		if _asked == Vector3.INF or _asked.distance_to(short) > 0.05 or not m.moving():
			_asked = short  # a hand's reach short of him: a catch, not one child inside the other
			m.go(_asked)
		return RUNNING

	static func W_clear(pair: Dictionary) -> float:
		return float((pair["W"] as Dictionary).get("clear", 0.2))

	## Whether anyone (a person, a dog, another child) is within `r` of a town-local point now, or running for it.
	static func _someone_at(root: Node3D, p: Vector3, r: float) -> bool:
		var life: Node3D = root.get_node_or_null("Life")
		if life == null:
			return false
		var w := root.to_global(p)
		for n in life.get_children():
			if n is Node3D and (n.has_meta("role") or n.has_meta("town_dog")) and Vector2((n as Node3D).position.x - p.x, (n as Node3D).position.z - p.z).length() < r:
				return true
			if n is Node3D and n.has_meta("step_to") and Vector2((n.get_meta("step_to") as Vector3).x - w.x, (n.get_meta("step_to") as Vector3).z - w.z).length() < r:
				return true  # where a posted person is stepping to is theirs (npc_mind Step)
		return false

	## A point on the square's open cobble within the chase's reach (off every stall, house and plinth, and nobody
	## standing there), the furthest of a few from the one he runs from.
	static func _open_cobble(pair: Dictionary) -> Vector3:
		var r := float(pair["r"])
		var root: Node3D = pair["root"]
		var away: Variant = pair.get("from", null)
		var from := root.to_local((away as Node3D).global_position) if away is Node3D and is_instance_valid(away) else Vector3.INF
		var best := Vector3.INF  # nowhere open at all: he stays put a moment
		var far := -1.0
		for t in 12:
			var a := randf() * TAU
			var p := Vector3(cos(a), 0, sin(a)) * r * randf_range(0.3, 1.0)
			if not pair["tl"].open_ground(root, p):
				continue
			# Clear cobble first; failing any, the furthest open spot from the one he runs from (never freeze by him).
			var d := (p.distance_to(from) if from != Vector3.INF else randf()) + (10.0 if not _someone_at(root, p, W_clear(pair)) else 0.0)
			if d > far:
				far = d
				best = p
		return best


## The head of a levy's file marching out: he walks the road out and is gone past its end (his file follows him).
class MarchOut extends BTAction:
	var _i := -1

	func _tick(_delta: float) -> Status:
		var me := agent as Node3D
		var m: Node = Mover.of(me)
		if m.moving():
			return RUNNING
		var route: Array = blackboard.get_var(&"route", [], false)
		_i += 1
		if _i >= route.size():
			me.queue_free()  # past the road's end: on his way to the host
			return SUCCESS
		m.go(route[_i])
		return RUNNING
