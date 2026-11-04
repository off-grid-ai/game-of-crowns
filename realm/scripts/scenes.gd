extends Node3D
## The scene director: turns what just happened in Freeciv into something you
## can watch where it happened. Battles clash and leave the fallen; sacked
## towns burn while their people flee; famine sends families onto the roads;
## the King's grain goes out by wagon under escort.

var terrain: Node3D
var towns: Node3D
var _people = preload("res://scripts/people.gd").new()
const Heraldry = preload("res://scripts/heraldry.gd")
const Realistic = preload("res://scripts/realistic.gd")
var _seen := {}  # scene key -> true, so each event plays once
var _wagon: Mesh
var _sieges := {}  # city id -> {root, until}: one camp per besieged town, kept while the host stays
var _timber: StandardMaterial3D
var _engines := [preload("res://assets/castle/siege-catapult.glb"), preload("res://assets/castle/siege-trebuchet.glb")]


func _ready() -> void:
	var builder = preload("res://scripts/house_builder.gd").new()
	_wagon = builder.piece_mesh("Prop_Wagon")


func sync(world: Dictionary, houses: Dictionary) -> void:
	var played_battle := {}
	for s in world.get("scenes", []):
		var key := "%s:%d:%d:%d:%d" % [s["kind"], int(s.get("x", 0)), int(s.get("y", 0)), int(s.get("turn", 0)), int(s.get("city", -1))]
		if _seen.has(key):
			continue
		_seen[key] = true
		var at: Vector3 = terrain.world_pos(float(s.get("x", 0)), float(s.get("y", 0)))
		match String(s["kind"]):
			"battle":
				# Many deaths on one tile in one turn are one battle.
				var tile := "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s["turn"])]
				if played_battle.has(tile):
					continue
				played_battle[tile] = true
				_battle(at, houses.get(int(s.get("owner", -1)), {}))
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
				for c in world.get("cities", []):
					if int(c["id"]) == int(s["city"]):
						city = c
				var approach: Vector3 = terrain.world_pos(float(s.get("ax", s["x"])), float(s.get("ay", s["y"])))
				_siege(int(s["city"]), at, approach, int(city.get("size", 4)), int(s.get("engines", 0)), houses.get(int(s.get("owner", -1)), {}), houses.get(int(s.get("defender", -1)), {}), float(world.get("turnSeconds", 20.0)))
			"grain", "tribute":
				_convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), s["kind"] == "grain")
			"muster":
				var goal: Vector3 = terrain.world_pos(float(s.get("tx", s["x"])), float(s.get("ty", s["y"])))
				_muster(at, goal)
			"ward":
				_convoy(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), false, "A ward for the King's court")
			"rider":
				_rider(at, terrain.world_pos(float(s["tx"]), float(s["ty"])), String(s.get("label", "The King's word")))
			"feast":
				_feast(at, houses.get(int(s.get("owner", -1)), {}))
			"handover":
				var town := "The town"
				for c in world.get("cities", []):
					if int(c["id"]) == int(s.get("city", -1)):
						town = String(c.get("title", c["name"]))
				_handover(at, houses.get(int(s.get("from", -1)), {}), houses.get(int(s.get("to", -1)), {}), town)


func _rng(at: Vector3) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(at) + Time.get_ticks_msec()
	return r


func _ground(p: Vector3) -> Vector3:
	return Vector3(p.x, terrain.height_at(p.x, p.z), p.z)


# --- battle -----------------------------------------------------------------------

## A pitched battle where Freeciv says men died: two companies form up under
## their banners in loose ranks, advance, charge, and meet along a line where
## each front-rank man duels the man opposite. Men fall, those behind step up,
## and one side breaks and scatters.
const RANKS := 3
const FILES := 7
const GAP := 0.19  # between files: about 1.6 m, room to swing a sword
const ROW := 0.21  # between ranks: about 1.8 m
const REACH := 0.09  # half the distance between two duelists: 1.5 m apart


