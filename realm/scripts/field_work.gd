extends Node
## People at work in the countryside's fields through the farming year, and the flocks on the
## fallow (docs/research/world-and-siege-rules.md rules 9-12: Manor Lords' oxen at the plough and its
## harvest, Kingdom Come's routines, Anno's busy fields). The farm state is the countryside's own:
## each field's crop and its stage in the realm's season (countryside.gd: shoots in spring, gold then
## stubble on the field's own reaping day in autumn). This only says who is out in it, near the
## camera: a ploughman behind his oxen walking the furrows in early spring, sowers casting seed,
## weeders and hoers in summer, reapers and binders in the gold with the stooks rising in rows behind
## them, gleaners in the stubble, the cabbages lifted; a shepherd moving his flock from one fallow
## field to the next. What each does next is their mind's (npc_mind.gd posts); the plough team and
## the flock are walked here (movement only). Numbers: realm/data/fieldwork.json (--fieldwork=off).

const Data := preload("res://scripts/data.gd")
const People := preload("res://scripts/people.gd")
const Animals := preload("res://scripts/animals.gd")
const Mind := preload("res://scripts/npc_mind.gd")
const TownLife := preload("res://scripts/town_life.gd")
const Countryside := preload("res://scripts/countryside.gd")

var land: Node3D  # countryside.gd: its fields, its season, its terrain
var _people = null
var _wait := 0.0
var _worked := {}  # crop node -> {job, node (holder), team?}
var _flocks: Array = []  # {node, sheep: [], shepherd, field, rest, goal}
var _rng := RandomNumberGenerator.new()


static func on() -> bool:
	return bool(Data.value("fieldwork", "on", true)) and not OS.get_cmdline_user_args().has("--fieldwork=off")


func _ready() -> void:
	_rng.randomize()


func _people_maker():
	if _people == null:
		var main := land.get_parent() if land else null
		var sc = main.get("scenes") if main else null
		_people = sc.people if sc and sc.get("people") else People.new()
	return _people


## The job a field's crop calls for now (fieldwork.json year), "" for none.
static func job_for(kind: String, season: String, t: float, lag: float) -> String:
	var stage: String = Countryside._stage(kind, season, t, lag)[0]
	for row in Data.value("fieldwork", "year", []):
		if String(row.get("season", "")) != season:
			continue
		var span: Array = row.get("t", [0.0, 1.0])
		if t < float(span[0]) or t >= float(span[1]):
			continue
		var crops := String(row.get("crops", "any"))
		if crops == "standing" and not kind in Countryside.STANDING or crops == "lifted" and kind in Countryside.STANDING:
			continue
		if row.has("stage") and String(row["stage"]) != stage:
			continue
		return String(row.get("job", ""))
	return ""


func _process(delta: float) -> void:
	if land == null or land.terrain == null:
		return
	_walk_teams(delta)
	_walk_flocks(delta)
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = Data.num("fieldwork", "every", 0.5)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	_look(Vector2(cam.global_position.x, cam.global_position.z), Countryside._season_name if Countryside._season_name != "" else String(land.terrain.season), Countryside._through())


## Once in a while: fields out of reach let go, near ones given the work their crop calls for now.
func _look(eye: Vector2, season: String, t: float) -> void:
	var reach := Data.num("fieldwork", "reach", 14.0)
	var keep := Data.num("fieldwork", "keep", 20.0)
	for crop in _worked.keys():
		var w: Dictionary = _worked[crop]
		var gone := not is_instance_valid(crop)
		var job := "" if gone else job_for(String(crop.get_meta("kind", "")), season, t, float(crop.get_meta("lag", 0.5)))
		if gone or _flat(w["at"]).distance_to(eye) > keep or job != String(w["job"]):
			_stop(crop)
		elif w.has("stooks"):
			_stooks(w, t)
	var near: Array = []
	for crop in get_tree().get_nodes_in_group("crops"):
		if _worked.has(crop) or not crop.has_meta("field"):
			continue
		var f: Array = crop.get_meta("field")
		var d := _flat(f[0]).distance_to(eye)
		if d < reach:
			near.append([d, crop])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for n in near:
		if _worked.size() >= int(Data.num("fieldwork", "most_fields", 4)):
			break
		var crop: Node3D = n[1]
		var job := job_for(String(crop.get_meta("kind", "")), season, t, float(crop.get_meta("lag", 0.5)))
		if job != "":
			_start(crop, job, t)
	_flock_look(eye, season, reach, keep)


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## A point in a field (its own frame: x along it, z across, each -0.5..0.5 of its size), on the ground.
func _in(f: Array, x: float, z: float) -> Vector3:
	var size: Vector2 = f[1]
	var p: Vector3 = (f[0] as Vector3) + Basis(Vector3.UP, float(f[2])) * Vector3(x * size.x, 0, z * size.y)
	p.y = land.terrain.height_at(p.x, p.z)
	return p


