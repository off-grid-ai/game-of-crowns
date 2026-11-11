extends Node3D
## Fire, v2 (docs/art/target/04-siege.jpg; the finesse catalogue's flames and ruins; Stronghold, Total War's
## sack, Manor Lords): a burning house has shaped flames licking off its roof and out of its front, embers, a
## dark sunlit smoke column leaning with the one wind, a scorch on the ground, and it chars as it burns, its roof
## falling in. Made of blocks: GDQuest's stylized fire shader (MIT) over Kenney's Particle Pack flame tongues,
## smoke and scorch sprites (CC0) on Godot's GPUParticles3D; the char is ruins.gd's charring as a shader.
##
## The one owner of the fire's look, and of which houses stand burnt: that is the bridge's damage fact
## (/world cities[].damage.burnt, bridge/damage.js), read from the mirror (awareness.gd's town scope, "burnt"),
## never a timer. A sack or razing (scenes.gd) sets the houses alight; they stay charred while the fact says so
## and stand whole again as the bridge rebuilds them. Knobs: data/fire.json. Switch: --fire=v2 (or fire.json on).

const FLAME_SHADER := preload("res://scripts/stylized_fire.gdshader")
const CHAR_SHADER := preload("res://scripts/charred.gdshader")
const WeatherFx := preload("res://scripts/weather_fx.gd")
const DIR := "res://assets/fx/fire/"
const SMOKE_LAYER := 1 << 10  # smoke is lit by the sun, never by the fire's own light (it glowed orange)
const FAR := 45.0  # game units: beyond this a fire isn't drawn

static var live: Node3D  # the one fire (main.gd adds it): scenes.gd's sacks and razings reach it here
static var _knobs = null
static var _cache := {}  # shared textures and materials, made once

var main: Node  # main.gd: its towns and its mirror (awareness)
var _burnt := {}  # "town:home" -> {shell, hidden: [[MultiMesh, index, transform]], box, root}
var _burning := {}  # "town:home" -> its fire node, while it burns
var _tick := 0.0


static func knobs() -> Dictionary:
	if _knobs == null:
		var f := FileAccess.open("res://data/fire.json", FileAccess.READ)
		var j = JSON.parse_string(f.get_as_text()) if f else null
		_knobs = j if j is Dictionary else {}
	return _knobs


static func on() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--fire=v1"):
		return false
	return args.has("--fire=v2") or bool(knobs().get("on", false))


static func apply(m: Node) -> void:
	if not on():
		return
	var f := new()
	f.name = "Fire"
	f.main = m
	m.add_child(f)


func _ready() -> void:
	live = self


func _exit_tree() -> void:
	if live == self:
		live = null


## A sack (or, razed, a razing) at `at`: the town's houses the damage fact marks burnt catch fire for
## `seconds` (if the fact hasn't come yet, fire.json's share of them). False if there's no town there.
static func ignite(at: Vector3, seconds: float, razed: bool) -> bool:
	return live != null and live._ignite(at, seconds, razed)


## A yard fire's flames (towns.gd _hearth keeps its light and smoke): the same flames, small.
static func hearth(root: Node3D, pos: Vector3) -> void:
	var k: Dictionary = knobs().get("hearth", {})
	var sz: Array = k.get("size", [0.05, 0.08])
	var p := _flames(int(k.get("amount", 8)), float(k.get("life", 0.6)), sz, Vector2(0.15, 0.25), Vector3(0.02, 0.0, 0.02), _flame_material(true))
	p.visibility_range_end = 30.0
	p.position = pos + Vector3(0, 0.01, 0)
	root.add_child(p)


func _ignite(at: Vector3, seconds: float, razed: bool) -> bool:
	var d := knobs()
	var best := -1
	var near := float(d.get("reach", 1.6))
	for id in main.towns.towns:
		var n: Node3D = main.towns.towns[id]["node"]
		if not is_instance_valid(n):
			continue
		var off: Vector3 = n.global_position - at
		if Vector2(off.x, off.z).length() < near:
			near = Vector2(off.x, off.z).length()
			best = id
	if best < 0:
		return false
	var root: Node3D = main.towns.towns[best]["node"]
	var homes: Array = root.get_meta("homes", [])
	if homes.is_empty():
		return false
	var share := maxf(_burnt_share(best), float(d.get("share_razed" if razed else "share_sack", 0.4)))
	var order := _order(best, homes.size())
	for i in mini(homes.size(), maxi(1, ceili(share * homes.size()))):
		var key := "%d:%d" % [best, order[i]]
		if not _burning.has(key):
			_alight(root, key, homes[order[i]], seconds)
	return true


