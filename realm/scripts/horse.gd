extends Node3D
## A horse, and whoever rides it. The horse is fdoss001's "Horse Rigged All
## Gaits" on Tarnyloo's "Horse" (BlendSwap), exported for the realm with its
## own five loops: idle, walk, trot, canter and gallop
## (assets/cavalry/horse/horse.glb). It stands about 1.5 m at the withers.
## The rider is any person from people.gd, seated on the saddle in a Mixamo
## straddling pose ("Ride_Grasp", hands forward on the reins), so they rise and
## fall with its back. A knight carries a lance: upright at a walk, couched
## forward under the arm once the horse breaks into a canter.
##   var horse := Horse.new()            # a bay, standing
##   add_child(horse); horse.mount(person)
##   horse.bear_lance()                  # a knight's lance in the rider's hand
##   horse.position = ...                # move it; the gait follows the speed
##   horse.dismount()                    # the rider stands beside it

const S := 0.12  # town scale, as people.gd: metres to world units
const SIZE := 1.1  # the export stands 1.38 m at the withers; a warhorse is 1.5
static var MODEL := preload("res://scripts/realistic.gd").path_of("horse")  # by component (realm/data/assets.json)
const SEAT := "res://assets/anims/mixamo/Ride_Grasp.fbx"
static var LANCE := preload("res://scripts/realistic.gd").path_of("lance")

## Speeds, in world units a second (people walk at 0.17, run at 0.42), each
## the pace its loop is made for: the legs keep to the ground at 1x.
const WALK := 0.2
const TROT := 0.42
const CANTER := 0.62
const GALLOP := 0.9
const GAITS := [["idle", 0.0], ["walk", WALK], ["trot", TROT], ["canter", CANTER], ["gallop", GALLOP]]

## Coats: the texture is a bay; these shift it.
const COATS := [Color(1, 1, 1), Color(1.15, 0.95, 0.8), Color(0.55, 0.5, 0.48), Color(1.35, 1.3, 1.25), Color(1.2, 0.8, 0.6)]

## How far the straddling pose's thighs drop (radians) and its shins come forward.
const THIGH_DROP := 0.7
const SHIN_LIFT := 0.25

## Where things sit on the horse, in its skeleton's own space (rest pose):
## the top of the saddle, and the corners of the mouth where the bit is.
const SADDLE := Vector3(0, 1.6, 0.02)
const BIT := Vector3(0.06, 1.88, 1.66)

## The lance: 3.5 m of painted ash, its length along +X in the file; the grip
## is just behind the hand guard, 2.75 units back from the file's origin. The
## file is drawn stout (its vamplate a seventh of its length across), so it is
## scaled along and across apart: 3.5 m long, the vamplate about 17 cm across
## and the shaft at the grip about 6 cm, as a man's hand closes round it.
const LANCE_LONG := 3.5
const LANCE_FILE_LONG := 7.756
const LANCE_GRIP := -2.75
const LANCE_GUARD := 0.17  # metres across the vamplate
const LANCE_FILE_GUARD := 1.073  # the vamplate's width in the file

static var _seat_lib: AnimationLibrary
static var _coats := {}  # coat index -> material
static var _looped := false

var rider: Node3D
var lance: Node3D
var gait := "idle"  # idle, walk, trot, canter, gallop
var speed := 0.0  # world units a second, measured from how it was moved

var _model: Node3D
var _skel: Skeleton3D
var _anim: AnimationPlayer
var _saddle: BoneAttachment3D
var _unit := 1.0  # world units per skeleton unit
var _head: int = -1
var _bits: Array[Vector3] = []  # the bit's two rings, in the head bone's space
var _reins: Array[MeshInstance3D] = []
var _last := Vector3.INF
var _couch := 0.0  # 0 the lance upright, 1 couched
var _down := false
var _rearing := false


