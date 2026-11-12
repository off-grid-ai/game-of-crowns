extends RefCounted
## The bailey lived in (Mac on Kingsmere's castle from above, 2026-11-12: "the emptiness looks kinda weird", two
## people in an empty yard; 01-town and Stronghold's castle yard): men drilling in lines in the training yard, cutting
## and thrusting together; archers loosing at the butts; guards standing either side of the gate inside it and more
## on the walks; grooms leading horses to and from the stables corner; servants carrying firewood and water between
## the well, the stores and the keep's steps; the castle's smith at his anvil; and a cart drawn up at the stores,
## unloaded by two men. 20-40 figures, every one of them busy. Placed in the castle's own frame (metres, the gate on
## +Z, the keep at the back: castle_builder.gd), kept clear of the carpet up the middle. castle_life.gd calls dress()
## once a castle is up; everything made is listed in its nodes, so it goes when the castle does.
## Knobs: realm/data/castle_folk.json. Switch: --castle-folk=off, or castle_folk.json on.

const Data := preload("res://scripts/data.gd")
const People := preload("res://scripts/people.gd")
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const PROPS := "res://assets/props/%s.gltf"


static func on() -> bool:
	if OS.get_cmdline_user_args().has("--castle-folk=off"):
		return false
	return bool(Data.value("castle_folk", "on", true)) or OS.get_cmdline_user_args().has("--castle-folk=on")


