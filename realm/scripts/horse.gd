extends Node3D
## A horse, and whoever rides it. The horse is abhayexe's "Horse Rigged (Game
## Ready)" (Sketchfab, CC-BY), at its real size: about 1.5 m at the withers.
## Its one long take is sliced at import into Idle, Walk, Leap, Fall and Rear
## (assets/cavalry/horse/scene.gltf.import). The rider is any person from
## people.gd, seated on the horse's back in a Mixamo straddling pose ("Ride_Grasp",
## hands forward on the reins), so they rise and fall with its back.
##   var horse := Horse.new()            # a bay, standing
##   add_child(horse); horse.mount(person)
##   horse.position = ...                # move it; the gait follows the speed
##   horse.dismount()                    # the rider stands beside it
## The take has no trot or gallop, so the walk is played faster as the horse
## goes faster: a walk, a quick walk (trot), and a hard run (gallop).
## horse.fall() and horse.rear() play the take's own.

const S := 0.12  # town scale, as people.gd: metres to world units
const MODEL := "res://assets/cavalry/horse/scene.gltf"
const SEAT := "res://assets/anims/mixamo/Ride_Grasp.fbx"

## Speeds, in world units a second (people walk at 0.17, run at 0.42).
const WALK := 0.2
const TROT := 0.45
const GALLOP := 0.9
## How far the clip's walk carries the horse in one second, played at 1x.
const CLIP_PACE := 1.1 * S

## Coats: the texture is a dark bay; these shift it.
const COATS := [Color(1, 1, 1), Color(1.15, 0.95, 0.8), Color(0.55, 0.5, 0.48), Color(1.35, 1.3, 1.25), Color(1.2, 0.8, 0.6)]

## How far the straddling pose's thighs drop (radians) and its shins come forward.
const THIGH_DROP := 0.7
const SHIN_LIFT := 0.25

static var _seat_lib: AnimationLibrary

var rider: Node3D
var gait := "Idle"  # Idle, Walk, Trot, Gallop, or a one-off: Rear, Fall
var speed := 0.0  # world units a second, measured from how it was moved

var _model: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _saddle: BoneAttachment3D
var _head: int = -1
var _reins: Array[MeshInstance3D] = []
var _last := Vector3.INF
var _one_off := false


func _init(coat := -1) -> void:
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	_model.scale = Vector3.ONE * S
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_anim.animation_finished.connect(func(_n): _one_off = false)
	_head = _bone("Head")
	var tint: Color = COATS[coat if coat >= 0 else randi() % COATS.size()]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).get_active_material(0) as StandardMaterial3D
		if m:
			var copy: StandardMaterial3D = m.duplicate()
			copy.albedo_color = m.albedo_color * tint
			(mi as MeshInstance3D).set_surface_override_material(0, copy)
		(mi as GeometryInstance3D).visibility_range_end = 40.0
	# The seat: on the back behind the withers, where a saddle sits.
	_saddle = BoneAttachment3D.new()
	_saddle.bone_name = _skel.get_bone_name(_bone("Spine1"))
	_skel.add_child(_saddle)
	_play("Idle", 1.0)
	_anim.seek(randf() * 10.0, true)


func _bone(part: String) -> int:
	for i in _skel.get_bone_count():
		if _skel.get_bone_name(i).begins_with("Bip01 " + part + "_"):
			return i
	return -1


## Seats a person on the horse: they take the riding pose and ride with its back.
func mount(person: Node3D) -> void:
	if rider:
		dismount()
	rider = person
	var k := person.scale
	if person.get_parent():
		person.get_parent().remove_child(person)
	_saddle.add_child(person)
	# The attachment carries the horse's scale; the rider keeps their own.
	person.scale = k / S
	person.rotation = Vector3.ZERO
	var anim: AnimationPlayer = person.get_node_or_null("Anim")
	if anim:
		if not anim.has_animation_library("ride"):
			anim.add_animation_library("ride", _seat())
		anim.play("ride/Seat", 0.2)
		anim.speed_scale = 1.0
	_seat_rider()
	for side in [-1.0, 1.0]:
		_reins.append(_rein())
	person.set_meta("mounted", self)


## Sets the rider down on the horse's left, standing. Returns them.
func dismount() -> Node3D:
	var who := rider
	if who == null:
		return null
	rider = null
	var at := global_transform * Vector3(-0.09, 0, 0)
	var k := who.global_transform.basis.get_scale()
	_saddle.remove_child(who)
	get_parent().add_child(who)
	who.global_position = at
	who.rotation = Vector3(0, rotation.y, 0)
	who.scale = k
	who.remove_meta("mounted")
	for r in _reins:
		r.queue_free()
	_reins.clear()
	return who


## The pose's hips (a chair's height off the floor) put on the saddle: in the
## bone's own space, its spine runs back along +Z and up is its own axis.
func _seat_rider() -> void:
	var spine := _skel.get_bone_global_rest(_bone("Spine1"))
	# The rider faces the horse's head (+Z in the model, as people face) and sits upright.
	var basis_in_bone := spine.basis.inverse()
	# Seat: a little behind the withers, on top of the back (model metres).
	var seat := Vector3(0, 1.43, -0.12) - spine.origin
	var seat_in_bone := spine.basis.inverse() * seat
	# The straddling pose's hips sit about 0.5 m above its feet; lift the rider so
	# the hips, not the feet, land on the seat.
	var hips_up: float = 0.52 * rider.scale.y
	rider.transform = Transform3D(basis_in_bone.scaled(rider.scale), seat_in_bone - basis_in_bone * Vector3(0, hips_up, 0))


