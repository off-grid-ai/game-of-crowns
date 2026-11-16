extends Node3D
## The massed fight: hosts of regiments (army.gd: one VAT draw and one banner each) meeting in the field or storming
## a breach (the army layer, docs/research/army-layer-2026-11-12.md; Total War's field battle and its storm through
## the breach, Warcraft III's worn colour and density). Who wins is the realm's (Freeciv decides, the bridge
## tells): the beaten side bleeds faster and breaks, the victors never do. Every regiment moves by its Mover on the
## realm's host map (nav_world.gd: round water and houses, every other block carved out), and decides by its mind (a LimboHSM from a data/army.json minds row,
## army_mind.gd). Numbers in data/battle.json field and data/siege.json storm_host (docs/TUNING.md).
##
## A field battle (stage(), from scenes.gd whenever the bridge tells of a battle, the one way a battle is fought; the test aid --army-battle=<men per side>[:foe|crown]): both hosts form facing each other, then
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

const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const Army := preload("res://scripts/army.gd")
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Mind := preload("res://scripts/army_mind.gd")
const Morale := preload("res://scripts/army_morale.gd")  # panic spreads: a regiment's nerve, on its mind's blackboard
const Footing := preload("res://scripts/ground.gd")  # the one owner of where a body may stand: a regiment stepping out asks it
const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const Awareness := preload("res://scripts/awareness.gd")  # the season's length: the field keeps its dead a season
const Fire := preload("res://scripts/fire.gd")
const F := "battle"  # data/battle.json, its field block
const Formation := preload("res://scripts/army_formation.gd")  # a regiment's formation templates (horse: the wedge)

var main: Node
var men := 0
var loser := 1  # the side Freeciv beat: 0 the crown (or the besiegers' foe), 1 the foe
var sides: Array = []  # the two hosts
var clock := -1.0  # seconds since the battle began; below 0 while the hosts deploy
var _arrows: MultiMeshInstance3D
var _flights: Array = []  # [from, to, start, flight, arc, on_land (Callable), light (Node3D or null)]
var _rng := RandomNumberGenerator.new()
var _dist := 0.0  # the test aid's lens distance: the town view's (camera.json town_view.dist), or --dist
var _focus := Vector3.ZERO
var _yaw := 0.0  # the battle lens's heading (lens_yaw, followed)
var _yawed := false
var _near := 1.0  # the battle lens's distance as a share of _dist: field.camera.close at blows, eased in
var _report := 0.0
var _over := false
var _formed := 0.0  # seconds both lines have stood formed
var play := {}  # in play: {at, face, houses: [victors, beaten], kinds: [[types], [types]], men: [victors, beaten], id}; empty for the test aid
var _over_at := -1.0
var _after := false  # the battle is over and gone: its fallen and dropped standards lie on the field (_aftermath)
# The storm (storm() only): the siege's assault (its breach and town) drives it.
var ai: Node
var _queue: Array = []  # besieger regiments sent, in order
var _wave_t := 0.0
var _arrow_t := 0.0
var _breach_lit := false  # the houses behind the first breach set alight (fire.gd breach_fires)
var _said := ""  # the phase last printed (--probe: a headless state proof, silent in play)
var _probe_t := 0.0
var _ready_sides := 0


