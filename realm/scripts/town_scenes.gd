extends Node3D
## Town life's director: the one reducer of docs/TOWN_LIFE.md. Every person and beast in a town's scenes is cast
## here from the rows of realm/data/town_scenes.json; nothing else places them.
## - The town's standing scenes (`standing` rows): staged whenever the town is dressed (town_life.gd update, the
##   town's Life rebuilt when its state turns), for as long as their needs hold: the riot at the keep's door and
##   the watch holding it, the hungry camped at the edge, the stall keepers, the crown's market day, the feast's
##   ring round the bonfire and its tables, the muster and the levy marching out, the gallows' onlookers, the dole,
##   the funeral round the square, and the square's own life (the crier, beggars, the watch's beat, dogs, children
##   chasing, gossip, guards at the forge and the castle, carriers, the market cart, a gardener in the yards).
##   Each row's dress is a class of its own (town_dress/, registered in town_scenes.json dressings): it lays the
##   props with town_life.gd's hands and says where they stand (anchors).
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
const Awareness := preload("res://scripts/awareness.gd")  # a mind's part handed it through the store (assign)
const SEEN := Vector3(-0.5736, 0, -0.8192)  # the side of a square the town camera looks across as it comes down
static var READ: float = Data.num("people", "readable", 1.0)  # drawn larger: they cover ground as their legs do
## Every var a town mind's tasks read, with its default: LimboAI's own declaration (a BlackboardPlan, mind_plan()),
## carried by every tree the director makes, so no read can miss and none carries its own default
## (rounds 13-14: `Blackboard: Variable "clip" not found`). tools/mind_plan_probe.gd holds the tasks to it.
const MIND_VARS := {
	# a passing scene's person (_cast): their spot, where they face, their clips, the way off, the end call
	"slot": Vector3.ZERO, "face": Vector3.ZERO, "clips": ["Idle"], "leaving": false, "exit": Vector3.ZERO,
	"done": Callable(), "react": {}, "clip": "", "clip_left": 0.0,
	# a walker (_walker): Round's route and stops, Follow's leader, Dog's yard, Chase's pair, MarchOut's road
	"route": [], "plan": {}, "lead": true, "side": 0.0, "waits": [], "pause": [0.0, 0.0], "rest": [],
	"market": null, "town": null, "tail": 0.22, "carter": null,
	"after": null, "with": false, "gap": 0.11, "life": null, "follow": 0.12, "pair": {},
}
static var _plan: BlackboardPlan

var main: Node
var _d: Dictionary
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
var _live := {}  # town id -> Array of running passing scenes {row, key, at, ends, cast: Array[Node3D], ending}
var _seq := 0
var _no_walk := {}  # town id -> {n: passing people not cast for want of a way in, rows: {id: n}, said: msec}
var _held := {}  # town id -> {row, map}: a passing scene waiting on the town's walk map, still baking
var _marches: Array = []  # levies marching out: {root, life, every, wait, file, spacing, most, gone, pace, rng}
var _dressings := {}  # dress name -> its town_dress.gd class, one of each (_dressing)


func _init(owner: Node) -> void:
	main = owner
	name = "TownScenes"
	_d = Data.read("town_scenes")


func _ready() -> void:
	_rng.randomize()
	if main and main.awareness:
		main.awareness.stimulus.connect(_on_stimulus)
	NavigationServer2D.map_changed.connect(_on_map_changed)  # a town's walk map synced: a held scene can start


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
## its dressings (town_scenes.json dressings), then each role cast at its anchor in its form. `tl` is the town_life that dresses
## the town (its placing, people and props); `states` the town's (works.gd states, and riot in disorder).
func stage(root: Node3D, life: Node3D, c: Dictionary, states: Array, tl: Object) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c.get("id", 0)) * 7919 + 17
	var size := int(c.get("size", 1))
	var tally := {"cast": 0, "no_room": {}, "no_place": []}  # said in the play log: an empty walk map shows as a number
	# The square's census (casebook, Living towns: 'The crowd is the census'): as many on its open setts as its size
	# holds at a lived-in square's density (towns.json square.targets.per_100m2: 01-town's, and round 11's Kingsmere),
	# shared among the roles that stand there by their `census` weights; worked out once the stalls stand (_census).
	var census := {"budget": -1, "left": 0, "weights": 0.0, "cast": 0, "m2": 0.0}
	for row in _d.get("standing", []):
		if _meets(row, root, states, size):
			for role in row.get("roles", []):
				var w: Variant = role.get("census", 0.0)
				if not (w is String):
					census["weights"] = float(census["weights"]) + float(w)
	for row in _d.get("standing", []):
		if not _meets(row, root, states, size):
			continue
		var anchors: Dictionary = (life.get_meta("anchors", {}) as Dictionary).duplicate()  # where town_life's own dressing stands
		for dress in row.get("dress", []):
			var d = _dressing(String(dress), tl)
			if d != null:
				anchors.merge(d.dress(root, life, row, rng), true)
		var k := {"root": root, "life": life, "tl": tl, "states": states, "size": size, "rng": rng, "row": row, "lead": null, "cast": [], "tally": tally, "census": census}
		for role in row.get("roles", []):
			_stage_role(k, role, anchors)
		if row.has("march") and _meets(row["march"], root, states, size):
			_begin_march(root, life, row["march"], rng)
	root.set_meta("square_cast", int(census["cast"]))  # the census cast standing there: the villagers' room is what's left (village_slots square_full)
	print("CHECK town scenes: %s: %d cast; no room for %s; rows whose place wasn't there: %s; square census %d for %.0f m2 of open setts, %d cast to it" % [String(root.get_meta("title", root.name)), int(tally["cast"]), str(tally["no_room"]), str(tally["no_place"]), int(census["budget"]), float(census["m2"]), int(census["cast"])])


## The dressing a standing row names (town_scenes.json dressings: its class, extends town_dress.gd), one of each
## kept; null, with an error, for a name with no row.
func _dressing(name: String, tl: Object):
	if not _dressings.has(name):
		var path := String((_d.get("dressings", {}) as Dictionary).get(name, ""))
		if path == "":
			push_error("town_scenes: no dressing '%s' in town_scenes.json dressings" % name)
			return null
		_dressings[name] = load(path).new(tl)
	var d = _dressings[name]
	d.tl = tl
	return d