func _start(crop: Node3D, job: String, t: float) -> void:
	var spec: Dictionary = Data.value("fieldwork", "jobs.%s" % job, {})
	var f: Array = crop.get_meta("field")
	var holder := Node3D.new()
	holder.name = "Work_" + job
	add_child(holder)
	var w := {"job": job, "node": holder, "at": f[0], "field": f}
	_worked[crop] = w
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([f[0], job]) + _rng.randi()
	var men: Array = spec.get("men", [1, 2])
	var count := rng.randi_range(int(men[0]), int(men[1]))
	if _hungry(f[0]):
		count = maxi(1, int(round(count * Data.num("fieldwork", "hunger", 0.5))))
	if job == "plough":
		_plough(w, spec, rng)
		return
	for i in count:
		_hand(holder, f, spec, String(spec.get("post", "")), i, rng)
	var binders: Array = spec.get("binders", [0, 0])
	for i in rng.randi_range(int(binders[0]), int(binders[1])):
		_hand(holder, f, spec, "binder", count + i, rng)
	if spec.has("stooks"):
		w["stooks"] = []
		w["most"] = int(spec["stooks"])
		w["gone_from"] = float(spec.get("stooks_gone", 2.0))
		w["reap_start"] = t
		_stooks(w, t)


## One worker at a spot in the field, facing along it, given their post's mind (or its first move).
func _hand(holder: Node3D, f: Array, spec: Dictionary, post: String, i: int, rng: RandomNumberGenerator) -> void:
	var roles: Array = spec.get("roles", ["peasant"])
	var p: Node3D = _people_maker().make(rng, String(roles[i % roles.size()]), Color.WHITE, "", "", String(spec.get("sex", "")))
	holder.add_child(p)
	p.global_position = _in(f, rng.randf_range(-0.38, 0.38), rng.randf_range(-0.35, 0.35))
	p.rotation.y = float(f[2]) + PI * 0.5 + (PI if rng.randf() < 0.5 else 0.0)
	var ground := func(q: Vector3) -> float: return land.terrain.height_at(q.x, q.z)
	if post == "" or not TownLife.minds_on(-1) or not Mind.give(p, post, ground, rng.randi()):
		People.play(p, "Idle")


## The plough team: oxen yoked side by side and the ploughman behind, walking the field's furrows
## end to end and back, turning at the headland.
func _plough(w: Dictionary, spec: Dictionary, rng: RandomNumberGenerator) -> void:
	var f: Array = w["field"]
	var team := Node3D.new()
	team.name = "Plough"
	(w["node"] as Node3D).add_child(team)
	for k in int(spec.get("oxen", 2)):
		var ox := Animals.make(String(spec.get("team", "cow")), rng, true)
		if ox == null:
			continue
		team.add_child(ox)
		ox.position = Vector3((k - (int(spec.get("oxen", 2)) - 1) * 0.5) * 0.11, 0, 0.12)  # side by side, ahead of the man
	var man: Node3D = _people_maker().make(rng, "peasant", Color.WHITE, "adult")
	team.add_child(man)
	man.position = Vector3(0, 0, -0.16)
	People.play(man, "Walk")
	var lines: Array = []
	var n := maxi(1, int(spec.get("furrows", 4)))
	for i in n:
		var z := lerpf(-0.36, 0.36, (i + 0.5) / n)
		var ends := [-0.42, 0.42] if i % 2 == 0 else [0.42, -0.42]
		lines.append(_in(f, ends[0], z))
		lines.append(_in(f, ends[1], z))
	team.global_position = lines[0]
	w["team"] = team
	w["path"] = lines
	w["leg"] = 1
	w["pace"] = float(spec.get("pace", 0.05))


