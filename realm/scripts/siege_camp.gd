extends Node3D
## The besiegers' camp and their engines (North Star docs/art/target/04-siege.jpg; Stronghold's and Age of
## Empires II's engines built on the spot and worked by their crews, Total War's camp; research rule 13: three
## rings read at a glance, the town and its wall, a band of open ground with the engines and the assault
## parties, the camp of tents and cook fires behind). scenes.gd pitches it for a siege when the switch is on.
##
## The camp: a palisade of stakes and planking in front of rows of tents in the besieger's colours, cook fires
## with men sat round them, the baggage wagons behind; a ram and a siege tower waiting in the band. The engines
## (Meshy's catapult) rise in a line in the band, ahead of the storm host, where they stand while carpenters hammer, then their crews work them: the arm
## drawn back, a stone loaded, the arm whips over and the stone flies on its arc to the wall, where it brings
## down the stones the town's wear has doomed (walls.gd aim/strike: the wear is the bridge's damage fact; the
## view decides nothing). The walls' archers shoot at the crews (scenes.gd's volleys, marks()).
##
## Made of blocks: Kenney's Castle Kit (CC0: the engines with their own arm nodes, the ram, the tower, the
## palisade), the realistic kit's wagons, barrels, crates and fire pits, fire.gd's flames. The tents are
## Godot's PrismMesh in the house's canvas: no tent model is on disk (Kenney's Survival Kit, CC0, has them).
## Knobs: data/siege.json. Pitched with every siege (scenes.gd _siege).

const Data := preload("res://scripts/data.gd")
const Real := preload("res://scripts/realistic.gd")
const Fire := preload("res://scripts/fire.gd")
const Particles := preload("res://scripts/particles.gd")
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md): the ram, the tower and their crews

var scenes: Node
var root: Node3D
var r: RandomNumberGenerator
var at: Vector3  # the town
var base := 0.0  # the camp's middle, as an angle round the town
var camp_r := 0.0  # where the companies stand
var col := Color.DARK_RED
var engines := []  # {node, arm, kind, crew: [marks], from, built}
var _crews := []  # every crewman as the walls' archers see him: {node, alive, rank, kit}
var _stone_mesh: SphereMesh
var _stone_mat: StandardMaterial3D
var _wood: Material
var _rolling := []  # the ram and the tower on their way to the wall: {node, kind, crew, to, from, t, beat, rolling, at_wall}


## The camp pitched for a siege of the town at `town`: `middle` the angle its middle stands at, `line` where
## its companies stand (world units from the town), `colour` the besieger's, `count` the bridge's engines.
func pitch(s: Node, siege: Node3D, town: Vector3, middle: float, line: float, colour: Color, count: int, rng: RandomNumberGenerator) -> void:
	scenes = s
	root = siege
	at = town
	base = middle
	camp_r = line
	col = colour
	r = rng
	name = "SiegeCamp"
	root.add_child(self)
	_palisade()
	_tents()
	_fires()
	_wagons()
	_parked()
	var k: Dictionary = Data.value("siege", "engines", {})
	var angles: Array = k.get("angles", [0.0])
	if OS.get_cmdline_user_args().has("--wall-demo"):
		count = angles.size()  # the demo's wall falls within a take: every engine at it
	for e in clampi(maxi(count, 1), 1, angles.size()):
		_engine(float(angles[e]), k)


## The camp's middle among its tents (world), for framing it.
func middle() -> Vector3:
	return _arc(0.0, camp_r + 0.6)


## The crews, for the walls' archers to shoot at (scenes.gd _arrows' marks).
func marks() -> Array:
	return _crews.filter(func(m): return m["alive"] and is_instance_valid(m["node"]))


func _arc(a: float, rad: float) -> Vector3:
	return scenes.ground(at + Vector3(cos(base + a), 0, sin(base + a)) * rad)


## Facing the town from `p`: the yaw that turns a model's +X toward it.
func _x_to_town(p: Vector3) -> float:
	var d := at - p
	return atan2(-d.z, d.x)


