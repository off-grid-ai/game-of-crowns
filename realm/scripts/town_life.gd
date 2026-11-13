extends RefCounted
const Units := preload("res://scripts/world_units.gd")  # the world's one scale (Units.M)
const Particles := preload("res://scripts/particles.gd")  # smoke and fire on the GPU
## The life director: turns what Freeciv says a town is doing into something you
## can see. Construction rises with its real progress; recruits drill on the
## square while troops train; hunger browns the fields and queues people at the
## keep; celebrations light a bonfire; unrest sets roofs smoking.

const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const S := Units.M
const Real = preload("res://scripts/realistic.gd")

var terrain: Node3D
var towns_node: Node3D  # towns.gd, for its baked building meshes

var _person := CapsuleMesh.new()
var _head := SphereMesh.new()
var _pole := CylinderMesh.new()
var _skin := StandardMaterial3D.new()
var _wood := StandardMaterial3D.new()
var _cloth := {}


func _init() -> void:
	_person.radius = 0.028
	_person.height = 0.15
	_head.radius = 0.022
	_head.height = 0.044
	_pole.top_radius = 0.008
	_pole.bottom_radius = 0.008
	_skin.albedo_color = Color(0.82, 0.66, 0.54)
	_wood.albedo_color = Color(0.45, 0.32, 0.2)
	_wood.roughness = 0.9


## The towns whose scene folk (builders, stall keepers and buyers, recruits)
## have a mind on LimboAI (npc_mind.gd): activities made of steps, never one
## move held. Empty: off, and everyone behaves exactly as before. (Town ids.)
const LIMBO_TOWNS: Array[int] = []
var _town_on := false  # this town's scenes run the job machine
var _town_id := -1  # the town being dressed: its people join its scope (awareness.gd)
var _house_col := Color(0.55, 0.16, 0.12)  # its holder's colour: the guards' cloth


## Towns switched on for a film: --limbo=246,250 on the command line.
static func _limbo_args() -> Array[int]:
	var out: Array[int] = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--limbo=") and a != "--limbo=all":
			for t in a.substr(8).split(","):
				out.append(int(t))
	return out


## Whether a town's scene people have minds (LimboAI); villagers always do (villagers.gd,
## integration audit #1: the old rules' day is gone). Every town has them by default (2026-11-11,
## after Mac's playtest: Crowford on the old rules was one knot round a cold fire
## while Kingsmere, on minds, read as a town). Minds cost only where townsfolk
## are drawn, near the camera. --limbo=none turns them off everywhere (the old
## rules); --limbo=<ids> keeps them to those towns, for a film or an A/B.
const LIMBO_ALL := true
static func minds_on(town: int) -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--limbo=none"):
		return false
	var only := _limbo_args()
	if not only.is_empty():
		return only.has(town) or LIMBO_TOWNS.has(town)
	return LIMBO_ALL or args.has("--limbo=all") or LIMBO_TOWNS.has(town)


func update(root: Node3D, c: Dictionary, house: Dictionary) -> void:
	_town_on = minds_on(int(c.get("id", -1)))
	_town_id = int(c.get("id", -1))
	# Its people dressed as its rank and holder dress them (people.gd cloth_pick).
	_people.dress_for(String(root.get_meta("rank", "town")), Color.from_string(String(house.get("color", "")), Color(0, 0, 0, 0)), bool(c.get("grief", false)))
	# Freeciv's own word that the town starved this season. An empty food store
	# alone isn't hunger: a town that just grew, or holds steady, sits at zero.
	var hungry: bool = c.get("famine", false)
	var kind := String(c.get("buildingKind", ""))
	var building := String(c.get("building", ""))
	var progress := float(c.get("progress", 0.0))
	var sig := "%s|%s|%s|%s|%s|%s|%s|%s|%s" % [kind, building, hungry, c.get("celebrating", false), c.get("disorder", false), c.get("atWar", false), c.get("grief", false), c.get("prosperity", false), c.get("grasping", false)]
	sig += "|%s" % c.get("plague", false)  # a sick town's life changes (town_scenes.json plague)
	# The working buildings' life changes with a levy and a low granary too, and when the town agent lists its buildings.
	sig += "|%s|%s|%d|%s" % [c.get("granaryLow", false), "levy" in Works.states(c, _town_id), hash(root.get_meta("works", {})), (c.get("ruling") as Dictionary).get("kind", "") if c.get("ruling") is Dictionary else ""]
	# The town dressed in what we own, once (dressing.gd; --dressing=on): gear at the trades' doors,
	# planters by house doors, bushes, flowers and rocks between the houses.
	if Dressing.on() and root.get_node_or_null("Dressing") == null:
		var at := root.position
		Dressing.dress(root, func(q: Vector3) -> float: return _y(at, q), func(q: Vector3) -> bool: return terrain.is_land(at.x + q.x, at.z + q.z), int(c.get("id", 0)))
	var life: Node3D = root.get_node_or_null("Life")
	if life and life.get_meta("sig", "") == sig:
		# Only the work moved on: the site grows where it stands, and the
		# townsfolk carry on, rather than the whole scene being rebuilt.
		var site: Node3D = life.get_node_or_null("Site")
		if site:
			_grow(site, clampf(progress, 0.08, 1.0))
		# A neighbour's plot may have been levelled since: everyone keeps their feet on it.
		_reground(life, root.position)
		if kind == "Building" or kind == "UnitType":
			life.set_meta("doing", doing_line(kind, building, progress))
		return
	if life:
		life.free()
	life = Node3D.new()
	life.name = "Life"
	life.set_meta("sig", sig)
	life.set_meta("standing", PackedVector2Array())
	root.add_child(life)
	var center := root.position
	var color := Color.from_string(String(house.get("color", "#888888")), Color.GRAY)
	_house_col = Color.from_string(String(house.get("color", "#8a2a1e")), Color(0.55, 0.16, 0.12))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(c["id"])

	_fields(root, hungry)
	if kind == "Building" and building != "" and building != "Coinage":
		_construction(root, life, center, building, progress, rng, int(c["size"]))
	elif kind == "UnitType" and building != "" and not building in Awareness.civilian:  # a soldier's training, not a civilian's (bridge campaigns.js CIVILIAN)
		_drill(root, life, center, progress, color, building)
	var states := Works.states(c, _town_id)  # riot, grasping and a rising's side among them (the store's facts)
	life.set_meta("states", states)
	life.set_meta("size", int(c.get("size", 1)))
	life.set_meta("town_id", _town_id)
	life.set_meta("house", house)
	life.set_meta("dress", [String(root.get_meta("rank", "town")), Color.from_string(String(house.get("color", "")), Color(0, 0, 0, 0)), bool(c.get("grief", false))])
	root.set_meta("keepers", {})
	_dress(root, life, center, c, rng, house)
	_works(root, life, center, c, rng)
	# What stands so far is the town's working life (its buildings' people, a site's builders, the drill); the
	# director casts every scene's people, by the rows of realm/data/town_scenes.json.
	for n in life.get_children():
		if n.has_meta("role"):
			n.set_meta("works", true)
	if director:
		director.stage(root, life, c, states, self)
	_near_only(life)
	_pin(life, center)


const Heraldry := preload("res://scripts/heraldry.gd")
const STANDARD_TALL := 0.45  # a planted standard, about 3.7 m: over every head in the street (scenes.gd PLANTED)


## The watch stand guard with sword and shield in hand (weapons.gd), never empty-handed.
func _watch(g: Node3D) -> void:
	preload("res://scripts/weapons.gd").arm(g, "sword", true)


func _y(center: Vector3, off: Vector3) -> float:
	return terrain.height_at(center.x + off.x, center.z + off.z) - center.y


static var ROOM: float = 0.11 * preload("res://scripts/data.gd").num("people", "readable", 1.0)  # world units between two people standing (about 0.9 m, at their drawn size): shoulders never meet
static var KEEPER_BACK: float = preload("res://scripts/data.gd").num("town_scenes", "life.keeper_back", 0.07)  # a stall keeper stands this far behind the counter's back edge (about half a metre)
static var LANE: float = preload("res://scripts/data.gd").num("town_scenes", "life.lane", 0.06)  # past a road's verge, ground the travellers on it keep: nobody stands there
static var HEART: float = preload("res://scripts/data.gd").num("town_scenes", "life.heart", 0.2)  # about 1.7 m round a town's heart, where every road's travellers come through and wait


## Whether `world` is on a road's lane through the town (roads.gd: a road or
## track, and LANE past its verge) or at the town's heart, where travellers
## from every road meet: no one claims, steps or stands there to be walked through.
static func on_lane(root: Node3D, world: Vector3) -> bool:
	if root == null or not root.is_inside_tree():
		return false
	if Vector2(world.x - root.global_position.x, world.z - root.global_position.z).length() < HEART:
		return true
	var holder := root.get_parent().get_parent() if root.get_parent() else null  # the towns' owner (main.gd), which keeps the roads
	var roads = holder.get("roads") if holder else null
	if roads != null and roads.has_method("in_setts") and roads.in_setts(world):
		return false  # the square's setts are its people's ground; a road's path across them keeps only the heart clear
	return roads != null and roads.has_method("on_path") and roads.on_path(world, LANE)
## The way a camera faces as it comes down into a town (camera_rig.frame_town
## stands it at yaw 35 degrees, looking back at the heart): the half of the
## square it sees first. Dressing that tells the town's news goes there.
const SEEN := Vector3(-0.5736, 0, -0.8192)
static var CLEAR: float = 0.05 * preload("res://scripts/data.gd").num("people", "readable", 1.0)  # how far a person keeps off a wall or a fence


## Everything that stands in the town, town-local: read off what is set down there (nav_ground.gd: its buildings,
## walls, fences, stalls, carts, tables, the life's props), the outlines its walk map is cut from, and each fire's
## ring and the step of heat past it (the life's "fires").
func _blocked(root: Node3D, life: Node3D) -> Array:
	var out: Array = NavGround.all(root, terrain)
	for f in life.get_meta("fires", []):
		out.append(_rect(Vector3(f[0].x, 0, f[0].y), Vector2(f[1], f[1]) * 2.0, 0.0))
	return out


