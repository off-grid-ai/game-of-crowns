extends RefCounted
## Builds varied, animated people from Quaternius's Fantasy Outfits, retargeted
## to Godot's humanoid skeleton and driven by Mixamo moves: outfit, hairstyle,
## beard, hair colour, cloth tint and build all vary, so no two look alike.

const S := 0.12  # same scale as the towns: a 1.8 m person is ~0.22 units

const OUTFITS := {
	"peasant": [["Male_Peasant", "m"], ["Female_Peasant", "f"]],
	"soldier": [["Male_Ranger", "m"], ["Female_Ranger", "f"]],
}
const HAIR := {"m": ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", ""], "f": ["Hair_Long", "Hair_Buns", "Hair_BuzzedFemale"]}
const HAIR_COLOURS := [Color(0.18, 0.12, 0.08), Color(0.35, 0.22, 0.12), Color(0.08, 0.07, 0.06), Color(0.55, 0.4, 0.22), Color(0.5, 0.25, 0.12), Color(0.55, 0.53, 0.5)]
const MALE_NAMES := ["Aldric", "Bran", "Cedric", "Dunstan", "Edric", "Godwin", "Harold", "Jory", "Osric", "Rowan", "Tobin", "Wat", "Hugh", "Garth", "Alaric", "Ewan"]
const FEMALE_NAMES := ["Agnes", "Bryony", "Cecily", "Edith", "Elsbeth", "Gwen", "Hilda", "Isolde", "Joan", "Maud", "Rosalind", "Wynne", "Alys", "Mira", "Tamsin", "Ysolde"]
const BYNAMES := ["the Smith", "Miller", "of the Ford", "Thatcher", "the Tall", "Cooper", "Fletcher", "Brewer", "Greenhill", "Ashby", "the Younger", "Tanner", "Carter", "Weaver", "Hayward", "Shepherd"]
const SKIN := [Color(1.0, 0.86, 0.74), Color(0.95, 0.78, 0.64), Color(0.82, 0.62, 0.48), Color(0.62, 0.45, 0.33), Color(0.45, 0.32, 0.24), Color(1.0, 0.9, 0.8)]
const CLOTH := [Color(1, 1, 1), Color(0.85, 0.75, 0.62), Color(0.7, 0.8, 0.7), Color(0.75, 0.7, 0.85), Color(0.9, 0.7, 0.6), Color(0.65, 0.65, 0.65)]

const HEAD_ONLY := preload("res://scripts/head_only.gdshader")

const ANIMS := "res://assets/anims/mixamo/"

var _lib: AnimationLibrary
var _scenes := {}


func _init() -> void:
	# Mixamo moves, retargeted at import to Godot's humanoid skeleton like the
	# outfits, so any Mixamo download plays on any townsperson. Each file is one
	# move, named for what the game asks for ("Walk", "Sword_Idle", "Praying").
	_lib = AnimationLibrary.new()
	var dir := DirAccess.open(ANIMS)
	for f in dir.get_files() if dir else []:
		if not f.ends_with(".fbx"):
			continue
		var packed := load(ANIMS + f) as PackedScene
		if packed == null:
			continue
		var src: Node = packed.instantiate()
		var players: Array = src.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			var player: AnimationPlayer = players[0]
			for n in player.get_animation_list():
				var a: Animation = player.get_animation(n)
				if a.length > 0.1:
					_lib.add_animation(f.get_basename(), _in_place(a.duplicate(true)))
					break
		src.free()


## Townsfolk are moved by the game, not the clip: keep the hips' sway and bob
## but take out any drift across the ground, and drop non-bone tracks.
static func _in_place(a: Animation) -> Animation:
	for t in range(a.get_track_count() - 1, -1, -1):
		if not String(a.track_get_path(t)).contains(":"):
			a.remove_track(t)
			continue
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D or not String(a.track_get_path(t)).ends_with(":Hips"):
			continue
		var n := a.track_get_key_count(t)
		if n < 2:
			continue
		var first: Vector3 = a.track_get_key_value(t, 0)
		var drift: Vector3 = a.track_get_key_value(t, n - 1) - first
		var span := maxf(a.track_get_key_time(t, n - 1), 0.001)
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			var along := drift * (a.track_get_key_time(t, k) / span)
			a.track_set_key_value(t, k, Vector3(v.x - along.x, v.y, v.z - along.z))
	return a


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path)
	return _scenes[path]


