extends RefCounted
## The villagers' talks (integration audit #10, villagers.gd split): the gatherings two or more minds arranged
## (npc_mind FindPartner, Talk, JoinCircle), recorded so chatter.gd puts words over them and hands the floor round.
## One owner of the talks: villagers.gd keeps the bodies, this keeps who is talking with whom, where and for how
## long. Each member's own dictionary points at its gathering (a.talk), and each gathering at its members.

var v: Node  # villagers.gd: the bodies, their towns and walk maps
var talks := {}  # town id -> Array of gatherings: {key, centre, members, move, kind, topic, until, speaker, turn_at, floor}
var _keys := 0  # each gathering's key, for chatter.gd to name it by
var _audit_at := 0.0


func _init(owner: Node) -> void:
	v = owner


## A town gone from view: its talks with it.
func forget(id: int) -> void:
	talks.erase(id)


## Two talking stand no further apart than this (about 2.5 m): further, and
## it's calling across the street, not a talk anyone overhears.
const TALK_REACH := 0.3


## A minds' talk nobody closed (both called away before it began) lapses after this.
const MIND_TALK_SECS := 40.0


## Where `x` is in `list`, by identity (a gathering and its members point at
## each other, so comparing them by value would never end); -1 if not there.
static func _index(list: Array, x: Dictionary) -> int:
	for k in list.size():
		if is_same(list[k], x):
			return k
	return -1


## Which way `b` faces in their gathering: toward the others in it (the one
## across from them, or the middle of the two others), turning as they come and go.
func _towards(b: Dictionary, g: Dictionary) -> Vector2:
	var nb: Node3D = b["node"]
	var sum := Vector2.ZERO
	var k := 0
	var c: Vector3 = b["center"]
	for near in [true, false]:  # those already standing there; failing that, those on their way
		for o in g["members"]:
			if is_same(o, b):
				continue
			var no: Node3D = o["node"]
			if near and Vector2(no.position.x - c.x, no.position.z - c.z).distance_to(g["centre"]) > 0.2:
				continue
			sum += Vector2(no.position.x, no.position.z)
			k += 1
		if k > 0:
			break
	if k == 0:
		return Vector2(g["centre"]) - Vector2(nb.position.x - c.x, nb.position.z - c.z)
	return sum / k - Vector2(nb.position.x, nb.position.z)


## In place: standing at the gathering, not still on the way.
func _present(b: Dictionary, g: Dictionary) -> bool:
	var nb: Node3D = b["node"]
	var c: Vector3 = b["center"]
	var here := Vector2(nb.position.x - c.x, nb.position.z - c.z)
	var to := _towards(b, g)
	# On their own spot in the ring (beside a partner is not across from them),
	# and turned to the others: no one starts talking with their back to them.
	return nb.visible and PackedVector2Array(b["route"]).is_empty() and here.distance_to(b.get("goal", here)) < 0.05 \
		and (to.length() < 0.005 or absf(angle_difference(nb.rotation.y, atan2(to.x, to.y))) < 0.6)


## The town's gatherings in full swing (everyone in them in place), for
## chatter.gd to put words over: {who: villager indices, nodes, kind, key}.
func gatherings(town: int) -> Array:
	var out := []
	for g in talks.get(town, []):
		var members: Array = g["members"]
		if members.size() < 2 or not members.all(func(b): return _in_talk(b, g)):
			continue
		out.append({"who": members.map(func(b): return int(b["i"])), "nodes": members.map(func(b): return b["node"]),
			"kind": g["kind"], "key": int(g["key"]), "topic": String(g.get("topic", ""))})
	return out


