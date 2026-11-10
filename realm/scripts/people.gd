extends RefCounted
## Builds varied, animated people from Quaternius's Fantasy Outfits, retargeted
## to Godot's humanoid skeleton and driven by Mixamo moves: outfit, hairstyle,
## beard, hair colour, cloth tint and build all vary, so no two look alike.

const S := 0.12  # same scale as the towns: a 1.8 m person is ~0.22 units
## The moves that carry a body across the ground, legs in step. A person who
## is moving plays one of these, whatever was asked (anim_lod.gd sees to it):
## "Carrying" and "Wheelbarrow" are standing moves, the legs barely swing.
const WALKS := ["Walk", "Running", "Sprint", "Sneak", "SS_Walk", "GS_Walk", "Axe_Walk", "Injured_Walk"]
const WALK_PACE := 0.17  # world units a second at a "Walk" played at speed 1
const RUN_PACE := 0.45  # and at "Running"
const MOVING_PACE := WALK_PACE * 0.5  # steadier than this across the ground is walking; slower is standing (a turning dance ring, a shuffle)
## How townsfolk stand about: each keeps one of these as their own "Idle",
## so a crowd never stands in one pose.
const IDLES := ["Idle", "Breathing_Idle", "Standing_Idle", "Standing_Idle_2", "Weight_Shift", "Looking_Around"]
## And how they talk, played for every "Idle_Talking".
const TALKS := ["Idle_Talking", "Talking", "Talking_2", "Happy_Gesture"]
const SEEN_TO := 18.0  # world units: beyond this a person isn't drawn or animated (a few pixels tall)

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

## Mixamo characters, each in assets/people/mixamo/<name>/<name>.fbx and
## retargeted at import to the same humanoid skeleton as the moves. Each says
## who it is ("m"/"f"), which stations it can stand for, and which of its
## meshes are clothing that takes a house's colour. "crowd" bodies are light
## enough to fill a square; the rest stand alone (the court, the close-up).
const BODIES := {
	"arissa": {"sex": "f", "roles": ["archer", "townsfolk"], "cloth": ["arissa_Cloak_Geo"], "crowd": true},
	"erika": {"sex": "f", "roles": ["archer"], "cloth": [], "crowd": true},
	"erika_bow": {"sex": "f", "roles": ["archer"], "cloth": [], "crowd": true},
	"knight": {"sex": "m", "roles": ["soldier", "noble", "knight"], "cloth": ["Lower_Armor"], "crowd": true},
	"paladin": {"sex": "m", "roles": ["soldier", "noble", "knight"], "cloth": [], "crowd": true},
	"paladin_prop": {"sex": "m", "roles": ["noble", "knight"], "cloth": [], "crowd": false},
	"heraklios": {"sex": "m", "roles": ["soldier"], "cloth": [], "crowd": true},
	"dreyar": {"sex": "m", "roles": ["noble", "soldier", "knight"], "cloth": [], "crowd": true},
	"ganfaul": {"sex": "m", "roles": ["soldier"], "cloth": [], "crowd": true},
	"akai": {"sex": "m", "roles": ["archer"], "cloth": [], "crowd": true},
	"brute": {"sex": "m", "roles": ["peasant", "soldier"], "cloth": ["MaleBruteA_Bottoms"], "crowd": false},
	"uriel": {"sex": "m", "roles": ["noble", "knight"], "cloth": [], "crowd": false},
	# Plain townsfolk in tunics and hose (Leonardo Carvalho's Fuse civilians, CC BY, by way of Sketchfab).
	# Their tunic ("material") and breeches ("Bottom") take a homespun dye each, so no two dress alike.
	"fuse_civilian_1": {"sex": "m", "roles": ["townsfolk", "peasant"], "cloth": [], "crowd": true, "dyed": ["Object_12", "Object_13"]},
	"fuse_civilian_2": {"sex": "m", "roles": ["townsfolk", "peasant"], "cloth": [], "crowd": true, "dyed": ["Object_78", "Object_74"]},
	"fuse_woman_1": {"sex": "f", "roles": ["townsfolk"], "cloth": [], "crowd": true, "dyed": ["Object_7"]},  # her linen top, near her skin's colour undyed
	# A townsman in a wool tunic (ChamberSu's Svend, CC BY), his Unreal bones renamed to Mixamo's (tools/ue_to_mixamo.py).
	"svend": {"sex": "m", "roles": ["townsfolk", "peasant"], "cloth": [], "crowd": true, "dyed": ["SvendWoolTunicLOD1"]},
	# A peasant in a belted jerkin and boots (EmanuelP's Medieval Man, CC BY), rigged by Mixamo.
	"medieval_man": {"sex": "m", "roles": ["peasant", "townsfolk"], "cloth": [], "crowd": true},
	# A mendicant friar in a hooded habit (Götz von Berlichingen's monk, CC BY), rigged by Mixamo.
	"monk": {"sex": "m", "roles": ["clergy"], "cloth": [], "crowd": true},
	# Gowned and veiled. Her gown shares a material with her hands and shoes, so it keeps its own colour.
	# Light enough (19k triangles) for the few gentlewomen about a town's market and sept.
	"noble_lady": {"sex": "f", "roles": ["noble"], "cloth": [], "crowd": true},
}
## How often a crowd figure is a Mixamo character rather than a Quaternius
## outfit, by station. The plain Fuse townsfolk, Svend and the jerkined
## peasant stand in for peasants and townsfolk; most clergy wear the friar's habit; archers and
## nobles are all Mixamo. (A Mixamo body is the cheaper of the two: 1-4 draws
## against an outfit's ~9.)
const MIXAMO_SHARE := {"peasant": 0.5, "townsfolk": 0.6, "soldier": 0.5, "archer": 1.0, "noble": 1.0, "knight": 1.0, "clergy": 0.8}

