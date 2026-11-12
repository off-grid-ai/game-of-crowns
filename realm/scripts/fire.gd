extends Node3D
## Fire, v2 (docs/art/target/04-siege.jpg; the finesse catalogue's flames and ruins; Stronghold, Total War's
## sack, Manor Lords): a burning house has shaped flames licking off its roof and out of its front, embers, a
## dark sunlit smoke column leaning with the one wind, a scorch on the ground, and it chars as it burns, its roof
## falling in. Made of blocks: GDQuest's stylized fire shader (MIT) over Kenney's Particle Pack flame tongues,
## smoke and scorch sprites (CC0) on Godot's GPUParticles3D; the char is ruins.gd's charring as a shader.
##
## The one owner of the fire's look. Which houses stand burnt is the bridge's damage fact (/world cities[].damage:
## its burnt share, and the houses kindled, bridge/damage.js), read from the mirror (awareness.gd's town scope,
## "damage"), never a timer and never kept here. A sack or razing (scenes.gd) or a fire arrow sets houses alight;
## each house that catches is told to the bridge (kindled), so it stands burnt through a reload, and whole again
## as the realm rebuilds it. Knobs: data/fire.json. On with fire.json on.

const FLAME_SHADER := preload("res://scripts/stylized_fire.gdshader")
const CHAR_SHADER := preload("res://scripts/charred.gdshader")
const WeatherFx := preload("res://scripts/weather_fx.gd")
const SceneKinds := preload("res://scripts/scene_kinds.gd")
const DIR := "res://assets/fx/fire/"
const SMOKE_LAYER := 1 << 10  # smoke is lit by the sun, never by the fire's own light (it glowed orange)
const FAR := 45.0  # game units: beyond this a fire isn't drawn

static var live: Node3D  # the one fire (main.gd adds it): scenes.gd's sacks and razings reach it here
static var _knobs = null
static var _cache := {}  # shared textures and materials, made once

var main: Node  # main.gd: its towns and its mirror (awareness)
var _burnt := {}  # "town:home" -> {shell, hidden: [[MultiMesh, index, transform]], box, root}
var _burning := {}  # "town:home" -> its fire node, while it burns (meta stage: catch, burn, collapse, smoulder)
var _spreads := {}  # town id -> {left: [homes still to catch], lit: [homes caught], root, pace, pick, at}: a fire travelling
var _told := {}  # "town:home" -> true: a house that caught, told to the bridge, until the mirror has it (kindled)
var _lines := {}  # town id -> {key: the house it works at, folk: [their minds]}: the town's bucket line
var _tick := 0.0
var _clock := 0.0


static func knobs() -> Dictionary:
	if _knobs == null:
		var f := FileAccess.open("res://data/fire.json", FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text()) if f else null
		_knobs = j if j is Dictionary else {}
	return _knobs


static func on() -> bool:
	return bool(knobs().get("on", false))


static func apply(m: Node) -> void:
	if not on():
		return
	var f := new()
	f.name = "Fire"
	f.main = m
	m.add_child(f)


func _ready() -> void:
	live = self


func _exit_tree() -> void:
	if live == self:
		live = null


## A sack (or, razed, a razing) at `at`: the town's houses the damage fact marks burnt (if the fact hasn't
## come yet, fire.json's share of them) catch one after another, all within about `seconds` (the scene's
## length). False if there's no town there.
static func ignite(at: Vector3, seconds: float, razed: bool) -> bool:
	return live != null and live._ignite(at, seconds, razed)


## A fire arrow lands at `at`: the house nearest it (within reach) catches, unless it burns already, and stands
## burnt in the realm's damage fact (kindled) until the realm rebuilds it. False if no house was near.
static func kindle(at: Vector3, reach := 0.35) -> bool:
	return live != null and live._kindle(at, reach)


func _kindle(at: Vector3, reach: float) -> bool:
	for id in main.towns.towns:
		var root: Node3D = main.towns.towns[id].get("node")
		if root == null or not is_instance_valid(root):
			continue
		var homes: Array = root.get_meta("homes", [])
		var here := root.to_local(at)
		var best := -1
		var near := reach
		for i in homes.size():
			var p := _home_at(homes[i])
			var d := Vector2(p.x - here.x, p.z - here.z).length()
			if d < near:
				near = d
				best = i
		if best >= 0:
			var key := "%d:%d" % [id, best]
			if _burning.has(key) or _burnt.has(key):
				return false
			_alight(root, key, homes[best], int(id))
			return true
	return false


## A yard fire's flames (towns.gd _hearth keeps its light and smoke): the same flames, small.
static func hearth(root: Node3D, pos: Vector3) -> void:
	var k: Dictionary = knobs().get("hearth", {})
	var sz: Array = k.get("size", [0.05, 0.08])
	var p := _flames(int(k.get("amount", 8)), float(k.get("life", 0.6)), sz, Vector2(0.15, 0.25), Vector3(0.02, 0.0, 0.02), _flame_material(true))
	p.visibility_range_end = 30.0
	p.position = pos + Vector3(0, 0.01, 0)
	root.add_child(p)


## A yard fire's light (towns.gd _hearth): warm, low and soft, held over the flames (fire.json hearth.light).
## It stood 0.12 over the ground at 0.5: the grass right under it lit to white and bloomed into a glowing
## orb beside the fire (batch 7 review #13, the bailey's campfire).
static func hearth_light(root: Node3D, pos: Vector3) -> void:
	var k: Dictionary = (knobs().get("hearth", {}) as Dictionary).get("light", {})
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = float(k.get("energy", 0.3))
	light.omni_range = float(k.get("range", 0.45))
	light.omni_attenuation = float(k.get("falloff", 1.6))
	light.light_specular = 0.0
	light.shadow_enabled = false
	light.position = pos + Vector3(0, float(k.get("height", 0.3)), 0)
	root.add_child(light)


