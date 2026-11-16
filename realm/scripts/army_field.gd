extends Node3D
## The massed fight: hosts of regiments (army.gd: one VAT draw and one banner each) meeting in the field or storming
## a breach (the army layer, docs/research/army-layer-2026-11-12.md; Total War's field battle and its storm through
## the breach, Warcraft III's worn colour and density). Who wins is the realm's (Freeciv decides, the bridge
## tells): every man fights to the death (Mac 2026-11-17: "no fleeing, fight to the death"); the larger host hits harder. Every regiment moves by its Mover on the
## realm's host map (nav_world.gd: round water and houses, every other block carved out), and decides by its mind (a LimboHSM from a data/army.json minds row,
## army_mind.gd). Numbers in data/battle.json field and data/siege.json storm_host (docs/TUNING.md).
##
## A field battle (stage(), from scenes.gd whenever the bridge tells of a battle, the one way a battle is fought; the test aid --army-battle=<men per side>[:foe|crown]): both hosts form facing each other, then
## each regiment's mind (minds.regiment) takes it through: archers loose volleys that arc onto the enemy's ranks
## and fell men where they land; the foot advance and stop at sword's length, front ranks cutting, reeling and
## falling, the fallen left where they fell, the men behind stepping into their cells, until one side has
## no man standing; the victors hold the field. In play it is quiet, sized from the men who really fought, ends as Freeciv decided, never moves the camera,
## and is gone field.play.linger seconds after. The test aid prints "BATTLE …" lines and frames itself.
##
## A storm (storm(), raised with every siege beside its assault parties, army_assault.gd, whose breach drives it once
## Freeciv assaults the town): the besiegers in line on the camp side, the holder's drawn up inside the wall
## (minds.storm_regiment). Before the gap opens the besiegers stand ready and loose fire arrows over the wall: they
## arc into the town and now and then a roof catches (fire.gd kindle). Once the gap is open the besiegers' regiments
## march up in waves and queue into it, the front one at blows in the gap, the holder's regiments meeting them on
## the town side, their banners wavering as the fight goes on. When the holder's block breaks, its regiments run
## into the town and the besiegers pour in through the gap and spread out among the houses. Never moves the camera.

const Combat := preload("res://scripts/army_combat.gd")  # who bleeds at blows: the one decider of losses
const BattleOrders := preload("res://scripts/battle_orders.gd")
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
const Army := preload("res://scripts/army.gd")
const FieldHost := preload("res://scripts/field_host.gd")  # a host on a battle's field
const Mover := preload("res://scripts/mover.gd")  # the one way to move (CLAUDE.md)
const Mind := preload("res://scripts/army_mind.gd")
const Footing := preload("res://scripts/ground.gd")  # the one owner of where a body may stand: a regiment stepping out asks it
const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const Awareness := preload("res://scripts/awareness.gd")  # the season's length: the field keeps its dead a season
const Fire := preload("res://scripts/fire.gd")
const F := "battle"  # data/battle.json, its field block
const FieldCells := preload("res://scripts/field_cells.gd")  # the field as cells: the one decider of where every man stands
const Troops := preload("res://scripts/troops.gd")  # each regiment as its Troop: the battle asks the troop, never its role
const Formation := preload("res://scripts/army_formation.gd")  # a regiment's formation templates (horse: the wedge)