const HEAD_ONLY := preload("res://scripts/head_only.gdshader")

const ANIMS := "res://assets/anims/mixamo/"
const HERO_ANIMS := "res://assets/hero/anims/"
## The Universal Animation Library (Quaternius, CC0), retargeted at import
## (assets/retarget/ual_map.tres): sitting, a torch idle, a formal walk, crouch,
## jog. Guns, spells, swimming and root-motion copies stay out: no place here.
const UAL := "res://assets/anims/AnimationLibrary_Godot_Standard.gltf"
const UAL_SKIP := ["A_TPose", "Pistol", "Spell", "Swim", "_RM", "Roll"]
const Motion := preload("res://scripts/motion.gd")
# Ways a soldier stands ready (all on the shared skeleton), one per man.
const GUARDS := ["Sword_Idle", "Sword_Idle", "SS_Idle_2", "SS_Block_Idle"]

var _lib: AnimationLibrary
var _scenes := {}
var _heights := {}  # Mixamo body -> scale that stands it as tall as an outfit
var _ok := {}  # Mixamo body -> whether it loads with the shared skeleton


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
	# The UAL set, each clip under its own name unless the crowd has one already.
	if ResourceLoader.exists(UAL):
		var ual: Node = (load(UAL) as PackedScene).instantiate()
		for ap in ual.find_children("*", "AnimationPlayer", true, false):
			for n in (ap as AnimationPlayer).get_animation_list():
				var nm := String(n)
				if _lib.has_animation(nm) or UAL_SKIP.any(func(k): return nm.contains(k)):
					continue
				var a: Animation = (ap as AnimationPlayer).get_animation(n)
				if a.length > 0.1:
					_lib.add_animation(nm, _in_place(a.duplicate(true)))
		ual.free()
	# The close-up's own gestures too (Shake No, Dismiss, Relieved Sigh, Talking
	# Hands...), retargeted the same way, named with underscores; a move the
	# crowd already has keeps the crowd's take.
	var hero_dir := DirAccess.open(HERO_ANIMS)
	for f in hero_dir.get_files() if hero_dir else []:
		if not f.ends_with(".fbx"):
			continue
		var name: String = String(f).get_basename().replace(" ", "_")
		if _lib.has_animation(name):
			continue
		var packed := load(HERO_ANIMS + f) as PackedScene
		if packed == null:
			continue
		var src: Node = packed.instantiate()
		var players: Array = src.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			var player: AnimationPlayer = players[0]
			for n in player.get_animation_list():
				var a: Animation = player.get_animation(n)
				if a.length > 0.1:
					_lib.add_animation(name, _in_place(a.duplicate(true)))
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


