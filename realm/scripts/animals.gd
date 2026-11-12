extends RefCounted
## The farm's beasts at ease: each kind lives a small loop of its own moves
## (realm/data/animals.json): a cow stands and grazes, a sheep grazes, a pig
## roots, a chicken pecks, a horse drops its head to the grass. Whoever places
## a beast calls Animals.live(model, kind, rng) once; the beast's own
## AnimationPlayer then plays one move after another (a Timer on the model picks
## the next when one ends: nothing runs per frame).
##
## A kind's moves are its model's own clips where it has them (Quaternius'
## deer has Eating and Idle_Headlow). The Quaternius cow, sheep and pig and our
## war horse have only an idle, so their head-down moves are made from it: the
## neck bones turned down until the head reaches a set share of its height
## (found on the rig itself, whichever way its bones face), with a slow chew or
## a quick peck over it, eased in and out so it joins the idle. This is the
## additive pose-over-idle that engines layer on a base loop (Unreal's additive
## animations, Unity's avatar-mask layers), baked once into a clip.

const Data := preload("res://scripts/data.gd")


## Sets a beast living its idle life. Returns the moves it will play ([] when the
## model has no player or the kind no life in data: it keeps whatever it played).
## `busy`, when given, says the beast is doing something else (a horse walking,
## led or ridden): its life waits and tries again shortly, playing nothing over it.
## A move plays for its picked number of passes, timed by a Timer on the model, so
## no clip's loop mode is changed (the clips are shared with every copy of the model:
## a cavalry horse's idle keeps looping).
static func live(model: Node3D, kind: String, rng: RandomNumberGenerator, busy := Callable()) -> Array:
	var spec: Dictionary = Data.value("animals", "kinds.%s" % kind, {})
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if spec.is_empty() or players.is_empty():
		return []
	var anim: AnimationPlayer = players[0]
	var moves := []  # [clip name in the player, weight, [fewest, most] times in a row]
	for m in spec.get("life", []):
		var clip := _clip(anim, String(m[0]))
		if clip == "" and (spec.get("derive", {}) as Dictionary).has(String(m[0])):
			clip = _derive(model, anim, String(m[0]), spec["derive"][String(m[0])])
		if clip != "":
			anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR  # an idle life loops; the Timer says when it ends
			moves.append([clip, float(m[1]), m[2] if m.size() > 2 else [1, 1]])
	if moves.is_empty():
		return []
	var blend := Data.num("animals", "blend", 0.4)
	var own := RandomNumberGenerator.new()
	own.seed = rng.randi()
	var clock := Timer.new()
	clock.name = "Life"
	clock.one_shot = true
	clock.autostart = true
	var state := {"clip": ""}
	var pick := func() -> Array:  # [clip, passes], never the move just played when there's another
		var pool := moves.filter(func(m): return m[0] != state["clip"]) if moves.size() > 1 and own.randf() < Data.num("animals", "change", 0.7) else moves
		var total := 0.0
		for m in pool:
			total += float(m[1])
		var roll := own.randf() * total
		for m in pool:
			roll -= float(m[1])
			if roll <= 0.0:
				return [m[0], own.randi_range(int(m[2][0]), int(m[2][1]))]
		return [pool[-1][0], 1]
	var next := func() -> void:
		if not is_instance_valid(anim):
			return
		if busy.is_valid() and bool(busy.call()):
			state["clip"] = ""
			clock.start(Data.num("animals", "busyRetry", 2.0))
			return
		var m: Array = pick.call()
		state["clip"] = m[0]
		anim.play(String(m[0]), blend)
		clock.start(maxf(anim.get_animation(String(m[0])).length * int(m[1]) - own.randf() * 0.3, 0.5))
	clock.timeout.connect(next)
	model.add_child(clock)
	var first: Array = pick.call()
	state["clip"] = first[0]
	clock.wait_time = maxf(anim.get_animation(String(first[0])).length * int(first[1]) * own.randf_range(0.2, 1.0), 0.5)  # a herd never moves as one
	if not (busy.is_valid() and bool(busy.call())):
		anim.play(String(first[0]))
		anim.seek(own.randf() * anim.current_animation_length * 0.8, true)
	return moves.map(func(m): return m[0])