## True when a person can stand at `p` (town-local): on land, clear of every
## footprint, and a shoulder's width from everyone already placed.
func _open(center: Vector3, p: Vector3, walls: Array, taken: PackedVector2Array) -> bool:
	if not terrain.is_land(center.x + p.x, center.z + p.z):
		return false
	var q := Vector2(p.x, p.z)
	for t in taken:
		if q.distance_to(t) < ROOM:
			return false
	for fp: PackedVector2Array in walls:
		if q.distance_to(fp[0]) > 3.0:
			continue  # far off: no building is that big
		if Geometry2D.is_point_in_polygon(q, fp):
			return false
		for i in fp.size():
			if q.distance_to(Geometry2D.get_closest_point_to_segment(q, fp[i], fp[(i + 1) % fp.size()])) < CLEAR:
				return false
	return true


## The nearest open spot to `want` (town-local), searching outward in rings;
## NAN in x when there is none within reach, and that person isn't placed.
func _spot(center: Vector3, want: Vector3, walls: Array, taken: PackedVector2Array, reach := 0.4, lanes: Node3D = null) -> Vector3:
	var r := 0.0
	while r <= reach:
		var n := 1 if r == 0.0 else int(TAU * r / 0.05)
		for i in n:
			var a := TAU * i / n
			var p := want + Vector3(cos(a), 0, sin(a)) * r
			if _open(center, p, walls, taken) and (lanes == null or not on_lane(lanes, center + p)):
				p.y = _y(center, p)
				return p
		r += 0.05
	return Vector3(NAN, 0, 0)


## Places a townsperson at the nearest open spot to `want` and keeps them in
## the life's list of who stands where; null when there's no room.
## inside: they work inside a building's own footprint (the smiths at the forge's anvil and bellows, on its
## paved yard): no building's walls keep them out, only the others standing and the road's lanes.
func _stand(root: Node3D, life: Node3D, center: Vector3, want: Vector3, role: String, anim: String, seed: int, tint := Color.WHITE, reach := 0.4, post := "", inside := false) -> Node3D:
	var taken: PackedVector2Array = life.get_meta("standing")
	var p := _spot(center, want, [] if inside else _blocked(root, life), taken, reach, root)  # a person: never on a road's lane
	if is_nan(p.x):
		return null
	taken.append(Vector2(p.x, p.z))
	life.set_meta("standing", taken)
	return _townsperson(life, p, role, anim, seed, tint, post)


## Remembers how high each thing stands above the ground under it, so it can
## be set back on the ground if that ground is levelled later.
func _pin(life: Node3D, center: Vector3) -> void:
	for n in life.get_children():
		if n is Node3D:
			n.set_meta("lift", n.position.y - _y(center, n.position))


func _reground(life: Node3D, center: Vector3) -> void:
	for n in life.get_children():
		if n is Node3D and n.has_meta("lift"):
			n.position.y = _y(center, n.position) + float(n.get_meta("lift"))


var _people = preload("res://scripts/people.gd").new()


## A drill is a short set, not a loop: each recruit does three or four moves
## (cuts and thrusts, or draw, aim and loose), then stands easy for good, and
## after a season the rank falls out. Nobody blocks (a crouch reads as a fight).
const DRILL_SWORD := ["SS_Slash_1", "SS_Slash_4", "Spear_Thrust", "SS_Attack_4"]  # cuts whose feet hold standing (NPC perf, clip_skate_probe 2026-11-11: Sword_Attack, SS_Attack_3, SS_Slash_2 skid 37-59% and end ~50 cm ahead)
const DRILL_BOW := ["Bow_Draw", "Bow_Aim", "Bow_Shoot"]

func _drill_routine(s: Node3D, bow: bool, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var moves: Array = DRILL_BOW if bow else DRILL_SWORD
	var t := Timer.new()
	t.one_shot = true
	s.add_child(t)
	var left := [3 + rng.randi() % 2]
	var i := [rng.randi() % moves.size()]
	var once := preload("res://scripts/motion.gd")
	var next := func() -> void:
		if not is_instance_valid(s):
			return
		if left[0] <= 0:
			_people.play(s, "Idle")  # stand easy, for good
			return
		left[0] -= 1
		i[0] = (i[0] + 1) % moves.size() if bow else rng.randi() % moves.size()
		var move: String = moves[i[0]]
		if once.is_once(move):
			_people.repeat(s, move)
		else:
			_people.play(s, move)
		t.start(rng.randf_range(2.2, 3.6))
	t.timeout.connect(next)
	t.start(rng.randf_range(0.5, 3.0))
	# After a season the rank falls out.
	var out := Timer.new()
	out.one_shot = true
	s.add_child(out)
	out.timeout.connect(func():
		if is_instance_valid(s):
			s.queue_free())
	out.start(maxf(Awareness.season_seconds, 1.0) + rng.randf_range(0.0, 4.0))  # one season of the realm's, then the recruits fall out


## post: the work they're there for (the cast's smith works the forge: people.gd cast_for_post); age: "child" or
## "elder" when the scene wants one (the children's chase), else the role's own mix.
func _townsperson(parent: Node3D, pos: Vector3, role: String, anim: String, seed: int, tint := Color.WHITE, post := "", age := "", sex := "") -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var cast_body: String = _people.cast_for_post(post)
	var p: Node3D = _people.make_body(rng, cast_body, tint, "adult", "average", role) if cast_body != "" else _people.make(rng, role, tint, age if age != "" else ("adult" if role == "soldier" else ""), "", sex)
	p.set_meta("role", role)  # who they are in the scene (a film can find a drill's soldiers)
	p.position = pos
	parent.add_child(p)
	# A drill is practised over and over: a one-off move (a cut, a draw of the
	# bow) repeats rather than playing once and standing down.
	if preload("res://scripts/motion.gd").is_once(anim):
		_people.repeat(p, anim)
	else:
		_people.play(p, anim)
	return p


## Gives a scene's townsperson a mind (npc_mind.gd, LimboAI) when this town is
## on the switch: activities of their post instead of one move held. Returns
## false (and changes nothing) when the town is off.
func _mind(p: Node3D, post: String, center: Vector3) -> bool:
	if not _town_on or p == null:
		return false
	return preload("res://scripts/npc_mind.gd").give(p, post, func(q: Vector3) -> float: return _y(center, q), int(p.get_instance_id()), [], _town_id)


func _figure(parent: Node3D, pos: Vector3, mat: Material) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var body := MeshInstance3D.new()
	body.mesh = _person
	body.material_override = mat
	body.position.y = 0.075
	n.add_child(body)
	var head := MeshInstance3D.new()
	head.mesh = _head
	head.material_override = _skin
	head.position.y = 0.17
	n.add_child(head)
	parent.add_child(n)
	return n


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _cloth.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		_cloth[key] = m
	return _cloth[key]


## Fields ripen or wither with the town's food.
func _fields(root: Node3D, hungry: bool) -> void:
	var fields: Node3D = root.get_node_or_null("Fields")
	if fields == null:
		return
	# A blighted-field texture replaces the crop when the town starves; until
	# that art exists, the crop is tinted the colour of dead earth.
	var dead := "res://assets/ground/field-dead.jpg"
	var blight := ResourceLoader.exists(dead)
	for d in fields.get_children():
		var f := d as Decal
		if f == null:
			continue  # the crops themselves (countryside.gd), not a painted field
		if not f.has_meta("ripe"):
			f.set_meta("ripe", f.modulate)
			f.set_meta("crop", f.texture_albedo)
		if blight:
			var reps: Vector2i = f.get_meta("reps", Vector2i.ONE)
			f.texture_albedo = terrain.tiled(dead, reps.x, reps.y) if hungry else f.get_meta("crop")
		else:
			f.modulate = Color(0.42, 0.33, 0.24) if hungry else f.get_meta("ripe")


## A building site: the structure rises with real progress under scaffolding,
## with timber stacked beside it and builders at work.
func _construction(root: Node3D, life: Node3D, center: Vector3, building: String, progress: float, rng: RandomNumberGenerator, size: int) -> void:
	var kit := site_kit(building)
	# Sites go up at the edge of town, on the first flat ground found that no
	# house, wall or fence already stands on (with room round it for the builders).
	var f: Vector2 = Real.footprint(kit)
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0) + 0.7
	var ang := rng.randf() * TAU
	var walls: Array = _blocked(root, life)
	var plot := PackedVector2Array()
	var found := false
	for tries in 36:
		var a := ang + TAU * (tries % 12) / 12.0
		var probe := Vector3(cos(a), 0, sin(a)) * (reach + (tries / 12) * 0.5)
		var wp := center + probe
		if not terrain.is_land(wp.x, wp.z) or absf(terrain.height_at(wp.x + 0.4, wp.z) - terrain.height_at(wp.x - 0.4, wp.z)) >= 0.3:
			continue
		var rect := _rect(probe, f + Vector2(0.4, 0.4), a + PI)
		var clear := true
		for fp: PackedVector2Array in walls:
			if Vector2(probe.x, probe.z).distance_to(fp[0]) < 4.0 and not Geometry2D.intersect_polygons(rect, fp).is_empty():
				clear = false
				break
		if clear:
			ang = a
			plot = _rect(probe, f * 1.1, a + PI)
			found = true
			break
	if not found:
		return  # nowhere to build in sight: the work goes on unseen
	var off := Vector3((plot[0].x + plot[2].x) / 2.0, 0, (plot[0].y + plot[2].y) / 2.0)
	_site(root, life, center, off + Vector3(0, _y(center, off), 0), ang, kit, f, plot, clampf(progress, 0.08, 1.0), rng)
	# What's being raised shows under the town's name on the map (map_labels.gd).
	life.set_meta("doing", doing_line("Building", building, progress))