## role: "peasant", "townsfolk", "soldier", "archer", "noble", "knight" or "clergy".
## Returns a Node3D with an AnimationPlayer named "Anim".
## Body: "child", "young", "adult", "elder"; build: "thin", "average", "stout".
## sex: "male" or "female" to choose, "" for either.
## look: a stable key (a named person's id) that always gives the same body.
func make(rng: RandomNumberGenerator, role := "peasant", tint := Color.WHITE, age := "", build := "", sex := "", look := "") -> Node3D:
	if not MIXAMO_SHARE.has(role):
		role = "peasant"
	if age == "":
		age = ["child", "young", "young", "adult", "adult", "adult", "adult", "elder"][rng.randi() % 8] if role in ["peasant", "townsfolk"] else ["young", "adult"][rng.randi() % 2]
	if build == "":
		build = ["thin", "average", "average", "stout"][rng.randi() % 4]
	var roll := rng.randf()
	# Children and elders are outfits only: every Mixamo character is in their
	# prime, so a lady of 74 would stand there looking 25. Built from parts,
	# an elder gets grey hair and a slightly shorter frame.
	if age not in ["child", "elder"] and (roll < MIXAMO_SHARE[role] or look != ""):
		# A named person is known by their body, so only a crowd needs one that shows its colour.
		# A crowd's sex is rolled first, so the mix of bodies on hand doesn't decide it.
		var want := sex if sex != "" or look != "" else ("male" if rng.randf() < 0.5 else "female")
		var pool := _bodies(role, want, tint != Color.WHITE and look == "", look == "")
		if not pool.is_empty():
			var body: String = pool[(abs(hash(look)) if look != "" else rng.randi()) % pool.size()]
			return make_body(rng, body, tint, age, build, role)
	# A lady in a crowd, or too young or old for the gowned body, wears the dress in her house's colour.
	var outfit_role := "soldier" if role in ["soldier", "archer", "knight"] or (role == "noble" and sex.left(1) != "f") else "peasant"
	var outfits: Array = OUTFITS[outfit_role].filter(func(o): return sex == "" or o[1] == sex.left(1))
	if outfits.is_empty():
		outfits = OUTFITS[outfit_role]
	var pick: Array = outfits[rng.randi() % outfits.size()]
	var person: Node3D = _scene("res://assets/people/%s.gltf" % pick[0]).instantiate()
	var skeleton: Skeleton3D = person.get_node("Armature/GeneralSkeleton")
	var cloth: Color = tint if tint != Color.WHITE else CLOTH[rng.randi() % CLOTH.size()]
	var livery := tint != Color.WHITE and outfit_role == "soldier"
	for child in skeleton.get_children():
		if child is MeshInstance3D:
			_tint(child, cloth, livery)
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
	return _finish(person, skeleton, rng, role, age, build, "male" if pick[1] == "m" else "female")


## The station a named person (a bridge /person record) is dressed for: by
## their court role if they have one, else by rank.
static func station(person: Dictionary) -> String:
	var role := str(person.get("role")) if person.get("role") else ""
	if role in ["knight", "hedge_knight"]:
		return "knight"
	if role == "sellsword":
		return "soldier"
	if role in ["priest", "scholar"]:
		return "clergy"
	if role == "outlaw":
		return "archer"
	if role == "merchant":
		return "townsfolk"
	if role != "" or str(person.get("rank", "")) in ["lord", "spouse", "heir", "bannerman"]:
		return "noble"
	return "townsfolk"


## The Mixamo characters that can stand for a station: of the asked sex if
## any are, able to wear a house's colour if one is asked, and light enough
## for a crowd unless they stand alone.
func _bodies(role: String, sex: String, coloured: bool, crowd: bool) -> Array:
	var pool := BODIES.keys().filter(func(b): return role in BODIES[b]["roles"] and (not crowd or BODIES[b]["crowd"]) and (not coloured or not BODIES[b]["cloth"].is_empty()) and _usable(b))
	# Never the other sex: with no body of theirs, they wear an outfit instead.
	return pool.filter(func(b): return sex == "" or BODIES[b]["sex"] == sex.left(1))


## A body whose file is on disk and imported with the shared skeleton: one
## that isn't (not fetched yet, or its retarget lost) is never cast, so the
## station falls back to an outfit rather than to nobody.
func _usable(body: String) -> bool:
	if not _ok.has(body):
		var path := _path(body)
		var scene: PackedScene = _scene(path) if ResourceLoader.exists(path) else null
		var probe: Node = scene.instantiate() if scene else null
		_ok[body] = probe != null and probe.find_child("GeneralSkeleton", true, false) != null
		if probe:
			probe.free()
	return _ok[body]