func _battle(at: Vector3, loser: Dictionary) -> void:
	var root := Node3D.new()
	add_child(root)
	var r := _rng(at)
	var cols := [Color.from_string(String(loser.get("color", "#777")), Color.GRAY).lerp(Color.WHITE, 0.3), Color(0.5, 0.17, 0.15)]
	var ang := r.randf() * TAU
	var dir := Vector3(cos(ang), 0, sin(ang))  # team 0 faces -dir, team 1 faces +dir
	var side := Vector3(-dir.z, 0, dir.x)
	var teams := [[], []]
	var banners := []
	for team in 2:
		var face: Vector3 = -dir if team == 0 else dir
		for rank in RANKS:
			for file in FILES:
				# Where this man will stand once the lines meet; he starts 0.9 back from there.
				var slot: Vector3 = at - face * (REACH + rank * ROW) + side * ((file - (FILES - 1) / 2.0) * GAP)
				slot += side * r.randf_range(-0.025, 0.025) - face * r.randf_range(0.0, 0.03)
				var f: Node3D = _people.make(r, "soldier", cols[team], "adult")
				f.position = _ground(slot - face * 1.4)
				f.rotation.y = atan2(face.x, face.z)
				root.add_child(f)
				_people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
				teams[team].append({"node": f, "rank": rank, "file": file, "face": face, "slot": slot, "alive": true, "engaged": false})
		banners.append(_standard(root, at - face * (REACH + RANKS * ROW + 1.45), cols[team], face, loser if team == 0 else {}))
	# 1. Form up and hold (0-3 s), 2. advance at a walk to 0.3 short (3-8 s), 3. charge home (8-10 s).
	_advance(teams, 3.0, 5.0, 0.45, "Walk", r)
	_advance(teams, 8.0, 2.0, 0.0, "Sprint", r)
	_follow_banners(banners, teams, 3.0, 7.0)
	# 4. The clash (10-21 s): front pairs duel; men fall, those behind step up.
	var tw := create_tween()
	tw.tween_interval(10.2)
	tw.tween_callback(func():
		_dust(root, _ground(at) + Vector3(0, 0.01, 0), side, FILES * GAP)
		for team in teams:
			for m in team:
				m["engaged"] = m["rank"] == 0
				_people.play(m["node"], "Sword_Attack" if m["rank"] == 0 else "Sword_Idle", r.randf_range(0.8, 1.2)))
	# The ranks behind press into the gaps and join the melee: the second
	# rank two seconds in, the third three seconds later.
	_press(teams, 1, 12.0, side, r)
	_press(teams, 2, 15.0, side, r)
	for beat in 11:
		tw.tween_interval(1.0)
		tw.tween_callback(func():
			# The losing side (team 0) falls three times as often.
			if r.randf() < 0.75:
				_fall(teams[0], r)
			if r.randf() < 0.25:
				_fall(teams[1], r)
			for team in teams:
				for m in team:
					if m["alive"] and m["engaged"]:
						_duel_step(m, r))
	# 5. The rout (21 s): the beaten turn and scatter; the victors chase a few paces.
	tw.tween_callback(func():
		_drop_banner(banners[0])
		for m in teams[0]:
			if not m["alive"]:
				continue
			var n: Node3D = m["node"]
			var away: Vector3 = (-m["face"] + side * r.randf_range(-0.7, 0.7)).normalized()
			n.rotation.y = atan2(away.x, away.z)
			_people.play(n, "Sprint", r.randf_range(1.0, 1.2))
			_walk(n, n.position + away * r.randf_range(2.0, 3.0), r.randf_range(5.0, 7.0), true)
		for m in teams[1]:
			if not m["alive"]:
				continue
			var n: Node3D = m["node"]
			if m["rank"] == 0 and r.randf() < 0.6:
				_people.play(n, "Sprint", 0.9)
				var from := n.position
				var to: Vector3 = from + m["face"] * r.randf_range(0.3, 0.6)
				var mt := n.create_tween()
				mt.tween_method(func(k: float):
					if is_instance_valid(n):
						n.position = _ground(from.lerp(to, k)), 0.0, 1.0, 1.5)
				mt.tween_callback(func(): _people.play(n, "Sword_Idle", 1.0))
			else:
				_people.play(n, "Sword_Idle", 1.0))
	# 6. The field (afterwards): the fallen stay a minute.
	tw.tween_interval(70.0)
	tw.tween_callback(root.queue_free)


