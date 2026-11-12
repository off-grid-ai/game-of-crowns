extends RefCounted
## Where a villager may stand (integration audit #10, villagers.gd split): the claims on a town's places and slots
## (Unreal's smart objects, The Sims' slots). The rings round the market, the well, the tavern and the sept (ROOM: near,
## far, how many), the overflow to the next place when one is full, the stall fronts, the well's draw, the street
## ends and the cart's tail (SLOTS), each held by one at a time and shut a moment after it's left; and the square's
## room (how many may be bound there at once). One owner of the claims: villagers.gd keeps the bodies and asks here;
## a mind's GoTo asks through villagers (v.slots.place).

var v: Node  # villagers.gd: the bodies, their towns and walk maps


func _init(owner: Node) -> void:
	v = owner


## How much room each shared place has: people stand from `near` to `far`
## out from its heart, and no more than `room` of them at once.
## A square looks busy at 15-25 people with room between them, never shoulder
## to shoulder (the judge, from Manor Lords): what each place holds.
const ROOM := {"market": {"near": 0.3, "far": 1.0, "room": 6}, "well": {"near": 0.21, "far": 0.65, "room": 4},
	"tavern": {"near": 0.15, "far": 0.6, "room": 7}, "sept": {"near": 0.15, "far": 0.55, "room": 5},
	# Round the town's feast fire, out from its reach (town_life.fire_reach) and
	# past the revellers' own ring: a second ring of faces, a shoulder apart.
	"feast": {"near": 0.3, "far": 0.6, "room": 12, "fire": true}}

## Where those who find a place full go instead.
const OVERFLOW := {"market": ["well", "tavern"], "well": ["market", "sept"], "tavern": ["market", "well"], "sept": ["well", "market"], "feast": ["market", "tavern"]}

static var SHOULDER: float = preload("res://scripts/data.gd").num("crowd", "villagers.shoulder", 0.11)  # two people standing: a shoulder's width apart

static var SQUARE_HOLDS: int = int(preload("res://scripts/data.gd").num("crowd", "villagers.square_holds", 10))  # at most this many bound for the square at once (talkers included), in the biggest towns (_square_cap)

static var SQUARE_EDGE: float = preload("res://scripts/data.gd").num("crowd", "villagers.square_edge", 0.6)  # past the square's paving this far is still the square: stall fronts, the well, the doors on its edge

static var KNOT: float = preload("res://scripts/data.gd").num("crowd", "villagers.knot_clear", 0.26)  # a gathering keeps this clear round its middle: knots of two or three, never one blob

## The square's smart objects (crowd.json square_agents, the switch --square-agents=on|off; supervisor 2026-11-12,
## Mac: "the people behaviour is poor"): each stall's front, the well's rim and the main streets' mouths offer a
## few slots, each with the way to face (the counter, the well, out along the street). A villager sent there
## (npc_mind go("stall"), go("draw"), go("street")) claims a slot nobody stands on or is bound for, as Manor
## Lords' and Anno's villagers claim a market stall's or a well's slot, so two never stack and the square fills
## by its stalls and its well, not in one ring round a point.
const SLOTS := ["stall", "draw", "street", "cart"]

var _released := {}  # slot id -> when it was last left (msec): shut for square_agents.cooldown after


## A free spot at a shared place (world), spread over its ground on the walk
## map and clear of where everyone else stands or is bound; a full place sends
## them on to the next that fits, and failing all, to their own work spot by
## their door (their bench: the yard, the workshop front), where a town's
## people mostly are.
func place(a: Dictionary, key: String, knot := false) -> Vector3:
	if a.has("slot_id"):
		_released[String(a["slot_id"])] = Time.get_ticks_msec()  # the slot they leave shuts a moment (square_agents.cooldown)
		a.erase("slot_id")
	a["face_at"] = Vector3.INF
	a["slot_stall"] = -1
	a["slot_kind"] = ""
	if key == "cart":
		var sc := _slot(a, "cart")  # the market cart's tail while it waits there; none, the errand is off
		if not is_nan(sc.x):
			a["place_key"] = "cart"
			return sc
		return Vector3.INF
	if key == "stall_buy":
		# Up from the queue to a buying slot: one or none; none sends them on (GoTo fails, the tree moves on).
		var sb := _slot(a, "stall", false)
		if not is_nan(sb.x):
			a["place_key"] = "stall"
			return sb
		return Vector3.INF
	if key in SLOTS:
		# A smart object's slot (a stall's front, the well's rim, a street's mouth): claimed, faced, never stacked.
		var sp := _slot(a, key)
		if not is_nan(sp.x):
			a["place_key"] = key
			return sp
		if v.TownLife.square_agents_on() and key != "street":
			# No slot to be had: the errand is off (GoTo fails, the tree goes on to something else), never its moves
			# played at an open spot on the cobbles in front of nothing (Mac's man looping gestures alone, round 8).
			return Vector3.INF
		key = "market" if key != "street" else "home"
		if key == "home":
			a["place_key"] = ""
			return v.nearby(a["home"], a["rng"], 0.25)
	for k in [key] + Array(OVERFLOW.get(key, [])):
		var clear := KNOT if knot else (SHOULDER * 1.2 if k == "feast" else SHOULDER * 2.6)  # alone, a couple of strides from the next: a lively square, not a crowd; round a fire, a shoulder apart
		var p := _claim(a, k, clear)
		if not is_nan(p.x):
			a["place_key"] = k
			return p
	a["place_key"] = ""
	return a["bench"] if a.has("bench") and not on_square(a, Vector2(a["bench"].x - a["center"].x, a["bench"].z - a["center"].z)) else v.nearby(a["home"], a["rng"], 0.25)