func _init(coat := -1) -> void:
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	_model.scale = Vector3.ONE * S * SIZE
	_skel = _model.find_children("*", "Skeleton3D", true, false)[0]
	_anim = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_unit = _model.scale.x * (_skel.get_parent() as Node3D).scale.x
	if not _looped:
		_looped = true
		for g in GAITS:
			_anim.get_animation(g[0]).loop_mode = Animation.LOOP_LINEAR
	preload("res://scripts/anim_lod.gd").add(_anim)  # moved by distance, as people are
	_head = _skel.find_bone("DEF-head")
	var head_rest := _skel.get_bone_global_rest(_head).affine_inverse()
	_bits = [head_rest * BIT, head_rest * (BIT * Vector3(-1, 1, 1))]
	var c: int = coat if coat >= 0 else randi() % COATS.size()
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).set_surface_override_material(0, _coat(c, (mi as MeshInstance3D).get_active_material(0)))
		(mi as GeometryInstance3D).visibility_range_end = 40.0
	# The seat: on the saddle, over the middle of the back.
	_saddle = BoneAttachment3D.new()
	_saddle.bone_name = "DEF-spine.004"
	_skel.add_child(_saddle)
	_anim.play("idle")
	_anim.seek(randf() * 2.0, true)


## One shared material per coat, so a troop of bays draws as one.
static func _coat(c: int, base: Material) -> Material:
	if not _coats.has(c):
		var m := base as StandardMaterial3D
		if m == null:
			return base
		var copy: StandardMaterial3D = m.duplicate()
		copy.albedo_color = m.albedo_color * COATS[c]
		_coats[c] = copy
	return _coats[c]


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
	person.scale = k / _unit
	person.rotation = Vector3.ZERO
	var people = load("res://scripts/people.gd")
	people.add_moves(person, "ride", _seat())
	people.play(person, "ride/Seat", 1.0)
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
	var at := global_transform * Vector3(0.1, 0, 0)
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
	if lance:
		lance.queue_free()
		lance = null
	return who