## Moves each living soldier toward his slot, stopping `short` before it, over
## about `secs` from `start`. Each man sets off a beat apart, so no line moves
## like a single block.
func _advance(teams: Array, start: float, secs: float, short: float, anim: String, r: RandomNumberGenerator) -> void:
	for team in teams:
		for m in team:
			var delay: float = start + r.randf_range(0.0, 0.5) + m["rank"] * 0.15
			var n: Node3D = m["node"]
			var tw := n.create_tween()
			tw.tween_interval(delay)
			tw.tween_callback(func():
				if not m["alive"]:
					return
				_people.play(n, anim, r.randf_range(0.9, 1.1))
				var from := n.position
				var to: Vector3 = m["slot"] - m["face"] * short
				var mt := n.create_tween()
				mt.tween_method(func(k: float):
					if is_instance_valid(n):
						n.position = _ground(from.lerp(to, k)), 0.0, 1.0, secs * r.randf_range(0.9, 1.05)))


## A duelist's footwork between blows: a lunge in, a step back, or a sidestep.
func _duel_step(m: Dictionary, r: RandomNumberGenerator) -> void:
	var n: Node3D = m["node"]
	var face: Vector3 = m["face"]
	var across := Vector3(-face.z, 0, face.x)
	var home: Vector3 = m["slot"]
	var to: Vector3 = home + face * r.randf_range(-0.04, 0.03) + across * r.randf_range(-0.03, 0.03)
	var mt := n.create_tween()
	mt.tween_property(n, "position", _ground(to), r.randf_range(0.35, 0.6)).set_trans(Tween.TRANS_SINE)
	_people.play(n, "Sword_Attack", r.randf_range(0.8, 1.25))


func _follow_banners(banners: Array, teams: Array, start: float, secs: float) -> void:
	for i in banners.size():
		var b: Node3D = banners[i]
		var face: Vector3 = teams[i][0]["face"]
		var tw := create_tween()
		tw.tween_interval(start)
		tw.tween_property(b, "position", _ground(b.position + face * 1.4), secs)


## The men of `rank` push forward into the gaps between the duelling pairs and fight.
func _press(teams: Array, rank: int, at_time: float, side: Vector3, r: RandomNumberGenerator) -> void:
	var tw := create_tween()
	tw.tween_interval(at_time)
	tw.tween_callback(func():
		for team in teams:
			for m in team:
				if not m["alive"] or m["engaged"] or m["rank"] != rank:
					continue
				var n: Node3D = m["node"]
				var lane := 0.5 if (m["file"] + rank) % 2 == 0 else -0.5
				m["slot"] = m["slot"] + m["face"] * (ROW * rank - REACH * 0.3 * rank) + side * GAP * lane * 0.8
				m["engaged"] = true
				var mt := n.create_tween()
				mt.tween_interval(r.randf_range(0.0, 0.9))
				mt.tween_callback(func(): _people.play(n, "Sprint", r.randf_range(0.8, 1.0)))
				mt.tween_property(n, "position", _ground(m["slot"]), r.randf_range(0.7, 1.0))
				mt.tween_callback(func(): _people.play(n, "Sword_Attack", r.randf_range(0.85, 1.15))))


func _fall(team: Array, r: RandomNumberGenerator) -> void:
	var front := team.filter(func(m): return m["alive"] and m["engaged"])
	if front.is_empty():
		return
	var m: Dictionary = front[r.randi() % front.size()]
	m["alive"] = false
	var anim: AnimationPlayer = m["node"].get_node("Anim")
	anim.get_animation("Death01").loop_mode = Animation.LOOP_NONE
	anim.play("Death01", 0.1)
	# The man behind steps over the body into the gap, at his own pace.
	for back in team:
		if back["alive"] and not back["engaged"] and back["file"] == m["file"] and back["rank"] > 0:
			back["rank"] -= 1
			back["engaged"] = true
			back["slot"] = back["slot"] + back["face"] * ROW + Vector3(-back["face"].z, 0, back["face"].x) * r.randf_range(-0.04, 0.04)
			var n: Node3D = back["node"]
			var mt := n.create_tween()
			mt.tween_interval(r.randf_range(0.2, 0.8))
			mt.tween_callback(_people.play.bind(n, "Walk", 1.0))
			mt.tween_property(n, "position", _ground(back["slot"]), 0.8)
			mt.tween_callback(_people.play.bind(n, "Sword_Attack", 1.0))
			break


