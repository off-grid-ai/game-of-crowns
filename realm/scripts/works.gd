extends RefCounted
## The working buildings as the town's people find them: where each trade's
## building stands and its work spots (the anvil, the bellows, the mill's door,
## the inn's benches), what lies stacked there (swords on the armoury rack,
## sacks by the mill), the town's horses, and how the realm's state sets the
## numbers. It decides nothing anyone does: the minds do (npc_mind.gd), the
## scenes set people out (town_life.gd), the walkers walk (villagers.gd).
## The town agent lists each building on the town's root as meta `works`
## (realm/data/works.json says the shape); a town without it has none of this.
## Knobs: realm/data/works.json. --works=off turns it all off.

const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Data := preload("res://scripts/data.gd")
const S := Units.M  # world units per metre, as towns.gd


static func on() -> bool:
	return bool(Data.value("works", "on", true)) and not OS.get_cmdline_user_args().has("--works=off")


## A trade by the name the realm uses (works.json aliases: a smithy is a forge).
static func trade_of(name: String) -> String:
	var al: Dictionary = Data.value("works", "aliases", {})
	return String(al.get(name, name))


## A point as data gives it: a Vector3, or [x, z] / [x, y, z].
static func v3(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Vector2:
		return Vector3(v.x, 0, v.y)
	if v is Array and (v as Array).size() == 2:
		return Vector3(float(v[0]), 0, float(v[1]))
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.INF


## Each working building of the town: trade -> {at, yaw, spots, node, radius},
## town-local. From the town agent's meta `works`; a tavern the town raised
## (towns.gd's places) is its inn when the list doesn't name one.
static func anchors(root: Node3D) -> Dictionary:
	if root == null or not is_instance_valid(root):
		return {}
	var src: Variant = root.get_meta("works", {})
	var places: Dictionary = root.get_meta("places", {})
	var h := hash([src, places.get("tavern")])
	var cached: Array = root.get_meta("_works_cache", [])
	if not cached.is_empty() and int(cached[0]) == h:
		return cached[1]
	var entries: Array = []
	if src is Dictionary:
		for k in src:
			var e: Variant = src[k]
			if e is Dictionary:
				var d: Dictionary = (e as Dictionary).duplicate()
				d["trade"] = d.get("trade", k)
				entries.append(d)
			else:
				entries.append({"trade": k, "at": e})
	elif src is Array:
		for e in src:
			if e is Dictionary:
				entries.append(e)
	var out := {}
	for e: Dictionary in entries:
		var trade := trade_of(String(e.get("trade", e.get("kind", ""))))
		var at := v3(e.get("at"))
		if trade == "" or out.has(trade) or at == Vector3.INF:
			continue
		out[trade] = _resolve(trade, at, e)
	if not out.has("inn") and places.has("tavern"):
		# towns.gd keeps the gathering spot just out from the tavern's door: its
		# middle is a little further back, the front facing the square.
		var door: Vector3 = places["tavern"]
		var flat := Vector3(door.x, 0, door.z)
		var mid := door + flat.normalized() * 0.3 if flat.length() > 0.01 else door
		out["inn"] = _resolve("inn", mid, {"yaw": atan2(-mid.x, -mid.z), "dress": true})
	root.set_meta("_works_cache", [h, out])
	return out


static func _resolve(trade: String, at: Vector3, e: Dictionary) -> Dictionary:
	var yaw: float = float(e["yaw"]) if e.has("yaw") else atan2(-at.x, -at.z)  # front to the square
	var scale := float(e.get("scale", 1.0))
	var spots := {}
	var given: Variant = e.get("spots")
	if given is Dictionary:
		for k in given:
			var p := v3(given[k])
			if p != Vector3.INF:
				spots[k] = p
	var comp := String(e.get("component", trade))
	var model_spots: Variant = Data.value("assets", "components.%s.work" % comp, null)
	var metres: Dictionary = model_spots if model_spots is Dictionary else {}
	var defaults: Dictionary = Data.value("works", "spots.%s" % trade, {})
	var b := Basis(Vector3.UP, yaw)
	for k in defaults.keys() + metres.keys():
		if spots.has(k):
			continue
		var m := v3(metres.get(k, defaults.get(k)))
		if m != Vector3.INF:
			spots[k] = at + b * (m * S * scale)
	return {"at": at, "yaw": yaw, "spots": spots, "node": e.get("node"), "radius": float(e.get("radius", 0.0)), "dress": bool(e.get("dress", true))}


## The trades that stand in for `trade` (works.json fallback: any mill, the
## granary for a missing bakery).
static func candidates(trade: String) -> Array:
	var fb: Dictionary = Data.value("works", "fallback", {})
	var t := trade_of(trade)
	return fb.get(trade, fb.get(t, [t]))


## The building that does `trade`'s work in this town, or {}.
static func find(root: Node3D, trade: String) -> Dictionary:
	var all := anchors(root)
	for t in candidates(trade):
		if all.has(t):
			return all[t]
	return {}


static func has(root: Node3D, trade: String) -> bool:
	return not find(root, trade).is_empty()


## A work spot, "forge.anvil" (town-local), or INF when the town has no such
## building. "trade" alone is the building's middle; "gate" is where the road
## nearest the stables leaves the town.
static func spot(root: Node3D, key: String) -> Vector3:
	var parts := key.split(".")
	if parts[0] == "gate":
		var st := find(root, "stables")
		return gate(root, st.get("at", Vector3.ZERO))
	var b := find(root, parts[0])
	if b.is_empty():
		return Vector3.INF
	if parts.size() < 2:
		return b["at"]
	return (b["spots"] as Dictionary).get(parts[1], Vector3.INF)


## Where a road leaves the town (its plots' edge), the one nearest `near`
## (town-local), or INF in a town laid out with no roads.
static func gate(root: Node3D, near: Vector3) -> Vector3:
	var ways: Array = root.get_meta("ways_main", [])
	var edge := float(root.get_meta("plot_edge", root.get_meta("reach", 3.0))) - 0.4
	var best := Vector3.INF
	for w in ways:
		var path := PackedVector2Array(w)
		for q in path:
			if q.length() >= edge:
				var p := Vector3(q.x, 0, q.y)
				if best == Vector3.INF or p.distance_to(near) < best.distance_to(near):
					best = p
				break
	return best


## The town root a person works in: a villager's through villagers.gd
## (work_root), a scene's person as the Life they stand in.
static func work_root(agent: Node, bb: Blackboard) -> Node3D:
	var v: Variant = bb.get_var(&"vill", null, false)
	if v != null and (v as Object).has_method("work_root") and bb.has_var(&"va"):
		return v.work_root(bb.get_var(&"va"))
	var life := agent.get_parent()
	return life.get_parent() as Node3D if life and life.name == "Life" else null


# --- the town's state, as the work feels it ------------------------------------

## The states a town is in (works.json priority's words), from the city as the
## view has it and the mirror's town scope (a levy is a muster scene there).
static func states(c: Dictionary, town: int) -> Array:
	var bb := Blackboard.new()
	var facts: Dictionary = load("res://scripts/awareness.gd").town_facts(c)  # the store's own translation
	for k in facts:
		bb.set_var(StringName(k), facts[k])
	if Engine.has_meta("awareness") and town >= 0:
		bb.set_var(&"levy", bool(Engine.get_meta("awareness").town(town).get_var(&"levy", false, false)))  # a scene fact: the store's
		bb.set_var(&"raid", bool(Engine.get_meta("awareness").town(town).get_var(&"raid", false, false)))  # raiders at its edge: the store's
	return states_bb(bb)


## A court ruling standing at the town (the bridge's rulings.js) adds its kind: a feast or a
## levy ruled is that state; relief, justice, build and grant are states of their own.
static func _ruled(out: Array, kind: String) -> Array:
	if kind != "" and not kind in out:
		out.append(kind)
	return out


## The same states read up a mind's scopes (awareness.gd).
static func states_bb(bb: Blackboard) -> Array:
	var out: Array = []
	var mood := String(bb.get_var(&"mood", "", false))
	if mood == "hunger" or bool(bb.get_var(&"famine", false, false)):
		out.append("hunger")
	if mood == "feast" or bool(bb.get_var(&"celebrating", false, false)):
		out.append("feast")
	if mood == "riot":
		out.append("riot")  # Freeciv's disorder (bridge view.js mood)
	if bool(bb.get_var(&"grasping", false, false)):
		out.append("grasping")
	# A house split in a rising (bridge risings.js): the rebels hold this town, or its lord still does.
	var side := String((bb.get_var(&"rising", {}, false) as Dictionary).get("side", ""))
	if side == "rebels":
		out.append("rebels")
	elif side == "lord":
		out.append("loyal")
	if bool(bb.get_var(&"levy", false, false)):
		out.append("levy")
	if bool(bb.get_var(&"at_war", false, false)):
		out.append("war")
	if bool(bb.get_var(&"raid", false, false)):
		out.append("raid")  # raiders at its edge (awareness.gd _raided): folk indoors, the alarm bell, houses burning
	if bool(bb.get_var(&"granary_low", false, false)):
		out.append("low")
	if bool(bb.get_var(&"prosperity", false, false)):
		out.append("prosperity")
	if bool(bb.get_var(&"grief", false, false)):
		out.append("grief")
	if bool(bb.get_var(&"plague", false, false)):
		out.append("plague")  # the town is sick: few about, the sick at the sept (town_scenes.json plague)
	for life in ["wedding", "birth", "burial"]:  # its folk's season (bridge households.js): a wedding walks, the bell rings
		if bool(bb.get_var(StringName(life), false, false)):
			out.append(life)
	return _ruled(out, String(bb.get_var(&"ruling", "", false)))


## How many of `what` work at a building now (works.json counts).
static func count(what: String, active: Array, size: int) -> int:
	var row: Dictionary = Data.value("works", "counts." + what, {})
	for s in Data.value("works", "priority", []):
		if s in active and row.has(s):
			return int(row[s])
	var n := int(row.get("base", 0))
	if int(row.get("size_per", 0)) > 0:
		n += size / int(row["size_per"])
	if row.has("most"):
		n = mini(n, int(row["most"]))
	return n


## How the town's state shifts the odds of an activity (works.json weights).
static func weight(act: String, bb: Blackboard) -> float:
	var table: Dictionary = Data.value("works", "weights", {})
	var w := 1.0
	for s in states_bb(bb):
		w *= float((table.get(s, {}) as Dictionary).get(act, 1.0))
	return w


# --- what lies stacked at the buildings ---------------------------------------

static func stock(root: Node3D, what: String) -> int:
	var s: Dictionary = root.get_meta("stock", {})
	return int(s.get(what, Data.num("works", "stock.%s_start" % what, 0)))


## Adds `n` (or takes, n < 0): false when there's none to take. A full stack
## takes no more, and that's no failure (the rest goes inside).
static func add_stock(root: Node3D, what: String, n: int) -> bool:
	if root == null or not is_instance_valid(root):
		return n >= 0
	var s: Dictionary = root.get_meta("stock", {})
	var now := stock(root, what)
	if now + n < 0:
		return false
	s[what] = clampi(now + n, 0, int(Data.num("works", "stock.%s_most" % what, 6)))
	root.set_meta("stock", s)
	return true


# --- horses ---------------------------------------------------------------------

static func horses(root: Node3D) -> Array:
	if root == null or not is_instance_valid(root):
		return []
	return (root.get_meta("horses", []) as Array).filter(func(h): return is_instance_valid(h) and (h as Node).is_inside_tree())


## A horse for `by` to lead (one tied at the inn, or one loose in the
## paddock), now following them; null when there is none.
static func take_horse(root: Node3D, by: Node3D, tied: bool) -> Node3D:
	var best: Node3D = null
	for h: Node3D in horses(root):
		if h.has_meta("led_by") or h.has_meta("tied_at") != tied or h.has_meta("rider"):
			continue
		if best == null or h.global_position.distance_to(by.global_position) < best.global_position.distance_to(by.global_position):
			best = h
	if best:
		best.set_meta("led_by", by)
		best.set_meta("led_at", Time.get_ticks_msec())
		if best.has_meta("tied_at"):
			best.remove_meta("tied_at")
	return best


## Let go: tied where it stands (at the inn's rail), or loose (in the paddock).
static func let_go(h: Node3D, tie: bool) -> void:
	if h == null or not is_instance_valid(h):
		return
	if h.has_meta("led_by"):
		h.remove_meta("led_by")
	if tie:
		h.set_meta("tied_at", Time.get_ticks_msec())


# --- the clock --------------------------------------------------------------------

## The village clock (villagers.gd keeps it), or midday with no village.
static func hour() -> float:
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	var v: Variant = aw.get("villagers") if aw else null
	return float(v.hour) if v is Node and is_instance_valid(v) else 12.0


## Whether the sky is dark now (the villagers' night: main.gd sets it from Sky3D). Lights follow this, not the
## village clock alone: in always-day light that clock loops a working day while the sky stays at its morning
## hour, and the inn's windows lit from 19:00 glowed white in daylight (batch 8b review #14).
static func dark() -> bool:
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	var v: Variant = aw.get("villagers") if aw else null
	return bool(v.night) if v is Node and is_instance_valid(v) else false


## Whether the hour is within a span of works.json day ([from, to], wrapping midnight).
static func within(h: float, key: String) -> bool:
	var span: Array = Data.value("works", "day." + key, [0.0, 24.0])
	var a := float(span[0])
	var b := float(span[1])
	return (h >= a and h < b) if a <= b else (h >= a or h < b)




## The buildings' running life, under a town's Life (town_life.gd adds it):
## the forge's glow and sparks while the hammer swings, the mill turning while
## it works, the inn's windows lit at night and its benches filled by day, the
## stacks at the rack, mill and granary, and the horses: grazing about the
## paddock, led by the groom, tied at the inn.
class Tick extends Node:
	var root: Node3D
	var life: Node3D
	var ground: Callable  # town-local point -> its ground height, town-local
	var hot := false  # war or a levy: the forge works double
	var smiths: Array = []
	var glow: OmniLight3D
	var sparks: GPUParticles3D
	var mills: Array = []  # [{node, axis, rpm, speed}]
	var lights: Array = []  # the inn's window lights
	var by_day: Array = []  # people out only by day (the bench drinkers, the crier's ring)
	var stacks: Array = []  # [{what, at, yaw, prop, most, nodes, fixed}]
	var make_prop: Callable  # town_life._prop, bound: (name, at, yaw) -> Node3D
	var paddock := Vector3.INF
	var roam := 0.4
	var _slow := 0.0
	var _rng := RandomNumberGenerator.new()
	var _swing := {}  # smith -> where in his Hammer_Swing he was last frame (0-1)

	func _ready() -> void:
		_rng.randomize()

	func _process(delta: float) -> void:
		if root == null or not is_instance_valid(root):
			return
		_horses(delta)
		_strikes()
		var h := Works.hour()
		var working := Works.within(h, "work")
		for m: Dictionary in mills:
			var n: Node3D = m["node"]
			if not is_instance_valid(n):
				continue
			var want: float = float(m["rpm"]) if working and bool(m.get("grain", true)) else 0.0
			m["speed"] = move_toward(float(m["speed"]), want, delta * float(m["rpm"]) * Data.num("works", "mill.ease", 0.25))
			if float(m["speed"]) > 0.0:
				n.rotate_object_local(m["axis"], float(m["speed"]) * TAU / 60.0 * delta)
		_slow -= delta
		if _slow > 0.0:
			return
		_slow = 1.0
		_each_second(h, working)

	## Sparks off the anvil at the hammer's strike, on the frame the head meets the iron: the same moments its
	## sound rings (sounds.json clips.Hammer_Swing.at, fractions of the swing), so a burst, a ring and a blow are
	## one (batch 9: sparks once a second, whatever the hammer was doing).
	func _strikes() -> void:
		if sparks == null:
			return
		var at: Array = Data.value("sounds", "clips.Hammer_Swing.at", [0.5])
		for s in smiths:
			if not is_instance_valid(s):
				continue
			var ap: AnimationPlayer = (s as Node).get_node_or_null("Anim")
			if ap == null or ap.current_animation != "Hammer_Swing" or ap.current_animation_length <= 0.0:
				_swing.erase(s)
				continue
			var now: float = ap.current_animation_position / ap.current_animation_length
			var was: float = float(_swing.get(s, now))
			_swing[s] = now
			for t in at:
				var f := float(t)
				if (was < f and f <= now) or (now < was and (f > was or f <= now)):  # passed it, or round the loop past it
					sparks.restart()  # a burst off the anvil for the stroke (one_shot: never a steady stream)
					return

	func _each_second(h: float, working: bool) -> void:
		if glow:
			glow.light_energy = Data.num("works", ("forge.glow.war" if hot else "forge.glow.day") if working else "forge.glow.night", 1.0)
		var lit := Works.within(h, "lit") and Works.dark()
		for l in lights:
			if is_instance_valid(l):
				(l as OmniLight3D).visible = lit
		var benches := Works.within(h, "benches")
		for p in by_day:
			if is_instance_valid(p):
				(p as Node3D).visible = benches if p.has_meta("bench") else working
		for m: Dictionary in mills:
			m["grain"] = Works.stock(root, "mill") > 0 or not m.has("needs_grain")
		for st: Dictionary in stacks:
			var n: int = int(st["fixed"]) if st.has("fixed") else Works.stock(root, String(st["what"]))
			_show(st, n)

	## A stack shows `n` of its things: set out or taken away one by one.
	func _show(st: Dictionary, n: int) -> void:
		var nodes: Array = st["nodes"]
		while nodes.size() > n:
			var x: Variant = nodes.pop_back()
			if is_instance_valid(x):
				(x as Node).queue_free()
		while nodes.size() < n and make_prop.is_valid():
			var i := nodes.size()
			var yaw: float = st["yaw"]
			var along := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
			var row := float(i % 3) - 1.0
			var at: Vector3 = st["at"] + along * row * float(st.get("gap", 0.06))
			var p: Node3D = make_prop.call(String(st["prop"]), at, yaw + _rng.randf_range(-0.3, 0.3), float(i / 3) * float(st.get("lift", 0.035)))
			if p == null:
				break
			nodes.append(p)

	## Horses: led ones walk behind their groom, tied ones wait at the rail
	## (then walk home on their own if nobody comes), loose ones graze about.
	## Whether `at` is `gap` clear of every horse but `h`, and of where each is headed.
	func _clear_of_horses(h: Node3D, at: Vector3, gap: float) -> bool:
		for o: Node3D in Works.horses(root):
			if o == h:
				continue
			var g: Vector3 = o.get_meta("goal", Vector3.INF)
			if Vector2(at.x - o.position.x, at.z - o.position.z).length() < gap or (g != Vector3.INF and Vector2(at.x - g.x, at.z - g.z).length() < gap):
				return false
		return true

	func _horses(delta: float) -> void:
		var gap := Data.num("works", "paddock.gap", 0.45)
		var follow := Data.num("works", "paddock.follow", 0.16)
		var amble := Data.num("works", "paddock.amble", 0.07)
		for h: Node3D in Works.horses(root):
			h.add_to_group("bodies")  # a standing body: another's Mover gives way to it (mover.gd standing_on, the one rule)
			var to := Vector3.INF
			var pace := amble
			var by: Variant = h.get_meta("led_by") if h.has_meta("led_by") else null  # (a null default to get_meta is no default)
			if by != null and (not is_instance_valid(by) or Time.get_ticks_msec() - int(h.get_meta("led_at", 0)) > int(Data.num("works", "paddock.lead_most", 120.0) * 1000.0)):
				Works.let_go(h, false)  # their groom gone, or never let go: it wanders home
				by = null
			if by != null:
				var g: Node3D = by
				var back := Vector3(sin(g.global_rotation.y), 0, cos(g.global_rotation.y))
				to = root.to_local(g.global_position - back * follow)
				pace = 0.25
				if Vector2(to.x - h.position.x, to.z - h.position.z).length() < 0.03:
					to = Vector3.INF  # close enough: it stands
			elif h.has_meta("tied_at"):
				if Time.get_ticks_msec() - int(h.get_meta("tied_at")) > int(Data.num("works", "paddock.tied_secs", 90.0) * 1000.0):
					h.remove_meta("tied_at")  # nobody came: it's brought home (or wanders back)
				continue
			else:
				var goal: Vector3 = h.get_meta("goal", Vector3.INF)
				var rest := float(h.get_meta("rest", 0.0)) - delta
				h.set_meta("rest", rest)
				if goal == Vector3.INF and rest <= 0.0 and paddock != Vector3.INF:
					# A spot of its own, a horse's length and more from every other horse and where it's headed
					# (works.json paddock.gap; round 5: the paddock's horses walked into each other).
					for t in 8:
						var a := _rng.randf() * TAU
						var r := sqrt(_rng.randf()) * roam
						goal = paddock + Vector3(cos(a) * r, 0, sin(a) * r)
						if _clear_of_horses(h, goal, gap):
							break
					h.set_meta("goal", goal)
				if goal != Vector3.INF:
					to = goal
					if Vector2(goal.x - h.position.x, goal.z - h.position.z).length() < 0.02:
						h.set_meta("goal", Vector3.INF)
						var span: Array = Data.value("works", "paddock.rest", [4.0, 14.0])
						h.set_meta("rest", _rng.randf_range(float(span[0]), float(span[1])))
						to = Vector3.INF
			if to == Vector3.INF:
				if h.has_node("Mover") and by != null:
					Mover.of(h).stop()  # at its groom's back: it stands
				continue
			_walk_horse(h, to, pace, by == null)

	## A horse's walk to `to` (town-local) by the Mover (CLAUDE.md, one way to move): it steers on an arc at least
	## works.json paddock.turn_radius wide and never turns on the spot (Mac, 12 Nov: "it just rotates in the same
	## place"); its gait follows its speed (horse.gd). A goal that moves (its groom walking on) is asked for again
	## once it has moved a stride.
	## fenced: loose in its paddock, it never steps past the fence (the Mover's keep: a horse on an arc slides along
	## the rail rather than walking through it); led, it goes where its groom goes.
	func _walk_horse(h: Node3D, to: Vector3, pace: float, fenced: bool) -> void:
		var m: Node = Mover.of(h)
		if fenced and paddock != Vector3.INF:
			var r := root
			var mid := paddock
			var most := roam
			m.keep = func(w: Vector3) -> Vector3:
				var l := r.to_local(w)
				var off := Vector2(l.x - mid.x, l.z - mid.z)
				if off.length() <= most:
					return w
				off = off.normalized() * most
				return r.to_global(Vector3(mid.x + off.x, l.y, mid.z + off.y))
		else:
			m.keep = Callable()
		var goal := root.to_global(to)
		var was: Vector3 = h.get_meta("walk_to", Vector3.INF)
		if m.moving() and was.distance_to(goal) < 0.05:
			return
		m.speed = pace
		m.clip = ""  # the horse plays its own gait from its speed
		m.turn_radius = Data.num("works", "paddock.turn_radius", 0.4)
		var r := root
		var g := ground
		m.ground = func(w: Vector3) -> float:
			var l := r.to_local(w)
			return r.to_global(Vector3(l.x, float(g.call(l)) if g.is_valid() else l.y, l.z)).y
		h.set_meta("walk_to", goal)
		m.go(goal)


const Works := preload("res://scripts/works.gd")
