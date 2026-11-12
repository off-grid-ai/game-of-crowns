extends Node3D
## The storm as a mass (North Star docs/art/target/04-siege.jpg and 03-army.jpg; Total War's storm through the
## breach, Warcraft III's density): hundreds in their houses' colours, not the dozen men siege_ai.gd fights
## man to man. Two hosts of the army's regiments (tools/army_spike.gd, army-ui's: one VAT draw and one banner
## a regiment, the painted finish and the knight's clips; raised as battle sides, so they frame nothing and
## stand where they're put): the besiegers in line on the camp side, the holder's drawn up inside the wall.
## Driven by siege_ai.gd's breach (its gap and phase, no copy of its own):
##  - before the gap opens the besiegers stand ready and loose fire arrows over the wall: they arc into the
##    town and now and then a roof catches (fire.gd kindle: it burns and stays charred);
##  - once the gap is open the besiegers' regiments march up in waves and queue into it, the front one at
##    blows in the gap, the holder's regiments meeting them on the town side, their banners wavering as the
##    fight goes on (siege_ai's men duel in the gap itself, close up);
##  - when the holder's block breaks, its regiments waver to breaking and run into the town, and the
##    besiegers pour in through the gap and spread out among the houses.
## Never moves the camera. Knobs: data/siege.json storm_host. Switch: --storm-host=on|off, on with --wall-demo.

const Army := preload("res://tools/army_spike.gd")
const Fire := preload("res://scripts/fire.gd")
const Data := preload("res://scripts/data.gd")

var ai: Node  # siege_ai.gd: its _held_at (the gap, its phase), its town
var main: Node
var sides: Array = []  # [besiegers, holders] (army_spike battle sides)
var _ready_sides := 0
var _queue: Array = []  # besieger regiments sent, in order
var _clock := 0.0
var _wave_t := 0.0
var _arrow_t := 0.0
var _arrows: Array = []  # [{node, from, to, t, dur, top}]
var _rng := RandomNumberGenerator.new()
var _said := ""  # the phase last printed (--probe: a headless state proof, silent in play)
var _probe_t := 0.0


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--storm-host=off"):
		return false
	if args.has("--storm-host=on") or args.has("--wall-demo"):
		return true
	return bool(Data.value("siege", "storm_host.on", false))


static func k(path: String, fallback: float) -> float:
	return Data.num("siege", "storm_host." + path, fallback)


## Raised beside a siege: `camp` where the besiegers stand (world), `wall` a point on the wall's foot facing
## them, `town` the town's heart; colours and houses of each side.
func begin(siege_ai: Node, camp: Vector3, wall: Vector3, town: Vector3, foe_col: Color, held_col: Color, foe: Dictionary, held: Dictionary) -> void:
	ai = siege_ai
	main = ai.scenes.get_parent()
	name = "SiegeStorm"
	_rng.seed = hash(town)
	ai.root.add_child(self)
	if OS.get_cmdline_user_args().has("--probe"):
		print("STORM begun: besiegers by %s, the wall at %s, the town at %s" % [str(camp), str(wall), str(town)])
	var out := Vector3(camp.x - town.x, 0, camp.z - town.z).normalized()
	var men: Array = Data.value("siege", "storm_host.men", [800, 300])
	var face_in := atan2(-out.x, -out.z)  # the soldier faces +Z: toward the town
	var face_out := atan2(out.x, out.z)
	var inside: Vector3 = wall - out * k("holders_back", 0.9)
	for i in 2:
		var side := {"side": i, "field": camp if i == 0 else inside, "face": face_in if i == 0 else face_out,
			"colour": foe_col if i == 0 else held_col, "house": foe if i == 0 else held, "shape": "line", "quiet": true}
		var a := Army.new(main, int(men[i]), side)
		add_child(a)
		a.raised.connect(func():
			for r in a.rows():
				r["state"] = "storm"  # the spike leaves it be from here: this drives it
				r["goal"] = (r["node"] as Node3D).global_position
				r["pace"] = 0.0
				a.play(r, "ready" if i == 0 else "rest")
			_ready_sides += 1
			if OS.get_cmdline_user_args().has("--probe"):
				print("STORM side %d raised: %d regiments" % [i, a.rows().size()]))
		sides.append(a)


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
	print("STORM t=%.0f phase=%s besiegers_at_gap=%d through=%d gap_defenders=%d regiments_sent=%d" % [_clock, phase, at_gap, through, defenders, _queue.size()])


func _gap() -> Dictionary:
	for key in ai._held_at:
		return ai._held_at[key]
	return {}