## A battle the bridge told of (its scene: x, y, owner the beaten, victor, men [beaten, victors], kinds [beaten,
## victors]) staged as a field battle at `at` (open ground near it), or null when it can't be: switched off, no
## victors known, or field.play.most already fighting (the battle is then told, not shown).
static func stage(m: Node, s: Dictionary, houses: Dictionary, at: Vector3) -> Node:
	if at == Vector3.INF or int(s.get("victor", -1)) < 0 or not (s.get("kinds") is Array):
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
	while main.terrain.width == 0 or not main.terrain.built or (Army._rec("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5, false).timeout
	var crown: Army = Army.new(main, men, {"side": 0, "shape": "line"})
	add_child(crown)
	if not crown.mustered:
		await crown.raised
	if crown.rows().is_empty():
		push_error("BATTLE the crown's host could not be raised")
		return
	var gap := Data.num(F, "field.gap", 9.0)
	var best := _turn_to_ground(crown, gap)
	var face := crown.facing()
	var fwd := Vector3(sin(face), 0, cos(face))
	var house := _foe_house()
	var foe_col := Heraldry.colour(house, Color(0.72, 0.12, 0.12)) if not house.is_empty() else Color(0.72, 0.12, 0.12)
	var foe_worn := apart(Heraldry.field_colour(house, foe_col) if not house.is_empty() else foe_col, crown.rows()[0]["worn"])
	var foe: Army = Army.new(main, men, {"side": 1, "shape": "line", "field": crown.field() + fwd * gap, "face": face + PI,
		"colour": foe_col, "worn": foe_worn, "house": house})
	add_child(foe)
	if not foe.mustered:
		await foe.raised
	sides = [crown, foe]
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
	var gap := Data.num(F, "field.play.gap", 5.0)
	var per := int(Data.num(F, "field.play.perCompany", 150))
	var most := int(Data.num(F, "field.play.companies", 12))
	var made: Array = []
	for i in 2:
		var house: Dictionary = (play["houses"] as Array)[i]
		var colour := Heraldry.colour(house, Color(0.5, 0.17, 0.15)) if not house.is_empty() else Color(0.5, 0.17, 0.15)
		var worn := Heraldry.field_colour(house, colour) if not house.is_empty() else colour
		if i == 1 and made.size() == 1:
			worn = apart(worn, (made[0] as Army).battle["worn"])  # two houses alike: the beaten in a tone that reads apart
		# The victors form first at the battle's place, turned to the ground; the beaten form facing them across the gap.
		var face: float = play["face"] if i == 0 else (made[0] as Army).facing() + PI
		var field: Vector3 = at if i == 0 else (made[0] as Army).field() - Vector3(sin(face), 0, cos(face)) * gap
		var side: Army = Army.new(main, 0, {"side": i, "field": field, "face": face, "colour": colour, "worn": worn, "house": house, "quiet": true,
			"shape": "line"})
		var specs: Array = []
		var kinds: Array = (play["kinds"] as Array)[i]
		for j in mini(kinds.size(), most):
			specs.append(side.spec_for(String(kinds[j]), per, -(j + 1)))
		side.battle["specs"] = specs
		add_child(side)
		made.append(side)
		if not side.mustered:
			await side.raised
		if i == 0:
			_turn_to_ground(side, gap)
	sides = made
	_arrows = _arrow_pool()
	_focus = ((made[0] as Army).field() + (made[1] as Army).field()) * 0.5


## The battle turned to fit the ground (batch 8b: the foe formed across a lake): of field.turns bearings round the
## victors' line, the one where the other line, `gap` ahead, stands most on ground fit for men; the line turns to
## face it. Returns that share of fit ground.
func _turn_to_ground(crown: Army, gap: float) -> float:
	var best_face := crown.facing()
	var best := -1.0
	var turns := Data.num(F, "field.turns", 12)
	for i in int(turns):
		var a := crown.facing() + TAU * float(i) / turns
		var share := crown.ground_share(crown.field() + Vector3(sin(a), 0, cos(a)) * gap, a + PI, crown.extent())
		if share > best + 0.001:
			best = share
			best_face = a
	if absf(angle_difference(best_face, crown.facing())) > 0.01:
		crown.stand_at(crown.field(), best_face)
	return best


## Whether two sides' worn colours read alike (Mac is colour-blind: lightness carries the difference, never hue alone):
## their lightness closer than army.json sides.lightness, or their hue within sides.hue, pale or not (a pale grey-blue
## beside a blue read as one host).
static func _alike(a: Color, b: Color) -> bool:
	var k: Dictionary = Data.value("army", "sides", {})
	return absf(a.get_luminance() - b.get_luminance()) < float(k.get("lightness", 0.3)) \
		or absf(wrapf(a.h - b.h, -0.5, 0.5)) < float(k.get("hue", 0.08))


## The colour a side wears against the other's `other`: its own, unless the two read alike; then of army.json
## sides.tones (a near-white and a near-black tabard) the one furthest in lightness from the other's.
static func apart(own: Color, other: Color) -> Color:
	if not _alike(own, other):
		return own
	var best := own
	var far := -1.0
	for t in (Data.value("army", "sides.tones", [[0.85, 0.83, 0.76], [0.14, 0.13, 0.12]]) as Array):
		var c := Data.colour(t, own)
		var d := absf(c.get_luminance() - other.get_luminance())
		if d > far:
			far = d
			best = c
	return best


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
	preload("res://scripts/on_screen.gd").keep_on(r["node"])  # it fights on whether seen or not (field_clash_probe)
	Mind.make(kind, r, r["node"], self)
	Morale.start(r)


func _send(r: Dictionary, ev: StringName) -> void:
	Mind.send(r, ev)


# --- Each frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("army_field", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	if ai != null:
		_storm_tick(delta)
		return
	if sides.size() < 2 or _after:
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
			_aftermath()
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


## The battle is over and gone (casebook, War and sieges: the field remembers): the living march off (they fade), the
## fallen lie where they fell, and the standard of every regiment that broke lies in the grass where it broke, for
## field.play.aftermath seasons; then the field is clear.
func _aftermath() -> void:
	_after = true
	remove_from_group(&"field_battles")  # no longer fighting: field.play.most counts the battles still on
	for a in sides:
		for r in (a as Army).rows():
			if not r.has("alive"):
				continue
			var alive: PackedByteArray = r["alive"]
			var vat: VATMultiMeshInstance3D = r["vat"]
			for s in alive.size():
				if alive[s] == 1:
					vat.fade_out_instance(s, 1.5, _rng.randf_range(0.0, 2.0))
			if r.get("banner") is Node3D:
				(r["banner"] as Node3D).visible = false
			if r.has("broke_at"):
				var std: Node3D = Heraldry.standard(r.get("house", {}), r.get("colour", Color.GRAY), Data.num(F, "field.play.dropped", 0.45))
				var at: Vector3 = r["broke_at"]
				add_child(std)
				std.global_position = Vector3(at.x, main.terrain.height_at(at.x, at.z) + 0.01, at.z)
				std.rotation = Vector3(0.0, _rng.randf() * TAU, PI * 0.47)  # fallen over, its pole along the ground
	for a in sides:
		var b = (a as Army).banners
		for n in [b.standard]:
			if n is Node3D and is_instance_valid(n):
				(n as Node3D).visible = false  # the host's standard goes with the living
	_prisoners()
	get_tree().create_timer(maxf(1.0, Awareness.season_seconds * Data.num(F, "field.play.aftermath", 1.0)), false).timeout.connect(queue_free)


## Prisoners led away (Total War's captives after the battle, Bannerlord's prisoners marched behind the victor): from
## where the beaten broke, a file of their men in their colours trudging (Injured_Walk) between the victors' guards
## (spears, marching), along the navigation's route to the victors' rear; field.play.prisoners: men per regiment that
## broke (most at most), guards at the head and tail, pace, how far back. Gone at the end of the way.
func _prisoners() -> void:
	var k: Dictionary = Data.value(F, "field", {}).get("play", {}).get("prisoners", {})
	var scenes: Node = main.get("scenes")
	if scenes == null:
		return
	var beaten: Array = (sides[loser] as Army).rows().filter(func(r): return r.has("broke_at"))
	if beaten.is_empty():
		return
	var victor: Army = sides[1 - loser]
	var from := Vector3.ZERO
	for r in beaten:
		from += r["broke_at"]
	from /= beaten.size()
	var face := victor.facing()
	var to := from - Vector3(sin(face), 0, cos(face)) * float(k.get("back", 4.0))
	var way: PackedVector3Array = scenes.route(from, to)
	if way.size() < 2:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec()
	var held_col: Color = beaten[0].get("colour", Color.GRAY)
	var won: Array = victor.rows()
	var won_col: Color = won[0].get("colour", Color.GRAY) if not won.is_empty() else Color.GRAY
	var n := mini(int(k.get("most", 12)), int(k.get("per_regiment", 4)) * beaten.size())
	var guards := int(k.get("guards", 2))
	var gap := float(k.get("gap", 0.11))
	var file: Array = []  # [body, how far behind the head, how far across]
	var at := 0
	for i in n + guards * 2:
		var guard := i < guards or i >= n + guards
		var p: Node3D = scenes.people.make(rng, "soldier", won_col if guard else held_col, "adult")
		if guard:
			scenes.arm(p, "spear")
		scenes.people.play(p, "SS_Walk" if guard else "Injured_Walk", rng.randf_range(0.9, 1.05))
		file.append([p, gap * at, rng.randf_range(-0.03, 0.03) if not guard else 0.06 * (1 if i % 2 == 0 else -1)])
		at += 1
	Mover.road(self, way, file, float(k.get("pace", 0.12)), {"name": "Prisoners", "min": 10.0, "max": maxf(12.0, Awareness.season_seconds)})


## Every regiment's men brought back to their stance after a one-shot, and its fallen kept where they fell while it
## moves on.
func _keep_up() -> void:
	for a in sides:
		for r in (a as Army).rows():
			if not r.has("alive"):
				continue
			_backs(r)
			# Any change to where it stands (a move, a turn where it stands, a wheel): its fallen put back where they
			# fell, each on the land under him (Mac 2026-11-15: a dead man flat in mid-air; a turn swung the fallen
			# round the block's middle, off the ground they lay on).
			var xf := (r["node"] as Node3D).global_transform
			if r["moved"] or Mover.of(r["node"]).moving() or not xf.is_equal_approx(r.get("kept_xf", Transform3D())):
				_keep_dead(r)
				r["kept_xf"] = xf
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
				_straggle(r, Morale.waver(r), dt)
	for r in gone:
		_send(r, &"break")
	for r in Morale.rallied(_rows(), dt, clock > Data.num(F, "field.longest", 45.0), [(sides[0] as Army).commander(), (sides[1] as Army).commander()]):
		_send(r, &"rally")
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
	_focus = _focus.lerp(lens_aim(_rows(), loser, met(), _focus), minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2)))
	var crown: Army = sides[0]
	_yaw = lerp_angle(_yaw if _yawed else crown.facing() + Data.num(F, "field.camera.quarter", 0.9), lens_yaw(_rows(), loser, crown.facing()),
			minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2)))
	_yawed = true
	# At blows the lens comes in on the press, so the men fighting fill the frame (g38 battle: from the lines' own
	# distance the clash read as two diagonal lines on a lawn), and lower, across the fronts rather than down on them.
	var at_blows := met()
	_near = lerpf(_near, Data.num(F, "field.camera.close", 0.55) if at_blows else 1.0, minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2)))
	var d := maxf(_dist * _near, main.rig.min_distance)  # never under the lens's floor, roof height (Mac 2026-11-16: "almost FPS zoom")
	main.rig.snap(_focus, d, _yaw)
	var pitch := Data.num(F, "field.camera.pitch", 30.0) if at_blows else Data.num("army", "camera.pitch", 38.0)
	main.rig.tilt = main.rig.tilt_for(pitch, maxf(d, main.rig.min_distance))  # 03-army's pitch; lower at blows
	main.rig.goal_tilt = main.rig.tilt


# --- A regiment's mind (data/army.json minds.regiment) ----------------------------------------------------

func _ready_in(r: Dictionary) -> void:
	_play(r, "ready")


func _walk_in(r: Dictionary) -> void:
	_play(r, "walk")
	r["gait"] = "walk"
	r["moving"] = "walk"
	r.erase("ran")
	r["gait_still"] = 0.0
	r.erase("gait_at")
	r.erase("gait_yaw")


## How far the battle's lens stands (the test aid): the town view's distance (camera.json town_view.dist), so a
## rout reads as a crowd in the square does; --dist=<units> for another.
static func lens_distance() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			return float(a.substr(7))
	return Data.num(F, "field.camera.dist", 5.0)  # both lines in the frame (Mac 2026-11-16: the square's distance was "almost FPS zoom")


