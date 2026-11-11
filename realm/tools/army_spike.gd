extends Node3D
## The army spike (a test aid; docs/review/army-spike-plan.md; target docs/art/target/03-army.jpg). Run with
## --army-spike=<men> in a shot (--dist=<height>): it draws that many soldiers as regiments, each regiment one
## VATMultiMeshInstance3D (antzGames' VAT plugin, MIT) of the baked KayKit Knight (CC0; realm/assets/armies/knight),
## each in a house's colour (army_vat.gdshader's team colour), mustered on open dry ground beside the crown's seat
## and facing it, a share still marching in, and prints "ARMY men=… regiments=… fps=… process=… draws=… prims=…"
## every 2 s. Off in play; nothing else reads it. The numbers are in data/army.json (docs/TUNING.md).
## The soldier is asked for by catalogue id (ASSET) so another family is a data change.

const ASSET := "res://assets/armies/knight/"
const Data := preload("res://scripts/data.gd")
const TownNav := preload("res://scripts/town_nav.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const VAT := preload("res://addons/godot_vat/vat_multi_mesh_instance_3d.gd")
const HOUSES := [Color(0.82, 0.62, 0.12), Color(0.72, 0.12, 0.12), Color(0.15, 0.32, 0.72), Color(0.18, 0.5, 0.22), Color(0.45, 0.2, 0.55), Color(0.85, 0.85, 0.82)]
const IDLE := 0  # the baked tracks (tracks.json): Idle, Walking_A, Running_A, two attacks, Block, Hit_A, Death_A
const WALK := 1
const BLOCK := 5

var main: Node
var men := 0
var REGIMENT := int(Data.num("army", "regiment", 150))
var _regiments: Array = []  # {vat, slot, at, face, speed, marching}
var _report := 0.0
var _field := Vector3.ZERO  # the muster's middle, on the ground
var _dist := 12.0
var _hold := false  # the camera held on the army (the whole take)


func _init(owner: Node, count: int) -> void:
	main = owner
	men = count
	name = "ArmySpike"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			_dist = float(a.substr(7))
	# Wait for the land and the realm's towns as the bridge reports them.
	while main.terrain.width == 0 or not main.terrain.built or (main.bridge.world.get("cities", []) as Array).is_empty():
		await get_tree().create_timer(0.5).timeout
	var seat := _seat()
	if seat.is_empty():
		push_error("ARMY no seat in the realm to muster by")
		return
	var id := int(seat["id"])
	# Its town raised first (its buildings are what the field keeps clear of); a while at most.
	main.towns.ensure(id)
	var waited := 0.0
	while not main.towns.towns.has(id) and waited < 30.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
	var town: Vector3 = main.towns.towns[id]["node"].global_position if main.towns.towns.has(id) else main.terrain.world_pos(float(seat["x"]), float(seat["y"]))
	var mesh := _soldier_mesh()
	if mesh == null:
		push_error("ARMY no soldier mesh at " + ASSET)
		return
	var mat := mesh.surface_get_material(0) as ShaderMaterial
	var tracks := _tracks()
	var n := int(ceil(float(men) / REGIMENT))
	var colours := _house_colours()
	var frontages: Array = Data.value("army", "frontages", [15])
	var sf := Data.num("army", "spacing.file", 0.1)
	var sr := Data.num("army", "spacing.rank", 0.12)
	# The largest regiment's footprint sets the field's grid, so no two regiments overlap.
	var wide := 0.0
	var deep := 0.0
	for f in frontages:
		wide = maxf(wide, int(f) * sf)
		deep = maxf(deep, ceil(float(REGIMENT) / int(f)) * sr)
	var slots := _muster(town, n, maxf(wide, deep) + Data.num("army", "gap", 0.35))
	if slots.is_empty():
		push_error("ARMY no open ground by the seat")
		return
	var face := (town - _field) * Vector3(1, 0, 1)
	face = face.normalized() if face.length() > 0.01 else Vector3.FORWARD
	var yaw := atan2(face.x, face.z)  # the knight faces +Z: the host faces the seat
	var rng := RandomNumberGenerator.new()
	rng.seed = 3017
	var share := Data.num("army", "march.share", 0.3)
	var from: Array = Data.value("army", "march.from", [3.0, 9.0])
	var speed := Data.num("army", "march.speed", 0.07)
	var stance := Data.num("army", "stance", 0.25)
	for i in slots.size():
		var slot: Vector3 = slots[i]
		var vat: VATMultiMeshInstance3D = VAT.new()
		vat.exported_mesh = mesh
		vat.material_override = mat  # the plugin's own advice: the VAT material in the Material Override slot
		vat.instance_count = REGIMENT
		vat.rand_anim_offset = true
		vat.vat_animation_tracks = tracks
		vat.set_instance_shader_parameter("team_color", colours[i % colours.size()])
		add_child(vat)
		# Some regiments are still marching in from behind the host, along open ground.
		var start := slot
		var marching := false
		if rng.randf() < share:
			var back := slot - face * rng.randf_range(float(from[0]), float(from[1]))
			if _dry(back, wide) and _dry((back + slot) * 0.5, wide):
				start = back
				marching = true
		var clip := WALK if marching else (BLOCK if rng.randf() < stance else IDLE)
		_dress(vat, int(frontages[rng.randi() % frontages.size()]), sf, sr, clip, rng)
		var r := {"vat": vat, "slot": slot, "at": start, "yaw": yaw + rng.randf_range(-0.06, 0.06), "speed": speed * rng.randf_range(0.9, 1.1), "marching": marching}
		_regiments.append(r)
		_place(r)
	var probe := mesh.surface_get_arrays(0)
	print("ARMY mustered men=%d regiments=%d by %s at %s on open ground %s, %d marching; soldier verts=%d uv2=%s albedo=%s" % [slots.size() * REGIMENT, slots.size(),
		String(seat.get("name", "?")), str(town), str(_field), _regiments.filter(func(r): return r["marching"]).size(),
		(probe[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), str(probe[Mesh.ARRAY_TEX_UV2] != null), str(mat.get_shader_parameter("albedo_texture") != null)])
	_hold = true  # the camera on the army itself, at the shot's own --dist, for the whole take (a test aid)


## The crown's seat (/world seatId), or Kingsmere by name.
func _seat() -> Dictionary:
	var cities: Array = main.bridge.world.get("cities", [])
	var want := int(main.bridge.world.get("seatId", -1)) if main.bridge.world.get("seatId") != null else -1
	for c in cities:
		if int(c.get("id", -2)) == want:
			return c
	for c in cities:
		if String(c.get("name", "")) == "Kingsmere":
			return c
	return {}


## The realm's house colours (as heraldry draws them), the stock six when there are none yet.
func _house_colours() -> Array:
	var out: Array = []
	var houses: Variant = main.get("_houses")
	for h in (houses as Dictionary).values() if houses is Dictionary else []:
		if h is Dictionary and not h.get("wild", false) and h.has("color"):
			var c: Color = Heraldry.colour(h)
			if not out.has(c):
				out.append(c)
	return out if out.size() >= 2 else HOUSES


## One regiment's men in ranks and files, in its own frame (it moves as one node): a frontage of `files`,
## each man a little off his mark, turned a little, a little taller or shorter, at his own point in the clip.
func _dress(vat: VATMultiMeshInstance3D, files: int, sf: float, sr: float, clip: int, rng: RandomNumberGenerator) -> void:
	var tall := Data.num("army", "man", 0.22) / _height
	var place := Data.num("army", "jitter.place", 0.012)
	var turn := Data.num("army", "jitter.turn", 0.18)
	var size := Data.num("army", "jitter.size", 0.06)
	var ranks := int(ceil(float(REGIMENT) / files))
	for s in REGIMENT:
		var f := float(s % files) - (files - 1) * 0.5
		var k := float(s / files) - (ranks - 1) * 0.5
		var b := Basis(Vector3.UP, rng.randf_range(-turn, turn)).scaled(Vector3.ONE * tall * rng.randf_range(1.0 - size, 1.0 + size))
		var p := Vector3(f * sf + rng.randf_range(-place, place), 0, -k * sr + rng.randf_range(-place, place))
		vat.multimesh.set_instance_transform(s, Transform3D(b, p))
		vat.update_instance_track(s, clip)
		vat.update_instance_animation_offset(s, rng.randf())
		vat.update_instance_alpha(s, 1.0)


## Where the host stands: regiment slots on a grid round the open side of the seat, nearest first, each on dry
## land clear of the town's buildings and level enough (terrain.is_land, town_nav.in_building).
func _muster(town: Vector3, n: int, pitch: float) -> Array:
	var clear := Data.num("army", "muster.clear", 4.5)
	var reach := Data.num("army", "muster.reach", 40.0)
	# The open side: the heading with the most dry ground just past the town.
	var best := Vector3.RIGHT
	var most := -1
	for i in 16:
		var d := Vector3(cos(TAU * i / 16.0), 0, sin(TAU * i / 16.0))
		var dry := 0
		for step in range(1, 9):
			if _dry(town + d * (clear + step * 1.5), pitch):
				dry += 1
		if dry > most:
			most = dry
			best = d
	var anchor := town + best * (clear + pitch * sqrt(float(n)) * 0.5)
	var cells: Array = []
	var span := int(ceil(reach / pitch))
	for gx in range(-span, span + 1):
		for gz in range(-span, span + 1):
			var p := anchor + Vector3(gx * pitch, 0, gz * pitch)
			if Vector2(p.x - town.x, p.z - town.z).length() >= clear and p.distance_to(anchor) <= reach:
				cells.append(p)
	cells.sort_custom(func(a: Vector3, b: Vector3): return a.distance_squared_to(anchor) < b.distance_squared_to(anchor))
	var out: Array = []
	for p in cells:
		if out.size() >= n:
			break
		if _dry(p, pitch * 0.9):
			out.append(Vector3(p.x, main.terrain.height_at(p.x, p.z), p.z))
	if not out.is_empty():
		var sum := Vector3.ZERO
		for p in out:
			sum += p
		_field = sum / out.size()
	return out


## A regiment's ground: its middle and four corners dry land, clear of buildings, and level enough.
func _dry(p: Vector3, size: float) -> bool:
	var h: float = main.terrain.height_at(p.x, p.z)
	var slope := Data.num("army", "muster.slope", 0.2)
	for o in [Vector2.ZERO, Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
		var q := Vector3(p.x + o.x * size, 0, p.z + o.y * size)
		if not main.terrain.is_land(q.x, q.z) or TownNav.in_building(main.towns, q, 0.1):
			return false
		if absf(main.terrain.height_at(q.x, q.z) - h) > slope:
			return false
	return true


func _place(r: Dictionary) -> void:
	var at: Vector3 = r["at"]
	at.y = main.terrain.height_at(at.x, at.z)
	(r["vat"] as Node3D).global_transform = Transform3D(Basis(Vector3.UP, float(r["yaw"])), at)


func _process(delta: float) -> void:
	if _hold and main.rig:
		main.rig.snap(_field, _dist, 0.6)
	# The regiments still marching in come on toward their places and stand there at ease.
	for r in _regiments:
		if not r["marching"]:
			continue
		var to: Vector3 = r["slot"] - r["at"]
		to.y = 0.0
		var step := float(r["speed"]) * delta
		if to.length() <= step:
			r["at"] = r["slot"]
			r["marching"] = false
			var vat: VATMultiMeshInstance3D = r["vat"]
			for s in vat.multimesh.instance_count:
				vat.update_instance_track(s, IDLE)
				vat.update_instance_animation_offset(s, randf())
		else:
			r["at"] = r["at"] + to.normalized() * step
		_place(r)
	_report -= delta
	if _report <= 0.0 and not _regiments.is_empty():
		_report = 2.0
		print("ARMY men=%d regiments=%d fps=%d process=%.1fms draws=%d prims=%dk cam=%.1f" % [_regiments.size() * REGIMENT, _regiments.size(),
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0),
			main.rig.distance if main.rig else 0.0])


var _height := 2.45  # the baked soldier's own height (its mesh's bounds), so data/army.json's man is his height in the world


## The baked soldier as one plain mesh wearing the team-colour VAT material (army_vat.gdshader): the import's
## arrays laid into a fresh ArrayMesh, uncompressed, without the importer's LODs or shadow mesh. The VAT shader
## reads each vertex's frame by its UV2 column; a simplified LOD or a merged shadow mesh would draw other
## vertices than the ones baked (the plugin's import guide: compression and LODs off).
func _soldier_mesh() -> ArrayMesh:
	var scene: PackedScene = load(ASSET + "soldier.glb")
	if scene == null:
		return null
	var root := scene.instantiate()
	var mi := root.find_children("*", "MeshInstance3D", true, false)
	if mi.is_empty():
		root.free()
		return null
	var src: Mesh = (mi[0] as MeshInstance3D).mesh
	root.free()
	var mesh := ArrayMesh.new()
	for i in src.get_surface_count():
		var arrays := src.surface_get_arrays(i)
		if arrays[Mesh.ARRAY_TEX_UV2] == null or arrays[Mesh.ARRAY_TEX_UV] == null:
			push_error("ARMY the soldier's mesh has lost its UVs (the VAT column or the palette)")
			return null
		arrays[Mesh.ARRAY_TANGENT] = null  # the shader rebuilds its own frame from the baked normals
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_height = maxf(mesh.get_aabb().size.y, 0.01)
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/army_vat.gdshader")
	m.set_shader_parameter("offset_map", load(ASSET + "offsets.exr"))
	m.set_shader_parameter("normal_map", load(ASSET + "normals.png"))
	m.set_shader_parameter("albedo_texture", load(ASSET + "knight_texture.png"))
	var a := Data.num("army", "albedo", 0.85)
	m.set_shader_parameter("albedo", Color(a, a, a))
	var rects: Array = Data.value("army", "team.rects", [])
	for k in mini(rects.size(), 2):
		var q: Array = rects[k]
		m.set_shader_parameter("team_rect_a" if k == 0 else "team_rect_b", Vector4(float(q[0]), float(q[1]), float(q[2]), float(q[3])))
	m.set_shader_parameter("team_shade", Data.num("army", "team.shade", 1.1))
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