## The town's burnt share, as the mirror holds it (the bridge's damage fact).
func _burnt_share(id: int) -> float:
	if main.awareness == null:
		return 0.0
	return float(main.awareness.town(id).get_var(&"burnt", 0.0, false))


## The order a town's houses burn in: the same every time (by its id), so the fact's share always means the
## same houses, and a sack sets alight the ones that will stand burnt.
func _order(id: int, count: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = hash(id)
	var order := range(count)
	for i in range(count - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t = order[i]
		order[i] = order[j]
		order[j] = t
	return order


## Once a second: each town's burnt houses follow the fact (charred while it says so, whole again once
## rebuilt), and the smoke and embers follow the wind.
func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 1.0
	if main == null or main.towns == null:
		return
	for key in _burnt.keys():
		if not is_instance_valid(_burnt[key]["shell"]):
			_burnt.erase(key)  # its town was built anew: charred again below
	for id in main.towns.towns:
		var root: Node3D = main.towns.towns[id]["node"]
		if not is_instance_valid(root):
			continue
		var homes: Array = root.get_meta("homes", [])
		if homes.is_empty():
			continue
		var n := roundi(_burnt_share(id) * homes.size())
		var order := _order(id, homes.size())
		for i in homes.size():
			var key := "%d:%d" % [id, order[i]]
			if i < n:
				_char(root, key, homes[order[i]])
			elif _burnt.has(key) and not _burning.has(key):
				_mend(key)
	var g := _drift()
	for key in _burning:
		var f: Node3D = _burning[key]
		if is_instance_valid(f):
			for p in f.get_children():
				if p is GPUParticles3D and p.has_meta("drift"):
					((p as GPUParticles3D).process_material as ParticleProcessMaterial).gravity = g * float(p.get_meta("drift")) + Vector3(0, float(p.get_meta("lift", 0.0)), 0)


## The wind's push on smoke and embers (world units/s² per unit of drift), from the one wind.
static func _drift() -> Vector3:
	var w: Vector4 = WeatherFx.wind
	return Vector3(w.x, 0, w.z) * (0.25 + 0.75 * w.w)


## A house set alight: charred (its roof falling in as it burns, embers glowing in the char), flames on its
## roof and out of its front, embers, smoke and the fire's light, for `seconds`; then the flames die down.
func _alight(root: Node3D, key: String, h: Array, seconds: float) -> void:
	var d := knobs()
	var b: Dictionary = _char(root, key, h)
	var box: AABB = b["box"]
	var face: Vector3 = h[1]
	var c := box.get_center()
	var top := box.end.y
	var fire := Node3D.new()
	fire.name = "Burning"
	root.add_child(fire)
	_burning[key] = fire
	var fk: Dictionary = d.get("flames", {})
	var roof := _flames(int(fk.get("amount", 26)), float(fk.get("life", 0.9)), fk.get("size", [0.2, 0.34]), _v2(fk.get("rise", [0.08, 0.18])), Vector3(box.size.x * 0.3, box.size.y * 0.1, box.size.z * 0.3), _flame_material(false), float(fk.get("aspect", 1.6)), float(fk.get("lift", 0.35)))
	roof.position = Vector3(c.x, top - box.size.y * 0.3, c.z)
	fire.add_child(roof)
	var fr: Dictionary = d.get("front", {})
	var front := _flames(int(fr.get("amount", 10)), float(fk.get("life", 0.9)) * 0.8, fr.get("size", [0.09, 0.15]), _v2(fk.get("rise", [0.08, 0.18])) * 0.7, Vector3(box.size.x * 0.25, 0.01, box.size.z * 0.25), _flame_material(false), float(fk.get("aspect", 1.6)), float(fk.get("lift", 0.35)) * 0.5)
	var lateral := Vector3(box.size.x, 0, box.size.z).length() * 0.3
	front.position = Vector3(c.x, box.position.y + box.size.y * float(fr.get("height", 0.35)), c.z) + Vector3(face.x, 0, face.z).normalized() * lateral
	fire.add_child(front)
	var ek: Dictionary = d.get("embers", {})
	var embers := _embers(ek, Vector3(box.size.x * 0.3, 0.02, box.size.z * 0.3))
	embers.position = Vector3(c.x, top, c.z)
	fire.add_child(embers)
	var smoke := _smoke(d.get("smoke", {}))
	smoke.position = Vector3(c.x, top + 0.05, c.z)
	fire.add_child(smoke)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = float(d.get("light_energy", 1.4))
	light.omni_range = float(d.get("light_range", 1.1))
	light.light_cull_mask = 0xFFFFF & ~SMOKE_LAYER
	light.position = Vector3(c.x, box.position.y + box.size.y * 0.5, c.z) + Vector3(face.x, 0, face.z).normalized() * lateral * 1.6
	fire.add_child(light)
	# The roof falls in as it burns; the embers in the char glow while it does, and go out after.
	var ck: Dictionary = d.get("char", {})
	var tw := create_tween()
	for mi in b["shell"].get_children():
		if mi is GeometryInstance3D:
			(mi as GeometryInstance3D).set_instance_shader_parameter("glow", 1.0)
			var cut := float(mi.get_meta("cut", 1.0))
			tw.parallel().tween_method(func(v: float): if is_instance_valid(mi): mi.set_instance_shader_parameter("cut", v), 1.0, cut, seconds * 0.6)
	tw.tween_interval(seconds * 0.4)
	tw.tween_callback(func():
		for p in fire.get_children():
			if p is GPUParticles3D:
				p.emitting = false
		light.queue_free())
	var glow_out := float(ck.get("glow_out", 20.0))
	for mi in b["shell"].get_children():
		if mi is GeometryInstance3D:
			tw.parallel().tween_method(func(v: float): if is_instance_valid(mi): mi.set_instance_shader_parameter("glow", v), 1.0, 0.0, glow_out)
	tw.tween_callback(func():
		fire.queue_free()
		_burning.erase(key))


## A house charred: its kit batches' copy of it hidden, a charred shell of the same meshes in its place
## (part of the roof gone), a scorch under it. Kept in _burnt until mended.
func _char(root: Node3D, key: String, h: Array) -> Dictionary:
	if _burnt.has(key):
		return _burnt[key]
	var d := knobs()
	var shell := Node3D.new()
	shell.name = "Burnt"
	root.add_child(shell)
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	var collapse: Array = (d.get("char", {}) as Dictionary).get("collapse", [0.45, 0.7])
	var cut := r.randf_range(float(collapse[0]), float(collapse[1]))
	var hidden := []
	var box := AABB()
	if h.size() >= 5:
		for g in root.get_children():
			if not (g is MultiMeshInstance3D and String(g.get_meta("kind", "")) == String(h[3])):
				continue
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			var idx := int(h[4])
			if mm == null or mm.mesh == null or idx >= mm.instance_count:
				continue
			var t := mm.get_instance_transform(idx)
			hidden.append([mm, idx, t])
			mm.set_instance_transform(idx, Transform3D(Basis.from_scale(Vector3.ONE * 0.0001), t.origin))
			var mi := MeshInstance3D.new()
			mi.mesh = mm.mesh
			mi.transform = (g as Node3D).transform * t
			for s in mm.mesh.get_surface_count():
				mi.set_surface_override_material(s, _char_material(mm.mesh.surface_get_material(s)))
			var ab := mm.mesh.get_aabb()
			mi.set_instance_shader_parameter("lo", ab.position.y)
			mi.set_instance_shader_parameter("hi", ab.end.y)
			mi.set_instance_shader_parameter("cut", cut)
			mi.set_meta("cut", cut)
			mi.visibility_range_end = (g as GeometryInstance3D).visibility_range_end
			shell.add_child(mi)
			var wb: AABB = mi.transform * ab
			box = wb if box.size == Vector3.ZERO else box.merge(wb)
	if box.size == Vector3.ZERO:  # a house we can't find in the batches: burn where it stands
		var face: Vector3 = h[1]
		var at: Vector3 = (h[2] if h.size() >= 3 else Vector3(h[0]) - face * 0.15)
		box = AABB(at - Vector3(0.12, 0.0, 0.12), Vector3(0.24, 0.3, 0.24))
	var scorch := Decal.new()
	scorch.texture_albedo = _scorch()
	var sz := float(d.get("scorch_size", 1.7)) * maxf(box.size.x, box.size.z)
	scorch.size = Vector3(sz, 0.3, sz)
	scorch.rotation.y = r.randf() * TAU
	scorch.position = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	scorch.distance_fade_enabled = true  # a Decal has no visibility range; it fades by distance instead
	scorch.distance_fade_begin = FAR * 0.8
	scorch.distance_fade_length = FAR * 0.2
	shell.add_child(scorch)
	_burnt[key] = {"shell": shell, "hidden": hidden, "box": box}
	return _burnt[key]


## A burnt house rebuilt (the fact says so): the shell gone, the house back in its batch.
func _mend(key: String) -> void:
	var b: Dictionary = _burnt[key]
	for e in b["hidden"]:
		(e[0] as MultiMesh).set_instance_transform(int(e[1]), e[2])
	if is_instance_valid(b["shell"]):
		b["shell"].queue_free()
	_burnt.erase(key)


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Flames: tall billboards of the flame shader, born small, swelling, then eaten away from the edges as
## they rise (alpha erosion), each a random frame of the tongues.
static func _flames(amount: int, life: float, size: Array, rise: Vector2, box: Vector3, mat: Material, aspect := 1.6, lift := 0.35) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 6.0
	pm.initial_velocity_min = rise.x
	pm.initial_velocity_max = rise.y
	pm.gravity = Vector3(0, lift, 0)
	pm.scale_min = float(size[0])
	pm.scale_max = float(size[1])
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.45))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.7))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.8), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.3)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.randomness = 0.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1.0, aspect)
	q.center_offset = Vector3(0, aspect * 0.35, 0)  # the flame's foot at its particle: it rises from the roof
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(-box - Vector3(0.6, 0.2, 0.6), box * 2.0 + Vector3(1.2, 1.6, 1.2))
	p.visibility_range_end = FAR
	return p


