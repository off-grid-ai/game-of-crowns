extends RefCounted
const Particles := preload("res://scripts/particles.gd")  # smoke and fire on the GPU
## The life director: turns what Freeciv says a town is doing into something you
## can see. Construction rises with its real progress; recruits drill on the
## square while troops train; hunger browns the fields and queues people at the
## keep; celebrations light a bonfire; unrest sets roofs smoking.

const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const S := 0.12
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


## Whether a town's people have minds (LimboAI): the one rule, for the town's
## scenes and its villagers alike. Every town has them by default (2026-11-11,
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
	# What stands in people's way, town-local like the town's own footprints:
	# the building site and each group (town_nav.gd walks villagers round them).
	life.set_meta("footprints", [])
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
	# The town's health, readable at its door: beggars and the homeless when it
	# starves (more in a bigger town), an angry crowd when it's in disorder.
	if c.get("disorder", false):
		_crowd(root, life, center, rng, 14, true)
	elif hungry:
		_crowd(root, life, center, rng, 4 + mini(int(c.get("size", 1)) / 2, 8), false)
	if not c.get("disorder", false):
		_buyers_more = Data.value("moods", "relief.buyers", []) if "relief" in _mood_states(c) else []
		_trade(root, life, center, rng, not hungry, _mood_num(c, "stalls_open", 1.0))  # a hungry town's stalls are kept, bare: no buyers; war and hunger shut some
		if not hungry and bool(root.get_meta("crown_seat", false)):
			_market_day(root, life, center, rng)  # the crown's seat: the realm's busiest market
	if c.get("celebrating", false):
		_fire_at = _fire_spot(root)
		_bonfire(life, center)
		_revels(root, life, center, rng, 6 + mini(int(c.get("size", 1)), 8))
	if c.get("disorder", false):
		_unrest(life, center, rng)
	_dress(root, life, center, c, rng, house)
	_works(root, life, center, c, rng)
	if not c.get("disorder", false):
		_square_life(root, life, center, c, rng)  # before the moods: a funeral walks with the square's walkers
	_moods(root, life, center, c, rng, house)
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
const KEEPER_BACK := 0.07  # a stall keeper stands this far behind the counter's back edge (about half a metre)
const LANE := 0.06  # past a road's verge, ground the travellers on it keep: nobody stands there
const HEART := 0.2  # about 1.7 m round a town's heart, where every road's travellers come through and wait


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
	return roads != null and roads.has_method("on_path") and roads.on_path(world, LANE)
## The way a camera faces as it comes down into a town (camera_rig.frame_town
## stands it at yaw 35 degrees, looking back at the heart): the half of the
## square it sees first. Dressing that tells the town's news goes there.
const SEEN := Vector3(-0.5736, 0, -0.8192)
static var CLEAR: float = 0.05 * preload("res://scripts/data.gd").num("people", "readable", 1.0)  # how far a person keeps off a wall or a fence


## Everything that stands in the town, town-local: its buildings, walls, fences
## and stalls (towns.gd) and whatever the life here has put up.
func _blocked(root: Node3D, life: Node3D) -> Array:
	return root.get_meta("footprints", []) + life.get_meta("footprints", [])


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


## A brawling pair on the switch: both scuffle for the same count of blows
## (Fist_Fight_A against Fist_Fight_B), then each riots with the rest.
func _mind_pair(a: Node3D, b: Node3D, center: Vector3) -> bool:
	if not _town_on:
		return false
	var Mind := preload("res://scripts/npc_mind.gd")
	var blows := randi_range(4, 5)
	var ground := func(q: Vector3) -> float: return _y(center, q)
	Mind.give(a, "riot", ground, int(a.get_instance_id()), [Mind.run(["Fist_Fight_A"], blows, blows)], _town_id)
	Mind.give(b, "riot", ground, int(b.get_instance_id()), [Mind.run(["Fist_Fight_B"], blows, blows)], _town_id)
	return true


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
		# The rank is one block to walk round, not a lane to thread.
		var mid := -face * dist
		life.set_meta("footprints", life.get_meta("footprints") + [_rect(mid, Vector2(count * 0.45 + 0.1, 0.36), atan2(face.x, face.z))])
		break
	life.set_meta("doing", doing_line("UnitType", unit, progress))


## Outside the keep: the hungry beg and camp rough by a small fire, or, in
## disorder, a crowd presses at the door with its grievances.
func _crowd(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int, angry: bool) -> void:
	var dir := Vector3(cos(rng.randf() * TAU), 0, sin(rng.randf() * TAU))
	if angry:
		# A riot is the town's news: on the side of the square the camera looks
		# across as it comes down, give or take, never behind the lens.
		dir = SEEN.rotated(Vector3.UP, rng.randf_range(-0.25, 0.25))
	var side := Vector3(-dir.z, 0, dir.x)
	var knots := maxi(1, ceili(count / 3.0))
	for i in count:
		var p := dir * rng.randf_range(0.55, 0.95) + side * rng.randf_range(-0.45, 0.45)
		if not angry:
			# The hungry and the grieving keep in knots of two or three spread
			# round the town's edge, never one crowd at a door (Mac's call).
			var ang := atan2(dir.z, dir.x) + TAU * float(i / 3) / knots + rng.randf_range(-0.15, 0.15)
			var hub := Vector3(cos(ang), 0, sin(ang)) * rng.randf_range(1.0, 1.4)
			p = hub + Vector3(rng.randf_range(-0.09, 0.09), 0, rng.randf_range(-0.09, 0.09))
		var anim: String
		if angry:
			anim = ["Arguing", "Yelling", "Arguing", "Yelling"][i % 4]  # arguing, shouting at the door they all face
		else:
			anim = ["Defeated", "Crying", "Kneeling", "Idle", "Praying", "Looking_Around"][rng.randi() % 6]  # waiting, weeping, begging on their knees (none talking to the air)
		var f := _stand(root, life, center, p, "peasant", anim, rng.randi(), Color(0.55, 0.5, 0.45) if not angry else Color(0.7, 0.66, 0.6))
		if f == null:
			continue  # no room left at the door: the crowd is what fits
		var look := -f.position + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))
		f.rotation.y = atan2(look.x, look.z) if angry or i % 2 == 0 else rng.randf() * TAU
		# Rioters; and at the edge, beggars, mourners and refugees in turn.
		_mind(f, "riot" if angry else ["beg", "mourn", "refugee"][i % 3], center)
	if angry:
		# The watch holds the door against them, and here and there it comes to blows.
		for i in 3:
			var g := _stand(root, life, center, dir * 0.32 + side * (i - 1) * 0.14, "soldier", "Sword_Idle", rng.randi(), Color(0.55, 0.5, 0.45), 0.2)
			if g:
				g.rotation.y = atan2(dir.x, dir.z)  # facing the crowd
				_watch(g)
				_mind(g, "guard", center)
		# What the crowd has done to the square: a cart turned on its side, crates
		# and a cask knocked over and rolled, in the press where a street camera sees it.
		var tipped: Node3D = Real.make(Real.one("cart"))
		var tip_at := _spot(center, dir * 0.8, _blocked(root, life), life.get_meta("standing"), 0.35)
		if tipped and not is_nan(tip_at.x):
			tipped.position = Vector3(tip_at.x, _y(center, tip_at) + 0.05, tip_at.z)
			tipped.rotation = Vector3(0, atan2(side.x, side.z), PI * 0.5)  # over on its side
			tipped.set_meta("dress", "overturned cart")
			life.add_child(tipped)
			life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(tip_at, Real.footprint(Real.one("cart")), atan2(side.x, side.z))])
		elif tipped:
			tipped.free()
		for k in 4:
			var spill := dir * rng.randf_range(0.5, 0.8) + side * rng.randf_range(-0.2, 0.2)
			var thing := _prop(life, center, ["Crate_Wooden", "Barrel", "FarmCrate_Empty", "FarmCrate_Apple"][k], spill, rng.randf() * TAU, 1.0, 0.0, 0.07)
			if thing:
				thing.rotation.x = PI * 0.5 if k == 1 else rng.randf_range(-0.6, 0.6)  # the cask on its side, the crates askew
				thing.set_meta("dress", "wreckage")
		for k in 2:
			var at := dir * rng.randf_range(0.6, 0.8) + side * (0.4 if k == 0 else -0.4)  # in the press, not off at its rim
			var a := _stand(root, life, center, at, "peasant", "Fist_Fight_A", rng.randi(), Color(0.7, 0.66, 0.6), 0.25)
			if a == null:
				continue
			var b := _stand(root, life, center, a.position + side * 0.2, "peasant", "Fist_Fight_B", rng.randi(), Color(0.7, 0.66, 0.6), 0.1)
			if b == null:
				continue
			a.rotation.y = atan2(b.position.x - a.position.x, b.position.z - a.position.z)
			b.rotation.y = a.rotation.y + PI
			# On the switch: the pair scuffle for the same while, then riot with the rest.
			if _mind_pair(a, b, center):
				continue
			# A scuffle, not a fight without end: about 8 s, then they're back to shouting.
			for f in [a, b]:
				var stop := Timer.new()
				stop.one_shot = true
				f.add_child(stop)
				stop.timeout.connect(func():
					if is_instance_valid(f):
						_people.play(f, "Arguing"))
				stop.start(rng.randf_range(7.0, 9.0))
	if not angry:
		# Where they lie at night: dark bedrolls in a row against the wall, and a
		# cooking fire that's a few embers and a thread of smoke, not a beacon.
		var camp := dir * 1.35 + side * rng.randf_range(-0.3, 0.3)
		var rag := StandardMaterial3D.new()
		rag.albedo_color = Color(0.3, 0.26, 0.22)
		rag.roughness = 1.0
		var roll_mesh := CapsuleMesh.new()
		roll_mesh.radius = 0.018
		roll_mesh.height = 0.17
		for i in mini(count / 2, 5):
			var roll := MeshInstance3D.new()
			roll.mesh = roll_mesh
			roll.material_override = rag
			var q := camp + side * (i - 2) * 0.06 + dir * rng.randf_range(-0.03, 0.03)
			roll.position = Vector3(q.x, _y(center, q) + 0.012, q.z)
			roll.rotation = Vector3(PI / 2, atan2(dir.x, dir.z) + rng.randf_range(-0.2, 0.2), 0)
			life.add_child(roll)
		var smoke := CPUParticles3D.new()
		smoke.amount = 8
		smoke.lifetime = 3.0
		smoke.direction = Vector3.UP
		smoke.spread = 6
		smoke.initial_velocity_min = 0.04
		smoke.initial_velocity_max = 0.08
		smoke.scale_amount_min = 0.03
		smoke.scale_amount_max = 0.07
		smoke.color = Color(0.35, 0.33, 0.31, 0.25)
		smoke.angle_min = -180.0
		smoke.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		q.material = preload("res://scripts/towns.gd").smoke_material(true)
		smoke.mesh = q
		var fp := camp - dir * 0.12
		smoke.position = Vector3(fp.x, _y(center, fp) + 0.03, fp.z)
		life.add_child(Particles.to_gpu(smoke))


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
	# step of heat past its stones, is ground nobody claims, steps on or walks.
	var keep := fire_reach()
	life.set_meta("footprints", life.get_meta("footprints") + [_rect(_fire_at, Vector2(keep, keep) * 2.0, 0.0)])
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
const HEAT := 0.06  # past the stones, a step nobody takes: half a metre