func _ignite(at: Vector3, seconds: float, razed: bool) -> bool:
	var d := knobs()
	var best := -1
	var near := float(d.get("reach", 1.6))
	for id in main.towns.towns:
		var n: Node3D = main.towns.towns[id]["node"]
		if not is_instance_valid(n):
			continue
		var off: Vector3 = n.global_position - at
		if Vector2(off.x, off.z).length() < near:
			near = Vector2(off.x, off.z).length()
			best = id
	if best < 0:
		return false
	var root: Node3D = main.towns.towns[best]["node"]
	var homes: Array = root.get_meta("homes", [])
	if homes.is_empty():
		return false
	var share := maxf(_burnt_share(best), float(d.get("share_razed" if razed else "share_sack", 0.4)))
	# The houses that catch are the ones nearest what the King is looking at (a sack is a decision: its fire
	# must be seen); each that catches is told to the bridge, so those are the ones that stand burnt.
	var order := _nearest_first(root, homes)
	var left := []
	var least := int((d.get("spread", {}) as Dictionary).get("least", 4))  # a sack is seen to spread: a few houses at least
	for i in mini(homes.size(), maxi(mini(least, homes.size()), ceili(share * homes.size()))):
		if not _burning.has("%d:%d" % [best, order[i]]):
			left.append(order[i])
	if left.is_empty():
		return true
	# The raiders torch a few at once (fire.json spread.torched), never two neighbours; the rest catch one at a
	# time from the ones already burning (spread). A short scene (`seconds`) quickens the spread so every house
	# the fact names has caught before it ends.
	var sp: Dictionary = d.get("spread", {})
	var gap: Array = sp.get("gap_s", [3.0, 12.0])
	var mean := (float(gap[0]) + float(gap[1])) * 0.5
	var pace := clampf(seconds * 0.6 / maxf(1.0, (left.size() - 1) * mean), 0.25, 1.0) if seconds > 0.0 else 1.0
	var lit := []
	for h in left.duplicate():
		if lit.size() >= maxi(1, int(sp.get("torched", 3))):
			break
		var p := _home_at(homes[h])
		if lit.any(func(o): return _home_at(homes[o]).distance_to(p) < float(sp.get("torch_apart", 0.5))):
			continue
		lit.append(h)
		left.erase(h)
		_alight(root, "%d:%d" % [best, h], homes[h], best)
	_spreads[best] = {"left": left, "lit": lit, "root": root, "pace": pace}
	if left.is_empty():
		_spreads[best]["at"] = INF
	else:
		_queue_next(best)
	return true


## A town's houses, the nearest first to where the camera looks (its rig's target, when it's on this town),
## else to the town's heart.
func _nearest_first(root: Node3D, homes: Array) -> Array:
	var eye := root.global_position
	var rig = main.get("rig")
	if rig != null and rig.get("target") is Vector3:
		var t: Vector3 = rig.target
		var reach := float(knobs().get("reach", 1.6)) * 4.0
		if Vector2(t.x - eye.x, t.z - eye.z).length() < reach:
			eye = t
	var here := root.to_local(eye)
	var idx := range(homes.size())
	idx.sort_custom(func(a, b): return Vector2(_home_at(homes[a]).x - here.x, _home_at(homes[a]).z - here.z).length() < Vector2(_home_at(homes[b]).x - here.x, _home_at(homes[b]).z - here.z).length())
	return idx


## A town's root as it stands now (towns.gd builds a town anew, for one when it's sacked), or null.
func _root_of(id: int) -> Node3D:
	if main == null or main.towns == null or not main.towns.towns.has(id):
		return null
	var n = main.towns.towns[id].get("node")
	return n if is_instance_valid(n) else null


# --- spread (Stronghold, Manor Lords: the fire travels house to house, and the player watches it go) ------

## The house that catches next in a town, and when: the one most exposed to those burning now (near them,
## downwind of them, and the more the readier its roof burns), after a gap that is shorter for a thatch roof
## and longer while a bucket line works.
func _queue_next(id: int) -> void:
	var s: Dictionary = _spreads[id]
	var root := _root_of(id)
	if root == null:
		_spreads.erase(id)
		return
	var homes: Array = root.get_meta("homes", [])
	var sp: Dictionary = knobs().get("spread", {})
	var wind := _drift()
	var wd := Vector2(wind.x, wind.z)
	wd = wd.normalized() if wd.length() > 0.001 else Vector2.ZERO
	var bias := float(sp.get("wind_bias", 0.6))
	var pick := int(s["left"][0])
	var most := -1.0
	for i in s["left"]:
		var p := _home_at(homes[i])
		var exposed := 0.0
		for key in _burning:
			if not String(key).begins_with("%d:" % id):
				continue
			var q := _home_at(homes[int(String(key).get_slice(":", 1))])
			var off := Vector2(p.x - q.x, p.z - q.z)
			var dd := maxf(off.length(), 0.05)
			exposed += (1.0 + bias * off.normalized().dot(wd)) / (dd * dd)
		exposed *= _burns(homes[i])
		if exposed > most:
			most = exposed
			pick = i
	var gap: Array = sp.get("gap_s", [3.0, 12.0])
	var wait := randf_range(float(gap[0]), float(gap[1])) / maxf(_burns(homes[pick]), 0.1) * float(s["pace"])
	wait = clampf(wait, float(gap[0]) * float(s["pace"]), float(gap[1]) * 2.0)
	if _lines.has(id):
		wait *= float((knobs().get("folk", {}) as Dictionary).get("slow", 1.6))
	# A wet town burns slower (the one wetness, weather_fx.gd; data/weather.json fire.slow).
	wait *= 1.0 + WeatherFx.wet * float(preload("res://scripts/data.gd").num("weather", "fire.slow", 1.2))
	s["pick"] = pick
	s["at"] = _clock + wait