## Where the battle's lens looks (rows: [side 0's, side 1's]): before the lines meet, the middle of every regiment
## not running; at blows, where the beaten regiment whose nerve is lowest (army_morale.gd: where the line breaks next)
## meets its nearest foe still standing, so both lines are in frame at the point of contact (g15 battle.jpg: the lens
## on one flanking cavalry regiment alone, over empty grass) and the rout is framed as it starts and runs along the
## line; once none of the beaten stands, `last` (the lens stays where the rout ended).
static func lens_aim(rows: Array, loser: int, met: bool, last: Vector3) -> Vector3:
	if met:
		# Where two fronts are locked (a beaten regiment at blows with its foe, the shakiest of them): midway between
		# the two, so the frame holds the press itself, front ranks cutting, men falling, both standards over it (g17
		# battle.jpg: the shakiest regiment and its nearest foe were not the pair fighting; grey horse and red pikes in
		# frame, apart).
		var pair := locked_pair(rows, loser)
		if not pair.is_empty():
			return ((pair[0]["node"] as Node3D).global_position).lerp((pair[1]["node"] as Node3D).global_position, 0.5)
		var next := Morale.shakiest(rows, loser)
		if next.is_empty():
			return last
		var at: Vector3 = (next["node"] as Node3D).global_position
		var foe := at
		var bd := INF
		for x in rows[1 - loser]:
			if String(x.get("state_name", "")) != "rout":
				var p: Vector3 = (x["node"] as Node3D).global_position
				if at.distance_squared_to(p) < bd:
					bd = at.distance_squared_to(p)
					foe = p
		return at.lerp(foe, 0.5)
	var sum := Vector3.ZERO
	var n := 0
	for side in rows:
		for r in side:
			if String(r.get("state_name", "")) != "rout":
				sum += (r["node"] as Node3D).global_position
				n += 1
	return sum / n if n > 0 else last


## The press the lens holds (rows: [side 0's, side 1's]): the shakiest beaten regiment at blows with its foe,
## [it, its foe]; a pair front to front (Total War's lines meeting) before one hit in the flank; [] when none fights.
static func locked_pair(rows: Array, loser: int) -> Array:
	var low := INF
	var pair: Array = []
	for r in rows[loser]:
		var f: Variant = r.get("foe")
		if String(r.get("state_name", "")) != "fight" or not f is Dictionary or String((f as Dictionary).get("state_name", "")) == "rout":
			continue
		var score := Morale.of(r) + (0.0 if bool(r.get("flanked", false)) == false else 10.0)
		if score < low:
			low = score
			pair = [r, f]
	return pair


## The lens's heading on the battle (the test aid): off the quarter of the locked pair's line of attack, the victor's
## regiment facing into the beaten one (field.camera.quarter), so the lens looks across both fronts where they meet,
## not down a line's length (g20 battle.jpg: two thin columns seen straight along); before blows, off the crown's
## line, as it was.
static func lens_yaw(rows: Array, loser: int, crown_face: float) -> float:
	var q := Data.num(F, "field.camera.quarter", 0.9)
	var pair := locked_pair(rows, loser)
	if pair.is_empty():
		return crown_face + q
	var a: Vector3 = (pair[0]["node"] as Node3D).global_position
	var b: Vector3 = (pair[1]["node"] as Node3D).global_position
	var into := a - b if loser == 1 else b - a  # the crown's side's regiment facing into its foe
	return atan2(into.x, into.z) + q


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
	if _front_gap(r, foe) < Data.num(F, "field.volley.until", 3.0) or met():
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
	var kills: Array = Data.value(F, "field.volley.kills", [1, 4])
	var fells := _rng.randi_range(int(kills[0]), int(kills[1])) * (2 if int(foe["side"]) == loser else 1)
	var man := Data.num("army", "man", 0.22)
	var draw := Data.num(F, "field.volley.draw_s", 0.8)
	var step := Data.num(F, "field.volley.step", 0.15)
	var spread := Data.num(F, "field.volley.spread", 0.05)
	var most := int(Data.num(F, "field.volley.arrows", 70))
	var fnode: Node3D = foe["node"]
	var their: PackedVector3Array = foe["local"]
	var their_alive: PackedByteArray = foe["alive"]
	# The volley in step (research note step 5; Total War's volleys): every living archer draws at once, and they loose
	# together draw_s later, within `step` of each other; each arrow on a true ballistic arc (field.volley.angle and
	# gravity: its flight from its range) onto a man of the target block, a little off him (spread).
	var shot := 0
	for s in local.size():
		if alive[s] == 0 or shot >= most:
			continue
		shot += 1
		vat.update_instance_track(s, army.track(r, "attack"))
		vat.update_instance_animation_offset(s, _rng.randf_range(0.0, 0.05))
		(r["back"] as Dictionary)[s] = clock + draw + 0.6
		var from := node.to_global(local[s]) + Vector3(0, man * 0.8, 0)
		var aim := _rng.randi() % their.size()
		for tries in 6:
			if their_alive[aim] == 1:
				break
			aim = _rng.randi() % their.size()
		var to := fnode.to_global(their[aim]) + Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
		to.y = main.terrain.height_at(to.x, to.z)
		var arc := ballistic(from, to, Data.num(F, "field.volley.angle", 0.75), Data.num(F, "field.volley.gravity", 3.0))
		var lands := shot <= fells
		_loose(from, to, clock + draw + _rng.randf_range(0.0, step), arc.x, arc.y,
			func(): if lands and foe.get("state_name", "") != "rout": _fell(foe, 1, false))


## A shaft's flight from `from` to `to` (world) loosed at `angle` (radians over the flat) under `gravity` (world units a
## second squared): the speed that carries it there, so (flight seconds, its arc's top over its length as _on_arc
## draws it: g T^2 / 8 over the range). A parabola in time with the run uniform is the ballistic path without drag.
static func ballistic(from: Vector3, to: Vector3, angle: float, gravity: float) -> Vector2:
	var run := maxf(Vector2(to.x - from.x, to.z - from.z).length(), 0.01)
	var g := maxf(gravity, 0.01)
	var v := sqrt(g * run / maxf(sin(2.0 * angle), 0.05))
	var t := 2.0 * v * sin(angle) / g
	return Vector2(t, g * t * t / 8.0 / maxf(from.distance_to(to), 0.01))


## Foot: forward until its front is at sword's length from the nearest enemy's front; then both fight.
func _advance(r: Dictionary, _dt: float) -> void:
	var foe := _opposite_foe(r)
	if foe.is_empty():
		return
	var at: Vector3 = (r["node"] as Node3D).global_position
	var gap := _front_gap(r, foe)
	var contact := Data.num(F, "field.contact", 0.12)
	# At blows only face to face (g17/g19: "at blows" with a foe two blocks aside; g20: a line that walked sideways
	# facing its walk met the foe file to file, two thin columns side by side): it closes square on the foe's front,
	# facing it, its own front at sword's length; at blows once the fronts are that close and overlap across the line.
	# Square to its side's own front, the line meeting the foe's line as a line (Total War's battle lines; Mac
	# 2026-11-15: a block set slanted to its neighbour, each squared to its own foe's facing): every regiment of a side
	# faces its host's facing and closes to the foe's front along it, so neighbours stand parallel; only a foe beside
	# or behind that front (a flank, the line broken through) is met square on his own front instead.
	var b: Node3D = foe["node"]
	var look := _meet_look(r, foe)
	var theirs: Vector3
	if look.is_equal_approx(_line_front(r)):
		var across := look.cross(Vector3.UP).normalized()
		theirs = at + across * (b.global_position - at).dot(across) + look * ((b.global_position - at).dot(look) - _depth_along(foe, look) * 0.5)
	else:
		theirs = b.global_position - look * float(foe["d"]) * 0.5
	# Its own place on that front: beside any of its side already closing there, never on it (Mac 2026-11-15: three
	# blocks heaped in one lump, each sent to the same foe's front).
	var spot := _free_spot(r, theirs - look * (float(r["d"]) * 0.5 + contact), look)
	spot.y = at.y
	r["spot"] = spot
	# At sword's length from its foe's front, it is at blows wherever its spot was (Mac 2026-11-16: blocks stopping a
	# step short of the press, their place in it taken; field_clash_probe): field.reach.
	var touching := gap < Data.num(F, "field.reach", 0.4) and gap > -float(r["d"])
	if not touching and (Vector2(spot.x - at.x, spot.z - at.z).length() > contact or gap > contact * 2.0):
		# The last stretch at a run, a cry going up (Total War's charge: the lines walk in, then run the last of it; Mac
		# 2026-11-16: "standing instead of charging"): within field.charge.from of the foe's front, field.charge.pace.
		var runs := gap < Data.num(F, "field.charge.from", 2.2)
		if runs and not r.get("ran", false):
			r["ran"] = true
			if main.get("sound") and main.sound.has_method("event"):
				main.sound.event("charge")
		r["moving"] = "run" if runs else "walk"
		Mover.of(r["node"]).toward(spot, Data.num(F, "field.charge.pace", 0.45) if runs else Data.num(F, "field.advance", 0.12) * _dress_pace(r, look), look)
		if _gait(r, _dt) == "ready":
			_square(r, look, _dt)  # held where it stands (its way blocked, its place taken): its front to the foe, never askew
		return
	r["foe"] = foe
	_send(r, &"engage")
	if foe.get("state_name", "") in ["stand", "volley", "advance"]:
		foe["foe"] = r
		_send(foe, &"engage")