## How many of a role the square's census lets stand, or -1 for no cap: a role outside the census (a riot's press,
## a feast's ring: the state's own crowd), or one the census takes whole (`"census": "all"`: a keeper at every stall).
## A weighted role takes its weight's share of what's still left when its turn comes, so whatever one couldn't place
## (fewer stalls, no room) goes to those after it.
func _census_cap(k: Dictionary, role: Dictionary) -> int:
	var c: Dictionary = k["census"]
	var w: Variant = role.get("census", 0.0)
	if int(c["budget"]) == -1 and (w is String or float(w) > 0.0):
		c["m2"] = open_setts_m2(k["root"])
		# No paved square read (a town without setts, a made-up probe town): no census, each row's own count stands.
		var b := square_budget(k["root"])
		c["budget"] = b if b >= 0 else -2
		c["left"] = int(c["budget"]) - int(c["cast"])
	if w is String or float(w) <= 0.0 or int(c["budget"]) == -2:
		return -1
	var share := float(c["left"]) * float(w) / maxf(float(c["weights"]), 0.001)
	c["weights"] = float(c["weights"]) - float(w)
	var cap := maxi(0, int(round(share)))
	if bool(role.get("pairs", false)) or String(role.get("does", "")) == "beat":
		cap = maxi(2, cap) / 2 * 2 if share >= 1.5 else 0  # by twos
	var fewest := _knot_fewest(role)
	if fewest > 1 and cap < fewest:
		cap = fewest if share >= fewest * 0.5 else 0  # a knot is whole: never one gossip talking to nobody
	cap = mini(cap, maxi(0, int(c["left"])))
	return 0 if fewest > 1 and cap < fewest else cap


## The fewest in one of a role's knots (knot: n, or [fewest, most]); 0 for a role that stands in no knots.
static func _knot_fewest(role: Dictionary) -> int:
	var kn: Variant = role.get("knot", 0)
	return int(kn[0]) if kn is Array else int(kn)


## A body the census counts: marked, and the count kept for the play log.
func _counted(k: Dictionary, role: Dictionary, body: Node3D) -> void:
	var w: Variant = role.get("census", 0.0)
	if w is String or float(w) > 0.0:
		body.set_meta("census", true)
		k["census"]["cast"] = int(k["census"]["cast"]) + 1
		k["census"]["left"] = int(k["census"]["left"]) - 1


## The square's open setts in square metres: metre cells inside its paved disc (towns.gd's first `paved` entry) under
## nothing that stands on it (nav_ground's outlines centred on the setts: stalls, the well, the statue). The measure
## squarelife (autoplay.gd) reads the square by.
## How many stand on the town's square at once, everyone counted (the scene cast's census here and the villagers bound
## there, village_slots square_cap): its open setts at a lived-in square's density, towns.json
## square.targets.per_100m2 (01-town's). The one owner of that number (tools/square_crowd_probe.gd); worked out once a
## town root stands with its stalls, and kept on the root (meta "square_budget"). -1: no paved square.
static func square_budget(root: Node3D) -> int:
	if root.has_meta("square_budget"):
		return int(root.get_meta("square_budget"))
	var m2 := open_setts_m2(root)
	var b := int(round(m2 / 100.0 * Data.num("towns", "square.targets.per_100m2", 6.0))) if m2 > 0.0 else -1
	root.set_meta("square_budget", b)
	return b


static func open_setts_m2(root: Node3D) -> float:
	var um: float = load("res://scripts/towns.gd").S
	var pr := 0.0
	for pv in root.get_meta("paved", []):
		if (pv[0] as Vector2) == Vector2.ZERO and (pv[1] as Vector2) == Vector2.ZERO:
			pr = float(pv[2])
			break
	if pr <= 0.0:
		return 0.0
	var feats: Array = []
	for fp in load("res://scripts/town_nav.gd").footprints(root):
		var poly := fp as PackedVector2Array
		if poly.size() < 3:
			continue
		var mid := Vector2.ZERO
		for v in poly:
			mid += v
		if (mid / poly.size()).length() <= pr:
			feats.append(poly)
	var n := int(ceil(pr / um))
	var open := 0
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var cq := Vector2(gx, gz) * um
			if cq.length() > pr:
				continue
			if not feats.any(func(poly): return Geometry2D.is_point_in_polygon(cq, poly)):
				open += 1
	return float(open)


## Whether a row's conditions hold: any of `needs`, none of `not`, the square's own life (`square`: a market
## town big enough, or the crown's seat, and none of director.square_off: a riot, a raid), the crown's seat (`crown`).
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
		if (_d.get("director", {}).get("square_off", ["riot"]) as Array).any(func(s): return s in states) or not bool(Data.value("crowd", "on", true)):
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


## Where a role stands: one its dressing set down, or a town_scenes.json `anchors` row (a town's place, a working
## building's front, or the square's heart, out along the way it faces). An anchor is {at (town-local), dir (the
## way it faces), side, r, points: [{at, dir}] for each of many (stalls, seats, carts, gardens)}.
func _anchor(name: String, k: Dictionary, anchors: Dictionary) -> Dictionary:
	if anchors.has(name):
		return anchors[name]
	var root: Node3D = k["root"]
	var row: Dictionary = k["row"]
	var r := float(root.get_meta("square_r", 1.0))
	var d: Dictionary = (_d.get("anchors", {}) as Dictionary).get(name, {})
	if d.is_empty():
		return {}
	match String(d.get("by", "")):  # the two worked out from the town's shape, not a place
		"castle":
			return _castle(root, r, row)
		"stops":
			return _stops(k)
		"open":
			return _open(k, d)
	var dir: Vector3 = Basis(Vector3.UP, float(d.get("turn", 0.0))) * SEEN
	var at := Vector3.ZERO
	var from := String(d.get("at", "heart"))
	if from.begins_with("place:"):
		var places: Dictionary = root.get_meta("places", {})
		var key := from.substr(6)
		if places.has(key):
			at = places[key]
		elif d.has("or"):
			at = Vector3(float(d["or"][0]), float(d["or"][1]), float(d["or"][2]))
		else:
			return {}
	elif from.begins_with("works:"):
		var wk: Dictionary = root.get_meta("works", {})
		var key := from.substr(6)
		if not wk.has(key):
			return {}
		at = wk[key]["at"]
		dir = Basis(Vector3.UP, float(wk[key].get("yaw", 0.0))) * Vector3(0, 0, 1)  # out of its front
	var out: Variant = d.get("out", 0.0)
	if out is Dictionary:
		out = float(row.get(String(out["row"]), out["or"])) if (out as Dictionary).has("row") else Data.num(String(out["data"][0]), String(out["data"][1]), float(out["data"][2]))
	var got := {"at": at + dir * float(out), "dir": dir}
	if d.has("r"):
		got["r"] = r if d["r"] is String else float(d["r"])  # "square": the square's own radius
	return got