## In place for the talk their minds arranged: both arrived, standing, face to face within talking distance.
func _in_talk(b: Dictionary, g: Dictionary) -> bool:
	if not is_instance_valid(b.get("node")):
		return false  # gone with their town (rebuilt, razed): not in any talk
	var nb: Node3D = b["node"]
	if not nb.visible or not PackedVector2Array(b["route"]).is_empty() or not b.get("conversing", false):
		return false  # (their mind enters the talk in steps: close, turn, settle; npc_mind.gd Talk)
	for o in g["members"]:
		if is_same(o, b):
			continue
		if not is_instance_valid(o.get("node")):
			return false  # the other gone with their town: no talk to be in
		var no: Node3D = o["node"]
		var to := Vector2(no.position.x - nb.position.x, no.position.z - nb.position.z)
		if to.length() > TALK_REACH or (to.length() > 0.005 and absf(angle_difference(nb.rotation.y, atan2(to.x, to.y))) > 0.6):
			return false
	return true


## Two whose minds (npc_mind.gd FindPartner) arranged a talk: recorded as a
## gathering so chatter.gd puts words over them. Their minds move and play
## them; the old rules' upkeep leaves them be ("mind"). Returns its key.
func open_talk(a: Dictionary, b: Dictionary, kind := "talk", topic := "") -> int:
	var town: int = a["town"]
	var now := Time.get_ticks_msec() * 0.001
	var list: Array = talks.get(town, []).filter(func(g): return float(g["until"]) > now and not (_index(g["members"], a) >= 0 or _index(g["members"], b) >= 0))
	_keys += 1
	var c: Vector3 = a["center"]
	var mid: Vector3 = (a["node"].position + b["node"].position) * 0.5
	list.append({"key": _keys, "centre": Vector2(mid.x - c.x, mid.z - c.z), "members": [a, b], "move": "Idle_Talking", "kind": kind,
		"topic": topic, "until": now + MIND_TALK_SECS, "speaker": 0, "turn_at": now, "spin": 0.0, "mind": true})
	talks[town] = list
	return _keys


## Room for two more to talk at `at` (world): fewer than two knots talking
## there already (a third makes them one crowd), and nobody else standing on
## the spot. Asked by a mind before it arranges a talk.
func room_to_talk(a: Dictionary, at: Vector3, partner: Dictionary) -> bool:
	var c: Vector3 = a["center"]
	var here := Vector2(at.x - c.x, at.z - c.z)
	var knots := 0
	for g in talks.get(a["town"], []):
		if Vector2(g["centre"]).distance_to(here) < 0.6:
			knots += 1
	if knots >= 2:
		return false
	for b in v.crowds.get(a["town"], []):
		if is_same(b, a) or is_same(b, partner) or not b["node"].visible:
			continue
		var nb: Node3D = b["node"]
		if Vector2(nb.position.x - at.x, nb.position.z - at.z).length() < v.TownLife.ROOM * 1.5:
			return false
	return true


## Test aid (chatter.gd's talk count): talks open in a town, by the minds, and how many have everyone in place.
func talk_counts(town: int) -> Dictionary:
	var out := {"open (minds)": 0, "in place": 0}
	for g in talks.get(town, []):
		out["open (minds)"] += 1
		if g["members"].size() >= 2 and g["members"].all(func(b): return _in_talk(b, g)):
			out["in place"] += 1
		elif g.get("mind", false) and g["members"].size() == 2:
			# Why not: how far apart, who's still walking, how far each is turned from the other.
			var a: Dictionary = g["members"][0]
			var b: Dictionary = g["members"][1]
			var na: Node3D = a["node"]
			var nb: Node3D = b["node"]
			var to := Vector2(nb.position.x - na.position.x, nb.position.z - na.position.z)
			var why := "d=%.2f walking=%d/%d turned=%.1f" % [to.length(), PackedVector2Array(a["route"]).size(), PackedVector2Array(b["route"]).size(),
				absf(angle_difference(na.rotation.y, atan2(to.x, to.y)))]
			out[why] = int(out.get(why, 0)) + 1
	return out


## Talks long over that nobody closed: a knot of people with minds (the old
## rules never keep those up), or a minds' talk both left. Gone, and their
## people free again, so a lapsed knot never blocks a new talk.
func prune(id: int) -> void:
	var now := Time.get_ticks_msec() * 0.001
	var list: Array = talks.get(id, [])
	for k in range(list.size() - 1, -1, -1):
		var g: Dictionary = list[k]
		if now < float(g["until"]) + 5.0:
			continue
		for b in g["members"]:
			if is_same(b.get("talk", {}), g):
				b["talk"] = {}
		list.remove_at(k)  # by place, never by value: a gathering and its people point at each other