## The riding pose, shared by every rider: Mixamo's straddling sit, legs apart,
## hands forward and closed as on reins.
static func _seat() -> AnimationLibrary:
	if _seat_lib:
		return _seat_lib
	_seat_lib = AnimationLibrary.new()
	var src: Node = (load(SEAT) as PackedScene).instantiate()
	var player: AnimationPlayer = src.find_children("*", "AnimationPlayer", true, false)[0]
	var a: Animation = player.get_animation(player.get_animation_list()[0]).duplicate(true)
	src.free()
	for t in range(a.get_track_count() - 1, -1, -1):
		if not String(a.track_get_path(t)).contains(":"):
			a.remove_track(t)
	a.loop_mode = Animation.LOOP_LINEAR
	# Off a chair onto a horse: the thighs drop from level to hang round the
	# barrel, and the shins come forward a little, heels under the hips.
	_lower_legs(a, THIGH_DROP, SHIN_LIFT)
	_seat_lib.add_animation("Seat", a)
	return _seat_lib


## Swings each thigh down about the hip (toward straight down) and each shin
## back toward forward, editing the pose's rotation keys. Bones in Godot's
## humanoid skeleton point along their own +Y.
static func _lower_legs(a: Animation, drop: float, lift: float) -> void:
	var hips := a.find_track(NodePath("%GeneralSkeleton:Hips"), Animation.TYPE_ROTATION_3D)
	for side in ["Left", "Right"]:
		var thigh := a.find_track(NodePath("%GeneralSkeleton:" + side + "UpperLeg"), Animation.TYPE_ROTATION_3D)
		var shin := a.find_track(NodePath("%GeneralSkeleton:" + side + "LowerLeg"), Animation.TYPE_ROTATION_3D)
		if hips < 0 or thigh < 0 or shin < 0:
			continue
		for k in a.track_get_key_count(thigh):
			var t := a.track_get_key_time(thigh, k)
			var p: Quaternion = a.rotation_track_interpolate(hips, t)
			var l: Quaternion = a.track_get_key_value(thigh, k)
			var along := (p * l) * Vector3.UP
			var axis := along.cross(Vector3.DOWN)
			if axis.length() < 0.01:
				continue
			var turn := Quaternion(axis.normalized(), drop)
			var l2 := p.inverse() * turn * p * l
			a.track_set_key_value(thigh, k, l2)
			# The shin turns back the other way about the same axis.
			var g := p * l2
			var ks := mini(k, a.track_get_key_count(shin) - 1)
			var s0: Quaternion = a.track_get_key_value(shin, ks)
			a.track_set_key_value(shin, ks, g.inverse() * Quaternion(axis.normalized(), -lift) * g * s0)


func _rein() -> MeshInstance3D:
	var r := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.0012
	m.bottom_radius = 0.0012
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.1, 0.06)
	m.material = mat
	r.mesh = m
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(r)
	return r


## Rears up on its hind legs, once.
func rear() -> void:
	_one_off = true
	_play("Rear", 1.0)


## Goes down, and stays down.
func fall() -> void:
	_one_off = true
	_play("Fall", 1.0)
	set_process(false)


func _play(clip: String, rate: float) -> void:
	if _anim.current_animation != clip:
		_anim.play(clip, 0.3)
	_anim.speed_scale = rate


func _process(delta: float) -> void:
	# How fast it was moved, eased so a jerky path doesn't flicker the gait.
	if _last != Vector3.INF and delta > 0.0:
		var flat := global_position - _last
		flat.y = 0
		speed = lerpf(speed, flat.length() / delta, minf(1.0, delta * 6.0))
	_last = global_position
	if not _one_off:
		if speed < 0.02:
			gait = "Idle"
			_play("Idle", 1.0)
		else:
			gait = "Walk" if speed < (WALK + TROT) * 0.5 else ("Trot" if speed < (TROT + GALLOP) * 0.5 else "Gallop")
			# The stride quickens with the pace, but a longer stride carries a fast
			# horse, so the legs don't spin.
			_play("Walk", clampf(speed / CLIP_PACE, 0.6, 1.0 + speed / CLIP_PACE * 0.35))
	_reins_follow()


## Reins from the bit to the rider's fists, one each side.
func _reins_follow() -> void:
	if rider == null or _reins.is_empty() or _head < 0:
		return
	var skel: Skeleton3D = rider.get_node_or_null("Armature/GeneralSkeleton")
	if skel == null:
		return
	var head := _skel.global_transform * _skel.get_bone_global_pose(_head)
	for i in 2:
		var hand := skel.find_bone("LeftHand" if i == 0 else "RightHand")
		if hand < 0:
			continue
		var a: Vector3 = head * Vector3(0.06 * (1 if i == 0 else -1), -0.14, 0.18)
		var b: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand).origin
		var r := _reins[i]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var up := (b - a) / length
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		r.global_transform = Transform3D(Basis(side, up * length, side.cross(up)), mid)
