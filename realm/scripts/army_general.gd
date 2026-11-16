extends Node
## A host's captain in a field battle: the one decider of what its regiments do (Total War's battle AI: one general
## reads the field and gives every unit its task; Mac 2026-11-16: "the troops aren't acting like an army", "per host
## there should be one captain or general"). Its mind is a LimboHSM from data/army.json minds.general (army_mind.gd):
##   - advance: the whole line marches as one (army_field.gd _march_lines asks marching());
##   - hold: the line stands and the foe must come to it (an order that holds: the shield wall, a regroup);
##   - charge: within field.charge.from the whole front runs in together, each block on the foe in its lane;
##   - melee: the lines locked, it thinks every field.general.think seconds: a block whose foe broke wheels onto the
##     flank of the nearest foe fighting a neighbour; the horse goes round at the flank of a foe block at blows (the
##     hammer on the foot's anvil), round again after every charge; archers loose on the nearest foe not at blows; a
##     worn block is relieved by the second line; the horse reserve rides out; a captain losing the day changes his
##     order (the foe's only: the King gives his own).
## Its regiments only carry out their task (army_field.gd: r.task, the foe a foot block closes on; r.target, the
## foe its horse rides at or its archers loose at). Numbers in data/battle.json field.general.

const Mind := preload("res://scripts/army_mind.gd")
const Data := preload("res://scripts/data.gd")
const Morale := preload("res://scripts/army_morale.gd")
const BattleOrders := preload("res://scripts/battle_orders.gd")
const F := "battle"

var field: Node  # army_field.gd
var side := 0
var me := {}  # its mind's own (army_mind.gd: state_name, hsm)
var _think := 0.0
var _changed := false  # the foe's captain changes his order once a battle


func _init(f: Node, s: int) -> void:
	field = f
	side = s
	name = "General%d" % s


func _ready() -> void:
	Mind.make("general", me, self, self)
	plan()


## The host's name as the realm says it ("The crown", "House Wolfholt").
func who() -> String:
	if side == field.player_side():
		return "The crown"
	var house: Dictionary = (field.sides[side]).battle.get("house", {})
	return String(house.get("name", "The foe"))


func _rows() -> Array:
	return (field.sides[side]).rows()


func _foes() -> Array:
	return (field.sides[1 - side]).rows().filter(func(x): return _standing(x))


static func _standing(x: Variant) -> bool:
	return x is Dictionary and String((x as Dictionary).get("state_name", "")) != "rout" and int((x as Dictionary).get("living", 0)) > 0


## Whether the line marches now (army_field.gd _march_lines).
func marching() -> bool:
	return String(me.get("state_name", "")) == "advance"


## Its plan by its order (battle_orders.json orders.<key>.advance): advance, or hold; two walls never stand all day,
## so the foe's captain goes in when both hold.
func plan() -> void:
	var mine := bool(Data.value("battle_orders", "orders.%s.advance" % String(field.orders[side]), true))
	var theirs := bool(Data.value("battle_orders", "orders.%s.advance" % String(field.orders[1 - side]), true))
	var holds: bool = not mine and (theirs or side == field.player_side())
	for r in _rows():
		if not _standing(r) or String(r.get("state_name", "")) == "fight":
			continue
		if r["role"] == "ranged":
			field._send(r, &"volley")
		elif r["role"] == "melee" and int(r.get("line_no", 1)) != 2:
			r.erase("task")
			field._send(r, &"advance")  # in its place in the line, marching with it or standing
	Mind.send(me, &"hold" if holds else &"advance")


## The King's order (or this captain's own): the side forms anew (army_field.gd reorder), then acts by it.
func order(key: String) -> void:
	field.reorder(side, key)
	Mind.send(me, &"reform")


func _say(text: String) -> void:
	field._say(me, "%s: %s" % [who(), text])


# --- Its mind's states (data/army.json minds.general) ------------------------------------------------------

func _reform(_g: Dictionary, _dt: float) -> void:
	# The side marches to its new places (army_field.gd _reform_tick); once none is still on its way, its plan.
	if _rows().any(func(r): return String(r.get("state_name", "")) == "reform"):
		return
	plan()


func _advance(_g: Dictionary, _dt: float) -> void:
	if _gap() <= Data.num(F, "field.charge.from", 2.2):
		Mind.send(me, &"charge")
	elif _met():
		Mind.send(me, &"met")


func _hold(_g: Dictionary, _dt: float) -> void:
	if _met():
		Mind.send(me, &"met")


## The whole front runs in together, each block on the foe in its lane (or, its lane clear, the nearest ahead).
func _charge_in(_g: Dictionary) -> void:
	_say("the line charges")
	for r in _rows():
		if r["role"] == "melee" and int(r.get("line_no", 1)) != 2 and String(r.get("state_name", "")) == "advance":
			var foe: Dictionary = field._lane_foe(r)
			r["task"] = foe if not foe.is_empty() else field._opposite_foe(r)


func _charge(_g: Dictionary, _dt: float) -> void:
	if _met():
		Mind.send(me, &"met")


func _melee(_g: Dictionary, dt: float) -> void:
	_think -= dt
	if _think > 0.0:
		return
	_think = Data.num(F, "field.general.think", 0.5)
	var foes := _foes()
	if foes.is_empty():
		return
	_foot(foes)
	_horse(foes)
	_archers(foes)
	_relief()
	_change_order()


## The lines have met: a regiment of this side or the foe's is at blows.
func _met() -> bool:
	return field.met()