func _standard(root: Node3D, p: Vector3, color: Color, face: Vector3, house := {}) -> Node3D:
	var b: Node3D = Heraldry.standard(house, color, 0.62)
	b.position = _ground(p)
	b.rotation.y = atan2(face.x, face.z)
	root.add_child(b)
	return b


func _drop_banner(b: Node3D) -> void:
	var tw := b.create_tween()
	tw.tween_property(b, "rotation:x", deg_to_rad(80), 1.2).set_ease(Tween.EASE_IN)


func _dust(root: Node3D, p: Vector3, along: Vector3, width: float) -> void:
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
	root.add_child(d)
	var tw := d.create_tween()
	tw.tween_interval(10.0)
	tw.tween_callback(func(): d.emitting = false)


# --- sieges ------------------------------------------------------------------------------

## A host at a town's walls: its camp spreads in an arc on the side it came
## from, engines throw stones over the walls, assault parties rush the walls
## and fall back, and the defenders hold the line. The camp stays while the
## bridge keeps reporting the siege, and breaks up a turn and a half after.
func _siege(id: int, at: Vector3, approach: Vector3, size: int, engines: int, foe: Dictionary, held: Dictionary, turn_secs: float) -> void:
	if _sieges.has(id) and is_instance_valid(_sieges[id]["root"]):
		_sieges[id]["until"] = Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5
		return
	var root := Node3D.new()
	add_child(root)
	_sieges[id] = {"root": root, "until": Time.get_ticks_msec() / 1000.0 + turn_secs * 1.5}
	var r := _rng(at)
	var foe_col := Color.from_string(String(foe.get("color", "#7a2222")), Color.DARK_RED).lerp(Color.WHITE, 0.2)
	var held_col := Color.from_string(String(held.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.3)
	var reach := clampf(1.6 + size * 0.32, 2.0, 6.0)
	var wall := reach + 0.35
	var out := Vector3(approach.x - at.x, 0, approach.z - at.z)
	var want := atan2(out.z, out.x) if out.length() > 0.01 else r.randf() * TAU
	var camp_r := wall + 1.3
	var base := _camp_side(at, want, wall, camp_r)
	var arc := func(a: float, rad: float) -> Vector3:
		return _ground(at + Vector3(cos(base + a), 0, sin(base + a)) * rad)
	_sieges[id]["front"] = arc.call(0.0, wall + 0.6)
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
			var f: Node3D = _people.make(r, "soldier", foe_col, "adult")
			f.position = _ground(p)
			f.rotation.y = atan2(inward.x, inward.z) + r.randf_range(-0.6, 0.6)
			root.add_child(f)
			_people.play(f, "Sword_Idle" if r.randf() < 0.6 else "Idle", r.randf_range(0.8, 1.1))
	# The engines, set back behind the camp line, and their stones.
	for e in clampi(maxi(engines, 1), 1, 3):
		var a := (e - 1) * 0.45 + r.randf_range(-0.05, 0.05)
		var ep: Vector3 = arc.call(a, camp_r + 0.75)
		var engine: Node3D = _engines[e % 2].instantiate()
		root.add_child(engine)
		_fit(engine, 0.7)
		_weather(engine)
		engine.position = ep
		var to_town := at - ep
		engine.rotation.y = atan2(to_town.x, to_town.z) + PI
		_volley(root, ep + Vector3(0, 0.35, 0), at, reach * 0.8, r, 4.0 + e * 1.3)
	# The defenders on the walls, facing out toward the host.
	for i in 9:
		var a := (i - 4) * 0.13
		var p: Vector3 = arc.call(a, wall - 0.12)
		if not _footing(p):
			continue
		var f: Node3D = _people.make(r, "soldier", held_col, "adult")
		f.position = p
		var face := (p - at).normalized()
		f.rotation.y = atan2(face.x, face.z)
		root.add_child(f)
		_people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
	# Assault parties rush the walls in turn, fight there, and fall back.
	for party in 2:
		_assault(root, arc, (party - 0.5) * 0.5, camp_r, wall, foe_col, r, 3.0 + party * 6.0)
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


## Stones in flight on a loop: each arcs from the engine to a point inside the
## walls, lands with a puff of dust, and now and then sets a roof alight.
func _volley(root: Node3D, from: Vector3, at: Vector3, spread: float, r: RandomNumberGenerator, every: float) -> void:
	var stone := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	stone.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.33, 0.3)
	stone.material_override = mat
	stone.visible = false
	root.add_child(stone)
	var shoot := func():
		var land := _ground(at + Vector3(r.randf_range(-spread, spread), 0, r.randf_range(-spread, spread)))
		var top := maxf(from.y, land.y) + from.distance_to(land) * 0.45
		stone.visible = true
		var tw := stone.create_tween()
		tw.tween_method(func(t: float):
			var p := from.lerp(land, t)
			p.y = lerpf(from.y, land.y, t) + (top - maxf(from.y, land.y)) * 4.0 * t * (1.0 - t)
			stone.position = p, 0.0, 1.0, 1.6)
		tw.tween_callback(func():
			stone.visible = false
			var d := _puffs(Color(0.5, 0.45, 0.38, 0.22), 6, 1.0, 0.04, 0.1)
			d.one_shot = true
			d.explosiveness = 0.9
			d.position = land + Vector3(0, 0.05, 0)
			root.add_child(d)
			d.emitting = true)
	var t := Timer.new()
	t.wait_time = every
	t.autostart = true
	t.timeout.connect(shoot)
	root.add_child(t)