func _claim(a: Dictionary, key: String, clear: float) -> Vector3:
	var c: Vector3 = a["center"]
	var room: Dictionary = ROOM[key]
	var busy := crown_market(a["town"])
	if busy.has("rooms") and (busy["rooms"] as Dictionary).has(key):
		room = room.duplicate()
		room["room"] = int(busy["rooms"][key])  # the crown's market at midday: more at each place
	var h: Vector2
	if room.get("fire", false):
		# The feast's ring is round the town's lit fire: none lit, no feast ring.
		var fire: Array = v.registry.fire_of(a["town"])
		if fire.is_empty():
			return Vector3(NAN, 0, 0)
		h = fire[0]
		var reach := float(fire[1])
		room = {"near": reach + float(room["near"]), "far": reach + float(room["far"]), "room": room["room"]}
	else:
		var heart: Vector3 = v._places(a["town"], c)[key]
		h = Vector2(heart.x - c.x, heart.z - c.z)
	if on_square(a, h) and square_full(a):
		return Vector3(NAN, 0, 0)  # the square's budget is spent, whichever of its places they asked for
	var goals := []
	var there := 0
	for b in v.crowds.get(a["town"], []):
		if is_same(b, a) or not b.has("goal") or not b["node"].visible:
			continue
		var gp: Vector2 = b["goal"]
		goals.append(gp)
		if gp.distance_to(h) < float(room["far"]) + 0.1:
			there += 1
	# The town's scene folk (stall keepers and buyers, a crowd, revellers) stand
	# where they stand: their spots are taken too.
	var town_node: Node3D = v.towns.towns.get(a["town"], {}).get("node")
	var life: Node = town_node.get_node_or_null("Life") if town_node else null
	if life:
		for sp: Vector2 in life.get_meta("standing", PackedVector2Array()):
			goals.append(sp)
			if sp.distance_to(h) < float(room["far"]) + 0.1:
				there += 1
	if there >= int(room["room"]):
		return Vector3(NAN, 0, 0)  # full
	var map: RID = a["map"]
	var start: float = a["rng"].randf() * TAU
	# Every ring out from the heart, starting from one at random: filled from
	# the middle outward, a busy square packed into one tight clump.
	var rings: Array[float] = []
	var rr: float = room["near"]
	while rr <= float(room["far"]):
		rings.append(rr)
		rr += SHOULDER
	var first: int = a["rng"].randi() % rings.size()
	for ri in rings.size():
		var r: float = rings[(first + ri) % rings.size()]
		var n := maxi(4, int(TAU * r / SHOULDER))
		for i in n:
			var want := h + Vector2.from_angle(start + TAU * i / n) * r
			var q: Vector2 = v.nav.closest(map, want)
			if q.distance_to(want) > 0.05:
				continue  # under a stall or a wall
			if town_node and not v.nav.inside(town_node, Vector3(c.x + q.x, 0, c.z + q.y)).is_empty():
				continue  # in a fire, a cart or a table the walk map doesn't know of yet
			if town_node and v.TownLife.on_lane(town_node, Vector3(c.x + q.x, 0, c.z + q.y)):
				continue  # on a road's lane: travellers would walk through them
			var clear_here := true
			for gp: Vector2 in goals:
				if gp.distance_to(q) < clear:
					clear_here = false
					break
			if clear_here:
				return Vector3(c.x + q.x, v.terrain.height_at(c.x + q.x, c.z + q.y), c.z + q.y)
	return Vector3(NAN, 0, 0)


