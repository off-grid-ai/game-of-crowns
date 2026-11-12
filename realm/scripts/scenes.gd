extends Node3D
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Particles := preload("res://scripts/particles.gd")  # smoke and fire on the GPU
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
const SceneKinds := preload("res://scripts/scene_kinds.gd")
var _seen := {}  # scene key -> true, so each event plays once
var _kinds := {}  # a kind's class path (scene_kinds.gd "play") -> its one instance (scene_kind.gd): kinds sharing a class share it


## The class that stages a kind of scene (scene_kinds.gd KINDS row "play"), or null for a kind still played here.
func kind(name_: String) -> RefCounted:
	var path := String(SceneKinds.of(name_).get("play", ""))
	if path == "":
		return null
	if not _kinds.has(path):
		_kinds[path] = load(path).new(self)  # one of each: a storm finds the siege its siege kind pitched
	return _kinds[path]
var wagon_mesh: Mesh  # the convoys' and carts' wagon (house_builder Prop_Wagon)
var _timber: StandardMaterial3D


func _ready() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	wagon_mesh = builder.piece_mesh("Prop_Wagon")


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


## Plays each scene the bridge reports once, by its kind's own class (scene_kinds.gd "play"; scene_kinds/), and
## tells who listens what it staged and what to follow. A kind with no class (a raid, a fire, a vigil) is news only.
func sync(houses: Dictionary) -> void:
	var store: Node = Awareness.store()
	if not _towns_up():
		get_tree().create_timer(1.0).timeout.connect(sync.bind(houses))
		return
	for s in store.rec("scenes", []):
		var key := "%s:%d:%d:%d:%d" % [s["kind"], int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]
		if _seen.has(key):
			continue
		_seen[key] = true
		var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
		var follow: Node3D = null
		var player = kind(String(s["kind"]))
		if player:
			follow = player.play(s, at, houses)
		staged.emit(s, follow)


# --- the roads alive: carters and pedlars between the King's moments ---------------


## A rider on the road from one town to another, given back so what rides with
## him (a house's envoy plate, scheme_marks.gd) can follow; null when none can go.
func rider_on_road(from: Vector3, to: Vector3, on_done := Callable()) -> Node3D:
	var horse: Node3D = kind("rider").ride(from, to, "")
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
	var r := rng(from + Vector3(randf(), 0, randf()))
	# Only where there's a way: a straight line between two towns means no road
	# and no land joins them (it would cross the water).
	var way := route(from, to)
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
	return Mover.road(self, way, [[body, 0.0]], pace, {"name": "Traveller", "min": 15.0, "max": 90.0, "yields": true, "ahead": 0.16 if carter else 0.1}, on_done) != null


## One horse and cart, built as a single piece so its parts can never come
## apart: the wagon, a hitch where its shafts end, the horse between the shafts
## facing the way they point, and the carter at the horse's head. Its forward is
## -z, the way PathFollow3D carries it.
func _cart_rig(r: RandomNumberGenerator, carter: Node3D) -> Node3D:
	var rig := Node3D.new()
	rig.name = "Cart"
	var wagon := MeshInstance3D.new()
	wagon.mesh = wagon_mesh
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


func rng(at: Vector3) -> RandomNumberGenerator:
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
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
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


## Camera beats for whoever holds the camera (the director, or a shot):
## where to look, from how far, and from which side.
signal framing(pos: Vector3, dist: float, yaw: float)


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


## A standard planted behind a line or at a muster: a little taller than one carried.
const PLANTED := 0.45


func standard(root: Node3D, p: Vector3, color: Color, face: Vector3, house := {}) -> Node3D:
	var b: Node3D = Heraldry.standard(house, color, PLANTED)
	b.position = ground(p)
	b.rotation.y = atan2(face.x, face.z)
	root.add_child(b)
	return b


## A standard goes over: it sways, then topples backward from the line and
## lies on the field. `face` is the way its line faced.
func drop_banner(b: Node3D, face := Vector3.ZERO) -> void:
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
	var d := puffs(Color(0.58, 0.52, 0.42, 0.07), 8, 1.6, 0.04, 0.09)
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

## Whether a man could stand here: dry land, not a crag.
func _footing(p: Vector3) -> bool:
	if not terrain.is_land(p.x, p.z):
		return false
	return absf(terrain.height_at(p.x + 0.15, p.z) - terrain.height_at(p.x - 0.15, p.z)) < 0.12 and absf(terrain.height_at(p.x, p.z + 0.15) - terrain.height_at(p.x, p.z - 0.15)) < 0.12


static func _flat_gap(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


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


# --- fire, smoke and flight ---------------------------------------------------------

func puffs(color: Color, amount: int, life: float, smin: float, smax: float, additive := false) -> CPUParticles3D:
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


## Captions in the world now, oldest first: a new one near an older one goes a
## line above it, so two never print over each other.
var _tags: Array[Label3D] = []
const LINE := 0.17  # one caption's height, in world units
const NEAR := 0.8  # captions closer than this (across the ground) share a place


## A caption over the world: what a scene is, or what a rider carries. `root`
## must sit at the world's origin (the scene roots and this node do).
func caption(root: Node3D, text: String, at: Vector3) -> Label3D:
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
	place_tag(tag, at)
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
func place_tag(tag: Label3D, at: Vector3) -> void:
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
func fade_out(root: Node3D, seconds: float, tag: Label3D) -> void:
	var tw := root.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
