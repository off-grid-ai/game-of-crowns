extends Node3D
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Particles := preload("res://scripts/particles.gd")  # smoke and fire on the GPU
const SiegeCamp := preload("res://scripts/siege_camp.gd")  # the besiegers' camp and engines
const Fire := preload("res://scripts/fire.gd")  # fire v2: shaped flames, smoke and burnt houses
## The scene director: turns what just happened in Freeciv into something you
## can watch where it happened. Battles clash and leave the fallen; sacked
## towns burn while their people flee; famine sends families onto the roads;
## the King's grain goes out by wagon under escort.

## A scene has just been staged (what the bridge reported, and the thing to
## follow if it travels): the game can offer to take you to it.
signal staged(s: Dictionary, follow: Node3D)
## The King's grain, gold, ward or rider reached the town it was sent to.
signal arrived(s: Dictionary)

var terrain: Node3D
var towns: Node3D
var nav = preload("res://scripts/town_nav.gd").new()  # where people may stand, and the streets they walk
var people = preload("res://scripts/people.gd").new()
const Awareness := preload("res://scripts/awareness.gd")  # the realm's rules as the bridge sends them (season length, bands)
const Heraldry = preload("res://scripts/heraldry.gd")
const Realistic = preload("res://scripts/realistic.gd")
const TownLife := preload("res://scripts/town_life.gd")  # a feast's fire, its reach, and footprints
const TownNav := preload("res://scripts/town_nav.gd")
const Data := preload("res://scripts/data.gd")
var _seen := {}  # scene key -> true, so each event plays once
var _wagon: Mesh
var _sieges := {}  # city id -> {root, until}: one camp per besieged town, kept while the host stays
var _timber: StandardMaterial3D


func _ready() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	_wagon = builder.piece_mesh("Prop_Wagon")


## Whether the towns stand: scenes are set out against their buildings, so
## none is staged while a realm just opened is still putting them up.
## How far the town's outermost building stands from its heart (world units), 0 if it isn't up yet.
func _town_extent(id: int) -> float:
	if towns == null or not towns.towns.has(id):
		return 0.0
	var root: Node3D = towns.towns[id].get("node")
	if root == null or not is_instance_valid(root):
		return 0.0
	var far := 0.0
	for rect in root.get_meta("footprints", []):
		for v in rect:
			far = maxf(far, (v as Vector2).length())
	return far


func _towns_up() -> bool:
	if towns == null:
		towns = get_parent().get("towns")
	return towns == null or not towns.has_method("building") or not (towns.building() or towns.towns.is_empty())


## The army layer (docs/research/army-layer-2026-11-12.md): two hosts in the field (army_field.gd, in play when
## switched on), else the small skirmish (army_skirmish.gd); a siege's assault parties (army_assault.gd).
const Army := preload("res://scripts/army.gd")  # a host mustering and marching out (READY.md line 3)
const ArmyField := preload("res://scripts/army_field.gd")
const ArmySkirmish := preload("res://scripts/army_skirmish.gd")
const ArmyAssault := preload("res://scripts/army_assault.gd")


func sync(houses: Dictionary) -> void:
	var store: Node = Awareness.store()
	if not _towns_up():
		get_tree().create_timer(1.0).timeout.connect(sync.bind(houses))
		return
	var played_battle := {}
	for s in store.rec("scenes", []):
		var key := "%s:%d:%d:%d:%d" % [s["kind"], int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]
		if _seen.has(key):
			continue
		_seen[key] = true
		var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
		var follow: Node3D = null
		match String(s["kind"]):
			"battle":
				# Many deaths on one tile in one turn are one battle.
				var tile := "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s["turn"])]
				if played_battle.has(tile):
					continue
				played_battle[tile] = true
				# The bridge says who won and how many fought (battles.js); a field battle when it can be staged
				# (army_field.gd, field.play.on), else the small skirmish.
				var victor := int(s["victor"]) if s.get("victor") != null else -1
				if victor < 0:
					victor = _victor(s)  # the bridge didn't see who: whoever stands beside it
				var staged_field: Node = null
				if s.get("kinds") != null and ArmyField.in_play():
					staged_field = ArmyField.stage(get_parent(), s, houses, battlefield(at))
				if staged_field == null:
					_battle(at, houses.get(int(s.get("owner", -1)), {}), houses.get(victor, {}))
			"sack":
				_burn(at, 45.0)
				_refugees(at, 7)
			"razed":
				_burn(at, 70.0, 2.0)
				_refugees(at, 10)
			"famine":
				_refugees(at, 5)
			"plague":
				_refugees(at, 3)
			"siege":
				var city: Dictionary = {}
				for c in store.rec("cities", []):
					if int(c["id"]) == int(s["city"]):
						city = c
				var approach: Vector3 = terrain.world_pos(float(s.get("ax", s["x"])), float(s.get("ay", s["y"])))
				_siege(int(s["city"]), at, approach, int(city.get("size", 4)), int(s.get("engines", 0)), houses.get(int(s.get("owner", -1)), {}), houses.get(int(s.get("defender", -1)), {}), Awareness.season_seconds)
			"storm":
				# Freeciv's assault on a town (the bridge's storm scene, campaigns.js stormScene): the siege shown there
				# storms and ends as Freeciv decided; pitched first when the view has none there yet.
				var stormed := int(s["city"])
				var town_size := 4
				for c in store.rec("cities", []):
					if int(c["id"]) == stormed:
						town_size = int(c.get("size", 4))
				_siege(stormed, at, terrain.world_pos(float(s.get("ax", s["x"])), float(s.get("ay", s["y"]))), town_size, int(s.get("engines", 0)), houses.get(int(s.get("owner", -1)), {}), houses.get(int(s.get("defender", -1)), {}), Awareness.season_seconds)
				storm(stormed, bool(s.get("taken", false)))
			"grain", "tribute":
				follow = _convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), s["kind"] == "grain", "", s)
			"muster":
				_muster(s, at, houses)
			"ward":
				follow = _convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), false, "A ward for the King's court", s)
			"rider":
				follow = _rider(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), String(s.get("label", "The King's word")), s)
			"feast":
				_feast(at, houses.get(int(s.get("owner", -1)), {}))
			"handover":
				var town := "The town"
				for c in store.rec("cities", []):
					if int(c["id"]) == int(s.get("city", -1)):
						town = String(c.get("title", c["name"]))
				_handover(at, houses.get(int(s.get("from", -1)), {}), houses.get(int(s.get("to", -1)), {}), town)
		staged.emit(s, follow)


## Who won a fight: the house with men standing on or next to the tile where
## the loser's died. -1 if no one is there.
func _victor(s: Dictionary) -> int:
	var store: Node = Awareness.store()
	var best := -1
	var near := INF
	for u in store.rec("units", []):
		if int(u["owner"]) == int(s.get("owner", -1)):
			continue
		var d := Vector2(float(u["x"]) - float(s["x"]), float(u["y"]) - float(s["y"])).length()
		if d <= 1.5 and d < near:
			near = d
			best = int(u["owner"])
	return best


# --- the roads alive: carters and pedlars between the King's moments ---------------



## A rider on the road from one town to another, given back so what rides with
## him (a house's envoy plate, scheme_marks.gd) can follow; null when none can go.
func rider_on_road(from: Vector3, to: Vector3, on_done := Callable()) -> Node3D:
	var horse := _rider(from, to, "")
	if horse and on_done.is_valid():
		horse.tree_exited.connect(on_done)
	return horse


