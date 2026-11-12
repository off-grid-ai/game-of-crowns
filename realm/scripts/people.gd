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
## Who fights (dressed and tinted as soldiers; presence.gd's soldierly bearing), and of
## them who stands ready with a sword (an archer stands with his bow): one list each.
const SOLDIERLY := ["soldier", "archer", "knight"]
const SWORDED := ["soldier", "knight"]
const SEEN_TO := 18.0  # world units: beyond this a person isn't drawn or animated (a few pixels tall)

const OUTFITS := {
	"peasant": [["Male_Peasant", "m"], ["Female_Peasant", "f"]],
	"soldier": [["Male_Ranger", "m"]],  # a man of the watch in hood and leather; no women in the watch (Female_Ranger is out: plain medieval, Mac 2026-11-10)
}
const HAIR := {"m": ["Hair_SimpleParted", "Hair_Buzzed", "Hair_Long", ""], "f": ["Hair_Long", "Hair_Buns", "Hair_BuzzedFemale"]}
const HAIR_COLOURS := [Color(0.18, 0.12, 0.08), Color(0.35, 0.22, 0.12), Color(0.08, 0.07, 0.06), Color(0.55, 0.4, 0.22), Color(0.5, 0.25, 0.12), Color(0.55, 0.53, 0.5)]
const MALE_NAMES := ["Aldric", "Bran", "Cedric", "Dunstan", "Edric", "Godwin", "Harold", "Jory", "Osric", "Rowan", "Tobin", "Wat", "Hugh", "Garth", "Alaric", "Ewan"]
const FEMALE_NAMES := ["Agnes", "Bryony", "Cecily", "Edith", "Elsbeth", "Gwen", "Hilda", "Isolde", "Joan", "Maud", "Rosalind", "Wynne", "Alys", "Mira", "Tamsin", "Ysolde"]
const BYNAMES := ["the Smith", "Miller", "of the Ford", "Thatcher", "the Tall", "Cooper", "Fletcher", "Brewer", "Greenhill", "Ashby", "the Younger", "Tanner", "Carter", "Weaver", "Hayward", "Shepherd"]
const SKIN := [Color(1.0, 0.86, 0.74), Color(0.95, 0.78, 0.64), Color(0.82, 0.62, 0.48), Color(0.62, 0.45, 0.33), Color(0.45, 0.32, 0.24), Color(1.0, 0.9, 0.8)]