## How far from a bonfire's middle the ground is the fire's: its ring of
## stones as wide as it stands (the model's real footprint, scaled), and HEAT.
static func fire_reach() -> float:
	var foot := Real.footprint(Real.one("fire_pit"))
	return maxf(foot.x, foot.y) * RING_SCALE * 0.5 + HEAT if foot != Vector2.ZERO else 0.23


## A feast: the town in a ring round the bonfire, dancing, cheering and
## drinking, everyone turned to the fire: a ring of faces in its light, a
## shoulder apart, each on their own place on it and none inside it.
func _revels(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int) -> void:
	var spin := rng.randf() * TAU
	var inner := fire_reach() + 0.08  # the near edge of the ring: past the heat, and a step (the revel's own steps) more
	for i in count:
		var a := spin + TAU * i / count + rng.randf_range(-0.1, 0.1)
		var want := _fire_at + Vector3(cos(a), 0, sin(a)) * rng.randf_range(inner, inner + 0.12)
		var move: String = ["Dance", "Cheering", "Dance", "Drinking", "Cheering", "Dance"][i % 6]
		var f := _stand(root, life, center, want, "townsfolk" if i % 3 else "peasant", move, rng.randi(), Color.WHITE, 0.06)
		if f:
			f.rotation.y = atan2(_fire_at.x - f.position.x, _fire_at.z - f.position.z)
			_mind(f, "revel", center)


## Trade at the market: a keeper behind each stall facing the square, and a
## buyer or two at its front, haggling (none when there's nothing to buy).
func _trade(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator, buyers := true, open := 1.0) -> void:
	var keepers := {}  # stall index -> its keeper, for a shopper at its front to be served (npc_mind Serve)
	root.set_meta("keepers", keepers)
	var si := -1
	for st in root.get_meta("stalls", []):
		si += 1
		var m: Vector3 = st[0]
		if open < 1.0 and float(absi(hash(Vector2i(roundi(m.x * 100.0), roundi(m.z * 100.0)))) % 1000) / 1000.0 >= open:
			continue  # shut for the war or the hunger (moods.json stalls_open): no keeper, no buyers, the same stalls each time
		var out := Vector3(m.x, 0, m.z).normalized()  # from the square's heart to the stall
		# The keeper's mark: behind the counter, on the stall's back side (the
		# model faces the square), just clear of its footprint, facing the lane
		# over the goods (the judge's spec). At the counter's end he stood in the
		# heap of goods towns.gd _plaza piles there (and knelt, on Interact):
		# Crowford's log had him inside the stall's footprint, unseen.
		# Failing the mark (someone there), past either end of the goods.
		var along := Vector3(-out.z, 0, out.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var taken: PackedVector2Array = life.get_meta("standing")
		var at := Vector3(NAN, 0, 0)
		var marks: Array[Vector3] = [m + out * (float(st[1]) * 0.5 + KEEPER_BACK)]
		for end in [1.0, -1.0]:
			marks.append(m + along * end * (float(st[2]) * 0.5 + 0.22) - out * float(st[1]) * 0.25)
		for try: Vector3 in marks:
			var free := true
			for q: Vector2 in taken:
				if q.distance_to(Vector2(try.x, try.z)) < ROOM:
					free = false
					break
			if free:
				at = try
				break
		if is_nan(at.x):
			continue  # this stall's keeper is the next one's: one keeps both
		at.y = _y(center, at)
		var keeper := _townsperson(life, at, "townsfolk", ["Idle_Talking", "Pointing_Forward", "Nodding"][rng.randi() % 3], rng.randi(), Color.WHITE, "stallholder")
		keeper.rotation.y = atan2(-out.x, -out.z)
		keepers[si] = keeper
		if si > 0 and not keepers.has(si - 1):
			keepers[si - 1] = keeper  # the stall before had no keeper of its own: this one keeps both
		_pile(root, life, center, si, m, out, float(st[2]))
		_mind(keeper, "trade", center)
		taken.append(Vector2(at.x, at.z))
		life.set_meta("standing", taken)
		var many: Array = _market_knobs(root).get("buyers", [1, 2])  # the crown's market draws more to each stall
		if not _buyers_more.is_empty() and int(_buyers_more[1]) > int(many[1]):
			many = _buyers_more  # the tax remitted: the market fills (moods.json relief.buyers)
		if square_agents_on():
			many = Data.value("crowd", "square_agents.posted.buyers", many)  # the villagers come to the stalls themselves
		for i in rng.randi_range(int(many[0]), int(many[1])) if buyers else 0:
			var side := Vector3(-out.z, 0, out.x) * rng.randf_range(-0.12, 0.12)
			var buyer := _stand(root, life, center, m - out * (float(st[1]) * 0.5 + 0.12) + side, "townsfolk" if rng.randf() < 0.7 else "peasant", ["Idle_Talking", "Arguing", "Nodding"][rng.randi() % 3], rng.randi(), Color.WHITE, 0.2)
			if buyer:
				var to := m - buyer.position
				buyer.rotation.y = atan2(to.x, to.z)
				_mind(buyer, "buy", center)


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


## The crown's market at midday (art target 01-town: some twenty at work round the square): a
## smith at his anvil, a carter selling from his cart, porters at the stalls' ends, all on the
## half of the square a camera coming in sees. Each stands where there's room, or not at all.
func _market_day(root: Node3D, life: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	var k := _market_knobs(root)
	var stalls: Array = root.get_meta("stalls", [])
	var square_r := float(root.get_meta("square_r", 1.0))
	var market := Vector3.ZERO
	for st in stalls:
		market += st[0]
	var toward := (market / maxf(1.0, stalls.size())).normalized() if not stalls.is_empty() else SEEN
	var side := Vector3(-toward.z, 0, toward.x)
	if side.dot(SEEN) < 0.0:
		side = -side  # the seen half
	# The smith: an anvil on the square's edge, hammering; not when the town's smithy stands on the square (towns.gd
	# _smithy, 01-town's forge): one smith, at his forge (crowd.json square_agents.smith_in_smithy).
	var smithy := false
	var wk: Dictionary = root.get_meta("works", {})
	if wk.has("forge") and bool(Data.value("crowd", "square_agents.smith_in_smithy", true)) and square_agents_on():
		smithy = (wk["forge"]["at"] as Vector3).length() < square_r * 1.8
	if not smithy and bool(k.get("smith", true)) and preload("res://scripts/weapons.gd").can_play("Hammer_Swing"):
		var at := side * square_r * 0.72
		var anvil := _prop(life, center, "Anvil", at, atan2(-side.x, -side.z), 1.0, 0.0, 0.1)
		if anvil:
			_prop(life, center, "Bucket_Metal", at + Vector3(-side.z, 0, side.x) * 0.12, 0.0, 1.0, 0.0, 0.05)
			var smith := _stand(root, life, center, at - side * 0.12, "townsfolk", "Hammer_Swing", rng.randi(), Color.WHITE, 0.2, "smith")
			if smith:
				smith.rotation.y = atan2(side.x, side.z)  # facing his anvil, his back to the houses
				_mind(smith, "smith", center)
	# The carter: a cart drawn up on the square across from the smith, selling from its bed.
	for i in int(k.get("carts", 1)):
		var cp := (-side * 0.62 + toward * (0.2 * i - 0.1)) * square_r
		# Meshy's merchant cart in its place when it's judged and in (--landmarks=meshy; data/meshy.json square_cart).
		var cart: Node3D = Real.meshy_piece("square_cart")
		if cart:
			cart.position = Vector3(cp.x, _y(center, cp), cp.z)
			cart.rotation.y = atan2(toward.x, toward.z)
			life.add_child(cart)
			life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(cp, Vector2(0.4, 0.3), cart.rotation.y)])
		else:
			cart = _prop(life, center, "Stall_Cart_Empty", cp, atan2(toward.x, toward.z), 1.0, 0.0, 0.18)
		if cart:
			for g in 2:
				_prop(life, center, ["FarmCrate_Apple", "Barrel_Apples", "FarmCrate_Carrot"][(i + g) % 3], cp + toward * (0.05 - 0.1 * g), rng.randf() * TAU, 1.0, 0.0, 0.05)
			var carter := _stand(root, life, center, cp + side * 0.16, "peasant", "Idle_Talking", rng.randi(), Color.WHITE, 0.2)
			if carter:
				carter.rotation.y = atan2(-side.x, -side.z)
				_mind(carter, "trade", center)
			var buyer := _stand(root, life, center, cp - side * 0.18, "townsfolk", "Arguing", rng.randi(), Color.WHITE, 0.2)
			if buyer:
				buyer.rotation.y = atan2(side.x, side.z)
				_mind(buyer, "buy", center)
	# Porters at the stalls' ends, a load in their arms.
	var porters := int(k.get("porters", 3))
	for i in porters:
		if stalls.is_empty():
			break
		var st: Array = stalls[i % stalls.size()]
		var m: Vector3 = st[0]
		var out := Vector3(m.x, 0, m.z).normalized()
		var along := Vector3(-out.z, 0, out.x) * (1.0 if i % 2 == 0 else -1.0)
		var p := _stand(root, life, center, m + along * (float(st[2]) * 0.5 + 0.18) - out * 0.15, "peasant", "Carrying", rng.randi(), Color.WHITE, 0.25)
		if p:
			p.rotation.y = atan2(-out.x, -out.z) + rng.randf_range(-0.8, 0.8)
			_mind(p, "porter", center)  # fetch, carry, set down


func _unrest(life: Node3D, center: Vector3, rng: RandomNumberGenerator) -> void:
	for i in 2:
		var off := Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
		var p := CPUParticles3D.new()
		p.amount = 24
		p.lifetime = 4.0
		p.direction = Vector3.UP
		p.spread = 10
		p.initial_velocity_min = 0.2
		p.initial_velocity_max = 0.35
		p.scale_amount_min = 0.15
		p.scale_amount_max = 0.35
		var grad := Gradient.new()
		grad.set_color(0, Color(0.15, 0.13, 0.12, 0.7))
		grad.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
		p.color_ramp = grad
		p.angle_min = -180.0
		p.angle_max = 180.0
		var q := QuadMesh.new()
		q.size = Vector2(0.6, 0.6)
		q.material = preload("res://scripts/towns.gd").smoke_material(true)
		p.mesh = q
		p.position = off + Vector3(0, _y(center, off) + 0.6, 0)
		life.add_child(Particles.to_gpu(p))


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
	# The site, its scaffold and its timber stand in the way: walk round them.
	life.set_meta("footprints", life.get_meta("footprints", []) + [plot, _rect(base + Vector3(f.x * 0.55 + 0.2, 0, 0).rotated(Vector3.UP, ang), Vector2(0.42, 0.36), ang),
		_rect(base + Vector3(f.x * 0.55 + 0.25, 0, f.y * 0.55 + 0.35).rotated(Vector3.UP, ang), Vector2(0.4, 0.3), ang + 0.4)])
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
const SITE_SHOWS := 0.35
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
		life.set_meta("footprints", [])
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
const PROP_SCALE := 0.12  # the props kit is in metres; a person here stands about 0.2
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