## Someone on the road from one town to another, of a kind: "walker", "cart",
## "wagon" (a trade convoy's cart), "rider", "soldier" or "refugee". Who goes,
## where and how often is traffic.gd's to decide (it reads the awareness
## mirror); this only builds them and walks them along the road. `on_done` is
## called when they arrive and are gone. Returns false when no road joins the two.
func traveller(from: Vector3, to: Vector3, kind := "walker", on_done := Callable()) -> bool:
	if kind == "rider":
		return rider_on_road(from, to, on_done) != null
	var r := _rng(from + Vector3(randf(), 0, randf()))
	# Only where there's a way: a straight line between two towns means no road
	# and no land joins them (it would cross the water).
	var way := _route(from, to)
	if way.size() <= 2:
		return false
	var carter := kind in ["cart", "wagon"]
	var cloth: Color = [Color(0.55, 0.47, 0.36), Color(0.42, 0.45, 0.38), Color(0.5, 0.36, 0.3), Color(0.38, 0.4, 0.47), Color(0.6, 0.55, 0.45)][r.randi() % 5]
	var station: String = {"soldier": "soldier", "refugee": "peasant"}.get(kind, ["townsfolk", "peasant", "peasant", "townsfolk"][r.randi() % 4])
	var who: Node3D = people.make(r, station, cloth.darkened(0.25) if kind == "refugee" else cloth, "adult" if kind == "soldier" else ["adult", "adult", "elder"][r.randi() % 3])
	var body: Node3D = who
	if carter:
		body = _cart_rig(r, who)
		body.rotation.y = PI  # the rig is built facing -z: turned to face +z like everyone else
	# A soldier marches, a refugee trudges, everyone else walks.
	var gait: String = {"soldier": "SS_Walk", "refugee": "Injured_Walk"}.get(kind, "Walk")
	people.play(who, gait, r.randf_range(0.9, 1.1))
	var pace: float = {"cart": 0.22, "wagon": 0.18, "soldier": 0.3, "refugee": 0.2}.get(kind, 0.26)
	# Along the road the navigation gave, giving way to anyone standing in it (Mover.road).
	Mover.road(self, way, [[body, 0.0]], pace, {"min": 15.0, "max": 90.0, "yields": true, "ahead": 0.16 if carter else 0.1}, on_done)
	return true


## One horse and cart, built as a single piece so its parts can never come
## apart: the wagon, a hitch where its shafts end, the horse between the shafts
## facing the way they point, and the carter at the horse's head. Its forward is
## -z, the way PathFollow3D carries it.
func _cart_rig(r: RandomNumberGenerator, carter: Node3D) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Cart"
	var wagon := MeshInstance3D.new()
	wagon.mesh = _wagon
	var big := float(Data.num("people", "readable", 1.0))  # drawn larger, as the people and horses are
	wagon.scale = Vector3.ONE * 0.1 * big
	wagon.rotation.y = PI  # the wagon's shafts are its +z end: turned to point forward
	rig.add_child(wagon)
	var hitch := Marker3D.new()
	hitch.name = "Hitch"
	hitch.position = Vector3(0, 0, -0.08 * big)  # between the shafts, just ahead of the box
	rig.add_child(hitch)
	var horse: Node3D = Horse.new(r.randi() % Horse.COATS.size())
	horse.rotation.y = PI  # horses face +z
	hitch.add_child(horse)
	carter.position = Vector3(0.09, 0, -0.16) * big  # walking at the horse's head
	carter.rotation.y = PI
	rig.add_child(carter)
	return rig


func _rng(at: Vector3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(at) + Time.get_ticks_msec()
	return r


## Where a person may stand nearest `p`: on the ground and in no building
## (town_nav.gd, the realm's one answer). Every person or horse a scene places
## or moves is set down through here; things (standards, fires, wagons' dust)
## use _ground.
func stand(p: Vector3, body := 0.0) -> Vector3:
	if towns == null:
		towns = get_parent().get("towns")
	nav.terrain = terrain
	if nav.roads == null:
		nav.roads = get_parent().get("roads")
	return nav.stand(towns, p, body)


## A horse is set down with its whole body clear, nose to tail.
const HORSE_BODY := 0.17


## The way a scene's people go from one place to another: through a town's
## streets, never through its houses, and over open land between.
func _route(from: Vector3, to: Vector3) -> PackedVector3Array:
	stand(from)  # finds the towns and the ground
	return nav.route(towns, from, to)


func ground(p: Vector3) -> Vector3:
	var rs := get_parent().get_node_or_null("Roadside")  # a bridge's deck, where one stands (roadside.gd)
	return Vector3(p.x, maxf(terrain.height_at(p.x, p.z), rs.deck_at(p.x, p.z) if rs else -INF), p.z)


## The road a traveller's PathFollow3D rides, with its height taken from the
## ground every `travel.groundStep` units: a curve through waypoints tiles
## apart lerps its height between them, and walkers on it sank knee-deep where
## a town had levelled its square below the line (realm/data/people.json).
func _on_ground(c: Curve3D) -> Curve3D:
	var step := Data.num("people", "travel.groundStep", 0.08)
	var length := c.get_baked_length()
	var out := Curve3D.new()
	out.bake_interval = c.bake_interval
	var d := 0.0
	while true:
		out.add_point(ground(c.sample_baked(minf(d, length), true)))
		if d >= length:
			break
		d += step
	return out


# --- arms ----------------------------------------------------------------------

const Horse := preload("res://scripts/horse.gd")
const Combat := preload("res://scripts/combat.gd")


## A cut from the sword-and-shield set (combat.gd): a different one each time,
## never `last`. The jumping slash is left for the duels.
static func cut(r: RandomNumberGenerator, last := "") -> String:
	var moves: Array = Combat.KITS["sword"]["attacks"].filter(func(x): return x != last and x != "Sword_Attack_2")
	return moves[r.randi() % moves.size()]


## A guard or parry from the same set.
static func guard(r: RandomNumberGenerator) -> String:
	var g: Array = Combat.KITS["sword"]["parry"] + [Combat.KITS["sword"]["guard"]]
	return g[r.randi() % g.size()]
static var SWORD: PackedScene = load(Realistic.path_of("sword"))
static var SHIELD: PackedScene = load(Realistic.path_of("shield"))
# Where a weapon sits in the hand, in the hand bone's own space (metres).
static var SWORD_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)).scaled(Vector3.ONE * 0.8), Vector3(0, 0.08, 0.02))
static var SPEAR_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)), Vector3(0, 0.08, 0.02))
static var SHIELD_GRIP := Transform3D(Basis.from_euler(Vector3(-PI / 2, 0, 0)).scaled(Vector3.ONE * 0.9), Vector3(0, 0.06, 0))
const DEATHS := ["Death01", "Death_Front", "Death_Back", "Sword_Death"]


## A company's standard as its bearer carries it, beside him and about 0.4
## world units tall (a man stands 0.22), whatever scale the bearer is drawn at:
## a man on foot is scaled to the towns, a horse is not.
const CARRIED := 0.4
static func carried_standard(bearer: Node3D, house: Dictionary, color: Color) -> Node3D:
	var k := maxf(bearer.global_transform.basis.get_scale().y if bearer.is_inside_tree() else bearer.scale.y, 0.001)
	var b: Node3D = Heraldry.standard(house, color, CARRIED / k)
	b.position = Vector3(0.042, 0, -0.012) / k
	bearer.add_child(b)
	return b


## Puts arms in a soldier's hands, held on the hand bones so they swing with
## every move: "sword" (sword and shield), "spear" (spear and shield), "lance"
## (a knight's shield; the lance is the horse's to carry, see horse.gd), or
## "bow" (archers keep their hands free; there is no bow model yet).
static func arm(person: Node3D, kit: String, paint := Color.TRANSPARENT) -> void:
	var skel: Skeleton3D = person.get_node_or_null("Armature/GeneralSkeleton")
	if skel == null or kit == "bow":
		return
	var shield: Node3D = SHIELD.instantiate()
	if paint.a > 0.0:
		_paint(shield, paint)
	_hold(skel, "LeftHand", shield, SHIELD_GRIP)
	if kit == "lance":
		var h: Node = person.get_meta("mounted", null)
		if h:
			h.bear_lance()
		return
	_hold(skel, "RightHand", SWORD.instantiate() if kit == "sword" else _spear(), SWORD_GRIP if kit == "sword" else SPEAR_GRIP)


## A shield painted in its side's colour: half the soldiers wear their own
## clothes, so in the press the shields are what tells the two sides apart.
static var _paints := {}
static func _paint(shield: Node3D, col: Color) -> void:
	var key := col.to_html()
	if not _paints.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.75
		_paints[key] = m
	for mi in shield.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _paints[key]


static func _hold(skel: Skeleton3D, bone: String, item: Node3D, grip: Transform3D) -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = bone
	skel.add_child(at)
	item.transform = grip
	at.add_child(item)


## An ash shaft about 2.4 m long with a bronze blade for its head, held a
## third of the way up.
static func _spear() -> Node3D:
	var s := Node3D.new()
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.014
	cyl.bottom_radius = 0.016
	cyl.height = 2.4
	cyl.radial_segments = 6
	shaft.mesh = cyl
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.36, 0.27, 0.18)
	wood.roughness = 0.9
	shaft.material_override = wood
	shaft.position.y = 0.4
	s.add_child(shaft)
	var head: Node3D = SWORD.instantiate()
	head.scale = Vector3.ONE * 0.22
	head.position.y = 1.62
	s.add_child(head)
	return s