## Mixamo characters, each in assets/people/mixamo/<name>/<name>.fbx and
## retargeted at import to the same humanoid skeleton as the moves. Each says
## who it is ("m"/"f"), which stations it can stand for, and which of its
## meshes are clothing that takes a house's colour. "crowd" bodies are light
## enough to fill a square; the rest stand alone (the court, the close-up).
const BODIES := {
	# Erika, Arissa and Eve are out: modern black leather and fitted suits read as a joke in a medieval town (Mac, 2026-11-10).
	# Akai (face paint, buckled leather, goggles), Ganfaul (half a demon's face, a horned arm) and Uriel (wings) are out too:
	# fantasy, not a medieval town. Archers wear a soldier's outfit; soldiers and nobles keep the armoured bodies above.
	# Dreyar (glowing red gems, spiked anime hair), Brute (bare-chested, tribal tattoos) and the Fuse woman (a short
	# tunic over bare legs, which reads as a short dress once dyed dark) are out with them (Mac's feast shots, 20:20).
	# Women in the street wear the peasant's dress (OUTFITS); gentlewomen the noble lady's gown.
	"knight": {"sex": "m", "roles": ["noble", "knight"], "cloth": ["Lower_Armor"], "crowd": true},  # mail and a surcoat: knights and lords, never the common soldier
	"paladin": {"sex": "m", "roles": ["knight"], "cloth": [], "crowd": false},  # ornate plate and great pauldrons: a knight at court, never a face in the street
	"paladin_prop": {"sex": "m", "roles": ["noble", "knight"], "cloth": [], "crowd": false},
	"heraklios": {"sex": "m", "roles": ["soldier"], "cloth": [], "crowd": true},
	# Plain townsfolk in tunics and hose (Leonardo Carvalho's Fuse civilians, CC BY, by way of Sketchfab).
	# Their tunic ("material") and breeches ("Bottom") take a homespun dye each, so no two dress alike.
	"fuse_civilian_1": {"sex": "m", "roles": ["townsfolk"], "cloth": [], "crowd": true, "dyed": ["Object_12", "Object_13"]},
	"fuse_civilian_2": {"sex": "m", "roles": ["townsfolk"], "cloth": [], "crowd": true, "dyed": ["Object_78", "Object_74"]},
	# A townsman in a wool tunic (ChamberSu's Svend, CC BY), his Unreal bones renamed to Mixamo's (tools/ue_to_mixamo.py).
	"svend": {"sex": "m", "roles": ["peasant"], "cloth": [], "crowd": true, "dyed": ["SvendWoolTunicLOD1"]},
	# A peasant in a belted jerkin and boots (EmanuelP's Medieval Man, CC BY), rigged by Mixamo.
	"medieval_man": {"sex": "m", "roles": ["peasant"], "cloth": [], "crowd": true},
	# A mendicant friar in a hooded habit (Götz von Berlichingen's monk, CC BY), rigged by Mixamo.
	"monk": {"sex": "m", "roles": ["clergy"], "cloth": [], "crowd": true},
	# Gowned and veiled. Her gown shares a material with her hands and shoes, so it keeps its own colour.
	# Light enough (19k triangles) for the few gentlewomen about a town's market and sept.
	"noble_lady": {"sex": "f", "roles": ["noble"], "cloth": [], "crowd": true},
}
## Never cast, whatever a list elsewhere says (asset-audit.md's never-use
## list, plain medieval: Mac, 2026-11-10): modern dress, fantasy armour and
## faces, bare chests. Bodies and outfits alike; the one place it's kept.
## Paladin and paladin_prop (dark fantasy plate) and heraklios (a gas-mask
## look) failed the judge's body sheet (v11): soldiers and knights wear the
## knight's mail and surcoat, or the Ranger's hood and leather.
const NEVER := ["erika", "erika_bow", "arissa", "eve", "akai", "ganfaul", "uriel", "dreyar", "brute", "fuse_woman_1", "Female_Ranger",
	"paladin", "paladin_prop", "heraklios"]
## How many people made just before are "beside" the next: the scenes, knots
## and rows that set people down make them one after another, so the last few
## made are the ones they'll stand next to.
const NEIGHBOURS := 4

## How often a crowd figure is a Mixamo character rather than a Quaternius
## outfit, by station. The plain Fuse townsfolk, Svend and the jerkined
## peasant stand in for peasants and townsfolk; most clergy wear the friar's habit; most archers wear a soldier's outfit;
## nobles are all Mixamo. (A Mixamo body is the cheaper of the two: 1-4 draws
## against an outfit's ~9.)
const MIXAMO_SHARE := {"peasant": 0.5, "townsfolk": 0.6, "soldier": 0.0, "archer": 0.0, "noble": 1.0, "knight": 1.0, "clergy": 1.0}
## Each station reads at a glance (the judge's role sheets, review v12): the
## clergy always in the friar's habit, knights in mail and surcoat against the
## plain soldier's hood and leather, peasants in undyed homespun against the
## townsfolk's dyed cloth.
const HOMESPUN := [Color(0.62, 0.55, 0.45), Color(0.55, 0.5, 0.42), Color(0.5, 0.47, 0.42), Color(0.68, 0.62, 0.52), Color(0.45, 0.4, 0.33)]
const DYED := [Color(0.45, 0.5, 0.7), Color(0.66, 0.36, 0.3), Color(0.5, 0.6, 0.4), Color(0.75, 0.62, 0.35), Color(0.86, 0.82, 0.72), Color(0.5, 0.42, 0.55)]


## Stations whose one body is their dress (the friar's habit, the knight's
## surcoat, the lord's or lady's): kept even beside another in it, never swapped
## for an outfit that would make them read as someone else.
const STATION_DRESS := ["clergy", "knight", "noble"]