## A beast of the farm (the catalogue's cow, sheep, pig: Quaternius, animated), sized to its true
## length (roadside.json animals, metres) and stood on the ground from its posed mesh (roadside.gd
## beast_fit), drawn only near the camera; standing, it lives its idle life (live), walking it plays
## its walk. Whoever moves it says so with walk(beast, true): its idle life waits meanwhile. The one
## place a beast is made (the roadside, a town's yard, the fields and flocks). null with no model.
static var _fits := {}  # kind -> [scale, lift]
static func make(kind: String, rng: RandomNumberGenerator, walking := false) -> Node3D:
	var own := String(Data.value("animals", "kinds.%s.model" % kind, ""))  # a kind the catalogue doesn't hold (a town dog: the wolf, shrunk)
	var path := own if own != "" else preload("res://scripts/realistic.gd").path_of(kind)
	if kind == "" or path == "" or not ResourceLoader.exists(path):
		return null
	if not _fits.has(kind):
		_fits[kind] = load("res://scripts/roadside.gd").beast_fit(kind, Data.num("animals", "kinds.%s.length" % kind, Data.num("roadside", "animals.%s" % kind, 1.5)), own)
	var fit: Array = _fits[kind]
	if float(fit[0]) <= 0.0:
		return null
	var model: Node3D = (load(path) as PackedScene).instantiate()
	var root := Node3D.new()
	root.name = kind.capitalize()
	root.set_meta("beast", kind)
	model.scale = Vector3.ONE * float(fit[0]) * float(Data.num("people", "readable", 1.0))  # drawn larger, as the people are
	model.position.y = float(fit[1])
	model.rotation.y = rng.randf_range(-0.3, 0.3)
	root.add_child(model)
	for g in model.find_children("*", "GeometryInstance3D", true, false):
		(g as GeometryInstance3D).visibility_range_end = Data.num("roadside", "fade.small", 22.0)
	var ap := model.find_children("*", "AnimationPlayer", true, false)
	if ap.is_empty():
		return root
	var anim: AnimationPlayer = ap[0]
	var lived := live(model, kind, rng, func() -> bool: return bool(root.get_meta("walking", false)))
	if walking or lived.is_empty():
		root.set_meta("walking", walking)
		_loop(anim, "Walk" if walking else "Idle", rng)
	preload("res://scripts/anim_lod.gd").add(anim, Data.num("roadside", "fade.small", 22.0))  # moving as far off as it's drawn
	return root


## Sets a beast made by make() walking (its walk, its idle life waiting) or standing again (its
## idle life takes up within animals.json busyRetry seconds).
static func walk(beast: Node3D, on: bool) -> void:
	if beast == null or bool(beast.get_meta("walking", false)) == on:
		return
	beast.set_meta("walking", on)
	var ap := beast.find_children("*", "AnimationPlayer", true, false)
	if on and not ap.is_empty():
		_loop(ap[0], "Walk", null)


static func _loop(anim: AnimationPlayer, want: String, rng: RandomNumberGenerator) -> void:
	var clip := _clip(anim, want)
	if clip == "":
		return
	anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	anim.play(clip, Data.num("animals", "blend", 0.4))
	if rng:
		anim.seek(rng.randf() * 2.0, true)


## The player's clip of this name, however its file prefixes it ("Armature|Idle",
## "AnimalArmature|Eating", "idle"): the name after the last bar, any case. "" if none.
static func _clip(anim: AnimationPlayer, name: String) -> String:
	for c in anim.get_animation_list():
		if String(c).get_slice("|", String(c).get_slice_count("|") - 1).to_lower() == name.to_lower():
			return String(c)
	return ""