func _prop(life: Node3D, center: Vector3, name: String, at: Vector3, yaw := 0.0, scale := 1.0, lift := 0.0, size := 0.0) -> Node3D:
	if not _prop_cache.has(name):
		_prop_cache[name] = load(PROPS % name) if ResourceLoader.exists(PROPS % name) else null
	var scene: PackedScene = _prop_cache[name]
	if scene == null:
		return null
	var n: Node3D = scene.instantiate()
	if name in FURN_NAMES:
		scale *= FURN
		size *= FURN
	n.scale = Vector3.ONE * PROP_SCALE * scale
	n.position = Vector3(at.x, _y(center, at) + lift, at.z)
	n.rotation.y = yaw
	life.add_child(n)
	# Something to walk round (a table, a stand, a crate), as every group in the square is.
	if size > 0.0:
		life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(at, Vector2(size, size * 0.6), yaw)])
	return n


func _dress(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, rng: RandomNumberGenerator, house := {}) -> void:
	var stalls: Array = root.get_meta("stalls", [])
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	# At every stall's front: what it has to sell, or that it has nothing.
	var goods: Array = []
	if c.get("prosperity", false) or ("relief" in _mood_states(c) and bool(Data.value("moods", "relief.goods", false))):
		goods = ["FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Apples", "Coin_Pile"]
	elif c.get("famine", false) or c.get("atWar", false) or c.get("grief", false):
		goods = ["FarmCrate_Empty", "Crate_Wooden"]  # shut or sold out
	for st in stalls:
		var m: Vector3 = st[0]
		var out := Vector3(m.x, 0, m.z).normalized()
		var along := Vector3(-out.z, 0, out.x)
		for i in goods.size():
			_prop(life, center, goods[i], m - out * (float(st[1]) * 0.5 + 0.06) + along * ((i - (goods.size() - 1) * 0.5) * 0.07), atan2(out.x, out.z), 1.0, 0.0, 0.06)
	# Where the eye lands: inside the square, between its heart and the far side
	# from the well (the judge: dressing at the edge is dressing nobody sees),
	# on the half of the square a camera coming down into the town looks across.
	var edge := Vector3(-well.z, 0, well.x).normalized() * 0.55  # across the square from the well-to-market line, clear of the stalls
	if edge.dot(SEEN) < 0.0:
		edge = -edge
	var side := Vector3(-edge.z, 0, edge.x).normalized()
	if c.get("atWar", false):
		# A barricade cart across the road in, weapons stacked, and more of the watch.
		var cart: Node3D = Real.make(Real.one("cart"))
		var cart_at := _spot(center, edge * 1.2, _blocked(root, life), life.get_meta("standing"), 0.3)  # the nearest open ground to the way in
		if cart and not is_nan(cart_at.x):
			cart.position = Vector3(cart_at.x, _y(center, cart_at), cart_at.z)
			cart.rotation.y = atan2(side.x, side.z) + 0.35  # slewed across the way, not parked
			cart.set_meta("dress", "barricade")
			life.add_child(cart)
			life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(cart_at, Real.footprint(Real.one("cart")), atan2(side.x, side.z) + 0.35)])
		elif cart:
			cart.free()  # no room on that road: no cart across it
		# Crates and casks heaped against it: a barricade, not a cart parked.
		for k in 4:
			var heap := edge * (1.2 + (0.06 if k % 2 else -0.06)) + side * (0.24 + k * 0.07) * (1.0 if k < 2 else -1.0)
			_prop(life, center, ["Crate_Wooden", "Barrel", "FarmCrate_Empty", "Crate_Wooden"][k], heap, rng.randf() * TAU, 1.0, 0.0, 0.07)
		# The lord's standard planted either side of the way, high over the heads: seen from any street.
		var col := Color.from_string(String(house.get("color", "#8a2a1e")), Color(0.55, 0.16, 0.12))
		for k in [-1.0, 1.0]:
			var at: Vector3 = edge * 1.1 + side * 0.28 * k  # close enough together that a street camera has both
			var flag := Heraldry.standard(house, col, STANDARD_TALL)
			flag.position = Vector3(at.x, _y(center, at), at.z)
			flag.rotation.y = atan2(-edge.x, -edge.z)
			flag.set_meta("dress", "standard")
			life.add_child(flag)
			life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(at, Vector2(0.05, 0.05), 0.0)])
		_prop(life, center, "WeaponStand", edge * 1.05 + side * 0.2, atan2(-edge.x, -edge.z), 1.0, 0.0, 0.1)
		_prop(life, center, "Shield_Wooden", edge * 1.05 - side * 0.2, atan2(-edge.x, -edge.z))
		for i in 3:
			var g := _stand(root, life, center, edge * 0.95 + side * (i - 1) * 0.22, "soldier", "Sword_Idle", rng.randi(), Color.WHITE, 0.2)
			if g:
				g.rotation.y = atan2(edge.x, edge.z)  # facing the road out
				_watch(g)
				_mind(g, "guard", center)
	if c.get("grief", false):
		# Mourners gathered at the well, candles set down; at a fountain, round its rim, outside the basin
		# (moods.json centre.mourners, centre.candles: past its real radius).
		var basin := centre_reach(root)
		var kneel := basin + float(Data.num("moods", "centre.mourners", 0.08)) if basin > 0.0 else 0.22
		var set_down := basin + float(Data.num("moods", "centre.candles", 0.04)) if basin > 0.0 else 0.19
		for i in 3:
			var a := TAU * i / 3.0
			var f := _stand(root, life, center, well + Vector3(cos(a), 0, sin(a)) * kneel, "peasant", "Kneeling", rng.randi(), Color(0.35, 0.33, 0.32), 0.1)
			if f:
				f.rotation.y = atan2(well.x - f.position.x, well.z - f.position.z)
				_mind(f, "mourn", center)
		for i in 3:
			_prop(life, center, "Candle_1", well + Vector3(cos(i * 2.1), 0, sin(i * 2.1)) * set_down)  # round the well's curb (its winch reaches 0.16 out) or the basin's rim, not in it
	if c.get("prosperity", false):
		# One more stall in good times, by the well, heaped with produce.
		var extra := _off_centre(root, well + side * 0.38, float(Data.num("moods", "centre.stall", 0.2)))  # the canopy clear of a fountain's rim
		var stall := _prop(life, center, "Stall_Empty", extra, atan2(-extra.x, -extra.z), 1.0, 0.0, 0.16)
		if stall:
			for i in 3:
				_prop(life, center, ["FarmCrate_Apple", "FarmCrate_Carrot", "Barrel_Apples"][i], extra + Vector3(-extra.z, 0, extra.x).normalized() * (i - 1) * 0.06 - extra.normalized() * 0.08, atan2(-extra.x, -extra.z))
		# A lute at the well and children at play.
		var lute := _stand(root, life, center, well + side * 0.18, "townsfolk", "Lute_Playing" if preload("res://scripts/weapons.gd").can_play("Lute_Playing") else "Clapping", rng.randi(), Color.WHITE, 0.15)  # a lute only once there's a lute
		if lute:
			_mind(lute, "revel", center)
	if c.get("grasping", false):
		# The tax collector's table in the square, coin and ledger on it, a guard by him, a queue muttering.
		var at := edge * 0.6
		_prop(life, center, "Table_Large", at, atan2(side.x, side.z), 1.0, 0.0, 0.16)
		var TABLE_TOP := 0.098 * FURN  # the table's height (0.815 m at PROP_SCALE, drawn at the people's size): coin and ledger lie on it
		_prop(life, center, "Coin_Pile", at + side * 0.04, 0.0, 1.0, TABLE_TOP)
		_prop(life, center, "Scroll_1", at - side * 0.04, 0.0, 1.0, TABLE_TOP)
		_prop(life, center, "Chest_Wood", at + edge.normalized() * 0.2, atan2(side.x, side.z), 1.0, 0.0, 0.07)
		var collector := _stand(root, life, center, at + edge.normalized() * 0.13, "townsfolk", "PickUp_Table", rng.randi(), Color(0.45, 0.4, 0.3), 0.1)
		if collector:
			collector.rotation.y = atan2(-edge.x, -edge.z)
			_mind(collector, "trade", center)
		var guard := _stand(root, life, center, at + side * 0.18, "soldier", "Sword_Idle", rng.randi(), Color.WHITE, 0.1)
		if guard:
			_watch(guard)
			_mind(guard, "guard", center)
		for i in 3:
			var q := _stand(root, life, center, at - edge.normalized() * (0.18 + i * 0.1), "peasant", "Arguing", rng.randi(), Color(0.6, 0.55, 0.5), 0.08)
			if q:
				q.rotation.y = atan2(edge.x, edge.z)
				_mind(q, "riot", center)


# --- the working buildings (works.gd, realm/data/works.json) --------------------

const Works := preload("res://scripts/works.gd")
const Dressing := preload("res://scripts/dressing.gd")
const Horse := preload("res://scripts/horse.gd")
const Data := preload("res://scripts/data.gd")
const NEWS := ["feast", "levy", "war", "hunger", "low", "relief", "justice", "grant", "build"]  # states the crier cries in the square (the last four: a court ruling, the herald's news)


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
	if all.has("tannery"):
		for i in n.call("tanners"):
			var sp: Dictionary = all["tannery"]["spots"]
			var t := _stand(root, life, center, sp.get("vats", all["tannery"]["at"]), "peasant", "Fixing_Kneeling", rng.randi(), Color.WHITE, 0.2)
			if t:
				_face(t, all["tannery"]["at"])
				_mind(t, "tanner", center)
	if all.has("inn"):
		_inn(root, life, center, all["inn"], tick, n, rng)
	if NEWS.any(func(st): return st in active):
		_crier(root, life, center, tick, n.call("listeners"), rng)


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
		_prop(life, center, "Anvil", anvil, float(b["yaw"]), 1.0, 0.0, 0.1)
		if sp.has("trough"):
			_prop(life, center, "Bucket_Metal", sp["trough"], 0.0, 1.0, 0.0, 0.05)
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
	glow.light_color = Works.colour(g.get("color"), Color(1.0, 0.52, 0.22))
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
		_prop(life, center, "WeaponStand", rack, float(b["yaw"]), 1.0, 0.0, 0.1)
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
		m.albedo_color = Works.colour(paint.get("tint"), Color.WHITE)
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
			_prop(life, center, "Bench", at, yaw, 1.0, 0.0, 0.0)
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
		light.light_color = Works.colour(l.get("color"), Color(1.0, 0.68, 0.36))
		light.light_energy = float(l.get("energy", 0.8))
		light.omni_range = float(l.get("range", 0.7))
		light.position = Vector3(w.x, _y(center, w) + w.y, w.z)
		light.visible = false
		life.add_child(light)
		tick.lights.append(light)