## Scales a model so it stands `height` tall, measured through its own node
## transforms (an armature's import scale included), before it is in the tree.
static func _fit_static(n: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf: Transform3D = (mi as Node3D).transform
		var up: Node = mi.get_parent()
		while up != n and up is Node3D:
			xf = (up as Node3D).transform * xf
			up = up.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		n.scale = Vector3.ONE * (height / box.size.y)


# --- battle -----------------------------------------------------------------------

## A pitched battle where Freeciv says men died, staged like film. The losing
## house (team 0) holds a shield wall: swords and locked shields in front,
## spears over their shoulders, archers behind. The victors (team 1) form
## under their banner while their captain shouts them on, advance at a walk
## under the archers' arrows, then charge home as their knights gallop round the
## end of the wall into its flank. Front-rank men duel the man opposite; men fall, those behind step
## up. The defenders' standard-bearer goes down, the banner falls, and the
## wall breaks and scatters. The victors cheer under their own standard.
const RANKS := 3
const FILES := 9
const GAP := 0.2  # between files: about 1.7 m, room for each pair to fight
const ROW := 0.2  # between ranks: about 1.7 m
const REACH := 0.11  # half the distance between two duelists: 1.8 m apart
const KNIGHTS := 5
const FIELD := 3.4  # how far the fight reaches from its centre: lines, the attackers' approach, the knights' wing

## Camera beats for whoever holds the camera (the director, or a shot):
## where to look, from how far, and from which side.
signal framing(pos: Vector3, dist: float, yaw: float)


var _fighting: Array = []  # [centre, battle root] of every battle on the field now
var last_view_yaw := 0.0  # the side the last battle is watched from (its trees cleared); the film takes use it


func _battle(at: Vector3, loser: Dictionary, victor := {}) -> void:
	var root := Node3D.new()
	root.name = "Battle"
	add_child(root)
	var r := _rng(at)
	var lost := Color.from_string(String(loser.get("color", "#777")), Color.GRAY)
	var won := Color.from_string(String(victor.get("color", "#7f2b26")), Color(0.5, 0.17, 0.15))
	# Two houses in like colours (or victors unknown, in blood red, against a red
	# house): the victors go in steel blue, so you can tell the sides apart.
	if absf(wrapf(lost.h - won.h, -0.5, 0.5)) < 0.12 and lost.s > 0.25 and won.s > 0.25:
		won = Color(0.22, 0.3, 0.46)
	var cols := [lost.lerp(Color.WHITE, 0.3), won.lerp(Color.WHITE, 0.15)]
	# Battles are fought on open ground: out past the town, off its roads and
	# fields, on land flat enough to hold a line. No trees stand in the fight.
	# The field is chosen against the towns as they stand: while they are
	# still going up (a realm just opened), wait for them.
	if not _towns_up():
		root.queue_free()
		get_tree().create_timer(0.5).timeout.connect(_battle.bind(at, loser, victor))
		return
	at = battlefield(at)
	if at == Vector3.INF:
		root.queue_free()
		return  # no open ground near: the battle is told, not shown
	_fighting.append([at, root])
	terrain.clear_around(at, FIELD)
	# The lines meet across the view, so you watch the clash from the side.
	var dir := Vector3(cos(r.randf() * TAU), 0, 0)
	dir.z = sqrt(1.0 - dir.x * dir.x)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam:
		dir = Vector3(cam.global_basis.x.x, 0, cam.global_basis.x.z).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	# One side of the field for the whole battle: moving round it puts houses
	# and trees between you and the fighting.
	var view_yaw := atan2(side.x, side.z) + 0.35
	last_view_yaw = view_yaw
	# The camera watches low across the field from that side: fell the trees
	# between it and the fight, in a cone opening toward where it stands.
	var toward_cam := Vector3(sin(view_yaw), 0, cos(view_yaw))
	for k in 6:
		terrain.clear_around(at + toward_cam * (FIELD + k * 1.2), 1.4 + k * 0.35)
	var teams := [[], []]
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		for rank in RANKS:
			for file in FILES:
				# Where this man will stand once the lines meet. The wall holds
				# its ground a little forward; the attackers start well back.
				var slot: Vector3 = at - face * (REACH + rank * ROW) + side * ((file - (FILES - 1) / 2.0) * GAP)
				slot += side * r.randf_range(-0.015, 0.015) - face * r.randf_range(0.0, 0.02)
				var f: Node3D = people.make(r, "soldier", cols[team], "adult")
				var back := 0.25 if team == 0 else 1.5
				f.position = stand(slot - face * back)
				f.rotation.y = atan2(face.x, face.z)
				root.add_child(f)
				var kit := "sword"
				if team == 0 and rank == 1:
					kit = "spear"
				elif team == 0 and rank == 2:
					kit = "bow"
				arm(f, kit, cols[team])
				people.play(f, "Bow_Idle" if kit == "bow" else "Sword_Idle", r.randf_range(0.9, 1.1))
				teams[team].append({"node": f, "rank": rank, "file": file, "face": face, "slot": slot, "alive": true, "engaged": false, "kit": kit})
	# Each side's standard, carried by a bearer behind the middle of its line.
	var bearers := []
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		var p: Vector3 = at - face * (REACH + RANKS * ROW + (0.3 if team == 0 else 1.6))
		var bearer: Node3D = people.make(r, "soldier", cols[team], "adult")
		bearer.position = stand(p)
		bearer.rotation.y = atan2(face.x, face.z)
		root.add_child(bearer)
		arm(bearer, "bow")
		people.play(bearer, "Sword_Idle")
		var house: Dictionary = loser if team == 0 else victor
		# A standard needs its house's arms; men of no known house fight without one.
		var flag: Node3D = _standard(root, p + side * 0.06, cols[team], face, house)
		bearers.append({"node": bearer, "flag": flag, "face": face})
	var knights := _flank_company(root, at, dir, side, cols[1], r)
	root.set_meta("fallen", [])
	framing.emit(ground(at), 5.5, view_yaw)
	# Fought by the men in it: each soldier and knight runs his own mind (army_skirmish.gd, the army layer's
	# close fight), every step through his Mover on the field's own ground.
	ArmySkirmish.new().start(self, root, r, at, dir, side, view_yaw, teams, knights, bearers)


## Plays a move with everyone at the same point in it: a rank marching in step,
## or drilling as one.
func _in_step(n: Node3D, anim_name: String, phase: float, speed := 1.0) -> void:
	n.set_meta("tempo", 1.0)
	people.play(n, anim_name, speed, phase)


## The fallen lie apart, never on one another: a body that would land on
## another (`size` its half-length: a man about 0.1, a horse 0.17) staggers to
## the nearest free ground as it goes down. The battle keeps its list of them.
func _lie_clear(n: Node3D, size: float, body: float) -> void:
	var root: Node = n.get_parent()
	if root == null or not root.has_meta("fallen"):
		return
	var fallen: Array = root.get_meta("fallen")
	var p := n.global_position
	var free := func(q: Vector3) -> bool:
		for f in fallen:
			if _flat_gap(q, f[0]) < size + float(f[1]):
				return false
		return true
	var to := p
	if not free.call(p):
		var found := false
		for k in range(1, 8):
			for i in 12:
				var a := TAU * i / 12.0
				var q := p + Vector3(cos(a), 0, sin(a)) * k * 0.05
				if free.call(q):
					to = q
					found = true
					break
			if found:
				break
	fallen.append([to, size])
	if to != p:
		var mo: Node = Mover.of(n)  # he staggers there as he goes down (the one way to move)
		mo.stop()
		mo.clip = ""
		mo.shift(stand(to, body), 0.5)


## A man goes down and stays down: the death plays once and holds its last frame.
func die(n: Node3D, how: String, r: RandomNumberGenerator) -> void:
	if n.has_meta("dead"):
		return  # one death each: a body is never laid down twice
	n.set_meta("dead", true)
	n.remove_meta("in_step")  # no move held back for later: he stays down
	_lie_clear(n, 0.1, 0.0)
	people.die(n, how, r.randf_range(0.9, 1.1))


## Archers loose a volley: an arrow from each living archer arcs onto the
## advancing ranks, and now and then one finds its man.
func _arrows(root: Node3D, archers_team: Array, targets: Array, r: RandomNumberGenerator) -> void:
	for m in archers_team:
		if not m["alive"] or m["kit"] != "bow":
			continue
		var n: Node3D = m["node"]
		var tw := n.create_tween()
		tw.tween_interval(r.randf_range(0.0, 0.3))
		tw.tween_callback(func(): people.play(n, "Bow_Draw", 1.2))
		tw.tween_interval(0.6)
		tw.tween_callback(func():
			if not m["alive"]:
				return
			people.play(n, "Bow_Shoot", 1.0)
			var mark: Dictionary = targets[r.randi() % targets.size()]
			var land: Vector3 = mark["node"].position + Vector3(r.randf_range(-0.12, 0.12), 0, r.randf_range(-0.12, 0.12))
			_arrow(root, n.position + Vector3(0, 0.17, 0), land, r)
			if mark["alive"] and mark["rank"] > 0 and r.randf() < 0.08:
				mark["alive"] = false
				var hit: Tween = mark["node"].create_tween()
				hit.tween_interval(1.1)
				hit.tween_callback(func(): die(mark["node"], "Death_Front", r)))
		tw.tween_interval(0.5)
		tw.tween_callback(func():
			if m["alive"] and not m["engaged"]:
				people.play(n, "Bow_Idle", 1.0))


var _arrow_mesh: BoxMesh


func _arrow(root: Node3D, from: Vector3, to: Vector3, r: RandomNumberGenerator) -> void:
	if _arrow_mesh == null:
		_arrow_mesh = BoxMesh.new()
		_arrow_mesh.size = Vector3(0.0025, 0.0025, 0.09)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.25, 0.2, 0.15)
		_arrow_mesh.material = mat
	var a := MeshInstance3D.new()
	a.mesh = _arrow_mesh
	root.add_child(a)
	var top := from.distance_to(to) * 0.35
	var path := func(t: float) -> Vector3:
		var p := from.lerp(to, t)
		p.y += top * 4.0 * t * (1.0 - t)
		return p
	var tw := a.create_tween()
	tw.tween_method(func(t: float):
		var p: Vector3 = path.call(t)
		var q: Vector3 = path.call(minf(t + 0.02, 1.0))
		a.position = p
		if q.distance_to(p) > 0.0001:
			a.look_at(q, Vector3.UP), 0.0, 1.0, r.randf_range(1.0, 1.2))
	# Arrows that miss stand in the ground a while.
	tw.tween_interval(6.0)
	tw.tween_callback(a.queue_free)


