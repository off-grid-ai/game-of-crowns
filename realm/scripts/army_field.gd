extends Node3D
## The massed fight: hosts of regiments (army.gd: one VAT draw and one banner each) meeting in the field or storming
## a breach (the army layer, docs/research/army-layer-2026-11-12.md; Total War's field battle and its storm through
## the breach, Warcraft III's worn colour and density). Who wins is the realm's (Freeciv decides, the bridge
## tells): the beaten side bleeds faster and breaks, the victors never do. Every regiment moves by its Mover on the
## battle's one ground (army_ground.gd), and decides by its mind (a LimboHSM from a data/army.json minds row,
## army_mind.gd). Numbers in data/battle.json field and data/siege.json storm_host (docs/TUNING.md).
##
## A field battle (stage(), from scenes.gd when the bridge tells of a battle, data/battle.json field.play.on or
## --battles=field; the test aid --army-battle=<men per side>[:foe|crown]): both hosts form facing each other, then
## each regiment's mind (minds.regiment) takes it through: archers loose volleys that arc onto the enemy's ranks
## and fell men where they land; the foot advance and stop at sword's length, front ranks cutting, reeling and
## falling, the fallen left where they fell; cavalry swings round the enemy's end and charges his flank; a beaten
## regiment's banner wavers as its pips fall, then it breaks and runs, its men scattering; the victors hold the
## field. In play it is quiet, sized from the men who really fought, ends as Freeciv decided, never moves the camera,
## and is gone field.play.linger seconds after. The test aid prints "BATTLE …" lines and frames itself.
##
## A storm (storm(), raised with every siege beside its assault parties, army_assault.gd, whose breach drives it once
## Freeciv assaults the town): the besiegers in line on the camp side, the holder's drawn up inside the wall
## (minds.storm_regiment). Before the gap opens the besiegers stand ready and loose fire arrows over the wall: they
## arc into the town and now and then a roof catches (fire.gd kindle). Once the gap is open the besiegers' regiments
## march up in waves and queue into it, the front one at blows in the gap, the holder's regiments meeting them on
## the town side, their banners wavering as the fight goes on. When the holder's block breaks, its regiments run
## into the town and the besiegers pour in through the gap and spread out among the houses. Never moves the camera.

const Army := preload("res://scripts/army.gd")
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Mind := preload("res://scripts/army_mind.gd")
const Morale := preload("res://scripts/army_morale.gd")  # panic spreads: a regiment's nerve, on its mind's blackboard
const Ground := preload("res://scripts/army_ground.gd")
const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const Fire := preload("res://scripts/fire.gd")
const F := "battle"  # data/battle.json, its field block

var main: Node
var men := 0
var loser := 1  # the side Freeciv beat: 0 the crown (or the besiegers' foe), 1 the foe
var sides: Array = []  # the two hosts
var clock := -1.0  # seconds since the battle began; below 0 while the hosts deploy
var ground: RefCounted  # army_ground.gd: the battle's one field
var _arrows: MultiMeshInstance3D
var _flights: Array = []  # [from, to, start, flight, arc, on_land (Callable), light (Node3D or null)]
var _rng := RandomNumberGenerator.new()
var _dist := 0.0  # the test aid's lens distance: the town view's (camera.json town_view.dist), or --dist
var _focus := Vector3.ZERO
var _report := 0.0
var _over := false
var _formed := 0.0  # seconds both lines have stood formed
var play := {}  # in play: {at, face, houses: [victors, beaten], kinds: [[types], [types]], men: [victors, beaten], id}; empty for the test aid
var _over_at := -1.0
# The storm (storm() only): the siege's assault (its breach and town) drives it.
var ai: Node
var _queue: Array = []  # besieger regiments sent, in order
var _wave_t := 0.0
var _arrow_t := 0.0
var _said := ""  # the phase last printed (--probe: a headless state proof, silent in play)
var _probe_t := 0.0
var _ready_sides := 0


## Field battles in play, on or off (data/battle.json field.play.on; --battles=field / --battles=skirmish).
static func in_play() -> bool:
	var args := OS.get_cmdline_user_args()
	return args.has("--battles=field") or (bool(Data.value(F, "field.play.on", false)) and not args.has("--battles=skirmish"))


## A battle the bridge told of (its scene: x, y, owner the beaten, victor, men [beaten, victors], kinds [beaten,
## victors]) staged as a field battle at `at` (open ground near it), or null when it can't be: switched off, no
## victors known, or field.play.most already fighting (scenes.gd then plays the small skirmish).
static func stage(m: Node, s: Dictionary, houses: Dictionary, at: Vector3) -> Node:
	if not in_play() or at == Vector3.INF or int(s.get("victor", -1)) < 0 or not (s.get("kinds") is Array):
		return null
	if m.get_tree().get_nodes_in_group(&"field_battles").size() >= int(Data.num(F, "field.play.most", 1)):
		return null
	var kinds: Array = s["kinds"]
	var men_: Array = s.get("men", [200, 200])
	if kinds.size() < 2 or (kinds[1] as Array).is_empty():
		return null
	var b = (load("res://scripts/army_field.gd") as GDScript).new(m, "0")
	var seed := hash(String(s.get("id", "%d,%d,%d" % [int(s["x"]), int(s["y"]), int(s.get("turn", 0))])))
	b.play = {"at": at, "face": float(posmod(seed, 6283)) / 1000.0, "id": seed,
		"houses": [houses.get(int(s["victor"]), {}), houses.get(int(s.get("owner", -1)), {})],
		"kinds": [kinds[1], kinds[0]], "men": [int(men_[1]) if men_.size() > 1 else 200, int(men_[0])]}
	b.add_to_group(&"field_battles")
	m.add_child(b)
	return b


static func k(path: String, fallback: float) -> float:
	return Data.num("siege", "storm_host." + path, fallback)