## The crier in the square with the news, and a ring of listeners.
func _crier(root: Node3D, life: Node3D, center: Vector3, tick: Works.Tick, listeners: int, rng: RandomNumberGenerator) -> void:
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var at := well + SEEN * Data.num("works", "crier.from_well", 0.35)
	var crier := _stand(root, life, center, at, "townsfolk", "Yelling", rng.randi(), Color.WHITE, 0.3, "crier")
	if crier == null:
		return
	var toward := SEEN  # he faces the seen half of the square, his listeners before him
	crier.rotation.y = atan2(toward.x, toward.z)
	_mind(crier, "crier", center)
	tick.by_day.append(crier)
	var ring: Array = Data.value("works", "crier.ring", [0.22, 0.38])
	for i in listeners:
		var ang := atan2(toward.x, toward.z) + lerpf(-1.6, 1.6, (i + 0.5) / maxf(1.0, listeners)) + rng.randf_range(-0.12, 0.12)
		var r := rng.randf_range(float(ring[0]), float(ring[1]))
		var p := _stand(root, life, center, crier.position + Vector3(sin(ang), 0, cos(ang)) * r, "townsfolk", "Nodding", rng.randi(), Color.WHITE, 0.12)
		if p:
			_face(p, crier.position)
			_mind(p, "listener", center)
			tick.by_day.append(p)


# --- the realm's state in the streets (realm/data/moods.json) -------------------

var _buyers_more: Array = []  # buyers at each stall while a ruling's relief stands (moods.json relief.buyers), else []

## The town's states (works.gd: war, a levy, hunger, a feast...) that moods.json
## dresses, [] with the switch off (--moods=off).
func _mood_states(c: Dictionary) -> Array:
	if not bool(Data.value("moods", "on", true)) or OS.get_cmdline_user_args().has("--moods=off"):
		return []
	return Works.states(c, _town_id).filter(func(st): return (Data.value("moods", st, {}) as Dictionary).size() > 0)


## A mood's number for this town: the least over its states that set it (the
## shut-most market, the slowest...), or with `most`, the greatest; `fallback` when none does.
func _mood_num(c: Dictionary, key: String, fallback: float, most := false) -> float:
	var out := fallback
	var any := false
	for st in _mood_states(c):
		var row: Dictionary = Data.value("moods", st, {})
		if row.has(key) and row[key] is float:
			out = float(row[key]) if not any else (maxf(out, float(row[key])) if most else minf(out, float(row[key])))
			any = true
	return out


## What the realm's state makes of the streets, over what the town already
## shows (the barricade and the watch in war, bare stalls in hunger, the bonfire
## at a feast): in war or a levy the forge hammers faster, swords fill the
## armoury's rack and the levy gathers in the square before a sergeant.
func _moods(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, rng: RandomNumberGenerator, house: Dictionary) -> void:
	var states := _mood_states(c)
	if states.is_empty():
		return
	var hot := "war" in states or "levy" in states
	if hot:
		var tick: Node = life.get_node_or_null("Works")
		var pace := _mood_num(c, "hammer", 1.0, true)
		if tick and pace != 1.0:
			for sm in tick.smiths:
				if is_instance_valid(sm):
					(sm as Node).set_meta("work_pace", {"Hammer_Swing": pace})
		var want := int(_mood_num(c, "rack", 0.0, true))
		if Works.stock(root, "rack") < want:
			Works.add_stock(root, "rack", want - Works.stock(root, "rack"))
		_muster(root, life, center, Data.value("moods", "levy.muster" if "levy" in states else "war.muster", {}), rng)
	if "grief" in states:
		_mourning(root, life, center, Data.value("moods", "grief", {}), rng)
	if "hunger" in states:
		_dole(root, life, center, Data.value("moods", "hunger.dole", {}), rng)
	if "justice" in states:
		_justice(root, life, center, Data.value("moods", "justice", {}), rng)
	if "grant" in states:
		_grant(root, life, center, c, house, Data.value("moods", "grant", {}), rng)
	if "build" in states:
		var b: Dictionary = Data.value("moods", "build", {})
		_construction(root, life, center, String(b.get("site", "Granary")), float(b.get("progress", 0.3)), rng, int(c.get("size", 1)))
	if "levy" in states:
		_leaving(root, life, center, Data.value("moods", "levy.leave", {}), rng)
	if "feast" in states:
		_feast(root, life, center, house, rng)


## The levy gathered in the square: rows of men facing a sergeant who calls
## them (npc_mind posts levy and crier), on the seen half of the square, turned
## off the crier's line so the two crowds stand apart.
func _muster(root: Node3D, life: Node3D, center: Vector3, m: Dictionary, rng: RandomNumberGenerator) -> void:
	var men := int(m.get("men", 0))
	if men <= 0:
		return
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var toward := Basis(Vector3.UP, 1.0) * SEEN
	var front := well + toward * float(m.get("from_well", 0.45))
	var side := Vector3(-toward.z, 0, toward.x)
	var sergeant := _stand(root, life, center, front, "soldier", "Pointing_Forward", rng.randi(), Color.WHITE, 0.2)
	if sergeant == null:
		return
	_face(sergeant, sergeant.position + toward)
	_watch(sergeant)
	_mind(sergeant, "crier", center)
	var rows := maxi(1, int(m.get("rows", 2)))
	var cols := ceili(float(men) / rows)
	for i in men:
		var r := i / cols
		var k := i % cols
		var at := sergeant.position + toward * (0.2 + r * ROOM * 1.25) + side * (k - (cols - 1) * 0.5) * ROOM * 1.15
		var soldier := rng.randf() < float(m.get("soldiers", 0.2))
		var p := _stand(root, life, center, at, "soldier" if soldier else "peasant", "Weight_Shift", rng.randi(), Color.WHITE, 0.1)
		if p:
			p.set_meta("levy_man", true)
			_face(p, sergeant.position)
			_mind(p, "levy", center)


## A feast in the square, round the bonfire and its dancers (_revels): bunting
## strung from a pole by the well out to poles round the seen half of the
## square, in the house's colour and the feast's, and long tables set with
## mugs and plates, the town sat at them drinking and talking, a minstrel by them.
func _feast(root: Node3D, life: Node3D, center: Vector3, house: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = Data.value("moods", "feast", {})
	_fire_at = _fire_spot(root)  # this town's fire, whichever town was dressed before
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var col := Color.from_string(String(house.get("color", "#8a2a1e")), Color(0.55, 0.16, 0.12))
	var colours: Array = [col]
	for k in f.get("colours", []):
		colours.append(Works.colour(k, Color.WHITE))
	_bunting(root, life, center, well, f.get("bunting", {}), colours, rng)
	# Long tables on the seen half, across the line from the fire, benches either side.
	var reach := fire_reach() + 0.28
	var taken: PackedVector2Array = life.get_meta("standing")
	var sat := []
	for t in int(f.get("tables", 2)):
		var a := atan2(SEEN.x, SEEN.z) + (t - (int(f.get("tables", 2)) - 1) * 0.5) * 0.9
		var at := _fire_at + Vector3(sin(a), 0, cos(a)) * reach
		var out := (at - _fire_at).normalized()
		for p in _long_table(life, center, at, out, int(f.get("seats", 3)), t, rng):
			p.set_meta("feaster", true)
			sat.append(p)

	for p in sat:
		_mind(p, "drinker", center)
	if not sat.is_empty() and preload("res://scripts/weapons.gd").can_play("Lute_Playing"):
		var m := _stand(root, life, center, (sat[0] as Node3D).position + SEEN * 0.16, "townsfolk", "Lute_Playing", rng.randi(), Color.WHITE, 0.15)
		if m:
			_face(m, Vector3.ZERO)
			_mind(m, "minstrel", center)


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
		life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(at, Vector2(0.03, 0.03), 0.0)])
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


## A levy marching out: kin at the square seeing them off, and every few
## seconds one of the mustered men shoulders his bundle and walks out of the
## town along the nearest road (moods.json levy.leave), until most have gone.
func _leaving(root: Node3D, life: Node3D, center: Vector3, l: Dictionary, rng: RandomNumberGenerator) -> void:
	if l.is_empty():
		return
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	for i in int(l.get("kin", 3)):
		var k := _stand(root, life, center, _off_centre(root, well + Basis(Vector3.UP, 1.0) * SEEN * 0.2 + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), float(Data.num("moods", "centre.mourners", 0.08))), "peasant", "Waving", rng.randi(), Color.WHITE, 0.2)
		if k:
			_face(k, k.position + Basis(Vector3.UP, 1.0) * SEEN)
			_mind(k, "listener", center)
	var go := Leaving.new()
	go.name = "Leaving"
	go.file = int(l.get("file", 1))
	go.spacing = float(l.get("spacing", 0.13))
	go.root = root
	go.life = life
	go.ground = func(q: Vector3) -> float: return _y(center, q)
	go.every = l.get("every", [7.0, 13.0])
	go.most = int(l.get("most", 5))
	go.pace = float(l.get("pace", 0.15))
	go.rng.seed = rng.randi()
	go.wait = go.rng.randf_range(2.0, float(go.every[0]))
	life.add_child(go)


## The levy's men walking out one by one (_leaving): each in turn leaves his
## place in the muster (his mind put by), carries his bundle out along the road
## nearest him (the town's main ways, heart outward) and is gone past its end.
class Leaving extends Node:
	const People := preload("res://scripts/people.gd")
	var root: Node3D
	var life: Node3D
	var ground: Callable
	var every: Array = [7.0, 13.0]
	var most := 5
	var pace := 0.15
	var wait := 3.0
	var gone := 0
	var rng := RandomNumberGenerator.new()
	var file := 1  # men who set off together, one behind the other
	var spacing := 0.13  # world units between them in the column
	var walking: Array = []  # [person, [points left], seconds before he steps off]

	func _process(delta: float) -> void:
		if not is_instance_valid(root) or not is_instance_valid(life):
			return
		wait -= delta
		if wait <= 0.0 and gone < most:
			wait = rng.randf_range(float(every[0]), float(every[1]))
			_send()
		for w in walking.duplicate():
			var p: Node3D = w[0]
			var left: Array = w[1]
			if w.size() > 2 and float(w[2]) > 0.0:
				w[2] = float(w[2]) - delta  # his place in the column: he steps off after the man in front
				continue
			if not is_instance_valid(p) or left.is_empty():
				walking.erase(w)
				if is_instance_valid(p):
					p.queue_free()  # past the road's end: on his way to the host
				continue
			var to: Vector3 = left[0]
			var flat := Vector2(to.x - p.position.x, to.z - p.position.z)
			var step := pace * delta
			if flat.length() <= step:
				p.position = Vector3(to.x, p.position.y, to.z)
				left.pop_front()
			else:
				var d := flat.normalized() * step
				p.position += Vector3(d.x, 0, d.y)
				p.rotation.y = lerp_angle(p.rotation.y, atan2(d.x, d.y), minf(1.0, delta * 6.0))
			p.position.y = float(ground.call(p.position))
			People.play(p, "Carrying")  # the bundle in his arms over his walking legs

	## A file of men marches off together: the first picks the road out nearest him, the rest fall in
	## behind him one by one, so the town sees a column on its road.
	func _send() -> void:
		var men := life.get_children().filter(func(n): return n.has_meta("levy_man") and not n.has_meta("leaving"))
		if men.is_empty():
			return
		men.sort_custom(func(a, b): return int(a.get_meta("role", "") == "soldier") > int(b.get_meta("role", "") == "soldier"))  # a soldier leads
		var lead: Node3D = men[0]
		var path := _road_out(lead)
		if path.is_empty():
			return  # a town with no roads: they stay in the muster
		for k in mini(file, men.size()):
			if gone >= most:
				break
			var p: Node3D = men[k]
			p.set_meta("leaving", true)
			var mind := p.get_node_or_null("Mind")
			if mind:
				mind.queue_free()  # his post put by: he marches now
			gone += 1
			walking.append([p, [path[0]] + path.duplicate(), k * spacing / maxf(pace, 0.01)])


	## The way out along the nearest main road, heart outward, from near `p`; [] with no roads.
	func _road_out(p: Node3D) -> Array:
		var ways: Array = root.get_meta("ways_main", [])
		var best: Array = []
		var near := INF
		for w in ways:
			var path := PackedVector2Array(w)
			for i in path.size():
				var dd := path[i].distance_to(Vector2(p.position.x, p.position.z))
				if dd < near:
					near = dd
					best = Array(path.slice(i)).map(func(q: Vector2) -> Vector3: return Vector3(q.x, 0, q.y))
		return best