## The cloth a station wears: homespun for peasants, dyed for the rest (realm/data/people.json
## cloth.homespun, cloth.dyed; these lists if the data has none).
static func cloth_of(role: String) -> Array:
	var key := "homespun" if role == "peasant" else "dyed"
	var d: Array = Data.value("people", "cloth." + key, [])
	return d.map(func(c): return Color(float(c[0]), float(c[1]), float(c[2]))) if not d.is_empty() else (HOMESPUN if role == "peasant" else DYED)


## The town being dressed (town_life and villagers say, before they make its people): its rank and
## its holder's colour. A crowd in a richer town wears more dyed cloth, and some wear the house's.
static var _town_rank := "town"
static var _town_house := Color(0, 0, 0, 0)
static var _town_mourning := false
static func dress_for(rank: String, house: Color, mourning := false) -> void:
	_town_rank = rank
	_town_house = house
	_town_mourning = mourning


## One person's cloth (batch 8 look2: the crowd in dark, colourless clothes; town-b's is warm and
## varied, the holder's colour here and there): the holder's colour by the rank's share, a dyed cloth
## for a peasant by the rank's dyed share, else the station's own (people.json cloth.rank).
static func cloth_pick(role: String, rng: RandomNumberGenerator) -> Color:
	if _town_mourning:
		var dark: Array = Data.value("people", "cloth.mourning", [])
		if not dark.is_empty():
			var d: Array = dark[rng.randi() % dark.size()]
			return Color(float(d[0]), float(d[1]), float(d[2]))  # a town in grief, all in dark wool
	var r: Dictionary = (Data.value("people", "cloth.rank", {}) as Dictionary).get(_town_rank, {})
	if _town_house.a > 0.0 and rng.randf() < float(r.get("house", 0.0)):
		return _town_house.lerp(Color.WHITE, float(Data.num("people", "cloth.house_soften", 0.1)))
	var pal := cloth_of(role)
	if role == "peasant" and rng.randf() < float(r.get("dyed", 0.0)):
		pal = cloth_of("townsfolk")
	return pal[rng.randi() % pal.size()]

const HEAD_ONLY := preload("res://scripts/head_only.gdshader")

const ANIMS := "res://assets/anims/mixamo/"
const HERO_ANIMS := "res://assets/hero/anims/"
## The Universal Animation Library (Quaternius, CC0), retargeted at import
## (assets/retarget/ual_map.tres): sitting, a torch idle, a formal walk, crouch,
## jog. Guns, spells, swimming and root-motion copies stay out: no place here.
const UAL := "res://assets/anims/AnimationLibrary_Godot_Standard.gltf"
const UAL_SKIP := ["A_TPose", "Pistol", "Spell", "Swim", "_RM", "Roll"]
const Motion := preload("res://scripts/motion.gd")
const Data := preload("res://scripts/data.gd")
# Ways a soldier stands ready (all on the shared skeleton), one per man.
const GUARDS := ["Sword_Idle", "Sword_Idle", "SS_Idle_2", "SS_Block_Idle"]

var _lib: AnimationLibrary
var _scenes := {}
var _heights := {}  # Mixamo body -> scale that stands it as tall as an outfit
var _ok := {}  # Mixamo body -> whether it loads with the shared skeleton
var _recent: Array[String] = []  # the looks of the last NEIGHBOURS people made: body, or outfit and cloth


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
	_plant(_lib)