## The square's own open ground (look audit on step 6: a bare plaza ringed by stalls; GoC's square life, Kingsmere:
## the largest stretch nobody stands within 2 m of 400-670 m2 against 01-town's 30, every standing role anchored to a
## stall, the well, a cart or the crier): a spot on its open setts, the emptiest first (farthest from anything that
## stands on them: town_nav footprints), each call the next, spots at least `apart` metres from each other
## (town_scenes.json anchors.<name>: by "open", apart, within: the share of the square's radius they keep inside).
## Worked out once a stage (k["open"]); facing the heart. {} when the square has no open setts left.
func _open(k: Dictionary, d: Dictionary) -> Dictionary:
	if not k.has("open"):
		if bool(d.get("cover", false)):
			# The coverage rule: one standing person a spot, laid farthest-first from everyone already standing, inside
			# what the square's census budget has left (cover_people).
			var life: Node3D = k["life"]
			var seeds: Array = Array(life.get_meta("standing", PackedVector2Array())) if life else []
			var c: Dictionary = k["census"]
			var b := square_budget(k["root"])
			var left := maxi(0, b - int(c.get("cast", 0))) if b >= 0 else 0
			# Never more than towns.json square.cover_most (Mac: keep round 11's open court; a handful stand in the open).
			left = mini(left, int(Data.num("towns", "square.cover_most", 8)))
			k["open"] = cover_people(k["root"], seeds, left, float(d.get("within", 0.85)))
		else:
			k["open"] = open_spots(k["root"], float(d.get("apart", 4.0)), float(d.get("within", 0.85)))
		k["open_next"] = 0
	var spots: Array = k["open"]
	if spots.is_empty():
		return {}
	var i := int(k["open_next"]) % spots.size()
	k["open_next"] = int(k["open_next"]) + 1
	var at: Vector2 = spots[i]
	var dir := Vector3(-at.x, 0, -at.y).normalized() if at.length() > 0.001 else SEEN
	var rest: Array = []
	for j in spots.size():
		var q: Vector2 = spots[(i + j) % spots.size()]
		rest.append(Vector3(q.x, 0, q.y))
	return {"at": Vector3(at.x, 0, at.y), "dir": dir, "spots": rest}


## The coverage rule (supervisor, 12 Nov; casebook, "The market is a place"): no stretch of the square's open setts
## nobody stands within near_m of may be bigger than towns.json square.cover_share of the open setts (01-town's: its
## largest empty patch, 30 m2, over its about 470 m2). Measured as autoplay squarelife measures it: 1 m cells of the
## open setts (off every footprint and lane, within `within` of the radius), a cell free when nobody is within near_m,
## free cells joined side to side. Standing people are laid one by one, each on the cell farthest from everyone already
## standing (`seeds`, town-local), until the largest free stretch is under the limit or `budget` people are laid.
## Returns their spots, town-local; tools/square_open_probe.gd asserts it on a staged square.
static func cover_people(root: Node3D, seeds: Array, budget: int, within: float) -> Array:
	var um: float = load("res://scripts/towns.gd").S
	var TL: Script = load("res://scripts/town_life.gd")
	var pr := 0.0
	for pv in root.get_meta("paved", []):
		if (pv[0] as Vector2) == Vector2.ZERO and (pv[1] as Vector2) == Vector2.ZERO:
			pr = float(pv[2])
			break
	if pr <= 0.0 or budget <= 0:
		return []
	var feats: Array = []
	for fp in load("res://scripts/town_nav.gd").footprints(root):
		if (fp as PackedVector2Array).size() >= 3:
			feats.append(fp)
	var near := float(Data.num("towns", "square.near_m", 2.0)) * um
	var cells: Array = []  # Vector2i
	var n := int(ceil(pr / um))
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var q := Vector2(gx, gz) * um
			if q.length() > pr * within:
				continue
			if feats.any(func(poly): return Geometry2D.is_point_in_polygon(q, poly)):
				continue
			if TL.on_lane(root, root.global_position + Vector3(q.x, 0, q.y)):
				continue
			cells.append(Vector2i(gx, gz))
	if cells.is_empty():
		return []
	var limit := float(Data.num("towns", "square.cover_share", 0.064)) * cells.size()  # m2: a cell is a square metre
	var index := {}
	for ci in cells.size():
		index[cells[ci]] = ci
	var dist: Array = []
	dist.resize(cells.size())
	dist.fill(INF)
	var lay := func(q: Vector2) -> void:
		for ci in cells.size():
			dist[ci] = minf(float(dist[ci]), q.distance_to(Vector2(cells[ci]) * um))
	for sd in seeds:
		lay.call(sd as Vector2)
	var largest := func() -> int:
		var seen := {}
		var most := 0
		for ci in cells.size():
			if seen.has(ci) or float(dist[ci]) <= near:
				continue
			var size := 0
			var todo: Array = [ci]
			seen[ci] = true
			while not todo.is_empty():
				var a: int = todo.pop_back()
				size += 1
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var b = index.get(cells[a] + d, -1)
					if b >= 0 and not seen.has(b) and float(dist[b]) > near:
						seen[b] = true
						todo.append(b)
			most = maxi(most, size)
		return most
	var spots: Array = []
	while spots.size() < budget and largest.call() > limit:
		var bi := 0
		for ci in cells.size():
			if float(dist[ci]) > float(dist[bi]):
				bi = ci
		var q := Vector2(cells[bi]) * um
		spots.append(q)
		lay.call(q)
	return spots