## Justice done (a court sentence standing at the town): an empty gallows at
## the square's seen edge, the watch either side, and the town come to look in
## silence (npc_mind post onlooker; a hanging itself is never shown).
func _justice(root: Node3D, life: Node3D, center: Vector3, j: Dictionary, rng: RandomNumberGenerator) -> void:
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var toward := Basis(Vector3.UP, -1.0) * SEEN  # the other side of the crier's line from the muster
	var at := _spot(center, well + toward * float(j.get("from_well", 0.62)), _blocked(root, life), life.get_meta("standing"), 0.3)
	if is_nan(at.x):
		return
	var g: Node3D = Real.make(Real.one("gallows")) if bool(j.get("gallows", true)) else null
	if g:
		g.position = Vector3(at.x, _y(center, at), at.z)
		g.rotation.y = atan2(toward.x, toward.z)
		g.set_meta("dress", "gallows")
		life.add_child(g)
		life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(at, Real.footprint(Real.one("gallows")), atan2(toward.x, toward.z))])
	var side := Vector3(-toward.z, 0, toward.x)
	for i in int(j.get("guards", 2)):
		var w := _stand(root, life, center, at - toward * 0.12 + side * (0.18 if i % 2 else -0.18), "soldier", "Sword_Idle", rng.randi(), Color.WHITE, 0.15)
		if w:
			_face(w, w.position - toward)
			_watch(w)
			_mind(w, "guard", center)
	for i in int(j.get("crowd", 7)):
		var a := atan2(-toward.x, -toward.z) + lerpf(-0.9, 0.9, (i + 0.5) / maxf(1.0, int(j.get("crowd", 7))))
		var p := _stand(root, life, center, at + Vector3(sin(a), 0, cos(a)) * rng.randf_range(0.3, 0.42), "peasant" if rng.randf() < 0.6 else "townsfolk", "Looking_Around", rng.randi(), Color.WHITE, 0.12)
		if p:
			p.set_meta("onlooker", true)
			_face(p, at)
			_mind(p, "onlooker", center)


## A grant to the house that holds the town (CK3's granted holding): its
## banners stand round the square, and the work the grant pays for rises.
func _grant(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, house: Dictionary, g: Dictionary, rng: RandomNumberGenerator) -> void:
	var col := Color.from_string(String(house.get("color", "#8a2a1e")), Color(0.55, 0.16, 0.12))
	var n := int(g.get("banners", 4))
	for i in n:
		var a := atan2(SEEN.x, SEEN.z) + (i - (n - 1) * 0.5) * 0.7
		var at := _spot(center, Vector3(sin(a), 0, cos(a)) * float(g.get("ring", 0.7)), _blocked(root, life), life.get_meta("standing"), 0.2)
		if is_nan(at.x):
			continue
		var flag := Heraldry.standard(house, col, STANDARD_TALL)
		flag.position = Vector3(at.x, _y(center, at), at.z)
		flag.rotation.y = atan2(-at.x, -at.z)
		flag.set_meta("dress", "grant_banner")
		life.add_child(flag)
		life.set_meta("footprints", life.get_meta("footprints", []) + [_rect(at, Vector2(0.05, 0.05), 0.0)])
	_construction(root, life, center, String(g.get("site", "Palace")), float(g.get("progress", 0.15)), rng, int(c.get("size", 1)))


# --- the square's own life (realm/data/crowd.json; art target town-b) -----------------------------

## The square on any day in a market town: a crier at the well, beggars at the church step, a pair
## of guards walking its ring, town dogs trotting after people, children chasing each other, knots of
## neighbours gossiping (who turn to look at news: npc_mind React). Each is there for a reason: their
## post's mind (npc_mind.gd) or their walk here (SquareLife). How many by the town's state: crowd.json.
func _square_life(root: Node3D, life: Node3D, center: Vector3, c: Dictionary, rng: RandomNumberGenerator) -> void:
	if not bool(Data.value("crowd", "on", true)) or OS.get_cmdline_user_args().has("--crowd=off"):
		return
	if int(c.get("size", 1)) < int(Data.num("crowd", "min_size", 6)) and not bool(root.get_meta("crown_seat", false)):
		return
	var active := Works.states(c, _town_id)
	var n := func(what: String) -> int: return _crowd_count(what, active)
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var r := float(root.get_meta("square_r", 1.0))
	var go := SquareLife.new()
	go.name = "SquareLife"
	go.ground = func(q: Vector3) -> float: return _y(center, q)
	go.blocks = func() -> Array: return _blocked(root, life)  # every building, stall, plinth and table (read once, after the square is set)
	go.life = life
	go.rng.seed = rng.randi()
	life.add_child(go)
	# The crier at the well (the news crier already stands there when there's news).
	if not NEWS.any(func(st): return st in active) and n.call("crier") > 0:
		var tick: Node = life.get_node_or_null("Works")
		if tick:
			_crier(root, life, center, tick, 3, rng)
	# Beggars at the church step.
	if places.has("sept"):
		for i in n.call("beggars"):
			var b := _stand(root, life, center, places["sept"] + Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15)), "peasant", "Sitting_Ground", rng.randi(), Color(0.45, 0.42, 0.38), 0.2)
			if b:
				_face(b, Vector3.ZERO)
				_mind(b, "beg", center)
	# Guards walking the square's ring in pairs.
	var P: Dictionary = Data.value("crowd", "patrol", {})
	for k in n.call("patrol"):
		var ring: Array = []
		var a0 := rng.randf() * TAU
		for i in 8:
			var a := a0 + TAU * i / 8.0 * (1.0 if k % 2 == 0 else -1.0)
			ring.append(Vector3(cos(a), 0, sin(a)) * r * float(P.get("ring", 0.85)))
		var route := _beat(root, life, center, r, k, rng) if square_agents_on() else []
		if route.size() >= 2:
			ring = route  # a beat between the square's mouths and the well, not a ring (round 6 clip: it read mechanical)
		var pair: Array = []
		for j in 2:
			var g := _townsperson(life, Vector3(ring[0].x, _y(center, ring[0]), ring[0].z) + Vector3(0.07 * j, 0, 0), "soldier", "Sword_Idle", rng.randi(), _house_col)
			_watch(g)
			g.set_meta("patrol", true)
			pair.append(g)
		go.patrols.append({"men": pair, "ring": ring, "beat": ring == route, "leg": 1, "rest": 0.0, "pace": float(P.get("pace", 0.14)), "pause": P.get("pause", [3.0, 7.0])})
	# Town dogs.
	var D: Dictionary = Data.value("crowd", "dogs", {})
	var tints: Array = D.get("tint", [])
	for i in n.call("dogs"):
		var dog := preload("res://scripts/animals.gd").make("dog", rng)
		if dog == null:
			break
		if not tints.is_empty():
			var col := Works.colour(tints[i % tints.size()], Color.WHITE)
			for mi in dog.find_children("*", "MeshInstance3D", true, false):
				var m := (mi as MeshInstance3D).get_active_material(0)
				if m is StandardMaterial3D:
					var copy: StandardMaterial3D = m.duplicate()
					copy.albedo_color = col
					(mi as MeshInstance3D).material_override = copy
		var at := _off_centre(root, well + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r)) * 0.6, float(Data.num("moods", "centre.mourners", 0.08)))
		dog.position = Vector3(at.x, _y(center, at), at.z)
		dog.rotation.y = rng.randf() * TAU
		dog.set_meta("town_dog", true)
		life.add_child(dog)
		go.dogs.append({"dog": dog, "rest": rng.randf_range(2.0, 8.0), "after": null, "trot": float(D.get("trot", 0.2)), "follow": float(D.get("follow", 0.12))})
	# Children chasing each other round the square.
	var C: Dictionary = Data.value("crowd", "chase", {})
	for k in n.call("chase"):
		var kids: Array = []
		for j in 2:
			var at := _off_centre(root, well + Vector3(rng.randf_range(-r, r), 0, rng.randf_range(-r, r)) * 0.5, float(Data.num("moods", "centre.mourners", 0.08)))
			var kid := _townsperson(life, Vector3(at.x, _y(center, at), at.z), "peasant", "Laughing", rng.randi(), Color.WHITE, "", "child")
			kid.set_meta("chasing", true)
			if rng.randf() < float(C.get("sticks", 0.0)):
				preload("res://scripts/weapons.gd").arm(kid, String(C.get("stick", "dagger")))  # a stick for a sword (01-town)
			_people.play(kid, "Running")  # their legs run while they're moved (motion.gd reads their pace)
			kids.append(kid)
		go.chases.append({"kids": kids, "goal": Vector3.INF, "r": r * 0.8, "pace": float(C.get("pace", 0.32)), "apart": float(C.get("apart", 0.35))})
	# Knots of neighbours gossiping, on the seen half of the square.
	var G: Dictionary = Data.value("crowd", "gossip", {})
	var knot: Array = G.get("knot", [2, 4])
	for k in n.call("gossip"):
		# Spread round the square's open cobble, each knot in its own arc of it (crowd.json gossip.arc radians either side
		# of the seen side, reach [nearest, furthest] in square radii; round 5: the knots met in one clump at the heart).
		var arc := float(G.get("arc", 1.4))
		var reach: Array = G.get("reach", [0.35, 0.75])
		var share: float = (k + rng.randf_range(0.2, 0.8)) / maxf(float(n.call("gossip")), 1.0)
		var a := atan2(SEEN.x, SEEN.z) + lerpf(-arc, arc, share)
		var mid := Vector3(sin(a), 0, cos(a)) * r * rng.randf_range(float(reach[0]), float(reach[1]))
		if k < int(G.get("at_well", 0)):
			# 01-town's women talking at the well's rim, a step toward the square's heart (crowd.json gossip.at_well).
			mid = well - well.normalized() * float(G.get("well_out", 0.22)) + Vector3(rng.randf_range(-0.06, 0.06), 0, rng.randf_range(-0.06, 0.06))
		var m := rng.randi_range(int(knot[0]), int(knot[1]))
		for j in m:
			var b := TAU * j / m + rng.randf_range(-0.3, 0.3)
			var p := _stand(root, life, center, mid + Vector3(cos(b), 0, sin(b)) * 0.085, "townsfolk" if rng.randf() < 0.6 else "peasant", "Idle_Talking", rng.randi(), Color.WHITE, 0.08)
			if p:
				p.set_meta("gossip", true)
				_face(p, mid)
				_mind(p, "gossip", center)
	_square_more(root, life, center, n, go, rng)