func _walk_teams(delta: float) -> void:
	for crop in _worked:
		var w: Dictionary = _worked[crop]
		if not w.has("team") or not is_instance_valid(w["team"]):
			continue
		var team: Node3D = w["team"]
		var path: Array = w["path"]
		var to: Vector3 = path[int(w["leg"]) % path.size()]
		var flat := Vector2(to.x - team.global_position.x, to.z - team.global_position.z)
		var step := float(w["pace"]) * delta
		if flat.length() <= step:
			w["leg"] = (int(w["leg"]) + 1) % path.size()  # the headland: turn into the next furrow (and round again)
			continue
		var d := flat.normalized() * step
		var at := team.global_position + Vector3(d.x, 0, d.y)
		at.y = land.terrain.height_at(at.x, at.z)
		team.global_position = at
		team.rotation.y = lerp_angle(team.rotation.y, atan2(d.x, d.y), minf(1.0, delta * 3.0))


## Stooks set up in rows as the field is cut (reaping: rising with the time since it began; in the
## stubble all stand, until they are carted off late in the season).
func _stooks(w: Dictionary, t: float) -> void:
	var most := int(w.get("most", 0))
	var want := most
	if String(w["job"]) == "reap":
		want = int(most * clampf((t - float(w.get("reap_start", t))) / 0.25 + 0.15, 0.0, 1.0))
	elif t >= float(w.get("gone_from", 2.0)):
		want = 0
	var have: Array = w["stooks"]
	while have.size() > want:
		var s: Variant = have.pop_back()
		if is_instance_valid(s):
			(s as Node).queue_free()
	var mesh := Countryside.crop_mesh("hay")
	while have.size() < want and mesh:
		var i := have.size()
		var cols := 3
		var m := MeshInstance3D.new()
		m.mesh = mesh
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visibility_range_end = Countryside.CROP_REACH
		(w["node"] as Node3D).add_child(m)
		m.global_position = _in(w["field"], lerpf(-0.35, 0.35, float(i / cols) / maxf(1.0, ceilf(float(most) / cols) - 1.0)), lerpf(-0.25, 0.25, float(i % cols) / (cols - 1)))
		m.rotation.y = randf() * TAU
		m.scale = Vector3(0.32, 0.55, 0.32)  # a stook: sheaves stood together, about a man's height
		have.append(m)


func _stop(crop: Node) -> void:
	var w: Dictionary = _worked[crop]
	if is_instance_valid(w["node"]):
		(w["node"] as Node).queue_free()
	_worked.erase(crop)


## Whether the land near a point starves (the nearest town's mood on the mirror).
func _hungry(at: Vector3) -> bool:
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	if aw == null:
		return false
	var best := INF
	var mood := ""
	for id in aw.realm.get_var(&"towns", []):
		var bb: Blackboard = aw.town(int(id))
		var tile: Vector2i = bb.get_var(&"tile", Vector2i(-1, -1))
		if tile.x < 0:
			continue
		var p: Vector3 = land.terrain.world_pos(float(tile.x), float(tile.y))
		var d := Vector2(p.x - at.x, p.z - at.z).length()
		if d < best:
			best = d
			mood = String(bb.get_var(&"mood", "", false))
	return mood == "hunger"


# --- flocks -------------------------------------------------------------------------------------

func _flock_look(eye: Vector2, season: String, reach: float, keep: float) -> void:
	var F: Dictionary = Data.value("fieldwork", "flock", {})
	for fl in _flocks.duplicate():
		if not is_instance_valid(fl["node"]) or _flat(fl["field"][0]).distance_to(eye) > keep or not season in F.get("seasons", []):
			if is_instance_valid(fl["node"]):
				(fl["node"] as Node).queue_free()
			_flocks.erase(fl)
	if _flocks.size() >= int(F.get("most", 2)) or not season in F.get("seasons", []) or not land.has_method("fallow_near"):
		return
	var fields: Array = land.fallow_near(eye, reach)
	fields = fields.filter(func(f): return not _flocks.any(func(fl): return (fl["field"][0] as Vector3).is_equal_approx(f[0])))
	if fields.is_empty():
		return
	fields.sort_custom(func(a, b): return _flat(a[0]).distance_to(eye) < _flat(b[0]).distance_to(eye))
	_flock(fields[0], F)