## The open setts' spots, town-local, the emptiest first: grid points on the paved square (within `within` of its
## radius) outside every footprint, chosen one by one farthest from anything standing and from the spots already
## chosen (farthest-point sampling), none nearer than `apart_m` metres to another or to a footprint. Static, so a probe
## checks the same spots (tools/square_open_probe.gd).
static func open_spots(root: Node3D, apart_m: float, within: float) -> Array:
	var TL: Script = load("res://scripts/town_life.gd")
	var um: float = load("res://scripts/towns.gd").S
	var pr := 0.0
	for pv in root.get_meta("paved", []):
		if (pv[0] as Vector2) == Vector2.ZERO and (pv[1] as Vector2) == Vector2.ZERO:
			pr = float(pv[2])
			break
	if pr <= 0.0:
		return []
	var feats: Array = []
	for fp in load("res://scripts/town_nav.gd").footprints(root):
		var poly := fp as PackedVector2Array
		if poly.size() >= 3:
			feats.append(poly)
	var far := func(q: Vector2) -> float:
		var best := INF
		for poly in feats:
			if Geometry2D.is_point_in_polygon(q, poly):
				return -1.0
			for i in (poly as PackedVector2Array).size():
				var e := Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])
				best = minf(best, q.distance_to(e))
		return best
	var step := um  # a metre
	var n := int(ceil(pr / step))
	var cells: Array = []
	for gx in range(-n, n + 1):
		for gz in range(-n, n + 1):
			var q := Vector2(gx, gz) * step
			if q.length() > pr * within:
				continue
			var f: float = far.call(q)
			# Nobody stands on a road's lane or at the heart (town_life on_lane: the travellers' ground); a spot there
			# would only come back "no room" (GoC's headless Kingsmere: 16 of the gossip's knots).
			if f >= 0.0 and not TL.on_lane(root, root.global_position + Vector3(q.x, 0, q.y)):
				cells.append([f, q])
	# Farthest-point sampling: each next spot the cell farthest from anything standing and from the spots already
	# chosen, so the knots spread over the bare ground instead of all keeping to its emptiest edge (GoC's headless
	# Kingsmere: ranked by footprints alone, every knot stood on the square's west rim, 14-18 m out).
	var spots: Array = []
	var apart := apart_m * um
	var gap: Array = cells.map(func(c): return float(c[0]))  # each cell's distance to the nearest standing thing or spot
	while true:
		var bi := -1
		var bd := apart
		for i in cells.size():
			if float(gap[i]) >= bd:
				bd = float(gap[i])
				bi = i
		if bi < 0:
			break
		var q: Vector2 = cells[bi][1]
		spots.append(q)
		for i in cells.size():
			gap[i] = minf(float(gap[i]), q.distance_to(cells[i][1]))
	return spots


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
	# And the open middle (open_stops: that many of the square's open spots), so the errands cross the bare setts
	# rather than keep to the stalls' ring (supervisor: walkers on errands that cross the open middle).
	var mid := int((k["row"] as Dictionary).get("open_stops", 0))
	if mid > 0:
		for q2 in open_spots(root, float((k["row"] as Dictionary).get("open_apart", 6.0)), 0.6).slice(0, mid):
			pts.append(Vector3((q2 as Vector2).x, 0, (q2 as Vector2).y))
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
	# And the alleys between the square's houses (row alleys; art target 01-town: people walking the lanes between
	# the houses), each a street an errand goes up and back.
	if bool((k["row"] as Dictionary).get("alleys", false)):
		for q in root.get_meta("alleys", []):
			streets.append(Vector3((q as Vector2).x, 0, (q as Vector2).y))
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
					out.append({"at": mid + Vector3(cos(b), 0, sin(b)) * float(role.get("apart", 0.085)), "face": mid, "knot": kn})
		"knots_open":
			# Knots of neighbours, one on each of the square's open spots, the emptiest first (anchor by "open"): the bare
			# middle of the setts, not an arc that may fall on the stalls' ring.
			var spots: Array = a.get("spots", [at])
			var size2: Array = role.get("knot", [2, 3])
			for kn in n:
				var mid: Vector3 = spots[kn % spots.size()]
				var m := rng.randi_range(int(size2[0]), int(size2[1]))
				for jj in m:
					var b := TAU * jj / m + rng.randf_range(-0.3, 0.3)
					out.append({"at": mid + Vector3(cos(b), 0, sin(b)) * float(role.get("apart", 0.085)), "face": mid, "knot": kn})
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


## The one BlackboardPlan of every town mind (MIND_VARS), made once; a var set as a mind is made keeps its value.
static func mind_plan() -> BlackboardPlan:
	if _plan == null:
		_plan = BlackboardPlan.new()
		for n in MIND_VARS:
			_plan.set("var/%s/name" % n, StringName(n))  # a plan's vars as its resource stores them (no add_var in GDScript)
			_plan.set("var/%s/type" % n, typeof(MIND_VARS[n]))
			_plan.set("var/%s/value" % n, MIND_VARS[n])
	return _plan


## The days gone by on the view's clock (villagers.gd counts each dawn): the week the market days fall in.
static var day := 0


## Whether today is `town`'s market day (town_scenes.json week: days in a week; each town keeps its own day of it,
## by its id, so some town nearby is always at market; Manor Lords' and Banished's market days).
static func market_day(town: int) -> bool:
	var w := int(Data.value("town_scenes", "week.days", 7))
	return w > 0 and town >= 0 and posmod(day, w) == posmod(town, w)


## The part of the day at `hour` (town_scenes.json `day` rows), for someone whose own clock runs `early` hours
## ahead (an early riser, a late one). The director owns the day; villagers and minds ask it here.
static func block(hour: float, early := 0.0) -> String:
	var h := fposmod(hour + early, 24.0)
	for r in Data.value("town_scenes", "day", []):
		var from := float(r["from"])
		var to := float(r["to"])
		if (h >= from and h < to) if from <= to else (h >= from or h < to):
			return String(r["part"])
	return "night"


## The working day's parts (the `day` rows marked day): the ones a town's mood bends (feast, riot, hunger).
static func daytime() -> Array:
	return Data.value("town_scenes", "day", []).filter(func(r): return r.get("day", false)).map(func(r): return String(r["part"]))