## Recruits drilling in ranks on the square while a unit trains.
func _drill(root: Node3D, life: Node3D, center: Vector3, progress: float, color: Color, unit: String) -> void:
	# One rank, side by side a pace and a half apart (0.45), on open ground beside
	# the square and facing its heart: nobody stands at another's back.
	var count := clampi(3 + int(progress * 4), 3, 6)
	var walls: Array = _blocked(root, life)
	var none := PackedVector2Array()
	var bow := unit.contains("Archer") or unit.contains("bow")
	for tries in 32:
		var a := TAU * (tries % 16) / 16.0
		var dist := 0.55 + (tries / 16) * 0.35
		var face := Vector3(-cos(a), 0, -sin(a))  # toward the heart of the square
		var side := Vector3(-face.z, 0, face.x)
		var spots: Array[Vector3] = []
		for i in count:
			var p := -face * dist + side * ((i - (count - 1) * 0.5) * 0.45)
			if not _open(center, p, walls, none):
				break
			spots.append(p)
		if spots.size() < count:
			continue
		var taken: PackedVector2Array = life.get_meta("standing")
		for i in count:
			var p := spots[i]
			p.y = _y(center, p)
			var s := _townsperson(life, p, "soldier", "Idle", hash(unit) + i, color.lerp(Color.WHITE, float(Data.num("crowd", "posted.lighten", 0.0))))  # the house's colour as the posted guards wear it (round 5: lightened 35%, it read pink)
			s.rotation.y = atan2(face.x, face.z)
			if not _mind(s, "bows" if bow else "drill", center):
				_drill_routine(s, bow, hash(unit) + i)
			taken.append(Vector2(p.x, p.z))
		life.set_meta("standing", taken)
		break
	life.set_meta("doing", doing_line("UnitType", unit, progress))


## A turned rectangle, town-local XZ, the way towns.gd records footprints.
static func _rect(at: Vector3, size: Vector2, rot: float) -> PackedVector2Array:
	var b := Basis(Vector3.UP, rot)
	var pts := PackedVector2Array()
	for c in [Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)]:
		var w: Vector3 = at + b * (c * 0.5)
		pts.append(Vector2(w.x, w.z))
	return pts


func _bonfire(life: Node3D, center: Vector3) -> void:
	# A fire you'd gather round, burning in the game's own flames (fire.gd's flame shader, as a house burns:
	# tongues born small, swelling, eaten away as they rise). Batch 8b centre-feast-wide: the ring stood unlit,
	# its 0.07-wide added dots too small to read from the town camera. Numbers: moods.json feast.bonfire.
	const Fire := preload("res://scripts/fire.gd")
	var B: Dictionary = Data.value("moods", "feast.bonfire", {})
	var r := fire_reach() - HEAT
	var rise: Array = B.get("rise", [0.1, 0.2])
	var flames := Fire._flames(int(B.get("amount", 26)), 0.9, B.get("size", [0.09, 0.16]), Vector2(float(rise[0]), float(rise[1])), Vector3(r * 0.35, 0.01, r * 0.35), Fire._flame_material(true))
	flames.position = Vector3(_fire_at.x, _y(center, _fire_at) + 0.02, _fire_at.z)
	var fire_at := flames.position
	life.add_child(flames)
	var ring: Node3D = Real.make(Real.one("fire_pit"))  # the stones it burns in
	if ring:
		ring.position = Vector3(_fire_at.x, _y(center, _fire_at) - 0.005, _fire_at.z)
		ring.scale = Vector3.ONE * RING_SCALE
		life.add_child(ring)
	# Nobody stands in the fire: the ring as wide as it really stands, and a
	# step of heat past its stones, is ground nobody claims (_blocked reads "fires").
	var keep := fire_reach()
	life.set_meta("fires", [[Vector2(_fire_at.x, _fire_at.z), keep]])
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.3)
	light.light_energy = float(B.get("light", 1.6))
	light.omni_range = float(B.get("range", 1.4))
	light.position = fire_at + Vector3(0, 0.2, 0)
	life.add_child(light)


const RING_SCALE := 1.4  # the fire pit's stones, a little larger than the model's own
var _fire_at := Vector3.ZERO  # where the feast's bonfire stands (town-local): the heart, or off a centrepiece standing there


## The square's centrepiece (a fountain at a seat, towns.gd root meta centrepiece): how far from the heart
## its basin reaches (game units), 0 when only the old well stands off the heart.
static func centre_reach(root: Node3D) -> float:
	var kind := String(root.get_meta("centrepiece", ""))
	if kind == "":
		return 0.0
	var foot := Real.footprint(kind)
	return maxf(foot.x, foot.y) * 0.5


## A point pushed out past the square's centrepiece (its basin's rim, plus `clear`), if it fell inside: a
## stall, a dog, a child, the levy's kin, never in the fountain's water (batch 8 review: a canopy over it).
func _off_centre(root: Node3D, p: Vector3, clear: float) -> Vector3:
	var r := centre_reach(root)
	if r <= 0.0:
		return p
	var flat := Vector2(p.x, p.z)
	var keep := r + clear
	if flat.length() >= keep:
		return p
	var dir := flat.normalized() if flat.length() > 0.001 else Vector2(SEEN.x, SEEN.z)
	return Vector3(dir.x * keep, p.y, dir.y * keep)


## Where the feast's bonfire goes: the square's heart, or with a fountain there, on the seen side clear of
## its basin by moods.json centre.fire (the dancers' ring and the tables follow it).
func _fire_spot(root: Node3D) -> Vector3:
	var r := centre_reach(root)
	if r <= 0.0:
		return Vector3.ZERO
	return SEEN * (r + fire_reach() + float(Data.num("moods", "centre.fire", 0.12)))
static var HEAT: float = preload("res://scripts/data.gd").num("town_scenes", "life.heat", 0.06)  # past the stones, a step nobody takes: half a metre


## How far from a bonfire's middle the ground is the fire's: its ring of
## stones as wide as it stands (the model's real footprint, scaled), and HEAT.
static func fire_reach() -> float:
	var foot := Real.footprint(Real.one("fire_pit"))
	return maxf(foot.x, foot.y) * RING_SCALE * 0.5 + HEAT if foot != Vector2.ZERO else 0.23


## A kept stall's stock beside it (crowd.json square_agents.pile; the routines spec: Stronghold's one load, one drop
## on a pile that grows; a sale takes one off): sacks and crates on the ground at the stall's end, the stall's
## pile in root meta piles by stall index. Only with the square's agents on.
func _pile(root: Node3D, life: Node3D, center: Vector3, si: int, m: Vector3, out: Vector3, width: float) -> void:
	if not square_agents_on():
		return
	var K: Dictionary = Data.value("crowd", "square_agents.pile", {})
	var kinds: Array = K.get("props", ["Bag", "FarmCrate_Apple"])
	var most := int(K.get("most", 4))
	if kinds.is_empty() or most <= 0:
		return
	var along := Vector3(-out.z, 0, out.x)
	var base := m + along * (width * 0.5 + float(K.get("aside", 0.06))) - out * 0.02
	var nodes: Array = []
	for i in most:
		var at := base + along * float(i % 2) * 0.05 - out * float(i / 2) * 0.05
		var n := _prop(life, center, String(kinds[i % kinds.size()]), at, atan2(out.x, out.z) + float(i) * 0.4, float(K.get("size", 1.0)))
		if n:
			nodes.append(n)
	var piles: Dictionary = root.get_meta("piles", {})
	piles[si] = nodes
	root.set_meta("piles", piles)


## Takes one off stall `si`'s pile (`n` -1, a sale) or puts one back (`n` +1, a porter's load). False when there's
## none to take or no room.
static func pile(root: Node3D, si: int, n: int) -> bool:
	if not is_instance_valid(root):
		return false
	var nodes: Array = (root.get_meta("piles", {}) as Dictionary).get(si, [])
	nodes = nodes.filter(func(x): return is_instance_valid(x))
	if n < 0:
		for i in range(nodes.size() - 1, -1, -1):
			if (nodes[i] as Node3D).visible:
				(nodes[i] as Node3D).visible = false
				return true
		return false
	for x in nodes:
		if not (x as Node3D).visible:
			(x as Node3D).visible = true
			return true
	return false


## The crown's seat's market knobs (data/towns.json market.crown), {} elsewhere.
func _market_knobs(root: Node3D) -> Dictionary:
	if not bool(root.get_meta("crown_seat", false)):
		return {}
	return crown_market()


## The crown's market's numbers (towns.json market.crown), the one reading of them (town_life and
## villagers): with --crowd=off, the square as it was before the crowd work (crowd.json off: fewer buyers,
## porters and carts, a square that holds fewer), so the switch shows the whole difference (batch 8b
## #15: crowd on and off barely differed).
static func crown_market() -> Dictionary:
	var m: Dictionary = (preload("res://scripts/data.gd").value("towns", "market", {}) as Dictionary).get("crown", {})
	if OS.get_cmdline_user_args().has("--crowd=off") or not bool(preload("res://scripts/data.gd").value("crowd", "on", true)):
		m = m.duplicate()
		m.merge(preload("res://scripts/data.gd").value("crowd", "off", {}), true)
	return m


## The town's life is street-level detail: drawn only within a short walk of the camera.
static func _near_only(life: Node) -> void:
	for g in life.find_children("*", "GeometryInstance3D", true, false):
		if g.visibility_range_end == 0.0:
			g.visibility_range_end = 30.0
			g.visibility_range_end_margin = 4.0
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## What a town is busy with, as its people would say it: "Raising settlers for
## a new town", "Building a granary", not the engine's "Training Settlers".
static func doing_line(kind: String, name: String, progress: float) -> String:
	const UNITS := {"Settlers": "Raising settlers for a new town", "Migrants": "Gathering families to move", "Workers": "Training labourers", "Engineers": "Training engineers", "Explorer": "Sending out scouts", "Caravan": "Fitting out a caravan", "Diplomat": "Choosing envoys"}
	const BUILDINGS := {"City Walls": "Raising the walls", "Coinage": "Filling the coffers", "Palace": "Building a palace", "Colosseum": "Building a tiltyard", "Marketplace": "Building a market", "Bank": "Building a counting house"}
	var what: String
	if kind == "UnitType":
		what = String(UNITS.get(name, "Raising %s" % name.to_lower()))
	else:
		var low := name.to_lower()
		what = String(BUILDINGS.get(name, "Building %s %s" % ["an" if "aeiou".contains(low.left(1)) else "a", low]))
	return "%s · %d%%" % [what, int(progress * 100)]


## What rises for a building: the kit's own building for it.
static func site_kit(building: String) -> String:
	match building:
		"Temple", "Cathedral", "Amphitheater", "Colosseum", "Courthouse", "Library", "University":
			return Real.one("church")
		"Barracks", "Barracks II", "Palace":
			return Real.one("hall")
		"Granary", "Marketplace", "Harbor":
			return Real.one("barn")
		"City Walls", "Great Wall":
			return Real.one("fence")
	return Real.one("house_poor")