## The victors' knights: horsemen waiting on open ground out on the wing, well
## behind their own line (the victors form on the -dir side), to walk up during
## the advance.
func _flank_company(root: Node3D, at: Vector3, dir: Vector3, side: Vector3, col: Color, r: RandomNumberGenerator) -> Array:
	var knights := []
	for i in KNIGHTS:
		var h: Node3D = Horse.new(r.randi() % 5)
		root.add_child(h)
		h.mount(people.make(r, "soldier", col, "adult"))
		arm(h.rider, "lance", col)
		var wing: Vector3 = at + side * ((FILES / 2.0) * GAP + 0.55 + (i / 2) * 0.24) - dir * ((i % 2) * 0.22)
		h.position = stand(wing - dir * (REACH + RANKS * ROW + 1.8), HORSE_BODY)
		h.rotation.y = atan2(dir.x, dir.z)
		knights.append({"node": h, "wing": wing, "alive": true})
	return knights


## A standard planted behind a line or at a muster: a little taller than one carried.
const PLANTED := 0.45


func _standard(root: Node3D, p: Vector3, color: Color, face: Vector3, house := {}) -> Node3D:
	var b: Node3D = Heraldry.standard(house, color, PLANTED)
	b.position = ground(p)
	b.rotation.y = atan2(face.x, face.z)
	root.add_child(b)
	return b


## A standard goes over: it sways, then topples backward from the line and
## lies on the field. `face` is the way its line faced.
func _drop_banner(b: Node3D, face := Vector3.ZERO) -> void:
	# The cloth turns to face you about its pole while it stands; once it falls
	# it must go down with the pole, so it gets a cloth of its own that doesn't.
	var cloth: MeshInstance3D = b.get_node_or_null("Banner")
	if cloth and cloth.material_override is BaseMaterial3D:
		var m: BaseMaterial3D = cloth.material_override.duplicate()
		m.billboard_mode = BaseMaterial3D.BILLBOARD_DISABLED
		cloth.material_override = m
	var tw := b.create_tween()
	if face == Vector3.ZERO:
		tw.tween_property(b, "rotation:x", deg_to_rad(80), 1.2).set_ease(Tween.EASE_IN)
		return
	# Topple about the axis along the line, away from the fighting.
	var axis := Vector3(-face.z, 0, face.x).normalized()
	var start := b.transform.basis
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.0, 0.12, 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.12, 0.04, 0.3).set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 0.04, 1.0, 1.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_method(func(k: float):
		b.transform.basis = Basis(axis, -k * deg_to_rad(84)) * start, 1.0, 0.96, 0.15)


func dust(root: Node3D, p: Vector3, along: Vector3, width: float) -> void:
	# A thin haze kicked up along the line where the ranks meet, low and faint.
	var d := _puffs(Color(0.58, 0.52, 0.42, 0.07), 8, 1.6, 0.04, 0.09)
	d.direction = Vector3(0, 0.2, 0)
	d.spread = 70
	d.initial_velocity_min = 0.02
	d.initial_velocity_max = 0.06
	d.gravity = Vector3(0, -0.01, 0)
	d.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	d.emission_box_extents = Vector3(width * 0.5, 0.01, 0.05)
	d.position = p
	d.rotation.y = atan2(along.x, along.z) - PI / 2
	d.emitting = true
	var gd := Particles.to_gpu(d)
	root.add_child(gd)
	var tw := gd.create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(func(): gd.emitting = false)


# --- sieges ------------------------------------------------------------------------------