# --- the camp ------------------------------------------------------------------

## Stakes and planking in front of the tents, along the camp line, with gaps where the companies go out.
func _palisade() -> void:
	var k: Dictionary = Data.value("siege", "palisade", {})
	var rad := camp_r + float(k.get("at", 0.35))
	var w := float(k.get("width", 0.22))
	var span := float(k.get("span", 0.95))
	var gaps: Array = k.get("gaps", [])
	var half := float(k.get("gap_half", 0.09))
	var models: Array = Real.variants("palisade")
	var step := w / rad
	var a := -span
	var i := 0
	while a <= span:
		if not gaps.any(func(g): return absf(a - float(g)) < half):
			var p := _arc(a, rad)
			if scenes._footing(p):
				var piece: Node3D = load(Real.path_of("palisade", i % maxi(models.size(), 1))).instantiate()
				piece.scale = Vector3.ONE * w
				for mi in piece.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = _timber()  # the kit's palette read as flat salmon (batch 8b)
				piece.position = p
				var t := Vector3(-sin(base + a), 0, cos(base + a))  # along the line
				piece.rotation.y = atan2(-t.z, t.x) + r.randf_range(-0.05, 0.05)
				root.add_child(piece)
		a += step
		i += 1


## Rows of tents in the house's canvas behind the palisade, each turned along its row.
func _tents() -> void:
	var k: Dictionary = Data.value("siege", "tents", {})
	var sz: Array = k.get("size", [0.26, 0.2, 0.36])
	var span := float(k.get("span", 0.85))
	# Woven canvas (the props kit's banner cloth, laid on in triplanar): the house's own colour, only a little
	# toward linen (half toward cream read as salmon pink beside a red house, batch 8b), and plain linen.
	var canvas := _cloth(col.lerp(Color(0.9, 0.85, 0.72), float(k.get("canvas", 0.15))))
	var plain := _cloth(Color(0.82, 0.76, 0.62))
	var mesh := PrismMesh.new()
	mesh.size = Vector3(float(sz[0]), float(sz[1]), float(sz[2]))
	for row in k.get("rows", [0.75]):
		var rad := camp_r + float(row)
		var step := float(k.get("every", 0.38)) / rad
		var a := -span + r.randf_range(0.0, step * 0.5)
		var n := 0
		while a <= span:
			var p := _arc(a + r.randf_range(-0.02, 0.02), rad + r.randf_range(-0.06, 0.06))
			if scenes._footing(p):
				var t := MeshInstance3D.new()
				t.mesh = mesh
				t.material_override = canvas if n % 3 != 2 else plain  # the house's canvas, now and then plain
				t.position = p + Vector3(0, float(sz[1]) * 0.5, 0)
				t.rotation.y = -(base + a) + r.randf_range(-0.15, 0.15)  # ridge along the row
				root.add_child(t)
			a += step
			n += 1


## The village kit's timber (its fence's wood), laid on in triplanar: the palisade's stakes and planks.
func _timber() -> Material:
	if _wood == null:
		_wood = Real.dyed(null, {"like": "Prop_WoodenFence_Single", "triplanar": 0.9})
	return _wood