var orders := ["", ""]
var cells: FieldCells  # the field as cells, one man a cell: who stands where and whom he fights (field_cells.gd)
var _cell_t := 0.0  # seconds since the field's last moment
var _order_t := 0.0
var _changed := false  # the foe has changed his order once (_foe_order)
var _alarm_t := 0.0  # seconds to the battle's next alarm to the folk about it (_alarm)  # the battle order each side stands in (battle_orders.gd)
var main: Node
var men := 0
var loser := 1  # the side losing now (_day: the fewer men standing), and once a side has none standing, the side beaten
var sides: Array = []  # the two hosts
var clock := -1.0  # seconds since the battle began; below 0 while the hosts deploy
var _arrows: MultiMeshInstance3D
var _flights: Array = []  # [from, to, start, flight, arc, on_land (Callable), light (Node3D or null)]
var _rng := RandomNumberGenerator.new()
var _dist := 0.0  # the test aid's lens distance: the town view's (camera.json town_view.dist), or --dist
var _focus := Vector3.ZERO
var _yaw := 0.0  # the battle lens's heading (_frame: behind the crown's line)
var _yawed := false
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
	add_to_group(&"field_battles")  # the one battle on the field: the realm's own are told, not shown, while it's fought (two battles in one frame read as one heap)
	while main.terrain.width == 0 or not main.terrain.built or (Army._rec("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5, false).timeout
	# The ground the realm's own battles are fought on (scene_kinds/battle.gd battlefield: open land clear of every
	# town and farm), as near the crown's seat as there is: never among its houses and fields.
	var spec := {"side": 0, "shape": "line", "pick": _pick.bind(0, {}, 0.0, "the crown")}
	var site: Vector3 = await _open_field_near_seat()
	print("BATTLE the field: %s" % ("open ground at %s" % str(site) if site != Vector3.INF else "none found, the seat's muster ground"))
	if site != Vector3.INF:
		spec["field"] = site
		spec["face"] = 0.0
	var crown: Army = FieldHost.new(main, men, spec)
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
	var foe_at := crown.field() + fwd * gap
	var rise: float = main.terrain.height_at(foe_at.x, foe_at.z) - main.terrain.height_at(crown.field().x, crown.field().z)
	var foe: Army = FieldHost.new(main, men, {"side": 1, "shape": "line", "field": foe_at, "face": face + PI,
		"colour": foe_col, "worn": foe_worn, "house": house,
		"mirror": true, "pick": _pick.bind(1, BattleOrders.count(crown.rows()), rise, String(house.get("name", "the foe")))})
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
		var other: Vector3 = at - Vector3(sin(face), 0, cos(face)) * gap if i == 0 else (made[0] as Army).field()
		var rise: float = main.terrain.height_at(field.x, field.z) - main.terrain.height_at(other.x, other.z)
		var side: Army = FieldHost.new(main, 0, {"side": i, "field": field, "face": face, "colour": colour, "worn": worn, "house": house, "quiet": true,
			"shape": "line", "mirror": i == 1, "pick": _pick.bind(i, _count_kinds((play["kinds"] as Array)[1 - i], per, most), rise, String(house.get("name", "")))})
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


## Open ground for the test aid's battle near the crown's seat (/world seatId, else Kingsmere): the realm's battles'
## own chooser (scene_kinds/battle.gd battlefield). Vector3.INF when there is none.
func _open_field_near_seat() -> Vector3:
	var want := int(Army._rec("seatId", -1))
	var seat := {}
	for c in Army._rec("cities", []):
		if int(c.get("id", -2)) == want or (seat.is_empty() and String(c.get("name", "")) == "Kingsmere"):
			seat = c
	var kind: Variant = main.scenes.kind("battle") if main.get("scenes") else null
	if seat.is_empty() or kind == null:
		return Vector3.INF
	while not main.scenes._towns_up():
		await get_tree().create_timer(0.5, false).timeout
	return kind.battlefield(main.terrain.world_pos(float(seat.get("x", 0)), float(seat.get("y", 0))))


## The order a side stands in (battle_orders.gd, its commander's choice): asked by its Army as its regiments form.
## foe: the other side's head count ({} when not yet known: the test aid's crown, which forms first, reads it as its
## own); rise: how much higher its ground stands than the foe's.
func _pick(regiments: Array, side: int, foe: Dictionary, rise: float, house: String) -> String:
	var own := BattleOrders.count(regiments)
	var key := BattleOrders.pick(own, own if foe.is_empty() else foe, rise, house, _rng)
	for a in (OS.get_cmdline_user_args() if play.is_empty() else PackedStringArray()):
		if a.begins_with("--battle-order="):  # the test aid: both sides in one order, to film it
			key = a.substr(15)
	orders[side] = key
	_say({}, "%s stands in %s" % [house.capitalize() if house.begins_with("the") else house, BattleOrders.title(key).to_lower()])
	print("BATTLE %s stands in %s (%d men against %d, ground %+.1f)" % [house, BattleOrders.title(key), int(own["men"]),
		int((own if foe.is_empty() else foe)["men"]), rise])
	return key


## A side's head count from its Freeciv kinds (the realm's battle: field.play.perCompany men each, at most `most`).
static func _count_kinds(kinds: Array, per: int, most: int) -> Dictionary:
	var out := {"men": 0, "melee": 0, "ranged": 0, "cavalry": 0}
	var units: Dictionary = Data.value("army", "units", {})
	for j in mini(kinds.size(), most):
		var role := "melee"
		for u in units:
			if ((units[u] as Dictionary).get("freeciv", []) as Array).has(String(kinds[j])):
				role = String((units[u] as Dictionary).get("role", "melee"))
				break
		out[role] = int(out.get(role, 0)) + 1
		out["men"] = int(out["men"]) + per
	return out


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
	# One rule for every soldier (Mac 2026-11-17: "everything is a cell"): every man of both hosts takes the cell he
	# stands on, and from here the field's rule moves him (field_cells.gd); every troop the same, whatever its kind.
	cells = FieldCells.new((sides[0] as Army).field(), (sides[1] as Army).field(), Data.num(F, "field.cells.size", 0.26))
	for i in 2:
		cells.order(i, String(orders[i]))
		for r in (sides[i] as Army).rows():
			_enlist(r, i, "regiment")
			_into_cells(r)
			_send(r, &"advance")
	if player_side() >= 0:
		add_child(preload("res://scripts/battle_orders_bar.gd").new(self))  # the King's orders in the fight (battle_orders_bar.gd; off for a night, back 2026-11-17: "get the different formation strategies back")
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
	(r["army"] as Army).let_go(r)  # on the open field no block holds ground in the walk map: the crowd keeps blocks apart, and a held block re-carved the map at every step (its own way bent round where it stood a moment ago; Mac 2026-11-16, the line fanned out and fell behind)
	mo.wheel = 0.0
	preload("res://scripts/on_screen.gd").keep_on(r["node"])  # it fights on whether seen or not (field_clash_probe)
	Mind.make(kind, r, r["node"], self)


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
		if play.is_empty():
			_frame(delta)
		return
	clock += delta
	if OS.get_cmdline_user_args().has("--track"):  # the test aid: one block's step each frame, to read its motion
		var tr: Dictionary = (sides[0] as Army).rows()[1]
		var tp: Vector3 = (tr["node"] as Node3D).global_position
		var was: Vector3 = tr.get("track_at", tp)
		tr["track_at"] = tp
		print("TRACK %.3f dt %.4f step %.4f speed %.3f yaw %.3f state %s gait %s" % [clock, delta, Vector2(tp.x - was.x, tp.z - was.z).length(), Vector2(tp.x - was.x, tp.z - was.z).length() / maxf(delta, 0.0001), (tr["node"] as Node3D).rotation.y, tr.get("state_name", ""), tr.get("gait", "")])
	_fly()
	_keep_up()
	_alarm(delta)
	_step_cells(delta)
	_foe_order(delta)
	_breathe(delta)
	_day()
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
		_report = 1.0 if OS.get_cmdline_user_args().has("--where") else 2.0
		var s := PackedStringArray()
		for i in 2:
			var states := {}
			var left := 0
			for r in (sides[i] as Army).rows():
				states[r["state_name"]] = int(states.get(r["state_name"], 0)) + 1
				left += int(r["living"])
			s.append("%s %d men %s" % ["crown" if i == 0 else "foe", left, str(states)])
		print("BATTLE t=%.0f %s; arrows in flight %d; fps=%d" % [clock, " | ".join(s), _flights.size(), Engine.get_frames_per_second()])
		if OS.get_cmdline_user_args().has("--where"):  # the test aid: every block's place against its line's, to read the shape
			for i in 2:
				for r in (sides[i] as Army).rows():
					var fighting := (r.get("contact", []) as Array).size()
					var cs: Array = (r.get("cell_men", []) as Array).map(func(m): return str(m["c"]))
					print("WHERE %d %s %s at grips %d cells %s" % [i, r["role"], r["state_name"], fighting, ",".join(cs)])
					var wp: Vector3 = (r["node"] as Node3D).global_position
					print("WORLD %d %s %s %.3f %.3f %.3f" % [i, r["role"], r["state_name"], wp.x, wp.z, (r["node"] as Node3D).rotation.y])
					# Where its men are by the rule (cells), by their bodies (runners) and as drawn (figures), each their middle.
					var by := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
					var nm := 0
					var marks: PackedVector3Array = r.get("marks", PackedVector3Array())
					var run: Dictionary = r.get("runners", {})
					for m in (r.get("cell_men", []) as Array):
						var k := int(m["s"])
						if not run.has(k) or not is_instance_valid(run[k]["node"]) or k >= marks.size():
							continue
						by[0] += cells.world(m["c"])
						by[1] += (run[k]["node"] as Node3D).global_position
						by[2] += (r["node"] as Node3D).to_global(marks[k])
						nm += 1
					if nm > 0:
						print("BODY %d %s cells %.2f,%.2f runners %.2f,%.2f figures %.2f,%.2f" % [i, r["role"], by[0].x / nm, by[0].z / nm, by[1].x / nm, by[1].z / nm, by[2].x / nm, by[2].z / nm])


## The battle is over and gone (casebook, War and sieges: the field remembers): the living march off (they fade), the
## fallen lie where they fell, and the standard of every troop cut down lies in the grass where its last man fell, for
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
			if r.has("fell_at"):
				var std: Node3D = Heraldry.standard(r.get("house", {}), r.get("colour", Color.GRAY), Data.num(F, "field.play.dropped", 0.45))
				var at: Vector3 = r["fell_at"]
				add_child(std)
				std.global_position = Vector3(at.x, main.terrain.height_at(at.x, at.z) + 0.01, at.z)
				std.rotation = Vector3(0.0, _rng.randf() * TAU, PI * 0.47)  # fallen over, its pole along the ground
	for a in sides:
		var b = (a as Army).banners
		for n in [b.standard]:
			if n is Node3D and is_instance_valid(n):
				(n as Node3D).visible = false  # the host's standard goes with the living
	get_tree().create_timer(maxf(1.0, Awareness.season_seconds * Data.num(F, "field.play.aftermath", 1.0)), false).timeout.connect(queue_free)


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


## The day (Mac 2026-11-17: "no fleeing, fight to the death"): every troop fights until its last man falls; the
## side with fewer men standing is losing (`loser`, the lens's), and when one side has none standing the other holds
## the field.
func _day() -> void:
	if _over:
		return
	var men := _standing_men()
	loser = 0 if men[0] < men[1] else 1
	for i in 2:
		if men[i] == 0:
			loser = i
			_over = true
			print("BATTLE the %s fall; the %s hold the field at t=%.0f" % ["crown's men" if i == 0 else "foe", "foe" if i == 0 else "crown's men", clock])
			_say({}, "The day is %s" % ("lost" if i == 0 else "won"))
			for r in (sides[1 - i] as Army).rows():
				_send(r, &"won")
			return


## Each side's men standing (figures alive).
func _standing_men() -> Array:
	var men := [0, 0]
	for i in 2:
		for r in (sides[i] as Army).rows():
			men[i] += maxi(int(r.get("living", 0)), 0)
	return men


## Each side's morale: the larger host has the heart (Mac 2026-11-17: "if you're the larger force you'll have a
## better chance"): its men standing over the foe's, to field.combat.morale.power, held between least and most.
func _morale() -> Array:
	var men := _standing_men()
	var k: Dictionary = Data.value(F, "field.combat.morale", {})
	var out := [1.0, 1.0]
	for i in 2:
		var ratio := float(men[i]) / maxf(float(men[1 - i]), 1.0)
		out[i] = clampf(pow(ratio, float(k.get("power", 0.5))), float(k.get("least", 0.5)), float(k.get("most", 2.0)))
	return out


## Steel near: the battle is news where it is fought (scene_kinds.gd battle, hostile), every field.alarm_every seconds
## while it lasts, so townsfolk and farmers within its reach drop what they do and run (npc_mind.gd danger), those
## further off stop and watch (Total War and Manor Lords: a village empties when an army comes).
func _alarm(dt: float) -> void:
	_alarm_t -= dt
	if _alarm_t > 0.0 or _over or main.get("awareness") == null:
		return
	_alarm_t = Data.num(F, "field.alarm_every", 6.0)
	var mid := Vector3.ZERO
	var n := 0
	for a in sides:
		for r in (a as Army).rows():
			mid += (r["node"] as Node3D).global_position
			n += 1
	if n > 0:
		main.awareness.emit("battle", mid / n)


## Every troop's wind with what it does (army_combat.gd breathe).
func _breathe(dt: float) -> void:
	for i in 2:
		for r in (sides[i] as Army).rows():
			Combat.breathe(r, dt)


## Every man at grips strikes his man once a moment of the field (field_cells.gd rule 1; Mac 2026-11-17: "it
## shouldn't take so long to kill", "if they die fast, they'll replace fast"): his blow fells him at army_combat.gd's
## odds, and the man behind steps into the cell at the next moment.
func _blows() -> void:
	var heart := _morale()
	for m in cells.men:
		if not m["fight"] or m["tgt"] == null:
			continue
		var e: Dictionary = m["tgt"]
		var a: Dictionary = m["r"]
		var r: Dictionary = e["r"]
		if int(r.get("living", 0)) <= 0 or (r["alive"] as PackedByteArray)[int(e["s"])] == 0:
			continue
		var odds := Combat.blow(a, float(heart[int(a["side"])]), String(orders[int(a["side"])]), r, String(orders[int(r["side"])]))
		if _rng.randf() < odds:
			_fell(r, _men_a_figure(r), true, int(e["s"]))


## The men one figure of r stands for (its men over its figures).
static func _men_a_figure(r: Dictionary) -> int:
	return maxi(1, ceili(float(r["men"]) / maxf(float(r["figures"]), 1.0)))


## The lens on the whole battle (the test aid only; Total War's tactical view: Mac 2026-11-16, "I can't see the
## strategy play out ... maybe its a zoom level problem"): over the middle of every regiment still in the field, from
## behind the crown's line, as far back as frames them all (field.camera.fit times their span across or along the
## lens, never under field.camera.dist), at field.camera.pitch: every block, flank and reserve in sight at once.
func _frame(delta: float) -> void:
	if main.rig == null:
		return
	var crown: Army = sides[0]
	var face := crown.facing()
	var fwd := Vector3(sin(face), 0, cos(face))
	var right := Vector3(cos(face), 0, -sin(face))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for side in _rows():
		for r in side:
			if int(r.get("living", 0)) <= 0:
				continue
			var p: Vector3 = (r["node"] as Node3D).global_position
			var half := Vector2(float(r.get("w", 0.0)), float(r.get("d", 0.0))) * 0.5
			var q := Vector2(p.dot(right), p.dot(fwd))
			lo = Vector2(minf(lo.x, q.x - half.x), minf(lo.y, q.y - half.y))
			hi = Vector2(maxf(hi.x, q.x + half.x), maxf(hi.y, q.y + half.y))
	if lo.x == INF:
		return
	var mid := (lo + hi) * 0.5
	var want := right * mid.x + fwd * mid.y
	want.y = main.terrain.height_at(want.x, want.z)
	var k := minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2))
	_focus = want if not _yawed else _focus.lerp(want, k)
	var span := maxf((hi.x - lo.x) * Data.num(F, "field.camera.fit_across", 1.0), (hi.y - lo.y) * Data.num(F, "field.camera.fit", 0.85))
	var d := maxf(maxf(span, Data.num(F, "field.camera.dist", 5.0)), main.rig.min_distance)
	_dist = d if not _yawed else lerpf(_dist, d, k)
	_yaw = face + Data.num(F, "field.camera.quarter", 0.0)
	_yawed = true
	main.rig.snap(_focus, _dist, _yaw)
	main.rig.tilt = main.rig.tilt_for(Data.num(F, "field.camera.pitch", 45.0), _dist)
	main.rig.goal_tilt = main.rig.tilt


