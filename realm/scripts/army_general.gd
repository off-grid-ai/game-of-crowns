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
	_write_plan()
	Mind.send(me, &"hold" if holds else &"advance")


## The King's order (or this captain's own): the side forms anew (army_field.gd reorder), then acts by it.
func order(key: String) -> void:
	field.reorder(side, key)
	Mind.send(me, &"reform")


# --- The battle plan ---------------------------------------------------------------------------------------

## The captain's plan, written before the lines move and again when a new order has formed them (Mac 2026-11-16: "you
## need to create a routine or battle plan for both the armies that they need to follow properly", "this on the fly
## stuff is really weird"; Total War's battle AI plans its line, its flanks and its reserve before it advances). Every
## regiment gets its list of marks, in the order it takes them (r.plan):
##   - foot: the foe's block across from its own place in the line (first to first, last to last along the front),
##     then that block's neighbours, nearest first: its own foe broken, it wheels onto the next one's flank;
##   - horse: the foe's block at the end of the line on its own wing, then inward (it rolls the line up from its end);
##   - archers: the foe across from them, then outward.
## Regiments only work down their lists (_mark); nothing is re-picked while a mark stands.
func _write_plan() -> void:
	var face: float = (field.sides[side]).facing()
	var right := Vector3(cos(face), 0, -sin(face))
	var lat := func(x: Dictionary) -> float: return ((x["node"] as Node3D).global_position).dot(right)
	var foes := _foes()
	var front: Array = foes.filter(func(f): return f["role"] == "melee")
	if front.is_empty():
		front = foes
	if front.is_empty():
		return
	front.sort_custom(func(a, b): return float(lat.call(a)) < float(lat.call(b)))
	var mine: Array = _rows().filter(func(r): return _standing(r) and r["role"] == "melee" and int(r.get("line_no", 1)) != 2)
	mine.sort_custom(func(a, b): return float(lat.call(a)) < float(lat.call(b)))
	for i in mine.size():
		var j := int(round(float(i) * float(front.size() - 1) / float(mine.size() - 1))) if mine.size() > 1 else front.size() / 2
		(mine[i] as Dictionary)["plan"] = _by_nearness(front, float(lat.call(front[j])), lat)
	var rest: Array = foes.filter(func(f): return not front.has(f) and f["role"] != "cavalry")  # their archers, last
	for r in _rows():
		if not _standing(r) or mine.has(r):
			continue
		(r as Dictionary)["plan"] = _by_nearness(front, float(lat.call(r)), lat) + _by_nearness(rest, float(lat.call(r)), lat)


## `list` in order of nearness along the front to the place `at`.
func _by_nearness(list: Array, at: float, lat: Callable) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a, b): return absf(float(lat.call(a)) - at) < absf(float(lat.call(b)) - at))
	return out


## The next mark on r's list still standing (clear of the press, for archers); {} when its list is spent.
func _mark(r: Dictionary, clear := false) -> Dictionary:
	for f in r.get("plan", []):
		if _standing(f) and not (clear and String((f as Dictionary).get("state_name", "")) == "fight"):
			return f
	return {}