## A building site (the royal works and any new building use the same): the
## building rising to `grow` of its height, scaffold poles, timber, a cart, a
## ladder, and three builders at work with minds. Returns the rising building.
func _site(root: Node3D, life: Node3D, center: Vector3, base: Vector3, ang: float, kit: String, f: Vector2, plot: PackedVector2Array, grow: float, rng: RandomNumberGenerator) -> Node3D:
	var site: Node3D = Real.make(kit)
	if site == null:
		return null
	_grow(site, grow)
	site.name = "Site"
	site.position = base
	site.rotation.y = ang + PI
	life.add_child(site)
	var hx := f.x * 0.55
	var hz := f.y * 0.55
	var full := maxf(f.x, f.y) * 0.6
	_pole.height = full * 1.05
	for p in [Vector3(hx, 0, hz), Vector3(-hx, 0, hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, -hz), Vector3(0, 0, hz), Vector3(0, 0, -hz)]:
		var pole := MeshInstance3D.new()
		pole.mesh = _pole
		pole.material_override = _wood
		pole.position = base + p.rotated(Vector3.UP, ang) + Vector3(0, full * 0.52, 0)
		life.add_child(pole)
	# Timber stacked beside it, a cart that brought it, a ladder up the side.
	var props := [[Real.one("woodpile"), Vector3(hx + 0.2, 0, 0), ang], [Real.one("cart"), Vector3(hx + 0.25, 0, hz + 0.35), ang + 0.4],
		[Real.one("ladder"), Vector3(-hx - 0.04, 0, 0), ang + PI / 2]]  # by component (realm/data/assets.json)
	for pr in props:
		var prop: Node3D = Real.make(pr[0])
		if prop == null:
			continue
		var at: Vector3 = base + Vector3(pr[1]).rotated(Vector3.UP, ang)
		if not terrain.is_land(center.x + at.x, center.z + at.z):
			prop.free()
			continue
		prop.position = Vector3(at.x, _y(center, at), at.z)
		prop.rotation.y = pr[2]
		life.add_child(prop)
	# Builders at work along its front, each at a task done standing or
	# kneeling where they are (carrying and barrowing are walks: not on the spot).
	for i in 3:
		var bp := base + Vector3(rng.randf_range(-hx, hx), 0, hz + 0.16).rotated(Vector3.UP, ang)
		var b := _stand(root, life, center, bp, "peasant", ["Fixing_Kneeling", "PickUp_Table", "Interact"][i], rng.randi())
		if b:
			b.rotation.y = atan2(base.x - b.position.x, base.z - b.position.z)  # facing the work
			_mind(b, "build", center)
	return site


## How far a site's building has risen (0..1, its height). Below SITE_SHOWS it is not shown at
## all: the plot, its scaffold poles, the timber and the builders are the site. A model squashed to
## a sliver read as grey slabs on the grass (Kingsmere's tiltyard at 0%, km-cap).
static var SITE_SHOWS: float = preload("res://scripts/data.gd").num("town_scenes", "life.site_shows", 0.35)
static func _grow(site: Node3D, g: float) -> void:
	site.scale.y = g
	site.visible = g >= SITE_SHOWS


## A new building rising in a town, for towns.gd (builder 2): the same site as
## the royal works, at `plot` (town-local), one step higher each season of the
## realm (awareness.gd's season_turned, so it waits while the realm waits), and
## gone when done, `on_done` called so the finished building can stand.
func raise_site(town_node: Node3D, plot: Transform3D, building: String, seasons: int, on_done := Callable()) -> Node3D:
	var life: Node3D = town_node.get_node_or_null("Life")
	if life == null:
		life = Node3D.new()
		life.name = "Life"
		life.set_meta("standing", PackedVector2Array())
		town_node.add_child(life)
	var kit := site_kit(building)
	var f: Vector2 = Real.footprint(kit)
	var ang := plot.basis.get_euler().y - PI
	var base := plot.origin
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(building) + int(base.x * 100.0)
	var holder := Node3D.new()  # the whole site, freed at once when it's done
	holder.name = "Raising"
	life.add_child(holder)
	# Its builders keep their set moves: _mind would join them to whichever town was dressed last.
	var was_on := _town_on
	_town_on = false
	var site := _site(town_node, holder, town_node.position, base, ang, kit, f, _rect(base, f * 1.1, ang + PI), 0.08, rng)
	_town_on = was_on
	if site == null:
		holder.free()
		return null
	var left := [maxi(1, seasons)]
	var step := 0.92 / float(left[0])
	var aw = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	if aw == null:
		return site
	var grow_on := func(_turn: int) -> void:
		if not is_instance_valid(site):
			return
		left[0] -= 1
		site.create_tween().tween_method(func(g: float): _grow(site, g), site.scale.y, minf(1.0, site.scale.y + step), 1.5)
		if left[0] <= 0:
			holder.queue_free()
			if on_done.is_valid():
				on_done.call()
	aw.season_turned.connect(grow_on)
	holder.tree_exiting.connect(func():
		if aw.season_turned.is_connected(grow_on):
			aw.season_turned.disconnect(grow_on))
	return site


## The town's state, read from the place even if nobody moved (the judge, from
## Frostpunk and Banished): what stands in the square, from the props the kits
## already hold. The state comes from the bridge (townStates); the people's
## behaviour is their minds' (npc_mind.gd); this is only what's set out.
const PROPS := "res://assets/props/%s.gltf"
const PROP_SCALE := Units.M  # the props kit is in metres; a person here stands about 0.2
static var _prop_cache := {}
## What people sit on, eat at and work at (people.json furniture: benches, tables and what's on them, the
## anvil) is drawn at the people's own size (readable), so a drinker sits on the bench and not proud of it.
## --furniture=off draws it life size, as before.
static var FURN: float = _furn_scale()
static var FURN_NAMES: Array = preload("res://scripts/data.gd").value("people", "furniture.props", []) if FURN != 1.0 else []


static func _furn_scale() -> float:
	var D := preload("res://scripts/data.gd")
	if OS.get_cmdline_user_args().has("--furniture=off") or not bool(D.value("people", "furniture.on", true)):
		return 1.0
	return float(D.num("people", "readable", 1.0))


func _prop(life: Node3D, center: Vector3, name: String, at: Vector3, yaw := 0.0, scale := 1.0, lift := 0.0) -> Node3D:
	if not _prop_cache.has(name):
		_prop_cache[name] = load(PROPS % name) if ResourceLoader.exists(PROPS % name) else null
	var scene: PackedScene = _prop_cache[name]
	if scene == null:
		return null
	var n: Node3D = scene.instantiate()
	if name in FURN_NAMES:
		scale *= FURN
	n.scale = Vector3.ONE * PROP_SCALE * scale
	n.position = Vector3(at.x, _y(center, at) + lift, at.z)
	n.rotation.y = yaw
	life.add_child(n)
	return n


func _dress(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, rng: RandomNumberGenerator, house := {}) -> void:
	var stalls: Array = root.get_meta("stalls", [])
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	# At every stall's front: what it has to sell, or that it has nothing.
	var goods: Array = []
	if c.get("prosperity", false) or ("relief" in Works.states(c, _town_id) and bool(Data.value("moods", "relief.goods", false))):
		goods = ["FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Apples", "Coin_Pile"]
	elif c.get("famine", false) or c.get("atWar", false) or c.get("grief", false):
		goods = ["FarmCrate_Empty", "Crate_Wooden"]  # shut or sold out
	for st in stalls:
		var m: Vector3 = st[0]
		var out := Vector3(m.x, 0, m.z).normalized()
		var along := Vector3(-out.z, 0, out.x)
		for i in goods.size():
			_prop(life, center, goods[i], m - out * (float(st[1]) * 0.5 + 0.06) + along * ((i - (goods.size() - 1) * 0.5) * 0.07), atan2(out.x, out.z), 1.0, 0.0)
	# Where the eye lands: inside the square, between its heart and the far side
	# from the well (the judge: dressing at the edge is dressing nobody sees),
	# on the half of the square a camera coming down into the town looks across.
	var edge := Vector3(-well.z, 0, well.x).normalized() * 0.55  # across the square from the well-to-market line, clear of the stalls
	if edge.dot(SEEN) < 0.0:
		edge = -edge
	var side := Vector3(-edge.z, 0, edge.x).normalized()
	life.set_meta("anchors", {"barricade": {"at": edge * 0.95, "dir": edge}, "lute": {"at": well + side * 0.18, "dir": SEEN},
		"tax": {"at": edge * 0.6, "dir": edge, "side": side}, "tax_queue": {"at": edge * 0.6, "dir": -edge.normalized()}})
	if c.get("atWar", false):
		# A barricade cart across the road in, weapons stacked, and more of the watch.
		var cart: Node3D = Real.make(Real.one("cart"))
		var cart_at := _spot(center, edge * 1.2, _blocked(root, life), life.get_meta("standing"), 0.3)  # the nearest open ground to the way in
		if cart and not is_nan(cart_at.x):
			cart.position = Vector3(cart_at.x, _y(center, cart_at), cart_at.z)
			cart.rotation.y = atan2(side.x, side.z) + 0.35  # slewed across the way, not parked
			cart.set_meta("dress", "barricade")
			life.add_child(cart)
		elif cart:
			cart.free()  # no room on that road: no cart across it
		# Crates and casks heaped against it: a barricade, not a cart parked.
		for k in 4:
			var heap := edge * (1.2 + (0.06 if k % 2 else -0.06)) + side * (0.24 + k * 0.07) * (1.0 if k < 2 else -1.0)
			_prop(life, center, ["Crate_Wooden", "Barrel", "FarmCrate_Empty", "Crate_Wooden"][k], heap, rng.randf() * TAU, 1.0, 0.0)
		# The lord's standard planted either side of the way, high over the heads: seen from any street.
		var col := Color.from_string(String(house.get("color", "#8a2a1e")), Color(0.55, 0.16, 0.12))
		for k in [-1.0, 1.0]:
			var at: Vector3 = edge * 1.1 + side * 0.28 * k  # close enough together that a street camera has both
			var flag := Heraldry.standard(house, col, STANDARD_TALL)
			flag.position = Vector3(at.x, _y(center, at), at.z)
			flag.rotation.y = atan2(-edge.x, -edge.z)
			flag.set_meta("dress", "standard")
			life.add_child(flag)
		_prop(life, center, "WeaponStand", edge * 1.05 + side * 0.2, atan2(-edge.x, -edge.z), 1.0, 0.0)
		_prop(life, center, "Shield_Wooden", edge * 1.05 - side * 0.2, atan2(-edge.x, -edge.z))
	if c.get("grief", false):
		# Mourners gathered at the well, candles set down; at a fountain, round its rim, outside the basin
		# (moods.json centre.mourners, centre.candles: past its real radius).
		var basin := centre_reach(root)
		var set_down := basin + float(Data.num("moods", "centre.candles", 0.04)) if basin > 0.0 else 0.19
		for i in 3:
			_prop(life, center, "Candle_1", well + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * set_down)  # round the well's curb (its winch reaches 0.16 out) or the basin's rim, not in it
	if c.get("prosperity", false):
		# One more stall in good times, by the well, heaped with produce.
		var extra := _off_centre(root, well + side * 0.38, float(Data.num("moods", "centre.stall", 0.2)))  # the canopy clear of a fountain's rim
		var stall: Node3D = Real.make(Real.one("market_stall"))  # the market's own stall (assets.json market_stall), as towns.gd's
		if stall:
			stall.position = Vector3(extra.x, _y(center, extra), extra.z)
			stall.rotation.y = atan2(-extra.x, -extra.z)
			life.add_child(stall)
			for i in 3:
				_prop(life, center, ["FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Apples"][i], extra + Vector3(-extra.z, 0, extra.x).normalized() * (i - 1) * 0.06 - extra.normalized() * 0.08, atan2(-extra.x, -extra.z))
	if c.get("grasping", false):
		# The tax collector's table in the square, coin and ledger on it, a guard by him, a queue muttering.
		var at := edge * 0.6
		_prop(life, center, "Table_Large", at, atan2(side.x, side.z), 1.0, 0.0)
		var TABLE_TOP := 0.098 * FURN  # the table's height (0.815 m at PROP_SCALE, drawn at the people's size): coin and ledger lie on it
		_prop(life, center, "Coin_Pile", at + side * 0.04, 0.0, 1.0, TABLE_TOP)
		_prop(life, center, "Scroll_1", at - side * 0.04, 0.0, 1.0, TABLE_TOP)
		_prop(life, center, "Chest_Wood", at + edge.normalized() * 0.2, atan2(side.x, side.z), 1.0, 0.0)