static func _path(body: String) -> String:
	var path := "res://assets/people/mixamo/%s/%s.fbx" % [body, body]
	return path if ResourceLoader.exists(path) else path.get_basename() + ".gltf"  # a Mixamo rig that came by way of Sketchfab


## One Mixamo character by name, laid out like the outfits (Armature/
## GeneralSkeleton, an "Anim" player on the shared moves) and stood as tall
## as one, whatever units it came in.
func make_body(rng: RandomNumberGenerator, body: String, tint := Color.WHITE, age := "adult", build := "average", role := "") -> Node3D:
	var info: Dictionary = BODIES[body]
	var person: Node3D = _scene(_path(body)).instantiate()
	for n in person.get_children():
		if n is AnimationPlayer:
			n.free()
	var skeleton: Skeleton3D = person.get_node_or_null("GeneralSkeleton")
	var nested := skeleton == null
	if nested:
		skeleton = person.find_child("GeneralSkeleton", true, false)
	var armature := Node3D.new()
	armature.name = "Armature"
	person.add_child(armature)
	armature.owner = person
	var meshes := skeleton.get_children()
	for n in [skeleton] + meshes:
		n.owner = null
	if nested:
		# Sketchfab wraps the rig in its own nodes, turned and scaled to stand
		# up: it is lifted out as it stands, and the wrapping dropped.
		var xf := _local_xf(person, skeleton)
		skeleton.reparent(armature, false)
		skeleton.transform = xf
		for n in person.get_children():
			if n != armature:
				n.free()  # the empty wrapping
	else:
		skeleton.reparent(armature, false)
	# The moves find the skeleton by its unique name, which needs its owner back.
	skeleton.owner = person
	skeleton.unique_name_in_owner = true
	for mi in skeleton.get_children():
		if mi is MeshInstance3D:
			mi.owner = person
			_solid(mi, nested)
			if tint != Color.WHITE and String(mi.name) in info["cloth"]:
				_tint(mi, tint, role in ["soldier", "archer", "knight"])
			elif String(mi.name) in info.get("dyed", []):
				_tint(mi, DYES[rng.randi() % DYES.size()])
	if role == "":
		role = info["roles"][0]
	person.set_meta("body", body)
	return _finish(person, skeleton, rng, role, age, build, "male" if info["sex"] == "m" else "female", _height(body, skeleton, info["sex"]))


## Homespun colours for clothes that come undyed.
## Undyed linen, ochre, madder, woad, walnut, moss, slate and rust: what a town's dyer has.
const DYES := [Color(0.9, 0.86, 0.76), Color(0.72, 0.58, 0.34), Color(0.66, 0.42, 0.34), Color(0.46, 0.48, 0.6),
	Color(0.5, 0.4, 0.32), Color(0.5, 0.56, 0.44), Color(0.55, 0.56, 0.58), Color(0.62, 0.45, 0.3)]
static var _solid_of := {}  # a body's material -> the copy it is drawn with


## A body is lit by the sun, never by itself, and drawn solid: Mixamo's
## exports switch emission on with the colour map as its glow (trims that
## shone green), and bodies by way of Sketchfab mark every surface see-through
## (hair that sorted away to nothing). Hair keeps its strands, cut out by alpha.
static func _solid(mi: MeshInstance3D, sketchfab := false) -> void:
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as BaseMaterial3D
		if m == null or (not m.emission_enabled and (not sketchfab or m.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED)):
			continue
		if not _solid_of.has(m):
			var c: BaseMaterial3D = m.duplicate()
			c.emission_enabled = false
			if sketchfab and c.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				var strands := String(m.resource_name).to_lower()
				if strands.contains("hair") or strands.contains("beard") or strands.contains("moustache") or strands.contains("lash"):
					c.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
					c.alpha_scissor_threshold = 0.4
				else:
					c.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			_solid_of[m] = c
		mi.set_surface_override_material(s, _solid_of[m])


