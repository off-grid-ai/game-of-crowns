extends Node3D
## The army spike (a test aid; docs/review/army-spike-plan.md; target docs/art/target/03-army.jpg). Run with
## --army-spike=<men> in a shot of Kingsmere (--city=Kingsmere --dist=<height>): it draws that many soldiers as
## regiments of REGIMENT men, each regiment one VATMultiMeshInstance3D (antzGames' VAT plugin, MIT) of the
## baked KayKit Knight (CC0; realm/assets/armies/knight), in ranks and files, each in a house's colour
## (army_vat.gdshader's team colour), marching and wheeling in the fields round the town, and prints
## "ARMY men=… regiments=… fps=… process=… draws=… prims=…" every 2 s. Off in play; nothing else reads it.
## The soldier is asked for by catalogue id (ASSET) so another family is a data change.

const ASSET := "res://assets/armies/knight/"
const REGIMENT := 150
const FILES := 15  # men abreast; ranks = REGIMENT / FILES
const SPACING := 0.06  # world units between men (~half a metre)
const MAN := 0.12  # the soldier's scale in the world (the realm's people: ~0.22 units tall)
const HOUSES := [Color(0.82, 0.62, 0.12), Color(0.72, 0.12, 0.12), Color(0.15, 0.32, 0.72), Color(0.18, 0.5, 0.22), Color(0.45, 0.2, 0.55), Color(0.85, 0.85, 0.82)]

var main: Node
var men := 0
var _regiments: Array = []  # [node, centre, heading, speed]
var _t := 0.0
var _report := 0.0


func _init(owner: Node, count: int) -> void:
	main = owner
	men = count
	name = "ArmySpike"


func _ready() -> void:
	# Wait for the realm and Kingsmere's town to stand, then muster beside it.
	while main.towns == null or main.towns.building() or main.terrain.width == 0:
		await get_tree().create_timer(1.0).timeout
	var at := Vector3.ZERO
	for id in main.towns.towns:
		var c: Dictionary = main.towns.towns[id].get("data", {})
		if String(c.get("title", c.get("name", ""))) == "Kingsmere":
			at = main.towns.towns[id]["node"].global_position
	var mesh := _soldier_mesh()
	if mesh == null:
		push_error("ARMY no soldier mesh at " + ASSET)
		return
	var tracks := _tracks()
	var n := int(ceil(float(men) / REGIMENT))
	var per_row := int(ceil(sqrt(float(n))))
	for i in n:
		var vat: MultiMeshInstance3D = load("res://addons/godot_vat/vat_multi_mesh_instance_3d.gd").new()
		vat.exported_mesh = mesh
		vat.instance_count = REGIMENT
		vat.rand_anim_offset = true
		vat.vat_animation_tracks = tracks
		vat.set_instance_shader_parameter("team_color", HOUSES[i % HOUSES.size()])
		add_child(vat)
		var gx := float(i % per_row) - per_row * 0.5
		var gz := float(i / per_row) - per_row * 0.5
		var centre := at + Vector3(2.5 + gx * FILES * SPACING * 1.4, 0, gz * (REGIMENT / FILES) * SPACING * 1.6)
		_regiments.append([vat, centre, randf() * TAU, 0.08])
		var walk := 1  # Walking_A
		var basis := Basis(Vector3.UP, PI).scaled(Vector3.ONE * MAN)
		for s in REGIMENT:
			# The men's slots, ranks and files, fixed in the regiment's own frame (it moves as one node).
			var f := float(s % FILES) - FILES * 0.5
			var k := float(s / FILES)
			vat.multimesh.set_instance_transform(s, Transform3D(basis, Vector3(f * SPACING, 0, k * SPACING)))
			vat.update_instance_track(s, walk)
			vat.update_instance_animation_offset(s, randf())
			vat.update_instance_alpha(s, 1.0)
	print("ARMY mustered men=%d regiments=%d at Kingsmere%s" % [n * REGIMENT, n, str(at)])
	# The camera on the army itself, at the shot's own --dist (roof, mid, map), from the town's side.
	var dist := 12.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			dist = float(a.substr(7))
	if main.rig:
		main.rig.snap(at + Vector3(2.5, 0, 0), dist, 0.6)


func _process(delta: float) -> void:
	_t += delta
	# Each regiment marches in a slow circle (wheeling) as one node, set on the ground at its centre.
	for r in _regiments:
		var vat: MultiMeshInstance3D = r[0]
		var centre: Vector3 = r[1]
		var heading: float = float(r[2]) + _t * float(r[3])
		var p := centre + Vector3(sin(heading), 0, cos(heading)) * 0.6
		p.y = main.terrain.height_at(p.x, p.z)
		vat.global_transform = Transform3D(Basis(Vector3.UP, heading + PI * 0.5), p)
	_report -= delta
	if _report <= 0.0 and not _regiments.is_empty():
		_report = 2.0
		print("ARMY men=%d regiments=%d fps=%d process=%.1fms draws=%d prims=%dk cam=%.1f" % [_regiments.size() * REGIMENT, _regiments.size(),
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			main.rig.distance if main.rig else 0.0])


## The baked soldier's mesh, its surface wearing the team-colour VAT material (army_vat.gdshader).
func _soldier_mesh() -> ArrayMesh:
	var scene: PackedScene = load(ASSET + "soldier.glb")
	if scene == null:
		return null
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		return null
	var mesh: ArrayMesh = (mi[0] as MeshInstance3D).mesh.duplicate()
	root.free()
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/army_vat.gdshader")
	m.set_shader_parameter("offset_map", load(ASSET + "offsets.exr"))
	m.set_shader_parameter("normal_map", load(ASSET + "normals.png"))
	m.set_shader_parameter("albedo_texture", load(ASSET + "knight_texture.png"))
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, m)
	return mesh


## The baked clips (tracks.json, written by tools/vat_bake.py) as the plugin's tracks.
func _tracks() -> Array[VATAnimationTrack]:
	var out: Array[VATAnimationTrack] = []
	var f := FileAccess.open(ASSET + "tracks.json", FileAccess.READ)
	for t in JSON.parse_string(f.get_as_text()) if f else []:
		var v := VATAnimationTrack.new()
		v.name = String(t["name"])
		v.startFrame = int(t["startFrame"])
		v.endFrame = int(t["endFrame"])
		v.isLooping = bool(t["isLooping"])
		v.isBlended = bool(t.get("isBlended", true))
		v.framerate = int(t.get("framerate", 24))
		out.append(v)
	return out