## Peoples the bailey of the castle framed by `xf` (castle metres to the world), built to `sp` (castle_builder's spec).
## `host`: the node that holds them (castle_life); `d`: its record of what it made (d["nodes"]).
static func dress(host: Node, main: Node, xf: Transform3D, sp: Dictionary, colour: Color, d: Dictionary) -> void:
	if not on():
		return
	var K: Dictionary = Data.read("castle_folk")
	var rng := RandomNumberGenerator.new()
	rng.seed = int(K.get("seed", 77))
	var people: Object = main.scenes.people
	var hx := int(sp.get("w", 18)) * 2.0 / 2.0
	var hz := int(sp.get("d", 16)) * 2.0 / 2.0
	var cloth := colour.lerp(Color.WHITE, float(K.get("lighten", 0.2)))
	# Where things stand, as shares of the bailey's half-width (x) and half-depth (z): -z the keep, +z the gate.
	var at := func(fx: float, fz: float) -> Vector3:
		var w: Vector3 = xf * Vector3(fx * hx, 0, fz * hz)
		w.y = main.terrain.height_at(w.x, w.z)
		return w
	var face := func(n: Node3D, toward: Vector3) -> void:
		var dir := toward - n.global_position
		n.rotation.y = atan2(dir.x, dir.z)
	var put := func(n: Node3D, p: Vector3) -> Node3D:
		host.add_child(n)
		n.global_position = p
		d["nodes"].append(n)
		return n

	# The training yard: lines of men facing their sergeant, cutting together; every few seconds the drill changes.
	var Dr: Dictionary = K.get("drill", {})
	var lines := int(Dr.get("lines", 3))
	var per := int(Dr.get("per_line", 5))
	var yard: Array = Dr.get("at", [-0.55, 0.25])
	var gap: Array = Dr.get("gap", [0.11, 0.13])  # across, between lines (shares)
	var sergeant_at: Vector3 = at.call(float(yard[0]) + 0.32, float(yard[1]))
	var drillers: Array = []
	for l in lines:
		for i in per:
			var p: Vector3 = at.call(float(yard[0]) - l * float(gap[0]), float(yard[1]) + (i - (per - 1) * 0.5) * float(gap[1]))
			var f: Node3D = put.call(people.make(rng, "soldier", cloth, "adult"), p)
			main.scenes.arm(f, "sword" if l % 2 == 0 else "spear")
			face.call(f, sergeant_at)
			drillers.append(f)
	var sergeant: Node3D = put.call(people.make(rng, "soldier", cloth, "adult"), sergeant_at)
	face.call(sergeant, at.call(float(yard[0]) - 0.3, float(yard[1])))
	People.play(sergeant, "Yelling")
	var drills: Array = Dr.get("moves", ["SS_Slash_1", "Spear_Thrust", "SS_Slash_4", "SS_Attack_4"])
	var beat := Timer.new()
	beat.wait_time = float(Dr.get("every", 6.0))
	beat.autostart = true
	host.add_child(beat)
	d["nodes"].append(beat)
	var turn := [0]
	var drill_now := func() -> void:
		var clip := String(drills[turn[0] % drills.size()])
		turn[0] += 1
		for f in drillers:
			if is_instance_valid(f):
				People.repeat(f, clip)
		if is_instance_valid(sergeant):
			People.play(sergeant, ["Yelling", "Pointing_Forward", "Sword_Idle"][turn[0] % 3])
	beat.timeout.connect(drill_now)
	drill_now.call()

	# The butts: archers in a line loosing at shields propped on barrels across the yard.
	var Ar: Dictionary = K.get("archers", {})
	var line_at: Array = Ar.get("at", [0.6, 0.45])
	var butts_at: Array = Ar.get("butts", [0.6, -0.15])
	var n_arch := int(Ar.get("count", 5))
	for i in int(Ar.get("butts_count", 3)):
		var bp: Vector3 = at.call(float(butts_at[0]) + (i - 1) * 0.12, float(butts_at[1]))
		# A straw archery target on its stand (castle_folk.json archers.butt: [model, size, turn]); a shield on a
		# barrel where that model isn't on hand.
		var B: Array = Ar.get("butt", [])
		var butt := _prop(String(B[0]), float(B[1])) if B.size() >= 2 else null
		if butt:
			put.call(butt, bp)
			face.call(butt, at.call(float(line_at[0]), float(line_at[1])))
			butt.rotation.y += deg_to_rad(float(B[2]) if B.size() > 2 else 0.0)
			continue
		var barrel := _prop("Barrel", 1.0)
		if barrel:
			put.call(barrel, bp)
			var target := _prop("Shield_Wooden", 1.4)
			if target:
				put.call(target, bp + Vector3(0, 0.1, 0))
				face.call(target, at.call(float(line_at[0]), float(line_at[1])))
	for i in n_arch:
		var p: Vector3 = at.call(float(line_at[0]) + (i - (n_arch - 1) * 0.5) * 0.08, float(line_at[1]))
		var f: Node3D = put.call(people.make(rng, "soldier", cloth, "adult"), p)
		main.scenes.arm(f, "bow")
		face.call(f, at.call(float(butts_at[0]), float(butts_at[1])))
		var tw := f.create_tween().set_loops()
		tw.tween_interval(rng.randf_range(0.0, 2.5))  # each on his own breath
		for clip in ["Bow_Draw", "Bow_Aim", "Bow_Shoot", "Bow_Idle"]:
			tw.tween_callback(func(): People.play(f, clip))
			tw.tween_interval(float((Ar.get("beat", {}) as Dictionary).get(clip, 1.2)))

	# The gate from inside: a guard either side, spears grounded, watching the yard.
	var Gt: Dictionary = K.get("gate", {})
	for sx in [-1.0, 1.0]:
		for j in int(Gt.get("per_side", 1)):
			var p: Vector3 = at.call(sx * (float(Gt.get("out", 0.16)) + j * 0.06), float(Gt.get("z", 0.86)))
			var g: Node3D = put.call(people.make(rng, "soldier", cloth, "adult"), p)
			main.scenes.arm(g, "spear")
			face.call(g, at.call(0.0, 0.0))
			People.play(g, "Sword_Idle")

	# The castle's smith at his anvil by the stores, his helper at the barrel.
	var Sm: Dictionary = K.get("smith", {})
	var sa: Array = Sm.get("at", [-0.82, -0.45])
	var anvil_at: Vector3 = at.call(float(sa[0]), float(sa[1]))
	var anvil := _prop("Anvil", 1.0)
	if anvil:
		put.call(anvil, anvil_at)
	var smith: Node3D = put.call(people.make(rng, "townsfolk", Color.WHITE, "adult", "", "male"), anvil_at + (xf.basis * Vector3(1, 0, 0)).normalized() * 0.16)
	face.call(smith, anvil_at)
	People.repeat(smith, "Hammer_Swing")
	var helper: Node3D = put.call(people.make(rng, "peasant", Color.WHITE, "young", "", "male"), anvil_at + (xf.basis * Vector3(0, 0, 1)).normalized() * 0.2)
	face.call(helper, anvil_at)
	People.repeat(helper, "Pushing")  # at the bellows

	# A groom warming himself at the yard's fire: towns.gd's bailey dressing lays the fire pit (its BAILEY row, in the
	# bailey's frame: the castle's place and turn, game units); he stands off it (castle_folk.json fire_groom), facing it.
	var Fg: Dictionary = K.get("fire_groom", {})
	for row in (load("res://scripts/towns.gd").BAILEY as Array):
		if Fg.is_empty() or String(row[0]) != "ph/stone_fire_pit":
			continue
		var frame := xf.basis.orthonormalized()
		var fire: Vector3 = xf.origin + frame * Vector3(row[1])
		var by: Array = Fg.get("by", [0.25, 0.25])
		var gp: Vector3 = fire + frame * Vector3(float(by[0]), 0, float(by[1]))
		gp.y = main.terrain.height_at(gp.x, gp.z)
		var groom: Node3D = put.call(people.make(rng, String(Fg.get("kind", "peasant")), Color.WHITE, "adult", "", "male"), gp)
		face.call(groom, Vector3(fire.x, gp.y, fire.z))
		People.play(groom, String(Fg.get("clip", "Idle")))
		break

	# The stores: crates, barrels and sacks against the wall by the keep, a horse and cart drawn up, two men unloading.
	var St: Dictionary = K.get("stores", {})
	var sto: Array = St.get("at", [0.78, -0.55])
	var stores_at: Vector3 = at.call(float(sto[0]), float(sto[1]))
	var goods := ["Crate_Wooden", "Barrel", "Bag", "Crate_Wooden", "Barrel_Apples", "Bag"]
	for i in goods.size():
		var g := _prop(goods[i], 1.0)
		if g:
			put.call(g, stores_at + xf.basis * Vector3((i % 3) * 1.1 - 1.1, 0, (i / 3) * 1.0))
			g.rotation.y = rng.randf() * TAU
	var Town := load("res://scripts/town_life.gd")
	var cart: Node3D = Town.horse_cart(people, rng)
	if cart:
		var cp: Vector3 = at.call(float(sto[0]) - 0.2, float(sto[1]) + 0.28)
		put.call(cart, cp)
		face.call(cart, cp + (xf.basis * Vector3(0, 0, -1)))
		var carter: Variant = cart.get_meta("carter", null)
		if carter is Node3D:
			People.play(carter, "Idle_Talking")
		for i in 2:
			var u: Node3D = put.call(people.make(rng, "peasant", Color.WHITE, "adult", "", "male"), cp.lerp(stores_at, 0.35 + 0.3 * i))
			_shuttle(u, cp, stores_at, "Box_Walk", rng, float(St.get("pace", 0.18)), i * 1.5)

	# Servants: water from the well to the keep's steps, firewood from the stores to the kitchen door; and back.
	var Sv: Dictionary = K.get("servants", {})
	var well_at: Vector3 = at.call(float((Sv.get("well", [0.1, 0.0]) as Array)[0]), float((Sv.get("well", [0.1, 0.0]) as Array)[1]))
	var keep_foot: Vector3 = at.call(float((Sv.get("keep", [0.18, -0.35]) as Array)[0]), float((Sv.get("keep", [0.18, -0.35]) as Array)[1]))
	for i in int(Sv.get("count", 4)):
		var water := i % 2 == 0
		var a: Vector3 = well_at if water else stores_at
		var b: Vector3 = keep_foot + xf.basis * Vector3((i - 1.5) * 1.2, 0, 0)
		var s: Node3D = put.call(people.make(rng, "peasant", Color.WHITE, "adult", "", "female" if water else "male"), a.lerp(b, rng.randf()))
		_shuttle(s, a, b, "Carrying" if water else "Box_Walk", rng, float(Sv.get("pace", 0.17)), i * 2.0)

	# Grooms leading horses between the gate and the stables corner.
	var Gr: Dictionary = K.get("grooms", {})
	var stable_at: Vector3 = at.call(float((Gr.get("stables", [-0.82, 0.62]) as Array)[0]), float((Gr.get("stables", [-0.82, 0.62]) as Array)[1]))
	var gate_in: Vector3 = at.call(-0.18, 0.8)
	var Horse := load("res://scripts/horse.gd")
	for i in int(Gr.get("count", 2)):
		var groom: Node3D = put.call(people.make(rng, "peasant", Color.WHITE, "adult", "", "male"), stable_at.lerp(gate_in, 0.3 * i))
		var horse: Node3D = Horse.new(rng.randi() % 5)
		host.add_child(horse)
		d["nodes"].append(horse)
		_shuttle(groom, stable_at, gate_in, "Walk", rng, float(Gr.get("pace", 0.15)), i * 4.0, horse)