## The props kit's banner cloth in `c`, in triplanar (a woven canvas, not a flat colour).
func _cloth(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = null
	var path := "res://assets/props/Banner_1.gltf"
	if ResourceLoader.exists(path):
		var n: Node = (load(path) as PackedScene).instantiate()
		for mi in n.find_children("*", "MeshInstance3D", true, false):
			var msh: Mesh = (mi as MeshInstance3D).mesh
			for s in (msh.get_surface_count() if msh else 0):
				var src := (mi as MeshInstance3D).get_active_material(s)
				if src is StandardMaterial3D and String(src.resource_name) == "MI_Banner":
					m = (src as StandardMaterial3D).duplicate()
		n.free()
	if m == null:
		m = StandardMaterial3D.new()
	m.albedo_color = c
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 4.0
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Cook fires among the tents, flames and a pit, men sat round them.
func _fires() -> void:
	var k: Dictionary = Data.value("siege", "fires", {})
	var n := int(k.get("count", 4))
	var pit := Real.one("fire_pit")
	for i in n:
		var a := lerpf(-0.7, 0.7, (i + 0.5) / float(n)) + r.randf_range(-0.05, 0.05)
		var p := _arc(a, camp_r + float(k.get("at", 0.95)))
		if not scenes._footing(p):
			continue
		var model: Node3D = Real.make(pit) if pit != "" else null
		if model:
			model.position = p
			root.add_child(model)
		Fire.hearth(root, p)
		for j in int(k.get("sitters", 2)):
			var ang := r.randf() * TAU
			var q := p + Vector3(cos(ang), 0, sin(ang)) * 0.12
			var f: Node3D = scenes.people.make(r, "soldier", col, "adult")
			f.position = scenes.stand(q)
			f.rotation.y = atan2(p.x - q.x, p.z - q.z)
			root.add_child(f)
			scenes.people.play(f, ["Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged"][r.randi() % 3], r.randf_range(0.9, 1.1))


## The baggage behind the tents: wagons and carts, barrels and crates by them.
func _wagons() -> void:
	var k: Dictionary = Data.value("siege", "wagons", {})
	var n := int(k.get("count", 3))
	for i in n:
		var a := lerpf(-0.6, 0.6, (i + 0.5) / float(n)) + r.randf_range(-0.08, 0.08)
		var p := _arc(a, camp_r + float(k.get("at", 1.55)))
		if not scenes._footing(p):
			continue
		var w: Node3D = Real.make(Real.one("wagon" if i % 2 == 0 else "cart"))
		if w:
			w.position = p
			w.rotation.y = r.randf() * TAU
			root.add_child(w)
		for j in int(k.get("props", 4)) / n + 1:
			var c: Node3D = Real.make(Real.one(["barrel", "crate"][r.randi() % 2]))
			if c:
				c.position = scenes.ground(p + Vector3(r.randf_range(-0.25, 0.25), 0, r.randf_range(-0.25, 0.25)))
				c.rotation.y = r.randf() * TAU
				root.add_child(c)


## A ram and a siege tower waiting in the band, their men by them.
func _parked() -> void:
	var k: Dictionary = Data.value("siege", "parked", {})
	var kinds := ["siege_ram", "siege_tower"]
	var angles: Array = k.get("angles", [])
	for i in mini(angles.size(), kinds.size()):
		var p := _arc(float(angles[i]), camp_r - Data.num("siege", "band", 6.0) + float(k.get("from_wall", 1.1)))  # in the band, as the engines
		if not scenes._footing(p):
			continue
		var m: Node3D = load(Real.path_of(kinds[i])).instantiate()
		root.add_child(m)
		scenes._fit(m, float(k.get("height", 0.5)) * (1.6 if kinds[i] == "siege_tower" else 1.0))
		scenes._weather(m)
		m.position = p
		m.rotation.y = _x_to_town(p)
		var crew := []
		for j in int(k.get("crew", 2)):
			crew.append(_crewman(p + Vector3(r.randf_range(-0.2, 0.2), 0, r.randf_range(-0.2, 0.2)), ["Idle", "Looking_Around", "Weight_Shift"]))
		# Then pushed up to the wall (04-siege: the ram at the wall, the tower against it): after roll_after_s,
		# its crew behind it at pace, the ram to batter the wall's face, the tower to stand against it.
		var to: Vector3 = _wall_face(p, float(k.get("ram_out" if kinds[i] == "siege_ram" else "tower_out", 0.15)))
		if to != Vector3.INF:
			var go := {"node": m, "kind": kinds[i], "crew": crew, "from": p, "to": to, "t": -float(k.get("roll_after_s", 10.0)) - i * 4.0, "beat": 0.0}
			_rolling.append(go)


## The wall's outer face in front of `p`, `out` metres off it, on the ground (world), or INF (no wall).
func _wall_face(p: Vector3, out: float) -> Vector3:
	var walls: Node = Engine.get_meta("stone_walls") if Engine.has_meta("stone_walls") else null
	if walls == null or not walls.has_method("face_toward"):
		return Vector3.INF
	var f: Vector3 = walls.face_toward(p, out)
	return scenes.ground(f) if f != Vector3.INF else f


## The ram and the tower on their way: each goes to the wall by its Mover at the crew's pace (its route from the
## realm's navigation, its turning left to the camp's aim: the model faces the town on its x), its crew pushing
## behind by theirs; then the ram swings at the wall every blow_s, a blow and a burst of dust (walls.gd strike: a
## doomed stone falls to it), its crew heaving.
func _roll(dt: float) -> void:
	var k: Dictionary = Data.value("siege", "parked", {})
	for g in _rolling:
		var m: Node3D = g["node"]
		if not is_instance_valid(m):
			continue
		var t0 := float(g["t"])
		g["t"] = t0 + dt
		if float(g["t"]) < 0.0:
			continue
		var dir: Vector3 = (g["to"] - g["from"]).normalized()
		if not g.get("at_wall", false):
			var pace := float(k.get("pace", 0.12))
			if not g.get("rolling", false):
				g["rolling"] = true
				var mv := Mover.of(m)
				mv.speed = pace
				mv.clip = ""  # an engine: nothing to play
				mv.turn_rate = 0.0  # it keeps the camp's aim at the wall
				Mover.of(m).go(g["to"], func(): g["at_wall"] = true)
				for c in g["crew"]:
					if c["alive"] and is_instance_valid(c["node"]):
						Mover.of(c["node"]).clip = "Pushing"
			var j := 0
			for c in g["crew"]:
				if c["alive"] and is_instance_valid(c["node"]):
					var side := Vector3(-dir.z, 0, dir.x) * (0.12 * (j - 0.5))
					Mover.of(c["node"]).toward(m.global_position - dir * float(k.get("behind", 0.35)) + side, pace * 1.1, dir)
				j += 1
			if not g.get("at_wall", false):
				continue
		if not g.get("crew_still", false):  # at the wall: the crew stop pushing where they are
			g["crew_still"] = true
			for c in g["crew"]:
				if c["alive"] and is_instance_valid(c["node"]):
					Mover.of(c["node"]).stop()
		if g["kind"] != "siege_ram":
			if not g.get("there", false):
				g["there"] = true
				for c in g["crew"]:
					if c["alive"] and is_instance_valid(c["node"]):
						scenes.people.play(c["node"], "Cheering", 1.0)
			continue
		# The ram at the wall: drawn back and driven in, a blow at the end of each swing.
		g["beat"] = float(g["beat"]) + dt
		var blow := float(k.get("blow_s", 1.8))
		var b := fmod(float(g["beat"]), blow) / blow
		var back := float(k.get("swing", 0.08))
		var off := -back * smoothstep(0.0, 0.7, b) if b < 0.7 else -back * (1.0 - smoothstep(0.7, 0.8, b))
		m.global_position = scenes.ground(g["to"]) + dir * off
		var hit_now: bool = b >= 0.8 and not g.get("struck", false)
		if b < 0.8:
			g["struck"] = false
		if hit_now:
			g["struck"] = true
			var walls: Node = Engine.get_meta("stone_walls") if Engine.has_meta("stone_walls") else null
			var face: Vector3 = g["to"] + dir * float(k.get("ram_out", 0.15)) + Vector3(0, 0.12, 0)
			if walls and is_instance_valid(walls):
				walls.strike(face, dir)
			_puff(face, Color(0.55, 0.5, 0.42, 0.3), 1.0)
			for c in g["crew"]:
				if c["alive"] and is_instance_valid(c["node"]):
					scenes.people.play(c["node"], "Pushing", 1.2)


func _crewman(p: Vector3, idle: Array) -> Dictionary:
	var f: Node3D = scenes.people.make(r, "soldier", col, "adult")
	f.position = scenes.stand(p)
	f.rotation.y = atan2(at.x - p.x, at.z - p.z) + r.randf_range(-0.8, 0.8)
	root.add_child(f)
	scenes.people.play(f, idle[r.randi() % idle.size()], r.randf_range(0.9, 1.1))
	var m := {"node": f, "alive": true, "rank": 1, "kit": "", "engaged": false}
	_crews.append(m)
	return m


# --- the engines ---------------------------------------------------------------

## An engine raised where it will stand while carpenters hammer, then worked by its crew.
func _engine(a: float, k: Dictionary) -> void:
	# In the band, from_wall out from the wall's foot (the camp line is siege.json band out from it), ahead of the
	# storm host; where its own angle's ground isn't level, the nearest level ground a few steps along the arc or out
	# and in (near), never dropped (group test 1: of three engines one stood in frame).
	var rad := camp_r - Data.num("siege", "band", 6.0) + float(k.get("from_wall", 0.75))
	var p := _level_near(a, rad, k.get("near", [0.06, 0.25, 8]))
	if p == Vector3.INF:
		return
	var node: Node3D = load(Real.path_of("catapult")).instantiate()  # Meshy's catapult (data/meshy.json replaces the catapult)
	root.add_child(node)
	scenes._fit(node, float(k.get("height", 0.7)))
	scenes._weather(node)
	node.position = p
	node.rotation.y = _x_to_town(p)
	node.add_to_group("siege_engines")
	# Its arm, split out by the Meshy import: its own angles and tip (siege.json engines.kinds.catapult).
	var kk: Dictionary = (k.get("kinds", {}) as Dictionary).get("catapult", {})
	var arm: Node3D = node.find_child(String(kk.get("arm", "arm")), true, false)
	var e := {"node": node, "arm": arm, "kind": "catapult", "k": kk, "crew": [], "built": false}
	engines.append(e)
	var away: Vector3 = (p - at).normalized()
	away.y = 0.0
	var side := Vector3(-away.z, 0, away.x)
	for i in int(k.get("crew", 3)):
		e["crew"].append(_crewman(p + away * 0.22 + side * (i - 1) * 0.14, ["Hammer_Swing"]))
	# Rising where it stands (Age of Empires' building site), with dust as the timbers go up.
	var full := node.scale
	node.scale = Vector3(full.x, full.y * 0.05, full.z)
	var build := float(k.get("build_s", 12.0)) * r.randf_range(0.85, 1.15)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", full, build).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		e["built"] = true
		for m in e["crew"]:
			if m["alive"] and is_instance_valid(m["node"]):
				scenes.people.play(m["node"], "Cheering", 1.0)
		_cycle(e))
	var dust := Timer.new()
	dust.wait_time = 1.5
	dust.autostart = true
	node.add_child(dust)
	dust.timeout.connect(func():
		if e["built"]:
			dust.queue_free()
		else:
			_puff(p + Vector3(0, 0.05, 0), Color(0.55, 0.48, 0.38, 0.2)))