## How much a villager's plan (the bridge minds': where they mean to be) leans their pick to an activity that walks
## to `place` (town_scenes.json plan): its bend when the plan's where names that place, else 1.
static func plan_bend(where: String, place: String) -> float:
	if where == "" or place == "":
		return 1.0
	var p: Dictionary = Data.value("town_scenes", "plan", {})
	var w := where.to_lower()
	var places: Dictionary = p.get("places", {})
	for key in places:
		if w.contains(key) and place in places[key]:
			return float(p.get("bend", 1.0))
	return 1.0


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
	if bool(role.get("cover", false)):
		n = (a.get("spots", []) as Array).size()  # the coverage rule: a knot on every spot it took to cover the setts
	if bool(role.get("pairs", false)):
		n *= 2
	var cap := _census_cap(k, role)
	if cap >= 0 and String(role.get("form", "")) != "each":
		n = mini(n, cap)
	var spots := _spots(role, a, n, k)
	if cap >= 0 and String(role.get("form", "")) == "each" and spots.size() > cap:
		# More stalls (seats, carts) than the census stands people at: which of them get someone, by chance.
		var keep: Array = []
		var idx := range(spots.size())
		for j in range(idx.size() - 1, 0, -1):
			var r := k["rng"].randi() % (j + 1) as int
			var t: Variant = idx[j]
			idx[j] = idx[r]
			idx[r] = t
		for j in idx.slice(0, cap):
			keep.append(spots[j])
		spots = keep
	elif cap >= 0 and spots.size() > cap:
		spots = spots.slice(0, cap)  # a form of knots places several to each: the census counts people, not knots
		var last := spots.filter(func(sp): return sp.has("knot") and sp["knot"] == spots[-1].get("knot", -1)) if not spots.is_empty() else []
		if not last.is_empty() and last.size() < _knot_fewest(role):
			spots = spots.slice(0, spots.size() - last.size())  # the knot cut short goes whole: nobody left talking to nobody
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
			if body:
				body.add_to_group("bodies")  # stands on the ground like anyone: the stopping rule (npc_mind Step.room) sees it
		else:
			var tint := Color.WHITE
			var tv: Variant = role.get("tint", null)
			if tv is String and tv == "house":
				tint = tl.house_colour(root)
			elif tv is Array:
				tint = Data.colour(tv, Color.WHITE)
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
		_counted(k, role, body)
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
					if body.has_meta("census"):
						k["census"]["cast"] = int(k["census"]["cast"]) - 1  # not there after all: his place goes back
						k["census"]["left"] = int(k["census"]["left"]) + 1
					body.queue_free()  # no one found room to chase him: he isn't there
			"live":
				Animals.live(body, String(role.get("beast", "")), rng)  # its own idle life (a hen pecking about)
			"procession", "leave":
				pass
	if does == "procession":
		_procession(k, role, group, a)
	elif does == "leave":
		_leave(k, role, group, a)


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
	bt.blackboard_plan = mind_plan()
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(body)
	player.behavior_tree = bt
	Awareness.assign(player, vars)  # its starting state, through the store
	body.add_child(player)


## The beat, the errands and the cart: walkers going round places of the square in turn.
func _stage_walkers(k: Dictionary, role: Dictionary, a: Dictionary, does: String) -> void:
	var root: Node3D = k["root"]
	var life: Node3D = k["life"]
	var tl: Object = k["tl"]
	var rng: RandomNumberGenerator = k["rng"]
	var W: Dictionary = role.get("walk", {})
	var n := _count(role.get("n", 1), k)
	var cap := _census_cap(k, role)
	if cap >= 0:
		n = mini(n, cap / 2 if does == "beat" else cap)  # a beat is walked by a pair
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
					_counted(k, role, g)
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
				_counted(k, role, man)
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
## up an alley to the yards and back from the market now and then (walk.alleys), waiting at the market (its tail a
## porter's slot meanwhile), at the yards' end of an alley and at the streets' ends.
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
	# Drawn up at its street's end where nobody stands (the watch's beat can start at that same mouth).
	var start := root.to_local(Kit.free_near(life, Blackboard.new(), root.to_global(ends[0]), null, float(W.get("room", 0.2))))
	rig.position = Vector3(start.x, tl.ground_at(root, start), start.z)
	life.add_child(rig)
	rig.add_to_group("bodies")  # the stopping rule (npc_mind Step.room) keeps people out of its way
	rig.set_meta("room", float(W.get("room", 0.2)))  # and out of its standing place, wherever it draws up
	rig.set_meta("scene", String(k["row"]["id"]))
	rig.set_meta("cart", true)
	var mkt: Vector3 = (root.get_meta("places", {}) as Dictionary).get("market", Vector3.ZERO) * float(W.get("market_in", 0.7))
	var out_b: Array = (lanes[1] as Array).duplicate()
	var in_b: Array = out_b.duplicate()
	in_b.reverse()
	var out_a: Array = (lanes[0] as Array).duplicate()
	var in_a: Array = out_a.duplicate()
	in_a.reverse()
	# Up the alleys between the square's houses to the yards and back to the market (walk.alleys: how many a round;
	# art target 01-town: a carter on the lanes between the yards), the nearest the market first, along the alley's
	# own line from its mouth at the house fronts; it waits at the yard end to unload as at the market.
	var yard_ends: Array = []
	var trips: Array = []
	var front := float(root.get_meta("square_r", r)) + 0.25 - 0.1  # where an alley leaves the square (town_layout _ring_alley)
	var alleys: Array = (root.get_meta("alleys", []) as Array).duplicate()
	var m2 := Vector2(mkt.x, mkt.z)
	alleys.sort_custom(func(a, b): return (a as Vector2).normalized().distance_to(m2.normalized()) < (b as Vector2).normalized().distance_to(m2.normalized()))
	for q in alleys.slice(0, int(W.get("alleys", 0))):
		var far := Vector3((q as Vector2).x, 0, (q as Vector2).y)
		var mouth := far.normalized() * front
		yard_ends.append(far)
		trips.append([mouth, far, mouth, mkt])
	var first: Array = trips[0] if trips.size() > 0 else []
	var second: Array = trips[1] if trips.size() > 1 else []
	var route: Array = in_a + [mkt] + first + out_b + [ends[1]] + in_b + [mkt] + second + out_a + [ends[0]]
	var waits: Array = route.map(func(q): return q == mkt or q == ends[0] or q == ends[1] or q in yard_ends)
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