# --- the working buildings (works.gd, realm/data/works.json) --------------------

const Works := preload("res://scripts/works.gd")
const Dressing := preload("res://scripts/dressing.gd")
const Horse := preload("res://scripts/horse.gd")
const Data := preload("res://scripts/data.gd")
const NavGround := preload("res://scripts/nav_ground.gd")  # what stands in the town, read off what is set down


## The life at the town's working buildings, from the town agent's list of
## them (works.gd): the smith at the anvil with the forge's glow and sparks,
## arms stacking on the armoury's rack and the levy lining up for them, horses
## in the paddock, the miller at the turning mill, the granary's sacks as full
## as Freeciv says and a queue at its door when it runs low, the tanner at his
## vats, the inn's benches by day and lit windows by night, a crier in the
## square when there's news. Who works and how many follow the town's state
## (works.json counts); the people's choices are their minds' (npc_mind.gd).
func _works(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, rng: RandomNumberGenerator) -> void:
	if not Works.on():
		return
	var all := Works.anchors(root)
	if all.is_empty():
		return
	var active := Works.states(c, _town_id)
	var size := int(c.get("size", 1))
	var tick := Works.Tick.new()
	tick.name = "Works"
	tick.root = root
	tick.life = life
	tick.ground = func(q: Vector3) -> float: return _y(center, q)
	tick.hot = "war" in active or "levy" in active
	tick.make_prop = func(name: String, at: Vector3, yaw: float, lift: float) -> Node3D: return _work_prop(life, center, name, at, yaw, lift)
	life.add_child(tick)
	var n := func(what: String) -> int: return Works.count(what, active, size)
	if all.has("forge"):
		_forge(root, life, center, all["forge"], tick, n.call("smiths"), rng)
	if all.has("armoury"):
		_armoury(root, life, center, all["armoury"], tick, n.call("levy_queue"), rng)
	var pad := Works.find(root, "paddock")
	if not pad.is_empty():
		_paddock(root, life, center, pad, tick, n.call("horses"), rng)
	if all.has("barn"):
		_yard(root, life, center, all["barn"], n.call("beasts"), n.call("yardhands"), rng)
	for kind in ["windmill", "watermill"]:
		if all.has(kind):
			_mill(root, life, center, all[kind], kind, tick, n.call("millers"), rng)
	if all.has("granary"):
		_granary(root, life, center, all["granary"], c, tick, n.call("granary_queue"), rng)
	_crews(root, life, center, all, n, rng)
	if all.has("inn"):
		_inn(root, life, center, all["inn"], tick, n, rng)


## Each trade's crew at its work front, as works.json crews lists them (the tanner and the dyer at the vats, the
## brewer at the alehouse's barrels, the stable hand at the heap; casebook, Living towns: "A world with its own
## clock"): set down at the building's spot facing it, each with their post's day (npc_mind post_activities).
func _crews(root: Node3D, life: Node3D, center: Vector3, all: Dictionary, n: Callable, rng: RandomNumberGenerator) -> void:
	var crews: Dictionary = Data.value("works", "crews", {})
	for trade in crews:
		if not all.has(trade):
			continue
		var b: Dictionary = all[trade]
		var sp: Dictionary = b["spots"]
		for row: Dictionary in crews[trade]:
			var spot: Variant = null
			for k in row["spot"]:
				if sp.has(String(k)):
					spot = sp[String(k)]
					break
			if spot == null:
				continue  # none of its spots: nowhere to work at this building
			for i in int(n.call(String(row["n"]))):
				var t := _stand(root, life, center, spot, String(row["who"]), String(row["clip"]), rng.randi(), Color.WHITE, 0.2)
				if t:
					t.set_meta("crew", trade)
					_face(t, b["at"])
					_mind(t, String(row["post"]), center)


func _face(p: Node3D, at: Vector3) -> void:
	var flat := Vector2(at.x - p.position.x, at.z - p.position.z)
	if flat.length() > 0.001:
		p.rotation.y = atan2(flat.x, flat.y)


## A thing set out on a stack while the town is lived in (works.Tick): seen near only.
func _work_prop(life: Node3D, center: Vector3, name: String, at: Vector3, yaw: float, lift: float) -> Node3D:
	if not is_instance_valid(life):
		return null
	var p := _prop(life, center, name, at, yaw, 1.0, lift)
	if p:
		_near_only(p)
	return p


## A line of people from `start` out along `out` (town-local), facing back up it.
func _line(root: Node3D, life: Node3D, center: Vector3, start: Vector3, out: Vector3, count: int, station: String, anim: String, post: String, rng: RandomNumberGenerator) -> void:
	for i in count:
		var p := _stand(root, life, center, start + out * (ROOM * 1.15 * i), station, anim, rng.randi(), Color.WHITE, 0.12)
		if p:
			_face(p, p.position - out)
			_mind(p, post, center)


func _front(b: Dictionary) -> Vector3:
	return Basis(Vector3.UP, float(b["yaw"])) * Vector3(0, 0, 1)


func _forge(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, tick: Works.Tick, smiths: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var anvil: Vector3 = sp.get("anvil", b["at"] + _front(b) * 0.25)
	var hearth: Vector3 = sp.get("hearth", b["at"])
	if b["dress"]:
		_prop(life, center, "Anvil", anvil, float(b["yaw"]), 1.0, 0.0)
		if sp.has("trough"):
			_prop(life, center, "Bucket_Metal", sp["trough"], 0.0, 1.0, 0.0)
	# The smith at the anvil, the second at the bellows by the hearth (batch 9: both stood out by the door, the
	# building's own footprint keeping them off its yard): they work inside it.
	var bellows: Vector3 = sp.get("bellows", sp.get("second", hearth + _front(b) * 0.1))
	var posts: Array = [sp.get("smith", anvil + _front(b) * 0.08), bellows]
	for i in mini(smiths, posts.size()):
		var s := _stand(root, life, center, posts[i], "townsfolk", "Hammer_Swing" if i == 0 else "Pushing", rng.randi(), Color.WHITE, 0.12, "smith" if i == 0 else "", true)
		if s:
			_face(s, anvil if i == 0 else hearth)
			if i == 0 and sp.has("trough"):
				s.set_meta("spot_quench", sp["trough"])  # the quench: to the trough and back (npc_mind spot_step)
			if i == 1:
				s.set_meta("spot_coal", sp.get("store", hearth))  # the bellows boy fetches coal from the store
			_mind(s, "smith" if i == 0 else "bellows", center)
			tick.smiths.append(s)
	# The forge's glow, brighter in war, banked at night (works.Tick sets it each second).
	var g: Dictionary = Data.value("works", "forge.glow", {})
	var glow := OmniLight3D.new()
	glow.light_color = Data.colour(g.get("color"), Color(1.0, 0.52, 0.22))
	glow.light_energy = float(g.get("day", 1.1))
	glow.omni_range = float(g.get("range", 0.9))
	# Inside the hearth, not out at its mouth: set back toward the building's middle (forge.glow.inset), so it
	# lights the doorway warmly from within and never stands as a bright ball on the ground.
	var inward: Vector3 = b["at"] - hearth
	inward.y = 0.0
	var inside: Vector3 = hearth + (inward.normalized() * float(g.get("inset", 0.12)) if inward.length() > 0.001 else Vector3.ZERO)
	glow.position = Vector3(inside.x, _y(center, hearth) + float(g.get("height", 0.12)), inside.z)
	glow.shadow_enabled = false
	life.add_child(glow)
	tick.glow = glow
	# The hearth's fire, seen through the open front (01-town: a bright orange forge): the game's own flames (fire.gd,
	# as a house burns and the feast's bonfire), small, in the hearth (works.json forge.fire).
	var fk: Dictionary = Data.value("works", "forge.fire", {})
	if int(fk.get("amount", 0)) > 0:
		const Fire := preload("res://scripts/fire.gd")
		var fr: Array = fk.get("rise", [0.06, 0.12])
		var reach := float(fk.get("reach", 0.05))
		var flames := Fire._flames(int(fk["amount"]), 0.8, fk.get("size", [0.04, 0.08]), Vector2(float(fr[0]), float(fr[1])), Vector3(reach, 0.01, reach), Fire._flame_material(true))
		flames.position = Vector3(inside.x, _y(center, hearth) + float(fk.get("height", 0.04)), inside.z)
		life.add_child(flames)
	# Sparks off the anvil's face as the hammer strikes: a burst each stroke (works.Tick restarts it), never a
	# steady stream. Drawn at their real size in the quad itself: the GPU copy (Particles.to_gpu) loses a CPU
	# effect's scale, so 0.25-wide additive quads stacked into a white ball at the smith's feet (batch 7).
	var k: Dictionary = Data.value("works", "forge.sparks", {})
	var p := CPUParticles3D.new()
	p.amount = maxi(1, int(float(k.get("amount", 14)) * (float(k.get("war", 2.0)) if tick.hot else 1.0)))
	p.one_shot = true
	p.explosiveness = 0.85
	p.lifetime = float(k.get("life", 0.45))
	p.direction = Vector3.UP
	p.spread = 70
	p.gravity = Vector3(0, -0.9, 0)
	var speed: Array = k.get("speed", [0.25, 0.6])
	p.initial_velocity_min = float(speed[0])
	p.initial_velocity_max = float(speed[1])
	var size: Array = k.get("size", [0.008, 0.016])
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.68, 0.28, float(k.get("bright", 0.8))))  # orange, never white: added, it blooms
	grad.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2.ONE * (float(size[0]) + float(size[1])) * 0.5
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	p.emitting = false
	p.position = Vector3(anvil.x, _y(center, anvil) + float(k.get("height", 0.1)), anvil.z)
	var gpu := Particles.to_gpu(p, 25.0)
	life.add_child(gpu)
	tick.sparks = gpu