## A shepherd and his sheep on a fallow field: the sheep graze about him; every so often he walks
## them to another fallow field near by (herds moving between fold and pasture: rule 9).
func _flock(f: Array, F: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(f[0]) + _rng.randi()
	var node := Node3D.new()
	node.name = "Flock"
	add_child(node)
	var sheep: Array = []
	var cnt: Array = F.get("count", [5, 8])
	for i in rng.randi_range(int(cnt[0]), int(cnt[1])):
		var s := Animals.make(String(F.get("beast", "sheep")), rng)
		if s == null:
			break
		node.add_child(s)
		s.global_position = _in(f, rng.randf_range(-0.35, 0.35), rng.randf_range(-0.3, 0.3))
		s.rotation.y = rng.randf() * TAU
		sheep.append(s)
	var shepherd: Node3D = _people_maker().make(rng, "peasant", Color.WHITE, ["adult", "elder", "young"][rng.randi() % 3])
	node.add_child(shepherd)
	shepherd.global_position = _in(f, 0.45, 0.0)
	var ground := func(q: Vector3) -> float: return land.terrain.height_at(q.x, q.z)
	if not TownLife.minds_on(-1) or not Mind.give(shepherd, String(F.get("post", "shepherd")), ground, rng.randi()):
		People.play(shepherd, "Idle")
	var span: Array = F.get("move_every", [25.0, 50.0])
	_flocks.append({"node": node, "sheep": sheep, "shepherd": shepherd, "field": f, "rest": rng.randf_range(float(span[0]), float(span[1])), "goal": null, "offs": []})


func _walk_flocks(delta: float) -> void:
	var F: Dictionary = Data.value("fieldwork", "flock", {})
	for fl in _flocks:
		if not is_instance_valid(fl["node"]):
			continue
		if fl["goal"] == null:
			fl["rest"] = float(fl["rest"]) - delta
			if float(fl["rest"]) > 0.0:
				continue
			# Time to move on: another fallow field near by, else round this one.
			var near: Array = land.fallow_near(_flat(fl["field"][0]), 6.0).filter(func(g): return not (g[0] as Vector3).is_equal_approx(fl["field"][0]))
			fl["goal"] = near[_rng.randi() % near.size()] if not near.is_empty() else fl["field"]
			fl["offs"] = (fl["sheep"] as Array).map(func(_s): return Vector2(_rng.randf_range(-0.35, 0.35), _rng.randf_range(-0.3, 0.3)))
			var sh: Node3D = fl["shepherd"]
			var mind := sh.get_node_or_null("Mind")
			if mind:
				mind.set("active", false)  # he leads them now; his mind takes up again on the new field
			People.play(sh, "Walk")
			for s in fl["sheep"]:
				Animals.walk(s, true)
		var goal: Array = fl["goal"]
		var pace := float(F.get("pace", 0.05)) * delta
		var moving := 0
		var lead: Node3D = fl["shepherd"]
		var dest := _in(goal, 0.45, 0.0)
		if _step(lead, dest, pace * 1.1):
			moving += 1
		for i in (fl["sheep"] as Array).size():
			var s: Node3D = fl["sheep"][i]
			var o: Vector2 = fl["offs"][i]
			if is_instance_valid(s) and _step(s, _in(goal, o.x, o.y), pace):
				moving += 1
			elif is_instance_valid(s):
				Animals.walk(s, false)
		if moving == 0:
			fl["field"] = goal
			fl["goal"] = null
			var span: Array = F.get("move_every", [25.0, 50.0])
			fl["rest"] = _rng.randf_range(float(span[0]), float(span[1]))
			var mind := lead.get_node_or_null("Mind")
			if mind:
				(mind.get("blackboard") as Blackboard).set_var(&"post", lead.position)  # his place is by the new field now
				mind.set("active", true)
			else:
				People.play(lead, "Idle")


## One step of a walker toward `to`; false once there.
func _step(n: Node3D, to: Vector3, step: float) -> bool:
	var flat := Vector2(to.x - n.global_position.x, to.z - n.global_position.z)
	if flat.length() <= maxf(step, 0.01):
		return false
	var d := flat.normalized() * step
	var at := n.global_position + Vector3(d.x, 0, d.y)
	at.y = land.terrain.height_at(at.x, at.z)
	n.global_position = at
	n.rotation.y = lerp_angle(n.rotation.y, atan2(d.x, d.y), 0.2)
	return true