## The next house catches when its time comes.
func _spread_tick() -> void:
	for id in _spreads.keys():
		var s: Dictionary = _spreads[id]
		# The town as it stands now: towns.gd builds a sacked town anew, freeing the root the fire began on
		# (batch 7: 178 errors and a fire that stopped at its first house). The fire goes on in the new one:
		# the houses already caught are set alight again there, the rest still to come.
		var root := _root_of(id)
		if root == null:
			_spreads.erase(id)
			continue
		var homes: Array = root.get_meta("homes", [])
		if root != s.get("root"):
			s["root"] = root
			for h in s["lit"]:
				if int(h) < homes.size() and not _burning.has("%d:%d" % [id, int(h)]):
					_alight(root, "%d:%d" % [id, int(h)], homes[int(h)], id)
		if (s["left"] as Array).is_empty() and not _burning.keys().any(func(k): return String(k).begins_with("%d:" % id)):
			_spreads.erase(id)  # every house caught and burnt out
			continue
		if _clock < float(s.get("at", INF)):
			continue
		var pick := int(s["pick"])
		(s["left"] as Array).erase(pick)
		if pick < homes.size() and not _burning.has("%d:%d" % [id, pick]):
			_alight(root, "%d:%d" % [id, pick], homes[pick], id)
			(s["lit"] as Array).append(pick)
		if (s["left"] as Array).is_empty():
			s["at"] = INF  # all caught: kept while they burn, so a rebuild sets them alight again
		else:
			_queue_next(id)


## Still waiting to catch in a spreading fire (the fact may already count it burnt: it isn't charred yet).
func _waiting(id: int, home: int) -> bool:
	return _spreads.has(id) and (_spreads[id]["left"] as Array).has(home)


## Where a house stands (its root's frame).
static func _home_at(h: Array) -> Vector3:
	return h[2] if h.size() >= 3 else h[0]


## How readily a house burns (fire.json spread.burns), by what its kit model's name says it is.
static func _burns(h: Array) -> float:
	var sp: Dictionary = knobs().get("spread", {})
	var burns: Dictionary = sp.get("burns", {})
	var kind := String(h[3]).to_lower() if h.size() >= 4 else ""
	var kinds: Dictionary = sp.get("kinds", {})
	for m in kinds:
		for word in kinds[m]:
			if kind.contains(String(word)):
				return float(burns.get(m, 0.7))
	return float(burns.get("timber", 0.7))


## How many of a town's houses are burning (not yet smouldering): each stands a full smoke column.
func _columns(id: int) -> int:
	var n := 0
	for key in _burning:
		var f: Node3D = _burning[key]
		if String(key).begins_with("%d:" % id) and is_instance_valid(f) and String(f.get_meta("stage", "")) != "smoulder":
			n += 1
	return n


# --- the townsfolk answer a fire (Manor Lords: run from it, or run to the well) --------------------------

## A house catches: the townsfolk near it run (a hostile stimulus on the bus, scene_kinds "fire"), and if
## none is working yet, a bucket line forms from the well to its door.
func _alarm(id: int, root: Node3D, key: String, h: Array) -> void:
	if main.awareness:
		main.awareness.emit("fire", root.to_global(_home_at(h)))
	if not _lines.has(id):
		_line(id, root, key, h)


## Up to folk.line of the townsfolk near a burning house (none who are fleeing, no children) stand in a
## line from the well to its door and pass pails (their minds' fire branch, npc_mind.villager_fire).
func _line(id: int, root: Node3D, key: String, h: Array) -> void:
	var fk: Dictionary = knobs().get("folk", {})
	var n := int(fk.get("line", 6))
	var vill = main.get("villagers")
	if n <= 0 or vill == null or not is_instance_valid(vill):
		return
	var crowd: Array = (vill.crowds as Dictionary).get(id, [])
	var door: Vector3 = root.to_global(Vector3(h[0]))
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = root.to_global(places["well"]) if places.has("well") else root.global_position
	var flee := float(SceneKinds.of("fire")["reach"]) * 0.5  # the ones the alarm sends running
	var within := float(fk.get("pick_within", 4.0))
	var near := []
	for a in crowd:
		if not a.has("mind") or not is_instance_valid(a.get("node")) or not (a["node"] as Node3D).visible:
			continue
		if String(a.get("role", "")) == "child" or String(a.get("age", "")) == "child":
			continue
		var bb: Blackboard = (a["mind"] as BTPlayer).blackboard
		if bb.get_var(&"danger", false, false) or bb.get_var(&"firefight", false, false):
			continue
		var dd := (a["node"] as Node3D).global_position.distance_to(door)
		if dd > flee and dd < within:
			near.append([dd, a])
	if near.is_empty():
		return
	near.sort_custom(func(x, y): return x[0] < y[0])
	var along := Vector3(well.x - door.x, 0, well.z - door.z)
	var from := door + along.normalized() * float(fk.get("clear", 0.3))
	var side := Vector3(-along.z, 0, along.x).normalized() * 0.04
	var folk := []
	for i in mini(n, near.size()):
		var a: Dictionary = near[i][1]
		var bb: Blackboard = (a["mind"] as BTPlayer).blackboard
		bb.set_var(&"bucket_at", from.lerp(well, (i + 0.5) / float(n)) + side * (1.0 if i % 2 == 0 else -1.0))
		bb.set_var(&"fire_at", door)
		bb.set_var(&"firefight", true)
		folk.append(a["mind"])
	_lines[id] = {"key": key, "folk": folk}