## A knight's lance in the rider's right hand.
func bear_lance() -> void:
	if lance or rider == null:
		return
	lance = Node3D.new()
	var m: Node3D = (load(LANCE) as PackedScene).instantiate()
	var k := LANCE_LONG / LANCE_FILE_LONG * S
	var w := LANCE_GUARD / LANCE_FILE_GUARD * S
	# Its length turned to point ahead (+Z), the grip at the holder's origin.
	m.transform = Transform3D(Basis(Vector3.UP, -PI / 2) * Basis.from_scale(Vector3(k, w, w)), Vector3(0, 0, -LANCE_GRIP * k))
	lance.add_child(m)
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		(mi as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(mi as GeometryInstance3D).visibility_range_end = 40.0
	add_child(lance)
	if is_inside_tree():
		_lance_follow(0.0)


## The pose's hips put on the saddle: the rider faces the horse's head (+Z in
## the skeleton, as people face) and sits upright, in the spine bone's space.
func _seat_rider() -> void:
	var spine := _skel.get_bone_global_rest(_skel.find_bone(_saddle.bone_name))
	var basis_in_bone := spine.basis.inverse()
	var seat_in_bone := basis_in_bone * (SADDLE - spine.origin)
	# The straddling pose's hips sit about 0.5 m above its feet; lift the rider so
	# the hips, not the feet, land on the seat.
	var hips_up: float = 0.52 * rider.scale.y
	rider.transform = Transform3D(basis_in_bone.scaled(rider.scale), seat_in_bone + basis_in_bone * Vector3(0, -hips_up, 0))


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


## Rears up on its hind legs, once: the whole horse rocks back onto its hocks
## and comes down again (the export has no rearing loop of its own).
func rear() -> void:
	if _down or _rearing:
		return
	_rearing = true
	var tw := create_tween()
	tw.tween_method(func(a: float): _tilt(Vector3.RIGHT, -a, Vector3(0, 0, -0.9)), 0.0, 0.5, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3)
	tw.tween_method(func(a: float): _tilt(Vector3.RIGHT, -a, Vector3(0, 0, -0.9)), 0.5, 0.0, 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _rearing = false)


## Goes down onto its side, and stays down.
func fall() -> void:
	if _down:
		return
	_down = true
	_play("idle", 1.0)
	var tw := create_tween()
	tw.tween_method(func(a: float): _tilt(Vector3.BACK, a, Vector3(-0.3, 0, 0)), 0.0, 1.45, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func(): _anim.pause())


## Turns the model `angle` about `axis` through `pivot` (skeleton units, on the ground).
func _tilt(axis: Vector3, angle: float, pivot: Vector3) -> void:
	var p := pivot * _unit
	var b := Basis(axis, angle)
	_model.transform = Transform3D(b.scaled(Vector3.ONE * S * SIZE), p - b * p)


func _play(clip: String, rate: float) -> void:
	if _anim.current_animation != clip:
		_anim.play(clip, 0.4)
	_anim.speed_scale = rate


func _process(delta: float) -> void:
	# How fast it was moved, eased so a jerky path doesn't flicker the gait.
	if _last != Vector3.INF and delta > 0.0:
		var flat := global_position - _last
		flat.y = 0
		speed = lerpf(speed, flat.length() / delta, minf(1.0, delta * 4.0))
	_last = global_position
	if _down:
		return
	var g := _gait_for(speed)
	gait = String(GAITS[g][0])
	# Each loop is played at the pace it was made for, a little faster or
	# slower to keep the hooves on the ground between gaits.
	var pace: float = GAITS[g][1]
	_play(gait, 1.0 if pace <= 0.0 else clampf(speed / pace, 0.75, 1.3))
	if rider == null or not _seen():
		return
	_couch = move_toward(_couch, 1.0 if g >= 3 else 0.0, delta * 1.5)
	_reins_follow()
	_lance_follow(delta)


## Which gait a speed calls for, held a little past each change so it doesn't
## flicker between two.
func _gait_for(v: float) -> int:
	var now := 0
	for i in GAITS.size():
		if GAITS[i][0] == gait:
			now = i
	if v < 0.03:
		return 0
	var want := 1
	for i in range(2, GAITS.size()):
		if v > (float(GAITS[i - 1][1]) + float(GAITS[i][1])) * 0.5:
			want = i
	if absi(want - now) == 1 and now > 0:
		var edge := (float(GAITS[maxi(want, now) - 1][1]) + float(GAITS[maxi(want, now)][1])) * 0.5
		if absf(v - edge) < 0.03:
			return now
	return want


## Whether anyone could see the rider's hands: on screen and within sight.
func _seen() -> bool:
	if not is_visible_in_tree():
		return false
	var cam := get_viewport().get_camera_3d()
	return cam == null or (cam.global_position.distance_to(global_position) < 40.0 and cam.is_position_in_frustum(global_position))


## The lance in the right fist: carried upright at a walk, tip high, and
## lowered to the couch as the horse canters, aimed ahead across its neck.
func _lance_follow(_delta: float) -> void:
	if lance == null:
		return
	var skel: Skeleton3D = rider.get_node_or_null("Armature/GeneralSkeleton")
	if skel == null:
		return
	var hand := skel.find_bone("RightHand")
	if hand < 0:
		return
	var upright := Quaternion(Vector3.RIGHT, -1.3)
	var couched := Quaternion(Vector3.UP, 0.12) * Quaternion(Vector3.RIGHT, 0.05)
	var turn := Basis(upright.slerp(couched, smoothstep(0.0, 1.0, _couch)))
	lance.global_transform = Transform3D(global_basis.orthonormalized() * turn, skel.global_transform * skel.get_bone_global_pose(hand).origin)


## Reins from the bit to the rider's fists, one each side.
func _reins_follow() -> void:
	if _reins.is_empty() or _head < 0:
		return
	var skel: Skeleton3D = rider.get_node_or_null("Armature/GeneralSkeleton")
	if skel == null:
		return
	var head := _skel.global_transform * _skel.get_bone_global_pose(_head)
	for i in 2:
		var hand := skel.find_bone("LeftHand" if i == 0 else "RightHand")
		if hand < 0:
			continue
		var a: Vector3 = head * _bits[i]
		var b: Vector3 = skel.global_transform * skel.get_bone_global_pose(hand).origin
		var r := _reins[i]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b)
		if length < 0.001:
			continue
		var up := (b - a) / length
		var side := up.cross(Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		r.global_transform = Transform3D(Basis(side, up * length, side.cross(up)), mid)