## Every move stands on its feet (Unity Mecanim's "root height based upon feet"):
## the Mixamo legs, retargeted onto our skeletons, reach about 0.13 m lower than
## the hips' keys allow for, so a whole crowd stood ankle-deep in the ground
## (tools/feet_check.gd measures it). Each clip is posed on the reference
## outfit's skeleton, and its hips raised by how far the lowest foot of its
## standing frames falls below where the feet are at rest (soles on y = 0).
## Frames down low don't count (sat or lying: hips under `seated` of their rest
## height; on a knee: a knee under `kneeling` of its rest height); a clip that
## never stands keeps its keys. Crouches and lunges count: their soles are down. Tunables:
## realm/data/people.json feet.*; --feet=off for the old keys.
const LEGS := ["Hips", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"]
static func _plant(lib: AnimationLibrary) -> void:
	if not FEET_ON:
		return
	var ref: Node3D = (load(String(Data.value("people", "feet.reference", "res://assets/people/Male_Peasant.gltf"))) as PackedScene).instantiate()
	var sk: Skeleton3D = ref.find_child("GeneralSkeleton", true, false)
	var hips := sk.find_bone("Hips")
	var ms := maxf(sk.motion_scale, 0.001)
	var seats: Array = Data.value("people", "feet.seats", ["Driving", "Riding"])
	for name in lib.get_animation_list():
		if seats.any(func(k): return String(name).begins_with(String(k))):
			continue  # on a cart's box or a saddle: the seat holds them, not their feet (sat on a bench or the ground, the feet still find the ground)
		var a := lib.get_animation(name)
		var pt := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_POSITION_3D)
		if pt < 0 or a.track_get_key_count(pt) == 0:
			continue
		var lift := maxf(_sole_drop(sk, a), 0.0)
		if lift < 0.005 * ms:
			continue
		for k in a.track_get_key_count(pt):
			a.track_set_key_value(pt, k, (a.track_get_key_value(pt, k) as Vector3) + Vector3(0, lift / ms, 0))
	ref.free()

static var FEET_ON: bool = bool(Data.value("people", "feet.on", true)) and not OS.get_cmdline_user_args().has("--feet=off")


## How far (skeleton units) the lowest foot of a clip's standing frames falls
## below the feet at rest on this skeleton; negative when it stays above. Posed
## by hand down the leg chain (a skeleton outside the tree doesn't pose itself):
## a bone's place is its parent's times its own pose, the clip's where it has a
## key, its rest where not. Capped at feet.mostLift (metres on a 0.95 m hip).
static func _sole_drop(sk: Skeleton3D, a: Animation, down_only := false) -> float:
	var samples := int(Data.num("people", "feet.samples", 12))
	var seated := Data.num("people", "feet.seated", 0.45)
	var kneeling := Data.num("people", "feet.kneeling", 0.4)
	var hips := sk.find_bone("Hips")
	var bones := LEGS.map(func(n): return sk.find_bone(n))
	var feet := ["LeftFoot", "LeftToes", "RightFoot", "RightToes"].map(func(n): return sk.find_bone(n)).filter(func(i): return i >= 0)
	var knees := ["LeftLowerLeg", "RightLowerLeg"].map(func(n): return sk.find_bone(n)).filter(func(i): return i >= 0)
	var ms := maxf(sk.motion_scale, 0.001)
	var where := func(bone: int, pose: Dictionary) -> Transform3D:
		var xf := Transform3D.IDENTITY
		var b := bone
		while b >= 0:
			xf = (pose[b] if pose.has(b) else sk.get_bone_rest(b)) * xf
			b = sk.get_bone_parent(b)
		return xf
	var low := func(pose: Dictionary) -> float:
		var y := INF
		for i in feet:
			y = minf(y, (where.call(i, pose) as Transform3D).origin.y)
		return y
	var rest: float = low.call({})
	var hips_rest: float = (where.call(hips, {}) as Transform3D).origin.y
	var knee_rest: float = (where.call(knees[0], {}) as Transform3D).origin.y if not knees.is_empty() else 0.0
	var path := "%GeneralSkeleton:"
	var pt := a.find_track(NodePath(path + "Hips"), Animation.TYPE_POSITION_3D)
	var rt := LEGS.map(func(n): return a.find_track(NodePath(path + n), Animation.TYPE_ROTATION_3D))
	var lo := INF
	var touch := INF  # down low: the lowest of the knees and the laid-down feet, less what lies between bone and ground
	var knee_r := Data.num("people", "feet.kneeRadius", 0.06) * hips_rest / 0.95
	var instep := Data.num("people", "feet.instep", 0.05) * hips_rest / 0.95
	var seat_r := Data.num("people", "feet.seat", 0.12) * hips_rest / 0.95
	for k in samples + 1:
		var t := a.length * k / samples
		var pose := {}
		for j in bones.size():
			if bones[j] < 0:
				continue
			var r: Transform3D = sk.get_bone_rest(bones[j])
			var q: Quaternion = a.rotation_track_interpolate(rt[j], t) if rt[j] >= 0 else r.basis.get_rotation_quaternion()
			var o: Vector3 = a.position_track_interpolate(pt, t) * ms if bones[j] == hips and pt >= 0 else r.origin
			pose[bones[j]] = Transform3D(Basis(q), o)
		var down: bool = (where.call(hips, pose) as Transform3D).origin.y < hips_rest * seated
		for kn in knees:
			down = down or (where.call(kn, pose) as Transform3D).origin.y < knee_rest * kneeling
		if down:
			for kn in knees:
				touch = minf(touch, (where.call(kn, pose) as Transform3D).origin.y - knee_r)
			touch = minf(touch, low.call(pose) - instep)
			touch = minf(touch, (where.call(hips, pose) as Transform3D).origin.y - seat_r)  # sat back on the heels
			continue  # sat, lying or on a knee: the seat or the knee is on the ground, not the soles
		lo = minf(lo, low.call(pose))
	if lo == INF or down_only:
		# (down_only: only the frames down low are asked about, whatever else the move does.)
		# A move that never stands (kneeling, praying, planting): raised by how far its knee or its
		# laid-down foot goes under the ground, never lowered; sat or lying moves keep their keys.
		return clampf(-touch, 0.0, Data.num("people", "feet.mostLift", 0.25) * hips_rest / 0.95) if touch != INF else 0.0
	var most := Data.num("people", "feet.mostLift", 0.25) * hips_rest / 0.95
	return clampf(rest - lo, -most, most)