## Level ground for an engine at angle `a`, radius `rad` from the town, or the nearest of the steps round it
## (near: [radians along the arc, units out or in, steps]): first along the arc either way, then out and in.
## INF when none of them is level ground.
func _level_near(a: float, rad: float, near: Array) -> Vector3:
	var da := float(near[0]) if near.size() > 0 else 0.06
	var dr := float(near[1]) if near.size() > 1 else 0.25
	var n := int(near[2]) if near.size() > 2 else 8
	for i in n + 1:
		for sa in ([0] if i == 0 else [1, -1]):
			var p := _arc(a + da * i * sa, rad)
			if scenes._footing(p):
				return p
	for i in range(1, n + 1):
		for sr in [1, -1]:
			for j in n + 1:
				for sa in ([0] if j == 0 else [1, -1]):
					var p := _arc(a + da * j * sa, rad + dr * i * sr)
					if scenes._footing(p):
						return p
	return Vector3.INF


## One throw, then the next after every_s: wind, load, throw (the stone lets go partway through the swing),
## settle. A crew all fallen stops the engine until men come back from the camp.
func _cycle(e: Dictionary) -> void:
	var k: Dictionary = Data.value("siege", "engines", {})
	var node: Node3D = e["node"]
	if not is_instance_valid(node):
		return
	var crew: Array = e["crew"].filter(func(m): return m["alive"] and is_instance_valid(m["node"]))
	if crew.is_empty():
		_recrew(e, k)
		return
	var kk: Dictionary = e["k"]
	var arm: Node3D = e["arm"]
	var rest := float(kk.get("rest", 0.0))
	var wind := float(kk.get("wind", 0.5))
	var throw_to := float(kk.get("throw", -2.0))
	var throw_s := float(k.get("throw_s", 0.45))
	var stone := _stone()
	var tw := node.create_tween()
	# Wind: the arm drawn back, the crew at the winch.
	tw.tween_callback(func():
		for m in crew:
			if m["alive"] and is_instance_valid(m["node"]):
				scenes.people.play(m["node"], "Pushing", r.randf_range(0.9, 1.1)))
	if arm:
		tw.tween_property(arm, "rotation:z", wind, float(k.get("wind_s", 2.6))).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_interval(float(k.get("wind_s", 2.6)))
	# Load: a stone set in the sling or bucket.
	tw.tween_callback(func():
		if crew[0]["alive"] and is_instance_valid(crew[0]["node"]):
			scenes.people.play(crew[0]["node"], "PickUp_Table", 1.0)
		stone.visible = true
		_hold_stone(e, stone))
	tw.tween_interval(float(k.get("load_s", 1.2)))
	# Throw: the arm whips over; partway the stone lets go.
	if arm:
		tw.tween_property(arm, "rotation:z", throw_to, throw_s * float(kk.get("release", 0.7))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _loose(e, stone))
	if arm:
		tw.tween_property(arm, "rotation:z", throw_to * 1.06, throw_s * (1.0 - float(kk.get("release", 0.7))))
		tw.tween_property(arm, "rotation:z", rest, float(k.get("settle_s", 1.6))).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		for m in crew:
			if m["alive"] and is_instance_valid(m["node"]):
				scenes.people.play(m["node"], ["Idle", "Looking_Around", "Pointing_Forward"][r.randi() % 3], 1.0))
	var every: Array = k.get("every_s", [6.0, 9.0])
	tw.tween_interval(r.randf_range(float(every[0]), float(every[1])))
	tw.tween_callback(_cycle.bind(e))