static func _embers(k: Dictionary, box: Vector3) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box
	pm.direction = Vector3.UP
	pm.spread = 25.0
	var rise: Array = k.get("rise", [0.25, 0.5])
	pm.initial_velocity_min = float(rise[0])
	pm.initial_velocity_max = float(rise[1])
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.5
	pm.gravity = _drift() * 0.5
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1.0, 0.85, 0.4, 1.0), Color(1.0, 0.3, 0.05, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	var p := GPUParticles3D.new()
	p.amount = int(k.get("amount", 14))
	p.lifetime = float(k.get("life", 2.2))
	p.process_material = pm
	p.set_meta("drift", 0.5)
	var q := QuadMesh.new()
	var s := float(k.get("size", 0.014))
	q.size = Vector2(s, s)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://scripts/towns.gd").soft_dot()  # load, not preload: towns.gd preloads this file
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-2, -0.5, -2), Vector3(4, 4, 4))
	p.visibility_range_end = FAR
	return p


## The smoke column: Kenney's billowing smoke sprites, dark and lit by the sun (not by the fire), swelling
## as they rise and drifting downwind.
static func _smoke(k: Dictionary) -> GPUParticles3D:
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3.UP
	pm.spread = 10.0
	var rise: Array = k.get("rise", [0.12, 0.22])
	pm.initial_velocity_min = float(rise[0])
	pm.initial_velocity_max = float(rise[1])
	var drift := float(k.get("drift", 0.18))
	pm.gravity = _drift() * drift
	pm.damping_min = 0.02
	pm.damping_max = 0.05
	var sz: Array = k.get("size", [0.35, 0.8])
	pm.scale_min = float(sz[0])
	pm.scale_max = float(sz[1])
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1.0 / float(k.get("grow", 3.0))))
	curve.add_point(Vector2(1, 1.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -8.0
	pm.angular_velocity_max = 8.0
	var c: Array = k.get("colour", [0.12, 0.11, 0.1, 0.85])
	var col := Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 0.6, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), col, Color(col.lightened(0.25), col.a * 0.7), Color(col.lightened(0.4), 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	pm.anim_offset_min = 0.0
	pm.anim_offset_max = 1.0
	var p := GPUParticles3D.new()
	p.amount = int(k.get("amount", 26))
	p.lifetime = float(k.get("life", 7.0))
	p.preprocess = 2.0
	p.process_material = pm
	p.set_meta("drift", drift)
	p.layers = SMOKE_LAYER
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	q.material = _smoke_material()
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-4, -0.5, -4), Vector3(8, 6, 8))
	p.visibility_range_end = FAR + 20.0
	return p