## A body's own legs, after the clips are planted on the reference's: its
## stride and stance measured on its skeleton (feet.bodyClips), and the whole
## body raised by what its feet still fall short (Medieval Man's shorter shins
## stood 5-8 cm deep), once per body.
var _body_lift := {}
func _stand_up(body: String, skeleton: Skeleton3D) -> void:
	if not FEET_ON:
		return
	if not _body_lift.has(body):
		var sum := 0.0
		var n := 0
		for c in Data.value("people", "feet.bodyClips", ["Idle", "Walk"]):
			if _lib.has_animation(String(c)):
				sum += _sole_drop(skeleton, _lib.get_animation(String(c)))
				n += 1
		_body_lift[body] = maxf(sum / maxi(n, 1), 0.0)
	skeleton.position += skeleton.transform.basis * Vector3(0, float(_body_lift[body]), 0)


## A body's own knees and seat, in the moves played down low (Motion.LOW and
## feet.lowAlso): the clips are planted on the reference's legs, and a body with
## longer shins or a deeper seat still sank on a knee (tools/feet_check.gd:
## fuse_civilian_1 16 cm, the noble lady 14, the monk 13). Each low move is
## measured on the body's own skeleton, once per body, and what its knee, laid
## foot or seat still goes under the ground is kept on the person (meta
## "low_lift": move -> how far to raise the skeleton); motion.gd eases the body
## up by it while that move plays and back down after. feet.lowExtra adds to a
## body by hand (metres). Root height by the body's own contact points, as
## Unity's humanoid "root transform position (Y): feet" does per avatar.
var _low_lift := {}
func _kneel_up(person: Node3D, body: String, skeleton: Skeleton3D) -> void:
	if not FEET_ON or not bool(Data.value("people", "feet.low", true)):
		return
	if not _low_lift.has(body):
		var lifts := {}
		var hips := skeleton.find_bone("Hips")
		var per_m: float = skeleton.get_bone_global_rest(hips).origin.y / 0.95 if hips >= 0 else 1.0  # skeleton units in a metre (a 0.95 m hip)
		var extra := float((Data.value("people", "feet.lowExtra", {}) as Dictionary).get(body, 0.0)) * per_m
		var clips: Array = Motion.LOW + (Data.value("people", "feet.lowAlso", []) as Array)
		for c in clips:
			if not _lib.has_animation(String(c)):
				continue
			var up := _sole_drop(skeleton, _lib.get_animation(String(c)), true) - float(_body_lift.get(body, 0.0)) + extra
			if up > 0.01 * per_m:
				lifts[String(c)] = up
		# Standing moves whose feet these legs plant deeper than the reference's
		# (feet.bodyMoves: a crouch's heel-up foot sank 10-12 cm on fuse_civilian_1 and
		# Medieval Man): measured on this skeleton's standing frames, raised by the rest.
		for c in Data.value("people", "feet.bodyMoves", []):
			if not _lib.has_animation(String(c)) or lifts.has(String(c)):
				continue
			var up := _sole_drop(skeleton, _lib.get_animation(String(c))) - float(_body_lift.get(body, 0.0))
			if up > 0.01 * per_m:
				lifts[String(c)] = up
		_low_lift[body] = lifts
	var mine := {}
	for c in _low_lift[body]:
		mine[c] = skeleton.transform.basis * Vector3(0, float(_low_lift[body][c]), 0)
	if not mine.is_empty():
		person.set_meta("low_lift", mine)


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
	var share: float = 1.0 if CAST_ON and cast_members().any(func(b): return role in body_info(b)["roles"]) else MIXAMO_SHARE[role]  # the cast plays its roles always
	if (age not in ["child", "elder"] or (role in STATION_DRESS and age != "child")) and (roll < share or look != ""):  # an old friar is still robed, an old knight in his surcoat
		# A named person is known by their body, so only a crowd needs one that shows its colour.
		# A crowd's sex is rolled first, so the mix of bodies on hand doesn't decide it.
		var want := sex if sex != "" or look != "" else ("male" if rng.randf() < 0.5 or role in ["clergy", "knight"] else "female")  # friars and knights (no nun's habit or woman's mail yet)
		var pool := _bodies(role, want, tint != Color.WHITE and look == "", look == "")
		if look == "":
			# Never the twin of whoever they'll stand beside: another body when there is one.
			var fresh := pool.filter(func(b): return not ("body:" + String(b)) in _recent)
			if not fresh.is_empty():
				pool = fresh
			elif not role in STATION_DRESS and not _recent.is_empty() and pool.size() == 1 and ("body:" + String(pool[0])) == _recent[-1]:
				pool = []  # the only body there is would stand beside itself: they wear an outfit this once
		if not pool.is_empty():
			var body: String = pool[(abs(hash(look)) if look != "" else rng.randi()) % pool.size()]
			if look == "":
				_seen("body:" + body)
			return make_body(rng, body, tint, age, build, role)
	# A lady in a crowd, or too young or old for the gowned body, wears the dress in her house's colour.
	var outfit_role := "soldier" if role in SOLDIERLY or (role == "noble" and sex.left(1) != "f") else "peasant"
	var outfits: Array = OUTFITS[outfit_role].filter(func(o): return (sex == "" or o[1] == sex.left(1)) and not o[0] in NEVER)
	if outfits.is_empty():
		outfits = OUTFITS[outfit_role].filter(func(o): return not o[0] in NEVER)
	var pick: Array = outfits[rng.randi() % outfits.size()]
	var person: Node3D = _scene("res://assets/people/%s.gltf" % pick[0]).instantiate()
	var skeleton: Skeleton3D = person.get_node("Armature/GeneralSkeleton")
	var palette := cloth_of(role)
	var cloth: Color = tint if tint != Color.WHITE else cloth_pick(role, rng)
	if tint == Color.WHITE:
		# The same outfit in the same cloth beside them would be a twin: another cloth.
		for tries in palette.size():
			if not ("%s:%s" % [pick[0], cloth.to_html()]) in _recent:
				break
			cloth = palette[(palette.find(cloth) + 1) % palette.size()]
	_seen("%s:%s" % [pick[0], cloth.to_html()])
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