## Raised beside a siege's assault (army_assault.gd: its breach(), town_at, root): `camp` where the besiegers stand
## (world), `wall` a point on the wall's foot facing them, `town` the town's heart; each side's colours.
static func storm(assault: Node, camp: Vector3, wall: Vector3, town: Vector3, foe_col: Color, held_col: Color) -> Node:
	var b = (load("res://scripts/army_field.gd") as GDScript).new(assault.scenes.get_parent(), "0")
	b.call("_storm_up", assault, camp, wall, town, foe_col, held_col)
	return b


func _init(owner: Node, arg: String) -> void:
	main = owner
	name = "FieldBattle"
	var parts := arg.split(":")
	men = int(parts[0]) if parts[0].is_valid_int() else 3000
	loser = 0 if parts.size() > 1 and parts[1] == "crown" else 1


func _ready() -> void:
	if ai != null:
		return  # a storm: raised by _storm_up
	_rng.seed = 1415
	if not play.is_empty():
		_raise_in_play()
		return
	_dist = lens_distance()
	while main.terrain.width == 0 or not main.terrain.built or (main.bridge.world.get("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5).timeout
	var deep: Array = Data.value(F, "field.frontage", [10, 14])
	var crown: Army = Army.new(main, men, {"side": 0, "shape": "line", "frontage": deep})
	add_child(crown)
	if not crown.mustered:
		await crown.raised
	if crown.rows().is_empty():
		push_error("BATTLE the crown's host could not be raised")
		return
	# The battle turned to fit the ground (batch 8b: the foe formed across a lake): of field.turns bearings round the
	# crown's muster, the one where the foe's line stands most on ground fit for men; the crown's line turns to face it.
	var gap := Data.num(F, "field.gap", 9.0)
	var best_face := crown.facing()
	var best := -1.0
	for i in int(Data.num(F, "field.turns", 12)):
		var a := crown.facing() + TAU * float(i) / Data.num(F, "field.turns", 12)
		var share := crown.ground_share(crown.field() + Vector3(sin(a), 0, cos(a)) * gap, a + PI, crown.extent())
		if share > best + 0.001:
			best = share
			best_face = a
	if absf(angle_difference(best_face, crown.facing())) > 0.01:
		crown.stand_at(crown.field(), best_face)
	var face := crown.facing()
	var fwd := Vector3(sin(face), 0, cos(face))
	var house := _foe_house()
	var foe: Army = Army.new(main, men, {"side": 1, "shape": "line", "frontage": deep, "field": crown.field() + fwd * gap, "face": face + PI, "ground": crown.ground,
		"colour": Heraldry.colour(house, Color(0.72, 0.12, 0.12)) if not house.is_empty() else Color(0.72, 0.12, 0.12), "house": house})
	add_child(foe)
	if not foe.mustered:
		await foe.raised
	sides = [crown, foe]
	ground = crown.ground
	_arrows = _arrow_pool()
	_focus = (crown.field() + foe.field()) * 0.5
	print("BATTLE raised %d a side, %s against %s, the %s beaten; lines %.1f apart, the foe's ground %d%% fit" % [men, "the crown", String(house.get("name", "a rebel host")),
		"crown" if loser == 0 else "foe", crown.field().distance_to(foe.field()), int(best * 100.0)])


## Both sides at the battle's place, facing each other across field.play.gap: the victors (side 0) and the
## beaten (side 1), each a regiment per company that fought (the bridge's men and Freeciv types), quiet.
func _raise_in_play() -> void:
	_rng.seed = int(play["id"])
	loser = 1
	var at: Vector3 = play["at"]
	var face: float = play["face"]
	var fwd := Vector3(sin(face), 0, cos(face))
	var half := Data.num(F, "field.play.gap", 5.0) * 0.5
	var per := int(Data.num(F, "field.play.perCompany", 150))
	var most := int(Data.num(F, "field.play.companies", 12))
	ground = Ground.around(main, at, half + 8.0)
	var made: Array = []
	for i in 2:
		var house: Dictionary = (play["houses"] as Array)[i]
		var colour := Heraldry.colour(house, Color(0.5, 0.17, 0.15)) if not house.is_empty() else Color(0.5, 0.17, 0.15)
		if i == 1 and made.size() == 1 and _alike(colour, (made[0] as Army).battle["colour"]):
			colour = Color(0.22, 0.3, 0.46)  # two houses in like colours: the beaten in steel blue, so the sides read apart
		var side: Army = Army.new(main, 0, {"side": i, "field": at - fwd * half if i == 0 else at + fwd * half, "face": face if i == 0 else face + PI,
			"colour": colour, "house": house, "quiet": true, "shape": "auto", "frontage": Data.value(F, "field.frontage", [10, 14]), "ground": ground})
		var specs: Array = []
		var kinds: Array = (play["kinds"] as Array)[i]
		for j in mini(kinds.size(), most):
			specs.append(side.spec_for(String(kinds[j]), per, -(j + 1)))
		side.battle["specs"] = specs
		add_child(side)
		made.append(side)
	for side in made:
		if not (side as Army).mustered:
			await (side as Army).raised
	sides = made
	_arrows = _arrow_pool()
	_focus = at


static func _alike(a: Color, b: Color) -> bool:
	return absf(wrapf(a.h - b.h, -0.5, 0.5)) < 0.12 and a.s > 0.25 and b.s > 0.25


## The foe's house: the first great house with colours that isn't the crown's (the realm's own, as heraldry draws it).
func _foe_house() -> Dictionary:
	var houses: Variant = main.get("_houses")
	for h in (houses as Dictionary).values() if houses is Dictionary else []:
		if h is Dictionary and not h.get("crown", false) and not h.get("wild", false) and h.has("color"):
			return h
	return {}


# --- The battle begins: every regiment takes its own mind -------------------------------------------------

func _begin() -> void:
	clock = 0.0
	for i in 2:
		for r in (sides[i] as Army).rows():
			_enlist(r, i, "regiment")
	if play.is_empty():
		print("BATTLE begins")


## A regiment joins the fight: its men counted alive, its mind made from the row `kind`.
func _enlist(r: Dictionary, side: int, kind: String) -> void:
	r["state"] = "battle"  # the host leaves it be from here: its mind drives it
	r["side"] = side
	r["army"] = sides[side]
	var alive := PackedByteArray()
	alive.resize(int(r["figures"]))
	alive.fill(1)
	r["alive"] = alive
	r["living"] = int(r["figures"])  # figures standing (one for every 1 / Army.ratio() men)
	r["lost"] = 0  # men fallen
	r["dead_at"] = {}
	r["bleed"] = 0.0
	r["volley_t"] = _rng.randf_range(0.5, 2.0)
	r["swing"] = {}  # front man -> when he next cuts
	r["back"] = {}  # man -> when his one-shot ends and he takes his stance again
	r["foe"] = null
	r["moved"] = false
	var mo: Node = Mover.of(r["node"])
	mo.turn_rate = 1.8
	Mind.make(kind, r, r["node"], self)
	Morale.start(r)


func _send(r: Dictionary, ev: StringName) -> void:
	Mind.send(r, ev)


# --- Each frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ai != null:
		_storm_tick(delta)
		return
	if sides.size() < 2:
		return
	if clock < 0.0:
		# Both lines formed: a breath, then the battle.
		var formed := (sides as Array).all(func(a): return (a as Army).rows().all(func(r): return r["state"] == "rest"))
		if formed:
			_formed += delta
			if _formed >= Data.num(F, "field.start", 2.0):
				_begin()
				for i in 2:
					for r in (sides[i] as Army).rows():
						_send(r, &"volley" if r["role"] == "ranged" else (&"flank" if r["role"] == "cavalry" else &"advance"))
		if play.is_empty():
			_frame(delta)
		return
	clock += delta
	_fly()
	_keep_up()
	_morale(delta)
	if not play.is_empty():
		# In play: the field held a while, then the battle is gone (its dead too); the camera is never moved.
		if _over and _over_at < 0.0:
			_over_at = clock
		if (_over_at >= 0.0 and clock - _over_at > Data.num(F, "field.play.linger", 60.0)) or clock > Data.num(F, "field.longest", 45.0) + 120.0:
			queue_free()
		return
	_frame(delta)
	_report -= delta
	if _report <= 0.0:
		_report = 2.0
		var s := PackedStringArray()
		for i in 2:
			var states := {}
			var left := 0
			for r in (sides[i] as Army).rows():
				states[r["state_name"]] = int(states.get(r["state_name"], 0)) + 1
				left += int(r["living"])
			s.append("%s %d men %s" % ["crown" if i == 0 else "foe", left, str(states)])
		print("BATTLE t=%.0f %s; arrows in flight %d; fps=%d" % [clock, " | ".join(s), _flights.size(), Engine.get_frames_per_second()])


## Every regiment's men brought back to their stance after a one-shot, and its fallen kept where they fell while it
## moves on.
func _keep_up() -> void:
	for a in sides:
		for r in (a as Army).rows():
			if not r.has("alive"):
				continue
			_backs(r)
			if r["moved"] or Mover.of(r["node"]).moving():
				_keep_dead(r)
				r["moved"] = false


## Panic spreads (army_morale.gd): every regiment's nerve moves with what happens about it, its banner wavers with
## it, and a beaten regiment whose nerve goes breaks; after field.longest the beaten side's nerve drains (Freeciv
## decided the day), so the rest go one after another from the most shaken. When none of the beaten stands, the
## victors hold the field.
func _morale(dt: float) -> void:
	var gone := Morale.step(_rows(), dt, loser, [(sides[0] as Army).commander(), (sides[1] as Army).commander()], clock > Data.num(F, "field.longest", 45.0))
	for a in sides:
		for r in (a as Army).rows():
			if r.has("alive") and r["state_name"] != "rout":
				(r["army"] as Army).waver(r, Morale.waver(r))
	for r in gone:
		_send(r, &"break")
	var standing := 0
	for r in (sides[loser] as Army).rows():
		if r["state_name"] != "rout":
			standing += 1
	if standing == 0 and not _over:
		_over = true
		if play.is_empty(): print("BATTLE the %s break; the %s hold the field at t=%.0f" % ["crown's men" if loser == 0 else "foe", "foe" if loser == 0 else "crown's men", clock])
		for r in (sides[1 - loser] as Army).rows():
			_send(r, &"won")


## The lens on where it is decided (the test aid only), low and oblique off the lines' quarter at the square's
## distance: while the lines close, the middle of every regiment in the field; at blows, the line where it breaks.
func _frame(delta: float) -> void:
	if main.rig == null:
		return
	_focus = _focus.lerp(lens_aim(_rows(), loser, _lines_met(), _focus), minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2)))
	var crown: Army = sides[0]
	main.rig.step_floor = _dist if _dist < main.rig.min_distance else 0.0  # the shot's own distance (d4 is d4)
	main.rig.snap(_focus, _dist, crown.facing() + Data.num(F, "field.camera.quarter", 0.9))
	main.rig.tilt = Data.num("army", "camera.tilt", -8.0)
	main.rig.goal_tilt = main.rig.tilt