## A shopper standing at stall `stall`'s front: its keeper (town_life _trade's keepers) is told, to turn and serve
## them (npc_mind Serve). Nothing when the stall has no keeper.
func at_stall(a: Dictionary, who: Node3D) -> void:
	var stall := int(a.get("slot_stall", -1))
	var town_node: Node3D = v.towns.towns.get(a["town"], {}).get("node")
	if stall < 0 or not is_instance_valid(town_node) or String(a.get("slot_kind", "")) == "wait":
		return
	if String(a.get("role", "")) == "porter":
		v.TownLife.pile(town_node, stall, 1)  # the load set down on the stall's pile
		return
	var keeper: Variant = (town_node.get_meta("keepers", {}) as Dictionary).get(stall)
	if keeper is Node3D and is_instance_valid(keeper) and not (keeper as Node3D).has_meta("customer"):
		(keeper as Node3D).set_meta("customer", who)
		(keeper as Node3D).set_meta("customer_at", Time.get_ticks_msec())
		(keeper as Node3D).set_meta("customer_stall", stall)


func _slot(a: Dictionary, key: String, queue := true) -> Vector3:
	if not v.TownLife.square_agents_on():
		return Vector3(NAN, 0, 0)
	var town_node: Node3D = v.towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return Vector3(NAN, 0, 0)
	var c: Vector3 = a["center"]
	var K: Dictionary = preload("res://scripts/data.gd").value("crowd", "square_agents", {})
	var r := float(town_node.get_meta("square_r", 1.0))
	var offers: Array = []  # [town-local spot, town-local spot to face]
	match key:
		"stall":
			var off := float(K.get("stall_out", 0.13))
			var sti := -1
			var keepers: Dictionary = town_node.get_meta("keepers", {})
			var waits: Array = []
			for st in town_node.get_meta("stalls", []):
				sti += 1
				var m: Vector3 = st[0]
				if not (keepers.get(sti) is Node3D and is_instance_valid(keepers.get(sti))):
					continue  # nobody to buy from: the buyer's loop runs only with a keeper there
				var out := Vector3(m.x, 0, m.z).normalized()
				var along := Vector3(-out.z, 0, out.x)
				var front := m - out * (float(st[1]) * 0.5 + off)
				for k in [0.0, -0.32, 0.32]:
					offers.append([front + along * float(st[2]) * k, m, sti, "buy"])
				waits.append([front - out * float(K.get("queue_back", 0.1)), m, sti, "wait"])
			if queue:
				waits.shuffle()
				offers.append_array(waits)  # every buying slot taken: one waits behind, at a stall
		"draw":
			var places: Dictionary = town_node.get_meta("places", {})
			if places.has("well"):
				var w: Vector3 = places["well"]
				var rim := float(K.get("well_rim", 0.2))
				for i in 5:
					var ang := TAU * i / 5.0 + 0.4
					offers.append([w + Vector3(cos(ang), 0, sin(ang)) * rim, w])
		"cart":
			var tail: Array = town_node.get_meta("cart_tail", [])
			if tail.size() >= 2:
				var tp: Vector3 = tail[0]
				var side := Vector3(-(tail[1] - tp).z, 0, (tail[1] - tp).x).normalized()
				for k in [0.0, -0.08, 0.08]:
					offers.append([tp + side * k, tail[1]])
		"street":
			var reach := float(K.get("street_out", 1.25)) * r
			for wy in town_node.get_meta("ways_main", []):
				var line := wy as PackedVector2Array
				for q in line:
					if q.length() > reach:
						var o := Vector3(q.x, 0, q.y)
						var side := Vector3(-o.z, 0, o.x).normalized()
						for k in [-0.07, 0.07]:
							offers.append([o + side * k, o * 2.0])  # facing on out along the street
						break
	if offers.is_empty():
		return Vector3(NAN, 0, 0)
	var goals: Array = []
	for b in v.crowds.get(a["town"], []):
		if not is_same(b, a) and b.has("goal") and b["node"].visible:
			goals.append(b["goal"])
	var life: Node = town_node.get_node_or_null("Life")
	if life:
		goals.append_array(Array(life.get_meta("standing", PackedVector2Array())))
	var clear := float(K.get("slot_clear", 0.1))
	var cool := int(float(K.get("cooldown", 3.0)) * 1000.0)
	var now := Time.get_ticks_msec()
	var buys := offers.filter(func(o: Array) -> bool: return o.size() < 4 or o[3] != "wait")
	var rest := offers.filter(func(o: Array) -> bool: return o.size() >= 4 and o[3] == "wait")
	var first: int = a["rng"].randi() % maxi(buys.size(), 1)
	var order: Array = []
	for i in buys.size():
		order.append(buys[(first + i) % buys.size()])
	order.append_array(rest)  # the queue only once every buying slot is taken
	for i in order.size():
		var o: Array = order[i]
		var sid := "%s:%d:%d" % [key, roundi(o[0].x * 1000.0), roundi(o[0].z * 1000.0)]
		if now - int(_released.get(sid, -100000)) < cool:
			continue  # just left: shut a moment
		var q: Vector2 = v.nav.closest(a["map"], Vector2(o[0].x, o[0].z))
		if q.distance_to(Vector2(o[0].x, o[0].z)) > 0.06:
			continue  # under a stall's counter or a wall
		if not v.nav.inside(town_node, Vector3(c.x + q.x, 0, c.z + q.y)).is_empty():
			continue
		if goals.any(func(g: Vector2) -> bool: return g.distance_to(q) < clear):
			continue  # someone there, or on their way
		var f: Vector3 = o[1]
		a["face_at"] = Vector3(c.x + f.x, 0, c.z + f.z)
		a["slot_stall"] = int(o[2]) if o.size() > 2 else -1
		a["slot_kind"] = String(o[3]) if o.size() > 3 else key
		a["slot_id"] = sid
		return Vector3(c.x + q.x, v.terrain.height_at(c.x + q.x, c.z + q.y), c.z + q.y)
	return Vector3(NAN, 0, 0)


