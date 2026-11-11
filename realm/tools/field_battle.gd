extends Node3D
## Two hosts meet in the field (Mac: "battles need polish"; Total War's field battle, Warcraft III's worn colour;
## docs/research/army-and-town-rules.md section 1). A test aid, like the army spike it stands on:
## --army-battle=<men per side>[:foe|crown], the side Freeciv beat after the colon (foe by default).
##
## Both hosts are the army spike's regiments (tools/army_spike.gd: one VAT draw and one banner each). The crown's
## host musters by its seat and marches in by the road; the foe comes in over open land and forms facing it,
## field.gap away. When both lines stand, each regiment's own mind (a LimboHSM, as battle_ai.gd's men have) takes
## it through the battle: archers loose volleys that arc onto the enemy's ranks and fell men where they land; the
## foot advance and stop at sword's length, the two fronts fighting along their length, front ranks cutting,
## reeling and falling, the fallen left where they fell; cavalry swings round the enemy's end and charges into his
## flank; a beaten regiment's banner wavers as its pips fall, then it breaks and runs, its men scattering; the
## victors hold the field. Who wins is the realm's (Freeciv decides, the bridge tells): the beaten side bleeds
## faster and breaks, the victors never do. Numbers in data/battle.json field (docs/TUNING.md).
## Prints "BATTLE …" lines (a test aid). Off in play: nothing else reads it.