# --- A regiment's mind (data/army.json minds.regiment) ----------------------------------------------------

func _ready_in(r: Dictionary) -> void:
	_play(r, "ready")


func _walk_in(r: Dictionary) -> void:
	_play(r, "walk")


func _run_in(r: Dictionary) -> void:
	_play(r, "run")


## How far the battle's lens stands (the test aid): the town view's distance (camera.json town_view.dist), so a
## rout reads as a crowd in the square does; --dist=<units> for another.
static func lens_distance() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			return float(a.substr(7))
	return Data.num("camera", "town_view.dist", 6.0)


## Where the battle's lens looks (rows: [side 0's, side 1's]): before the lines meet, the middle of every regiment
## not running; at blows, the beaten regiment whose nerve is lowest (army_morale.gd: where the line breaks next), so
## the rout is framed as it starts and as it runs along the line; once none of the beaten stands, `last` (the lens
## stays where the rout ended).
static func lens_aim(rows: Array, loser: int, met: bool, last: Vector3) -> Vector3:
	if met:
		var next := Morale.shakiest(rows, loser)
		return (next["node"] as Node3D).global_position if not next.is_empty() else last
	var sum := Vector3.ZERO
	var n := 0
	for side in rows:
		for r in side:
			if String(r.get("state_name", "")) != "rout":
				sum += (r["node"] as Node3D).global_position
				n += 1
	return sum / n if n > 0 else last