func _seen(look: String) -> void:
	_recent.append(look)
	if _recent.size() > NEIGHBOURS:
		_recent.pop_front()


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
	# The cast (--cast=meshy; realm/data/cast.json): a role the cast covers is played by the cast alone.
	if CAST_ON:
		var cast := cast_members().filter(func(b): return role in body_info(b)["roles"] and _usable(b) and (sex == "" or body_info(b)["sex"] == sex.left(1)))
		if not cast.is_empty():
			return cast
	var pool := BODIES.keys().filter(func(b): return not b in NEVER and role in BODIES[b]["roles"] and (not crowd or BODIES[b]["crowd"]) and (not coloured or not BODIES[b]["cloth"].is_empty()) and _usable(b))
	# Never the other sex: with no body of theirs, they wear an outfit instead.
	return pool.filter(func(b): return sex == "" or BODIES[b]["sex"] == sex.left(1))


## The cast: Meshy characters brought in by tools/cast_import.py (realm/assets/people/mixamo/cast_*), each a body
## like the Mixamo ones, listed with its roles in realm/data/cast.json; with --cast=meshy (or cast.json on) they
## play every role they cover, --cast=kit the bodies and outfits as before (the before shot).
static var CAST_ON: bool = OS.get_cmdline_user_args().has("--cast=meshy") or (bool(Data.value("cast", "on", false)) and not OS.get_cmdline_user_args().has("--cast=kit"))