## A household leaving the town (the leaving row; bridge households.js): the whole file across the row's roles, the
## first pushing the barrow with their goods (Wheelbarrow, its barrow weapons.gd's), the rest behind in file, out
## from their door along the road (the leaving dressing's route) and gone at its end, as the levy marches out.
func _leave(k: Dictionary, role: Dictionary, group: Array, a: Dictionary) -> void:
	var route: Array = a.get("route", [])
	if group.is_empty() or route.is_empty():
		return
	var root: Node3D = k["root"]
	var W: Dictionary = (k["row"] as Dictionary).get("walk", {})
	var file: Array = (k.get("file", []) as Array)
	file.append_array(group)
	k["file"] = file
	if role != (k["row"]["roles"] as Array)[-1]:
		return
	var pace := float(W.get("pace", 0.12))
	var spacing := float(W.get("spacing", 0.12))
	var push := "Wheelbarrow" if preload("res://scripts/weapons.gd").can_play("Wheelbarrow") else "Carrying"
	var behind: Vector3 = ((route[0] as Vector3) - (route[1 % route.size()] as Vector3)).normalized()
	for i in file.size():
		var w: Node3D = file[i]
		var at: Vector3 = (route[0] as Vector3) + behind * spacing * i  # in file at their door, the barrow first
		w.position = Vector3(at.x, (k["tl"] as Object).ground_at(root, at), at.z)
		var mind := w.get_node_or_null("Mind")
		if mind:
			w.remove_child(mind)
			mind.queue_free()  # they go now
		w.set_meta("leaving", true)
		if i == 0:
			_walker(w, MarchOut.new(), {"route": route.map(func(q): return root.to_global(q))}, push, pace)
		else:
			_walker(w, Follow.new(), {"after": file[i - 1], "gap": spacing, "with": true}, "Carrying" if i == 1 else "Walk", pace * 1.2)


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
	while active < cap and tries > 0 and not _held.has(id):  # a scene held for the walk map comes first
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
	_publish(id)


## The store learns a town's running scenes and the places they claim (the mirror's town scope).
func _publish(id: int) -> void:
	var running: Array = _live.get(id, [])
	var bb: Blackboard = main.awareness.town(id)
	bb.set_var(&"scenes", running.map(func(s): return {"id": s["row"]["id"], "at": s["at"], "ending": s["ending"]}))
	bb.set_var(&"claims", running.filter(func(s): return not bool(s["ending"])).map(func(s): return s["key"]))


## The town's walk map, if it is still baking (Recast on a worker thread, 0.1-0.2 s after it is asked for); else none.
func _baking(id: int, root: Node3D) -> RID:
	var nav: Object = main.scenes.nav
	if not nav.has_method("map_for"):
		return RID()
	var map: RID = nav.map_for(id, root)
	return map if map.is_valid() and not nav.ready(map) else RID()


## A walk map synced: the scene held for it starts now (town_nav ready: its bake landed and the map has synced since).
func _on_map_changed(map: RID) -> void:
	for id in _held.keys():
		var h: Dictionary = _held[id]
		if h["map"] != map or not main.scenes.nav.ready(map):
			continue
		_held.erase(id)
		var t: Dictionary = main.towns.towns.get(id, {})
		var root: Node3D = t.get("node") if not t.is_empty() else null
		if root == null or not is_instance_valid(root):
			continue
		var s := _start(id, root, h["row"])
		if not s.is_empty():
			var running: Array = _live.get(id, [])
			running.append(s)
			_live[id] = running
			_publish(id)


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
	var enter: Array = _d.get("director", {}).get("enter", [1.2, 2.0])
	var map := _baking(id, root)
	if map.is_valid():
		_held[id] = {"row": row, "map": map}  # its people walk in once the map can route them (_on_map_changed)
		return {}
	_seq += 1
	var s := {"row": row, "key": "%s:%d" % [row["id"], _seq], "at": at, "cast": [], "ending": false,
		"ends": Time.get_ticks_msec() + int(_rng.randf_range(float(last[0]), float(last[1])) * 1000.0), "town": id}
	var axis := _rng.randf() * TAU
	var first := Vector3.INF
	for role in row.get("roles", []):
		var n: Array = role.get("n", [1, 1])
		var count := _rng.randi_range(int(n[0]), int(n[1]))
		for i in count:
			var want := _passing_spot(at, role, i, count, axis)
			var slot: Vector3 = main.scenes.stand(want)
			var ea := _rng.randf() * TAU
			var asked := slot + Vector3(cos(ea), 0, sin(ea)) * _rng.randf_range(float(enter[0]), float(enter[1]))
			var door: Vector3 = main.scenes.stand(asked)
			var reach := float(_d.get("director", {}).get("stand_reach", 0.4))
			# Stood where asked, a walk in from somewhere else: on a walk map that answers nothing, every stand is the town's
			# middle (town_nav closest() on no polygons: (0, 0)) and both ends are that one point, which waits() lets by.
			var stood := _flat(slot - want) <= reach and _flat(door - asked) <= reach and _flat(door - slot) > 0.05
			if not stood or main.scenes.nav.waits(main.towns, door, slot):
				_unwalkable(id, root, String(row["id"]))  # a baked map with no way in (a baking one held the scene above)
				continue
			var face := at
			if bool(role.get("face", false)) and first != Vector3.INF:
				face = first
			var p := _cast(s, role, slot, face, door)
			if p and first == Vector3.INF:
				first = slot
	if (s["cast"] as Array).is_empty():
		return {}  # nobody could walk in: the scene isn't playing
	return s


## Distance on the ground, height aside.
static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