# --- A regiment's mind (data/army.json minds.regiment) ----------------------------------------------------

func _ready_in(r: Dictionary) -> void:
	_play(r, "ready")


func _walk_in(r: Dictionary) -> void:
	_play(r, "walk")
	r["gait"] = "walk"
	r["moving"] = "walk"
	r.erase("ran")
	r.erase("struck")
	r.erase("duel")
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


## Both hosts' regiments, [side 0's, side 1's].
func _rows() -> Array:
	return [(sides[0] as Army).rows(), (sides[1] as Army).rows()]


func _may_hold(r: Dictionary) -> bool:
	return _over and int(r["side"]) != loser


## Shooters (field_cells.gd rule 2): its men stand and loose, each at the man in range the rule chose him (not in
## the press), a volley every field.volley.every seconds; of field.volley.kills arrows, those army_combat.gd arrows
## lets land fell their man.
func _volley(r: Dictionary, dt: float) -> void:
	_walk_men(r, dt)
	var t: Variant = r.get("target")
	if not (t is Dictionary) or int((t as Dictionary).get("living", 0)) <= 0:
		return
	var foe: Dictionary = t
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
	var fells := Combat.arrows(foe, _rng.randi_range(int(kills[0]), int(kills[1])), String(orders[int(foe["side"])]))
	var man := Data.num("army", "man", 0.22)
	var draw := Data.num(F, "field.volley.draw_s", 0.8)
	var step := Data.num(F, "field.volley.step", 0.15)
	var spread := Data.num(F, "field.volley.spread", 0.05)
	var most := int(Data.num(F, "field.volley.arrows", 70))
	# The volley in step (research note step 5; Total War's volleys): every archer who has a man to shoot (field_cells.gd
	# rule 2: the one the rule chose him) draws at once, and they loose together draw_s later, within `step` of each
	# other; each arrow on a true ballistic arc (field.volley.angle and gravity) onto his man, a little off him (spread).
	var shot := 0
	for m in (r.get("cell_men", []) as Array):
		var s := int(m["s"])
		var aim: Variant = m["shot"]
		if alive[s] == 0 or aim == null or shot >= most:
			continue
		var e: Dictionary = aim
		shot += 1
		vat.update_instance_track(s, army.track(r, "attack"))
		vat.update_instance_animation_offset(s, _rng.randf_range(0.0, 0.05))
		(r["back"] as Dictionary)[s] = clock + draw + 0.6
		var from := node.to_global(local[s]) + Vector3(0, man * 0.8, 0)
		var to := cells.world(e["c"]) + Vector3(_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
		to.y = main.terrain.height_at(to.x, to.z)
		var arc := ballistic(from, to, Data.num(F, "field.volley.angle", 0.75), Data.num(F, "field.volley.gravity", 3.0))
		var lands := shot <= fells
		var hit: Dictionary = e["r"]
		var who := int(e["s"])
		_loose(from, to, clock + draw + _rng.randf_range(0.0, step), arc.x, arc.y,
			func(): if lands: _fell(hit, _men_a_figure(hit), false, who))


## A shaft's flight from `from` to `to` (world) loosed at `angle` (radians over the flat) under `gravity` (world units a
## second squared): the speed that carries it there, so (flight seconds, its arc's top over its length as _on_arc
## draws it: g T^2 / 8 over the range). A parabola in time with the run uniform is the ballistic path without drag.
static func ballistic(from: Vector3, to: Vector3, angle: float, gravity: float) -> Vector2:
	var run := maxf(Vector2(to.x - from.x, to.z - from.z).length(), 0.01)
	var g := maxf(gravity, 0.01)
	var v := sqrt(g * run / maxf(sin(2.0 * angle), 0.05))
	var t := 2.0 * v * sin(angle) / g
	return Vector2(t, g * t * t / 8.0 / maxf(from.distance_to(to), 0.01))


## Every man of r walks to his cell (field_cells.gd decides it; Mac 2026-11-17: "everything is a cell") by his own
## Mover, a cell a tick, facing the man he fights or shoots, else the way he goes; the block's own body (its banner,
## its plate) keeps to its men's middle.
func _advance(r: Dictionary, dt: float) -> void:
	_walk_men(r, dt)


## Its side's front (flat, world): the way its host's line faces (Army.facing), one for every regiment of the side.
func _line_front(r: Dictionary) -> Vector3:
	var face: float = (r["army"] as Army).facing()
	return Vector3(sin(face), 0, cos(face))


func _fight_in(r: Dictionary) -> void:
	_play(r, "ready")
	r["man_gait"] = {}


func _fight_out(r: Dictionary) -> void:
	r["contact"] = []


## At blows (field_cells.gd rule 1): every man with a foe in the next cell stands and fights him on his own beat;
## the rest of the regiment keeps walking to its cells. Its fallen are those at grips (_fell, _front_men); what it
## loses is _bleed's (army_combat.gd).
func _fight(r: Dictionary, dt: float) -> void:
	_walk_men(r, dt)


## Every regiment's men into the field's cells, each his own body walked by his Mover (the block's VAT draw laid where
## he is: _follow_runners).
func _into_cells(r: Dictionary) -> void:
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var alive: PackedByteArray = r["alive"]
	var runners := {}
	for s in local.size():
		if alive[s] == 0:
			continue
		var man := Node3D.new()
		man.name = "Fighter"
		add_child(man)
		man.global_position = node.to_global(local[s])
		man.rotation.y = node.global_rotation.y
		var mo: Node = Mover.of(man)
		mo.clip = ""  # his figure is the block's VAT draw
		mo.fights(true)
		runners[s] = {"node": man}
		cells.add(r, s, man.global_position)
	r["runners"] = runners
	r["man_gait"] = {}


## A moment of the field (field.cells.tick seconds): the rule moves every man (field_cells.gd), then each regiment
## reads what its men do: any at grips, it fights; any shooting, it looses; else it comes on.
func _step_cells(delta: float) -> void:
	if cells == null:
		return
	_cell_t += delta
	var tick := Data.num(F, "field.cells.tick", 0.26)
	if _cell_t < tick:
		return
	_cell_t -= tick
	cells.tick()
	_blows()
	var by := {}
	for m in cells.men:
		var id := int((m["r"] as Dictionary)["id"]) * 2 + int(m["side"])
		if not by.has(id):
			by[id] = []
		(by[id] as Array).append(m)
	for i in 2:
		for r in (sides[i] as Army).rows():
			var st := String(r.get("state_name", ""))
			if st == "hold" or int(r.get("living", 0)) <= 0:
				continue
			var mine: Array = by.get(int(r["id"]) * 2 + i, [])
			r["cell_men"] = mine
			var grips: Array = []
			var shot: Dictionary = {}
			for m in mine:
				if m["fight"]:
					grips.append(int(m["s"]))
					r["foe"] = (m["tgt"] as Dictionary)["r"]
				elif m["shot"] != null:
					shot = (m["shot"] as Dictionary)["r"]
			r["contact"] = grips
			if not grips.is_empty():
				if st != "fight":
					_send(r, &"engage")
			elif not shot.is_empty():
				r["target"] = shot
				if st != "volley":
					_send(r, &"volley")
			elif st != "advance":
				r["foe"] = null
				_send(r, &"advance")


## Each man of r on his way to his cell, or standing at grips (see _advance).
func _walk_men(r: Dictionary, _dt: float) -> void:
	var runners: Dictionary = r.get("runners", {})
	if cells == null or runners.is_empty():
		return
	var tick := Data.num(F, "field.cells.tick", 0.26)
	var pace := cells.size / tick * Data.num(F, "field.cells.pace", 1.1)
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var gait: Dictionary = r["man_gait"]
	var swing: Dictionary = r["swing"]
	var back: Dictionary = r["back"]
	var range_s: Array = Data.value(F, "field.fight.swing", [0.7, 1.8])
	var hit_odds := Data.num(F, "field.fight.hitOdds", 0.2)
	var block_odds := Data.num(F, "field.fight.blockOdds", 0.25)
	var mid := Vector3.ZERO
	var count := 0
	for m in (r.get("cell_men", []) as Array):
		var s := int(m["s"])
		if not runners.has(s) or not is_instance_valid(runners[s]["node"]):
			continue
		var man: Node3D = runners[s]["node"]
		var at := man.global_position
		mid += at
		count += 1
		var goal := cells.world(m["c"])
		goal.y = main.terrain.height_at(goal.x, goal.z)
		var other: Variant = m["tgt"] if m["fight"] else m["shot"]
		var look := _line_front(r)
		if other != null:
			var o: Dictionary = other
			var op: Vector3 = cells.world(o["c"])
			look = Vector3(op.x - at.x, 0.0, op.z - at.z).normalized()
		elif Vector2(goal.x - at.x, goal.z - at.z).length() > 0.02:
			look = Vector3(goal.x - at.x, 0.0, goal.z - at.z).normalized()
		var far := Vector2(goal.x - at.x, goal.z - at.z).length() > 0.03
		Mover.of(man).toward(goal, pace / float(m["dur"]) if far else 0.0, look)
		var want := "walk" if far else "ready"
		if m["fight"]:
			want = "grips"
			if not swing.has(s):
				swing[s] = clock + _rng.randf_range(0.0, float(range_s[1]))
			if clock >= float(swing[s]):
				swing[s] = clock + _rng.randf_range(float(range_s[0]), float(range_s[1]))
				var roll := _rng.randf()
				vat.update_instance_track(s, army.track(r, "hit" if roll < hit_odds else ("block" if roll < hit_odds + block_odds else "attack")))
				back[s] = clock + 0.9
		elif String(gait.get(s, "")) != want and not back.has(s):
			vat.update_instance_track(s, army.track(r, want))
			vat.update_instance_animation_offset(s, _rng.randf())
		gait[s] = want
	_follow_runners(r)
	if count > 0:
		# The block's body at its men's middle: its banner and plate go with them.
		mid /= float(count)
		Mover.of(r["node"]).toward(mid, pace * 1.2, _line_front(r))


## The King's order in the fight (Mac 2026-11-16: "if I'm given an option to change the formation, regroup etc ... I'd
## love to see that happen real time"): side `side` comes on by order `key` from now (field_cells.gd order: a regroup
## steps straight back and stands, a shield wall comes on at its long slow step), its guard the order's
## (army_combat.gd order_guard).
func reorder(side: int, key: String) -> void:
	if sides.size() < 2 or clock < 0.0 or not (Data.value("battle_orders", "orders", {}) as Dictionary).has(key):
		return
	orders[side] = key
	if cells != null:
		cells.order(side, key)
	_say({}, "%s: %s" % ["The crown" if side == 0 else "The foe", BattleOrders.title(key)])


## The foe losing the day (his men standing under field.losing of the King's) changes his order once:
## shields locked (field.fallback).
func _foe_order(dt: float) -> void:
	_order_t -= dt
	if _order_t > 0.0 or _changed:
		return
	_order_t = 1.0
	var foe := 1 - player_side() if player_side() >= 0 else -1
	if foe < 0:
		return
	var worth := _standing_men()
	if float(worth[foe]) >= Data.num(F, "field.losing", 0.65) * float(worth[1 - foe]):
		return
	var key := String(Data.value(F, "field.fallback", "shield_wall"))
	if String(orders[foe]) == key:
		return
	_changed = true
	reorder(foe, key)


## The side the King commands in this fight: the crown's (side 0 in the test aid; in play, the side whose house is
## the crown's), or -1 when two lords fight and the King only watches.
func player_side() -> int:
	if sides.size() < 2:
		return -1
	if play.is_empty():
		return 0
	for i in 2:
		if ((sides[i] as Army).battle.get("house", {}) as Dictionary).get("crown", false):
			return i
	return -1


## A beat of the battle order, said where the player reads the realm's news (ui.toast), once per regiment and beat.
func _say(r: Dictionary, text: String) -> void:
	if String(r.get("said", "")) == text:
		return
	r["said"] = text
	print("BATTLE beat: %s" % text)
	var ui: Variant = main.get("ui")
	if ui and ui.has_method("toast"):
		ui.toast(text)


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


## The victors hold the field: they raise a cheer where they stand (Warcraft III and Total War: the winners cheer as
## the beaten run; every action gets a reaction), field.play.cheer_s seconds, then stand at ease.
func _hold(r: Dictionary) -> void:
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
func _fell(r: Dictionary, men: int, front: bool, who := -1) -> void:
	r["lost"] = int(r.get("lost", 0)) + men
	var n := int(floor(float(r["lost"]) / maxf(float(r["men"]), 1.0) * int(r["figures"]) + 0.0001)) - (int(r["figures"]) - int(r["living"]))  # figures now due to fall
	var alive: PackedByteArray = r["alive"]
	var vat: VATMultiMeshInstance3D = r["vat"]
	var army: Army = r["army"]
	var node: Node3D = r["node"]
	var local: PackedVector3Array = r["local"]
	var pool: Array = [who] if who >= 0 and (r["alive"] as PackedByteArray)[who] == 1 else (_front_men(r) if front else [])
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
		var run: Dictionary = r.get("runners", {})
		if run.has(s):
			if is_instance_valid(run[s]["node"]):
				(run[s]["node"] as Node3D).queue_free()
			run.erase(s)
		vat.update_instance_track(s, army.track(r, "death"))
		if fade:
			vat.fade_out_instance(s, 1.0, 0.0)  # no fall of his own (army.json meshes.<dir>.fallen): never left standing
		(r["dead_at"] as Dictionary)[s] = node.to_global(local[s])
		if int(r["living"]) <= 0:
			r["fell_at"] = node.to_global(local[s])  # its standard lies where its last man fell (_aftermath)
		(r["swing"] as Dictionary).erase(s)
		(r["back"] as Dictionary).erase(s)
	r["alive"] = alive
	army.set_strength(int(r["id"]), float(r["living"]) / maxf(float(r["figures"]), 1.0))


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
			continue  # the fallen lie still
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
			if alive[s] == 1:
				vat.update_instance_track(s, ready)


# --- Where things stand -----------------------------------------------------------------------------------

## The living men of its front ranks (field.fight.ranks), by their place in the line: the front is +Z.
func _front_men(r: Dictionary) -> Array:
	var alive: PackedByteArray = r["alive"]
	var grips: Array = (r.get("contact", []) as Array).filter(func(x): return alive[int(x)] == 1)
	if not grips.is_empty():
		return grips  # loose at blows: those at grips with a foe man fall (_press)
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


## The nearest enemy regiment still in the field, or {}.
func _nearest_foe(r: Dictionary) -> Dictionary:
	var best := {}
	var bd := INF
	var at: Vector3 = (r["node"] as Node3D).global_position
	for x in (sides[1 - int(r["side"])] as Army).rows():
		if int(x.get("living", 1)) <= 0:
			continue
		var d := at.distance_squared_to((x["node"] as Node3D).global_position)
		if d < bd:
			bd = d
			best = x
	return best


## The lines have met: a regiment of either side is at blows (the film's clash step waits on it).
func met() -> bool:
	for a in sides:
		for r in a.rows():
			if r.get("state_name", "") == "fight":
				return true
	return false


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