## Where a node stands relative to an ancestor, from the transforms between them.
static func _local_xf(top: Node, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var p: Node = n
	while p != null and p != top:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## The scale that puts a Mixamo character's head where an outfit's is.
func _height(body: String, skeleton: Skeleton3D, sex: String) -> float:
	if not _heights.has(body):
		var ref: Node3D = _scene("res://assets/people/%s_Peasant.gltf" % ("Male" if sex == "m" else "Female")).instantiate()
		var want := _head_y(ref.get_node("Armature/GeneralSkeleton"))
		ref.free()
		_heights[body] = want / maxf(_head_y(skeleton), 0.001)
	return _heights[body]


static func _head_y(skeleton: Skeleton3D) -> float:
	var head := skeleton.find_bone("Head")
	return (skeleton.transform * skeleton.get_bone_global_rest(head)).origin.y if head >= 0 else 1.0


func _finish(person: Node3D, skeleton: Skeleton3D, rng: RandomNumberGenerator, role: String, age: String, build: String, gender: String, k := 1.0) -> Node3D:
	person.add_to_group("people")  # everyone who stands on the ground, for the ground check
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	person.add_child(anim)
	anim.add_animation_library("", _lib)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Every move goes through the person's state machine (motion.gd); the player
	# only holds the moves.
	var stance := "Sword_Idle" if role in ["soldier", "knight"] else ("Bow_Idle" if role == "archer" else "Idle")
	var mo: AnimationTree = Motion.new()
	person.add_child(mo)
	mo.setup(anim, stance)
	preload("res://scripts/anim_lod.gd").add(mo)  # moved by distance, not every frame regardless
	# Past arm's length of the camera a person is a speck: they fade out and stop
	# costing draws, so a crowd only costs what's near.
	for mi in skeleton.get_children():
		if mi is GeometryInstance3D:
			mi.visibility_range_end = SEEN_TO
			mi.visibility_range_end_margin = 3.0
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	_shape(skeleton, build, age)
	var height: float = rng.randf_range(0.96, 1.04) * {"child": 0.72, "young": 0.98, "adult": 1.0, "elder": 0.96}[age]
	person.scale = Vector3.ONE * height * k * S
	person.set_meta("age", age)
	if role in ["peasant", "townsfolk", "clergy", "noble"]:
		person.set_meta("idle", IDLES[randi() % IDLES.size()])
		person.set_meta("talk", TALKS[randi() % TALKS.size()])
	if role in ["soldier", "knight"]:
		# Each soldier has his own way of standing ready, so a company at ease
		# isn't one pose copied down the ranks.
		person.set_meta("guard", GUARDS[randi() % GUARDS.size()])
		mo.set_ready(String(person.get_meta("guard")))
	# Who this person is, not just how they look: the character layer reads this.
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


static var _tinted := {}  # [material, colour, livery] -> the shared tinted copy


func _tint(mi: MeshInstance3D, colour: Color, livery := false) -> void:
	for s in mi.mesh.get_surface_count():
		var m: Material = mi.get_active_material(s)
		if m is StandardMaterial3D:
			# One copy per material and colour, shared by everyone wearing it: the
			# crowd still draws in batches, however many dyes it wears.
			var key := [m, colour, livery]
			if _tinted.has(key):
				mi.set_surface_override_material(s, _tinted[key])
				continue
			var copy: StandardMaterial3D = m.duplicate()
			copy.albedo_color = m.albedo_color * colour
			# A house's livery reads in its own colour: the cloth's weave kept,
			# its dyed colour taken out first (a grey house on green cloth
			# would otherwise still look green).
			if livery and copy.albedo_texture:
				copy.albedo_texture = _undyed(copy.albedo_texture)
				copy.albedo_color = colour * 1.15
			_tinted[key] = copy
			mi.set_surface_override_material(s, copy)


static var _undyed_of := {}


## A cloth texture with its colour taken out, kept for every soldier that wears it.
static func _undyed(tex: Texture2D) -> Texture2D:
	if not _undyed_of.has(tex):
		var img := tex.get_image()
		if img == null:
			return tex
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_L8)
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		_undyed_of[tex] = ImageTexture.create_from_image(img)
	return _undyed_of[tex]


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


## A person's state machine (motion.gd), or null for a body without one.
static func motion(person: Node) -> AnimationTree:
	return person.get_node_or_null("Motion") as AnimationTree if person else null


## The move a person is making now.
static func clip(person: Node) -> String:
	var mo := motion(person)
	if mo:
		return mo.current()
	var ap: AnimationPlayer = person.get_node_or_null("Anim") if person else null
	return String(ap.current_animation) if ap else ""