## A passing person the director didn't cast: the town's walk map, baked, gives no way from their way in to their
## spot (baked to nothing, as Kingsmere's was in round 13; town_nav.waits). Said in the play log as it
## starts and every `director.say_every` seconds while it lasts, with the count, so an empty map shows.
func _unwalkable(id: int, root: Node3D, row_id: String) -> void:
	var w: Dictionary = _no_walk.get(id, {"n": 0, "rows": {}, "said": -1})
	w["n"] = int(w["n"]) + 1
	w["rows"][row_id] = int(w["rows"].get(row_id, 0)) + 1
	var now := Time.get_ticks_msec()
	if int(w["said"]) < 0 or now - int(w["said"]) > int(float(_d.get("director", {}).get("say_every", 30.0)) * 1000.0):
		w["said"] = now
		print("CHECK town scenes: %s: no way to walk in for %d passing people so far (by row %s): its walk map, baked, gives no route; nobody cast there" % [String(root.get_meta("title", root.name)), int(w["n"]), str(w["rows"])])
	_no_walk[id] = w


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
func _cast(s: Dictionary, role: Dictionary, spot: Vector3, face: Vector3, door: Vector3) -> Node3D:
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
	person.global_position = door
	var mover: Node = Mover.of(person)
	mover.speed = float(D.get("pace", 0.17))
	var bt := BehaviorTree.new()
	bt.root_task = _tree()
	bt.blackboard_plan = mind_plan()
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(person)
	player.behavior_tree = bt
	Awareness.assign(player, {"slot": spot, "face": face, "clips": role.get("clips", ["Idle"]), "exit": person.global_position, "done": _done.bind(s, person)})
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
			Awareness.assign(m, {"leaving": true})


## A person has walked off: the only way a cast member leaves the store.
func _done(s: Dictionary, person: Node3D) -> void:
	(s["cast"] as Array).erase(person)
	if is_instance_valid(person):
		person.queue_free()


## Out of range: the town's passing scenes are put away at once (nobody watches them go).
func _end_town(id: int) -> void:
	_held.erase(id)
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
					Awareness.assign(m, {"react": {"act": act.get("act", "gather"), "at": pos, "r": float(act.get("r", 1.0)), "clips": act.get("clips", ["Looking_Around"]), "until": until}})


# --- the tasks: one tree each, the person's only decider ----------------------------------------

## What every task does the same way: play clips in turn, face a point, stop only where there's room.
class Kit:
	static var CLEAR: float = Data.num("town_scenes", "director.clear", 0.08)  # world units: two bodies' radii and a hand

	## The nearest spot to `want` (world) a walker may stop on: room there by the one stopping rule (npc_mind
	## Step.room: nobody standing or stepping within CLEAR, `but` the one they're with) and nothing built there
	## (Step.in_the_way). Rings widening out a body at a time; none: `want`.
	static func free_near(agent: Node3D, bb: Blackboard, want: Vector3, but: Node = null, clear := -1.0) -> Vector3:
		var c := CLEAR if clear < 0.0 else clear  # a person's room, or a wider body's (the cart's)
		for ring in 6:
			var n := 1 if ring == 0 else 6 * ring
			for i in n:
				var a := TAU * i / n
				var p := want + Vector3(cos(a), 0, sin(a)) * c * 0.75 * ring
				if Mind.Step.room(agent, p, c, but) and not Mind.Step.in_the_way(agent, bb, p):
					return p
		return want

	## Goes to a spot it has spoken for (its step_to, which the stopping rule reads), so nobody else stops there.
	static func go_to(agent: Node3D, to: Vector3) -> void:
		agent.set_meta("step_to", to)
		Mover.of(agent).go(to)

	## Plays a person's clips in turn, never the same twice running, a new one every few seconds.
	static func _cycle(agent: Node, bb: Blackboard, clips: Array, delta: float) -> void:
		var left := float(bb.get_var(&"clip_left")) - delta
		if left > 0.0:
			bb.set_var(&"clip_left", left)
			return
		var last := String(bb.get_var(&"clip"))
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
		var r: Dictionary = blackboard.get_var(&"react")
		if r.is_empty():
			return FAILURE
		if Time.get_ticks_msec() > int(r.get("until", 0)):
			blackboard.set_var(&"react", {})
			return FAILURE
		return SUCCESS


class DoReact extends BTAction:
	func _enter() -> void:
		var r: Dictionary = blackboard.get_var(&"react")
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
		var r: Dictionary = blackboard.get_var(&"react")
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
		Mover.of(agent as Node3D).go(blackboard.get_var(&"slot"))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		Kit._face(agent as Node3D, blackboard.get_var(&"face"))
		blackboard.set_var(&"clip_left", 0.0)
		return SUCCESS

	func _exit() -> void:
		Mover.of(agent as Node3D).stop()


class Act extends BTAction:
	func _tick(delta: float) -> Status:
		if bool(blackboard.get_var(&"leaving")):
			return SUCCESS
		Kit._cycle(agent, blackboard, blackboard.get_var(&"clips"), delta)
		return RUNNING


class Leave extends BTAction:
	func _enter() -> void:
		Mover.of(agent as Node3D).go(blackboard.get_var(&"exit"))

	func _tick(_delta: float) -> Status:
		if Mover.of(agent as Node3D).moving():
			return RUNNING
		var done: Callable = blackboard.get_var(&"done")
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
		var plan: Dictionary = blackboard.get_var(&"plan")
		var route: Array = blackboard.get_var(&"route")
		if route.is_empty():
			return RUNNING
		var now := Time.get_ticks_msec()
		var lead := bool(blackboard.get_var(&"lead"))
		var side := float(blackboard.get_var(&"side"))
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
			Kit.go_to(me, Kit.free_near(me, blackboard, goal + off))  # a stop with room: never on a beggar, nor a cart on the watch
			if lead:
				plan["goal"] = goal
			return RUNNING
		if m.moving() or not lead:
			return RUNNING
		# There: on to the next, after a rest where this stop is one.
		var here := int(plan["leg"]) % route.size()
		plan["leg"] = int(plan["leg"]) + 1
		var waits: Array = blackboard.get_var(&"waits")
		if not waits.is_empty() and not bool(waits[here]):
			return RUNNING  # a bend in the street: on without stopping
		var pause: Array = blackboard.get_var(&"pause")
		var secs := randf_range(float(pause[0]), float(pause[1]))
		if secs > 0.0:
			plan["until"] = now + int(secs * 1000.0)
			var rest: Array = blackboard.get_var(&"rest")
			if not rest.is_empty():
				People.play(me, String(rest[randi() % rest.size()]))
			var mk: Variant = blackboard.get_var(&"market")
			if mk is Vector3 and (mk as Vector3).distance_to(goal) < 0.02:
				_set_tail(true)
			_carter(false)
		return RUNNING

	func _set_tail(on: bool) -> void:
		var town: Node3D = blackboard.get_var(&"town")
		if not is_instance_valid(town):
			return
		var me := agent as Node3D
		if on:
			var back := Vector3(sin(me.rotation.y), 0, cos(me.rotation.y))
			var at := town.to_local(me.global_position)
			town.set_meta("cart_tail", [at - back * float(blackboard.get_var(&"tail")), at])
		elif town.has_meta("cart_tail"):
			town.remove_meta("cart_tail")  # rolling: nothing to unload

	func _carter(walking: bool) -> void:
		var c: Variant = blackboard.get_var(&"carter")
		if c is Node3D and is_instance_valid(c):
			People.play(c, "Walk" if walking else ["Idle", "Looking_Around", "Idle_Talking"][randi() % 3])