## Open ground from its front blocks to the foe in their lanes, nearest.
func _gap() -> float:
	var g := INF
	for r in _rows():
		if r["role"] == "melee" and String(r.get("state_name", "")) == "advance" and int(r.get("line_no", 1)) != 2:
			var f: Dictionary = field._lane_foe(r)
			if not f.is_empty():
				g = minf(g, field._front_gap(r, f))
	return g


## Foot with no foe (the foe charged first, its foe broke, it rallied): on the foe head on in its lane, so the line
## meets the line where it stands (Mac 2026-11-16: the foe's charge drew every block to the first fight, the line
## folded into a column); its lane clear, onto the flank of the nearest foe fighting one of its side; else the nearest.
func _foot(foes: Array) -> void:
	if not bool(Data.value("battle_orders", "orders.%s.advance" % String(field.orders[side]), true)):
		return  # a wall holds: a block whose foe broke stands back in its place
	for r in _rows():
		if r["role"] != "melee" or int(r.get("line_no", 1)) == 2 or r.has("relieve"):
			continue
		if String(r.get("state_name", "")) != "advance" or _standing(r.get("task")):
			continue
		var lane: Dictionary = field._lane_foe(r)
		if not lane.is_empty():
			r["task"] = lane
			continue
		var at: Vector3 = (r["node"] as Node3D).global_position
		var best := {}
		var bd := INF
		for f in foes:
			if String(f.get("state_name", "")) != "fight" or f["role"] == "cavalry":
				continue
			var d := at.distance_to((f["node"] as Node3D).global_position)
			if d < bd:
				bd = d
				best = f
		if best.is_empty():
			best = field._nearest_foe(r)
		if not best.is_empty():
			r["task"] = best
			if String(best.get("state_name", "")) == "fight":
				_say("a block wheels onto their flank")


## The horse: once the lines are locked, round at the flank of the foe block at blows nearest its wing (the hammer),
## the reserve with them; a foe's horse already at our flank first.
func _horse(foes: Array) -> void:
	for r in _rows():
		if r["role"] != "cavalry" or not _standing(r):
			continue
		var st := String(r.get("state_name", ""))
		if not st in ["stand", "flank"]:
			continue
		var at: Vector3 = (r["node"] as Node3D).global_position
		var best := {}
		var bd := INF
		for f in foes:
			var busy := String(f.get("state_name", "")) == "fight"
			if not busy and f["role"] != "cavalry":
				continue
			var d := at.distance_to((f["node"] as Node3D).global_position) * (1.0 if busy else Data.num(F, "field.general.horse_vs_horse", 0.8))
			if d < bd:
				bd = d
				best = f
		if best.is_empty():
			continue
		r["target"] = best
		if st == "stand":
			field._send(r, &"flank")
			_say("the reserve rides out" if String(r.get("post", "")) == "reserve" else "the horse goes round their flank")


## Archers: on the nearest foe not at blows (never into the press).
func _archers(foes: Array) -> void:
	for r in _rows():
		if r["role"] != "ranged" or String(r.get("state_name", "")) != "volley":
			continue
		var at: Vector3 = (r["node"] as Node3D).global_position
		var best := {}
		var bd := INF
		for f in foes:
			if String(f.get("state_name", "")) == "fight":
				continue
			var d := at.distance_to((f["node"] as Node3D).global_position)
			if d < bd:
				bd = d
				best = f
		r["target"] = best


## The second line relieves a worn block (battle_orders.json relief): the nearest second-line block still standing
## marches into its foe; once it is near, the worn one falls back to where its relief stood.
func _relief() -> void:
	var k: Dictionary = Data.value("battle_orders", "relief", {})
	var rows := _rows()
	for r in rows:
		if String(r.get("state_name", "")) != "fight" or r.has("relief") or r["role"] == "cavalry":
			continue
		if float(r["living"]) > float(k.get("at", 0.65)) * float(r["figures"]):
			continue
		var at: Vector3 = (r["node"] as Node3D).global_position
		var best := {}
		var bd := INF
		for x in rows:
			if int(x.get("line_no", 0)) != 2 or String(x.get("state_name", "")) != "stand" or x.has("relieve") or int(x.get("living", 0)) <= 0:
				continue
			var d := at.distance_squared_to((x["node"] as Node3D).global_position)
			if d < bd:
				bd = d
				best = x
		if best.is_empty():
			continue
		r["relief"] = best
		best["relieve"] = r
		best["relief_from"] = (best["node"] as Node3D).global_position
		best["task"] = r.get("foe") if _standing(r.get("foe")) else field._nearest_foe(best)
		field._send(best, &"advance")
		_say("the second line goes in")
	for r in rows:
		var worn: Variant = r.get("relieve")
		if not worn is Dictionary or String((worn as Dictionary).get("state_name", "")) != "fight":
			continue
		var apart := ((r["node"] as Node3D).global_position - ((worn as Dictionary)["node"] as Node3D).global_position).length()
		if apart <= float(k.get("near", 1.0)) + float(r["d"]):
			(worn as Dictionary)["back_to"] = r["relief_from"]
			field._send(worn, &"relieve")
			r.erase("relieve")


## The foe's captain losing the day (his side's strength and nerve under field.general.losing of the King's) changes
## his order once: shields locked where they stand.
func _change_order() -> void:
	if _changed or side == field.player_side():
		return
	var worth := [0.0, 0.0]
	for i in 2:
		for r in (field.sides[i]).rows():
			if _standing(r):
				worth[i] += float(r["living"]) * Morale.of(r)
	if worth[side] >= Data.num(F, "field.general.losing", 0.65) * worth[1 - side]:
		return
	var key := String(Data.value(F, "field.general.fallback", "shield_wall"))
	if String(field.orders[side]) == key:
		return
	_changed = true
	_say("orders %s" % BattleOrders.title(key).to_lower())
	order(key)