## The minds' talk `key` is over (either of the two ends it).
func close_talk(town: int, key: int) -> void:
	var list: Array = talks.get(town, [])
	for k in list.size():
		if int(list[k]["key"]) == key:
			list.remove_at(k)
			return


## A minds' talk close to `a` with room for one more (crowd.json square_agents.circle: most, reach): its key and
## the spot round its ring `a` takes, [key, world spot, world centre], or [] for none. The joiner is a member of
## the gathering from now (they get the floor in turn: chatter.gd); the ring's spots sit evenly round its centre,
## the pair's line across it, joiners on either side of that line, all facing in (FFXV's conversation spots).
func join_talk(a: Dictionary) -> Array:
	var K: Dictionary = preload("res://scripts/data.gd").value("crowd", "square_agents.circle", {})
	var c: Vector3 = a["center"]
	var here := Vector2(a["node"].position.x - c.x, a["node"].position.z - c.z)
	var now := Time.get_ticks_msec() * 0.001
	for g in talks.get(a["town"], []):
		if float(g["until"]) < now or _index(g["members"], a) >= 0:
			continue
		var members: Array = g["members"]
		if members.size() >= int(K.get("most", 4)) or Vector2(g["centre"]).distance_to(here) > float(K.get("reach", 1.2)):
			continue
		var p0: Vector3 = members[0]["node"].position
		var p1: Vector3 = members[1]["node"].position
		var ctr := Vector2((p0.x + p1.x) * 0.5 - c.x, (p0.z + p1.z) * 0.5 - c.z)
		var axis := Vector2(p1.x - p0.x, p1.z - p0.z).normalized()
		var side := Vector2(-axis.y, axis.x) * (1.0 if members.size() == 2 else -1.0)
		var rr := float(K.get("radius", 0.08))
		var spot: Vector2 = v.nav.closest(a["map"], ctr + side * rr)
		if spot.distance_to(ctr + side * rr) > 0.04 or v._body_at(a, spot):
			continue
		members.append(a)
		g["until"] = maxf(float(g["until"]), now + float(K.get("stay", 16.0)))
		return [int(g["key"]), Vector3(c.x + spot.x, v.terrain.height_at(c.x + spot.x, c.z + spot.y), c.z + spot.y), Vector3(c.x + ctr.x, 0, c.z + ctr.y)]
	return []


## `a` leaves talk `key`'s ring (the talk goes on for the rest).
func leave_talk(a: Dictionary, key: int) -> void:
	for g in talks.get(a["town"], []):
		if int(g["key"]) == key:
			var k := _index(g["members"], a)
			if k >= 2:
				(g["members"] as Array).remove_at(k)
			return


## The world centre of talk `key`'s ring when more than two stand in it (each faces it), else INF.
func talk_centre(town: int, key: int) -> Vector3:
	for g in talks.get(town, []):
		if int(g["key"]) == key and (g["members"] as Array).size() > 2:
			var c: Vector3 = g["members"][0]["center"]
			var p0: Vector3 = g["members"][0]["node"].position
			var p1: Vector3 = g["members"][1]["node"].position
			return Vector3((p0.x + p1.x) * 0.5, 0, (p0.z + p1.z) * 0.5)
	return Vector3.INF


## Who has the floor in talk `key` now (chatter.gd is showing their line):
## their villager index, or -1 between lines or when the talk is gone.
func floor_of(town: int, key: int) -> int:
	var now := Time.get_ticks_msec() * 0.001
	for g in talks.get(town, []):
		if int(g["key"]) == key:
			var f: Dictionary = g.get("floor", {})
			return int(f["i"]) if not f.is_empty() and now < float(g["turn_at"]) else -1
	return -1