## Walks after someone at `gap` behind them (and `side` to their right), asked again once they've moved a stride:
## a mourner in the funeral's file behind the one before, a guard at his mate's side on the beat. Stood still
## together, they play one of `rest`.
class Follow extends BTAction:
	var _asked := Vector3.INF
	var _rested := false

	func _tick(_delta: float) -> Status:
		var who: Variant = blackboard.get_var(&"after")
		# Alive first: a type test on a freed leader is itself an error (a town rebuilt frees its people at once).
		if not is_instance_valid(who) or not (who is Node3D) or (who as Node).is_queued_for_deletion():
			if bool(blackboard.get_var(&"with")):
				agent.queue_free()  # the column's head is gone up the road: so is he
			return RUNNING
		var them := who as Node3D
		var back := Vector3(sin(them.rotation.y), 0, cos(them.rotation.y))
		var right := Vector3(back.z, 0, -back.x)
		var to := them.global_position - back * float(blackboard.get_var(&"gap")) + right * float(blackboard.get_var(&"side"))
		var me := agent as Node3D
		var m: Node = Mover.of(me)
		if Vector2(to.x - me.global_position.x, to.z - me.global_position.z).length() < 0.02:
			var rest: Array = blackboard.get_var(&"rest")
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
			var dogged := life.get_children().filter(func(n): return n is Node3D and n.has_meta("dogged"))
			# One dog to a knot of people, never a pack round a child or a group: nobody a step from someone dogged.
			folk = folk.filter(func(n): return not dogged.any(func(o): return (o as Node3D).position.distance_to((n as Node3D).position) < 0.2))
			var kids := folk.filter(func(n): return n.has_meta("chasing"))
			var pool := kids if not kids.is_empty() and randf() < 0.6 else folk
			if pool.is_empty():
				_rest = randf_range(3.0, 8.0)
				return RUNNING
			_after = pool[randi() % pool.size()]
			_after.set_meta("dogged", dog.get_instance_id())
			_for = randf_range(6.0, 14.0)
			return RUNNING
		_for -= delta
		if _for <= 0.0:
			_after.remove_meta("dogged")
			_after = null
			m.stop()
			dog.remove_meta("step_to")
			_rest = randf_range(4.0, 12.0)  # it lies about, sniffs, scratches (its idle life)
			Animals.walk(dog, false)
			return RUNNING
		var to := _after.global_position
		var gap := dog.global_position.distance_to(to)
		var heel := gap <= float(blackboard.get_var(&"follow")) and gap >= Kit.CLEAR
		if heel and Mind.Step.room(dog, dog.global_position, Kit.CLEAR, _after):
			if m.moving():
				m.stop()  # at its man's heel, with room to stand
			dog.remove_meta("step_to")
		elif _asked == Vector3.INF or _asked.distance_to(to) > 0.05 or not m.moving():
			# A free spot at his heel (never on someone else standing by him), on the dog's side of him.
			var back := dog.global_position - to
			back.y = 0
			var want := to + (back.normalized() if back.length() > 0.01 else Vector3.BACK) * float(blackboard.get_var(&"follow")) * 0.8
			_asked = to
			Kit.go_to(dog, Kit.free_near(dog, blackboard, want, _after))
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
				Kit.go_to(me, root.to_global(pair["goal"]))
			return RUNNING
		if now < int(pair.get("count", 0)):
			return RUNNING  # the chaser counts while the runner makes off
		var runner: Node3D = kids[0]
		if me.global_position.distance_to(runner.global_position) <= float(W.get("catch", 0.06)):
			m.stop()
			Mover.of(runner).stop()
			me.remove_meta("step_to")
			runner.remove_meta("step_to")
			for kd: Node3D in [runner, me]:
				# Tagged on the run, they stand where it happened: each steps a pace to room if someone's there (the
				# other child, a gossip by the well), never standing in them for the breather.
				if not Mind.Step.room(kd, kd.global_position, Kit.CLEAR):
					Kit.go_to(kd, Kit.free_near(kd, blackboard, kd.global_position))
			pair["kids"] = [me, runner]  # caught: now the other one runs
			pair["goal"] = Vector3.INF
			pair["from"] = runner  # he makes off away from the one who caught him
			pair["count"] = now + int(float(W.get("count", 1.0)) * 1000.0)  # the new chaser counts a beat while the other runs
			if randf() < float(W.get("stop", 0.5)) and _alone(pair, root.to_local(runner.global_position)):
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
			Kit.go_to(me, Kit.free_near(me, blackboard, short, runner))
		return RUNNING

	## Whether nobody but the two children (and the dogs at their heels) stands within the chase's `clear` of a
	## town-local point: they stop for breath off on their own, never in among the crier's listeners or a knot of gossips.
	static func _alone(pair: Dictionary, p: Vector3) -> bool:
		var life: Node3D = (pair["root"] as Node3D).get_node_or_null("Life")
		if life == null:
			return true
		var ours: Array = (pair["kids"] as Array).duplicate()
		for kd in pair["kids"]:
			if is_instance_valid(kd) and (kd as Node).has_meta("dogged"):
				ours.append(instance_from_id(int((kd as Node).get_meta("dogged"))))
		for n in life.get_children():
			if n is Node3D and not n in ours and (n.has_meta("role") or n.has_meta("town_dog")) and Vector2((n as Node3D).position.x - p.x, (n as Node3D).position.z - p.z).length() < W_clear(pair):
				return false
		return true

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
		var route: Array = blackboard.get_var(&"route")
		_i += 1
		if _i >= route.size():
			me.queue_free()  # past the road's end: on his way to the host
			return SUCCESS
		m.go(route[_i])
		return RUNNING