## Six men leave the camp at a run, fight at the foot of the walls, and fall back.
func _assault(root: Node3D, arc: Callable, a: float, camp_r: float, wall: float, col: Color, r: RandomNumberGenerator, first: float) -> void:
	var men := []
	for i in 6:
		var f: Node3D = _people.make(r, "soldier", col, "adult")
		var off := (i - 2.5) * 0.06
		var home: Vector3 = arc.call(a + off, camp_r - 0.35)
		f.position = home
		root.add_child(f)
		men.append({"node": f, "home": home, "foot": arc.call(a + off, wall + 0.12)})
	var cycle := func():
		for m in men:
			var n: Node3D = m["node"]
			if not is_instance_valid(n):
				continue
			var tw := n.create_tween()
			var face: Vector3 = (m["foot"] - m["home"]).normalized()
			tw.tween_interval(r.randf_range(0.0, 0.6))
			tw.tween_callback(func():
				n.rotation.y = atan2(face.x, face.z)
				_people.play(n, "Sprint", r.randf_range(0.9, 1.1)))
			tw.tween_property(n, "position", m["foot"], 2.2)
			tw.tween_callback(func(): _people.play(n, "Sword_Attack", r.randf_range(0.85, 1.15)))
			tw.tween_interval(r.randf_range(3.0, 4.5))
			tw.tween_callback(func():
				n.rotation.y = atan2(-face.x, -face.z)
				_people.play(n, "Walk", 1.0))
			tw.tween_property(n, "position", m["home"], 3.0)
			tw.tween_callback(func():
				n.rotation.y = atan2(face.x, face.z)
				_people.play(n, "Sword_Idle", 1.0))
	var t := Timer.new()
	t.wait_time = 15.0
	t.timeout.connect(cycle)
	root.add_child(t)
	var start := create_tween()
	start.tween_interval(first)
	start.tween_callback(func():
		if is_instance_valid(t):
			cycle.call()
			t.start())


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
	var root := Node3D.new()
	add_child(root)
	var r := _rng(at)
	for i in int(5 * scale):
		var off := Vector3(r.randf_range(-1.2, 1.2), 0, r.randf_range(-1.2, 1.2)) * scale
		var p := _ground(at + off)
		# Flames as lit particles, not additive glow: additive fire blooms into
		# white orbs at this scale.
		var fire := _puffs(Color(1.0, 0.45, 0.1, 0.85), 18, 0.7, 0.05, 0.12)
		fire.initial_velocity_min = 0.15
		fire.initial_velocity_max = 0.35
		fire.position = p + Vector3(0, 0.2, 0)
		root.add_child(fire)
		var smoke := _puffs(Color(0.12, 0.11, 0.1, 0.75), 30, 6.0, 0.3, 0.8)
		smoke.position = p + Vector3(0, 0.6, 0)
		root.add_child(smoke)
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
			if c is CPUParticles3D:
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
		var f: Node3D = _people.make(r, "peasant", Color(0.75, 0.72, 0.68))
		var start := at + Vector3(cos(ang), 0, sin(ang)) * (2.0 + i * 0.12) + Vector3(r.randf_range(-0.1, 0.1), 0, r.randf_range(-0.1, 0.1))
		var goal := start + Vector3(cos(ang), 0, sin(ang)) * 4.0
		add_child(f)
		f.look_at_from_position(_ground(start), _ground(goal) + Vector3(0, _ground(start).y - terrain.height_at(goal.x, goal.z), 0), Vector3.UP)
		f.rotate_y(PI)
		# Some flee at a run, the rest trudge with what they could carry.
		var running := i % 3 == 0
		_people.play(f, "Running" if running else "Walk", 1.0 if running else 0.7)
		_walk(f, goal, 14.0 if running else 30.0, true)