## A head-down move made from the kind's idle (see the top): spec is
## {from: the base clip, bones: the neck chain (the head too, to tip the nose down),
## muzzle: how far past the head bone the nose lies (in neck lengths), to: the
## share of its rest height the muzzle comes down to, bob: [degrees, seconds] of chew or peck, ease: seconds
## in and out}. Added to the model's own animation library (shared by every copy
## of the model, so it is made once). Returns its name, or "" if the rig lacks the bones.
static func _derive(model: Node3D, anim: AnimationPlayer, name: String, spec: Dictionary) -> String:
	if anim.has_animation(name):
		return name
	var base := _clip(anim, String(spec.get("from", "Idle")))
	var sk := model.find_children("*", "Skeleton3D", true, false)
	if base == "" or sk.is_empty():
		return ""
	var skel: Skeleton3D = sk[0]
	var chain: Array = (spec.get("bones", ["Neck"]) as Array).map(func(b): return skel.find_bone(String(b))).filter(func(i): return i >= 0)
	var head := skel.find_bone(String(spec.get("head", "Head")))
	if chain.is_empty() or head < 0:
		return ""
	var turn := head_down(skel, chain, head, float(spec.get("to", 0.15)), frame_of(skel, model), float(spec.get("muzzle", 1.0)))
	if turn.is_empty():
		return ""
	var axis: Vector3 = turn[0]
	var down: float = turn[1]
	var src := anim.get_animation(base)
	var clip: Animation = src.duplicate(true)
	clip.loop_mode = Animation.LOOP_LINEAR  # eased in and out to the idle, so it loops on the idle's pose
	var bob: Array = spec.get("bob", [3.0, 1.5])
	var ease_s := float(spec.get("ease", 0.6))
	# The track path of a bone: as the base clip writes its own bone tracks.
	var prefix := ""
	for t in src.get_track_count():
		if src.track_get_type(t) == Animation.TYPE_ROTATION_3D and src.track_get_path(t).get_subname_count() > 0:
			prefix = String(src.track_get_path(t).get_concatenated_names())
			break
	if prefix == "":
		prefix = String(anim.get_node(anim.root_node).get_path_to(skel))
	for bone in chain:
		var path := NodePath("%s:%s" % [prefix, skel.get_bone_name(bone)])
		var was := src.find_track(path, Animation.TYPE_ROTATION_3D)
		var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
		var t := clip.find_track(path, Animation.TYPE_ROTATION_3D)
		if t >= 0:
			clip.remove_track(t)
		t = clip.add_track(Animation.TYPE_ROTATION_3D)
		clip.track_set_path(t, path)
		var steps := maxi(2, int(clip.length / 0.1))
		for k in steps + 1:
			var at := clip.length * k / steps
			var q: Quaternion = src.rotation_track_interpolate(was, at) if was >= 0 else rest
			var inout := smoothstep(0.0, ease_s, at) * smoothstep(0.0, ease_s, clip.length - at)
			var angle := (down + deg_to_rad(float(bob[0])) * sin(TAU * at / maxf(float(bob[1]), 0.05))) * inout / chain.size()
			clip.rotation_track_insert_key(t, at, q * Quaternion(axis, angle))
	var lib := anim.get_animation_library(anim.get_animation_library_list()[0])
	lib.add_animation(name, clip)
	return name


## How to bring a rig's head down to `share` of its rest height above its feet:
## [the bone-local axis the neck chain turns about, the whole angle in radians]
## (split evenly along the chain). Found on the rig's rest pose: the axis that
## lowers the head most, then the angle by halving. [] if no axis lowers it.
static func head_down(skel: Skeleton3D, chain: Array, head: int, share: float, frame := Transform3D.IDENTITY, muzzle := 1.0) -> Array:
	var ground := ground_of(skel, frame)
	var rest_h := head_height(skel, chain, head, Vector3.RIGHT, 0.0, frame, muzzle) - ground
	if rest_h <= 0.0:
		return []
	var best := Vector3.ZERO
	var lowest := rest_h
	for axis in [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]:
		var h := head_height(skel, chain, head, axis, deg_to_rad(40.0), frame, muzzle) - ground
		if h < lowest:
			lowest = h
			best = axis
	if best == Vector3.ZERO:
		return []
	var lo := 0.0
	var hi := deg_to_rad(float(Data.num("animals", "mostTurn", 120.0)))
	for i in 20:
		var mid := (lo + hi) / 2.0
		if head_height(skel, chain, head, best, mid, frame, muzzle) - ground > rest_h * share:
			lo = mid
		else:
			hi = mid
	return [best, (lo + hi) / 2.0]


## Where the skeleton stands in its model (a Quaternius rig's armature is turned
## and scaled a hundredfold: its bones' "up" is not the world's): heights are
## read through this. Walked up the nodes by hand, so it needs no scene tree.
static func frame_of(skel: Skeleton3D, model: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = skel
	while n != null and n != model:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## The rig's lowest bone at rest, in its model: the ground its feet stand on.
static func ground_of(skel: Skeleton3D, frame: Transform3D) -> float:
	var ground := INF
	for i in skel.get_bone_count():
		ground = minf(ground, (frame * skel.get_bone_global_rest(i).origin).y)
	return ground


## The muzzle's height (in its model, through `frame`) with the neck chain
## turned `angle` in all about `axis`, the rest of the rig at rest. The muzzle
## is taken as lying past the head bone, on from the neck's base through it, by
## `muzzle` times that length (the rigs have no bone at the nose). Worked down
## the bone chain by hand, so it needs no scene tree.
static func head_height(skel: Skeleton3D, chain: Array, head: int, axis: Vector3, angle: float, frame := Transform3D.IDENTITY, muzzle := 1.0) -> float:
	var at_rest := skel.get_bone_global_rest(head)
	var nose: Vector3 = at_rest.basis.inverse() * ((at_rest.origin - skel.get_bone_global_rest(chain[0]).origin) * muzzle)  # in the head bone's own space
	var xf := Transform3D.IDENTITY
	var b := head
	while b >= 0:
		var local := skel.get_bone_rest(b)
		if b in chain:
			local.basis = local.basis * Basis(Quaternion(axis, angle / chain.size()))
		xf = local * xf
		b = skel.get_bone_parent(b)
	return (frame * (xf * nose)).y