## Its pace in the walk-in kept to its side's line (Total War's lines advance dressed, as one front; Mac 2026-11-16:
## "fix the lines"): a block ahead of its side's other advancing foot (along the side's front) slows, one behind
## quickens, by field.dress.k a world unit, within field.dress.slow and field.dress.fast. A share of field.advance.
func _dress_pace(r: Dictionary, look: Vector3) -> float:
	var at: Vector3 = (r["node"] as Node3D).global_position
	var sum := 0.0
	var n := 0
	for x in (sides[int(r["side"])] as Army).rows():
		if is_same(x, r) or String(x.get("role", "")) != "melee" or String(x.get("state_name", "")) != "advance":
			continue
		sum += ((x["node"] as Node3D).global_position - at).dot(look)
		n += 1
	if n == 0:
		return 1.0
	var ahead := -sum / n  # how far this block stands ahead of the others' mean, along the front
	return clampf(1.0 - ahead * Data.num(F, "field.dress.k", 1.5), Data.num(F, "field.dress.slow", 0.3), Data.num(F, "field.dress.fast", 1.4))


## The way a regiment faces to meet `foe` (flat, world; research note step 4): its side's front while the foe stands
## ahead of it, so neighbours stand parallel and the lines meet as lines; a foe beside or behind that front (a flank,
## the line broken through) square on his own front instead.
func _meet_look(r: Dictionary, foe: Dictionary) -> Vector3:
	var look := _line_front(r)
	var b: Node3D = foe["node"]
	if (b.global_position - (r["node"] as Node3D).global_position).dot(look) > 0.0:
		return look
	var theirs := -b.global_transform.basis.z
	theirs.y = 0.0
	return theirs.normalized()


## Turns a regiment where it stands until its front is `look` (flat, world), at formations.json wheel.rate a second,
## within field.square.slack of it (Mac's run 7: a block that met its foe mid-wheel stood slanted to his line).
func _square(r: Dictionary, look: Vector3, dt: float) -> void:
	if look.length() < 0.001:
		return
	var yaw := (r["node"] as Node3D).rotation.y
	var off := angle_difference(yaw, atan2(look.x, look.z))
	if absf(off) <= Data.num(F, "field.square.slack", 0.03):
		return
	var rate := float(Data.value("formations", "wheel.rate", 0.9))
	(r["army"] as Army).turn(r, yaw + clampf(off, -rate * dt, rate * dt))
	r["gait_yaw"] = (r["node"] as Node3D).rotation.y  # its own squaring is no move of its Mover's (_gait)
	r["moved"] = true


## Its men's clip by whether its block moves (Mac's run 7: a block standing with its pikes upright, its walk, beside
## one at the ready): walk while its Mover takes it on more than field.gait.still a second or wheels it more than
## field.gait.wheel radians a second, ready once it has stood field.gait.hold seconds. Returns the gait it now has.
func _gait(r: Dictionary, dt: float) -> String:
	var node: Node3D = r["node"]
	var at := node.global_position
	var was: Vector3 = r.get("gait_at", at)
	var yaw_was := float(r.get("gait_yaw", node.rotation.y))
	r["gait_at"] = at
	r["gait_yaw"] = node.rotation.y
	var goes := dt > 0.0 and (Vector2(at.x - was.x, at.z - was.z).length() / dt > Data.num(F, "field.gait.still", 0.02)
		or absf(angle_difference(yaw_was, node.rotation.y)) / dt > Data.num(F, "field.gait.wheel", 0.1))
	r["gait_still"] = 0.0 if goes else float(r.get("gait_still", 0.0)) + dt
	var want := String(r.get("moving", "walk")) if float(r["gait_still"]) < Data.num(F, "field.gait.hold", 0.5) else "ready"
	if want != String(r.get("gait", "walk")):
		_play(r, want)
	r["gait"] = want
	return want


## Its side's front (flat, world): the way its host's line faces (Army.facing), one for every regiment of the side.
func _line_front(r: Dictionary) -> Vector3:
	var face: float = (r["army"] as Army).facing()
	return Vector3(sin(face), 0, cos(face))


## How deep a regiment stands along `dir` (flat): its rectangle's extent that way, however it is turned.
static func _depth_along(x: Dictionary, dir: Vector3) -> float:
	var basis := (x["node"] as Node3D).global_transform.basis
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var fwd := Vector3(basis.z.x, 0, basis.z.z).normalized()
	return absf(right.dot(dir)) * float(x["w"]) + absf(fwd.dot(dir)) * float(x["d"])