func _walk(n: Node3D, goal: Vector3, seconds: float, fade: bool) -> void:
	var route: PackedVector3Array = terrain.land_path(n.position, goal)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if not is_instance_valid(n):
			return
		var p: Vector3 = terrain.along(route, t)
		if not terrain.is_land(p.x, p.z):
			return  # never step into water; stop at the shore
		n.position = _ground(p), 0.0, 1.0, seconds)
	if fade:
		tw.tween_callback(n.queue_free)


## The royal host musters in Kingsmere's square in ranks under the crown's
## banners, holds a moment, then marches out in column two abreast along the
## road toward where it is sent, and halts there in formation.
func _muster(at: Vector3, goal: Vector3) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	add_child(root)
	var col := Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.25)
	var crown := {"name": "The Crown", "crown": true}
	var route: PackedVector3Array = terrain.land_path(at, goal)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var start_dir: Vector3 = (terrain.along(route, minf(1.0, 0.6 / maxf(length, 0.6))) - at)
	start_dir.y = 0
	start_dir = start_dir.normalized() if start_dir.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-start_dir.z, 0, start_dir.x)
	var men := []
	const FILES := 4
	const RANKS := 4
	for rank in RANKS:
		for file in FILES:
			var f: Node3D = _people.make(r, "soldier", col, "adult")
			f.position = _ground(at + side * ((file - 1.5) * 0.12) - start_dir * (rank * 0.14))
			f.rotation.y = atan2(start_dir.x, start_dir.z)
			root.add_child(f)
			_people.play(f, "Sword_Idle", r.randf_range(0.9, 1.1))
			men.append({"node": f, "slot": rank * FILES + file})
	var banners := []
	for i in 2:
		var b: Node3D = Heraldry.standard(crown, col, 0.62)
		b.position = _ground(at + side * (i * 0.36 - 0.18) + start_dir * 0.16)
		root.add_child(b)
		banners.append(b)
	# Formed up (0-4 s), then the column marches; each man keeps his place in it.
	var seconds := clampf(length / 0.25, 10.0, 80.0)
	var spacing := 0.11 / maxf(length, 0.5)
	var tw := create_tween()
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		for m in men:
			_people.play(m["node"], "Walk", r.randf_range(0.95, 1.05)))
	tw.tween_method(func(t: float):
		for m in men:
			var n: Node3D = m["node"]
			var row := int(m["slot"]) / 2
			var k := clampf(t - row * spacing, 0.0, 1.0)
			var p: Vector3 = terrain.along(route, k)
			var ahead: Vector3 = terrain.along(route, minf(1.0, k + 0.01))
			var dir := Vector3(ahead.x - p.x, 0, ahead.z - p.z)
			if dir.length() > 0.0001:
				dir = dir.normalized()
				n.rotation.y = atan2(dir.x, dir.z)
			var across := Vector3(-dir.z, 0, dir.x)
			n.position = _ground(p + across * (0.05 if int(m["slot"]) % 2 == 0 else -0.05))
		for i in banners.size():
			banners[i].position = _ground(terrain.along(route, clampf(t + 0.02 - i * 0.01, 0.0, 1.0)))
		, 0.0, 1.0 + 8 * spacing, seconds)
	tw.tween_callback(func():
		for m in men:
			_people.play(m["node"], "Sword_Idle", 1.0))
	tw.tween_interval(40.0)
	tw.tween_callback(root.queue_free)


