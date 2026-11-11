extends SceneTree
## Art bake-off (docs/art/target/01-town.jpg): one component from one source, alone
## on grass, under the one look (data/look.json), at roof height. A standalone
## scene: no bridge, no town, nothing of main.gd.
##   GODOT_ARGS="--script res://tools/bakeoff/bakeoff.gd" RES=1200x900 \
##     tools/render.sh /abs/out.png --cell=a_house
## Cells: <source>_<house|keep|trees>, sources:
##   a     the Quaternius Medieval Village kit (house_builder.gd, castle_builder.gd) and Stylized Nature trees
##   pack  today's Sketchfab pack models (assets.json variants)
##   ai    image-to-3D (TRELLIS) from our own Codex concept art: --model=<abs .glb> (loaded at run time)
## --model=<path> overrides the cell's model (res:// scene or an absolute .glb/.gltf).

## True heights in metres, by concept name (the cell after its source: ai_cow -> cow); --height=<m> overrides.
const TARGET_H := {
	"house": 9.0, "keep": 22.0, "trees": 13.0,
	"townhouse_2": 11.0, "townhouse_3": 9.0, "cottage": 6.0, "cottage_2": 6.0, "cottage_3": 6.0,
	"farmhouse_barn": 9.0, "inn": 11.0, "church": 16.0, "mill": 14.0, "watermill": 9.0, "granary": 6.0,
	"forge": 8.0, "armoury": 10.0, "barracks": 9.0, "stables": 7.0, "guard_tower": 16.0, "gatehouse": 18.0,
	"manor": 14.0, "market_stall": 3.5,
	"cow": 1.5, "ox": 1.7, "horse": 1.7, "pig": 0.9, "sheep": 1.0, "goat": 0.9, "chicken": 0.45, "dog": 0.65,
	"haystack": 3.0, "pen": 1.3, "well": 3.5, "cart": 1.4, "wagon": 2.6, "crops": 1.2,
	"barrels": 1.0, "crates": 1.4, "banner_pole": 4.5, "anvil": 1.0, "weapon_rack": 1.6,
}
const KIT_HOUSE := {"w": 2, "d": 3, "floors": 2, "style": "timber", "seed": 31}  # assets.json kit_townhouse_1
const KIT_CASTLE := {"w": 18, "d": 16, "wall_storeys": 2, "keep": 4, "keep_storeys": 5, "tower_storeys": 4, "side_towers": false, "banner": 1.5, "seed": 5}  # kit_castle_seat
const A_TREES := ["res://assets/nature/CommonTree_1.gltf", "res://assets/nature/CommonTree_3.gltf", "res://assets/nature/Pine_2.gltf", "res://assets/nature/CommonTree_4.gltf", "res://assets/nature/Bush_Common.gltf"]
const PACK := {
	"house": "res://assets/realistic/romano-british_house_in_medieval_london/scene.gltf",
	"keep": "res://assets/realistic/medieval_castle/scene.gltf",
	"trees": "res://assets/realistic/oak_trees_pack/scene.gltf",
}
const STRIP := ["Ground", "GroundWater", "Envoiremt_01", "FrontEnv."]

var _shot := "user://bakeoff.png"
var _cell := "a_house"
var _model := ""
var _height := 0.0
var _frames := 0
var _look := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--cell="):
			_cell = a.substr(7)
		elif a.begins_with("--model="):
			_model = a.substr(8)
		elif a.begins_with("--height="):
			_height = float(a.substr(9))
	var f := FileAccess.open("res://data/look.json", FileAccess.READ)
	var v = JSON.parse_string(f.get_as_text()) if f else null
	_look = v if v is Dictionary else {}
	var root := Node3D.new()
	get_root().add_child(root)
	_stage(root)
	var src := _cell.get_slice("_", 0)
	var kind := _cell.substr(src.length() + 1)
	var thing := _make(src, kind)
	if thing == null:
		push_error("bakeoff: nothing to show for %s" % _cell)
		quit(1)
		return
	root.add_child(thing)
	_fit(thing, _height if _height > 0.0 else float(TARGET_H.get(kind, 9.0)))
	_tint(thing)
	_frame(root, thing)


func _rgb(key: String, fb: Color) -> Color:
	var a = _look.get(key)
	return Color(float(a[0]), float(a[1]), float(a[2])) if a is Array and a.size() >= 3 else fb