## A host at a town's walls: its camp spreads in an arc on the side it came
## from, engines throw stones over the walls, assault parties rush the walls
## and fall back, and the defenders hold the line. The camp stays while the
## bridge keeps reporting the siege, and breaks up a turn and a half after.
func _siege(id: int, at: Vector3, approach: Vector3, size: int, engines: int, foe: Dictionary, held: Dictionary, turn_secs: float) -> void:
	if _sieges.has(id) and is_instance_valid(_sieges[id]["root"]):
		_sieges[id]["until"] = Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5
		return
	if not _towns_up():
		# Pitched once the town stands; until then, where it will be.
		_sieges[id] = {"root": null, "until": 0.0, "front": ground(approach)}
		get_tree().create_timer(1.0).timeout.connect(_siege.bind(id, at, approach, size, engines, foe, held, turn_secs))
		return
	var root := Node3D.new()
	root.name = "Siege"
	root.set_meta("fallen", [])  # the dead lie clear of each other, never in a heap
	add_child(root)
	_sieges[id] = {"root": root, "until": Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5}
	# The siege's dead are carried off after a minute, so the living never fight on them.
	var sweep := Timer.new()
	sweep.wait_time = 10.0
	root.add_child(sweep)
	sweep.timeout.connect(func():
		var now := Time.get_ticks_msec()
		for n in root.get_children():
			if n is Node3D and n.has_meta("dead"):
				if not n.has_meta("dead_ms"):
					n.set_meta("dead_ms", now)
				elif now - int(n.get_meta("dead_ms")) > 60000:
					n.queue_free())
	sweep.start()
	var r := _rng(at)
	var foe_col := Color.from_string(String(foe.get("color", "#7a2222")), Color.DARK_RED).lerp(Color.WHITE, 0.2)
	var held_col := Color.from_string(String(held.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.3)
	# The siege stands outside where the town really stands: its houses' outermost corner (round 2's
	# ring streets and packed plots reach past the old size rule), so the wall, the breach, the band of
	# engines and the camp are out on open ground with nothing built between them and the camera.
	var reach := maxf(clampf(1.6 + size * 0.32, 2.0, 6.0), _town_extent(id) + Data.num("siege", "clear_of_town", 0.25))
	var wall := reach + 0.35
	var out := Vector3(approach.x - at.x, 0, approach.z - at.z)
	var want := atan2(out.z, out.x) if out.length() > 0.01 else r.randf() * TAU
	var camp_r := wall + 1.3
	var base := _camp_side(at, want, wall, camp_r)
	var arc := func(a: float, rad: float) -> Vector3:
		return ground(at + Vector3(cos(base + a), 0, sin(base + a)) * rad)
	_sieges[id]["front"] = arc.call(0.0, wall + 0.6)
	# Seen from behind the camp, on the open ground it was pitched on, over the
	# engines and companies to the walls.
	framing.emit(_sieges[id]["front"], 4.5, PI / 2 - base)
	# The camp: companies under their standards.
	for g in 5:
		var a := (g - 2) * 0.32 + r.randf_range(-0.06, 0.06)
		var c: Vector3 = arc.call(a, camp_r)
		var inward := (at - c).normalized()
		inward.y = 0
		_standard(root, c - inward * 0.45, foe_col, inward, foe)
		for i in 5:
			var p := c + Vector3(r.randf_range(-0.35, 0.35), 0, r.randf_range(-0.35, 0.35))
			if not _footing(p):
				continue
			var f: Node3D = people.make(r, "soldier", foe_col, "adult")
			f.position = stand(p)
			f.rotation.y = atan2(inward.x, inward.z) + r.randf_range(-0.6, 0.6)
			root.add_child(f)
			arm(f, "spear" if i % 2 == 0 else "sword")
			people.play(f, "Sword_Idle" if r.randf() < 0.6 else "Idle", r.randf_range(0.8, 1.1))
	# The camp and its engines (siege_camp.gd): tents, palisade, fires, wagons, and the bridge's engines (Freeciv's
	# catapults and trebuchets at the walls) built on the spot and worked by their crews.
	var camp: Node3D = SiegeCamp.new()
	camp.pitch(self, root, at, base, camp_r, foe_col, engines, r)
	# The defenders on the walls, facing out toward the host: archers and
	# spearmen turn about.
	var archers := []
	var spears := []  # the wall's spearmen, who fight back at whoever reaches its foot
	for i in 9:
		var a := (i - 4) * 0.13
		var p: Vector3 = stand(arc.call(a, wall - 0.3))
		if not _footing(p):
			continue
		var f: Node3D = people.make(r, "soldier", held_col, "adult")
		f.position = p
		var face := (p - at).normalized()
		f.rotation.y = atan2(face.x, face.z)
		root.add_child(f)
		var bow := i % 2 == 0
		arm(f, "bow" if bow else "spear")
		people.play(f, "Bow_Idle" if bow else "Sword_Idle", r.randf_range(0.9, 1.1))
		if bow:
			archers.append({"node": f, "alive": true, "kit": "bow", "engaged": false})
		else:
			spears.append(f)
	# Assault parties rush the walls in turn under the archers' arrows, fight there, and fall back; fought by the
	# men in them (army_assault.gd, the army layer's close fight).
	var parties := []
	if OS.get_cmdline_user_args().has("--probe"):
		print("SIEGE staged: parties=%d" % 2)
	for party in 2:
		parties.append(_assault(arc, (party - 0.5) * 0.5, camp_r, wall))
	var assault := ArmyAssault.new()
	assault.start(self, root, r, foe_col, parties, [3.0, 9.0], held_col, at)  # held_col: the block behind a breach; at: the town the storm torches
	_sieges[id]["assault"] = assault
	var loose := Timer.new()
	loose.wait_time = 2.6
	loose.autostart = true
	loose.timeout.connect(func():
		var marks := []
		for men in parties:
			marks.append_array(men.filter(func(m): return m.get("out", false) and m["alive"]))
		if is_instance_valid(camp):
			marks.append_array(camp.marks())  # the engines' crews
		if not marks.is_empty():
			_arrows(root, archers, marks, r)
		# The spearmen above thrust down at the men at the foot of the wall,
		# or raise their shields against what comes up.
		for sp in spears:
			if is_instance_valid(sp) and not sp.has_meta("dead") and marks.any(func(m): return _flat_gap(m["node"].global_position, sp.global_position) < 0.6):
				people.play(sp, "Spear_Thrust" if r.randf() < 0.7 else guard(r), r.randf_range(0.9, 1.15)))
	root.add_child(loose)
	_siege_watch(id)


## The side a host camps on: open, dry, gentle ground, as near as possible to
## the way it came. Each direction is scored by how far it turns from that way
## and by the water and slope along its arc.
func _camp_side(at: Vector3, want: float, wall: float, camp_r: float) -> float:
	var best := want
	var best_score := INF
	for i in 24:
		var a := want + TAU * i / 24.0
		var score := absf(wrapf(a - want, -PI, PI)) * 0.6
		for k in 5:
			var aa := a + (k - 2) * 0.3
			var d := Vector3(cos(aa), 0, sin(aa))
			var p := at + d * camp_r
			if not terrain.is_land(p.x, p.z):
				score += 3.0
			score += absf(terrain.height_at(p.x, p.z) - terrain.height_at(at.x + d.x * wall, at.z + d.z * wall)) * 1.5
		if score < best_score:
			best_score = score
			best = a
	return best


## Whether a man could stand here: dry land, not a crag.
func _footing(p: Vector3) -> bool:
	if not terrain.is_land(p.x, p.z):
		return false
	return absf(terrain.height_at(p.x + 0.15, p.z) - terrain.height_at(p.x - 0.15, p.z)) < 0.12 and absf(terrain.height_at(p.x, p.z + 0.15) - terrain.height_at(p.x, p.z - 0.15)) < 0.12


## Open ground for a pitched battle, as near `near` as there is. A field is
## never in or beside a town or a farmstead: one whose fighting ground (FIELD
## and a margin) comes within any town's reach or near a farm is refused
## outright, and the search widens ring by ring until a clear one is found.
## Among the clear fields of the nearest ring, the driest, flattest and most
## open wins. Vector3.INF if the land has none (no battle is staged then).
func battlefield(near: Vector3) -> Vector3:
	var main := get_parent()
	if towns == null:
		towns = main.get("towns")
	var roads = main.get("roads")
	var country = main.get("countryside")
	var span := RINGS * 0.8 + FIELD
	var walls := []  # [centre, reach] of every town that could touch a field
	if towns:
		for id in towns.towns:
			var t: Node3D = towns.towns[id]["node"]
			var reach := float(t.get_meta("reach", 6.0)) if is_instance_valid(t) else 0.0
			if reach > 0.0 and _flat_gap(t.global_position, near) < span + reach:
				walls.append([t.global_position, reach])
	# A field already being fought over is taken: the next battle finds its own.
	_fighting = _fighting.filter(func(b): return is_instance_valid(b[1]))
	for b in _fighting:
		walls.append([b[0], FIELD])
	var farms := []
	for f in (country.get("_sites") if country else []):
		if _flat_gap(f["at"], near) < span + FARM_CLEAR:
			farms.append(f["at"])
	for ring in RINGS:
		var best := Vector3.INF
		var best_score := INF
		var n := maxi(1, ring * 8)
		for i in n:
			var a := TAU * i / n
			var p := ground(near + Vector3(cos(a), 0, sin(a)) * ring * 0.8)
			if not _clear_field(p, walls, farms):
				continue
			var score := _field_cost(p, roads)
			if score < best_score:
				best_score = score
				best = p
		if best != Vector3.INF:
			return best
	return Vector3.INF


## The most the ground may rise or fall across a field, from its centre.
const FIELD_RISE := 0.3
## How far out (in rings 0.8 apart) the field is looked for.
const RINGS := 40
## How far a field's edge keeps from a town's reach, and its centre from a farmstead.
const TOWN_CLEAR := 0.4
const FARM_CLEAR := FIELD + 4.8  # a farmstead's fields reach up to 4.6 from it (countryside._farmstead)
## What the land itself costs a battle, per sample: woods hide it, hills break the lines.
const ROUGH_GROUND := {"Forest": 12.0, "Jungle": 12.0, "Swamp": 8.0, "Hills": 4.0, "Mountains": 50.0, "Glacier": 50.0}


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Whether a field centred at `c` is clear of every town and farm.
static func _clear_field(c: Vector3, walls: Array, farms: Array) -> bool:
	for w in walls:
		if _flat_gap(c, w[0]) < float(w[1]) + FIELD + TOWN_CLEAR:
			return false
	for f in farms:
		if _flat_gap(c, f) < FARM_CLEAR:
			return false
	return true


## What's wrong with fighting at `c`: water, slope, rough ground and roads
## across the field, sampled at its centre and on three rings to its edge.
func _field_cost(c: Vector3, roads) -> float:
	var cost := 0.0
	for k in 25:
		var ring := int(ceil(k / 8.0))
		var q := c + Vector3(cos(TAU * k / 8.0), 0, sin(TAU * k / 8.0)) * FIELD * ring / 3.0 if k > 0 else c
		# Men stand everywhere out to the field's edge: none of it may be water.
		if not terrain.is_land(q.x, q.z):
			return INF
		var rise := absf(terrain.height_at(q.x, q.z) - c.y)
		var tile: Vector2i = terrain.tile_of(q)
		var kind := String(terrain.tile_at(tile.x, tile.y))
		# A mountainside is never a battlefield: the lines can't stand on it.
		if rise > FIELD_RISE or kind == "Mountains" or kind == "Glacier":
			return INF
		cost += rise * 30.0
		cost += float(ROUGH_GROUND.get(kind, 0.0))
		if roads and roads.on_path(q, 0.05):
			cost += 3.0
	return cost


## Six men leave the camp behind their raised shields, run the last stretch,
## fight at the foot of the walls and fall back, leaving a man or two there.
## The camp sends a fresh man in each one's place before the next rush.
func _assault(arc: Callable, a: float, camp_r: float, wall: float) -> Array:
	var men := []
	for i in 6:
		var off := (i - 2.5) * 0.06
		var home: Vector3 = arc.call(a + off, camp_r - 0.35)
		men.append({"home": home, "foot": arc.call(a + off, wall + 0.12), "alive": true, "kit": "sword", "rank": 1})
	return men  # army_assault.gd raises the men and runs them


## Re-skins a bright toy-kit model in weathered timber, like the town's beams.
func _weather(n: Node3D) -> void:
	if _timber == null:
		_timber = StandardMaterial3D.new()
		_timber.albedo_texture = load("res://assets/village/T_WoodTrim_BaseColor.png")
		_timber.normal_enabled = true
		_timber.normal_texture = load("res://assets/village/T_WoodTrim_Normal.png")
		_timber.uv1_triplanar = true
		_timber.uv1_world_triplanar = true
		_timber.uv1_scale = Vector3.ONE * 3.0
		_timber.albedo_color = Color(0.62, 0.5, 0.4)
		_timber.roughness = 0.95
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = _timber


## Scales an imported model so it stands `height` tall, feet on the ground.
func _fit(n: Node3D, height: float) -> void:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first and box.size.y > 0.0:
		n.scale = Vector3.ONE * (height / box.size.y)


## Breaks a camp up once the host has moved on.
## Freeciv's assault on the siege of town `id` (the storm scene; the shot harness's --siege=taken|held): its parties
## and massed host storm, and it ends as Freeciv decided (army_assault.gd storm). A siege still being pitched (its
## town not up yet) storms once it stands.
func storm(id: int, taken: bool) -> void:
	var s: Dictionary = _sieges.get(id, {})
	if s.is_empty():
		return
	var a = s.get("assault")
	if a != null and is_instance_valid(a):
		a.storm(taken)
	else:
		get_tree().create_timer(1.0).timeout.connect(storm.bind(id, taken))


func _siege_watch(id: int) -> void:
	var t := Timer.new()
	t.wait_time = 2.0
	t.autostart = true
	t.timeout.connect(func():
		if not _sieges.has(id):
			return
		var s: Dictionary = _sieges[id]
		if Time.get_ticks_msec() / 1000.0 > s["until"]:
			_sieges.erase(id)
			if is_instance_valid(s["root"]):
				s["root"].queue_free())
	_sieges[id]["root"].add_child(t)


# --- fire, smoke and flight ---------------------------------------------------------

func _puffs(color: Color, amount: int, life: float, smin: float, smax: float, additive := false) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 18
	p.initial_velocity_min = 0.2
	p.initial_velocity_max = 0.45
	p.gravity = Vector3(0.03, 0.04, 0)
	p.scale_amount_min = smin
	p.scale_amount_max = smax
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.8))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.5, 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if additive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.mesh = q
	return p