## The square holds so many and no more, whatever sends them (an errand, a
## talk, a mind's plan, a mourning): bound there when it's full, they keep to
## their own door instead, so the square stays busy but never a press.
func room_in_square(a: Dictionary, goal: Vector2, map: RID) -> Vector2:
	var town: Dictionary = v.towns.towns.get(a["town"], {})
	if town.is_empty():
		return goal
	var sq: float = town["node"].get_meta("square_r", 0.0) + 0.1
	if not on_square(a, goal):
		return goal
	if v._grieving(a):
		# A town mourns in small knots spread through it, never one crowd in
		# the square (Mac's call): the grieving keep to their own door, or
		# just beyond the square's edge when their door is on it.
		var c0: Vector3 = a["center"]
		var home := Vector2(a["home"].x - c0.x, a["home"].z - c0.z)
		if home.length() < sq + 0.15:
			home = home.normalized() * (sq + 0.25) if home.length() > 0.01 else Vector2(sq + 0.25, 0)
		return v.nav.closest(map, home)
	if not square_full(a):
		return goal
	var c: Vector3 = a["center"]
	var near: Vector3 = v.nearby(a["home"], a["rng"], 0.2)
	return v.nav.closest(map, Vector2(near.x - c.x, near.z - c.z))


## The square and the ring round its edge (town-local): in a small town every
## shared place stands here (stalls, well, tavern and church doors), so it is
## one ground with one budget, not four places each with its own room.
func on_square(a: Dictionary, p: Vector2) -> bool:
	var town_node: Node3D = v.towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return false
	return p.length() < float(town_node.get_meta("square_r", 0.0)) + SQUARE_EDGE


## How many the square holds at once, by the town's size: a hamlet's square
## has a handful about it, a market town's its fill (SQUARE_HOLDS). Crowford
## (size 6) had 30 villagers and four places' rooms on one square: a press.
func square_cap(a: Dictionary) -> int:
	var size := int(v.towns.towns.get(a["town"], {}).get("data", {}).get("size", 1))
	var busy := crown_market(a["town"])
	if busy.has("square_holds") and v.TownLife.square_agents_on():
		return int(preload("res://scripts/data.gd").num("crowd", "square_agents.square_holds", float(busy["square_holds"])))  # the walkers on errands are the square's crowd now
	if busy.has("square_holds"):
		return int(busy["square_holds"])  # the crown's seat: the realm's busiest market (data/towns.json market.crown)
	return clampi(2 + size, 5, SQUARE_HOLDS)


## The crown's seat's market knobs (data/towns.json market.crown), or {} for any other town:
## its square holds more, each place there more, and more of its people are out.
func crown_market(id) -> Dictionary:
	var node = v.towns.towns.get(id, {}).get("node")
	if not is_instance_valid(node) or not bool(node.get_meta("crown_seat", false)):
		return {}
	return v.TownLife.crown_market()


## Whether the square (with its edge) already holds its fill: everyone bound
## there, and those town life stands there (beggars, a mob, revellers, keepers
## and buyers at the stalls), since two crowds in one square make a press.
func square_full(a: Dictionary) -> bool:
	var town_node: Node3D = v.towns.towns.get(a["town"], {}).get("node")
	if not is_instance_valid(town_node):
		return false
	var there := 0
	for b in v.crowds.get(a["town"], []):
		if not is_same(b, a) and b["node"].visible and on_square(a, Vector2(b.get("goal", Vector2(99, 99)))):
			there += 1
	var life: Node = town_node.get_node_or_null("Life")
	if life and not v.TownLife.square_agents_on():  # with the square's agents on, the posted few (keepers, the drill) don't use up the walkers' room
		for p: Vector2 in life.get_meta("standing", PackedVector2Array()):
			if on_square(a, p):
				there += 1
	return there >= square_cap(a)