const Army := preload("res://tools/army_spike.gd")
const Data := preload("res://scripts/data.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const F := "battle"  # data/battle.json, its field block

var main: Node
var men := 0
var loser := 1  # the side Freeciv beat: 0 the crown, 1 the foe
var sides: Array = []  # the two army spikes
var clock := -1.0  # seconds since the battle began; below 0 while the hosts deploy
var _arrows: MultiMeshInstance3D
var _flights: Array = []  # [from, to, start, flight, target regiment, fells]
var _rng := RandomNumberGenerator.new()
var _dist := 12.0
var _focus := Vector3.ZERO
var _report := 0.0
var _over := false
var _formed := 0.0  # seconds both lines have stood formed


func _init(owner: Node, arg: String) -> void:
	main = owner
	name = "FieldBattle"
	var parts := arg.split(":")
	men = int(parts[0]) if parts[0].is_valid_int() else 3000
	loser = 0 if parts.size() > 1 and parts[1] == "crown" else 1


func _ready() -> void:
	_rng.seed = 1415
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			_dist = float(a.substr(7))
	while main.terrain.width == 0 or not main.terrain.built or (main.bridge.world.get("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5).timeout
	var crown: Army = Army.new(main, men, {"side": 0})
	add_child(crown)
	if not crown.mustered:
		await crown.raised
	if crown.rows().is_empty():
		push_error("BATTLE the crown's host could not be raised")
		return
	var face := crown.facing()
	var fwd := Vector3(sin(face), 0, cos(face))
	var house := _foe_house()
	var foe: Army = Army.new(main, men, {"side": 1, "field": crown.field() + fwd * Data.num(F, "field.gap", 9.0), "face": face + PI,
		"colour": Heraldry.colour(house, Color(0.72, 0.12, 0.12)) if not house.is_empty() else Color(0.72, 0.12, 0.12), "house": house})
	add_child(foe)
	if not foe.mustered:
		await foe.raised
	sides = [crown, foe]
	_arrows = _arrow_pool()
	_focus = (crown.field() + foe.field()) * 0.5
	print("BATTLE raised %d a side, %s against %s, the %s beaten; lines %.1f apart" % [men, "the crown", String(house.get("name", "a rebel host")),
		"crown" if loser == 0 else "foe", crown.field().distance_to(foe.field())])


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
	for k in 2:
		for r in (sides[k] as Army).rows():
			r["state"] = "battle"  # the spike leaves it be from here
			r["side"] = k
			r["army"] = sides[k]
			var alive := PackedByteArray()
			alive.resize(int(r["men"]))
			alive.fill(1)
			r["alive"] = alive
			r["living"] = int(r["men"])
			r["dead_at"] = {}
			r["bleed"] = 0.0
			r["volley_t"] = _rng.randf_range(0.5, 2.0)
			r["swing"] = {}  # front man -> when he next cuts
			r["back"] = {}  # man -> when his one-shot ends and he takes his stance again
			r["foe"] = null
			r["moved"] = false
			_mind(r)
	print("BATTLE begins")


## A regiment's mind: stand, then by its role loose volleys, advance or ride round the flank; fight; break and run,
## or hold the field. No way back from running.
func _mind(r: Dictionary) -> void:
	var hsm := LimboHSM.new()
	var stand := LimboState.new()
	var volley := LimboState.new()
	var advance := LimboState.new()
	var flank := LimboState.new()
	var charge := LimboState.new()
	var fight := LimboState.new()
	var rout := LimboState.new()
	var hold := LimboState.new()
	for s in [stand, volley, advance, flank, charge, fight, rout, hold]:
		hsm.add_child(s)
	var army: Army = r["army"]
	var enter := func(state: LimboState, label: String, then: Callable) -> void:
		state.call_on_enter(func():
			r["state_name"] = label
			then.call())
	enter.call(stand, "stand", func(): _play(r, "ready"))
	enter.call(volley, "volley", func(): _play(r, "ready"))
	volley.call_on_update(func(dt: float): _volley(r, dt))
	enter.call(advance, "advance", func(): _play(r, "walk"))
	advance.call_on_update(func(dt: float): _advance(r, dt))
	enter.call(flank, "flank", func(): _play(r, "walk"))
	flank.call_on_update(func(dt: float): _flank(r, dt))
	enter.call(charge, "charge", func(): _play(r, "run"))
	charge.call_on_update(func(dt: float): _charge(r, dt))
	enter.call(fight, "fight", func(): _play(r, "ready"))
	fight.call_on_update(func(dt: float): _fight(r, dt))
	enter.call(rout, "rout", func(): _break(r))
	rout.call_on_update(func(dt: float): _run(r, dt))
	enter.call(hold, "hold", func(): _hold(r))
	hold.call_on_update(func(dt: float): _settle(r, dt))
	hsm.add_transition(stand, volley, &"volley")
	hsm.add_transition(stand, advance, &"advance")
	hsm.add_transition(stand, flank, &"flank")
	hsm.add_transition(advance, fight, &"engage")
	hsm.add_transition(volley, fight, &"engage")
	hsm.add_transition(flank, charge, &"charge")
	hsm.add_transition(charge, fight, &"engage")
	hsm.add_transition(fight, advance, &"advance")  # its foe broke: on to the next
	hsm.add_transition(charge, flank, &"flank")
	rout.set_guard(func() -> bool: return int(r["side"]) == loser)  # the victors never break
	hsm.add_transition(hsm.ANYSTATE, rout, &"break")
	hold.set_guard(func() -> bool: return int(r["side"]) != loser)
	hsm.add_transition(hsm.ANYSTATE, hold, &"won")
	hsm.initial_state = stand
	(r["node"] as Node).add_child(hsm)
	hsm.initialize(r["node"])
	hsm.set_active(true)
	r["hsm"] = hsm
	r["state_name"] = "stand"


func _send(r: Dictionary, ev: StringName) -> void:
	(r["hsm"] as LimboHSM).dispatch(ev)


# --- Each frame -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sides.size() < 2:
		return
	if clock < 0.0:
		# Both lines formed: a breath, then the battle.
		var formed := (sides as Array).all(func(a): return (a as Army).rows().all(func(r): return r["state"] == "rest"))
		if formed:
			_formed += delta
			if _formed >= Data.num(F, "field.start", 2.0):
				_begin()
				for k in 2:
					for r in (sides[k] as Army).rows():
						_send(r, &"volley" if r["role"] == "ranged" else (&"flank" if r["role"] == "cavalry" else &"advance"))
		_frame(delta)
		return
	clock += delta
	_fly(delta)
	for k in 2:
		for r in (sides[k] as Army).rows():
			_backs(r)
			if r["moved"]:
				_keep_dead(r)
				r["moved"] = false
	_morale()
	_frame(delta)
	_report -= delta
	if _report <= 0.0:
		_report = 2.0
		var s := PackedStringArray()
		for k in 2:
			var states := {}
			var left := 0
			for r in (sides[k] as Army).rows():
				states[r["state_name"]] = int(states.get(r["state_name"], 0)) + 1
				left += int(r["living"])
			s.append("%s %d men %s" % ["crown" if k == 0 else "foe", left, str(states)])
		print("BATTLE t=%.0f %s; arrows in flight %d; fps=%d" % [clock, " | ".join(s), _flights.size(), Engine.get_frames_per_second()])


## The beaten side's banners waver as their strength falls, and each breaks below field.rout, or all of them after
## field.longest; when none of the beaten stands, the victors hold the field.
func _morale() -> void:
	var waver := Data.num(F, "field.waver", 0.7)
	var rout := Data.num(F, "field.rout", 0.45)
	var standing := 0
	for r in (sides[loser] as Army).rows():
		if r["state_name"] == "rout":
			continue
		var st: float = r["strength"]
		(r["army"] as Army).waver(r, (waver - st) / maxf(waver - rout, 0.01))
		if st < rout or clock > Data.num(F, "field.longest", 45.0):
			_send(r, &"break")
		else:
			standing += 1
	if standing == 0 and not _over:
		_over = true
		print("BATTLE the %s break; the %s hold the field at t=%.0f" % ["crown's men" if loser == 0 else "foe", "foe" if loser == 0 else "crown's men", clock])
		for r in (sides[1 - loser] as Army).rows():
			_send(r, &"won")


## The lens on the thick of it: the middle of every regiment still in the field, low and oblique, off the lines' quarter.
func _frame(delta: float) -> void:
	if main.rig == null:
		return
	var sum := Vector3.ZERO
	var n := 0
	for a in sides:
		for r in (a as Army).rows():
			if r.get("state_name", "") != "rout":
				sum += (r["node"] as Node3D).global_position
				n += 1
	if n > 0:
		_focus = _focus.lerp(sum / n, minf(1.0, delta * Data.num(F, "field.camera.follow", 1.2)))
	var crown: Army = sides[0]
	main.rig.snap(_focus, _dist, crown.facing() + Data.num(F, "field.camera.quarter", 0.9))
	main.rig.tilt = Data.num("army", "camera.tilt", -8.0)
	main.rig.goal_tilt = main.rig.tilt


# --- Archers ----------------------------------------------------------------------------------------------

## Loose a volley every field.volley.every seconds at the nearest enemy regiment, while the lines are apart.
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
		var lands := 1 if i < fells else 0
		_flights.append([from, to, clock + _rng.randf_range(0.0, 0.5), flight * _rng.randf_range(0.9, 1.1), foe, lands])


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


## Every arrow in the air along its arc, pointing the way it flies; one that lands on its mark fells a man there.
func _fly(_delta: float) -> void:
	var mm := _arrows.multimesh
	var arc := Data.num(F, "field.volley.arc", 0.45)
	var shown: Array = []
	for i in range(_flights.size() - 1, -1, -1):
		var f: Array = _flights[i]
		var t := (clock - float(f[2])) / float(f[3])
		if t < 0.0:
			continue
		if t >= 1.0:
			if int(f[5]) > 0 and (f[4] as Dictionary).get("state_name", "") != "rout":
				_fell(f[4], 1, false)
			_flights.remove_at(i)
			continue
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var top := a.distance_to(b) * arc
		var p := a.lerp(b, t) + Vector3(0, top * 4.0 * t * (1.0 - t), 0)
		var q := a.lerp(b, minf(t + 0.02, 1.0)) + Vector3(0, top * 4.0 * minf(t + 0.02, 1.0) * (1.0 - minf(t + 0.02, 1.0)), 0)
		shown.append(Transform3D(Basis.looking_at(q - p if (q - p).length() > 0.0001 else Vector3.FORWARD, Vector3.UP), p))
	mm.instance_count = shown.size()
	for i in shown.size():
		mm.set_instance_transform(i, shown[i])


# --- Foot -------------------------------------------------------------------------------------------------

## Forward at field.advance until its front is at sword's length from the nearest enemy's front; then both fight.
func _advance(r: Dictionary, dt: float) -> void:
	var foe := _nearest_foe(r)
	if foe.is_empty():
		return
	var to: Vector3 = (foe["node"] as Node3D).global_position
	_face_toward(r, to, dt)
	var gap := _front_gap(r, foe)
	var contact := Data.num(F, "field.contact", 0.12)
	if gap <= contact:
		r["foe"] = foe
		_send(r, &"engage")
		if foe.get("state_name", "") in ["stand", "volley", "advance"]:
			foe["foe"] = r
			_send(foe, &"engage")
		return
	var node: Node3D = r["node"]
	var fwd := node.global_transform.basis.z.normalized()  # a regiment faces its +Z
	(r["army"] as Army).place(r, node.global_position + fwd * minf(Data.num(F, "field.advance", 0.12) * dt, gap - contact), float(r["yaw"]))
	r["moved"] = true


## At blows: the front ranks cut and reel, men fall from the front, the rest stand ready behind; the front
## surges a little back and forth. It bleeds by the realm's outcome (field.fight.loss), harder when flanked.
func _fight(r: Dictionary, dt: float) -> void:
	var foe: Variant = r["foe"]
	if foe == null or (foe as Dictionary).get("state_name", "") == "rout" or int((foe as Dictionary)["living"]) == 0:
		var next := _nearest_foe(r)
		if next.is_empty():
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
	for s in front:
		if not swing.has(s):
			swing[s] = clock + _rng.randf_range(0.0, float(range_s[1]))
		if clock >= float(swing[s]):
			swing[s] = clock + _rng.randf_range(float(range_s[0]), float(range_s[1]))
			vat.update_instance_track(s, army.track(r, "hit" if _rng.randf() < hit_odds else "attack"))
			back[s] = clock + 0.9
	# The front surges: each front man a little forward and back on his own beat.
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


# --- Horse ------------------------------------------------------------------------------------------------

## Round the end of the enemy's line nearest its own wing, wide of it (field.cavalry.wide), then in on his flank.
func _flank(r: Dictionary, dt: float) -> void:
	var foe_army: Army = sides[1 - int(r["side"])]
	var rows := foe_army.rows().filter(func(x): return x.get("state_name", "") != "rout" and int(x.get("living", 1)) > 0)
	if rows.is_empty():
		return
	var node: Node3D = r["node"]
	var face := foe_army.facing()
	var right := Vector3(cos(face), 0, -sin(face))
	var fwd := Vector3(sin(face), 0, cos(face))
	# The enemy's end on this wing's side, and a point wide of it and a little behind his front.
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
	if _move_to(r, goal, Data.num(F, "field.cavalry.ride", 0.3), dt):
		_send(r, &"charge")


## In on the flank at the charge, into the side of the regiment at the enemy's end; it fights there, and the
## regiment it hits is flanked (bleeds harder).
func _charge(r: Dictionary, dt: float) -> void:
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
	_move_to(r, tn.global_position, Data.num(F, "field.cavalry.charge", 0.55), dt)


# --- Breaking and holding ---------------------------------------------------------------------------------

## It breaks: turns its back on the enemy, runs; its banner wavers its last.
func _break(r: Dictionary) -> void:
	var army: Army = r["army"]
	army.waver(r, 1.0)
	r["yaw"] = float(r["yaw"]) + PI
	army.place(r, (r["node"] as Node3D).global_position, float(r["yaw"]))
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
	print("BATTLE t=%.0f a %s regiment breaks at %d%%" % [clock, "crown" if int(r["side"]) == 0 else "foe", int(float(r["strength"]) * 100.0)])


## Running: away from the field at field.run, each man drifting from his place (field.scatter), gone after field.fade.
func _run(r: Dictionary, dt: float) -> void:
	var node: Node3D = r["node"]
	var fwd := node.global_transform.basis.z.normalized()
	(r["army"] as Army).place(r, node.global_position + fwd * Data.num(F, "field.run", 0.42) * dt, float(r["yaw"]))
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


func _settle(_r: Dictionary, _dt: float) -> void:
	pass


# --- Men falling and the fallen ---------------------------------------------------------------------------

## n men of a regiment fall: from its front at blows, anywhere under arrows. Each plays his death and stays where
## he fell; the regiment's strength (its banner's pips) is its living over its muster.
func _fell(r: Dictionary, n: int, front: bool) -> void:
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
	army.set_strength(int(r["id"]), float(r["living"]) / maxf(float(r["men"]), 1.0))


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


## Turns a regiment toward a point, a little each frame.
func _face_toward(r: Dictionary, to: Vector3, dt: float) -> void:
	var at: Vector3 = (r["node"] as Node3D).global_position
	var want := atan2(to.x - at.x, to.z - at.z)
	var yaw := lerp_angle(float(r["yaw"]), want, minf(1.0, dt * 1.5))
	if absf(angle_difference(yaw, float(r["yaw"]))) > 0.0005:
		(r["army"] as Army).place(r, at, yaw)
		r["moved"] = true


## Moves a regiment toward a point at a pace, turning as it goes; true when it is there.
func _move_to(r: Dictionary, goal: Vector3, pace: float, dt: float) -> bool:
	var node: Node3D = r["node"]
	var to := goal - node.global_position
	to.y = 0.0
	var step := pace * dt
	if to.length() <= step:
		(r["army"] as Army).place(r, goal, float(r["yaw"]))
		r["moved"] = true
		return true
	var yaw := lerp_angle(float(r["yaw"]), atan2(to.x, to.z), minf(1.0, dt * 2.0))
	(r["army"] as Army).place(r, node.global_position + to.normalized() * step, yaw)
	r["moved"] = true
	return false