func _burn(at: Vector3, seconds: float, scale := 1.0) -> void:
	if Fire.ignite(at, seconds, scale > 1.0):
		return  # fire v2 (fire.gd): the town's houses burn, and stand burnt while the realm says so
	var root := Node3D.new()
	root.name = "Burn"
	add_child(root)
	var r := _rng(at)
	for i in int(5 * scale):
		var off := Vector3(r.randf_range(-1.2, 1.2), 0, r.randf_range(-1.2, 1.2)) * scale
		var p := ground(at + off)
		# Flames and smoke are unshaded: they give the fire's light, they don't
		# take it. Shaded, the big smoke puffs inside the fire's own light were lit
		# bright orange and read as glowing balls over a stormed town (review v14,
		# Stormwatch); additive fire blooms into white orbs at this scale.
		var fire := _puffs(Color(1.0, 0.45, 0.1, 0.85), 18, 0.7, 0.05, 0.12)
		fire.initial_velocity_min = 0.15
		fire.initial_velocity_max = 0.35
		fire.position = p + Vector3(0, 0.2, 0)
		(fire.mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(Particles.to_gpu(fire))
		var smoke := _puffs(Color(0.12, 0.11, 0.1, 0.75), 30, 6.0, 0.3, 0.8)
		smoke.position = p + Vector3(0, 0.6, 0)
		(smoke.mesh.material as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		root.add_child(Particles.to_gpu(smoke))
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.2)
		light.light_energy = 0.6
		light.omni_range = 1.0
		light.position = p + Vector3(0, 0.4, 0)
		root.add_child(light)
	var tw := create_tween()
	tw.tween_interval(seconds)
	tw.tween_callback(func():
		for c in root.get_children():
			if c is CPUParticles3D or c is GPUParticles3D:  # the flames are GPU particles (Particles.to_gpu): they die down too
				c.emitting = false
			elif c is OmniLight3D:
				c.queue_free())
	tw.tween_interval(8.0)
	tw.tween_callback(root.queue_free)


func _refugees(at: Vector3, count: int) -> void:
	var r := _rng(at)
	# Flee toward land: try directions until one leads somewhere walkable.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 5.5
		if terrain.is_land(probe.x, probe.z):
			break
		ang += TAU / 12.0
	for i in count:
		var f: Node3D = people.make(r, "peasant", Color(0.75, 0.72, 0.68))
		var start := at + Vector3(cos(ang), 0, sin(ang)) * (2.0 + i * 0.12) + Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))
		var goal := start + Vector3(cos(ang), 0, sin(ang)) * 4.0
		add_child(f)
		f.look_at_from_position(stand(start), ground(goal) + Vector3(0, ground(start).y - terrain.height_at(goal.x, goal.z), 0), Vector3.UP)
		f.rotate_y(PI)
		# Some flee at a run, the rest trudge with what they could carry.
		var running := i % 3 == 0
		people.play(f, "Running" if running else "Walk", 1.0 if running else 0.7)
		_walk(f, goal, 14.0 if running else 30.0, true)


func _walk(n: Node3D, goal: Vector3, seconds: float, fade: bool) -> void:
	var route: PackedVector3Array = _route(n.position, goal)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(n):
			return
		var p: Vector3 = terrain.along(route, t)
		if not terrain.is_land(p.x, p.z):
			return  # never step into water; stop at the shore
		n.position = stand(p), 0.0, 1.0, seconds)
	if fade:
		tw.tween_callback(n.queue_free)


## A host musters at its seat and marches out along the roads to where it is sent (READY.md line 3; casebook, War
## and sieges: "The march feeds the battle"): the army layer's host (army.gd), formed in line by the seat, then out
## in column by each regiment's Mover (march_out). The crown's largest host as the realm reports it (new levies of
## march.men when it has none in the field); a rising's muster, its house's men in its colours and arms.
func _muster(s: Dictionary, at: Vector3, houses: Dictionary) -> void:
	var house: Dictionary = houses.get(int(s.get("owner", -1)), {})
	var host := {"side": 0, "seat": int(s.get("city", -1)), "shape": "line", "quiet": true,
		"out_to": terrain.world_pos(float(s.get("tx", s["x"])), float(s.get("ty", s["y"])))}
	if not house.is_empty():
		host["house"] = house
		host["colour"] = Heraldry.colour(house, Color(0.5, 0.17, 0.15))
	get_parent().add_child(Army.new(get_parent(), 0, host))
	framing.emit(ground(at), 2.6, 0.0)