## The rest of 01-town's square (crowd.json): guards in the house's colour posted at the forge and at the
## castle's steps, townsfolk carrying sacks and baskets between the square's places, a horse and cart crossing
## it to the market and on, and the yards nearest it kept: hens and a pig about the beds, someone on their
## knees weeding. Everyone there for a reason, doing it.
func _square_more(root: Node3D, life: Node3D, center: Vector3, n: Callable, go: SquareLife, rng: RandomNumberGenerator) -> void:
	var places: Dictionary = root.get_meta("places", {})
	var r := float(root.get_meta("square_r", 1.0))
	var guard_cloth := _house_col.lerp(Color.WHITE, float(Data.num("crowd", "posted.lighten", 0.2)))
	# Guards posted at the forge, either side of its yard, watching the square.
	var works: Dictionary = root.get_meta("works", {})
	if works.has("forge"):
		var fb: Dictionary = works["forge"]
		var fat: Vector3 = fb["at"]
		var ff := _front(fb)
		var fside := Vector3(-ff.z, 0, ff.x)
		var foot := float(Data.num("crowd", "posted.forge_out", 0.55))
		for i in n.call("guards_forge"):
			var want: Vector3 = fat + ff * foot + fside * (0.22 if i % 2 == 0 else -0.22) * (1 + i / 2)
			var g := _stand(root, life, center, want, "soldier", "Sword_Idle", rng.randi(), guard_cloth, 0.2)
			if g:
				_watch(g)
				_face(g, g.position + ff)
				_mind(g, "guard", center)
	# Guards at the castle's steps: along the castle's side that faces the square, a little out from it.
	var poly: Variant = root.get_meta("castle_poly") if root.has_meta("castle_poly") else null  # a null default errors when unset (towns without a castle)
	if poly is PackedVector2Array and (poly as PackedVector2Array).size() >= 3:
		var cp := poly as PackedVector2Array
		var best := Vector2.INF
		var seg := [Vector2.ZERO, Vector2.ZERO]
		for i in cp.size():
			var q := Geometry2D.get_closest_point_to_segment(Vector2.ZERO, cp[i], cp[(i + 1) % cp.size()])
			if q.length() < best.length():
				best = q
				seg = [cp[i], cp[(i + 1) % cp.size()]]
		if best.length() < r * float(Data.num("crowd", "posted.castle_within", 4.0)):
			var along := ((seg[1] as Vector2) - (seg[0] as Vector2)).normalized()
			var out := -best.normalized()
			var m := n.call("guards_castle") as int
			for i in m:
				var at2 := best + out * float(Data.num("crowd", "posted.castle_out", 0.14)) + along * (i - (m - 1) * 0.5) * 0.16
				var g := _stand(root, life, center, Vector3(at2.x, 0, at2.y), "soldier", "Sword_Idle", rng.randi(), guard_cloth, 0.15)
				if g:
					_watch(g)
					_face(g, Vector3.ZERO)
					_mind(g, "guard", center)
	# Errands across the square: a sack on the shoulder or a basket on the arm, from place to place.
	var E: Dictionary = Data.value("crowd", "errands", {})
	var stops: Array = []
	for k in ["market", "well", "tavern", "sept"]:
		if places.has(k):
			stops.append(places[k])
	if works.has("forge"):
		stops.append((works["forge"]["at"] as Vector3) + _front(works["forge"]) * 0.45)
	# And a way up each main street (crowd.json errands.streets, square radii out): the errands come in off the
	# streets and go back up them, so the streets round the square are busy too (01-town).
	var streets: Array = []
	if float(E.get("streets", 0.0)) > 0.0:
		for w in root.get_meta("ways_main", []):
			var line := w as PackedVector2Array
			for q in line:
				if q.length() > r * float(E["streets"]):
					streets.append(Vector3(q.x, 0, q.y))
					break
	if stops.size() >= 2:
		var loads: Array = E.get("loads", [["Carrying", "townsfolk", "female"], ["Box_Walk", "peasant", "male"]])
		for i in n.call("errands"):
			var ld: Array = loads[i % loads.size()]
			if i == 0:
				# Each place's stop on open ground by it, never its middle: the well's middle is in the well (round 6 clip).
				var walls := _blocked(root, life)
				for si in stops.size():
					var q := _spot(center, stops[si], walls, PackedVector2Array(), 0.4)
					if not is_nan(q.x):
						stops[si] = q
			var first: Vector3 = stops[rng.randi() % stops.size()]
			var p := _stand(root, life, center, first + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), String(ld[1]), String(ld[0]), rng.randi(), Color.WHITE, 0.3)
			if p == null:
				continue
			p.set_meta("errand", true)
			if ld.size() > 3 and String(ld[3]) == "shoulder":
				_shoulder_sack(p)  # a sack on his shoulder (01-town's porter), carried through every move
			var order := stops.duplicate()
			order.shuffle()
			if not streets.is_empty() and rng.randf() < float(E.get("street_share", 0.6)):
				# Up one street and back: between two places on the square, never street to street across the houses.
				order.insert(1 + rng.randi() % (order.size() - 1), streets[i % streets.size()])
			go.errands.append({"man": p, "stops": order, "leg": 0, "rest": rng.randf_range(0.0, 3.0), "pace": float(E.get("pace", 0.15)), "pause": E.get("pause", [2.0, 6.0]), "carry": String(ld[0]), "set_down": String(E.get("set_down", "PickUp_Table"))})
	# A horse and cart crossing the square on its way through, stopping at the market.
	var K: Dictionary = Data.value("crowd", "cart", {})
	var ways: Array = root.get_meta("ways_main", [])
	if n.call("cart") > 0 and ways.size() >= 2:
		var ends: Array = []
		var lanes: Array = []  # each street's own points from the square's edge out to its end: the cart keeps to them
		for w in ways.slice(0, 2):
			var line := w as PackedVector2Array
			var far := line[line.size() - 1]
			var lane: Array = []
			for q in line:
				if q.length() > r * 0.9:
					lane.append(Vector3(q.x, 0, q.y))
				if q.length() > r * float(K.get("from", 1.3)):
					far = q
					break
			ends.append(Vector3(far.x, 0, far.y))
			if lane.is_empty() or (lane[0] as Vector3).length() > (lane[lane.size() - 1] as Vector3).length():
				lane.reverse()  # the square's end first
			lanes.append(lane)
		var rig := horse_cart(_people, rng)
		if rig:
			rig.position = Vector3(ends[0].x, _y(center, ends[0]), ends[0].z)
			life.add_child(rig)
			var mkt: Vector3 = places.get("market", Vector3.ZERO)
			mkt = mkt * float(K.get("market_in", 0.7))
			# Round 6: it crossed the cobbles on a straight line from a street's end, turned aside round the stalls, and read
			# sideways. Now in along one street's own line, to the market, out along the other's, and back; it waits only
			# at the market and at the streets' ends (crowd.json cart.by_street: off for the straight line as before).
			var route: Array = [mkt, ends[1], mkt, ends[0]]
			var waits: Array = [true, true, true, true]
			if bool(K.get("by_street", true)):
				var out_b: Array = (lanes[1] as Array).duplicate()
				var in_b: Array = out_b.duplicate()
				in_b.reverse()
				var out_a: Array = (lanes[0] as Array).duplicate()
				var in_a: Array = out_a.duplicate()
				in_a.reverse()
				route = in_a + [mkt] + out_b + [ends[1]] + in_b + [mkt] + out_a + [ends[0]]
				waits = []
				for q in route:
					waits.append(q == mkt or q == ends[0] or q == ends[1])
			go.carts.append({"rig": rig, "market": mkt, "stops": route, "waits": waits, "leg": 0, "rest": 0.0, "pace": float(K.get("pace", 0.16)), "stop": K.get("stop", [6.0, 12.0])})
	# The yards nearest the square: hens and a pig about the beds, a gardener on their knees.
	var gardens: Array = (root.get_meta("gardens", []) as Array).filter(func(g): return Vector3(g).length() < r * float(Data.num("crowd", "yards.within", 3.0)))
	gardens.sort_custom(func(a, b): return Vector3(a).length() < Vector3(b).length())
	var Y: Dictionary = Data.value("crowd", "yards", {})
	var Animals := preload("res://scripts/animals.gd")
	for gi in mini(gardens.size(), int(n.call("yards"))):
		var g: Vector3 = gardens[gi]
		var hens := rng.randi_range(int((Y.get("hens", [2, 4]) as Array)[0]), int((Y.get("hens", [2, 4]) as Array)[1]))
		var beasts: Array = []
		for h in hens:
			beasts.append("chicken")
		if rng.randf() < float(Y.get("pig", 0.5)):
			beasts.append("pig")
		for kind in beasts:
			var b := Animals.make(String(kind), rng)
			if b == null:
				continue
			var off := Vector3(rng.randf_range(-0.22, 0.22), 0, rng.randf_range(-0.22, 0.22))
			var at3: Vector3 = g + off
			b.position = Vector3(at3.x, _y(center, at3), at3.z)
			b.rotation.y = rng.randf() * TAU
			b.set_meta("yard_beast", true)
			life.add_child(b)
			Animals.live(b, String(kind), rng)
		if rng.randf() < float(Y.get("gardener", 0.7)):
			var w := _stand(root, life, center, g, "peasant", "Fixing_Kneeling", rng.randi(), Color.WHITE, 0.15)
			if w:
				_face(w, g)
				_mind(w, "weeder", center)


static var _wagon_mesh: Mesh


## A sack slung on a porter's right shoulder (crowd.json cart.sack: [up, back] metres from the shoulder bone,
## its size), on the bone itself so it goes with him through every step and stoop.
func _shoulder_sack(p: Node3D) -> void:
	shoulder_sack(p, true)


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


## How many of `what` (crowd.json) stand in a town in these states: base, else the first state set.
func _crowd_count(what: String, active: Array) -> int:
	# With the square's agents on, the posted crowd is cut to crowd.json square_agents.posted (the villagers walk the
	# square on errands instead: stall to street, well to door).
	var cut: Dictionary = Data.value("crowd", "square_agents.posted", {}) if square_agents_on() else {}
	if cut.has(what):
		return int(cut[what])
	var row: Dictionary = Data.value("crowd", what, {})
	for st in Data.value("works", "priority", []):
		if st in active and row.has(st):
			return int(row[st])
	return int(row.get("base", 0))


## Whether the square's people are agents on errands (villagers.gd _slot, npc_mind's shopper, water carrier and
## porter; crowd.json square_agents) rather than posted in place: --square-agents=on|off, else crowd.json.
static func square_agents_on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--square-agents=off"):
		return false
	return args.has("--square-agents=on") or bool(preload("res://scripts/data.gd").value("crowd", "square_agents.on", false))