## A royal rider carries the King's ruling at a run to the petitioner's seat,
## under the crown's banner, with what was decided written above him.
func _rider(from: Vector3, to: Vector3, label: String) -> void:
	var r := _rng(to)
	var rider: Node3D = _people.make(r, "soldier", Color(0.72, 0.13, 0.16).lerp(Color.WHITE, 0.3), "adult")
	add_child(rider)
	var standard: Node3D = Heraldry.standard({"name": "The Crown", "crown": true}, Color(0.72, 0.13, 0.16), 3.4)
	standard.position = Vector3(0.35, 0, -0.1)
	rider.add_child(standard)
	var tag := Label3D.new()
	tag.visibility_range_begin = 1.6  # gone when you're walking right past it
	tag.text = label
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.85, 0.6)
	add_child(tag)
	_people.play(rider, "Running", 1.1)
	var route: PackedVector3Array = terrain.land_path(from, to)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := _ground(terrain.along(route, t))
		var ahead := _ground(terrain.along(route, minf(1.0, t + 0.01)))
		if ahead.distance_to(p) > 0.0001:
			rider.rotation.y = atan2(ahead.x - p.x, ahead.z - p.z)
		rider.position = p
		tag.position = p + Vector3(0, 0.4, 0), 0.0, 1.0, clampf(length / 0.6, 8.0, 45.0))
	tw.tween_callback(func(): _people.play(rider, "Idle", 1.0))
	tw.tween_interval(4.0)
	tw.tween_callback(func():
		rider.queue_free()
		tag.queue_free())


# --- the King's convoys ------------------------------------------------------------------

func _convoy(from: Vector3, to: Vector3, grain: bool, label := "") -> void:
	var r := _rng(from)
	var root := Node3D.new()
	add_child(root)
	var wagon := MeshInstance3D.new()
	wagon.mesh = _wagon
	wagon.scale = Vector3.ONE * 0.12
	root.add_child(wagon)
	var crown_col := Color(0.72, 0.13, 0.16)
	var escort := []
	for i in 3:
		var s: Node3D = _people.make(r, "soldier", crown_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		_people.play(s, "Walk")
		escort.append(s)
	var route: PackedVector3Array = terrain.land_path(from, to)
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var seconds := clampf(length / 0.35, 12.0, 70.0)
	var tag := Label3D.new()
	tag.visibility_range_begin = 1.6  # gone when you're walking right past it
	tag.text = label if label != "" else ("The King's grain" if grain else "The King's gold")
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.85, 0.6)
	root.add_child(tag)
	var tw := create_tween()
	tw.tween_method(func(t: float):
		var p := _ground(terrain.along(route, t))
		var ahead := _ground(terrain.along(route, minf(1.0, t + 0.01)))
		var dir := (ahead - p).normalized() if ahead.distance_to(p) > 0.0001 else Vector3.FORWARD
		var side := Vector3(-dir.z, 0, dir.x)
		wagon.position = p
		wagon.rotation.y = atan2(dir.x, dir.z) + PI
		tag.position = p + Vector3(0, 0.45, 0)
		for i in escort.size():
			var e: Node3D = escort[i]
			var trail := _ground(terrain.along(route, maxf(0.0, t - (0.004 + i * 0.003))))
			e.position = trail + side * (0.05 if i % 2 == 0 else -0.05)
			e.rotation.y = atan2(dir.x, dir.z), 0.0, 1.0, seconds)
	tw.tween_interval(3.0)
	tw.tween_callback(root.queue_free)


# --- feasts and handovers ----------------------------------------------------------