## How many of the beaten side's regiments have broken (autoplay's `rout` step waits on it, so a film starts at
## the first break).
func routed() -> int:
	if sides.size() < 2:
		return 0
	return (sides[loser] as Army).rows().filter(func(r): return String(r.get("state_name", "")) == "rout").size()


## Both hosts' regiments, [side 0's, side 1's] (what army_morale.gd reads).
func _rows() -> Array:
	return [(sides[0] as Army).rows(), (sides[1] as Army).rows()]


func _may_break(r: Dictionary) -> bool:
	return int(r["side"]) == loser  # the victors never break


func _may_hold(r: Dictionary) -> bool:
	return int(r["side"]) != loser


## Archers: a volley every field.volley.every seconds at the nearest enemy regiment, while the lines are apart.
func _volley(r: Dictionary, dt: float) -> void:
	var foe := _nearest_foe(r)
	if foe.is_empty():
		return
	_face_toward(r, (foe["node"] as Node3D).global_position, dt)
	if _front_gap(r, foe) < Data.num(F, "field.volley.until", 3.0) or _lines_met():
		return  # the lines are at blows: no shooting into the press
	r["volley_t"] = float(r["volley_t"]) - dt
	if float(r["volley_t"]) > 0.0:
		return
	var every: Array = Data.value(F, "field.volley.every", [2.5, 3.6])
	r["volley_t"] = _rng.randf_range(float(every[0]), float(every[1]))
	var army: Army = r["army"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	var shots := int(Data.num(F, "field.volley.arrows", 70))
	var kills: Array = Data.value(F, "field.volley.kills", [1, 4])
	var fells := _rng.randi_range(int(kills[0]), int(kills[1])) * (2 if int(foe["side"]) == loser else 1)
	var flight := Data.num(F, "field.volley.flight", 1.7)
	var man := Data.num("army", "man", 0.22)
	for i in shots:
		var s := _rng.randi() % local.size()
		if alive[s] == 0:
			continue
		if _rng.randf() < 0.3:  # some of them draw and loose where we can see it
			vat.update_instance_track(s, army.track(r, "attack"))
			(r["back"] as Dictionary)[s] = clock + 0.9
		var from := node.to_global(local[s]) + Vector3(0, man * 0.8, 0)
		var fnode: Node3D = foe["node"]
		var to := fnode.to_global(Vector3(_rng.randf_range(-0.5, 0.5) * float(foe["w"]), 0.0, _rng.randf_range(-0.5, 0.5) * float(foe["d"])))
		to.y = main.terrain.height_at(to.x, to.z)
		var lands := i < fells
		_loose(from, to, clock + _rng.randf_range(0.0, 0.5), flight * _rng.randf_range(0.9, 1.1), Data.num(F, "field.volley.arc", 0.45),
			func(): if lands and foe.get("state_name", "") != "rout": _fell(foe, 1, false))


## Foot: forward until its front is at sword's length from the nearest enemy's front; then both fight.
func _advance(r: Dictionary, _dt: float) -> void:
	var foe := _nearest_foe(r)
	if foe.is_empty():
		return
	var at: Vector3 = (r["node"] as Node3D).global_position
	var to: Vector3 = (foe["node"] as Node3D).global_position
	var gap := _front_gap(r, foe)
	var contact := Data.num(F, "field.contact", 0.12)
	if gap <= contact:
		r["foe"] = foe
		_send(r, &"engage")
		if foe.get("state_name", "") in ["stand", "volley", "advance"]:
			foe["foe"] = r
			_send(foe, &"engage")
		return
	var way := Vector3(to.x - at.x, 0, to.z - at.z).normalized()
	Mover.of(r["node"]).toward(at + way * (gap - contact), Data.num(F, "field.advance", 0.12), way)


## At blows: the front ranks cut and reel, men fall from the front, the rest stand ready behind; the front surges a
## little back and forth. It bleeds by the realm's outcome (field.fight.loss), harder when flanked.
func _fight(r: Dictionary, dt: float) -> void:
	var foe: Variant = r["foe"]
	if foe == null or (foe as Dictionary).get("state_name", "") == "rout" or int((foe as Dictionary)["living"]) == 0:
		if _nearest_foe(r).is_empty():
			return
		r["foe"] = null
		_send(r, &"advance")  # its foe broke: on to the next
		return
	var army: Army = r["army"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var front := _front_men(r)
	var swing: Dictionary = r["swing"]
	var back: Dictionary = r["back"]
	var range_s: Array = Data.value(F, "field.fight.swing", [0.7, 1.8])
	var hit_odds := Data.num(F, "field.fight.hitOdds", 0.2)
	var block_odds := Data.num(F, "field.fight.blockOdds", 0.25)
	for s in front:
		if not swing.has(s):
			swing[s] = clock + _rng.randf_range(0.0, float(range_s[1]))
		if clock >= float(swing[s]):
			swing[s] = clock + _rng.randf_range(float(range_s[0]), float(range_s[1]))
			var roll := _rng.randf()
			vat.update_instance_track(s, army.track(r, "hit" if roll < hit_odds else ("block" if roll < hit_odds + block_odds else "attack")))
			back[s] = clock + 0.9
	# The front surges: each front man a little forward and back on his own beat (his place in the formation).
	var surge := Data.num(F, "field.fight.surge", 0.02)
	var local: PackedVector3Array = r["local"]
	var line: PackedVector3Array = r["line"]["at"]
	for s in front:
		var v := local[s]
		v.z = line[s].z + sin(clock * 2.1 + float(s) * 1.7) * surge
		local[s] = v
	r["local"] = local
	r["moved"] = true
	# Its losses: the realm's outcome sets the rate; a flanked regiment bleeds harder.
	var loss: Dictionary = Data.value(F, "field.fight.loss", {"beaten": 2.4, "victors": 0.9})
	var rate := float(loss.get("beaten" if int(r["side"]) == loser else "victors", 1.0))
	if r.get("flanked", false):
		rate *= Data.num(F, "field.fight.flanked", 1.6)
	r["bleed"] = float(r["bleed"]) + rate * dt
	if float(r["bleed"]) >= 1.0:
		var n := int(r["bleed"])
		r["bleed"] = float(r["bleed"]) - n
		_fell(r, n, true)


## Horse: round the end of the enemy's line nearest its own wing, wide of it (field.cavalry.wide), then in on his
## flank.
func _flank(r: Dictionary, _dt: float) -> void:
	var foe_army: Army = sides[1 - int(r["side"])]
	var rows := foe_army.rows().filter(func(x): return x.get("state_name", "") != "rout" and int(x.get("living", 1)) > 0)
	if rows.is_empty():
		return
	var node: Node3D = r["node"]
	var face := foe_army.facing()
	var right := Vector3(cos(face), 0, -sin(face))
	var fwd := Vector3(sin(face), 0, cos(face))
	var mid := foe_army.field()
	var side_sign := signf((node.global_position - mid).dot(right))
	if side_sign == 0.0:
		side_sign = 1.0
	var end: Dictionary = rows[0]
	for x in rows:
		if ((x["node"] as Node3D).global_position - mid).dot(right) * side_sign > ((end["node"] as Node3D).global_position - mid).dot(right) * side_sign:
			end = x
	var end_at: Vector3 = (end["node"] as Node3D).global_position
	var goal := end_at + right * side_sign * (float(end["w"]) * 0.5 + Data.num(F, "field.cavalry.wide", 2.2)) - fwd * Data.num(F, "field.cavalry.behind", 1.0)
	r["target"] = end
	if Vector2(goal.x - node.global_position.x, goal.z - node.global_position.z).length() <= 0.05:
		_send(r, &"charge")
		return
	Mover.of(node).toward(goal, Data.num(F, "field.cavalry.ride", 0.3))


## In on the flank at the charge, into the side of the regiment at the enemy's end; it fights there, and the
## regiment it hits is flanked (bleeds harder).
func _charge(r: Dictionary, _dt: float) -> void:
	var t: Variant = r.get("target")
	if t == null or (t as Dictionary).get("state_name", "") == "rout":
		_send(r, &"flank")
		return
	var target: Dictionary = t
	var tn: Node3D = target["node"]
	var at: Vector3 = (r["node"] as Node3D).global_position
	var reach := float(target["w"]) * 0.5 + float(r["d"]) * 0.5 + Data.num(F, "field.contact", 0.12)
	if Vector2(at.x - tn.global_position.x, at.z - tn.global_position.z).length() <= reach:
		r["foe"] = target
		target["flanked"] = true
		_send(r, &"engage")
		return
	Mover.of(r["node"]).toward(tn.global_position, Data.num(F, "field.cavalry.charge", 0.55))


## It breaks: turns its back on the enemy, runs; its banner wavers its last.
func _break(r: Dictionary) -> void:
	var army: Army = r["army"]
	army.waver(r, 1.0)
	Morale.broke(_rows(), r)  # those beside it are shaken: the chain
	army.turn(r, float(r["yaw"]) + PI)
	# The dead lie where they fell; the living face the other way in their places.
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	for s in local.size():
		if alive[s] == 1:
			local[s] = Vector3(-local[s].x, 0.0, -local[s].z)
	r["local"] = local
	r["moved"] = true
	var vat: VATMultiMeshInstance3D = r["vat"]
	var run := army.track(r, "run")
	for s in local.size():
		if alive[s] == 1:
			vat.update_instance_track(s, run)
			vat.update_instance_animation_offset(s, _rng.randf())
	r["ran"] = 0.0
	if play.is_empty() and ai == null: print("BATTLE t=%.0f a %s regiment breaks at %d%%" % [clock, "crown" if int(r["side"]) == 0 else "foe", int(float(r["strength"]) * 100.0)])


## Running: away from the field at field.run, each man drifting from his place (field.scatter), gone after
## field.fade.
func _run(r: Dictionary, dt: float) -> void:
	var node: Node3D = r["node"]
	var fwd := node.global_transform.basis.z.normalized()
	Mover.of(node).toward(node.global_position + fwd * 0.5, Data.num(F, "field.run", 0.42), fwd)
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	var scatter := Data.num(F, "field.scatter", 0.05)
	for s in local.size():
		if alive[s] == 1:
			local[s] += Vector3(sin(float(s) * 12.9898) * scatter, 0.0, absf(cos(float(s) * 78.233)) * scatter * 0.6) * dt
	r["local"] = local
	r["moved"] = true
	r["ran"] = float(r["ran"]) + dt
	if float(r["ran"]) > Data.num(F, "field.fade", 7.0) and not r.get("gone", false):
		r["gone"] = true
		var vat: VATMultiMeshInstance3D = r["vat"]
		for s in local.size():
			if alive[s] == 1:
				vat.fade_out_instance(s, 1.0, _rng.randf_range(0.0, 1.5))
		(r["banner"] as Node3D).visible = false


## The victors hold the field: they stand where they are at ease, ready.
func _hold(r: Dictionary) -> void:
	(r["army"] as Army).waver(r, 0.0)
	_play(r, "rest")
	r["foe"] = null


# --- Men falling and the fallen ---------------------------------------------------------------------------

## n men of a regiment fall: from its front at blows, anywhere under arrows. A figure stands for 1 / Army.ratio()
## men, so one goes down for each that many fallen: it plays his death and stays where he fell; the regiment's
## strength (its banner's pips) is its figures standing over its figures.
func _fell(r: Dictionary, men: int, front: bool) -> void:
	r["lost"] = int(r.get("lost", 0)) + men
	var n := int(floor(float(r["lost"]) * Army.ratio() + 0.0001)) - (int(r["figures"]) - int(r["living"]))  # figures now due to fall
	var alive: PackedByteArray = r["alive"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var pool: Array = _front_men(r) if front else []
	for i in n:
		if int(r["living"]) <= 0:
			break
		var s := -1
		if not pool.is_empty():
			s = int(pool.pop_at(_rng.randi() % pool.size()))
		else:
			for tries in 12:
				var c := _rng.randi() % alive.size()
				if alive[c] == 1:
					s = c
					break
		if s < 0 or alive[s] == 0:
			continue
		alive[s] = 0
		r["living"] = int(r["living"]) - 1
		vat.update_instance_track(s, army.track(r, "death"))
		(r["dead_at"] as Dictionary)[s] = node.to_global(local[s])
		(r["swing"] as Dictionary).erase(s)
		(r["back"] as Dictionary).erase(s)
	r["alive"] = alive
	army.set_strength(int(r["id"]), float(r["living"]) / maxf(float(r["figures"]), 1.0))
	# Its men falling shake it, and those of its side near where they fell (panic spreads, army_morale.gd).
	var at: Vector3 = node.global_position  # under arrows, anywhere in it
	if front:
		at = node.to_global(Vector3(0.0, 0.0, float(r["d"]) * 0.5))  # at blows, its front rank (+Z its front)
	Morale.fell(_rows(), r, men, at)


## The fallen stay where they fell while their regiment moves on: their places are put back under them.
func _keep_dead(r: Dictionary) -> void:
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var dead: Dictionary = r["dead_at"]
	for s in dead:
		var p := node.to_local(dead[s])
		local[s] = Vector3(p.x, 0.0, p.z)
	r["local"] = local
	(r["army"] as Army).dress(r)


## Every living man of a regiment plays a role's clip, each at his own point in it (marching men nearly in step);
## the fallen keep lying where they are.
func _play(r: Dictionary, role: String) -> void:
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var alive: PackedByteArray = r.get("alive", PackedByteArray())
	var step := Data.num("army", "jitter.step", 0.06)
	var phase := _rng.randf()
	for s in vat.multimesh.instance_count:
		if not alive.is_empty() and alive[s] == 0:
			continue
		vat.update_instance_track(s, army.track(r, role))
		vat.update_instance_animation_offset(s, fposmod(phase + _rng.randf_range(-step, step), 1.0) if role in ["walk", "run"] else _rng.randf())


## A man whose cut or reel has played takes his stance again.
func _backs(r: Dictionary) -> void:
	var back: Dictionary = r["back"]
	if back.is_empty():
		return
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var alive: PackedByteArray = r["alive"]
	var ready := army.track(r, "ready")
	for s in back.keys():
		if clock >= float(back[s]):
			back.erase(s)
			if alive[s] == 1 and r.get("state_name", "") != "rout":
				vat.update_instance_track(s, ready)


# --- Where things stand -----------------------------------------------------------------------------------

## The living men of its front ranks (field.fight.ranks), by their place in the line: the front is +Z.
func _front_men(r: Dictionary) -> Array:
	var alive: PackedByteArray = r["alive"]
	var line: PackedVector3Array = r["line"]["at"]
	var files := int(r["line"].get("files", 20))
	var ranks := int(Data.num(F, "field.fight.ranks", 2))
	var order: Array = []
	for s in alive.size():
		if alive[s] == 1:
			order.append(s)
	order.sort_custom(func(a, b): return line[a].z > line[b].z)
	return order.slice(0, files * ranks)


## The nearest enemy regiment still in the field, or {}.
func _nearest_foe(r: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	var at: Vector3 = (r["node"] as Node3D).global_position
	for x in (sides[1 - int(r["side"])] as Army).rows():
		if x.get("state_name", "") == "rout" or int(x.get("living", 1)) <= 0:
			continue
		var d := at.distance_squared_to((x["node"] as Node3D).global_position)
		if d < bd:
			bd = d
			best = x
	return best


## The gap between two regiments' fronts, along the first's facing.
func _front_gap(r: Dictionary, foe: Dictionary) -> float:
	var a: Node3D = r["node"]
	var b: Node3D = foe["node"]
	var fwd := a.global_transform.basis.z.normalized()
	var mine := a.global_position + fwd * float(r["d"]) * 0.5
	var theirs := b.global_position + b.global_transform.basis.z.normalized() * float(foe["d"]) * 0.5
	return (theirs - mine).dot(fwd)


func _lines_met() -> bool:
	for a in sides:
		for r in (a as Army).rows():
			if r.get("state_name", "") == "fight":
				return true
	return false


## Turns a regiment toward a point where it stands, a little each frame.
func _face_toward(r: Dictionary, to: Vector3, dt: float) -> void:
	var at: Vector3 = (r["node"] as Node3D).global_position
	var yaw := lerp_angle(float(r["yaw"]), atan2(to.x - at.x, to.z - at.z), minf(1.0, dt * 1.5))
	if absf(angle_difference(yaw, float(r["yaw"]))) > 0.0005:
		(r["army"] as Army).turn(r, yaw)
		r["moved"] = true


# --- Arrows in the air ------------------------------------------------------------------------------------

## An arrow loosed from `from` at `to` (world), leaving at `start` (the battle's clock) for `flight` seconds on an arc
## `arc` high over its length; `on_land` when it comes down. Fire arrows carry a flame (`light`).
func _loose(from: Vector3, to: Vector3, start: float, flight: float, arc: float, on_land: Callable, light: Node3D = null) -> void:
	_flights.append([from, to, start, flight, arc, on_land, light])


func _arrow_pool() -> MultiMeshInstance3D:
	var shaft := BoxMesh.new()
	shaft.size = Vector3(0.006, 0.006, 0.09)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.24, 0.17)
	m.roughness = 0.9
	shaft.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shaft
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


## Every arrow in the air along its arc, pointing the way it flies (its flame with it); landed, it does what it does.
func _fly() -> void:
	var mm := _arrows.multimesh
	var shown: Array = []
	for i in range(_flights.size() - 1, -1, -1):
		var f: Array = _flights[i]
		var t := (clock - float(f[2])) / float(f[3])
		if t < 0.0:
			continue
		if t >= 1.0:
			(f[5] as Callable).call()
			if f[6] != null and is_instance_valid(f[6]):
				(f[6] as Node3D).queue_free()
			_flights.remove_at(i)
			continue
		var p := _on_arc(f, t)
		var q := _on_arc(f, minf(t + 0.02, 1.0))
		shown.append(Transform3D(Basis.looking_at(q - p if (q - p).length() > 0.0001 else Vector3.FORWARD, Vector3.UP), p))
		if f[6] != null and is_instance_valid(f[6]):
			(f[6] as Node3D).global_position = p  # the flame rides its arrow (an effect, not a traveller)
	mm.instance_count = shown.size()
	for i in shown.size():
		mm.set_instance_transform(i, shown[i])


func _on_arc(f: Array, t: float) -> Vector3:
	var a: Vector3 = f[0]
	var b: Vector3 = f[1]
	var top := a.distance_to(b) * float(f[4])
	return a.lerp(b, t) + Vector3(0, top * 4.0 * t * (1.0 - t), 0)


# --- The storm ---------------------------------------------------------------------------------------------

func _storm_up(assault: Node, camp: Vector3, wall: Vector3, town: Vector3, foe_col: Color, held_col: Color) -> void:
	ai = assault
	name = "SiegeStorm"
	_rng.seed = hash(town)
	clock = 0.0
	ground = assault.ground
	ai.root.add_child(self)
	_arrows = _arrow_pool()
	if OS.get_cmdline_user_args().has("--probe"):
		print("STORM begun: besiegers by %s, the wall at %s, the town at %s" % [str(camp), str(wall), str(town)])
	var out := Vector3(camp.x - town.x, 0, camp.z - town.z).normalized()
	var counts: Array = Data.value("siege", "storm_host.men", [800, 300])
	var face_in := atan2(-out.x, -out.z)  # the soldier faces +Z: toward the town
	var face_out := atan2(out.x, out.z)
	var inside: Vector3 = wall - out * k("holders_back", 0.9)
	for i in 2:
		var side := {"side": i, "field": camp if i == 0 else inside, "face": face_in if i == 0 else face_out, "ground": ground,
			"colour": foe_col if i == 0 else held_col, "house": {}, "shape": "line", "quiet": true}
		var a := Army.new(main, int(counts[i]), side)
		# Connected before it enters the tree: with the land and the towns already up (a siege always is), its _ready
		# runs straight through inside add_child and says it's raised before anyone could be listening.
		a.raised.connect(func():
			for r in a.rows():
				_enlist(r, i, "storm_regiment")
				r["goal"] = (r["node"] as Node3D).global_position
			_ready_sides += 1
			if OS.get_cmdline_user_args().has("--probe"):
				print("STORM side %d raised: %d regiments" % [i, a.rows().size()]))
		sides.append(a)
		add_child(a)


func _storm_tick(delta: float) -> void:
	if _ready_sides < 2 or not is_instance_valid(ai):
		return
	clock += delta
	var st: Dictionary = ai.breach()
	var phase := String(st.get("phase", "")) if not st.is_empty() else "wall"
	_probe(phase, st, delta)
	if phase == "wall":
		_fire_arrows(delta)
	elif phase == "hold":
		_fire_arrows(delta)
		_waves(st, delta)
		_hold_line(st)
	else:
		_pour_in(st)
	_fly()
	_keep_up()


## A storm regiment's mind (data/army.json minds.storm_regiment): standing it takes its stance, facing its way;
## marching it goes to its goal at its pace by its Mover, and stands there.
func _storm_stand(r: Dictionary) -> void:
	_play(r, String(r.get("stance", "ready" if int(r["side"]) == 0 else "rest")))
	if r.has("face"):
		(r["army"] as Army).turn(r, float(r["face"]))


func _storm_march(r: Dictionary) -> void:
	_play(r, "run" if r.get("running", false) else "walk")
	var mo: Node = Mover.of(r["node"])
	mo.speed = float(r["pace"])
	mo.go(r["goal"], func(): _send(r, &"there"))


## Sends a storm regiment to `goal` (world), at a run or a walk; there it takes `stance`, facing `face`.
func _go(r: Dictionary, goal: Vector3, run: bool, stance: String, face: float) -> void:
	r["goal"] = goal
	r["pace"] = k("run" if run else "walk", 0.5 if run else 0.22)
	r["running"] = run
	r["stance"] = stance
	r["face"] = face
	if r.get("state_name", "") == "march":
		_storm_march(r)  # a new goal on the way
	else:
		_send(r, &"march")


## The gap open: a besieger regiment sent every wave_s, each queueing into the gap behind the one before; the front
## one at blows in the gap.
func _waves(st: Dictionary, dt: float) -> void:
	_wave_t -= dt
	var gap: Vector3 = st["gap"]
	var inward: Vector3 = st["inward"]
	var across: Vector3 = st["across"]
	if _wave_t <= 0.0:
		_wave_t = k("wave_s", 6.0)
		for r in (sides[0] as Army).rows():
			if not _queue.has(r):
				_queue.append(r)
				break
	var face := atan2(inward.x, inward.z)
	for i in _queue.size():
		var r: Dictionary = _queue[i]
		var goal := gap - inward * (k("front", 0.1) + i * k("queue", 0.35)) + across * (_rng.randf_range(-0.05, 0.05) if i > 0 else 0.0)
		if (r["goal"] as Vector3).distance_to(goal) > 0.05:
			_go(r, goal, true, "attack" if i == 0 else "ready", face)


## The holder's regiments meet them on the town side of the gap, their banners wavering more as the fight goes on
## and the block thins (the assault's holders standing).
func _hold_line(st: Dictionary) -> void:
	var gap: Vector3 = st["gap"]
	var inward: Vector3 = st["inward"]
	var across: Vector3 = st["across"]
	var face := atan2(-inward.x, -inward.z)
	var rows: Array = (sides[1] as Army).rows()
	var standing := (st["men"] as Array).filter(func(d): return d["alive"]).size()
	var full := maxf(1.0, (st["men"] as Array).size())
	for i in rows.size():
		var r: Dictionary = rows[i]
		var goal := gap + inward * (k("holders_at", 0.35) + (i / 3) * 0.3) + across * ((i % 3) - 1) * 0.3
		if (r["goal"] as Vector3).distance_to(goal) > 0.05:
			_go(r, goal, false, "attack" if i < 3 else "block", face)
		(sides[1] as Army).waver(r, 1.0 - standing / full)


## The gap taken: the holder's regiments break and run into the town, the besiegers pour through and spread out
## among the houses.
func _pour_in(st: Dictionary) -> void:
	if st.is_empty():
		return
	var gap: Vector3 = st["gap"]
	var inward: Vector3 = st["inward"]
	var town: Vector3 = ai.town_at if ai.town_at != Vector3.INF else gap + inward * 2.0
	for r in (sides[1] as Army).rows():
		if not r.get("broke", false):
			r["broke"] = true
			(sides[1] as Army).waver(r, 1.0)
			var away := town + Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * k("spread", 1.2)
			_go(r, away, true, "rest", float(r["yaw"]))
	var i := 0
	for r in (sides[0] as Army).rows():
		if not r.get("in", false):
			r["in"] = true
			var into := gap + inward * (0.6 + 0.4 * (i % 4)) + Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * k("spread", 1.2) * 0.6
			_go(r, into, true, "ready", atan2(inward.x, inward.z))
		i += 1


## The besiegers' archers loose fire arrows over the wall into the town; now and then a roof catches.
func _fire_arrows(dt: float) -> void:
	_arrow_t -= dt
	var burning := 0
	for f in _flights:
		if f[6] != null:
			burning += 1
	if _arrow_t > 0.0 or burning >= int(k("arrows.most_flying", 8)):
		return
	_arrow_t = k("arrows.every_s", 1.2) * _rng.randf_range(0.6, 1.4)
	var rows: Array = (sides[0] as Army).rows()
	if rows.is_empty() or ai.town_at == Vector3.INF:
		return
	var from: Vector3 = (rows[_rng.randi() % rows.size()]["node"] as Node3D).global_position + Vector3(0, 0.2, 0)
	var spread := k("arrows.spread", 1.4)
	var to: Vector3 = ai.town_at + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
	to.y = main.terrain.height_at(to.x, to.z) + 0.2
	var flame := Node3D.new()
	add_child(flame)
	flame.global_position = from
	Fire.hearth(flame, Vector3.ZERO)  # the burning rag on its head: fire.gd's small flames
	_loose(from, to, clock, from.distance_to(to) / k("arrows.speed", 3.0), 0.3, func():
		if _rng.randf() < k("arrows.catch", 0.18) and _burning_now() < int(k("arrows.most_burning", 6)):
			Fire.kindle(to), flame)


func _burning_now() -> int:
	return Fire.live._burning.size() if Fire.live else 0


## --probe only: the storm's state as it goes (phase changes, and every 10 s the men in the gap and through it).
func _probe(phase: String, st: Dictionary, dt: float) -> void:
	if not OS.get_cmdline_user_args().has("--probe"):
		return
	_probe_t -= dt
	if phase == _said and _probe_t > 0.0:
		return
	_probe_t = 10.0
	_said = phase
	var gap: Vector3 = st.get("gap", Vector3.ZERO)
	var inward: Vector3 = st.get("inward", Vector3.ZERO)
	var through := 0
	var at_gap := 0
	for r in (sides[0] as Army).rows():
		var p: Vector3 = (r["node"] as Node3D).global_position
		var d := (p - gap).dot(inward) if not st.is_empty() else -9.0
		if d > 0.2:
			through += int(r["men"])
		elif d > -0.6:
			at_gap += int(r["men"])
	var defenders := (st.get("men", []) as Array).filter(func(x): return x["alive"]).size()
	print("STORM t=%.0f phase=%s besiegers_at_gap=%d through=%d gap_defenders=%d regiments_sent=%d" % [clock, phase, at_gap, through, defenders, _queue.size()])