## The one look, without Sky3D: warm key at sun_elevation, cool ambient, AgX, the LUT,
## the S-curve, SSAO/SSIL, light haze.
func _stage(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.32, 0.52, 0.85)
	sm.sky_horizon_color = Color(0.78, 0.84, 0.92)
	sm.ground_horizon_color = Color(0.78, 0.84, 0.92)
	sm.ground_bottom_color = Color(0.3, 0.35, 0.25)
	sky.sky_material = sm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = float(_look.get("sky_contribution", 0.8))
	env.ambient_light_color = _rgb("ambient_color", Color(0.55, 0.65, 0.95))
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = float(_look.get("exposure", 1.1))
	var ssao: Dictionary = _look.get("ssao", {})
	env.ssao_enabled = true
	env.ssao_radius = float(ssao.get("radius", 1.2))
	env.ssao_intensity = float(ssao.get("intensity", 1.8))
	env.ssao_power = float(ssao.get("power", 1.6))
	var ssil: Dictionary = _look.get("ssil", {})
	env.ssil_enabled = true
	env.ssil_radius = float(ssil.get("radius", 4.0))
	env.ssil_intensity = float(ssil.get("intensity", 1.0))
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = _rgb("haze_color", Color(0.9, 0.92, 1.0))
	env.fog_density = float((_look.get("haze", {}) as Dictionary).get("fog", 0.0008))
	env.adjustment_enabled = true
	var lut := String(_look.get("lut", ""))
	if lut != "" and ResourceLoader.exists(lut):
		env.adjustment_color_correction = load(lut)
	env.adjustment_saturation = float(_look.get("saturation", 1.2))
	env.adjustment_contrast = float(_look.get("contrast", 1.1))
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-float(_look.get("sun_elevation", 42.0)), 35, 0)
	sun.light_energy = 1.6
	sun.light_color = _rgb("sun_color", Color(1.0, 0.95, 0.86))
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 200.0
	root.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400, 400)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = load("res://assets/ground/grass-albedo.jpg")
	gm.normal_enabled = true
	gm.normal_texture = load("res://assets/ground/grass-normal.jpg")
	gm.uv1_scale = Vector3(60, 60, 60)
	ground.material_override = gm
	root.add_child(ground)


func _scene(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps = load(path)
		return ps.instantiate() if ps else null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _mesh_node(m: Mesh) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


func _make(src: String, kind: String) -> Node3D:
	if _model != "":
		return _scene(_model)
	match src:
		"a":
			match kind:
				"house":
					return _mesh_node(load("res://scripts/house_builder.gd").new().build(KIT_HOUSE))
				"keep":
					return _mesh_node(load("res://scripts/castle_builder.gd").new().build_castle(KIT_CASTLE))
				"trees":
					var g := Node3D.new()
					var spots := [Vector3(-3.5, 0, 0.5), Vector3(3, 0, -1.5), Vector3(0, 0, -4), Vector3(0.5, 0, 3.5), Vector3(-1.5, 0, 4.5)]
					var sizes := [13.0, 11.0, 15.0, 9.0, 1.6]
					for i in A_TREES.size():
						var t := _scene(A_TREES[i])
						g.add_child(t)
						_fit(t, sizes[i])
						t.position += spots[i]
						t.rotation.y = i * 1.3
					return g
		"pack":
			var n := _scene(PACK.get(kind, ""))
			if n:
				for s in STRIP:
					var x := n.find_child(s, true, false)
					if x:
						x.queue_free()
						x.get_parent().remove_child(x)
			return n
	return null


func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var all: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		all.append(n)
	for vi in all:
		var b: AABB = vi.global_transform * vi.get_aabb() if vi.is_inside_tree() else _local_xf(vi, n) * vi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _local_xf(n: Node, top: Node) -> Transform3D:
	var xf := Transform3D()
	var c := n
	while c and c != top.get_parent():
		if c is Node3D:
			xf = (c as Node3D).transform * xf
		c = c.get_parent()
	return xf


## Scales a model to the true height and stands it on the ground, centred.
func _fit(n: Node3D, h: float) -> void:
	var b := _aabb(n)
	if b.size.y <= 0.0:
		return
	var k := h / b.size.y
	n.scale *= k
	b = _aabb(n)
	n.position -= Vector3(b.get_center().x, b.position.y, b.get_center().z)


## The one look's kit re-grade (look.json kit_tints): a multiply on matching materials.
func _tint(n: Node) -> void:
	var tints: Dictionary = _look.get("kit_tints", {})
	var all: Array = n.find_children("*", "MeshInstance3D", true, false)
	if n is MeshInstance3D:
		all.append(n)
	for mi in all:
		var m: Mesh = mi.mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat = mi.get_active_material(s)
			if not (mat is BaseMaterial3D):
				continue
			for key in tints:
				if String(mat.resource_name).contains(key):
					var c: Array = tints[key]
					var dup: BaseMaterial3D = mat.duplicate()
					dup.albedo_color = mat.albedo_color * Color(c[0], c[1], c[2])
					mi.set_surface_override_material(s, dup)
					break


## Roof-height oblique: about 35 degrees down, from the front three-quarter, fitted.
func _frame(root: Node3D, thing: Node3D) -> void:
	var b := _aabb(thing)
	var centre := b.get_center()
	var radius := b.size.length() * 0.5
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	var dir := Vector3(0.62, 0.62, 0.8).normalized()
	var dist := radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.0
	cam.look_at_from_position(centre + dir * dist, centre)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 45:
		get_root().get_texture().get_image().save_png(_shot)
		print("Saved ", _shot)
		return true
	return false