## A horse block's ride at `mark`, planned whole before it sets off: the points of its way to its run-up, from where
## it charges straight in (army_field.gd _flank follows them, _charge rides the last straight, _ride_out_in pulls it
## back to the run-up to charge again). The flank of its mark on the horse's own wing if no other block stands there,
## else his rear; and round the outside of both lines (field.cavalry.wide clear of the last block) when the straight
## way to the run-up is shut, never through its own foot.
func _plan_ride(r: Dictionary, mark: Dictionary) -> Array:
	var mine: Node = field.sides[side]
	var face: float = mine.facing()
	var right := Vector3(cos(face), 0, -sin(face))
	var fwd := Vector3(sin(face), 0, cos(face))
	var mid: Vector3 = mine.field()
	var at: Vector3 = (r["node"] as Node3D).global_position
	var to := _will_stand(mark)
	var sgn := signf((at - mid).dot(right))
	if sgn == 0.0:
		sgn = 1.0
	var run := float(r["d"]) * 0.5 + Data.num(F, "field.cavalry.run", 1.2)
	var runup: Vector3 = to + right * sgn * (float(mark["w"]) * 0.5 + run)  # out on his flank, on its own wing
	if field._block_near(r, mark, to + right * sgn * float(mark["w"]) * 0.5, float(r["w"]) * 0.5):
		runup = to + fwd * (float(mark["d"]) * 0.5 + run)  # that flank is taken: behind him
	var way: Array = []
	# Already by its run-up (planned again after a charge there): straight in from it, never out round the wing and
	# back (a whole loop on the spot, 8 rad by field_clash_probe).
	var there := Vector2(runup.x - at.x, runup.z - at.z).length() <= Data.num(F, "field.cavalry.near", 0.5) * 2.0
	if not there and not field._way_clear(r, at, runup, mark):
		# Round the outside of both lines: out past the last block on its wing, level with where it stands, then up
		# that side level with its run-up.
		var far := 0.0
		for i in 2:
			for x in (field.sides[i]).rows():
				if _standing(x) and not is_same(x, r):
					far = maxf(far, ((x["node"] as Node3D).global_position - mid).dot(right * sgn) + float(x["w"]) * 0.5)
		var out := far + float(r["w"]) * 0.5 + Data.num(F, "field.cavalry.wide", 1.0)
		var level: Vector3 = mid + right * sgn * out + fwd * (runup - mid).dot(fwd)  # out on that side, level with its run-up
		var first: Vector3 = mid + right * sgn * out + fwd * (at - mid).dot(fwd)  # out on that side, level with where it stands
		# The first only when it is on its way and ahead of where it heads (never a point behind it: it doubled back in
		# a loop to one, 10 rad by field_clash_probe) and the straight way to the second is shut.
		var heads: Vector3 = (r["node"] as Node3D).global_basis.z
		if (first - at).dot(level - at) > 0.0 and (first - at).dot(heads) > 0.0 and not field._way_clear(r, at, level, mark):
			way.append(first)
		way.append(level)
	way.append(runup)
	return way


## Where a mark will stand once the lines are locked: where it stands, or, still closing on the block it was sent at,
## where the two will meet (its own side of their middle). A ride is planned to there, so it needn't be planned again
## as the mark marches in.
func _will_stand(mark: Dictionary) -> Vector3:
	var at: Vector3 = (mark["node"] as Node3D).global_position
	if String(mark.get("state_name", "")) != "advance":
		return at
	# Whom it will meet: the block it was sent at, or (its own captain's word not yet given) the block of this side
	# whose plan sends it at him first.
	var foe: Variant = mark.get("task")
	if not _standing(foe):
		foe = null
		for x in _rows():
			if x["role"] == "melee" and _standing(x) and is_same(_mark(x), mark):
				foe = x
				break
	if not _standing(foe):
		return at
	var theirs: Vector3 = ((foe as Dictionary)["node"] as Node3D).global_position
	var apart := Vector3(at.x - theirs.x, 0.0, at.z - theirs.z)
	if apart.length() < 0.01:
		return at
	var meet := (at + theirs) * 0.5 + apart.normalized() * (float(mark["d"]) * 0.5 + Data.num(F, "field.contact", 0.12) * 0.5)
	return Vector3(meet.x, at.y, meet.z)


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
	_horse(_foes())  # the horse sets off round the wing as the foot go in, to strike as the lines lock (Mac 2026-11-16: "why dont the horses attack", "they just go and wait there": sent only once the lines had locked, it was 15 s riding round)
	for r in _rows():
		if r["role"] == "melee" and int(r.get("line_no", 1)) != 2 and String(r.get("state_name", "")) == "advance":
			r["task"] = _mark(r)


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
	_answer_horse(foes)
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


## Foot with no foe (the foe charged first, its foe broke, it rallied): the next on its list in the plan (its own
## foe across the line first, so the line meets the line where it stands; then his neighbours, nearest first, onto
## their flank).
func _foot(_foes: Array) -> void:
	if not bool(Data.value("battle_orders", "orders.%s.advance" % String(field.orders[side]), true)):
		return  # a wall holds: a block whose foe broke stands back in its place
	for r in _rows():
		if r["role"] != "melee" or int(r.get("line_no", 1)) == 2 or r.has("relieve"):
			continue
		if String(r.get("state_name", "")) == "stand" and String(r.get("post", "")) != "reserve":
			field._send(r, &"advance")  # formed again after a rally: back into the fight (it stood out the battle, 12 s idle by field_clash_probe)
		if String(r.get("state_name", "")) != "advance" or _standing(r.get("task")):
			continue
		var next := _mark(r)
		if next.is_empty():
			continue
		r["task"] = next
		if String(next.get("state_name", "")) == "fight":
			_say("a block wheels onto their flank")