## A royal rider carries the King's ruling to the petitioner's seat on a
## horse, the crown's standard in hand, with what was decided written above
## him. He sets off at a walk, rides the road at a gallop and draws up at a walk.
## Returns the horse, to follow. `s`: the scene, reported back on arrival.
func _rider(from: Vector3, to: Vector3, label: String, s := {}) -> Node3D:
	var r := _rng(to)
	var horse: Node3D = Horse.new(r.randi() % Horse.COATS.size())
	add_child(horse)
	horse.position = stand(from, HORSE_BODY)
	var rider: Node3D = people.make(r, "soldier", Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.3), "adult")
	horse.mount(rider)
	carried_standard(rider, {"name": "The Crown", "crown": true}, Color(0.72, 0.13, 0.16))
	var tag := _caption(self, label, ground(from) + Vector3(0, 0.45, 0))
	var road: Curve3D = terrain.smooth_road(_route(from, to))
	var length: float = maxf(road.get_baked_length(), 0.01)
	# Eased in and out, the pace peaks at about pi/2 the average: a gallop
	# (horse.gd) over the open road, a walk at either end.
	var secs := clampf(length / (Horse.GALLOP * 0.63), 8.0, 90.0)
	var last_y := [INF]  # the horse's height eases over the ground's bumps
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var d := t * length
		var g := road.sample_baked(d)
		var p := stand(g, HORSE_BODY)
		# Eased, so the ground's bumps and a nudge clear of a wall are glides, not jumps.
		if last_y[0] != INF:
			var x := lerpf(horse.position.x, p.x, 0.35)
			var z := lerpf(horse.position.z, p.z, 0.35)
			# The ground under where the horse really is: it glides down over a
			# bump, but going uphill it never sinks into the slope.
			var under: float = stand(Vector3(x, p.y, z), HORSE_BODY).y
			p = Vector3(x, maxf(lerpf(last_y[0], under, 0.25), under), z)
		last_y[0] = p.y
		# It steers toward a point a little way down the road, gently.
		var ahead := road.sample_baked(minf(length, d + 0.25))
		if Vector2(ahead.x - g.x, ahead.z - g.z).length() > 0.001:
			horse.rotation.y = lerp_angle(horse.rotation.y, atan2(ahead.x - g.x, ahead.z - g.z), 0.12)
		horse.position = p
		_place_tag(tag, p + Vector3(0, 0.45, 0)), 0.0, 1.0, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func(): if not s.is_empty(): arrived.emit(s))
	tw.tween_interval(3.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(func():
		horse.queue_free()
		tag.queue_free())
	return horse


# --- the King's convoys ------------------------------------------------------------------

## Returns the wagon, to follow. `scene`: the bridge's scene, reported back on arrival.
func _convoy(from: Vector3, to: Vector3, grain: bool, label := "", scene := {}) -> Node3D:
	var r := _rng(from)
	var root := Node3D.new()
	root.name = "Convoy"
	add_child(root)
	var wagon := MeshInstance3D.new()
	wagon.mesh = _wagon
	wagon.scale = Vector3.ONE * 0.12
	root.add_child(wagon)
	var crown_col := Color(0.72, 0.13, 0.16)
	var escort := []
	for i in 3:
		var s: Node3D = people.make(r, "soldier", crown_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		people.play(s, "Walk")
		escort.append(s)
	var road: Curve3D = terrain.smooth_road(_route(from, to))
	var length: float = maxf(road.get_baked_length(), 0.01)
	var seconds := clampf(length / 0.35, 12.0, 70.0)
	# No road joins the two towns and the way runs over the land: a cart track
	# through any wood it crosses, wide enough that no crown closes over it, so
	# what travels it can be watched (drawn roads have their lanes already).
	var along := 0.0
	while along < length:
		terrain.clear_around(road.sample_baked(along), 0.85)  # a crown reaches about 0.8 from its trunk (main.gd LANE_MARGIN)
		along += 0.4
	var tag := _caption(root, label if label != "" else ("The King's grain" if grain else "The King's gold"), ground(from) + Vector3(0, 0.45, 0))
	var heading := [INF]  # eased, so the wagon rounds a bend instead of snapping to it
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var d := t * length
		var g := road.sample_baked(d)
		var p := stand(g)
		var ahead := road.sample_baked(minf(length, d + 0.25))
		var flat := Vector3(ahead.x - g.x, 0, ahead.z - g.z)
		var dir := flat.normalized() if flat.length() > 0.001 else Vector3.FORWARD
		var want := atan2(dir.x, dir.z)
		heading[0] = want if heading[0] == INF else lerp_angle(heading[0], want, 0.12)
		dir = Vector3(sin(heading[0]), 0, cos(heading[0]))
		var side := Vector3(-dir.z, 0, dir.x)
		wagon.position = p
		wagon.rotation.y = heading[0] + PI
		_place_tag(tag, p + Vector3(0, 0.45, 0))
		for i in escort.size():
			var e: Node3D = escort[i]
			var trail := stand(road.sample_baked(maxf(0.0, d - (0.12 + i * 0.09))))
			e.position = trail + side * (0.05 if i % 2 == 0 else -0.05)
			e.rotation.y = heading[0], 0.0, 1.0, seconds)
	tw.tween_callback(func():
		# Arrived: the escort hails the town it was sent to.
		for e in escort:
			people.play(e, ["Waving", "Salute", "Cheering"][r.randi() % 3], r.randf_range(0.9, 1.1))
		if not scene.is_empty():
			arrived.emit(scene))
	tw.tween_interval(1.0)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
	return wagon


# --- feasts and handovers ----------------------------------------------------------

## A wedding feast in the town square: a fire, barrels broached, the town
## dancing in a ring around it and talking in knots at the edges.
func _feast(at: Vector3, house: Dictionary) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	root.name = "Feast"
	add_child(root)
	var centre := ground(at)
	# One feast, one fire, one ring of faces round it. When the town already
	# keeps a feast (town_life.gd's bonfire and revels), that's this feast's
	# fire and ring; the wedding brings its standard, casks and talk. Otherwise
	# its fire is the town's, put on the town's Life like town_life's, so the
	# town's people claim their places round it (villagers "feast") and keep
	# out of it, and its dancers stand outside its reach.
	var town: Array = TownNav.towns_at(towns, at)
	var town_root: Node3D = town[0][1] if not town.is_empty() else null
	var life: Node3D = town_root.get_node_or_null("Life") if town_root else null
	var lit: bool = life != null and not life.get_meta("fires", []).is_empty()
	var keep := TownLife.fire_reach()
	var added := {"fires": [], "standing": PackedVector2Array()}
	var local := func(p: Vector3) -> Vector2:
		return Vector2(p.x - town_root.global_position.x, p.z - town_root.global_position.z) if town_root else Vector2(p.x, p.z)
	# What the feast sets down on the ground (its fire pit, its casks) stands on the town's Life, so it is in the
	# town's way like any stall (nav_ground.gd reads it off); placed in world space, gone with the feast.
	var stands := Node3D.new()
	stands.name = "FeastStands"
	stands.top_level = true
	(life if life else root).add_child(stands)
	if not lit:
		var fire: Node3D = Realistic.make(Realistic.one("fire_pit"))
		if fire:
			fire.position = centre
			fire.scale = Vector3.ONE * TownLife.RING_SCALE  # the same stones as a town's own feast, and the same reach
			stands.add_child(fire)
		# A roasting fire: seen by day as its smoke, a thin grey column.
		# Thin and see-through, and drifting off on the air, so it never hides the
		# dancers round the fire.
		var flame := _puffs(Color(0.5, 0.48, 0.46, 0.22), 10, 3.5, 0.04, 0.09)
		flame.gravity = Vector3(0.12, 0.06, 0.05)
		flame.position = centre + Vector3(0, 0.08, 0)
		root.add_child(Particles.to_gpu(flame))
		var mid: Vector2 = local.call(centre)
		added["fires"].append([mid, keep])
	for i in 3:
		var cask: Node3D = Realistic.make(Realistic.one("cask"))
		if cask:
			var a := TAU * (0.1 + i * 0.07)
			cask.position = ground(at + Vector3(cos(a), 0, sin(a)) * 0.95)
			cask.rotation.y = r.randf() * TAU
			stands.add_child(cask)
	var col := Color.from_string(String(house.get("color", "#b08a4a")), Color(0.7, 0.55, 0.3))
	if not house.is_empty():
		_standard(root, at + Vector3(0.0, 0, -0.9), col, Vector3(0, 0, 1), house)
	# The ring of dancers, turning slowly about the fire, in their own village
	# clothes: the house shows in its standard, not on the dancers (in its
	# colours they read as two companies brawling).
	var ring := Node3D.new()
	ring.position = centre
	root.add_child(ring)
	var n := 0 if lit else 12  # the town's own revellers are this feast's ring when it keeps one
	for i in n:
		var a := TAU * i / n
		var f: Node3D = people.make(r, "peasant")
		ring.add_child(f)
		var p := Vector3(cos(a), 0, sin(a)) * (keep + 0.14)  # outside the fire's reach, and a step more
		f.position = stand(centre + p) - centre
		f.rotation.y = a + PI * 0.5
		# Most dance; between them some clap, laugh and wave the others on.
		var joy := ["Cheering", "Happy_Gesture", "Laughing", "Waving"]
		people.play(f, "Dance" if i % 3 != 0 else joy[r.randi() % joy.size()], r.randf_range(0.9, 1.1))
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 40.0).as_relative()
	# Knots of talkers at the edge of the square.
	for k in 3:
		var a := TAU * (0.35 + k * 0.22)
		var spot := at + Vector3(cos(a), 0, sin(a)) * 1.05
		for j in 3:
			var f: Node3D = people.make(r, "townsfolk")  # wedding guests in their village best, never a stranger's armour
			root.add_child(f)
			var off := Vector3(cos(j * 2.1), 0, sin(j * 2.1)) * 0.09
			f.position = stand(spot + off)
			f.rotation.y = atan2(-off.x, -off.z)
			people.play(f, "Idle_Talking")
			added["standing"].append(local.call(f.position))  # their places are taken
	# The town's Life holds what this feast put in its way, until the feast ends.
	if life:
		for k in added:
			life.set_meta(k, life.get_meta(k, [] if k != "standing" else PackedVector2Array()) + added[k])
		root.tree_exiting.connect(func():
			if is_instance_valid(stands):
				stands.queue_free()
			if not is_instance_valid(life):
				return
			for k in added:
				var kept = life.get_meta(k, [])
				var out = PackedVector2Array() if k == "standing" else []
				for e in kept:
					if not (k == "standing" and (added[k] as PackedVector2Array).has(e)) and not (k != "standing" and (added[k] as Array).has(e)):
						out.append(e)
				life.set_meta(k, out))
	var tag := _caption(root, "A wedding feast", centre + Vector3(0, 1.3, 0))
	_fade_out(root, 75.0, tag)