## The house a line works at has fallen in: the line breaks up, and forms again at the next house still
## burning in the town, if there is one.
func _release(id: int, key: String) -> void:
	if not _lines.has(id) or String(_lines[id]["key"]) != key:
		return
	for m in _lines[id]["folk"]:
		if is_instance_valid(m):
			(m as BTPlayer).blackboard.set_var(&"firefight", false)
	_lines.erase(id)
	for k in _burning:
		var f: Node3D = _burning[k]
		if String(k).begins_with("%d:" % id) and k != key and is_instance_valid(f) and String(f.get_meta("stage", "")) in ["catch", "burn"]:
			var root: Node3D = f.get_parent()
			var homes: Array = root.get_meta("homes", [])
			var home := int(String(k).get_slice(":", 1))
			if home < homes.size():
				_line(id, root, k, homes[home])
			return


## Which of a town's houses stand burnt (home number -> true): those the fact names (`named`, damage.kindled) and
## those just told it (`told`), then, in the town's fixed `order`, as many more as its burnt `share` counts past
## them. Nothing else: no session memory, so a reload shows the same ruins (tools/ground_truth_probe.gd).
static func burnt_homes(named: Array, told: Array, share: float, order: Array) -> Dictionary:
	var burnt := {}
	for h in named + told:
		if int(h) >= 0 and int(h) < order.size():
			burnt[int(h)] = true
	var n := roundi(share * order.size())
	for h in order:
		if burnt.size() >= n:
			break
		burnt[int(h)] = true
	return burnt


## The houses the fact names burnt in a town (fire arrows, a sack's spread: damage.kindled), as the mirror holds it.
func _kindled_of(id: int) -> Array:
	if main.awareness == null:
		return []
	var d = main.awareness.town(id).get_var(&"damage", {}, false)
	var k = d.get("kindled", []) if d is Dictionary else []
	return k if k is Array else []


## The town's burnt share, as the mirror holds it (the bridge's damage fact).
func _burnt_share(id: int) -> float:
	if main.awareness == null:
		return 0.0
	return float(main.awareness.town(id).get_var(&"burnt", 0.0, false))