## The horse: once the lines are locked, at the next mark on its list in the plan (the foe's block at the end of the
## line on its own wing first, then inward: it rolls up the line), by a ride planned whole before it sets off
## (_plan_ride). Its mark is kept while it stands; a ride that proved shut puts that mark last and plans the next.
func _horse(_foes: Array) -> void:
	for r in _rows():
		if r["role"] != "cavalry" or not _standing(r):
			continue
		var st := String(r.get("state_name", ""))
		if not st in ["stand", "flank"]:
			continue
		if r.get("ride_failed", false):
			r.erase("ride_failed")
			var list: Array = r.get("plan", [])
			var was: Variant = r.get("target")
			if was is Dictionary and list.has(was):
				list.erase(was)
				list.append(was)
			r.erase("target")
		if _standing(r.get("target")) and r.has("ride"):
			# Its mark has moved since its ride was planned (field.cavalry.moved): planned anew to where he stands now.
			var m: Dictionary = r["target"]
			if st == "flank" and (_will_stand(m) - (r.get("ride_mark_at", _will_stand(m)) as Vector3)).length() > Data.num(F, "field.cavalry.moved", 1.0):
				_send_horse(r, m)
			elif st == "stand":
				_send_horse(r, m)  # formed again with its mark still standing: off at him by a ride planned from where it stands now (it stood 10 s, field_clash_probe)
			continue
		var next := _mark(r)
		if next.is_empty():
			continue
		_send_horse(r, next)
		_say("the reserve rides out" if String(r.get("post", "")) == "reserve" else "the horse goes round their flank")


## A horse block sent at `mark` by a ride planned now.
func _send_horse(r: Dictionary, mark: Dictionary) -> void:
	r["target"] = mark
	r["ride"] = _plan_ride(r, mark)
	r["ride_i"] = 0
	r["ride_mark_at"] = _will_stand(mark)
	if OS.get_cmdline_user_args().has("--where"):  # test aid: the planned ride, to read against the block's track
		print("PLAN side%d horse from %s at mark %s by %s" % [side, str((r["node"] as Node3D).global_position), str((mark["node"] as Node3D).global_position), str(r["ride"])])
	if String(r.get("state_name", "")) == "stand":
		field._send(r, &"flank")


## A foe horse in among one of its blocks is answered (Total War: a unit charged turns on the horse, and its general
## sends spears or his own horse at it; Mac 2026-11-16: "obviously they should try to retaliate"): the block struck
## fights it man to man (army_field.gd _press takes every foe at blows with it); its own horse, free or riding round,
## goes at it; and the nearest foot block standing free (the second line, a block whose foe broke) goes in at it.
func _answer_horse(foes: Array) -> void:
	var rows := _rows()
	for h in foes:
		if h["role"] != "cavalry" or String(h.get("state_name", "")) not in ["charge", "fight"]:
			continue
		var hit: Variant = h.get("foe") if String(h.get("state_name", "")) == "fight" else h.get("target")
		if not hit is Dictionary or int((hit as Dictionary).get("side", -1)) != side:
			continue
		var at: Vector3 = (h["node"] as Node3D).global_position
		var best := {}
		var bd := INF
		for r in rows:
			if not _standing(r) or r.has("relieve") or r.has("relief") or is_same(r, hit):
				continue
			var st := String(r.get("state_name", ""))
			var free: bool = (r["role"] == "cavalry" and st in ["stand", "flank"] and not is_same(r.get("target"), h)) \
				or (r["role"] == "melee" and (st == "stand" or (st == "advance" and not _standing(r.get("task")))))
			if not free:
				continue
			var d := at.distance_to((r["node"] as Node3D).global_position)
			if d < bd and d <= Data.num(F, "field.general.answer", 4.0):
				bd = d
				best = r
		if best.is_empty():
			continue
		if best["role"] == "cavalry":
			_send_horse(best, h)
		else:
			best["task"] = h
			field._send(best, &"advance")
		_say("%s turn on their horse" % ("our horse" if best["role"] == "cavalry" else "a block"))


## Archers: on the first mark on their list in the plan that stands clear of the press (never into it), kept while
## it does.
func _archers(_foes: Array) -> void:
	for r in _rows():
		if r["role"] != "ranged" or String(r.get("state_name", "")) != "volley":
			continue
		var has: Variant = r.get("target")
		if _standing(has) and String((has as Dictionary).get("state_name", "")) != "fight":
			continue
		r["target"] = _mark(r, true)


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