static func _smoke_material() -> StandardMaterial3D:
	if _cache.has("smoke"):
		return _cache["smoke"]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _strip(["smoke_04", "smoke_05", "smoke_07", "smoke_08"], 128, 128, false)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 4
	m.particles_anim_v_frames = 1
	m.particles_anim_loop = false
	m.roughness = 1.0
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.15
	_cache["smoke"] = m
	return m


## The flame material: hearth (small flames, finer noise) or house.
static func _flame_material(small: bool) -> ShaderMaterial:
	var key := "flame_small" if small else "flame"
	if _cache.has(key):
		return _cache[key]
	var d := knobs()
	var fk: Dictionary = d.get("flames", {})
	var ck: Dictionary = d.get("colours", {})
	var m := ShaderMaterial.new()
	m.shader = FLAME_SHADER
	m.set_shader_parameter("texture_mask", _strip(["flame_05", "flame_06", "flame_05", "flame_06"], 128, int(128 * float(fk.get("aspect", 1.6))), true))
	m.set_shader_parameter("noise_texture", _noise())
	m.set_shader_parameter("frames", 4)
	m.set_shader_parameter("texture_scale", float(fk.get("noise_scale", 7.0)) * (3.0 if small else 1.0))
	m.set_shader_parameter("lean", float(fk.get("lean", 0.7)))
	for band in ["core", "body", "edge"]:
		var a: Array = ck.get(band, [1, 1, 1])
		m.set_shader_parameter(band, Color(float(a[0]), float(a[1]), float(a[2])))
	m.set_shader_parameter("brightness", float(ck.get("brightness", 1.25)))
	_cache[key] = m
	return m