## Men from the camp take the fallen crew's places after crew_back_s, and the engine works again.
func _recrew(e: Dictionary, k: Dictionary) -> void:
	var t := get_tree().create_timer(float(k.get("crew_back_s", 20.0)))
	t.timeout.connect(func():
		if not is_instance_valid(e["node"]):
			return
		var p: Vector3 = e["node"].position
		var away: Vector3 = (p - at).normalized()
		away.y = 0.0
		var side := Vector3(-away.z, 0, away.x)
		e["crew"] = []
		for i in int(k.get("crew", 3)):
			e["crew"].append(_crewman(p + away * 0.22 + side * (i - 1) * 0.14, ["Idle"]))
		_cycle(e))


## The stone sits at the arm's tip until it lets go.
func _hold_stone(e: Dictionary, stone: MeshInstance3D) -> void:
	var arm: Node3D = e["arm"]
	if arm == null:
		stone.global_position = e["node"].global_position + Vector3(0, 0.35, 0)
		return
	var tip: Array = e["k"].get("tip", [-1.0, 0.0, 0.0])
	var held := Node3D.new()
	held.position = Vector3(float(tip[0]), float(tip[1]), float(tip[2]))
	arm.add_child(held)
	stone.set_meta("held", held)
	stone.global_position = held.global_position
	stone.set_process(true)