## A regiment's place on a front: `spot` (world, its middle, facing `look`), or the nearest beside it along the
## front, a regiment's width and army.gap at a time, that no other regiment of its side holds or is closing on (its
## own spot while it advances or fights, else where it stands). Rectangles side by side, never one over another.
func _free_spot(r: Dictionary, spot: Vector3, look: Vector3) -> Vector3:
	var across := look.cross(Vector3.UP).normalized()
	var w := float(r["w"])
	var d := float(r["d"])
	var gap := Data.num("army", "gap", 0.35)
	for k in 13:
		var step := float((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
		var q := spot + across * step * (w + gap)
		var free := true
		for x in (sides[int(r["side"])] as Army).rows():
			if is_same(x, r) or x.get("state_name", "") == "rout" or int(x.get("living", 1)) <= 0:
				continue
			var there: Vector3 = x["spot"] if x.has("spot") and x.get("state_name", "") in ["advance", "fight"] else (x["node"] as Node3D).global_position
			var off := there - q
			if absf(off.dot(across)) < (w + float(x["w"])) * 0.5 + gap and absf(off.dot(look)) < (d + float(x["d"])) * 0.5 + gap:
				free = false
				break
		if free:
			return q
	return spot


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
	if r["role"] == "cavalry" and clock - float(r.get("met_at", clock)) > Data.num(F, "field.cavalry.melee_s", 4.0):
		_send(r, &"rideout")  # horse never stays stuck in: it rides out to charge again (Total War's cycle charge)
		return
	if r["role"] != "cavalry":
		_square(r, _meet_look(r, foe), dt)  # met mid-wheel (its foe closed on it first): it squares to him where it stands
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
	var line: PackedVector3Array = r[String(r.get("form", "line"))]["at"]
	for s in front:
		var v := local[s]
		v.z = line[s].z + sin(clock * 2.1 + float(s) * 1.7) * surge
		local[s] = v
	r["local"] = local
	r["moved"] = true
	# Dust thrown up along its front where the lines grind (scenes.gd dust, the skirmish's own), raised again as it
	# thins (field.fight.dustEvery), so the press has weight in the frame (g21: a clean seam).
	if clock >= float(r.get("dust_t", 0.0)):
		r["dust_t"] = clock + Data.num(F, "field.fight.dustEvery", 6.0)
		_dust_at(r)
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


## Dust along a regiment's front (scenes.gd dust over each third of its width: the massed front is wider and
## thicker with men than a skirmish's line).
func _dust_at(r: Dictionary) -> void:
	var sc: Node = main.get("scenes")
	if sc == null:
		return
	var node: Node3D = r["node"]
	var along := node.global_transform.basis.x.normalized()
	var w := float(r["w"])
	for k in 3:
		var p := node.to_global(Vector3(w * (k - 1) / 3.0, 0.0, float(r["d"]) * 0.5 + Data.num(F, "field.contact", 0.12) * 0.5))
		p.y = main.terrain.height_at(p.x, p.z) + 0.01
		sc.dust(self, p, along, w / 3.0)


## Horse: round the end of the enemy's line nearest its own wing, wide of it (field.cavalry.wide), then in on his
## flank.
func _flank(r: Dictionary, _dt: float) -> void:
	var foe_army: Army = sides[1 - int(r["side"])]
	var rows := foe_army.rows().filter(func(x): return x.get("state_name", "") != "rout" and int(x.get("living", 1)) > 0)
	if rows.is_empty():
		return
	var node: Node3D = r["node"]
	_morph_step(r, _dt)  # back into its ranks as it rides round (after a ride out)
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


## Horse in a wedge (research note step 6; Total War's cavalry, 0 A.D.'s wedge template): on its charge it forms the
## wedge as it runs (formations.json templates.wedge, each man to his nearest place), then in on its target's flank or
## rear, whichever it is nearest, never its front; the shock where it strikes (field.cavalry.shock men down at once),
## at blows for field.cavalry.melee_s, then it rides out (field.cavalry.out away from the target), forms its ranks again
## as it rides round, and charges again: the cycle charge, never stuck in the press.
func _charge_in(r: Dictionary) -> void:
	_play(r, "run")
	_morph(r, "wedge")


func _charge(r: Dictionary, _dt: float) -> void:
	_morph_step(r, _dt)
	var t: Variant = r.get("target")
	if t == null or (t as Dictionary).get("state_name", "") == "rout":
		_send(r, &"flank")
		return
	var target: Dictionary = t
	var tn: Node3D = target["node"]
	var at: Vector3 = (r["node"] as Node3D).global_position
	var hit := charge_face(tn.global_transform, float(target["w"]), float(target["d"]), at)
	var side: Vector3 = hit[0]
	var reach := float(hit[1]) + float(r["d"]) * 0.5 + Data.num(F, "field.contact", 0.12)
	var spot := tn.global_position + side * reach
	spot.y = at.y
	if Vector2(at.x - spot.x, at.z - spot.z).length() <= Data.num(F, "field.contact", 0.12):
		r["foe"] = target
		r["met_at"] = clock
		target["flanked"] = true
		# The shock of the charge: men go down at once where the horse strikes (Total War's charge impact).
		if target.get("state_name", "") != "rout" and int(target.get("living", 0)) > 0:
			_fell(target, int(Data.num(F, "field.cavalry.shock", 12.0)), true)
		_send(r, &"engage")
		return
	Mover.of(r["node"]).toward(spot, Data.num(F, "field.cavalry.charge", 0.55), -side)


## Which face of a block (its transform, width, depth) a charge from `from` strikes: its left or right flank or its
## rear, whichever `from` stands most before, never its front. [the face's outward way (flat, world), its half extent].
static func charge_face(xf: Transform3D, w: float, d: float, from: Vector3) -> Array:
	var right := Vector3(xf.basis.x.x, 0, xf.basis.x.z).normalized()
	var fwd := Vector3(xf.basis.z.x, 0, xf.basis.z.z).normalized()
	var off := Vector3(from.x - xf.origin.x, 0, from.z - xf.origin.z)
	var best: Array = [right, w * 0.5]
	var most := -INF
	for f in [[right, w * 0.5], [-right, w * 0.5], [-fwd, d * 0.5]]:
		var score := off.dot(f[0] as Vector3)
		if score > most:
			most = score
			best = f
	return best


## Out of the press: away from the foe it hit, at the charge's pace, field.cavalry.out; then round for the next.
func _ride_out_in(r: Dictionary) -> void:
	_play(r, "run")
	var foe: Variant = r.get("foe")
	var at: Vector3 = (r["node"] as Node3D).global_position
	var away := (r["node"] as Node3D).global_transform.basis.z
	if foe is Dictionary and is_instance_valid((foe as Dictionary).get("node")):
		away = at - ((foe as Dictionary)["node"] as Node3D).global_position
		(foe as Dictionary)["flanked"] = false
	away.y = 0.0
	r["out_to"] = at + away.normalized() * Data.num(F, "field.cavalry.out", 2.5)
	r["foe"] = null
	r["ride_t"] = 0.0


func _ride_out(r: Dictionary, dt: float) -> void:
	_morph_step(r, dt)
	var at: Vector3 = (r["node"] as Node3D).global_position
	var to: Vector3 = r["out_to"]
	r["ride_t"] = float(r["ride_t"]) + dt
	if Vector2(to.x - at.x, to.z - at.z).length() <= 0.1 or float(r["ride_t"]) > Data.num(F, "field.cavalry.out_s", 8.0):
		_morph(r, "line")  # its ranks again as it rides round for the next charge
		_play(r, "walk")
		_send(r, &"flank")
		return
	Mover.of(r["node"]).toward(to, Data.num(F, "field.cavalry.charge", 0.55))


## A regiment taking another of its formations (formations.json) while it moves: each living man from where he stands
## to his nearest place in it (Formation.assign) over field.cavalry.form_s; its fight reads the new formation's ranks.
func _morph(r: Dictionary, shape: String) -> void:
	if not r.has(shape):
		r[shape] = Formation.layout(r, shape, _rng)
	if String(r.get("form", "line")) == shape and not r.has("morph"):
		return
	var to := Formation.assign(r["local"], r[shape]["at"])
	(r[shape] as Dictionary)["at"] = to
	r["form"] = shape
	r["morph"] = {"from": (r["local"] as PackedVector3Array).duplicate(), "to": to, "t": 0.0}


func _morph_step(r: Dictionary, dt: float) -> void:
	if not r.has("morph"):
		return
	var m: Dictionary = r["morph"]
	m["t"] = minf(1.0, float(m["t"]) + dt / maxf(Data.num(F, "field.cavalry.form_s", 1.5), 0.05))
	var e := smoothstep(0.0, 1.0, float(m["t"]))
	var from: PackedVector3Array = m["from"]
	var to: PackedVector3Array = m["to"]
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	for s in mini(local.size(), to.size()):
		if alive[s] == 1:
			local[s] = from[s].lerp(to[s], e)
	r["local"] = local
	r["moved"] = true
	if float(m["t"]) >= 1.0:
		var shape: Dictionary = r[String(r["form"])]
		r["w"] = shape["w"]
		r["d"] = shape["d"]
		r.erase("morph")


## Men break ranks before a rout (Total War and Bannerlord: a wavering unit sheds men from its rear before it
## breaks): as a regiment's banner wavers past morale.straggle.from, up to `most` of its living men, the rearmost
## first, turn their backs and edge back at `pace`, no further than `back` and never out of their own block's ground
## (its rectangle, its claim: Mac 2026-11-15, loose single men wandering between the blocks were these, 0.5 behind a
## block's rear rank in the gap before the next row); steadied again (no one left to shed), they walk back to their
## places and face the foe. Its break takes them along with the rest: only a broken regiment's men leave its ground.
func _straggle(r: Dictionary, w: float, dt: float) -> void:
	var k: Dictionary = Data.value("army", "morale", {}).get("straggle", {})
	var strag: Dictionary = r.get("strag", {})
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	var yaws: PackedFloat32Array = r["yaws"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var from := float(k.get("from", 0.5))
	var living := alive.count(1)
	var want := int(living * float(k.get("most", 0.12)) * clampf((w - from) / maxf(1.0 - from, 0.01), 0.0, 1.0))
	if strag.is_empty() and want == 0:
		return
	while strag.size() < want:  # the rearmost living man not yet slipping away
		var pick := -1
		for s in local.size():
			if alive[s] == 1 and not strag.has(s) and (pick < 0 or local[s].z < local[pick].z):
				pick = s
		if pick < 0:
			break
		strag[pick] = local[pick]
		yaws[pick] += PI
		vat.update_instance_track(pick, army.track(r, "walk"))
		vat.update_instance_animation_offset(pick, _rng.randf())
	var pace := float(k.get("pace", 0.05)) * dt
	for s in strag.keys():
		var home: Vector3 = strag[s]
		if alive[s] == 0:
			strag.erase(s)  # he fell where he was
			continue
		if want > 0:
			local[s].z = maxf(local[s].z - pace, maxf(home.z - float(k.get("back", 0.5)), -float(r["d"]) * 0.5))
		else:
			local[s] = local[s].move_toward(home, pace)
			if local[s].is_equal_approx(home):
				strag.erase(s)
				yaws[s] -= PI
				vat.update_instance_track(s, army.track(r, "ready"))
	r["strag"] = strag
	r["local"] = local
	r["yaws"] = yaws
	r["moved"] = true


## It breaks (research note step 7; Total War's and Bannerlord's rout): the block comes apart into loose men, each his
## own body walked by his Mover through the field's crowd (Godot's RVO, _rout_crowd), running away from its side's
## front, each a little wide of the next (field.loose.spread); its ground is let go; its banner wavers its last. The
## figures stay the block's one VAT draw, each laid where his runner is (_follow_runners).
func _break(r: Dictionary) -> void:
	var army: Army = r["army"]
	if not r.has("broke_at"):
		r["broke_at"] = (r["node"] as Node3D).global_position  # where its standard falls (_aftermath)
	army.waver(r, 1.0)
	Morale.broke(_rows(), r)  # those beside it are shaken: the chain
	r["strag"] = {}
	r["yaws0"] = (r["yaws"] as PackedFloat32Array).duplicate()  # each man's own turn in the ranks, for a rally
	army.let_go(r)  # its ground is no one's: its men are loose
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	var away := -_line_front(r)
	var across := away.cross(Vector3.UP)
	var spread := Data.num(F, "field.loose.spread", 0.6)
	var pace := Data.num(F, "field.run", 0.42)
	var crowd := _rout_crowd()
	var runners := {}
	for s in local.size():
		if alive[s] == 0:
			continue
		var man := Node3D.new()
		man.name = "Runner"
		add_child(man)
		man.global_position = node.to_global(local[s])
		man.rotation.y = atan2(away.x, away.z)
		var mo: Node = Mover.of(man)
		mo.clip = ""  # his figure is the block's VAT draw
		mo.fights(true)
		mo.join(crowd, &"man", pace * 1.3)
		runners[s] = {"node": man, "way": (away + across * _rng.randf_range(-spread, spread)).normalized(), "pace": pace * _rng.randf_range(0.85, 1.15)}
	r["runners"] = runners
	var vat: VATMultiMeshInstance3D = r["vat"]
	var run := army.track(r, "run")
	for s in runners:
		vat.update_instance_track(s, run)
		vat.update_instance_animation_offset(s, _rng.randf())
	r["ran"] = 0.0
	if play.is_empty() and ai == null: print("BATTLE t=%.0f a %s regiment breaks at %d%%" % [clock, "crown" if int(r["side"]) == 0 else "foe", int(float(r["strength"]) * 100.0)])


## The field's crowd for loose men (a NavigationServer3D avoidance map of its own, as army_melee.gd's): made on the
## first rout, freed with the battle.
var _crowd := RID()
func _rout_crowd() -> RID:
	if not _crowd.is_valid():
		_crowd = NavigationServer3D.map_create()
		NavigationServer3D.map_set_active(_crowd, true)
	return _crowd


func _exit_tree() -> void:
	if _crowd.is_valid():
		NavigationServer3D.free_rid(_crowd)
		_crowd = RID()


## Running: each loose man on, away from the field at his own pace, round the others (his Mover, steered every frame);
## gone after field.fade.
func _run(r: Dictionary, dt: float) -> void:
	var runners: Dictionary = r.get("runners", {})
	if not r.get("gone", false):
		for s in runners:
			var m: Dictionary = runners[s]
			var man: Node3D = m["node"]
			if is_instance_valid(man):
				Mover.of(man).toward(man.global_position + (m["way"] as Vector3) * 0.5, float(m["pace"]))
	_follow_runners(r)
	r["ran"] = float(r["ran"]) + dt
	if float(r["ran"]) > Data.num(F, "field.fade", 7.0) and not r.get("gone", false):
		r["gone"] = true
		var vat: VATMultiMeshInstance3D = r["vat"]
		for s in runners:
			vat.fade_out_instance(s, 1.0, _rng.randf_range(0.0, 1.5))
		(r["banner"] as Node3D).visible = false
		get_tree().create_timer(3.0, false).timeout.connect(func(): _free_runners(r))


## Each loose man's figure laid where his runner is and turned the way he faces (in the block's frame: its one draw).
func _follow_runners(r: Dictionary) -> void:
	var runners: Dictionary = r.get("runners", {})
	if runners.is_empty():
		return
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var yaws: PackedFloat32Array = r["yaws"]
	for s in runners:
		var man: Node3D = runners[s]["node"]
		if not is_instance_valid(man):
			continue
		var p := node.to_local(man.global_position)
		local[s] = Vector3(p.x, 0.0, p.z)
		yaws[s] = wrapf(man.global_rotation.y - node.global_rotation.y, -PI, PI)
	r["local"] = local
	r["yaws"] = yaws
	r["moved"] = true


func _free_runners(r: Dictionary) -> void:
	for s in (r.get("runners", {}) as Dictionary):
		var man: Node3D = r["runners"][s]["node"]
		if is_instance_valid(man):
			man.queue_free()
	r["runners"] = {}


## Rallied (army_morale.gd rallied: its commander near while the day isn't spent): every loose man walks back to his
## place in its block by his Mover; all back, the block stands formed again where it broke, its ground held, and goes
## back to its work.
func _rally_in(r: Dictionary) -> void:
	var node: Node3D = r["node"]
	var form: PackedVector3Array = r[String(r.get("form", "line"))]["at"]
	(r["army"] as Army).waver(r, 0.5)
	_play(r, "walk")
	for s in (r.get("runners", {}) as Dictionary):
		var man: Node3D = r["runners"][s]["node"]
		if is_instance_valid(man):
			var mo: Node = Mover.of(man)
			mo.speed = Data.num(F, "field.advance", 0.16)
			mo.go(node.to_global(form[s]), func(): r["runners"][s]["back"] = true)


func _rally(r: Dictionary, _dt: float) -> void:
	_follow_runners(r)
	var runners: Dictionary = r.get("runners", {})
	for s in runners:
		if not runners[s].get("back", false) and is_instance_valid(runners[s]["node"]):
			return
	_free_runners(r)
	var form: PackedVector3Array = r[String(r.get("form", "line"))]["at"]
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	for s in local.size():
		if alive[s] == 1:
			local[s] = form[s]
	r["local"] = local
	r["yaws"] = r.get("yaws0", r["yaws"])
	r["moved"] = true
	(r["army"] as Army).hold_ground(r)
	_send(r, &"formed")
	_send(r, &"volley" if r["role"] == "ranged" else (&"flank" if r["role"] == "cavalry" else &"advance"))


## The victors hold the field: they raise a cheer where they stand (Warcraft III and Total War: the winners cheer as
## the beaten run; every action gets a reaction), field.play.cheer_s seconds, then stand at ease.
func _hold(r: Dictionary) -> void:
	(r["army"] as Army).waver(r, 0.0)
	_play(r, "cheer")
	r["foe"] = null
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = Data.num(F, "field.play.cheer_s", 4.0) * _rng.randf_range(0.8, 1.2)
	t.timeout.connect(func():
		if not _after and r.has("alive"):
			_play(r, "rest")
		t.queue_free())
	add_child(t)
	t.start()


# --- Men falling and the fallen ---------------------------------------------------------------------------

## n men of a regiment fall: from its front at blows, anywhere under arrows. Its figures fall in step with its men
## (its figures over its men each: a floor of figures stands for a small regiment, army.json figureFloor): each plays
## his death and stays where he fell (a horseman, with no fall of his own, fades there: meshes.<dir>.fallen); the
## regiment's strength (its banner's pips) is its figures standing over its figures.
func _fell(r: Dictionary, men: int, front: bool) -> void:
	r["lost"] = int(r.get("lost", 0)) + men
	var n := int(floor(float(r["lost"]) / maxf(float(r["men"]), 1.0) * int(r["figures"]) + 0.0001)) - (int(r["figures"]) - int(r["living"]))  # figures now due to fall
	var alive: PackedByteArray = r["alive"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var pool: Array = _front_men(r) if front else []
	var fade := String(Data.value("army", "meshes.%s.fallen" % String(r["kit"]["asset"]), "lie")) == "fade"
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
		if fade:
			vat.fade_out_instance(s, 1.0, 0.0)  # no fall of his own (army.json meshes.<dir>.fallen): never left standing
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
		if not alive.is_empty() and alive[s] == 0 or (r.get("strag", {}) as Dictionary).has(s):
			continue  # the fallen lie still; a straggler keeps slipping away
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
	var form: Dictionary = r[String(r.get("form", "line"))]
	var line: PackedVector3Array = form["at"]
	var files := int(form.get("files", 20))
	var ranks := int(Data.num(F, "field.fight.ranks", 2))
	var order: Array = []
	for s in alive.size():
		if alive[s] == 1:
			order.append(s)
	order.sort_custom(func(a, b): return line[a].z > line[b].z)
	return order.slice(0, files * ranks)


## The enemy regiment across from it (Total War's lines: each block meets the block in front of it, not the nearest one
## all at once; Mac 2026-11-16, blocks piling on one foe and the rest standing short): by its place along its side's
## line first (the distance across the front, field.opposite times the distance ahead), still in the field, or {}.
func _opposite_foe(r: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	var at: Vector3 = (r["node"] as Node3D).global_position
	var look := _line_front(r)
	var across := look.cross(Vector3.UP).normalized()
	var ahead_w := Data.num(F, "field.opposite", 0.3)
	for x in (sides[1 - int(r["side"])] as Army).rows():
		if x.get("state_name", "") == "rout" or int(x.get("living", 1)) <= 0:
			continue
		var off: Vector3 = (x["node"] as Node3D).global_position - at
		var d := absf(off.dot(across)) + absf(off.dot(look)) * ahead_w
		if d < bd:
			bd = d
			best = x
	return best


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


## The lines have met: a regiment of either side is at blows (the film's clash step waits on it).
func met() -> bool:
	for a in sides:
		for r in a.rows():
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
	mm.instance_count = maxi(1, int(Data.num(F, "field.loose.most", 2048)))  # a fixed room, never resized in flight
	mm.visible_instance_count = 0
	_arrow_buf.resize(mm.instance_count * 12)
	_arrows_shown = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


var _arrow_buf := PackedFloat32Array()  # our own copy of the arrows' transforms, set on the server in one call
var _arrows_shown := 0


## Every arrow in the air along its arc, pointing the way it flies (its flame with it); landed, it does what it does.
## The arrows go to the MultiMesh in one buffer write a frame, its room fixed (battle.json field.loose.most) and only
## the arrows in the air shown (FPS audit 2026-11-15 item 7: resized and written an arrow a server call each frame).
func _fly() -> void:
	var mm := _arrows.multimesh
	var room := mm.instance_count
	var n := 0
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
		if f[6] != null and is_instance_valid(f[6]):
			(f[6] as Node3D).global_position = p  # the flame rides its arrow (an effect, not a traveller)
		if n >= room:
			continue  # more in the air than the room: the rest fly unseen and land as ever
		var q := _on_arc(f, minf(t + 0.02, 1.0))
		var b := Basis.looking_at(q - p if (q - p).length() > 0.0001 else Vector3.FORWARD, Vector3.UP)
		var k := n * 12
		_arrow_buf[k] = b.x.x
		_arrow_buf[k + 1] = b.y.x
		_arrow_buf[k + 2] = b.z.x
		_arrow_buf[k + 3] = p.x
		_arrow_buf[k + 4] = b.x.y
		_arrow_buf[k + 5] = b.y.y
		_arrow_buf[k + 6] = b.z.y
		_arrow_buf[k + 7] = p.y
		_arrow_buf[k + 8] = b.x.z
		_arrow_buf[k + 9] = b.y.z
		_arrow_buf[k + 10] = b.z.z
		_arrow_buf[k + 11] = p.z
		n += 1
	if n > 0:
		RenderingServer.multimesh_set_buffer(mm.get_rid(), _arrow_buf)
	if n != _arrows_shown:
		mm.visible_instance_count = n
		_arrows_shown = n


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
	ai.root.add_child(self)
	_arrows = _arrow_pool()
	if OS.get_cmdline_user_args().has("--probe"):
		print("STORM begun: besiegers by %s, the wall at %s, the town at %s" % [str(camp), str(wall), str(town)])
	var out := Vector3(camp.x - town.x, 0, camp.z - town.z).normalized()
	var counts: Array = Data.value("siege", "storm_host.men", [800, 300])
	var face_in := atan2(-out.x, -out.z)  # the soldier faces +Z: toward the town
	var face_out := atan2(out.x, out.z)
	var inside: Vector3 = wall - out * k("holders_back", 0.9)
	held_col = apart(held_col, foe_col)  # the holders read apart from the besiegers by lightness (Mac is colour-blind)
	for i in 2:
		var side := {"side": i, "field": camp if i == 0 else inside, "face": face_in if i == 0 else face_out,
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
	if not st.is_empty() and not _breach_lit and st.has("gap"):
		# The wall opened: the houses just inside the gap catch (siege.json storm_host.breach_fires), a fact told to the bridge.
		_breach_lit = true
		var into: Vector3 = st.get("inward", Vector3.ZERO)
		Fire.breach_fires((st["gap"] as Vector3) + into * k("breach_in", 1.0), int(k("breach_fires", 3)))
	if phase == "wall":
		_fire_arrows(delta)
		_siege_beats(delta, [0, 1])
	elif phase == "hold":
		_fire_arrows(delta)
		_waves(st, delta)
		_hold_line(st)
		_siege_beats(delta, [0])  # the besiegers not yet sent keep their beat
	else:
		_fire_arrows(delta)  # the archers keep loosing over the wall while the storm goes in (04-siege: the town burns behind the breach)
		_pour_in(st)
	_make_way()
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
	var back := k("front", 0.1)  # the front regiment's front this far before the gap; each behind one block and army.gap back
	for i in _queue.size():
		var r: Dictionary = _queue[i]
		var goal := gap - inward * (back + float(r["d"]) * 0.5)
		back += float(r["d"]) + k("queue", 0.35)
		if (r["goal"] as Vector3).distance_to(goal) > 0.05:
			_go(r, goal, true, "attack" if i == 0 else "ready", face)


## While the wall holds a siege is never still (Stronghold Crusader, Total War: a siege works on a beat; Mac
## 2026-11-15, Oldhall and Saltkeep: "most of the troops are just standing"). Every standing regiment of `side_list`
## keeps its own beat from siege.json storm_host.wall.beats (by its unit, else its role): a stance held a while, never
## the same twice running, each regiment its own lengths and its own start, so no two keep step; now and then a foot
## regiment steps forward toward the wall with shields up (at most wall.forward_most a side out at once) and back
## again; archers (wall.volley) loose over the wall at their own cadence, the holder's back at the besiegers. The wall
## and its breach stay the bridge's: nothing here opens it.
func _siege_beats(dt: float, side_list: Array) -> void:
	var every: Array = Data.value("siege", "storm_host.wall.volley_s", [5.0, 7.0])
	for side in side_list:
		for r in (sides[side] as Army).rows():
			if _queue.has(r) or r.get("in", false) or r.get("broke", false) or r.has("aside"):
				continue
			if not r.has("beat_t"):
				r["beat_t"] = _rng.randf_range(0.0, k("wall.first_s", 5.0))
				r["home"] = (r["node"] as Node3D).global_position
				r["volley_t"] = _rng.randf_range(0.5, float(every[1]))
			if r.get("state_name", "") != "stand":
				continue  # on its way: its beat waits
			if String(r.get("unit", "")) in (Data.value("siege", "storm_host.wall.volley", ["archers"]) as Array):
				r["volley_t"] = float(r["volley_t"]) - dt
				if float(r["volley_t"]) <= 0.0:
					r["volley_t"] = _rng.randf_range(float(every[0]), float(every[1]))
					_siege_volley(r)
					continue
			r["beat_t"] = float(r["beat_t"]) - dt
			if float(r["beat_t"]) <= 0.0:
				_next_beat(r)


## A regiment's next beat: back to its place if it stood forward, else a fresh stance, or a step toward the wall.
func _next_beat(r: Dictionary) -> void:
	var yaw := float(r["yaw"])
	if r.get("forward", false):
		r["forward"] = false
		var back: Array = Data.value("siege", "storm_host.wall.back_s", [3.0, 5.0])
		r["beat_t"] = _rng.randf_range(float(back[0]), float(back[1]))
		_go(r, r["home"], false, "ready", yaw)
		return
	var all: Dictionary = Data.value("siege", "storm_host.wall.beats", {})
	var rows: Array = all.get(String(r.get("unit", "")), all.get(String(r.get("role", "melee")), all.get("melee", [])))
	if rows.is_empty():
		return
	var i := _rng.randi() % rows.size()
	if String((rows[i] as Dictionary).get("clip", "")) == String(r.get("beat", "")):
		i = (i + 1) % rows.size()  # never the same twice running
	var b: Dictionary = rows[i]
	var s: Array = b.get("s", [4.0, 7.0])
	r["beat"] = String(b.get("clip", "ready"))
	r["beat_t"] = _rng.randf_range(float(s[0]), float(s[1]))
	if b.get("step", false) and _forward_out(int(r["side"])) < int(k("wall.forward_most", 1)):
		var home: Vector3 = r["home"]
		var to_wall: Vector3 = ai.get("_wall") - home
		to_wall.y = 0.0
		var goal := home + to_wall.normalized() * k("wall.step", 0.6)
		if _free_for(r, goal, yaw):
			r["forward"] = true
			_go(r, goal, false, r["beat"], yaw)
			return
	r["stance"] = r["beat"]
	_play(r, r["beat"])


func _forward_out(side: int) -> int:
	return (sides[side] as Army).rows().filter(func(x): return x.get("forward", false)).size()


## Whether a regiment's block would stand free at `at` facing `yaw`: no engine, camp piece, house or water there
## (the ground owner, ground.gd area_free); other regiments' ground is theirs to mind.
func _free_for(r: Dictionary, at: Vector3, yaw: float) -> bool:
	var xf := Transform3D(Basis(Vector3.UP, yaw), at)
	var hw := float(r["w"]) * 0.5
	var hd := float(r["d"]) * 0.5
	var poly := PackedVector2Array()
	for c in [Vector3(-hw, 0, -hd), Vector3(hw, 0, -hd), Vector3(hw, 0, hd), Vector3(-hw, 0, hd)]:
		var w: Vector3 = xf * (c as Vector3)
		poly.append(Vector2(w.x, w.z))
	return Footing.area_free(poly, false, null, ["host"])


## An archer regiment's volley over the wall at the nearest regiment of the other side (both sides loose): its men
## draw and loose (the attack clip), wall.arrows arrows fly on a high arc, and the regiment they come down on raises
## its shields (the block clip) a moment: every action gets a reaction. The volleys fell no one: who falls in a siege
## is the bridge's to say.
func _siege_volley(r: Dictionary) -> void:
	var foe := _nearest_foe(r)
	if foe.is_empty():
		return
	r["beat"] = "attack"
	r["beat_t"] = k("wall.draw_s", 1.6)
	_play(r, "attack")
	var node: Node3D = r["node"]
	var fnode: Node3D = foe["node"]
	var man := Data.num("army", "man", 0.22)
	var flight := k("wall.flight", 1.7)
	for i in int(k("wall.arrows", 30)):
		var from := node.to_global(Vector3(_rng.randf_range(-0.5, 0.5) * float(r["w"]), man * 0.8, _rng.randf_range(-0.5, 0.5) * float(r["d"])))
		var to := fnode.to_global(Vector3(_rng.randf_range(-0.5, 0.5) * float(foe["w"]), 0.0, _rng.randf_range(-0.5, 0.5) * float(foe["d"])))
		to.y = main.terrain.height_at(to.x, to.z)
		var land := Callable()
		if i == 0:
			land = func(): _shields_up(foe)
		else:
			land = func(): pass
		_loose(from, to, clock + _rng.randf_range(0.0, 0.4), flight * _rng.randf_range(0.9, 1.1), k("wall.arc", 0.55), land)


## Arrows coming down on a standing regiment: its shields go up for wall.shields_s, then its beat goes on.
func _shields_up(r: Dictionary) -> void:
	if r.get("state_name", "") != "stand" or r.get("broke", false) or _queue.has(r):
		return
	r["beat"] = "block"
	r["beat_t"] = maxf(float(r.get("beat_t", 0.0)), k("wall.shields_s", 1.8))
	_play(r, "block")


## A moving siege engine (siege_camp.gd sets "way_to" and "half" on it while it rolls) never goes through a
## regiment of its own side: one standing in its way steps aside to clear ground by its Mover and, once the engine
## has gone by and its place is free again, steps back (Total War's units parting for a tower). Its route goes round
## the rest (nav_world.gd carves every held block out of the host map, engines' too).
func _make_way() -> void:
	var rolling: Array = get_tree().get_nodes_in_group(&"siege_engines").filter(func(n): return (n as Node).has_meta("way_to"))
	for r in (sides[0] as Army).rows():
		if r.has("aside"):
			var e = r["aside"]
			if (not is_instance_valid(e) or not (e as Node).has_meta("way_to")) and _free_for(r, r["home"], float(r["yaw"])):
				r.erase("aside")
				_go(r, r["home"], false, String(r.get("stance", "ready")), float(r["yaw"]))
			continue
		if r.get("state_name", "") != "stand" or _queue.has(r) or r.get("in", false):
			continue
		for e: Node3D in rolling:
			var from := e.global_position
			var to: Vector3 = e.get_meta("way_to")
			var half := float(e.get_meta("half", 0.3)) + Data.num("army", "gap", 0.35) * 0.5
			var at: Vector3 = (r["node"] as Node3D).global_position
			var along := Vector3(to.x - from.x, 0, to.z - from.z)
			var length := along.length()
			if length < 0.01:
				continue
			along /= length
			var across := Vector3(-along.z, 0, along.x)
			var down := (at - from).dot(along)
			var side := (at - from).dot(across)
			var reach := maxf(float(r["w"]), float(r["d"])) * 0.5 + half
			if down < -reach or down > length + reach or absf(side) > reach:
				continue
			if not r.has("home"):
				r["home"] = at
			r["aside"] = e
			_go(r, at + across * ((signf(side) if side != 0.0 else 1.0) * reach - side), false, String(r.get("stance", "ready")), float(r["yaw"]))
			break


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
		var goal := gap + _block_at(r, i, 3, k("holders_at", 0.35), inward, across)
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
	var across: Vector3 = st["across"]
	var town: Vector3 = ai.town_at if ai.town_at != Vector3.INF else gap + inward * 2.0
	var j := 0
	for r in (sides[1] as Army).rows():
		if not r.get("broke", false):
			r["broke"] = true
			(sides[1] as Army).waver(r, 1.0)
			_go(r, town + _block_at(r, j, 3, 0.0, inward, across), true, "rest", float(r["yaw"]))
		j += 1
	var i := 0
	for r in (sides[0] as Army).rows():
		if not r.get("in", false):
			r["in"] = true
			_go(r, gap + _block_at(r, i, 4, k("spread", 1.2), inward, across), true, "ready", atan2(inward.x, inward.z))
		i += 1


## Where the `i`th of a side's regiments stands round a point, `abreast` to a row (offset, world): rows from `from`
## out along `inward`, each a block's depth and army.gap behind the last, blocks side by side across, a block's width
## and army.gap apart (Mac 2026-11-15: the storm's regiments stood 0.3 apart, heaped in one lump).
func _block_at(r: Dictionary, i: int, abreast: int, from: float, inward: Vector3, across: Vector3) -> Vector3:
	var gap := Data.num("army", "gap", 0.35)
	var w := float(r["w"]) + gap
	var d := float(r["d"]) + gap
	return inward * (from + float(r["d"]) * 0.5 + (i / abreast) * d) + across * (float(i % abreast) - (abreast - 1) * 0.5) * w


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
	var to: Vector3 = Fire.target(ai.town_at, spread, _rng)  # on a roof within reach of the wall
	if to == Vector3.INF:
		to = ai.town_at + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
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