## The charred copy of a house material (its texture and colour kept under the soot).
static func _char_material(src: Material) -> ShaderMaterial:
	if _cache.has(src):
		return _cache[src]
	var m := ShaderMaterial.new()
	m.shader = CHAR_SHADER
	m.set_shader_parameter("noise_texture", _noise())
	var tex: Texture2D = null
	var col := Color.WHITE
	if src is BaseMaterial3D:
		tex = (src as BaseMaterial3D).albedo_texture
		col = (src as BaseMaterial3D).albedo_color
	elif src is ShaderMaterial:  # a kit material already in its holder's colours (team_colour.gd)
		var t = (src as ShaderMaterial).get_shader_parameter("albedo_tex")
		tex = t if t is Texture2D else null
		var a = (src as ShaderMaterial).get_shader_parameter("albedo")
		col = a if a is Color else Color.WHITE
	m.set_shader_parameter("albedo_tex", tex)
	m.set_shader_parameter("has_albedo_tex", tex != null)
	m.set_shader_parameter("albedo", col)
	_cache[src] = m
	return m


static func _noise() -> Texture2D:
	if not _cache.has("noise"):
		var n := FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.fractal_octaves = 3
		n.frequency = 0.02
		var t := NoiseTexture2D.new()
		t.noise = n
		t.seamless = true
		t.width = 128
		t.height = 128
		_cache["noise"] = t
	return _cache["noise"]


## Kenney's sprites (black backgrounds: brightness is the shape) side by side as one flipbook strip, each
## cropped to its shape and fitted to w x h; the second half mirrored for variety (`mirror`). Alpha from
## brightness, colour white (the shader or the particle colour gives it).
static func _strip(names: Array, w: int, h: int, mirror: bool) -> Texture2D:
	var key := "strip:" + ",".join(names)
	if _cache.has(key):
		return _cache[key]
	var out := Image.create_empty(w * names.size(), h, false, Image.FORMAT_RGBA8)
	for i in names.size():
		var tex: Texture2D = load(DIR + String(names[i]) + ".png")
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(128, 128)
		var used := _bright_rect(img)
		var part := img.get_region(used)
		part.resize(w, h)
		if mirror and i >= names.size() / 2:
			part.flip_x()
		for y in h:
			for x in w:
				var v := part.get_pixel(x, y).get_luminance()
				out.set_pixel(i * w + x, y, Color(1, 1, 1, v))
	out.generate_mipmaps()
	var t := ImageTexture.create_from_image(out)
	_cache[key] = t
	return t


## Where a black-backed sprite's shape lies (brighter than a trace), a little padded.
static func _bright_rect(img: Image) -> Rect2i:
	var lo := Vector2i(img.get_width(), img.get_height())
	var hi := Vector2i(0, 0)
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).get_luminance() > 0.04:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x <= lo.x or hi.y <= lo.y:
		return Rect2i(Vector2i.ZERO, img.get_size())
	return Rect2i(lo - Vector2i(2, 2), hi - lo + Vector2i(5, 5)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))


## The scorch under a burnt house: Kenney's scorch, black, its brightness the soot's reach.
static func _scorch() -> Texture2D:
	if _cache.has("scorch"):
		return _cache["scorch"]
	var img: Image = (load(DIR + "scorch_03.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.resize(256, 256)
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).get_luminance()
			img.set_pixel(x, y, Color(0.03, 0.025, 0.02, clampf(v * 1.6, 0.0, 0.92)))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache["scorch"] = t
	return t