static func cast_members() -> Array:
	return (Data.value("cast", "members", {}) as Dictionary).keys()


## A body's row: the Mixamo bodies' (BODIES) or a cast member's (cast.json members).
static func body_info(body: String) -> Dictionary:
	if BODIES.has(body):
		return BODIES[body]
	var m: Dictionary = (Data.value("cast", "members", {}) as Dictionary).get(body, {})
	var row := {"sex": String(m.get("sex", "m")), "roles": m.get("roles", []), "cloth": [], "crowd": true, "cast": true, "mask": String(m.get("mask", ""))}
	return row


## Every body there is to dress the crowd in: the Mixamo bodies and, with the cast on, the cast.
static func all_bodies() -> Array:
	return BODIES.keys() + (cast_members() if CAST_ON else [])


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
	var info: Dictionary = body_info(body)
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
	_stand_up(body, skeleton)
	_kneel_up(person, body, skeleton)
	# The moves find the skeleton by its unique name, which needs its owner back.
	skeleton.owner = person
	skeleton.unique_name_in_owner = true
	for mi in skeleton.get_children():
		if mi is MeshInstance3D:
			mi.owner = person
			_solid(mi, nested)
			if tint != Color.WHITE and String(mi.name) in info["cloth"]:
				_tint(mi, tint, role in SOLDIERLY)
			elif String(mi.name) in info.get("dyed", []):
				_tint(mi, cloth_pick(role if role != "" else String(info["roles"][0]), rng))
			elif String(info.get("mask", "")) != "":
				# A cast member's cloth by its mask (cast_import.py): the house's colour or a dye of the town's on
				# the masked cloth only, its skin, leather and steel kept as painted.
				_mask_dye(mi, String(info["mask"]), tint if tint != Color.WHITE else cloth_pick(role if role != "" else String(info["roles"][0]), rng))
	if role == "":
		role = info["roles"][0]
	person.set_meta("body", body)
	return _finish(person, skeleton, rng, role, age, build, "male" if info["sex"] == "m" else "female", _height(body, skeleton, info["sex"]))


## Homespun colours for clothes that come undyed.
## Undyed linen, ochre, madder, woad, walnut, moss, slate and rust: what a town's dyer has.
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
	# Anyone at the lens fades out, dithered, as the trees do (realistic.fade_near):
	# a street-level camera standing beside someone never shows a wall of cloth.
	# The materials are shared, so each is set once for everyone wearing it.
	for mi in person.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for i in m.mesh.get_surface_count():
			var mat := m.get_active_material(i) as BaseMaterial3D
			if mat and mat.distance_fade_mode != BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER:
				Realistic.fade_near(mat, NEAR_GONE, NEAR_SOLID)
	person.add_to_group("people")  # everyone who stands on the ground, for the ground check
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	person.add_child(anim)
	anim.add_animation_library("", _lib)
	anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	# Every move goes through the person's state machine (motion.gd); the player
	# only holds the moves.
	var stance := "Sword_Idle" if role in SWORDED else ("Bow_Idle" if role == "archer" else "Idle")
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
	if role in SWORDED:
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
	preload("res://scripts/presence.gd").fit(person)  # a glance for whoever comes near (presence.gd)
	return person


## Body shape by bone scale: the same models read as stout or thin, child or elder.
## The trunk is never widened (animation-pipeline.md, section 3): the moves
## were made on a slim body, and a stout man's swinging hand went through his
## own belly. Build shows in who they are (outfit, body), not in scaled bones.
func _shape(skeleton: Skeleton3D, _build: String, age: String) -> void:
	if age == "child":
		var head := skeleton.find_bone("Head")
		if head >= 0:
			skeleton.set_bone_pose_scale(head, Vector3.ONE * 1.1)