func _process(delta: float) -> void:
	if _ready_sides < 2:
		return
	_clock += delta
	var st := _gap()
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
	for a in sides:
		for r in (a as Army).rows():
			_move(a, r, delta)
	_fly(delta)


## A regiment walks (or runs) toward its goal, turned to it; there, it turns to face `face` and takes its stance.
func _move(a: Army, r: Dictionary, dt: float) -> void:
	if String(r.get("state", "")) != "storm":
		return
	var n: Node3D = r["node"]
	var at := n.global_position
	var to: Vector3 = r["goal"] - at
	to.y = 0.0
	var step := float(r["pace"]) * dt
	if to.length() <= maxf(step, 0.01):
		if float(r["pace"]) > 0.0:
			r["pace"] = 0.0
			a.place(r, r["goal"], float(r.get("face", r["yaw"])))
			a.play(r, String(r.get("stance", "ready")))
		return
	a.place(r, at + to.normalized() * step, lerp_angle(float(r["yaw"]), atan2(to.x, to.z), minf(1.0, dt * 4.0)))


func _go(a: Army, r: Dictionary, goal: Vector3, run: bool, stance: String, face: float) -> void:
	r["goal"] = goal
	r["pace"] = k("run" if run else "walk", 0.5 if run else 0.22)
	r["stance"] = stance
	r["face"] = face
	a.play(r, "run" if run else "walk")


## The gap open: a besieger regiment sent every wave_s, each queueing into the gap behind the one before; the
## front one at blows in the gap.
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
			_go(sides[0], r, goal, true, "attack" if i == 0 else "ready", face)


## The holder's regiments meet them on the town side of the gap, their banners wavering more as the fight
## goes on and the block thins (siege_ai's defenders standing).
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
			_go(sides[1], r, goal, false, "attack" if i < 3 else "block", face)
		(sides[1] as Army).waver(r, 1.0 - standing / full)


## The gap taken: the holder's regiments break and run into the town, the besiegers pour through and spread
## out among the houses.
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
			_go(sides[1], r, away, true, "rest", 0.0)
	var i := 0
	for r in (sides[0] as Army).rows():
		if not r.get("in", false):
			r["in"] = true
			var into := gap + inward * (0.6 + 0.4 * (i % 4)) + Vector3(_rng.randf_range(-1.0, 1.0), 0, _rng.randf_range(-1.0, 1.0)) * k("spread", 1.2) * 0.6
			_go(sides[0], r, into, true, "ready", atan2(inward.x, inward.z))
		i += 1


# --- fire arrows over the wall ------------------------------------------------------------------------

## The besiegers' archers loose fire arrows over the wall into the town; now and then a roof catches.
func _fire_arrows(dt: float) -> void:
	_arrow_t -= dt
	if _arrow_t > 0.0 or _arrows.size() >= int(k("arrows.most_flying", 8)):
		return
	_arrow_t = k("arrows.every_s", 1.2) * _rng.randf_range(0.6, 1.4)
	var rows: Array = (sides[0] as Army).rows()
	if rows.is_empty() or ai.town_at == Vector3.INF:
		return
	var from: Vector3 = (rows[_rng.randi() % rows.size()]["node"] as Node3D).global_position + Vector3(0, 0.2, 0)
	var r := k("arrows.spread", 1.4)
	var to: Vector3 = ai.town_at + Vector3(_rng.randf_range(-r, r), 0, _rng.randf_range(-r, r))
	to.y = main.terrain.height_at(to.x, to.z) + 0.2
	var n := Node3D.new()
	add_child(n)
	n.global_position = from
	Fire.hearth(n, Vector3.ZERO)  # the burning rag on its head: fire.gd's small flames
	_arrows.append({"node": n, "from": from, "to": to, "t": 0.0, "dur": from.distance_to(to) / k("arrows.speed", 3.0), "top": from.distance_to(to) * 0.3})


func _fly(dt: float) -> void:
	for a in _arrows.duplicate():
		a["t"] = float(a["t"]) + dt / maxf(float(a["dur"]), 0.1)
		var t := minf(float(a["t"]), 1.0)
		var p: Vector3 = (a["from"] as Vector3).lerp(a["to"], t)
		p.y += float(a["top"]) * 4.0 * t * (1.0 - t)
		(a["node"] as Node3D).global_position = p
		if t >= 1.0:
			if _rng.randf() < k("arrows.catch", 0.18) and _burning_now() < int(k("arrows.most_burning", 6)):
				Fire.kindle(a["to"])
			(a["node"] as Node3D).queue_free()
			_arrows.erase(a)


func _burning_now() -> int:
	return Fire.live._burning.size() if Fire.live else 0