## Plays a move once and holds its last frame (a guard raised, a fall). Returns
## the move's length at normal pace.
static func once(person: Node3D, anim_name: String, speed := 1.0, hold := true) -> float:
	var mo := motion(person)
	if mo == null:
		return 0.5
	if mo.dead():
		print("CHECK dead man asked to play %s" % anim_name)
		return 0.0
	# The clip's own length, as the player gave it: callers time by length / speed.
	var rate := speed * float(person.get_meta("tempo", 1.0))
	return mo.play(anim_name, rate, hold, 0.0) * rate


## Whoever wants to know when a clip starts (soundscape.gd: footsteps, hammer
## and axe falls timed to the move): one hook for every clip anyone plays.
static var _listeners: Array[Callable] = []

static func listen(on_clip: Callable) -> void:
	_listeners.append(on_clip)


## Tells the listeners: who, which clip, its period in seconds as played, and
## whether it loops (a walk, a drill repeated) or plays once.
static func _started(person: Node3D, anim_name: String, rate: float, looping: bool) -> void:
	if _listeners.is_empty():
		return
	# A loop asked for again (a walker's gait is asked every frame) is still the
	# same loop: told once, when it starts. A one-off is told every time.
	if looping and person.get_meta("heard", "") == anim_name:
		return
	person.set_meta("heard", anim_name if looping else "")
	var ap: AnimationPlayer = person.get_node_or_null("Anim")
	var period := ap.get_animation(anim_name).length / maxf(rate, 0.01) if ap and ap.has_animation(anim_name) else 0.0
	for c in _listeners:
		if c.is_valid():
			c.call(person, anim_name, period, looping)


## A one-off move practised over and over (a drill): loops instead of returning to rest.
static func repeat(person: Node3D, anim_name: String, speed := 1.0) -> void:
	var mo := motion(person)
	if mo and not mo.dead():
		if not person.has_meta("tempo"):
			person.set_meta("tempo", randf_range(0.85, 1.15))
		mo.play(anim_name, speed * float(person.get_meta("tempo")), false, -1.0, true)
		_started(person, anim_name, speed * float(person.get_meta("tempo")), true)


## A person dies: the machine goes to Dead, which nothing leaves.
static func die(person: Node3D, anim_name: String, speed := 1.0) -> void:
	var mo := motion(person)
	if mo:
		mo.die(anim_name, speed)


## A set of moves of its own (a rider's seat), played as "<name>/<move>".
static func add_moves(person: Node3D, lib_name: String, lib: AnimationLibrary) -> void:
	var ap: AnimationPlayer = person.get_node_or_null("Anim")
	if ap and not ap.has_animation_library(lib_name):
		ap.add_animation_library(lib_name, lib)
	var mo := motion(person)
	if mo:
		mo.add_moves(lib_name, lib)


## For a close-up stage that drives the player itself (a portrait, the hero
## view): the state machine steps aside.
static func release(person: Node3D) -> void:
	var mo := motion(person)
	if mo:
		mo.active = false
		mo.queue_free()
		mo.name = "MotionReleased"
	var ap: AnimationPlayer = person.get_node_or_null("Anim")
	if ap:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE


static func play(person: Node3D, anim_name: String, speed := 1.0, phase := -1.0) -> void:
	# The dead stay down: their machine is in Dead, which nothing leaves. Asking
	# is flagged in the log (CHECK lines), so a film run shows the caller.
	var mo := motion(person)
	if mo and mo.dead():
		print("CHECK dead man asked to play %s" % anim_name)
		return
	if person.get_meta("age", "") == "elder":
		speed *= 0.75
	if anim_name == "Idle":
		anim_name = String(person.get_meta("idle", "Idle"))
	elif anim_name == "Sword_Idle":
		anim_name = String(person.get_meta("guard", "Sword_Idle"))
	elif anim_name == "Idle_Talking":
		anim_name = String(person.get_meta("talk", "Idle_Talking"))
	if mo == null or not mo.has_animation(anim_name):
		return
	# Each at their own tempo, a little quicker or slower than the next.
	if not person.has_meta("tempo"):
		person.set_meta("tempo", randf_range(0.85, 1.15))
	mo.play(anim_name, speed * float(person.get_meta("tempo")), false, phase)
	_started(person, anim_name, speed * float(person.get_meta("tempo")), not preload("res://scripts/motion.gd").is_once(anim_name))