## The houses the fact's burnt share means past those it names (kindled): the same every time (by its id).
func _order(id: int, count: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash(id)
	var order := range(count)
	for i in range(count - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	return order


## Once a second: each town's burnt houses follow the fact (charred while it says so, whole again once
## rebuilt), and the smoke and embers follow the wind.
func _process(delta: float) -> void:
	_clock += delta
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if main == null or main.towns == null:
		return
	for key in _burning.keys():
		if not is_instance_valid(_burning[key]):
			_burning.erase(key)  # its town was built anew mid-fire
	_spread_tick()
	for key in _burnt.keys():
		if not is_instance_valid(_burnt[key]["shell"]):
			_burnt.erase(key)  # its town was built anew: charred again below
	for id in main.towns.towns:
		var root: Node3D = main.towns.towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var homes: Array = root.get_meta("homes", [])
		if homes.is_empty():
			continue
		# Burnt: the houses the fact names (kindled, and those just told it), then, by the town's own order, as
		# many more as its burnt share counts past them. The rest stand whole (the realm rebuilt them).
		var named: Array = _kindled_of(id)
		var told: Array = []
		for key in _told.keys():
			if String(key).begins_with("%d:" % id):
				if named.has(int(String(key).get_slice(":", 1))):
					_told.erase(key)  # the mirror has it now
				else:
					told.append(int(String(key).get_slice(":", 1)))
		var burnt := burnt_homes(named, told, _burnt_share(id), _order(id, homes.size()))
		for h in homes.size():
			var key := "%d:%d" % [id, h]
			if _waiting(id, h) or _burning.has(key):
				continue  # its turn to catch hasn't come, or it burns now: as it stands
			if burnt.has(h):
				_char(root, key, homes[h])  # charred while the fact says so
			elif _burnt.has(key):
				_mend(key)
	# Fewer flames and embers on the far fires (data fire.json lod: full to near, down to far_share by far):
	# many houses can burn at once. The smoke keeps whole: it's what's seen across the town.
	var lk: Dictionary = knobs().get("lod", {})
	var cam := get_viewport().get_camera_3d()
	for key in _burning:
		var f: Node3D = _burning[key]
		if not is_instance_valid(f) or cam == null:
			continue
		var dd := cam.global_position.distance_to(f.global_position)
		var lod := lerpf(1.0, float(lk.get("far_share", 0.3)), smoothstep(float(lk.get("near", 8.0)), float(lk.get("far", 30.0)), dd))
		for p in f.get_children():
			if p is GPUParticles3D and p.has_meta("want") and p.get_meta("kind", "") != "smoke":
				p.set_meta("lod", lod)
				_ratio(p, float(p.get_meta("want")))
	var g := _drift()
	for key in _burning:
		var f: Node3D = _burning[key]
		if is_instance_valid(f):
			for p in f.get_children():
				if p is GPUParticles3D and p.has_meta("drift"):
					((p as GPUParticles3D).process_material as ParticleProcessMaterial).gravity = g * float(p.get_meta("drift")) + Vector3(0, float(p.get_meta("lift", 0.0)), 0)


## The wind's push on smoke and embers (world units/s² per unit of drift), from the one wind.
static func _drift() -> Vector3:
	var w: Vector4 = WeatherFx.wind
	return Vector3(w.x, 0, w.z) * (0.25 + 0.75 * w.w)


## A house set alight, in four stages, each a visible change (docs/research/world-and-siege-rules.md, fire
## rule 5; Age of Empires' stepped fire): catching (smoke first, small flames on the roof, the soot creeping
## over it), burning (full flames on the roof, up the walls and out of the front, embers, the tall column, the
## roof falling in), collapse (the roof drops, a burst of sparks, the flames fall back), smouldering (a thin grey
## wisp, the char's embers glowing out); then out, the charred shell left standing.
func _alight(root: Node3D, key: String, h: Array, town: int) -> void:
	var d := knobs()
	var b: Dictionary = _char(root, key, h)
	var box: AABB = b["box"]
	var face: Vector3 = h[1]
	var c := box.get_center()
	var top := box.end.y
	var fire := Node3D.new()
	fire.name = "Burning"
	root.add_child(fire)
	_burning[key] = fire
	# A ruin stays a ruin until the realm rebuilds it (batch 9: it stood whole again by 90 s): the bridge keeps it.
	if not _kindled_of(town).has(int(key.get_slice(":", 1))) and not _told.has(key):
		_told[key] = true
		if main.bridge and main.bridge.has_method("kindled"):
			main.bridge.kindled(town, int(key.get_slice(":", 1)))
	if OS.get_cmdline_user_args().has("--probe"):
		print("FIRE lit %s (burning %d in town %d)" % [key, _columns(town), town])
	var thin := _columns(town) >= int(d.get("columns", 6))  # past the town's full columns: a thin one
	var fk: Dictionary = d.get("flames", {})
	var soft := String(fk.get("look", "soft")) == "soft"  # flipbook flames, a soft body and a hot core (else GDQuest's toon bands)
	var roof := _flames(int(fk.get("amount", 26)), float(fk.get("life", 0.9)), fk.get("size", [0.2, 0.34]), _v2(fk.get("rise", [0.08, 0.18])), Vector3(box.size.x * 0.3, box.size.y * 0.1, box.size.z * 0.3), _flame_material(false), float(fk.get("aspect", 1.6)), float(fk.get("lift", 0.35)), soft)
	roof.position = Vector3(c.x, top - box.size.y * 0.3, c.z)
	fire.add_child(roof)
	var fr: Dictionary = d.get("front", {})
	var front := _flames(int(fr.get("amount", 10)), float(fk.get("life", 0.9)) * 0.8, fr.get("size", [0.09, 0.15]), _v2(fk.get("rise", [0.08, 0.18])) * 0.7, Vector3(box.size.x * 0.25, 0.01, box.size.z * 0.25), _flame_material(false), float(fk.get("aspect", 1.6)), float(fk.get("lift", 0.35)) * 0.5, soft)
	var lateral := Vector3(box.size.x, 0, box.size.z).length() * 0.3
	front.position = Vector3(c.x, box.position.y + box.size.y * float(fr.get("height", 0.35)), c.z) + Vector3(face.x, 0, face.z).normalized() * lateral
	fire.add_child(front)
	# Up the walls: tongues from the walls' upper half all round, licking up into the roof (Stronghold's
	# and Manor Lords' burning houses: the walls burn, not only the roof).
	var wk: Dictionary = d.get("walls", {})
	if int(wk.get("amount", 0)) > 0:
		var walls := _flames(int(wk.get("amount", 18)), float(fk.get("life", 0.9)), wk.get("size", [0.14, 0.26]), _v2(fk.get("rise", [0.08, 0.18])), Vector3(box.size.x * 0.5, box.size.y * 0.2, box.size.z * 0.5), _flame_material(false), float(fk.get("aspect", 1.6)), float(fk.get("lift", 0.35)), soft)
		walls.position = Vector3(c.x, box.position.y + box.size.y * float(wk.get("height", 0.55)), c.z)
		fire.add_child(walls)
	var ek: Dictionary = d.get("embers", {})
	var embers := _embers(ek, Vector3(box.size.x * 0.3, 0.02, box.size.z * 0.3))
	embers.position = Vector3(c.x, top, c.z)
	fire.add_child(embers)
	var smoke := _smoke(d.get("smoke", {}))
	smoke.set_meta("kind", "smoke")
	smoke.position = Vector3(c.x, top + 0.05, c.z)
	fire.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = float(d.get("light_energy", 1.4))
	light.omni_range = float(d.get("light_range", 1.1))
	light.light_cull_mask = 0xFFFFF & ~SMOKE_LAYER
	light.position = Vector3(c.x, box.position.y + box.size.y * 0.5, c.z) + Vector3(face.x, 0, face.z).normalized() * lateral * 1.6
	fire.add_child(light)
	var st: Dictionary = d.get("stages", {})
	var r := RandomNumberGenerator.new()
	r.seed = hash(key + "stages")
	var catch_s := float(st.get("catch_s", 5.0))
	var span: Array = st.get("burn_s", [25.0, 50.0])
	var burn_s := r.randf_range(float(span[0]), float(span[1]))
	var collapse_s := float(st.get("collapse_s", 2.5))
	var smoulder_s := float(st.get("smoulder_s", 25.0))
	var column := 0.35 if thin else 1.0
	var energy := light.light_energy
	# The fire's light flickers on the walls and the ground round it (never steady), at the stage's strength.
	light.set_meta("e", energy)
	var flick := light.create_tween().set_loops()
	flick.tween_method(func(t: float):
		light.light_energy = float(light.get_meta("e", energy)) * (0.84 + 0.1 * sin(t * 21.0) + 0.06 * sin(t * 47.0 + 1.3)), 0.0, TAU, 2.9)
	var flames := fire.get_children().filter(func(n): return n is GPUParticles3D and n != embers and n != smoke)
	var shell: Array = (b["shell"] as Node).get_children().filter(func(n): return n is GeometryInstance3D)
	var roof_in := func(v: float):  # 0 whole .. 1 fallen in as far as it will
		for mi in shell:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter("cut", lerpf(1.0, float(mi.get_meta("cut", 1.0)), v))
	var shade := func(param: String, v: float):
		for mi in shell:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter(param, v)
	# Catching: smoke first, a few small flames on the roof, the house not yet black.
	fire.set_meta("stage", "catch")
	for p in flames:
		_ratio(p, float(st.get("catch_flames", 0.25)) if p == roof else 0.0)
	_ratio(embers, 0.2)
	_ratio(smoke, column * 0.7)
	light.set_meta("e", energy * 0.3)
	roof_in.call(0.0)
	shade.call("sooted", 0.0)
	shade.call("glow", 0.0)
	_alarm(town, root, key, h)
	var tw := fire.create_tween()
	tw.tween_method(func(v: float): shade.call("sooted", v * 0.4), 0.0, 1.0, catch_s)
	# Burning: everything at full, the soot over it all, the roof sagging in.
	tw.tween_callback(func():
		fire.set_meta("stage", "burn")
		for p in flames:
			_ratio(p, 1.0)
		_ratio(embers, 1.0)
		_ratio(smoke, column)
		light.set_meta("e", energy)
		shade.call("glow", 1.0))
	tw.tween_method(func(v: float):
		shade.call("sooted", lerpf(0.4, 1.0, v))
		roof_in.call(v * 0.4), 0.0, 1.0, burn_s)
	# Collapse: the roof drops, sparks burst up, the flames fall back.
	tw.tween_callback(func():
		fire.set_meta("stage", "collapse")
		var burst := _embers(d.get("burst", {}), Vector3(box.size.x * 0.35, 0.02, box.size.z * 0.35))
		burst.one_shot = true
		burst.explosiveness = 0.9
		burst.position = Vector3(c.x, top - box.size.y * 0.2, c.z)
		fire.add_child(burst)
		burst.emitting = true
		for p in flames:
			_ratio(p, float(st.get("collapse_flames", 0.35)))
		light.set_meta("e", energy * 0.5)
		_release(town, key))
	tw.tween_method(func(v: float): roof_in.call(lerpf(0.4, 1.0, v)), 0.0, 1.0, collapse_s)
	# Smouldering: the flames out, a thin grey wisp, the char's embers glowing out.
	tw.tween_callback(func():
		fire.set_meta("stage", "smoulder")
		for p in flames:
			(p as GPUParticles3D).emitting = false
		embers.emitting = false
		light.queue_free()
		_ratio(smoke, float(st.get("smoulder_smoke", 0.3)))
		var pm := smoke.process_material as ParticleProcessMaterial
		pm.scale_min *= 0.5
		pm.scale_max *= 0.5
		var tint := float(st.get("smoulder_tint", 2.2))
		pm.color = Color(tint, tint, tint * 0.97))
	tw.tween_method(func(v: float): shade.call("glow", v), 1.0, 0.0, smoulder_s)
	# Out: the smoke thins away; the shell stays while the realm's fact says so.
	tw.tween_callback(func(): smoke.emitting = false)
	tw.tween_interval(smoke.lifetime)
	tw.tween_callback(func():
		_burning.erase(key)
		fire.queue_free())


## A house charred: its kit batches' copy of it hidden, a charred shell of the same meshes in its place
## (part of the roof gone), a scorch under it. Kept in _burnt until mended.
func _char(root: Node3D, key: String, h: Array) -> Dictionary:
	if _burnt.has(key):
		return _burnt[key]
	var d := knobs()
	var shell := Node3D.new()
	shell.name = "Burnt"
	root.add_child(shell)
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	# How far its roof falls in; one burnt house in three loses its roof outright (fire rule 6).
	var ck: Dictionary = d.get("char", {})
	var collapse: Array = ck.get("roofless" if r.randf() < float(ck.get("roofless_share", 0.0)) else "collapse", [0.45, 0.7])
	var cut := r.randf_range(float(collapse[0]), float(collapse[1]))
	var hidden := []
	var box := AABB()
	if h.size() >= 5:
		for g in root.get_children():
			if not (g is MultiMeshInstance3D and String(g.get_meta("kind", "")) == String(h[3])):
				continue
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			var idx := int(h[4])
			if mm == null or mm.mesh == null or idx >= mm.instance_count:
				continue
			var t := mm.get_instance_transform(idx)
			hidden.append([mm, idx, t])
			mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), t.origin))
			var mi := MeshInstance3D.new()
			mi.mesh = mm.mesh
			mi.transform = (g as Node3D).transform * t
			for s in mm.mesh.get_surface_count():
				mi.set_surface_override_material(s, _char_material(mm.mesh.surface_get_material(s)))
			var ab := mm.mesh.get_aabb()
			mi.set_instance_shader_parameter("lo", ab.position.y)
			mi.set_instance_shader_parameter("hi", ab.end.y)
			mi.set_instance_shader_parameter("cut", cut)
			mi.set_meta("cut", cut)
			mi.visibility_range_end = (g as GeometryInstance3D).visibility_range_end
			shell.add_child(mi)
			var wb: AABB = mi.transform * ab
			box = wb if box.size == Vector3.ZERO else box.merge(wb)
	if box.size == Vector3.ZERO:  # a house we can't find in the batches: burn where it stands
		var face: Vector3 = h[1]
		var at: Vector3 = (h[2] if h.size() >= 3 else Vector3(h[0]) - face * 0.15)
		box = AABB(at - Vector3(0.12, 0.0, 0.12), Vector3(0.24, 0.3, 0.24))
	var scorch := Decal.new()
	scorch.texture_albedo = _scorch()
	var sz := float(d.get("scorch_size", 1.7)) * maxf(box.size.x, box.size.z)
	scorch.size = Vector3(sz, 0.3, sz)
	scorch.rotation.y = r.randf() * TAU
	scorch.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	scorch.distance_fade_enabled = true  # a Decal has no visibility range; it fades by distance instead
	scorch.distance_fade_begin = FAR * 0.8
	scorch.distance_fade_length = FAR * 0.2
	shell.add_child(scorch)
	_burnt[key] = {"shell": shell, "hidden": hidden, "box": box}
	return _burnt[key]