## A guard pair's beat (crowd.json patrol.beat): from one main street's mouth across the square past the well to
## another's, a stop at each to look about, then back; each pair starts from its own mouth.
func _beat(root: Node3D, life: Node3D, center: Vector3, r: float, k: int, rng: RandomNumberGenerator) -> Array:
	var mouths: Array = []
	for w in root.get_meta("ways_main", []):
		for q in w as PackedVector2Array:
			if q.length() > r * float(Data.num("crowd", "patrol.mouth", 0.95)):
				mouths.append(Vector3(q.x, 0, q.y))
				break
	if mouths.size() < 2:
		return []
	var places: Dictionary = root.get_meta("places", {})
	var walls := _blocked(root, life)
	var mid: Vector3 = places.get("well", Vector3.ZERO)
	var by_well := _spot(center, mid + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * 0.3, walls, PackedVector2Array(), 0.4)
	var a: Vector3 = mouths[k % mouths.size()]
	var b: Vector3 = mouths[(k + 1) % mouths.size()]
	# The castle's gate, when the castle stands by the square (towns.gd castle_frame): the beat starts and ends
	# before it (01-town: the guards between the gate and the square's mouths).
	var gate := Vector3.INF
	var castle: Array = root.get_meta("castle_frame", [])
	if castle.size() >= 3 and bool(Data.value("crowd", "patrol.gate", true)):
		var cp: Vector3 = castle[0]
		var cb := Basis(Vector3.UP, float(castle[1]))
		var half := float((castle[2] as Vector2).y) * 0.5 + float(Data.num("crowd", "patrol.gate_out", 0.2))
		var g1: Vector3 = cp + cb * Vector3(0, 0, half)
		var g2: Vector3 = cp - cb * Vector3(0, 0, half)
		var g := g1 if g1.length() < g2.length() else g2  # the castle's end toward the square
		if g.length() < r * 3.0:
			var q := _spot(center, g, walls, PackedVector2Array(), 0.4)
			if not is_nan(q.x):
				gate = q
	var route: Array = []
	if gate != Vector3.INF:
		route.append(gate)
	route.append(a)
	if not is_nan(by_well.x):
		route.append(by_well)
	route.append(b)
	if not is_nan(by_well.x) and gate == Vector3.INF:
		route.append(by_well)
	return route


## The square's walkers, moved here (movement only; what they're for is said where they're placed):
## guards walking its ring and stopping to look about, dogs trotting after someone then lying about,
## children chasing each other.
class SquareLife extends Node:
	const People := preload("res://scripts/people.gd")
	const Mover := preload("res://scripts/mover.gd")
	static var READ: float = preload("res://scripts/data.gd").num("people", "readable", 1.0)
	const Animals := preload("res://scripts/animals.gd")
	var life: Node3D
	var ground: Callable
	var rng := RandomNumberGenerator.new()
	var patrols: Array = []
	var dogs: Array = []
	var chases: Array = []
	var processions: Array = []  # a funeral round the square: {walkers, bearers, bier, ring, leg, pace, spacing, trail}
	var errands: Array = []  # {man, stops, leg, rest, pace, pause, carry, set_down}: a load carried place to place
	var carts: Array = []  # {rig, stops, leg, rest, pace, stop}: a horse and cart crossing the square

	func _process(delta: float) -> void:
		if not is_instance_valid(life):
			return
		for f in processions:
			_procession(f, delta)
		for p in patrols:
			_patrol(p, delta)
		for d in dogs:
			_dog(d, delta)
		for c in chases:
			_chase(c, delta)
		for e in errands:
			_errand(e, delta)
		for k in carts:
			_cart(k, delta)

	## A load carried to the next place, set down a while, taken up again and on to the next.
	func _errand(e: Dictionary, delta: float) -> void:
		var man: Node3D = e["man"]
		if not is_instance_valid(man):
			return
		if float(e["rest"]) > 0.0:
			e["rest"] = float(e["rest"]) - delta
			if float(e["rest"]) <= 0.0:
				People.play(man, String(e["carry"]))  # up with it again: the arms keep it over the walking legs
			return
		var stops: Array = e["stops"]
		var to: Vector3 = stops[int(e["leg"]) % stops.size()]
		if not step(man, to, float(e["pace"]), delta, 0.06):
			e["leg"] = int(e["leg"]) + 1
			var span: Array = e["pause"]
			e["rest"] = rng.randf_range(float(span[0]), float(span[1]))
			People.play(man, String(e["set_down"]))

	## The cart rolls to its next stop (the market, then out along the road and back), waits, rolls on.
	func _cart(k: Dictionary, delta: float) -> void:
		var rig: Node3D = k["rig"]
		if not is_instance_valid(rig):
			return
		var carter: Variant = rig.get_meta("carter", null)
		if float(k["rest"]) > 0.0:
			k["rest"] = float(k["rest"]) - delta
			return
		var stops: Array = k["stops"]
		if step(rig, stops[int(k["leg"]) % stops.size()], float(k["pace"]), delta, 0.08, false):
			if life.get_parent() and life.get_parent().has_meta("cart_tail"):
				life.get_parent().remove_meta("cart_tail")  # rolling: nothing to unload
			if carter is Node3D and is_instance_valid(carter) and not (carter as Node3D).has_meta("walking"):
				(carter as Node3D).set_meta("walking", true)
				People.play(carter, "Walk")
			return
		var waits: Array = k.get("waits", [])
		var here := int(k["leg"]) % stops.size()
		k["leg"] = int(k["leg"]) + 1
		if not waits.is_empty() and not bool(waits[here]):
			return  # a bend in the street: on without stopping
		# Drawn up at the market: its tail is a porter's slot to unload from (villagers.gd _slot "cart") while it waits.
		var town := life.get_parent()
		if town and stops[here] == k.get("market", Vector3.INF):
			var back := Vector3(sin(rig.rotation.y), 0, cos(rig.rotation.y))
			town.set_meta("cart_tail", [rig.position - back * float(preload("res://scripts/data.gd").num("crowd", "cart.tail", 0.22)), rig.position])
		var span: Array = k["stop"]
		k["rest"] = rng.randf_range(float(span[0]), float(span[1]))
		if carter is Node3D and is_instance_valid(carter):
			(carter as Node3D).remove_meta("walking")
			People.play(carter, ["Idle", "Looking_Around", "Idle_Talking"][rng.randi() % 3])

	## One step of a walk toward `to` (town-local): the Mover walks it by the navigation's route (CLAUDE.md, one way
	## to move), so the cart, the carriers, the watch, the dogs and the children all go round the well, the stalls
	## and the plinth. False once there (within `near`, or as near as the route reaches). A goal that moves (a dog
	## after its man, a child after another) is asked for again once it has moved a stride.
	func step(n: Node3D, to: Vector3, pace: float, _delta: float, near := 0.02, _sidestep := true) -> bool:
		var m: Node = Mover.of(n)
		if Vector2(to.x - n.position.x, to.z - n.position.z).length() <= near:
			m.stop()
			return false
		var parent := n.get_parent() as Node3D
		var goal: Vector3 = parent.to_global(to)
		var was: Vector3 = n.get_meta("walk_to", Vector3.INF)
		if m.moving() and was.distance_to(goal) <= 0.05:
			return true
		if not m.moving() and was.distance_to(goal) <= 0.05:
			return false  # walked as far as the route goes: there
		m.speed = pace * READ  # drawn larger (people.json readable): they cover ground as their legs do
		m.clip = ""  # the caller plays the walk, the carry or the trot
		m.ground = func(w: Vector3) -> float: return float(ground.call(parent.to_local(w)))
		n.set_meta("walk_to", goal)
		m.go(goal)
		return true

	## Every building, stall, plinth and table on the square (where a child may run to: _open_cobble).
	var blocks := Callable()
	var _blocks: Array = []

	func _patrol(p: Dictionary, delta: float) -> void:
		var men: Array = (p["men"] as Array).filter(func(m): return is_instance_valid(m))
		if men.is_empty():
			return
		if float(p["rest"]) > 0.0:
			p["rest"] = float(p["rest"]) - delta
			return
		var ring: Array = p["ring"]
		var to: Vector3 = ring[int(p["leg"]) % ring.size()]
		var moving := false
		for i in men.size():
			var side := Basis(Vector3.UP, (men[0] as Node3D).rotation.y) * Vector3(0.07 * (i - 0.5), 0, 0)
			moving = step(men[i], to + side, float(p["pace"]), delta) or moving
		if not moving:
			p["leg"] = int(p["leg"]) + 1
			if bool(p.get("beat", false)) or int(p["leg"]) % 2 == 0:  # on a beat at every stop, on a ring every other corner, they stop and look about
				var span: Array = p["pause"]
				p["rest"] = rng.randf_range(float(span[0]), float(span[1]))
				for m in men:
					People.play(m, ["Looking_Around", "Sword_Idle", "SS_Idle_2", "Weight_Shift"][rng.randi() % 4])

	func _dog(d: Dictionary, delta: float) -> void:
		var dog: Node3D = d["dog"]
		if not is_instance_valid(dog):
			return
		var after: Variant = d["after"]
		if after == null or not is_instance_valid(after):
			d["rest"] = float(d["rest"]) - delta
			Animals.walk(dog, false)
			if float(d["rest"]) > 0.0:
				return
			# Off after someone near: a child at play by choice, else anyone about the square.
			var folk := life.get_children().filter(func(n): return n is Node3D and n.has_node("Anim") and (n as Node3D).position.distance_to(dog.position) < 1.2)
			var kids := folk.filter(func(n): return n.has_meta("chasing"))
			var pool := kids if not kids.is_empty() and rng.randf() < 0.6 else folk
			if pool.is_empty():
				d["rest"] = rng.randf_range(3.0, 8.0)
				return
			d["after"] = pool[rng.randi() % pool.size()]
			d["for"] = rng.randf_range(6.0, 14.0)
			return
		d["for"] = float(d["for"]) - delta
		var who: Node3D = after
		var near := float(d["follow"])
		if float(d["for"]) <= 0.0:
			d["after"] = null
			d["rest"] = rng.randf_range(4.0, 12.0)  # it lies about, sniffs, scratches (its idle life)
			return
		Animals.walk(dog, step(dog, who.position, float(d["trot"]), delta, near))

	## The funeral: its head walks the ring; each behind follows the trail the head left, `spacing` back, so
	## the column keeps its shape round the bends; the bier rides at the bearers' shoulders.
	func _procession(f: Dictionary, delta: float) -> void:
		var walkers: Array = (f["walkers"] as Array).filter(func(w): return is_instance_valid(w))
		if walkers.is_empty():
			return
		var head: Node3D = walkers[0]
		var ring: Array = f["ring"]
		if not step(head, ring[int(f["leg"]) % ring.size()], float(f["pace"]), delta, 0.03):
			f["leg"] = int(f["leg"]) + 1
		var trail: Array = f["trail"]
		trail.push_front(head.position)
		var need := int(walkers.size() * float(f["spacing"]) / maxf(float(f["pace"]) * delta, 0.0005)) + 2
		while trail.size() > need:
			trail.pop_back()
		for i in range(1, walkers.size()):
			var back := float(f["spacing"]) * i
			var gone := 0.0
			var at: Vector3 = trail[trail.size() - 1]
			for k in range(1, trail.size()):
				gone += (trail[k] as Vector3).distance_to(trail[k - 1])
				if gone >= back:
					at = trail[k]
					break
			step(walkers[i], at, float(f["pace"]) * 1.4, delta, 0.005)
		var bearers: Array = (f["bearers"] as Array).filter(func(w): return is_instance_valid(w))
		var bier: Variant = f["bier"]
		if bier != null and is_instance_valid(bier) and not bearers.is_empty():
			var c := Vector3.ZERO
			for b in bearers:
				c += (b as Node3D).position
			c /= bearers.size()
			(bier as Node3D).position = c + Vector3(0, 0.15, 0)  # on their shoulders
			(bier as Node3D).rotation.y = (bearers[0] as Node3D).rotation.y

	func _chase(c: Dictionary, delta: float) -> void:
		var kids: Array = c["kids"]
		if kids.size() < 2 or not is_instance_valid(kids[0]) or not is_instance_valid(kids[1]):
			return
		var runner: Node3D = kids[0]
		var chaser: Node3D = kids[1]
		if float(c.get("rest", 0.0)) > 0.0:
			c["rest"] = float(c["rest"]) - delta
			if float(c["rest"]) <= 0.0:
				for kd in kids:
					People.play(kd, "Running")
			return
		if c["goal"] == Vector3.INF or not step(runner, c["goal"], float(c["pace"]), delta):
			c["goal"] = _open_cobble(float(c["r"]))
		if not step(chaser, runner.position, float(c["pace"]) * 0.97, delta, 0.06):
			c["kids"] = [chaser, runner]  # caught: now the other one runs
			var C: Dictionary = preload("res://scripts/data.gd").value("crowd", "chase", {})
			if rng.randf() < float(C.get("stop", 0.5)):
				# A breather after a catch: laughing, bent over, pointing off at something, then off again.
				var span: Array = C.get("rest", [2.0, 4.0])
				c["rest"] = rng.randf_range(float(span[0]), float(span[1]))
				for kd in kids:
					People.play(kd, ["Laughing", "Crouch_Idle", "Pointing_Forward", "Waving"][rng.randi() % 4])

	## A point on the square's open cobble within `r` of its heart: off every stall, house and plinth.
	func _open_cobble(r: float) -> Vector3:
		if _blocks.is_empty() and blocks.is_valid():
			_blocks = blocks.call()
		var p := Vector3.ZERO
		for t in 8:
			var a := rng.randf() * TAU
			p = Vector3(cos(a), 0, sin(a)) * r * rng.randf_range(0.3, 1.0)
			var q := Vector2(p.x, p.z)
			if not _blocks.any(func(fp): return (fp as PackedVector2Array).size() > 2 and q.distance_to(fp[0]) < 1.5 and Geometry2D.is_point_in_polygon(q, fp)):
				return p
		return p