## A wedding feast in the town square: a fire, barrels broached, the town
## dancing in a ring around it and talking in knots at the edges.
func _feast(at: Vector3, house: Dictionary) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	add_child(root)
	var centre := _ground(at)
	var fire: Node3D = Realistic.make("ph/stone_fire_pit")
	if fire:
		fire.position = centre + Vector3(0.0, 0.0, 0.0)
		root.add_child(fire)
	# A roasting fire: seen by day as its smoke, a thin grey column.
	var flame := _puffs(Color(0.55, 0.53, 0.5, 0.5), 10, 3.0, 0.06, 0.14)
	flame.position = centre + Vector3(0, 0.08, 0)
	root.add_child(flame)
	for i in 3:
		var cask: Node3D = Realistic.make("ph/wine_barrel_01")
		if cask:
			var a := TAU * (0.1 + i * 0.07)
			cask.position = _ground(at + Vector3(cos(a), 0, sin(a)) * 0.95)
			cask.rotation.y = r.randf() * TAU
			root.add_child(cask)
	var col := Color.from_string(String(house.get("color", "#b08a4a")), Color(0.7, 0.55, 0.3))
	if not house.is_empty():
		_standard(root, at + Vector3(0.0, 0, -0.9), col, Vector3(0, 0, 1), house)
	# The ring of dancers, turning slowly about the fire.
	var ring := Node3D.new()
	ring.position = centre
	root.add_child(ring)
	var n := 12
	for i in n:
		var a := TAU * i / n
		var f: Node3D = _people.make(r, "peasant", col.lerp(Color.WHITE, 0.55) if i % 3 == 0 else Color.WHITE)
		ring.add_child(f)
		var p := Vector3(cos(a), 0, sin(a)) * 0.42
		f.position = p + Vector3(0, terrain.height_at(at.x + p.x, at.z + p.z) - centre.y, 0)
		f.rotation.y = a + PI * 0.5
		_people.play(f, "Dance", r.randf_range(0.9, 1.1))
	var spin := ring.create_tween().set_loops()
	spin.tween_property(ring, "rotation:y", TAU, 40.0).as_relative()
	# Knots of talkers at the edge of the square.
	for k in 3:
		var a := TAU * (0.35 + k * 0.22)
		var spot := at + Vector3(cos(a), 0, sin(a)) * 1.05
		for j in 3:
			var f: Node3D = _people.make(r)
			root.add_child(f)
			var off := Vector3(cos(j * 2.1), 0, sin(j * 2.1)) * 0.09
			f.position = _ground(spot + off)
			f.rotation.y = atan2(-off.x, -off.z)
			_people.play(f, "Idle_Talking")
	var tag := _caption(root, "A wedding feast", centre + Vector3(0, 1.3, 0))
	_fade_out(root, 75.0, tag)


## A town changing hands by treaty or by its own will: the old lord's banner
## comes down, a file of the new lord's men marches in, and his goes up.
func _handover(at: Vector3, old_house: Dictionary, new_house: Dictionary, town: String) -> void:
	var r := _rng(at)
	var root := Node3D.new()
	add_child(root)
	var old_col := Color.from_string(String(old_house.get("color", "#777")), Color.GRAY)
	var new_col := Color.from_string(String(new_house.get("color", "#ccc")), Color.WHITE)
	var spot := at + Vector3(0.35, 0, -0.35)
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
	for i in 6:
		var s: Node3D = _people.make(r, "soldier", new_col.lerp(Color.WHITE, 0.3), "adult")
		root.add_child(s)
		var start := at + dir * (4.0 + (i / 2) * 0.22) + side * ((i % 2) * 0.16 - 0.08)
		var goal := spot + dir * (0.35 + (i / 2) * 0.16) + side * ((i % 2) * 0.16 - 0.08)
		s.position = _ground(start)
		s.rotation.y = atan2(-dir.x, -dir.z)
		_people.play(s, "Walk")
		var mt := s.create_tween()
		mt.tween_property(s, "position", _ground(goal), 14.0)
		mt.tween_callback(_people.play.bind(s, "Sword_Idle", 1.0))
	tw.tween_interval(13.0)
	tw.tween_callback(func():
		var b := _standard(root, spot + Vector3(0.12, 0, 0), new_col, Vector3(0, 0, 1), new_house)
		b.scale = Vector3(1, 0.05, 1)
		b.create_tween().tween_property(b, "scale", Vector3.ONE, 2.5).set_ease(Tween.EASE_OUT))
	var tag := _caption(root, "%s passes to %s" % [town, String(new_house.get("name", "a new lord"))], _ground(spot) + Vector3(0, 1.3, 0))
	_fade_out(root, 60.0, tag)


func _caption(root: Node3D, text: String, at: Vector3) -> Label3D:
	var tag := Label3D.new()
	tag.visibility_range_begin = 1.6  # gone when you're walking right past it
	tag.text = text
	tag.font_size = 36
	tag.pixel_size = 0.004
	tag.outline_size = 8
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.95, 0.85, 0.6)
	tag.position = at
	root.add_child(tag)
	return tag


func _fade_out(root: Node3D, seconds: float, tag: Label3D) -> void:
	var tw := root.create_tween()
	tw.tween_interval(seconds)
	tw.tween_property(tag, "modulate:a", 0.0, 2.0)
	tw.tween_callback(root.queue_free)