## A burnt house rebuilt (the fact says so): the shell gone, the house back in its batch.
func _mend(key: String) -> void:
	var b: Dictionary = _burnt[key]
	for e in b["hidden"]:
		(e[0] as MultiMesh).set_instance_transform(int(e[1]), e[2])
	if is_instance_valid(b["shell"]):
		b["shell"].queue_free()
	_burnt.erase(key)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Flames: tall billboards of the flame shader, born small, swelling, then eaten away from the edges as
## they rise (alpha erosion), each a random frame of the tongues.
static func _flames(amount: int, life: float, size: Array, rise: Vector2, box: Vector3, mat: Material, aspect := 1.6, lift := 0.35, soft := false) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 6.0
	pm.initial_velocity_min = rise.x
	pm.initial_velocity_max = rise.y
	pm.gravity = Vector3(0, lift, 0)
	pm.scale_min = float(size[0])
	pm.scale_max = float(size[1])
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.45))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.7))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.3)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	if soft:
		# Each flame plays through the tongues as it rises (a flipbook), white-yellow at its foot, orange, then
		# deep red as it thins away; HDR, so the hot part glows under the grade.
		pm.anim_offset_max = 0.3
		pm.anim_speed_min = 1.0
		pm.anim_speed_max = 1.0
		pm.color_ramp = _ramp(knobs().get("soft", {}).get("body", []), [[1.0, 0.8, 0.4, 0.0], [1.6, 0.85, 0.3, 0.9], [1.3, 0.42, 0.08, 0.75], [0.5, 0.1, 0.03, 0.0]])
		mat = _soft_material(false, aspect)
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.randomness = 0.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, aspect)
	q.center_offset = Vector3(0, aspect * 0.35, 0)  # the flame's foot at its particle: it rises from the roof
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-box - Vector3(0.6, 0.2, 0.6), box * 2.0 + Vector3(1.2, 1.6, 1.2))
	p.visibility_range_end = FAR
	if soft:
		# The hot core: smaller, brighter, added on (light adds to light), inside the body.
		var core := GPUParticles3D.new()
		var cm: ParticleProcessMaterial = pm.duplicate()
		var ck: Dictionary = knobs().get("soft", {})
		cm.scale_min = pm.scale_min * float(ck.get("core_size", 0.55))
		cm.scale_max = pm.scale_max * float(ck.get("core_size", 0.55))
		cm.color_ramp = _ramp(ck.get("core", []), [[1.0, 0.9, 0.6, 0.0], [1.5, 1.15, 0.6, 0.8], [1.2, 0.55, 0.15, 0.4], [0.6, 0.15, 0.02, 0.0]])
		core.amount = maxi(1, int(amount * float(ck.get("core_share", 0.6))))
		core.lifetime = life * 0.8
		core.randomness = 0.5
		core.process_material = cm
		var cq := QuadMesh.new()
		cq.size = Vector2(1.0, aspect)
		cq.center_offset = Vector3(0, aspect * 0.35, 0)
		cq.material = _soft_material(true, aspect)
		core.draw_pass_1 = cq
		core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		core.visibility_aabb = p.visibility_aabb
		core.visibility_range_end = FAR
		core.name = "Core"
		p.add_child(core)
	return p


