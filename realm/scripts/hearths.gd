extends Node
## Chimney smoke only where someone's home (the finesse catalogue; Manor Lords and Tiny Glade, where a
## house smokes because a family is in). Reads the shared fact villagers.who_is_home and lights or
## damps each house's chimney (towns.gd tags each with its doorstep, group "hearths"). It decides
## nothing about the people; towns with no townsfolk drawn keep their smoke as built.
## A starving town (the mirror's town mood, from the bridge's famine) burns little: only a share
## of its hearths smoke even with someone home, and those thinly (hearths.json hunger).
## Knobs: realm/data/hearths.json. --hearths=off leaves every chimney as built.

var main: Node
var _d := {"on": true, "every_sec": 1.0, "door_match": 0.35}
var _wait := 0.0


func _init(owner: Node) -> void:
	main = owner
	name = "Hearths"


func _ready() -> void:
	var f := FileAccess.open("res://data/hearths.json", FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f else null
	if j is Dictionary:
		_d.merge(j, true)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not bool(_d.get("on", true)) or main.towns == null or main.villagers == null:
		return
	_wait = float(_d.get("every_sec", 1.0))
	_drift()
	var town_of := {}
	for id in main.towns.towns:
		town_of[main.towns.towns[id]["node"]] = id
	var home_by_town := {}
	var hungry_town := {}
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	for h in get_tree().get_nodes_in_group("hearths"):
		var smoke := h as GPUParticles3D
		var root := smoke.get_parent() as Node3D if smoke else null
		if root == null or not town_of.has(root):
			continue
		var id: int = town_of[root]
		if not smoke.has_meta("styled"):
			_style(smoke)  # every town's smoke looks the same, folk drawn there or not
		if not main.villagers.crowds.has(id):
			continue  # no townsfolk drawn here: the chimney stays as built
		if not home_by_town.has(id):
			home_by_town[id] = main.villagers.who_is_home(id)
		var door: Vector3 = root.global_transform * (smoke.get_meta("door") as Vector3)
		var lit := false
		for at in home_by_town[id]:
			if Vector2((at as Vector3).x - door.x, (at as Vector3).z - door.z).length() < float(_d.get("door_match", 0.35)):
				lit = true
				break
		if not hungry_town.has(id):
			hungry_town[id] = aw != null and String(aw.town(id).get_var(&"mood", "", false)) == "hunger"
		var thin := 1.0
		if hungry_town[id]:
			var hg: Dictionary = _d.get("hunger", {})
			if float(absi(hash(Vector2i(roundi(door.x * 100.0), roundi(door.z * 100.0)))) % 1000) / 1000.0 >= float(hg.get("share", 0.5)):
				lit = false  # nothing to cook: this hearth stays cold
			thin = float(hg.get("thin", 0.35))
		if not is_equal_approx(smoke.amount_ratio, thin):
			smoke.amount_ratio = thin
		if smoke.emitting != lit:
			smoke.emitting = lit


# --- how the smoke looks (batch 8b look2: bright white blobs; hearths.json look) ----------------

var _mat: StandardMaterial3D = null  # one for every chimney, so the town's smoke draws as one
var _styled: Array = []  # the chimneys restyled, for the wind's drift


## A chimney's smoke as a thin, soft thread of grey-brown wood smoke (hearths.json look): more, smaller
## puffs that spread as they rise and thin to nothing, drawn unlit so the sun can't blow them to white.
## The smoke itself is towns.gd's (each house's chimney); only its look is set here, once.
func _style(smoke: GPUParticles3D) -> void:
	smoke.set_meta("styled", true)
	var L: Dictionary = _d.get("look", {})
	if L.is_empty():
		return
	var pm := smoke.process_material as ParticleProcessMaterial
	if pm == null:
		return
	pm = pm.duplicate()
	var c: Array = L.get("colour", [0.36, 0.33, 0.3])
	var a: Array = L.get("alpha", [0.16, 0.0])
	var grad := Gradient.new()
	grad.set_color(0, Color(float(c[0]), float(c[1]), float(c[2]), float(a[0])))
	grad.set_color(1, Color(float(c[0]) * 1.1, float(c[1]) * 1.1, float(c[2]) * 1.1, float(a[1])))
	grad.add_point(0.15, Color(float(c[0]), float(c[1]), float(c[2]), float(a[0])))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var sz: Array = L.get("size", [0.05, 0.09])
	pm.scale_min = float(sz[0])
	pm.scale_max = float(sz[1])
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.4))
	grow.add_point(Vector2(1, float(L.get("spread", 2.2))))
	var ct := CurveTexture.new()
	ct.curve = grow
	pm.scale_curve = ct
	var rise: Array = L.get("rise", [0.06, 0.12])
	pm.initial_velocity_min = float(rise[0])
	pm.initial_velocity_max = float(rise[1])
	pm.spread = float(L.get("cone", 8.0))
	smoke.process_material = pm
	smoke.lifetime = float(L.get("life", 6.0))
	smoke.amount = int(L.get("amount", 16))
	if _mat == null:
		_mat = preload("res://scripts/towns.gd").smoke_material(true)
	var q := smoke.draw_pass_1 as QuadMesh
	if q:
		q = q.duplicate()
		q.material = _mat
		smoke.draw_pass_1 = q
	_styled.append(weakref(smoke))


## The one wind (weather_fx.gd's global `wind`: x, z where it blows, w its strength) leans every chimney's
## smoke the same way, as it bends the grass and the wheat.
func _drift() -> void:
	if _styled.is_empty():
		return
	var w: Variant = RenderingServer.global_shader_parameter_get(&"wind")
	var wind: Vector4 = w if w is Vector4 else Vector4(0.8, 0.0, 0.6, 0.3)
	var k := float((_d.get("look", {}) as Dictionary).get("drift", 0.06))
	var lean := Vector3(wind.x, 0, wind.z).normalized() * k * (0.3 + clampf(wind.w, 0.0, 1.0) * 1.7) if Vector2(wind.x, wind.z).length() > 0.001 else Vector3.ZERO
	var keep: Array = []
	for r in _styled:
		var s: GPUParticles3D = r.get_ref()
		if s == null:
			continue
		keep.append(r)
		var pm := s.process_material as ParticleProcessMaterial
		if pm:
			pm.gravity = lean + Vector3(0, 0.005, 0)
	_styled = keep