## A town changing hands by treaty or by its own will: the old lord's banner
## comes down, a file of the new lord's men marches in, and his goes up.
func _handover(at: Vector3, old_house: Dictionary, new_house: Dictionary, town: String) -> void:
	var r := _rng(at)
	# Only the latest hand a town passes into is told: an older ceremony there goes.
	for old in get_children():
		if old.has_meta("handover") and String(old.get_meta("handover")) == town:
			old.queue_free()
	var root := Node3D.new()
	root.name = "Handover"
	root.set_meta("handover", town)
	add_child(root)
	var old_col := Color.from_string(String(old_house.get("color", "#777")), Color.GRAY)
	var new_col := Color.from_string(String(new_house.get("color", "#ccc")), Color.WHITE)
	var spot := stand(at + Vector3(0.35, 0, -0.35))  # on dry ground, clear of the houses (a riverside town's diagonal can be the river)
	var old_b := _standard(root, spot, old_col, Vector3(0, 0, 1), old_house)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_callback(_drop_banner.bind(old_b))
	# The new lord's men come up the road from outside the walls.
	var ang := r.randf() * TAU
	for tries in 12:
		var probe := at + Vector3(cos(ang), 0, sin(ang)) * 4.0
		if terrain.is_land(probe.x, probe.z):
			break
		ang += TAU / 12.0
	var dir := Vector3(cos(ang), 0, sin(ang))
	var side := Vector3(-dir.z, 0, dir.x)
	var escort := []
	for i in 6:
		var s: Node3D = people.make(r, "soldier", new_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		escort.append(s)
		var start := at + dir * (4.0 + (i / 2) * 0.22) + side * ((i % 2) * 0.16 - 0.08)
		var goal := spot + dir * (0.35 + (i / 2) * 0.16) + side * ((i % 2) * 0.16 - 0.08)
		s.position = stand(start)
		s.rotation.y = atan2(-dir.x, -dir.z)
		people.play(s, "Walk")
		var mt := s.create_tween()
		# Up the realm's own way in (town_nav: streets, roads, over dry land), never a straight line over a river.
		var way := _route(s.position, goal)
		if way.size() < 2:
			way = PackedVector3Array([s.position, goal])
		mt.tween_method(func(k: float): s.position = stand(terrain.along(way, k)), 0.0, 1.0, 14.0)
		mt.tween_callback(people.play.bind(s, "Sword_Idle", 1.0))
	tw.tween_interval(13.0)
	tw.tween_callback(func():
		var b := _standard(root, spot + Vector3(0.12, 0, 0), new_col, Vector3(0, 0, 1), new_house)
		b.scale = Vector3(1, 0.05, 1)
		b.create_tween().tween_property(b, "scale", Vector3.ONE, 2.5).set_ease(Tween.EASE_OUT)
		# As it goes up the new lord's men salute it and cheer, each in his own
		# time and way.
		for s in escort:
			var st: Tween = s.create_tween()
			st.tween_interval(r.randf_range(0.8, 2.2))
			st.tween_callback(func(): people.play(s, ["Salute", "Cheering", "Battlecry", "Cheering"][r.randi() % 4], r.randf_range(0.9, 1.1))))
	# Out on the road the new lord's men came in by, not over the town in the middle of the view.
	var tag := _caption(root, "%s passes to %s" % [town, String(new_house.get("name", "a new lord"))], ground(spot + dir * 2.2) + Vector3(0, 0.5, 0))
	_fade_out(root, 60.0, tag)


## Captions in the world now, oldest first: a new one near an older one goes a
## line above it, so two never print over each other.
var _tags: Array[Label3D] = []
const LINE := 0.17  # one caption's height, in world units
const NEAR := 0.8  # captions closer than this (across the ground) share a place


## A caption over the world: what a scene is, or what a rider carries. `root`
## must sit at the world's origin (the scene roots and this node do).
func _caption(root: Node3D, text: String, at: Vector3) -> Label3D:
	var tag := Label3D.new()
	tag.visibility_range_begin = 1.6  # gone when you're walking right past it
	tag.text = text
	tag.font_size = 30
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true  # read whole: a roof in front never cuts a caption mid-word
	tag.render_priority = 10
	tag.modulate = Color(0.95, 0.85, 0.6)
	root.add_child(tag)
	# One caption to a place: an older one nearby fades as this one comes.
	for o in _tags.duplicate():
		if is_instance_valid(o) and o.visible and Vector2(o.position.x - at.x, o.position.z - at.z).length() < NEAR:
			_fade_tag(o, 0.4)
	_tags.append(tag)
	tag.tree_exiting.connect(func(): _tags.erase(tag))
	_place_tag(tag, at)
	# Every caption has a lifetime, like combat text: read, then gone.
	get_tree().create_timer(9.0).timeout.connect(func(): _fade_tag(tag, 1.0))
	return tag


func _fade_tag(tag: Label3D, seconds: float) -> void:
	if not is_instance_valid(tag) or not tag.visible:
		return
	var tw := tag.create_tween()
	tw.tween_property(tag, "modulate:a", 0.0, seconds)
	tw.tween_callback(func(): tag.visible = false)


## Sets a caption at `at`, lifted a line for each older caption in the same place.
func _place_tag(tag: Label3D, at: Vector3) -> void:
	var lift := 0
	for o in _tags:
		if o == tag:
			break
		var p: Vector3 = o.get_meta("at", o.position)
		if Vector2(p.x - at.x, p.z - at.z).length() < NEAR:
			lift += 1
	tag.set_meta("at", at)
	tag.position = at + Vector3(0, lift * LINE, 0)


## The caption fades after `seconds`, and the scene it names ends with it: the
## whole of `root` (the feast's tables, the handover's standards) is freed.
func _fade_out(root: Node3D, seconds: float, tag: Label3D) -> void:
	var tw := root.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