## A colour ramp from rows of [r, g, b, a] spread evenly over a particle's life (data, else `fallback`).
static func _ramp(rows: Array, fallback: Array) -> GradientTexture1D:
	var use: Array = rows if rows.size() >= 2 else fallback
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for i in use.size():
		var c: Array = use[i]
		offs.append(i / float(use.size() - 1))
		cols.append(Color(float(c[0]), float(c[1]), float(c[2]), float(c[3])))
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.use_hdr = true
	return t


## The soft flames' material: Kenney's six flame tongues as one flipbook, soft-edged where they meet a wall or
## a roof (proximity fade), unshaded (they give light, they don't take it); the core added on.
static func _soft_material(core: bool, aspect: float) -> StandardMaterial3D:
	var key := "soft_core" if core else "soft_body"
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _strip(["flame_01", "flame_02", "flame_03", "flame_04", "flame_05", "flame_06"], 96, int(96 * aspect), false)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if core else BaseMaterial3D.BLEND_MODE_MIX
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 6
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = float((knobs().get("soft", {}) as Dictionary).get("soft_edge", 0.08))
	m.disable_receive_shadows = true
	_cache[key] = m
	return m


## A burning house's emitter at `v` of its stage's strength, times its distance's share (the LOD), and its core.
static func _ratio(p: GPUParticles3D, v: float) -> void:
	p.set_meta("want", v)
	p.amount_ratio = v * float(p.get_meta("lod", 1.0))
	for c in p.get_children():
		if c is GPUParticles3D:
			(c as GPUParticles3D).amount_ratio = p.amount_ratio


static func _embers(k: Dictionary, box: Vector3) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 25.0
	var rise: Array = k.get("rise", [0.25, 0.5])
	pm.initial_velocity_min = float(rise[0])
	pm.initial_velocity_max = float(rise[1])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5
	pm.gravity = _drift() * 0.5
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = int(k.get("amount", 14))
	p.lifetime = float(k.get("life", 2.2))
	p.process_material = pm
	p.set_meta("drift", 0.5)
	var q := QuadMesh.new()
	var s := float(k.get("size", 0.014))
	q.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://scripts/towns.gd").soft_dot()  # load, not preload: towns.gd preloads this file
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
	p.visibility_range_end = FAR
	return p