func _armoury(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, tick: Works.Tick, levy: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var rack: Vector3 = sp.get("rack", b["at"] + _front(b) * 0.25)
	if b["dress"]:
		_prop(life, center, "WeaponStand", rack, float(b["yaw"]), 1.0, 0.0)
	# The arms on the rack: the apprentice's deliveries, the levy's takings (works.gd stock).
	tick.stacks.append({"what": "rack", "at": rack + _front(b) * 0.06, "yaw": float(b["yaw"]), "prop": "Sword_Bronze", "nodes": [], "gap": 0.05, "lift": 0.0})
	_line(root, life, center, sp.get("queue", rack + _front(b) * 0.2), _front(b), levy, "peasant", "Weight_Shift", "levy", rng)


func _paddock(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, tick: Works.Tick, count: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var middle: Vector3 = sp.get("middle", b["at"])
	var roam: float = float(b["radius"]) if float(b["radius"]) > 0.0 else Data.num("works", "paddock.roam", 3.5) * Works.S
	var list: Array = []
	var gap := Data.num("works", "paddock.gap", 0.45)
	for i in count:
		var h: Node3D = Horse.new(rng.randi() % Horse.COATS.size())
		var at := middle
		for t in 10:  # each its own patch of grass, a horse's length and more from the rest (round 5: they stood in each other)
			var a := rng.randf() * TAU
			var r := sqrt(rng.randf()) * roam * 0.8
			at = middle + Vector3(cos(a) * r, 0, sin(a) * r)
			if list.all(func(o: Node3D) -> bool: return Vector2(o.position.x - at.x, o.position.z - at.z).length() >= gap):
				break
		h.position = Vector3(at.x, _y(center, at), at.z)
		h.rotation.y = rng.randf() * TAU
		h.set_meta("rest", rng.randf_range(0.0, 8.0))
		life.add_child(h)
		h.live_idle(rng)  # grazing between strolls (animals.gd)
		list.append(h)
	root.set_meta("horses", list)
	tick.paddock = middle
	tick.roam = roam


## The barn's yard: the town's beasts in a loose pen before it (works.json yard:
## which kinds and how many, by the town's state), each living its own idle life
## (animals.gd: a cow grazes, a pig roots), and a hand at them: milking, feeding,
## filling the trough, mucking out (npc_mind post yardhand).
func _yard(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, beasts: int, hands: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var pen: Vector3 = sp.get("yard", b["at"] + _front(b) * 0.4)
	var roam := Data.num("works", "yard.roam", 2.2) * Works.S
	var kinds: Array = Data.value("works", "yard.kinds", [["cow", 3], ["sheep", 4], ["pig", 2]])
	var taken: PackedVector2Array = life.get_meta("standing")
	var placed := 0
	var tries := 0
	var first_cow: Node3D = null
	var gap := maxf(Data.num("works", "yard.gap", 1.3) * Works.S, ROOM)
	while placed < beasts and tries < beasts * 12:
		tries += 1
		var kind := _weighed(kinds, rng)
		var a := rng.randf() * TAU
		var at := pen + Vector3(cos(a), 0, sin(a)) * sqrt(rng.randf()) * roam
		if Array(taken).any(func(q: Vector2) -> bool: return q.distance_to(Vector2(at.x, at.z)) < gap):
			continue
		var beast := _beast(kind, rng)
		if beast == null:
			continue
		beast.position = Vector3(at.x, _y(center, at), at.z)
		beast.rotation.y = rng.randf() * TAU
		life.add_child(beast)
		taken.append(Vector2(at.x, at.z))
		placed += 1
		if kind == "cow" and first_cow == null:
			first_cow = beast
	life.set_meta("standing", taken)
	for i in hands:
		var near: Vector3 = first_cow.position + Basis(Vector3.UP, first_cow.rotation.y) * Vector3(0.09, 0, 0) if first_cow and i == 0 else sp.get("trough", pen)
		var h := _stand(root, life, center, near, "peasant", "Milking" if first_cow and i == 0 else "PickUp_Table", rng.randi(), Color.WHITE, 0.15)
		if h:
			_face(h, first_cow.position if first_cow and i == 0 else pen)
			_mind(h, "yardhand", center)


## A name from [[name, weight], ...], picked by weight.
static func _weighed(rows: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for r in rows:
		total += float(r[1])
	var roll := rng.randf() * total
	for r in rows:
		roll -= float(r[1])
		if roll <= 0.0:
			return String(r[0])
	return String(rows[-1][0]) if not rows.is_empty() else ""


## A farm beast living its idle life (animals.gd make, the one place a beast is made).
func _beast(kind: String, rng: RandomNumberGenerator) -> Node3D:
	return preload("res://scripts/animals.gd").make(kind, rng)


func _mill(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, kind: String, tick: Works.Tick, millers: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var door: Vector3 = sp.get("door", b["at"] + _front(b) * 0.25)
	for i in millers:
		var m := _stand(root, life, center, door, "peasant", "PickUp_Table", rng.randi(), Color.WHITE, 0.2, "miller" if i == 0 else "")
		if m:
			_face(m, b["at"])
			_mind(m, "miller", center)
	tick.stacks.append({"what": "mill", "at": sp.get("sacks", door), "yaw": float(b["yaw"]), "prop": "Bag", "nodes": [], "gap": 0.07, "lift": 0.04})
	var turner := _spinner(root, b, kind)
	if turner:
		_dress_rotor(root, b, turner, kind)
		var ax: Vector3 = Works.v3(Data.value("works", "mill.axis." + kind, [0, 0, 1]))
		tick.mills.append({"node": turner, "axis": ax.normalized(), "rpm": Data.num("works", "mill.rpm." + kind, 7.0), "speed": 0.0, "needs_grain": true})


## A mill's turning part made to read and to fit (batch7-review #6, #12): repainted in our own kit's
## textures (the Kenney rotor is one palette surface, flat salmon at town scale: canvas for sails,
## timber for a wheel; works.json mill.paint) and, where its sweep would cut a neighbour's roof, made
## smaller until it clears every other building's footprint (works.json mill.clear: how near, the
## least it shrinks to). Once a rotor, whatever rebuilds the town's life.
func _dress_rotor(root: Node3D, b: Dictionary, turner: Node3D, kind: String) -> void:
	if turner.has_meta("dressed"):
		return
	turner.set_meta("dressed", true)
	var paint: Dictionary = Data.value("works", "mill.paint." + kind, {})
	var tex_path := String(paint.get("texture", ""))
	if tex_path != "" and ResourceLoader.exists(tex_path):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(tex_path)
		m.albedo_color = Data.colour(paint.get("tint"), Color.WHITE)
		m.uv1_triplanar = true
		m.uv1_world_triplanar = false
		m.uv1_scale = Vector3.ONE * float(paint.get("scale", 1.0))
		m.roughness = 0.9
		m.cull_mode = BaseMaterial3D.CULL_DISABLED  # a sail is one sheet: seen from behind too
		for g in turner.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).material_override = m
	# The sweep: the rotor's reach from its hub, against every footprint but the mill's own.
	var C: Dictionary = Data.value("works", "mill.clear", {})
	var hub := root.to_local(turner.global_position)
	var reach := 0.0
	for g in turner.find_children("*", "VisualInstance3D", true, false):
		var box: AABB = (g as VisualInstance3D).get_aabb()
		var xf := root.global_transform.affine_inverse() * (g as Node3D).global_transform
		for i in 8:
			reach = maxf(reach, Vector2((xf * box.get_endpoint(i)).x - hub.x, (xf * box.get_endpoint(i)).z - hub.z).length())
	if reach <= 0.0:
		return
	var own := Vector2(float(b["at"].x), float(b["at"].z))
	var nearest := INF
	for fp in root.get_meta("footprints", []):
		var poly := PackedVector2Array(fp)
		if poly.size() < 3 or Geometry2D.is_point_in_polygon(own, poly):
			continue
		var q := Vector2(hub.x, hub.z)
		if q.distance_to(poly[0]) > reach + 2.0:
			continue
		for i in poly.size():
			nearest = minf(nearest, q.distance_to(Geometry2D.get_closest_point_to_segment(q, poly[i], poly[(i + 1) % poly.size()])))
	var room := nearest - float(C.get("gap", 0.04))
	if room < reach:
		var k := clampf(room / reach, float(C.get("least", 0.55)), 1.0)
		turner.scale *= k


## The part of a mill's model that turns (its sails, its wheel), found by name
## (works.json mill.spin_names) in the building the town agent placed; null when
## the model is one piece and nothing can turn.
func _spinner(root: Node3D, b: Dictionary, kind: String) -> Node3D:
	var names: Array = Data.value("works", "mill.spin_names", [])
	var bodies: Array = []
	if b.get("node") is Node3D and is_instance_valid(b["node"]):
		bodies.append(b["node"])
	else:
		for ch in root.get_children():
			if ch is Node3D and ch.name != "Life" and Vector2(ch.position.x - b["at"].x, ch.position.z - b["at"].z).length() < 0.6:
				bodies.append(ch)
	for body: Node3D in bodies:
		for n in body.find_children("*", "Node3D", true, false):
			var low := String(n.name).to_lower()
			if names.any(func(w): return low.contains(String(w))):
				return n
	return null


func _granary(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, c: Dictionary, tick: Works.Tick, queue: int, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var door: Vector3 = sp.get("door", b["at"] + _front(b) * 0.25)
	# Its sacks as full as Freeciv says the granary is.
	var most := int(Data.num("works", "stock.granary_most", 8))
	var share := clampf(float(c.get("food", 0)) / float(c.get("granary", 1)), 0.0, 1.0) if c.get("food") != null and float(c.get("granary", 0)) > 0.0 else 0.5
	tick.stacks.append({"what": "granary", "fixed": roundi(share * most), "at": sp.get("sacks", door), "yaw": float(b["yaw"]), "prop": "Bag", "nodes": [], "gap": 0.07, "lift": 0.04})
	_line(root, life, center, sp.get("queue", door + _front(b) * 0.1), _front(b), queue, "peasant", "Weight_Shift", "queue", rng)


func _inn(root: Node3D, life: Node3D, center: Vector3, b: Dictionary, tick: Works.Tick, n: Callable, rng: RandomNumberGenerator) -> void:
	var sp: Dictionary = b["spots"]
	var yaw := float(b["yaw"])
	var along := Basis(Vector3.UP, yaw) * Vector3(1, 0, 0)
	# Benches by the door; drinkers on them by day (they go in at night: works.Tick).
	var seats: Array = []
	for key in ["bench_a", "bench_b"]:
		if not sp.has(key):
			continue
		var at: Vector3 = sp[key]
		if b["dress"]:
			_prop(life, center, "Bench", at, yaw, 1.0, 0.0)
		seats += [at - along * 0.04 * FURN, at + along * 0.04 * FURN]
	var taken: PackedVector2Array = life.get_meta("standing")
	# In war or a levy the crown's men take the benches first (works.json counts.inn_soldiers).
	var soldiers := mini(int(n.call("inn_soldiers")), seats.size())
	for i in mini(int(n.call("drinkers")) + soldiers, seats.size()):
		var at: Vector3 = seats[i]
		var d := _townsperson(life, Vector3(at.x, _y(center, at), at.z), "soldier" if i < soldiers else "townsfolk", "Sitting_Drinking", rng.randi())
		d.rotation.y = yaw  # facing out to the street
		d.set_meta("bench", true)
		taken.append(Vector2(at.x, at.z))
		_mind(d, "drinker", center)
		tick.by_day.append(d)
	life.set_meta("standing", taken)
	# A long table in the yard by day, drinkers at it (works.json inn.tables; the crown's men among them in war).
	var yard: Vector3 = sp.get("yard", b["at"] + _front(b) * 0.4)
	var tables := int(Data.num("works", "inn.tables", 1))
	for k in tables:
		var at := _spot(center, yard + along * (k - (tables - 1) * 0.5) * 0.36, _blocked(root, life), life.get_meta("standing"), 0.25)
		if is_nan(at.x):
			continue
		for p in _long_table(life, center, at, _front(b), int(Data.num("works", "inn.seats", 2)), k, rng, "soldier" if int(n.call("inn_soldiers")) > 0 and k == 0 else ""):
			p.set_meta("bench", true)
			_mind(p, "drinker", center)
			tick.by_day.append(p)
	# A feast fills the yard.
	for i in n.call("revellers"):
		var r := _stand(root, life, center, yard, "townsfolk", "Cheering", rng.randi(), Color.WHITE, 0.3)
		if r:
			_face(r, b["at"])
			_mind(r, "revel", center)
	# Travellers in off the road, each with a horse tied at the rail.
	var hitch: Vector3 = sp.get("hitch", b["at"] + _front(b) * 0.3)
	for i in n.call("travellers"):
		var h: Node3D = Horse.new(rng.randi() % Horse.COATS.size())
		var hp: Vector3 = hitch + along * (0.22 * i)
		h.position = Vector3(hp.x, _y(center, hp), hp.z)
		h.rotation.y = yaw + PI  # nose to the rail
		life.add_child(h)
		h.live_idle(rng)  # head down at the rail now and then (animals.gd)
		var t := _stand(root, life, center, hp + _front(b) * 0.14, "townsfolk", "PickUp_Table", rng.randi(), Color.WHITE, 0.2)
		if t:
			_face(t, hp)
			_mind(t, "traveller", center)
	# The windows lit at night.
	var l: Dictionary = Data.value("works", "inn.light", {})
	for key in sp:
		if not String(key).begins_with("window"):
			continue
		var w: Vector3 = sp[key]
		var light := OmniLight3D.new()
		light.light_color = Data.colour(l.get("color"), Color(1.0, 0.68, 0.36))
		light.light_energy = float(l.get("energy", 0.8))
		light.omni_range = float(l.get("range", 0.7))
		light.position = Vector3(w.x, _y(center, w) + w.y, w.z)
		light.visible = false
		life.add_child(light)
		tick.lights.append(light)


## A mood's number for a town in these states (moods.json): the least over its states that set it (the shut-most
## market, the slowest...), or with `most`, the greatest; `fallback` when none does.
func _mood_num(states: Array, key: String, fallback: float, most := false) -> float:
	var out := fallback
	var any := false
	for st in states:
		var row: Variant = Data.value("moods", st, {})
		if row is Dictionary and (row as Dictionary).has(key) and (row[key] is float or row[key] is int):
			out = float(row[key]) if not any else (maxf(out, float(row[key])) if most else minf(out, float(row[key])))
			any = true
	return out


## Lines of pennants from a tall pole by the well out to poles round the seen
## half of the square (moods.json feast.bunting), each line sagging between its
## poles, the flags in turn of `colours`. One mesh for every line.
func _bunting(root: Node3D, life: Node3D, center: Vector3, well: Vector3, b: Dictionary, colours: Array, rng: RandomNumberGenerator) -> void:
	var lines := int(b.get("lines", 5))
	if lines <= 0:
		return
	var walls := _blocked(root, life)
	var taken: PackedVector2Array = life.get_meta("standing")
	# Its tall pole by the well, toward the heart; with a fountain at the heart, clear of its basin on the
	# seen side (moods.json centre.bunting), never in the water.
	var basin := centre_reach(root)
	# (On the far side of a fountain from the camera's side: the lines then cross the square toward the seen half
	# and no bare pole stands in the foreground; batch 8b goldrock-fountain.)
	var hub_want: Vector3 = (-SEEN * (basin + float(Data.num("moods", "centre.bunting", 0.1)))) if basin > 0.0 else (well + (Vector3.ZERO - well).normalized() * 0.14)
	var hub_at := _spot(center, hub_want, walls, taken, 0.2)
	if is_nan(hub_at.x):
		return
	var top := float(b.get("height", 3.8)) * S
	var low := float(b.get("edge_height", 2.8)) * S
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	var pole := func(at: Vector3, h: float) -> Vector3:
		var m := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.top_radius = 0.005
		c.bottom_radius = 0.007
		c.height = h
		c.material = wood
		m.mesh = c
		var y := _y(center, at)
		m.position = Vector3(at.x, y + h * 0.5, at.z)
		life.add_child(m)
		return Vector3(at.x, y + h, at.z)
	var hub: Vector3 = pole.call(hub_at, top)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var flags := int(b.get("flags", 12))
	var sag := float(b.get("sag", 0.45)) * S
	var face := atan2(SEEN.x, SEEN.z)
	var ring := float(b.get("ring", 0.62))
	var n := 0
	for i in lines:
		var a := face + (i - (lines - 1) * 0.5) * (2.6 / maxf(lines - 1, 1))
		var end_at := _spot(center, Vector3(sin(a), 0, cos(a)) * ring, walls, taken, 0.15)
		if is_nan(end_at.x):
			continue
		var end: Vector3 = pole.call(end_at, low)
		var dir := (end - hub)
		var along := Vector3(dir.x, 0, dir.z).normalized()
		var w := maxf(dir.length() / (flags * 2.2), float(b.get("flag_m", 0.35)) * S * 0.5)  # a pennant you can see from roof height (it was about 18 cm)
		for k in flags:
			var t := (k + 0.5) / flags
			var at := hub.lerp(end, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
			st.set_color(colours[(k + i) % colours.size()])
			st.add_vertex(at - along * w)
			st.add_vertex(at + along * w)
			st.add_vertex(at - Vector3.UP * w * 1.6)
			n += 1
	if n == 0:
		return
	st.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.name = "Bunting"
	var cloth := StandardMaterial3D.new()
	cloth.vertex_color_use_as_albedo = true
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	cloth.roughness = 0.9
	mesh.material_override = cloth
	mesh.set_meta("dress", "bunting")
	life.add_child(mesh)


static var _wagon_mesh: Mesh


## A sack slung on `p`'s right shoulder (`on`), or taken off (a porter's load: npc_mind Sack).
static func shoulder_sack(p: Node3D, on: bool) -> void:
	var skel := p.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if skel == null:
		return
	var had := skel.get_node_or_null("ShoulderSack")
	if not on:
		if had:
			had.queue_free()
		return
	if had or skel.find_bone("RightShoulder") < 0 or not ResourceLoader.exists(PROPS % "Bag"):
		return
	var S2: Array = Data.value("crowd", "errands.sack", [0.16, -0.04, 0.9])
	var at := BoneAttachment3D.new()
	at.name = "ShoulderSack"
	at.bone_name = "RightShoulder"
	skel.add_child(at)
	var bag: Node3D = (load(PROPS % "Bag") as PackedScene).instantiate()
	bag.position = Vector3(0, float(S2[0]), float(S2[1]))
	bag.scale = Vector3.ONE * float(S2[2])
	bag.rotation.z = 0.5
	at.add_child(bag)


## A horse and cart in one piece (scenes.gd's road cart, facing +z as the town's people do): the wagon, the
## horse between its shafts and the carter at the horse's head.
static func horse_cart(people: Object, rng: RandomNumberGenerator) -> Node3D:
	if _wagon_mesh == null:
		_wagon_mesh = preload("res://scripts/house_builder.gd").new().piece_mesh("Prop_Wagon")
	if _wagon_mesh == null:
		return null
	var holder := Node3D.new()
	holder.name = "HorseCart"
	var rig := Node3D.new()
	rig.rotation.y = PI  # the road cart's forward is -z
	holder.add_child(rig)
	var wagon := MeshInstance3D.new()
	wagon.mesh = _wagon_mesh
	var big := float(Data.num("people", "readable", 1.0))
	wagon.scale = Vector3.ONE * 0.1 * big
	wagon.rotation.y = PI
	rig.add_child(wagon)
	var hitch := Marker3D.new()
	hitch.position = Vector3(0, 0, -0.08 * big)
	rig.add_child(hitch)
	var Horse := preload("res://scripts/horse.gd")
	var horse: Node3D = Horse.new(rng.randi() % Horse.COATS.size())
	horse.rotation.y = PI
	hitch.add_child(horse)
	var carter: Node3D = people.make(rng, "peasant", Color.WHITE, "adult", "", "male")
	carter.position = Vector3(0.09, 0, -0.16) * big
	carter.rotation.y = PI
	rig.add_child(carter)
	holder.set_meta("carter", carter)
	# Its load: sacks in the bed (crowd.json cart.load: how many, how high the bed stands, how far it runs back).
	var L: Dictionary = Data.value("crowd", "cart.load", {})
	if ResourceLoader.exists(PROPS % "Bag"):
		var bag_scene: PackedScene = load(PROPS % "Bag")
		var nb := int(L.get("sacks", 3))
		for i in nb:
			var bag: Node3D = bag_scene.instantiate()
			bag.scale = Vector3.ONE * PROP_SCALE * big * float(L.get("size", 1.0))
			bag.position = Vector3(rng.randf_range(-0.02, 0.02), float(L.get("bed", 0.1)), float(L.get("from", 0.02)) + float(L.get("run", 0.08)) * i / maxf(nb - 1, 1)) * big
			bag.rotation.y = rng.randf() * TAU
			rig.add_child(bag)
	return holder


## Whether the square's people are agents on errands (villagers.gd _slot, npc_mind's shopper, water carrier and
## porter; crowd.json square_agents) rather than posted in place: --square-agents=on|off, else crowd.json.
static func square_agents_on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--square-agents=off"):
		return false
	return args.has("--square-agents=on") or bool(preload("res://scripts/data.gd").value("crowd", "square_agents.on", false))


## A long table at `at` (town-local), its length across `out`, set with mugs and plates, a bench
## either side and `seats` a side sat drinking, facing across it (a feast's, the inn yard's). Returns
## who sits there; their minds are the caller's to give.
func _long_table(life: Node3D, center: Vector3, at: Vector3, out: Vector3, seats: int, n: int, rng: RandomNumberGenerator, role := "", people := true) -> Array:
	var along := Vector3(-out.z, 0, out.x)
	var yaw := atan2(along.x, along.z)
	if _prop(life, center, "Table_Large", at, yaw, 1.0, 0.0) == null:
		return []
	var TOP := 0.098 * FURN  # the table's height (0.815 m at PROP_SCALE, drawn at the people's size)
	var ware := ["Mug", "Table_Plate", "Chalice", "Mug", "Pot_1", "Table_Plate", "Mug"]
	for i in 5:
		_prop(life, center, ware[(n * 3 + i) % ware.size()], at + (along * (i - 2) * 0.04 + out * rng.randf_range(-0.015, 0.015)) * FURN, rng.randf() * TAU, 1.0, TOP)
	var taken: PackedVector2Array = life.get_meta("standing")
	var sat: Array = []
	for sgn in [-1.0, 1.0]:
		var bench: Vector3 = at + out * sgn * 0.1 * FURN  # clear of the table's edge at its drawn size
		_prop(life, center, "Bench", bench, yaw, 1.0, 0.0)
		for i in seats:
			var seat: Vector3 = bench + along * (i - (seats - 1) * 0.5) * 0.08 * FURN
			if not people:
				taken.append(Vector2(seat.x, seat.z))
				sat.append({"at": Vector3(seat.x, _y(center, seat), seat.z), "dir": -out * sgn})  # a seat for the director's feaster, facing across
				continue
			var who := role if role != "" else ("townsfolk" if rng.randf() < 0.6 else "peasant")
			var p := _townsperson(life, Vector3(seat.x, _y(center, seat), seat.z), who, "Sitting_Drinking", rng.randi())
			p.rotation.y = atan2(-out.x * sgn, -out.z * sgn)  # facing across the table
			taken.append(Vector2(seat.x, seat.z))
			sat.append(p)
	life.set_meta("standing", taken)
	return sat


# --- what the director asks of the town (town_scenes.gd: it casts every scene's people) -------------

var director: Node  # town_scenes.gd, the one director (main.gd sets it): it stages each town's scenes as it is dressed


## The nearest open spot to `want` (town-local) within `reach`, kept as taken; NAN in x when there's none.
## inside: within a building's own footprint (only the others standing and the road's lanes keep them out).
func place(root: Node3D, want: Vector3, reach: float, inside := false) -> Vector3:
	var life: Node3D = root.get_node_or_null("Life")
	if life == null:
		return Vector3(NAN, 0, 0)
	var taken: PackedVector2Array = life.get_meta("standing", PackedVector2Array())
	var p := _spot(root.position, want, [] if inside else _blocked(root, life), taken, reach, root)
	if not is_nan(p.x):
		taken.append(Vector2(p.x, p.z))
		life.set_meta("standing", taken)
	return p


## The ground's height at a town-local point, town-local.
func ground_at(root: Node3D, p: Vector3) -> float:
	return _y(root.position, p)


## Whether a town-local point is open cobble: in no building's, stall's, plinth's or fire's outline, and nobody
## standing there.
func open_ground(root: Node3D, p: Vector3) -> bool:
	var life: Node3D = root.get_node_or_null("Life")
	if life == null:
		return false
	var q := Vector2(p.x, p.z)
	for t in life.get_meta("standing", PackedVector2Array()):
		if (t as Vector2).distance_to(q) < ROOM:
			return false  # someone stands there
	for fp in _blocked(root, life):
		if (fp as PackedVector2Array).size() > 2 and q.distance_to(fp[0]) < 1.5 and Geometry2D.is_point_in_polygon(q, fp):
			return false
	return true


## One of a scene's people, set down under the town's Life at `pos` (town-local), dressed as this town dresses its
## people (its rank, its holder's colour, its grief). cast_post: the work they're there for (people.gd cast_for_post).
func cast(root: Node3D, pos: Vector3, who: String, clip: String, seed: int, tint := Color.WHITE, cast_post := "", age := "", sex := "") -> Node3D:
	var life: Node3D = root.get_node_or_null("Life")
	if life == null:
		return null
	var d: Array = life.get_meta("dress", [])
	if d.size() >= 3:
		_people.dress_for(String(d[0]), d[1], bool(d[2]))
	if age == "child" and who == "townsfolk":
		who = "peasant"
	return _townsperson(life, pos, who, clip, seed, tint, cast_post, age, sex)


## A scene person's mind (npc_mind.gd, LimboAI) for their post, when the town's people have minds (minds_on).
## opening: tasks done once first (a brawling pair's blows, in step).
func mind(p: Node3D, post: String, root: Node3D, opening: Array = []) -> bool:
	var life: Node3D = root.get_node_or_null("Life")
	var town := int(life.get_meta("town_id", -1)) if life else -1
	if p == null or not minds_on(town):
		return false
	var center := root.position
	return preload("res://scripts/npc_mind.gd").give(p, post, func(q: Vector3) -> float: return _y(center, q), int(p.get_instance_id()), opening, town)


## The watch stand guard armed (scenes' guards, the patrol).
func watch(g: Node3D) -> void:
	_watch(g)


## The town's holder's colour as its posted guards wear it (crowd.json posted.lighten toward white).
func house_colour(root: Node3D) -> Color:
	var life: Node3D = root.get_node_or_null("Life")
	var col: Color = (life.get_meta("dress", [null, _house_col])[1]) if life else _house_col
	if col.a <= 0.0:
		col = _house_col
	return col.lerp(Color.WHITE, float(Data.num("crowd", "posted.lighten", 0.0)))


func off_centre(root: Node3D, p: Vector3, clear: float) -> Vector3:
	return _off_centre(root, p, clear)


## A town beast for a scene (a town dog: the wolf shrunk, tinted a hound's colour by turn), set down at `pos`.
func beast(root: Node3D, kind: String, pos: Vector3, tints: Array, i: int, rng: RandomNumberGenerator) -> Node3D:
	var life: Node3D = root.get_node_or_null("Life")
	var b := preload("res://scripts/animals.gd").make(kind, rng)
	if b == null or life == null:
		return null
	if not tints.is_empty():
		var col := Data.colour(tints[i % tints.size()], Color.WHITE)
		for mi in b.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).get_active_material(0)
			if m is StandardMaterial3D:
				var copy: StandardMaterial3D = m.duplicate()
				copy.albedo_color = col
				(mi as MeshInstance3D).material_override = copy
	b.position = pos
	b.rotation.y = rng.randf() * TAU
	life.add_child(b)
	return b


# --- the scenes' props (town_scenes.json standing rows name them: dress) ------------------------------
# Each lays what a scene needs standing in the town and says where its people go (anchors, town-local).

## The nearest spot to `want` (town-local) a prop `half` across each way fits on: its middle and its four sides on
## open ground (_open: no building, stall or plinth, nobody standing) and off the road's lanes, on rings widening out
## to half the square; NAN if none.
func _room_for(center: Vector3, want: Vector3, half: float, walls: Array, root: Node3D) -> Vector3:
	var taken: PackedVector2Array = PackedVector2Array()
	var reach := float(root.get_meta("square_r", 1.0)) * 0.5
	var r := 0.0
	while r <= reach:
		var n := 1 if r == 0.0 else int(TAU * r / 0.05)
		for i in n:
			var p := want + Vector3(cos(TAU * i / n), 0, sin(TAU * i / n)) * r
			var fits := not on_lane(root, center + p)
			for o in [Vector3.ZERO, Vector3(half, 0, 0), Vector3(-half, 0, 0), Vector3(0, 0, half), Vector3(0, 0, -half)]:
				if fits and not _open(center, p + o, walls, taken):
					fits = false
			if fits:
				return p
		r += 0.05
	return Vector3(NAN, 0, 0)