## role: "peasant" or "soldier". Returns a Node3D with an AnimationPlayer named "Anim".
## Body: "child", "young", "adult", "elder"; build: "thin", "average", "stout".
## sex: "male" or "female" to choose, "" for either.
func make(rng: RandomNumberGenerator, role := "peasant", tint := Color.WHITE, age := "", build := "", sex := "") -> Node3D:
	if age == "":
		age = ["child", "young", "young", "adult", "adult", "adult", "adult", "elder"][rng.randi() % 8] if role == "peasant" else ["young", "adult"][rng.randi() % 2]
	if build == "":
		build = ["thin", "average", "average", "stout"][rng.randi() % 4]
	var outfits: Array = OUTFITS[role].filter(func(o): return sex == "" or o[1] == sex.left(1))
	if outfits.is_empty():
		outfits = OUTFITS[role]
	var pick: Array = outfits[rng.randi() % outfits.size()]
	var person: Node3D = _scene("res://assets/people/%s.gltf" % pick[0]).instantiate()
	var skeleton: Skeleton3D = person.get_node("Armature/GeneralSkeleton")
	var cloth: Color = tint if tint != Color.WHITE else CLOTH[rng.randi() % CLOTH.size()]
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			_tint(child, cloth)
	# The outfits are clothing only; the base character supplies head, hands and face.
	var styles: Array = HAIR[pick[1]]
	var hair_colour: Color = HAIR_COLOURS[rng.randi() % HAIR_COLOURS.size()]
	if age == "elder":
		hair_colour = Color(0.62, 0.6, 0.57).lerp(Color(0.85, 0.84, 0.8), rng.randf())
	# The base character supplies the head; its eyebrows take the hair's colour.
	_attach(skeleton, "", hair_colour, "res://assets/people/base/Superhero_%s_FullBody.gltf" % ("Male" if pick[1] == "m" else "Female"), SKIN[rng.randi() % SKIN.size()])
	var style: String = styles[rng.randi() % styles.size()]
	if style != "":
		_attach(skeleton, style, hair_colour)
	if pick[1] == "m" and age != "child" and rng.randf() < (0.7 if age == "elder" else 0.4):
		_attach(skeleton, "Hair_Beard", hair_colour)
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	person.add_child(anim)
	anim.add_animation_library("", _lib)
	_shape(skeleton, build, age)
	var height: float = rng.randf_range(0.96, 1.04) * {"child": 0.72, "young": 0.98, "adult": 1.0, "elder": 0.96}[age]
	person.scale = Vector3.ONE * height * S
	person.set_meta("age", age)
	# Who this person is, not just how they look: the character layer reads this.
	var gender: String = "male" if pick[1] == "m" else "female"
	var names: Array = MALE_NAMES if gender == "male" else FEMALE_NAMES
	person.set_meta("identity", {
		"name": "%s %s" % [names[rng.randi() % names.size()], BYNAMES[rng.randi() % BYNAMES.size()]],
		"gender": gender, "age": age,
		"years": {"child": rng.randi_range(6, 13), "young": rng.randi_range(15, 22), "adult": rng.randi_range(23, 50), "elder": rng.randi_range(55, 78)}[age],
		"build": build, "role": role,
	})
	return person


## Body shape by bone scale: the same models read as stout or thin, child or elder.
func _shape(skeleton: Skeleton3D, build: String, age: String) -> void:
	var girth: float = {"thin": 0.94, "average": 1.0, "stout": 1.08}[build]
	for bone in ["Hips", "Spine", "Chest"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			skeleton.set_bone_pose_scale(i, Vector3(girth, 1.0, girth * (1.05 if build == "stout" else 1.0)))
	for bone in ["LeftUpperLeg", "RightUpperLeg"]:
		var i := skeleton.find_bone(bone)
		if i >= 0:
			skeleton.set_bone_pose_scale(i, Vector3(lerpf(1.0, girth, 0.5), 1.0, lerpf(1.0, girth, 0.5)))
	if age == "child":
		var head := skeleton.find_bone("Head")
		if head >= 0:
			skeleton.set_bone_pose_scale(head, Vector3.ONE * 1.1)


func _tint(mi: MeshInstance3D, colour: Color) -> void:
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		if m is StandardMaterial3D:
			var copy: StandardMaterial3D = m.duplicate()
			copy.albedo_color = m.albedo_color * colour
			mi.set_surface_override_material(s, copy)


## Hair and beards are skinned to the head bone; re-home their meshes on our skeleton.
func _attach(skeleton: Skeleton3D, style: String, colour: Color, path := "", skin_tone := Color.WHITE) -> void:
	var src: Node = _scene(path if path != "" else "res://assets/people/hair/%s.gltf" % style).instantiate()
	var stack := [src]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := MeshInstance3D.new()
			mi.mesh = n.mesh
			mi.skin = n.skin
			skeleton.add_child(mi)
			mi.skeleton = NodePath("..")
			for s in mi.mesh.get_surface_count():
				var m: Material = n.get_active_material(s)
				if path != "" and String(n.name).to_lower().begins_with("superhero") and m is StandardMaterial3D:
					# Only the head and neck of the base body show; the outfit is the body.
					var head := ShaderMaterial.new()
					head.shader = HEAD_ONLY
					head.set_shader_parameter("albedo_tex", m.albedo_texture)
					head.set_shader_parameter("tint", skin_tone)
					head.set_shader_parameter("head_bone", _bind(mi.skin, "Head"))
					head.set_shader_parameter("neck_bone", _bind(mi.skin, "Neck"))
					mi.set_surface_override_material(s, head)
				elif m is StandardMaterial3D:
					var copy: StandardMaterial3D = m.duplicate()
					if path == "" or String(n.name).to_lower().begins_with("eyebrow"):
						copy.albedo_color = colour
					mi.set_surface_override_material(s, copy)
		stack.append_array(n.get_children())
	src.free()


func _bind(skin: Skin, bone: String) -> int:
	for i in skin.get_bind_count():
		if String(skin.get_bind_name(i)) == bone:
			return i
	return -1


static func play(person: Node3D, anim_name: String, speed := 1.0) -> void:
	if person.get_meta("age", "") == "elder":
		speed *= 0.75
	var anim: AnimationPlayer = person.get_node_or_null("Anim")
	if anim == null or not anim.has_animation(anim_name):
		return
	if anim.current_animation != anim_name:
		anim.play(anim_name, 0.25)
		var a := anim.get_animation(anim_name)
		a.loop_mode = Animation.LOOP_LINEAR
		# Each person joins the motion at their own point in it, so no two move in step.
		anim.seek(randf() * a.length, false)
	# And at their own tempo, a little quicker or slower than the next.
	if not person.has_meta("tempo"):
		person.set_meta("tempo", randf_range(0.85, 1.15))
	anim.speed_scale = speed * float(person.get_meta("tempo"))