## The smoke column: Kenney's billowing smoke sprites, dark and lit by the sun (not by the fire), swelling
## as they rise and drifting downwind.
static func _smoke(k: Dictionary) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 10.0
	var rise: Array = k.get("rise", [0.12, 0.22])
	pm.initial_velocity_min = float(rise[0])
	pm.initial_velocity_max = float(rise[1])
	var drift := float(k.get("drift", 0.18))
	pm.gravity = _drift() * drift
	pm.damping_min = 0.02
	pm.damping_max = 0.05
	var sz: Array = k.get("size", [0.35, 0.8])
	pm.scale_min = float(sz[0])
	pm.scale_max = float(sz[1])
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0 / float(k.get("grow", 3.0))))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -8.0
	pm.angular_velocity_max = 8.0
	var c: Array = k.get("colour", [0.12, 0.11, 0.1, 0.85])
	var col := Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), col, Color(col.lightened(0.25), col.a * 0.7), Color(col.lightened(0.4), 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	var p := GPUParticles3D.new()
	p.amount = int(k.get("amount", 26))
	p.lifetime = float(k.get("life", 7.0))
	p.preprocess = 2.0
	p.process_material = pm
	p.set_meta("drift", drift)
	p.layers = SMOKE_LAYER
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _smoke_material()
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A column three houses tall and more, seen from as far as the town is (fire rule 1: the far read).
	p.visibility_aabb = AABB(Vector3(-6, -0.5, -6), Vector3(12, 10, 12))
	p.visibility_range_end = float(k.get("far", FAR + 20.0))
	return p


static func _smoke_material() -> StandardMaterial3D:
	if _cache.has("smoke"):
		return _cache["smoke"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _strip(["smoke_04", "smoke_05", "smoke_07", "smoke_08"], 128, 128, false)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.15
	_cache["smoke"] = m
	return m


## The flame material: hearth (small flames, finer noise) or house.
static func _flame_material(small: bool) -> ShaderMaterial:
	var key := "flame_small" if small else "flame"
	if _cache.has(key):
		return _cache[key]
	var d := knobs()
	var fk: Dictionary = d.get("flames", {})
	var ck: Dictionary = d.get("colours", {})
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter("texture_mask", _strip(["flame_05", "flame_06", "flame_05", "flame_06"], 128, int(128 * float(fk.get("aspect", 1.6))), true))
	m.set_shader_parameter("noise_texture", _noise())
	m.set_shader_parameter("frames", 4)
	m.set_shader_parameter("texture_scale", float(fk.get("noise_scale", 7.0)) * (3.0 if small else 1.0))
	m.set_shader_parameter("lean", float(fk.get("lean", 0.7)))
	for band in ["core", "body", "edge"]:
		var a: Array = ck.get(band, [1, 1, 1])
		m.set_shader_parameter(band, Color(float(a[0]), float(a[1]), float(a[2])))
	m.set_shader_parameter("brightness", float(ck.get("brightness", 1.25)))
	_cache[key] = m
	return m


## The charred copy of a house material (its texture and colour kept under the soot).
static func _char_material(src: Material) -> ShaderMaterial:
	if _cache.has(src):
		return _cache[src]
	var m := ShaderMaterial.new()
	m.shader = CHAR_SHADER
	m.set_shader_parameter("noise_texture", _noise())
	m.set_shader_parameter("ember_power", float((knobs().get("char", {}) as Dictionary).get("ember", 1.4)))
	var tex: Texture2D = null
	var col := Color.WHITE
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
		col = (src as BaseMaterial3D).albedo_color
	elif src is ShaderMaterial:  # a kit material already in its holder's colours (team_colour.gd)
		var t = (src as ShaderMaterial).get_shader_parameter("albedo_tex")
		tex = t if t is Texture2D else null
		var a = (src as ShaderMaterial).get_shader_parameter("albedo")
		col = a if a is Color else Color.WHITE
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("has_albedo_tex", tex != null)
	m.set_shader_parameter("albedo", col)
	_cache[src] = m
	return m


static func _noise() -> Texture2D:
	if not _cache.has("noise"):
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 3
		n.frequency = 0.02
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 128
		t.height = 128
		_cache["noise"] = t
	return _cache["noise"]


## Kenney's sprites (black backgrounds: brightness is the shape) side by side as one flipbook strip, each
## cropped to its shape and fitted to w x h; the second half mirrored for variety (`mirror`). Alpha from
## brightness, colour white (the shader or the particle colour gives it).
static func _strip(names: Array, w: int, h: int, mirror: bool) -> Texture2D:
	var key := "strip:" + ",".join(names)
	if _cache.has(key):
		return _cache[key]
	var out := Image.create_empty(w * names.size(), h, false, Image.FORMAT_RGBA8)
	for i in names.size():
		var tex: Texture2D = load(DIR + String(names[i]) + ".png")
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(128, 128)
		var used := _bright_rect(img)
		var part := img.get_region(used)
		part.resize(w, h)
		if mirror and i >= names.size() / 2:
			part.flip_x()
		for y in h:
			for x in w:
				var v := part.get_pixel(x, y).get_luminance()
				out.set_pixel(i * w + x, y, Color(1, 1, 1, v))
	out.generate_mipmaps()
	var t := ImageTexture.create_from_image(out)
	_cache[key] = t
	return t


## Where a black-backed sprite's shape lies (brighter than a trace), a little padded.
static func _bright_rect(img: Image) -> Rect2i:
	var lo := Vector2i(img.get_width(), img.get_height())
	var hi := Vector2i(0, 0)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).get_luminance() > 0.04:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x <= lo.x or hi.y <= lo.y:
		return Rect2i(Vector2i.ZERO, img.get_size())
	return Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(5, 5)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))


## The scorch under a burnt house: Kenney's scorch, black, its brightness the soot's reach.
static func _scorch() -> Texture2D:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var img: Image = (load(DIR + "scorch_03.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 256)
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).get_luminance()
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, clampf(v * 1.6, 0.0, 0.92)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["scorch"] = t
	return t