## Within this of the lens a person is gone, beyond the next fully there: about 0.7 m and 1.5 m.
const NEAR_GONE := 0.08
const NEAR_SOLID := 0.18
const Realistic := preload("res://scripts/realistic.gd")
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
			elif copy.albedo_texture and bool(Data.value("people", "cloth.true", true)):
				# Everyone else's cloth in its true dye too: the weave kept and lifted to a set brightness,
				# its own colour taken out first, then dyed. Multiplied onto the coloured cloth, a dye
				# came out dark and muddy (batch 8 look2).
				copy.albedo_texture = _undyed(copy.albedo_texture, Data.num("people", "cloth.weave", 0.78))
				copy.albedo_color = colour
			_tinted[key] = copy
			mi.set_surface_override_material(s, copy)


static var _undyed_of := {}
static var _masked := {}  # [material, mask, colour] -> the dyed copy, shared by everyone wearing it


## Dyes a body's cloth through a mask (white: the cloth that takes the dye): the material's detail layer, the
## colour on the masked texels only (StandardMaterial3D detail_mask), so no shader of our own.
func _mask_dye(mi: MeshInstance3D, mask_path: String, colour: Color) -> void:
	if not ResourceLoader.exists(mask_path) and not FileAccess.file_exists(mask_path):
		return
	var mask: Texture2D = load(mask_path) if ResourceLoader.exists(mask_path) else ImageTexture.create_from_image(Image.load_from_file(mask_path))
	for s in mi.mesh.get_surface_count():
		var m := mi.get_active_material(s) as StandardMaterial3D
		if m == null:
			continue
		var key := [m, mask_path, colour]
		if not _masked.has(key):
			var copy: StandardMaterial3D = m.duplicate()
			var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
			img.fill(colour)
			copy.detail_enabled = true
			copy.detail_mask = mask
			copy.detail_albedo = ImageTexture.create_from_image(img)
			copy.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
			copy.detail_uv_layer = BaseMaterial3D.DETAIL_UV_1
			_masked[key] = copy
		mi.set_surface_override_material(s, _masked[key])


## A cloth texture with its colour taken out, kept for every soldier that wears it.
## `lift` (0 to keep it as it is): the weave's mean brightness raised or lowered to this, so a dark
## cloth takes a dye as brightly as a pale one.
static func _undyed(tex: Texture2D, lift := 0.0) -> Texture2D:
	var key := [tex, lift]
	if not _undyed_of.has(key):
		var img := tex.get_image()
		if img == null:
			return tex
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_L8)
		img.convert(Image.FORMAT_RGBA8)
		if lift > 0.0:
			# The mean read off a small copy; the lift itself by the engine (Image.adjust_bcs), not per pixel here.
			var small: Image = img.duplicate()
			small.resize(64, 64, Image.INTERPOLATE_BILINEAR)
			var data: PackedByteArray = small.get_data()
			var sum := 0
			for i in range(0, data.size(), 4):
				sum += data[i]
			var mean := float(sum) / maxf(data.size() / 4.0, 1.0) / 255.0
			img.adjust_bcs(clampf(lift / maxf(mean, 0.05), 0.5, 3.0), 1.0, 1.0)
		img.generate_mipmaps()
		_undyed_of[key] = ImageTexture.create_from_image(img)
	return _undyed_of[key]


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
		mo.sync_held()
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
	if person.has_meta("work_pace"):
		speed *= float((person.get_meta("work_pace") as Dictionary).get(anim_name, 1.0))  # a smith hammering faster for the war (town_life _moods)
	if mo and mo.v3 and mo.errand_load != "" and anim_name in IDLES:
		anim_name = mo.errand_load  # v3: someone carrying a load stands holding it (held up mid-errand), arms and all
	elif anim_name == "Idle":
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
	mo.sync_held()  # the move's tool in hand from its first frame
	_started(person, anim_name, speed * float(person.get_meta("tempo")), not preload("res://scripts/motion.gd").is_once(anim_name))