## Villager `i` has the floor in gathering `key` for `secs`: their turn to
## talk while chatter.gd shows their line, and the gathering lasts past it.
func give_floor(town: int, key: int, i: int, secs: float) -> void:
	var now := Time.get_ticks_msec() * 0.001
	for g in talks.get(town, []):
		if int(g["key"]) != key:
			continue
		for b in g["members"]:
			if int(b["i"]) == i:
				g["floor"] = b
				g["turn_at"] = now + secs
				g["until"] = maxf(float(g["until"]), now + secs + 2.0)
		return


## Test aid (--talkprobe): every five seconds, how many are talking and how
## many of those have nobody in their gathering facing them. Should be none.
func audit() -> void:
	_audit_at -= 1.0
	if _audit_at > 0.0:
		return
	_audit_at = 5.0
	var talkers := 0
	var unfaced := 0
	var groups := 0
	var planned := 0
	for id in v.crowds:
		groups += talks.get(id, []).size()
		planned += v.crowds[id].filter(func(b): return b.has("plan")).size()
		for a in v.crowds[id]:
			var n: Node3D = a["node"]
			var now: String = v.people.clip(n)
			if not n.visible or not now in v.SOCIAL + ["Drinking"]:
				continue
			if Time.get_ticks_msec() < int(a.get("hold_until", 0)):
				continue  # talking to the player
			if now == "Drinking" and a.get("talk", {}).is_empty():
				continue  # a drink alone is no conversation
			talkers += 1
			var faced := false
			for b in a.get("talk", {}).get("members", []):
				if is_same(b, a):
					continue
				var nb: Node3D = b["node"]
				var to := Vector2(n.position.x - nb.position.x, n.position.z - nb.position.z)
				if nb.visible and to.length() < 0.3 and Vector2(sin(nb.rotation.y), cos(nb.rotation.y)).dot(to.normalized()) > 0.5:
					faced = true
					break
			if not faced:
				unfaced += 1
				var g: Dictionary = a.get("talk", {})
				var gaps := []
				for b in g.get("members", []):
					if not is_same(b, a):
						gaps.append("%.2f/%s/%s" % [Vector2(n.position.x - b["node"].position.x, n.position.z - b["node"].position.z).length(), _present(b, g), PackedVector2Array(b["route"]).size()])
				print("UNFACED %s in_talk=%s self_present=%s others=%s" % [now, not g.is_empty(), _present(a, g) if not g.is_empty() else false, gaps])
	print("TALK hour=%.1f planned=%d gatherings=%d talkers=%d unfaced=%d" % [v.hour, planned, groups, talkers, unfaced])
	# How the town's places fill: people at each, the biggest gathering, and the
	# biggest cluster of people standing within a shoulder's reach of each other.
	for id in v.crowds:
		var c: Vector3 = v.towns.towns[id]["node"].global_position
		var places: Dictionary = v._places(id, c)
		var at := {}
		var standing := []
		for a in v.crowds[id]:
			var n: Node3D = a["node"]
			if not n.visible or not PackedVector2Array(a["route"]).is_empty():
				continue
			standing.append(Vector2(n.position.x, n.position.z))
			for k in v.slots.ROOM:
				if Vector2(n.position.x - places[k].x, n.position.z - places[k].z).length() < float(v.slots.ROOM[k]["far"]) + 0.1:
					at[k] = int(at.get(k, 0)) + 1
		var biggest := 0
		for g in talks.get(id, []):
			biggest = maxi(biggest, g["members"].size())
		var seen := {}
		var cluster := 0
		for i in standing.size():
			if seen.has(i):
				continue
			var todo := [i]
			seen[i] = true
			var size := 0
			while not todo.is_empty():
				var j: int = todo.pop_back()
				size += 1
				for k in standing.size():
					if not seen.has(k) and standing[j].distance_to(standing[k]) < 0.15:
						seen[k] = true
						todo.append(k)
			cluster = maxi(cluster, size)
		print("PLACES %s market=%d well=%d tavern=%d sept=%d gathering_max=%d cluster_max=%d" % [v.towns.towns[id]["data"]["name"], at.get("market", 0), at.get("well", 0), at.get("tavern", 0), at.get("sept", 0), biggest, cluster])