## Let go: the stone flies on its arc from where the arm let it go to a doomed stone of the wall (walls.gd),
## or into the town; it lands on the wall as a blow, or in a puff of dust.
func _loose(e: Dictionary, stone: MeshInstance3D) -> void:
	var k: Dictionary = Data.value("siege", "engines", {})
	var from := stone.global_position
	if stone.has_meta("held"):
		var held: Node3D = stone.get_meta("held")
		if is_instance_valid(held):
			from = held.global_position
			held.queue_free()
		stone.remove_meta("held")
	var walls: Node = Engine.get_meta("stone_walls") if Engine.has_meta("stone_walls") else null
	var on_wall: Vector3 = walls.aim(from) if walls else Vector3.INF
	var spread := float(k.get("spread", 0.8))
	var land: Vector3 = on_wall if on_wall != Vector3.INF else scenes.ground(at + Vector3(r.randf_range(-spread, spread), 0, r.randf_range(-spread, spread)))
	var top := maxf(from.y, land.y) + from.distance_to(land) * float(k.get("arc", 0.45))
	var flight := float(k.get("flight_s", 1.6)) * clampf(from.distance_to(land) / 2.5, 0.7, 1.6)
	# Its trail: a thin smear of dust behind it, so the arc reads from the camera (04-siege's flying stones).
	var trail: CPUParticles3D = scenes.puffs(Color(0.62, 0.58, 0.52, float(k.get("trail_alpha", 0.28))), int(k.get("trail", 24)), 0.9, 0.025, 0.06)
	trail.local_coords = false
	var tg: GPUParticles3D = Particles.to_gpu(trail)
	stone.add_child(tg)
	tg.emitting = true
	var tw := stone.create_tween()
	tw.tween_method(func(t: float):
		var q := from.lerp(land, t)
		q.y = lerpf(from.y, land.y, t) + (top - maxf(from.y, land.y)) * 4.0 * t * (1.0 - t)
		stone.global_position = q, 0.0, 1.0, flight)
	tw.tween_callback(func():
		# The stone gone, its trail let fade where it is.
		if is_instance_valid(tg):
			var at_end := tg.global_transform
			stone.remove_child(tg)
			root.add_child(tg)
			tg.global_transform = at_end
			tg.emitting = false
			get_tree().create_timer(1.5).timeout.connect(tg.queue_free)
		stone.queue_free()
		if on_wall != Vector3.INF and walls and is_instance_valid(walls):
			walls.strike(land, (land - from).normalized())  # its own dust and falling stones
			for m in e["crew"]:
				if m["alive"] and is_instance_valid(m["node"]) and r.randf() < 0.5:
					scenes.people.play(m["node"], "Cheering", 1.0)
		else:
			_puff(land + Vector3(0, 0.05, 0), Color(0.5, 0.45, 0.38, 0.3), float(k.get("impact", 2.5))))  # a burst of earth where it lands