## A famine's dole (the hungry in a line for bread, readable from the square's camera in seconds):
## a table at the market with a few sacks and a doler handing out, and the line out from it
## (npc_mind posts trade and queue). The granary's own queue (works.gd) stands besides, where there is one.
func _dole(root: Node3D, life: Node3D, center: Vector3, d: Dictionary, rng: RandomNumberGenerator) -> void:
	var men := int(d.get("men", 0))
	if men <= 0:
		return
	var places: Dictionary = root.get_meta("places", {})
	var at: Vector3 = places.get(String(d.get("at", "market")), places.get("well", Vector3(0.4, 0, 0.4)))
	at = _spot(center, at, _blocked(root, life), life.get_meta("standing"), 0.3)
	if is_nan(at.x):
		return
	var out := Vector3(at.x, 0, at.z).normalized() if Vector2(at.x, at.z).length() > 0.05 else SEEN
	var yaw := atan2(out.x, out.z) + PI / 2
	_prop(life, center, "Table_Large", at, yaw, 1.0, 0.0, 0.16)
	_prop(life, center, "Bag", at + Vector3(-out.z, 0, out.x) * 0.05, rng.randf() * TAU, 1.0, 0.09)
	_prop(life, center, "Bag", at - out * 0.12 + Vector3(-out.z, 0, out.x) * 0.1, rng.randf() * TAU)
	var doler := _stand(root, life, center, at - out * 0.12, "townsfolk", "PickUp_Table", rng.randi(), Color(0.45, 0.4, 0.3), 0.1)
	if doler:
		_face(doler, at)
		_mind(doler, "trade", center)
	_line(root, life, center, at + out * 0.16, out, men, "peasant", "Weight_Shift", "queue", rng)
	for p in life.get_children():
		if p.get_meta("role", "") == "peasant" and p.position.distance_to(at) < 0.16 + ROOM * 1.15 * men:
			p.set_meta("dole", true)


## A long table at `at` (town-local), its length across `out`, set with mugs and plates, a bench
## either side and `seats` a side sat drinking, facing across it (a feast's, the inn yard's). Returns
## who sits there; their minds are the caller's to give.
func _long_table(life: Node3D, center: Vector3, at: Vector3, out: Vector3, seats: int, n: int, rng: RandomNumberGenerator, role := "") -> Array:
	var along := Vector3(-out.z, 0, out.x)
	var yaw := atan2(along.x, along.z)
	if _prop(life, center, "Table_Large", at, yaw, 1.0, 0.0, 0.18) == null:
		return []
	var TOP := 0.098 * FURN  # the table's height (0.815 m at PROP_SCALE, drawn at the people's size)
	var ware := ["Mug", "Table_Plate", "Chalice", "Mug", "Pot_1", "Table_Plate", "Mug"]
	for i in 5:
		_prop(life, center, ware[(n * 3 + i) % ware.size()], at + (along * (i - 2) * 0.04 + out * rng.randf_range(-0.015, 0.015)) * FURN, rng.randf() * TAU, 1.0, TOP)
	var taken: PackedVector2Array = life.get_meta("standing")
	var sat: Array = []
	for sgn in [-1.0, 1.0]:
		var bench: Vector3 = at + out * sgn * 0.1 * FURN  # clear of the table's edge at its drawn size
		_prop(life, center, "Bench", bench, yaw, 1.0, 0.0, 0.0)
		for i in seats:
			var seat: Vector3 = bench + along * (i - (seats - 1) * 0.5) * 0.08 * FURN
			var who := role if role != "" else ("townsfolk" if rng.randf() < 0.6 else "peasant")
			var p := _townsperson(life, Vector3(seat.x, _y(center, seat), seat.z), who, "Sitting_Drinking", rng.randi())
			p.rotation.y = atan2(-out.x * sgn, -out.z * sgn)  # facing across the table
			taken.append(Vector2(seat.x, seat.z))
			sat.append(p)
	life.set_meta("standing", taken)
	return sat


## A town in grief, unmistakable from the town camera (batch 8b centre-grief: it read as a market day):
## candles and flowers in a ring at the centrepiece (or the well), black cloth over the doors of the houses
## nearest the square, the bell tolling from the sept (sound_v2.gd hears the "Tolling" node), and a funeral
## round the square: a priest, the bier on its bearers' shoulders, mourners behind (SquareLife walks it).
## The thin dark crowd and the shut stalls are the crowd's and the market's own (people.json cloth.mourning,
## moods.json grief.out, stalls_open). Numbers: moods.json grief.
func _mourning(root: Node3D, life: Node3D, center: Vector3, g: Dictionary, rng: RandomNumberGenerator) -> void:
	var places: Dictionary = root.get_meta("places", {})
	var well: Vector3 = places.get("well", Vector3(0.4, 0, 0.4))
	var mid := Vector3.ZERO if centre_reach(root) > 0.0 else well
	var rim := (centre_reach(root) if centre_reach(root) > 0.0 else 0.16) + 0.06
	var candles := int(g.get("candles", 16))
	for i in candles:
		var a := TAU * i / maxf(candles, 1) + rng.randf_range(-0.08, 0.08)
		var cn := _prop(life, center, ["Candle_1", "Candle_2", "CandleStick"][i % 3], mid + Vector3(cos(a), 0, sin(a)) * (rim + rng.randf_range(0.0, 0.03)), rng.randf() * TAU)
		if cn:
			cn.set_meta("dress", "candle")
	var flower := preload("res://scripts/dressing.gd").mesh_of("nature/Flower_4_Group")
	if not flower.is_empty():
		for i in int(g.get("flowers", 10)):
			var a := TAU * (i + 0.5) / maxf(int(g.get("flowers", 10)), 1)
			var at := mid + Vector3(cos(a), 0, sin(a)) * (rim + 0.035)
			var m := MeshInstance3D.new()
			m.mesh = flower[0]
			m.scale = Vector3.ONE * 0.12 * 0.6
			m.position = Vector3(at.x, _y(center, at) - float(flower[1]) * 0.072, at.z)
			m.rotation.y = rng.randf() * TAU
			life.add_child(m)
	# Black cloth over the doors nearest the square.
	var homes: Array = (root.get_meta("homes", []) as Array).duplicate()
	homes.sort_custom(func(a, b): return Vector2(a[0].x, a[0].z).length() < Vector2(b[0].x, b[0].z).length())
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.06, 0.055, 0.06)
	black.roughness = 1.0
	for h in homes.slice(0, int(g.get("black_doors", 12))):
		var step: Vector3 = h[0]
		var face: Vector3 = h[1]
		var cloth := _prop(life, center, "Banner_1_Cloth", step - face * 0.1, atan2(face.x, face.z), 0.6, 0.12)
		if cloth:
			cloth.set_meta("dress", "black_door")
			for gi in cloth.find_children("*", "GeometryInstance3D", true, false):
				(gi as GeometryInstance3D).material_override = black
	# The bell tolling from the sept (or the square).
	var toll := Node3D.new()
	toll.name = "Tolling"
	toll.set_meta("toll", g.get("toll", [9.0, 12.0]))
	var sept: Vector3 = places.get("sept", well)
	toll.position = Vector3(sept.x, _y(center, sept) + 0.3, sept.z)
	life.add_child(toll)
	# The funeral, walked round the square.
	var P: Dictionary = g.get("procession", {})
	var go: Node = life.get_node_or_null("SquareLife")
	if go == null or P.is_empty():
		return
	var r := float(root.get_meta("square_r", 1.0)) * float(P.get("ring", 0.72))
	var ring: Array = []
	var a0 := atan2(sept.x, sept.z)
	for i in 12:
		var a := a0 + TAU * i / 12.0
		ring.append(Vector3(sin(a), 0, cos(a)) * maxf(r, rim + 0.25))
	var walkers: Array = []
	if bool(P.get("priest", true)):
		walkers.append(_townsperson(life, ring[0], "clergy", "Walk", rng.randi()))
	var bearers: Array = []
	for i in int(P.get("bearers", 4)):
		var b := _townsperson(life, ring[0], "peasant", "Walk", rng.randi())
		bearers.append(b)
		walkers.append(b)
	for i in int(P.get("mourners", 8)):
		walkers.append(_townsperson(life, ring[0], "townsfolk" if i % 2 else "peasant", "Walk", rng.randi()))
	var bier := _prop(life, center, "Chest_Wood", ring[0], 0.0, 1.0)
	if bier:
		bier.scale = Vector3(0.7, 0.5, 1.5) * PROP_SCALE
	for w in walkers:
		w.set_meta("procession", true)
		_people.play(w, "Walk", 0.7)
	go.processions.append({"walkers": walkers, "bearers": bearers, "bier": bier, "ring": ring, "leg": 1, "pace": float(P.get("pace", 0.07)), "spacing": float(P.get("spacing", 0.11)), "trail": []})
