extends Node3D
## Decisions seen in the world (North Star: docs/art/target/07-unrest.jpg and 08-reinforce.jpg;
## docs/review/decisions-in-the-world.md; Warcraft III: an order is something on the map; CK3's county
## unrest; Total War's reinforcements). What the King decides stays visible where it lands, for as long
## as it's true:
##   unrest    a displeased house's seat: a crowd in the square round a speaker, its banner lowered, shops
##             barred; angry: smoke, a burned cart and rubble, guards doubled before the crowd
##   feast     lanterns round the square and the holder's banners
##   levy      a sergeant, a table and a line of recruits under the royal standard at the gate
##   garrison  the royal standard and a guard at the gate of a town the King's men marched to
## The one owner of these marks. It decides nothing: every reading comes from the realm as the view
## mirrors it (awareness.gd's town scopes and the world's scenes); the people are the scenes' own
## (scenes.people), the props come from the asset catalogue (realistic.gd), the banners from heraldry.
## The moving parts are already others': the muster's column on the road (scenes.gd), the riot of a
## town in disorder and the feast's fire (town_life.gd), the levy at the armoury and the crier (works.gd).
## Numbers and the switch: realm/data/decisions.json (--decisions=on / --decisions=off).

const Realistic := preload("res://scripts/realistic.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const Awareness := preload("res://scripts/awareness.gd")
const Scenes := preload("res://scripts/scenes.gd")
const Particles := preload("res://scripts/particles.gd")
const Towns := preload("res://scripts/towns.gd")
const CROWN := {"name": "The Crown", "crown": true}
const CROWN_RED := Color(0.72, 0.13, 0.16)
const PLANTED := 0.45  # a planted standard's height, as the scenes plant theirs

static var CFG: Dictionary = _read()

var main: Node
var _marks := {}  # "town:kind" -> {root, sig}
var _garrisons := {}  # town id -> the season its guard goes home
var _t := 0.0


static func _read() -> Dictionary:
	var f := FileAccess.open("res://data/decisions.json", FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text()) if f else null
	return v if v is Dictionary else {}


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--decisions=on") or (bool(CFG.get("on", false)) and not args.has("--decisions=off"))


static func apply(m: Node) -> void:
	if not on():
		return
	var d := new()
	d.name = "Decisions"
	d.main = m
	m.add_child(d)


func _process(delta: float) -> void:
	_t += delta
	if _t < float(CFG.get("every", 1.0)):
		return
	_t = 0.0
	if main.awareness == null or main.towns == null or main.terrain == null or main.scenes == null:
		return
	var world: Dictionary = main.bridge.world
	var turn := int(world.get("turn", 0))
	_note_garrisons(world, turn)
	var want := {}  # "town:kind" -> [town id, kind, level]
	var bands: Dictionary = Awareness.bands
	for c in world.get("cities", []):
		var id := int(c.get("id", -1))
		if not (main.towns.towns as Dictionary).has(id):
			continue  # not raised yet
		var bb: Blackboard = main.awareness.town(id)
		var house: Dictionary = main._houses.get(int(c.get("owner", -1)), {})
		# Unrest: a great house's own seat, by its favour band (the bridge's reading).
		if bool(c.get("capital", false)) and not house.is_empty() and not house.get("crown", false) and not house.get("wild", false) and not bands.is_empty():
			var favour := float(bb.get_var(&"favour", 100.0, false))
			var level := 2 if favour < float(bands.get("cooling", 25)) else (1 if favour < float(bands.get("steady", 35)) else 0)
			if level > 0:
				want["%d:unrest" % id] = [id, "unrest", level]
		if String(bb.get_var(&"mood", "", false)) == "feast":
			want["%d:feast" % id] = [id, "feast", 1]
		if bool(bb.get_var(&"levy", false, false)):
			want["%d:levy" % id] = [id, "levy", 1]
		if int(_garrisons.get(id, -1)) > turn:
			want["%d:garrison" % id] = [id, "garrison", 1]
	# A test aid for one batched render (off in play): --decisions-demo=unrest,unrest2,feast,levy,garrison
	# raises those marks at --city's town (else the King's seat), whatever the realm says.
	for a in OS.get_cmdline_user_args():
		if not String(a).begins_with("--decisions-demo="):
			continue
		var at_id := int(world.get("seatId", -1))
		for c in world.get("cities", []):
			if String(c.get("name", "")) == String(main._shot.get("city", "")) or String(c.get("title", "")) == String(main._shot.get("city", "")):
				at_id = int(c.get("id", -1))
		for kind in String(a).trim_prefix("--decisions-demo=").split(","):
			var level := 2 if kind == "unrest2" else 1
			var k := "unrest" if kind == "unrest2" else String(kind)
			if k in ["unrest", "feast", "levy", "garrison"] and (main.towns.towns as Dictionary).has(at_id):
				want["%d:%s" % [at_id, k]] = [at_id, k, level]
	# What's no longer true goes; what's new, or changed its level, is raised.
	for key in _marks.keys():
		var w = want.get(key)
		if w == null or int(w[2]) != int(_marks[key]["sig"]):
			_lower(key)
	for key in want:
		if not _marks.has(key):
			_raise(key, want[key])


## A muster that marched from the King's seat to another town leaves a guard there (the garrison's seasons).
func _note_garrisons(world: Dictionary, turn: int) -> void:
	var seasons := int((CFG.get("garrison", {}) as Dictionary).get("seasons", 4))
	for s in world.get("scenes", []):
		if String(s.get("kind", "")) != "muster" or s.get("tx") == null:
			continue
		for c in world.get("cities", []):
			if int(c.get("x", -1)) == int(s["tx"]) and int(c.get("y", -1)) == int(s["ty"]) and int(c.get("id", -1)) != int(s.get("city", -2)):
				var until := int(s.get("turn", turn)) + seasons
				if until > int(_garrisons.get(int(c["id"]), -1)):
					_garrisons[int(c["id"])] = until
	for id in _garrisons.keys():
		if int(_garrisons[id]) <= turn:
			_garrisons.erase(id)


# --- raising and lowering a mark -------------------------------------------------------------------

func _raise(key: String, w: Array) -> void:
	var id := int(w[0])
	var town: Dictionary = main.towns.towns.get(id, {})
	var node = town.get("node")
	if not (node is Node3D) or not is_instance_valid(node):
		return
	var root := Node3D.new()
	root.name = "Decision_%s" % key.replace(":", "_")
	add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var centre: Vector3 = (node as Node3D).global_position
	var house: Dictionary = main._houses.get(int((town.get("data", {}) as Dictionary).get("owner", -1)), {})
	match String(w[1]):
		"unrest":
			_unrest(root, node, centre, house, int(w[2]), rng)
		"feast":
			_feast(root, node, centre, house, rng)
		"levy":
			_levy(root, node, centre, id, rng)
		"garrison":
			_garrison(root, node, centre, id, rng)
	_near_only(root)
	_fade(root, 1.0, 0.0)
	_marks[key] = {"root": root, "sig": int(w[2])}


func _lower(key: String) -> void:
	var m: Dictionary = _marks[key]
	_marks.erase(key)
	var root: Node3D = m["root"]
	if not is_instance_valid(root):
		return
	_fade(root, 0.0, 1.0)
	get_tree().create_timer(float(CFG.get("ease", 1.2)) + 0.1).timeout.connect(func():
		if is_instance_valid(root):
			root.queue_free())


## Every mark eases in and out (nothing pops): its geometry's transparency over `ease` seconds.
func _fade(root: Node3D, from: float, to: float) -> void:
	var secs := float(CFG.get("ease", 1.2))
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = g
		gi.transparency = from
		var tw := gi.create_tween()
		tw.tween_property(gi, "transparency", to, secs)


## Street-level detail: drawn only within `near` of the camera, like a town's own life.
func _near_only(root: Node3D) -> void:
	var near := float(CFG.get("near", 40.0))
	for g in root.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = g
		if gi.visibility_range_end == 0.0:
			gi.visibility_range_end = near
			gi.visibility_range_end_margin = 4.0


# --- the marks ------------------------------------------------------------------------------------

## A displeased house's seat (07-unrest): the crowd round a speaker, the banner lowered, shops barred;
## angry: smoke, a burned cart, guards doubled before the crowd.
func _unrest(root: Node3D, node: Node3D, centre: Vector3, house: Dictionary, level: int, rng: RandomNumberGenerator) -> void:
	var u: Dictionary = CFG.get("unrest", {})
	var i := clampi(level - 1, 0, 1)
	var pick := func(key: String, fallback) -> Variant:
		var a = u.get(key)
		return a[i] if a is Array and a.size() > i else fallback
	var square_r := float(node.get_meta("square_r", 1.2))
	var ring := square_r * float(u.get("ring", 0.45))
	# The speaker, on the side of the square, and the crowd facing him in a loose half ring.
	var side := rng.randf() * TAU
	var speaker_at := centre + Vector3(cos(side), 0, sin(side)) * ring
	var speaker := _person(root, rng, "peasant", Color.WHITE, speaker_at, centre)
	_play(speaker, "Yelling", rng)
	var n := int(pick.call("crowd", 6))
	for k in n:
		var a := side + PI + (float(k) / maxf(1.0, n - 1) - 0.5) * 2.2
		var r := ring * rng.randf_range(0.35, 1.0)
		var p := _person(root, rng, "peasant", Color.WHITE, centre + Vector3(cos(a), 0, sin(a)) * r, speaker_at)
		_play(p, ["Arguing", "Yelling", "Idle_Talking", "Arguing"][k % 4], rng)
	# The house's own banner, lowered and askew, beside the speaker.
	var banner: Node3D = Heraldry.standard(house, Heraldry.colour(house, Color.GRAY, "#888"), PLANTED * 0.7)
	banner.position = main.scenes.ground(speaker_at + Vector3(cos(side + 1.2), 0, sin(side + 1.2)) * 0.18)
	banner.rotation.z = float(u.get("banner_tilt", 0.5))
	root.add_child(banner)
	# Shops barred: a plank across the doors nearest the square.
	var doors: Array = (node.get_meta("doors", []) as Array).duplicate()
	doors.sort_custom(func(a, b): return (a["at"] as Vector3).length() < (b["at"] as Vector3).length())
	for d in doors.slice(0, int(pick.call("barred", 3))):
		var at: Vector3 = d["at"]
		var plank := _prop(root, "plank", centre + Vector3(at.x, 0, at.z), atan2(-at.x, -at.z) + PI * 0.5)
		if plank:
			plank.position.y += 0.9 * Realistic.S  # across the door at chest height
			plank.rotation.z = 0.25
	# Angry: smoke, a burned cart with rubble, and the guard doubled between the crowd and the keep.
	for k in int(pick.call("smoke", 0)):
		_smoke(root, centre + Vector3(rng.randf_range(-1.0, 1.0), 0, rng.randf_range(-1.0, 1.0)) * square_r)
	if bool(pick.call("cart", false)):
		var ca := side + 2.4
		var cart_at := centre + Vector3(cos(ca), 0, sin(ca)) * ring * 1.3
		var cart := _prop(root, "cart", cart_at, rng.randf() * TAU)
		if cart:
			cart.rotation.z = 0.45  # tipped on its side
			_char(cart)
		_prop(root, "rubble", cart_at + Vector3(0.12, 0, 0.08), rng.randf() * TAU)
		_smoke(root, cart_at)
	var guards := int(pick.call("guards", 0))
	var col: Color = Heraldry.colour(house, Color.GRAY, "#888")
	for k in guards:
		var a := side + (float(k) / maxf(1.0, guards - 1) - 0.5) * 0.9
		var g := _person(root, rng, "soldier", col, centre + Vector3(cos(a), 0, sin(a)) * ring * 1.6, centre)
		Scenes.arm(g, "spear")
		_play(g, "Sword_Idle", rng)


## A feast (the holder's banners and lanterns round the square; the fire and the revels are town_life's).
func _feast(root: Node3D, node: Node3D, centre: Vector3, house: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Dictionary = CFG.get("feast", {})
	var r := float(node.get_meta("square_r", 1.2)) * float(f.get("ring", 0.85))
	var n := int(f.get("lanterns", 10))
	var light: Dictionary = f.get("light", {})
	var lc: Array = light.get("color", [1.0, 0.72, 0.38])
	for k in n:
		var a := TAU * float(k) / maxf(1.0, n)
		var at := centre + Vector3(cos(a), 0, sin(a)) * r
		var post := _prop(root, "lamp_post", at, a)
		if post == null:
			post = _prop(root, "lantern", at, a)
		if post and k % maxi(1, int(f.get("light_every", 3))) == 0:
			var l := OmniLight3D.new()
			l.light_color = Color(float(lc[0]), float(lc[1]), float(lc[2]))
			l.light_energy = float(light.get("energy", 0.9))
			l.omni_range = float(light.get("range", 0.8))
			l.shadow_enabled = false
			l.position = Vector3(0, 2.4 * Realistic.S, 0)
			l.distance_fade_enabled = true
			l.distance_fade_begin = float(CFG.get("near", 40.0)) * 0.6
			l.distance_fade_length = 6.0
			post.add_child(l)
	var b := int(f.get("banners", 4))
	var col: Color = Heraldry.colour(house, Color.GRAY, "#888")
	for k in b:
		var a := TAU * (float(k) + 0.5) / maxf(1.0, b)
		var s: Node3D = Heraldry.standard(house, col, PLANTED)
		s.position = main.scenes.ground(centre + Vector3(cos(a), 0, sin(a)) * r * 1.05)
		s.rotation.y = rng.randf() * TAU
		root.add_child(s)


## A levy raised (the gate): a sergeant at a table under the royal standard, and the recruits in line.
func _levy(root: Node3D, node: Node3D, centre: Vector3, id: int, rng: RandomNumberGenerator) -> void:
	var l: Dictionary = CFG.get("levy", {})
	var gate := _gate(node, centre, id)
	var out := (gate - centre)
	out.y = 0.0
	out = out.normalized() if out.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-out.z, 0, out.x)
	_prop(root, "table", gate, atan2(side.x, side.z))
	var sergeant := _person(root, rng, "soldier", CROWN_RED.lerp(Color.WHITE, 0.25), gate + out * 0.12, gate - out)
	Scenes.arm(sergeant, "sword")
	_play(sergeant, "Idle_Talking", rng)
	var std: Node3D = Heraldry.standard(CROWN, CROWN_RED.lerp(Color.WHITE, 0.25), PLANTED)
	std.position = main.scenes.ground(gate + side * 0.2 + out * 0.1)
	root.add_child(std)
	var gap := float(l.get("spacing", 0.14))
	for k in int(l.get("recruits", 6)):
		var p := _person(root, rng, "peasant", Color.WHITE, gate - out * (0.16 + gap * k) + side * rng.randf_range(-0.02, 0.02), gate)
		_play(p, "Idle" if k % 3 else "Idle_Talking", rng)


## Reinforcements (08-reinforce): the royal standard and a guard at the gate of the town the King's men
## marched to, for the garrison's seasons. (The column on the road is the muster scene's.)
func _garrison(root: Node3D, node: Node3D, centre: Vector3, id: int, rng: RandomNumberGenerator) -> void:
	var g: Dictionary = CFG.get("garrison", {})
	var gate := _gate(node, centre, id)
	var out := (gate - centre)
	out.y = 0.0
	out = out.normalized() if out.length() > 0.001 else Vector3.FORWARD
	var side := Vector3(-out.z, 0, out.x)
	var col := CROWN_RED.lerp(Color.WHITE, 0.25)
	var n := int(g.get("guards", 6))
	var gap := float(g.get("spacing", 0.13))
	for k in n:
		var file := k % 2
		var rank := k / 2
		var at := gate + side * ((float(file) - 0.5) * gap * 2.4) - out * (rank * gap)  # two files, ranks back toward the town
		var s := _person(root, rng, "soldier", col, at, gate + out)
		Scenes.arm(s, "spear")
		_play(s, "Sword_Idle", rng)
	for k in int(g.get("standards", 2)):
		var std: Node3D = Heraldry.standard(CROWN, col, PLANTED)
		std.position = main.scenes.ground(gate + side * ((float(k) - 0.5) * gap * 4.5) + out * 0.08)
		root.add_child(std)


# --- building blocks (the scenes' people, the catalogue's props) -----------------------------------

## Where a town's gate party stands: at its edge, on the side facing the King's seat (the seat faces its
## nearest town), set down clear of buildings.
func _gate(node: Node3D, centre: Vector3, id: int) -> Vector3:
	var toward := centre + Vector3.FORWARD
	var best := INF
	var seat_id := int(main.bridge.world.get("seatId", -1))
	for other_id in main.towns.towns:
		var o = main.towns.towns[other_id].get("node")
		if int(other_id) == id or not (o is Node3D) or not is_instance_valid(o):
			continue
		var d := centre.distance_to((o as Node3D).global_position)
		if int(other_id) == seat_id and id != seat_id:
			toward = (o as Node3D).global_position
			break
		if d < best:
			best = d
			toward = (o as Node3D).global_position
	var dir := toward - centre
	dir.y = 0.0
	dir = dir.normalized() if dir.length() > 0.001 else Vector3.FORWARD
	var r := float(node.get_meta("edge_r", float(node.get_meta("square_r", 1.2)) * 3.0)) * float((CFG.get("gate", {}) as Dictionary).get("at", 0.95))
	return main.scenes.stand(centre + dir * r)


func _person(root: Node3D, rng: RandomNumberGenerator, role: String, tint: Color, at: Vector3, face: Vector3) -> Node3D:
	var p: Node3D = main.scenes.people.make(rng, role, tint, "adult")
	p.position = main.scenes.stand(at)
	var d := face - p.position
	if Vector2(d.x, d.z).length() > 0.001:
		p.rotation.y = atan2(d.x, d.z)
	root.add_child(p)
	return p


func _play(p: Node3D, clip: String, rng: RandomNumberGenerator) -> void:
	main.scenes.people.play(p, clip, rng.randf_range(0.9, 1.1))


## A prop from the asset catalogue (a component, never a file), on the ground; null if the catalogue has none.
func _prop(root: Node3D, component: String, at: Vector3, yaw: float) -> Node3D:
	var model := Realistic.one(component)
	var n: Node3D = Realistic.make(model) if model != "" else null
	if n == null:
		return null
	n.position = main.scenes.ground(at)
	n.rotation.y = yaw
	root.add_child(n)
	return n


## Burnt: every surface a dull char, the shape still a cart.
func _char(n: Node3D) -> void:
	var burnt := StandardMaterial3D.new()
	burnt.albedo_color = Color(0.07, 0.06, 0.055)
	burnt.roughness = 1.0
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = burnt


## A thin column of dark smoke (the towns' own smoke material, as their unrest uses).
func _smoke(root: Node3D, at: Vector3) -> void:
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
	q.material = Towns.smoke_material(true)
	p.mesh = q
	p.position = main.scenes.ground(at) + Vector3(0, 0.3, 0)
	root.add_child(Particles.to_gpu(p))