func _stone() -> MeshInstance3D:
	if _stone_mesh == null:
		_stone_mesh = SphereMesh.new()
		_stone_mesh.radius = 0.035
		_stone_mesh.height = 0.07
		_stone_mat = StandardMaterial3D.new()
		_stone_mat.albedo_color = Color(0.36, 0.34, 0.31)
	var s := MeshInstance3D.new()
	s.mesh = _stone_mesh
	s.material_override = _stone_mat
	s.visible = false
	add_child(s)
	return s


## A held stone follows the arm's tip as it swings; the ram and the tower roll.
func _process(_delta: float) -> void:
	_roll(_delta)
	for s in get_children():
		if s is MeshInstance3D and s.has_meta("held"):
			var held: Node3D = s.get_meta("held")
			if is_instance_valid(held):
				(s as MeshInstance3D).global_position = held.global_position


func _puff(p: Vector3, c: Color, big := 1.0) -> void:
	var d: CPUParticles3D = scenes.puffs(c, int(6 * big * 2.0), 1.0 + 0.4 * big, 0.04 * big, 0.1 * big)
	d.one_shot = true
	d.explosiveness = 0.9
	d.position = p
	var g: GPUParticles3D = Particles.to_gpu(d)
	root.add_child(g)
	g.emitting = true
	get_tree().create_timer(3.0).timeout.connect(g.queue_free)