static func _prop(name: String, size: float) -> Node3D:
	# "kit/model" names a kit in dressing.json kits (yard/archery_target); a bare name is the props kit's.
	var path: String = PROPS % name
	if name.contains("/"):
		var kit: Array = (Data.value("dressing", "kits", {}) as Dictionary).get(name.get_slice("/", 0), [PROPS])
		path = String(kit[0]) % name.get_slice("/", 1)
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = (load(path) as PackedScene).instantiate()
	n.scale = Vector3.ONE * 0.12 * size * float(Data.num("people", "readable", 1.0)) * float(Data.num("castle_folk", "props", 1.0))
	return n


## Back and forth between a and b, carrying `clip`'s load (the arms keep it over the walking legs), setting it
## down at each end a while. `led`: a horse led at their side. Walked with the Mover, as every round in the castle is
## (castle_life.rounds; CLAUDE.md, one way to move): the body's holder is the castle's life.
static func _shuttle(f: Node3D, a: Vector3, b: Vector3, clip: String, rng: RandomNumberGenerator, pace: float, delay: float, led: Node3D = null) -> void:
	var m: Node = Mover.of(f)
	m.speed = maxf(pace * float(Data.num("people", "readable", 1.0)), 0.01)
	m.clip = clip
	var rest := ["PickUp_Table"] if clip != "Walk" else ["Idle"]
	if led:  # stood at their side to begin with (castle_life.LED_SIDE), facing the way they first go
		var way := b - f.global_position
		led.global_position = f.global_position + Basis(Vector3.UP, atan2(way.x, way.z)) * preload("res://scripts/castle_life.gd").LED_SIDE * float(Data.num("people", "readable", 1.0))
		led.rotation.y = atan2(way.x, way.z)
	(f.get_parent() as Object).rounds(f, [PackedVector3Array([b]), PackedVector3Array([a])], [[2.0, 5.0]], delay + rng.randf_range(0.0, 2.0), 0, rest, led)
