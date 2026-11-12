extends Node3D
## A wall built of stones (Mac: "the walls need to actually be built of stones
## stacked together. Then the stones break, the stones fall."). Dressed blocks
## laid in courses with staggered joints, crenellated on top, each face showing
## one painted block of the Medieval Village kit's rock trim (Quaternius). Standing,
## the whole wall is one MultiMesh draw. Struck, the stones near the blow come
## loose as rigid bodies in Godot's built-in Jolt physics, tumble and fall in a
## cloud of dust (Kenney particles); the stones above an opened gap lose their
## footing and slump after them, and the rubble settles and stays where it lies.
## Blows widen the gap into a breach whose foot is open ground.
##
## The fall runs in the wall's own physics space in metres (the realm draws 0.12
## units a metre, too small for stable stacking), and only while the wall is hot,
## near the camera: a cold wall jumps straight to where its stones would lie.
## A town's damage (bridge damage.js, one owner) is turned into the same breach
## every time from its wear (wear_to), so a reload shows the same gap.
## Its parent stands at the world's origin (positions are world positions).
## The API is in the notes, stone-wall-api.md; tunables in data/walls.json.
##
## No block exists for "a wall of stacked stones that falls stone by stone" in
## Godot (godot-destruction fractures one mesh into shards); this file is the
## glue between the kit's stone, Jolt and MultiMesh.

const Data := preload("res://scripts/data.gd")
const S := 0.12  # world units a metre (towns.gd S)
const KIT := "res://assets/village/T_RockTrim_%s.png"
const DUST := "res://assets/fx/fire/smoke_0%d.png"

## The wall's foot opened or closed somewhere: a breach troops can walk through.
signal opened

enum { WHOLE, LOOSE, RUBBLE }

var sections := 1
var outer := 1.0  # +1: the outer face (merlons, the side blows come from) is the right of each run's direction
var height_m := 6.0
var ground: Callable  # (world Vector3) -> world y
var shown := PackedFloat32Array()  # each section's wear as drawn (0 whole .. 1 gone)
var hot := false  # near the camera: blows fall as bodies, not jumps

var _xf: Array[Transform3D] = []  # each stone as laid, in metres (a unit box scaled to it)
var _size := PackedVector3Array()
var _s0 := PackedFloat32Array()  # its span along the wall, metres
var _s1 := PackedFloat32Array()
var _yb := PackedFloat32Array()  # its bottom
var _course := PackedInt32Array()
var _section := PackedInt32Array()
var _state := PackedByteArray()
var _founded := PackedByteArray()  # 1: it stands on the ground itself
var _shade: Array[Color] = []
var _courses := {}  # course -> Array of its stones
var _chords: Array[Dictionary] = []  # {a, dir, n, len, s0}
var _length := 0.0
var _gaps: Array[Vector2] = []  # stretches left open (metres along it): a town gate's way through (walls.gd)
var _gy := PackedFloat32Array()  # the ground's height every half metre along the wall
var _top := 0.0  # the wall walk's height (merlons stand on it)
var _thick := 1.8
var _shrink := 0.975

var _whole: MultiMeshInstance3D
var _loose: MultiMeshInstance3D
var _metres: Node3D
var _rng := RandomNumberGenerator.new()

var _space := RID()
var _bodies := {}  # stone -> [body, shape] while it falls
var _since := {}  # stone -> seconds falling
var _stays := {}  # stone -> [body, shape]: a standing or settled stone the falling ones strike
var _patches := {}  # ground patch key -> [body, shape]
var _quiet := 0.0
var _check := 0.0  # seconds since the stones over a gap were last checked
var _pending := {}  # section -> {stone: true}: stones the town's wear has doomed, not yet struck down
var _heap := {}  # rubble cell -> its top, metres: where jumped stones pile
var _rubble_grid := {}  # half-metre cell -> the rubble's top there, metres (rubble_height)
var _rubble_at_ms := -100000

static var _material: ShaderMaterial
static var _box: ArrayMesh
static var _dust_mat: StandardMaterial3D


## A straight wall from `from` to `to` (world, on the ground), `height_m` metres to
## its wall walk, in `colour` (multiplied over the stone; white keeps the kit's).
## opts: sections (how many damage sections along it), outer (+1/-1: which face
## takes the blows and wears the merlons; +1 is the right of from->to), ground
## (Callable world Vector3 -> y; default: the line between the ends), seed.
## Returns the wall, not yet in the tree: add it anywhere (it places itself).
static func build(from: Vector3, to: Vector3, height := 6.0, colour := Color.WHITE, opts := {}) -> Node3D:
	return build_along(PackedVector3Array([from, to]), height, colour, opts)


## The same along a line of points (a town's ring: close it by repeating the first).
static func build_along(points: PackedVector3Array, height := 6.0, colour := Color.WHITE, opts := {}) -> Node3D:
	var w: Node3D = (load("res://scripts/stone_wall.gd") as GDScript).new()
	w.name = "StoneWall"
	w.call("_lay", points, height, colour, opts)
	return w


# --- laying ------------------------------------------------------------------

func _lay(points: PackedVector3Array, height: float, colour: Color, opts: Dictionary) -> void:
	height_m = height
	sections = maxi(1, int(opts.get("sections", 1)))
	outer = signf(float(opts.get("outer", 1.0)))
	_rng.seed = int(opts.get("seed", hash(points[0])))
	var line := points
	ground = opts.get("ground", func(p: Vector3) -> float: return _line_y(line, p))
	shown.resize(sections)
	position = points[0]
	_metres = Node3D.new()
	_metres.name = "Stones"
	_metres.scale = Vector3.ONE * S
	add_child(_metres)
	var b: Dictionary = Data.value("walls", "block", {})
	var course_m: Array = b.get("course_m", [0.62, 0.82])
	var len_m: Array = b.get("length_m", [0.95, 1.65])
	_thick = float(b.get("thick_m", 1.8))
	_shrink = float(b.get("shrink", 0.975))
	var min_joint := float(b.get("min_joint_m", 0.28))
	var jit_r := deg_to_rad(float(b.get("jitter_deg", 1.4)))
	var jit_m := float(b.get("jitter_m", 0.03))
	var tint := Color.from_string(String(b.get("tint", "#d9d6d0")), Color(0.85, 0.84, 0.82)) * colour
	var spread := float(b.get("tint_spread", 0.1))
	# The runs, in metres from the first point.
	for i in points.size() - 1:
		var a := (points[i] - points[0]) / S
		var e := (points[i + 1] - points[0]) / S
		var d := Vector3(e.x - a.x, 0, e.z - a.z)
		if d.length() < 0.1:
			continue
		var dir := d.normalized()
		_chords.append({"a": Vector3(a.x, 0, a.z), "dir": dir, "n": Vector3(dir.z, 0, -dir.x) * outer, "len": d.length(), "s0": _length})
		_length += d.length()
	if _chords.is_empty():
		return
	# Gaps: opts gaps (world points on the line) each gap_m metres either side left unlaid, a gate's way through.
	for g in opts.get("gaps", []):
		var s := along(g)
		var hw := float(opts.get("gap_m", 7.0))
		_gaps.append(Vector2(s - hw, s + hw))
	# The ground under it, every half metre.
	var lo := INF
	var hi := -INF
	for k in int(ceil(_length / 0.5)) + 1:
		var y: float = (float(ground.call(_world_at(minf(k * 0.5, _length)))) - points[0].y) / S
		_gy.append(y)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	_top = hi + height_m
	# Courses from below the lowest ground to the wall walk, joints staggered.
	var y := lo - 0.5
	var c := 0
	var last_joints := PackedFloat32Array()
	while y < _top - 0.2:
		var h := _rng.randf_range(float(course_m[0]), float(course_m[1]))
		if _top - (y + h) < 0.35:
			h = _top - y
		var joints := PackedFloat32Array()
		for ch in _chords:
			var x := 0.0
			var L: float = ch["len"]
			while x < L - 0.05:
				var l := _rng.randf_range(float(len_m[0]), float(len_m[1]))
				for tries in 5:
					var j: float = ch["s0"] + x + l
					var near := false
					for pj in last_joints:
						if absf(pj - j) < min_joint:
							near = true
							break
					if not near:
						break
					l = _rng.randf_range(float(len_m[0]), float(len_m[1]))
				if L - (x + l) < 0.5:
					l = L - x
				_add(ch, x, l, y, h, _thick, 0.0, c, jit_r, jit_m, tint, spread)
				x += l
				joints.append(ch["s0"] + x)
		last_joints = joints
		y += h
		c += 1
	# Merlons on the outer edge of the wall walk, two courses high.
	if opts.get("merlons", true):
		var m: Dictionary = Data.value("walls", "merlon", {})
		var mw := float(m.get("w_m", 1.15))
		var gap := float(m.get("gap_m", 0.75))
		var depth := float(m.get("depth_m", 0.75))
		for k in int(m.get("courses", 2)):
			var mh := (float(course_m[0]) + float(course_m[1])) * 0.5
			for ch in _chords:
				var x := gap * 0.5
				while x + mw <= float(ch["len"]):
					_add(ch, x, mw, _top + k * mh, mh, depth, _thick * 0.5 - depth * 0.5, c, jit_r, jit_m, tint, spread)
					x += mw + gap
			c += 1
	_draw()


## One stone of a run: x, l along it, y, h up, `deep` through the wall, `off` toward the outer face.
func _add(ch: Dictionary, x: float, l: float, y: float, h: float, deep: float, off: float, c: int, jit_r: float, jit_m: float, tint: Color, spread: float) -> void:
	var s0: float = ch["s0"] + x
	var s1 := s0 + l
	for gap in _gaps:
		if (s0 + s1) * 0.5 > gap.x and (s0 + s1) * 0.5 < gap.y:
			return  # a gate's way through
	var g_lo := INF
	var g_hi := -INF
	for k in range(int(s0 / 0.5), int(ceil(s1 / 0.5)) + 1):
		var gy: float = _gy[clampi(k, 0, _gy.size() - 1)]
		g_lo = minf(g_lo, gy)
		g_hi = maxf(g_hi, gy)
	if y + h < g_lo - 0.05:
		return  # buried: the foundation nobody sees
	var dir: Vector3 = ch["dir"]
	var n: Vector3 = ch["n"]
	var size := Vector3(l, h, deep)
	var basis := Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).rotated(dir, _rng.randf_range(-jit_r, jit_r)).rotated(Vector3.UP, _rng.randf_range(-jit_r, jit_r))
	var o: Vector3 = ch["a"] + dir * (x + l * 0.5) + Vector3.UP * (y + h * 0.5) + n * (off + _rng.randf_range(-jit_m, jit_m))
	var i := _xf.size()
	_xf.append(Transform3D(basis, o))
	_size.append(size)
	_s0.append(s0)
	_s1.append(s1)
	_yb.append(y)
	_course.append(c)
	_section.append(clampi(int((s0 + s1) * 0.5 / maxf(_length, 0.01) * sections), 0, sections - 1))
	_state.append(WHOLE)
	_founded.append(1 if y <= g_hi + 0.02 else 0)
	var v := 1.0 + _rng.randf_range(-spread, spread)
	_shade.append(Color(tint.r * v, tint.g * v, tint.b * (v + _rng.randf_range(-0.03, 0.03))))
	if not _courses.has(c):
		_courses[c] = []
	(_courses[c] as Array).append(i)


func _draw() -> void:
	var bricks: Array = Data.value("walls", "bricks", [[0, 0, 1, 1]])
	var of := float(Data.num("walls", "bricks_of", 1.0))
	var n := _xf.size()
	var box := AABB(Vector3.ZERO, Vector3.ZERO)
	for i in n:
		box = box.expand(_xf[i].origin)
	box = box.grow(25.0)
	for which in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = _block()
		mm.instance_count = n
		mm.custom_aabb = box
		for i in n:
			var r: Array = bricks[_rng.randi() % bricks.size()] if which == 0 else [0, 0, 0, 0]
			mm.set_instance_transform(i, _laid(i) if which == 0 else _hidden())
			mm.set_instance_color(i, _shade[i])
			if which == 0:
				mm.set_instance_custom_data(i, Color(float(r[0]) / of, float(r[1]) / of, (float(r[2]) - float(r[0])) / of, (float(r[3]) - float(r[1])) / of))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Standing" if which == 0 else "Fallen"
		mmi.multimesh = mm
		mmi.material_override = _stone()
		_metres.add_child(mmi)
		if which == 0:
			_whole = mmi
		else:
			_loose = mmi
	# A stone keeps its painted face when it falls.
	for i in n:
		_loose.multimesh.set_instance_custom_data(i, _whole.multimesh.get_instance_custom_data(i))


func _laid(i: int) -> Transform3D:
	return Transform3D(_xf[i].basis * Basis.from_scale(_size[i] * _shrink), _xf[i].origin)


func _hidden() -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)


## The kit's rock trim on every face of a stone (stone_block.gdshader).
static func _stone() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://scripts/stone_block.gdshader")
		_material.set_shader_parameter("albedo_tex", load(KIT % "BaseColor"))
		_material.set_shader_parameter("normal_tex", load(KIT % "Normal"))
		_material.set_shader_parameter("orm_tex", load(KIT % "ORM"))
	return _material


## A unit box whose every face maps the whole of 0..1 (one painted block each).
static func _block() -> ArrayMesh:
	if _box:
		return _box
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := [
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, -1, 0)], [Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, -1, 0)],
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, -1, 0)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)]]
	for f in faces:
		var nn: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var corner := func(cu: float, cv: float) -> void:
			st.set_normal(nn)
			st.set_uv(Vector2(cu, cv))
			st.add_vertex(nn * 0.5 + u * (cu - 0.5) + v * (cv - 0.5))
		for q in [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]]:
			corner.call(float(q[0]), float(q[1]))
	st.generate_tangents()
	_box = st.commit()
	return _box


## The line between the ends' heights, under a wall built without a ground.
static func _line_y(line: PackedVector3Array, p: Vector3) -> float:
	var best := line[0].y
	var bd := INF
	for q in line:
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = q.y
	return best


# --- where things are --------------------------------------------------------

## The run under a distance along the wall, and how far along it.
func _chord_at(s: float) -> Dictionary:
	for ch in _chords:
		if s <= float(ch["s0"]) + float(ch["len"]) + 0.001:
			return ch
	return _chords.back()


## A point at `s` along the wall, `out` metres toward the outer face, `y` up (metres, local).
func _local_at(s: float, out := 0.0, y := 0.0) -> Vector3:
	var ch := _chord_at(s)
	return ch["a"] + ch["dir"] * (s - float(ch["s0"])) + ch["n"] * out + Vector3.UP * y


func _world_at(s: float, out := 0.0, y := 0.0) -> Vector3:
	return position + _local_at(s, out, y) * S


func _to_local(world: Vector3) -> Vector3:
	return (world - position) / S


func _ground_at(s: float) -> float:
	return _gy[clampi(int(round(s / 0.5)), 0, _gy.size() - 1)]


## How far along the wall a world point lies (nearest run), metres.
func along(world: Vector3) -> float:
	var p := _to_local(world)
	var best := 0.0
	var bd := INF
	for ch in _chords:
		var k := clampf((p - ch["a"]).dot(ch["dir"]), 0.0, float(ch["len"]))
		var q: Vector3 = ch["a"] + ch["dir"] * k
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < bd:
			bd = d
			best = float(ch["s0"]) + k
	return best


## How far a world point stands from the wall's line, in world units.
func distance_to(world: Vector3) -> float:
	var s := along(world)
	var q := _world_at(s)
	return Vector2(q.x - world.x, q.z - world.z).length()


## The middle of a section, on the outer face at half height (world).
func section_point(section: int) -> Vector3:
	var s := (section + 0.5) * _length / sections
	return _world_at(s, _thick * 0.5, _ground_at(s) + height_m * 0.5)


func section_of(world: Vector3) -> int:
	return clampi(int(along(world) / maxf(_length, 0.01) * sections), 0, sections - 1)


## Still bodies falling or stones the town's wear has doomed.
func busy() -> bool:
	return not _bodies.is_empty() or _pending.values().any(func(d): return not (d as Dictionary).is_empty())


# --- blows -------------------------------------------------------------------

## A blow at `world_pos` (world): stones within `radius_m` metres come loose,
## pushed `force` m/s away from it (and along `along`, the stone's flight, if
## given); stones above that lose their footing follow. `only`: stones that may
## fall (the town's wear decides; empty: any). Returns how many came loose.
func hit(world_pos: Vector3, force := 7.0, radius_m := 1.5, along_dir := Vector3.ZERO, only := {}) -> int:
	var p := _to_local(world_pos)
	var loose := 0
	var fly := along_dir.normalized()
	for i in _xf.size():
		if _state[i] != WHOLE or _footing(i) or (not only.is_empty() and not only.has(i)):
			continue
		var c := _xf[i].origin
		var d := c.distance_to(p)
		if d > radius_m + _size[i].x * 0.4:
			if d < radius_m * 2.0 and only.is_empty():
				_crack(i, 0.85)
			continue
		# Driven through the wall along the stone's flight (or straight in from the
		# outer face), enough to carry a stone off the course it sat on.
		var k := clampf(1.0 - d / (radius_m + 1.0), 0.55, 1.0)
		var into := Vector3(fly.x, 0, fly.z).normalized() if Vector2(fly.x, fly.z).length() > 0.1 else -_normal(i)
		var push := (into + (c - p).normalized() * 0.4 + Vector3.UP * 0.15).normalized() * force * k
		_loosen(i, push)
		loose += 1
	if not hot:
		_support(false)
	dust(world_pos, 1.0)
	if loose > 0:
		var foot := _world_at(along(world_pos), 0.0, _ground_at(along(world_pos)))
		get_tree().create_timer(0.7).timeout.connect(func(): if is_inside_tree(): dust(foot, 1.6))
		opened.emit()
	return loose


## The wear of a section (the town's damage fact, 0..1) drawn: the same stones
## gone every time for the same wear. Animated (hot), the doomed stones wait for
## blows (strike); otherwise they lie in rubble at once. Less wear mends it.
func wear_to(section: int, wear: float, animate := false) -> void:
	section = clampi(section, 0, sections - 1)
	if wear < shown[section] - 0.01:
		_mend(section)
	shown[section] = wear
	var doomed := _breach(section, wear)
	var left := {}
	for i in doomed:
		if _state[i] == WHOLE:
			left[i] = true
	_cracks(section, wear)
	if animate and hot:
		_pending[section] = left
		return
	_pending.erase(section)
	for i in left:
		_loosen(i, Vector3.ZERO, false)
	_support(false)
	opened.emit()


## A stone thrown at the wall lands at `world_pos`: it brings down the doomed
## stones near it (or, with `any`, whatever it strikes). Returns how many fell.
func strike(world_pos: Vector3, along_dir := Vector3.ZERO, any := false) -> int:
	var section := section_of(world_pos)
	var only: Dictionary = _pending.get(section, {})
	if only.is_empty() and not any:
		dust(world_pos, 0.7)  # it glances off
		return 0
	var r := float(Data.num("walls", "strike.radius_m", 1.5))
	var n := hit(world_pos, float(Data.num("walls", "strike.force", 7.0)), r, along_dir, only)
	for i in only.keys():
		if _state[i] != WHOLE:
			only.erase(i)
	return n


## Where the next blow should land to bring the doomed stones down: the highest
## of them nearest the breach's middle, on the outer face (world), or INF.
func aim(section := -1) -> Vector3:
	var best := -1
	for sec in _pending:
		if section >= 0 and sec != section:
			continue
		for i in _pending[sec]:
			if _state[i] != WHOLE:
				continue
			if best < 0 or _xf[i].origin.y > _xf[best].origin.y + 0.3:
				best = i
	if best < 0:
		return Vector3.INF
	var s := (_s0[best] + _s1[best]) * 0.5
	return _world_at(s, _thick * 0.5, _xf[best].origin.y)


## The rest of the doomed stones fall now (no more blows are coming).
func give_way() -> void:
	for sec in _pending.keys():
		for i in _pending[sec]:
			var side := -1.0 if _rng.randf() < 0.6 else 1.0
			_loosen(i, _normal(i) * side * _rng.randf_range(2.5, 4.5) + Vector3.UP * 0.5, hot)
		_pending.erase(sec)
	if not hot:
		_support(false)
	opened.emit()


## The stones a section's wear brings down: a notch at the section's breach
## point, deep with the wear (to the ground at breach.full_at), wider at the top,
## ragged at its edges. Pure: the same wear, the same stones. The four looks
## (docs/research/world-and-siege-rules.md, wall rule 8; Total War, Stronghold):
## whole; cracked from stages.crack (the crack band, battlements chipped: only
## the merlons over the wall walk come down); crumbling from stages.crumble (the
## top courses go, deeper with each blow); breached at breach.full_at (open to
## the ground, a rubble ramp at its foot).
func _breach(section: int, wear: float) -> Array:
	var out := []
	var stages: Dictionary = Data.value("walls", "stages", {})
	if wear <= float(stages.get("crack", 0.12)):
		return out
	var b: Dictionary = Data.value("walls", "breach", {})
	var sec_len := _length / sections
	var sc := (section + 0.5) * sec_len + (_h01(section * 7 + 1) - 0.5) * sec_len * 0.3
	var crumble := float(stages.get("crumble", 0.0))
	var depth := clampf((wear - crumble) / maxf(float(b.get("full_at", 0.75)) - crumble, 0.01), 0.0, 1.0)
	var hw_top := minf(lerpf(float(b.get("hw_min_m", 0.9)), float(b.get("hw_max_m", 3.4)), clampf((wear - 0.15) / 0.85, 0.0, 1.0)), sec_len * 0.45)
	var hw_bot := hw_top * float(b.get("bottom_share", 0.45))
	var g := _ground_at(sc)
	var crown := _top + 1.6
	var floor_y := g + (_top - g) * (1.0 - depth) if depth < 1.0 else g - 1.0
	var ragged := float(b.get("ragged_m", 0.45))
	for i in _xf.size():
		var mid := (_s0[i] + _s1[i]) * 0.5
		if absf(mid - sc) > hw_top + ragged + 1.0 or _footing(i):
			continue
		var yc := _xf[i].origin.y
		if yc < floor_y:
			continue
		var k := clampf((yc - floor_y) / maxf(crown - floor_y, 0.1), 0.0, 1.0)
		var hw := lerpf(hw_bot, hw_top, k) + (_h01(i * 31 + section) - 0.5) * ragged * 2.0
		if absf(mid - sc) < hw:
			out.append(i)
	return out


## Cracked stones round a section's breach: darker, a little out of true.
func _cracks(section: int, wear: float) -> void:
	if wear < float(Data.num("walls", "stages.crack", 0.2)):
		return
	var b: Dictionary = Data.value("walls", "breach", {})
	var band := float(b.get("crack_band_m", 1.4))
	var dark := float(b.get("crack_dark", 0.7))
	var sec_len := _length / sections
	var sc := (section + 0.5) * sec_len + (_h01(section * 7 + 1) - 0.5) * sec_len * 0.3
	var reach := lerpf(float(b.get("hw_min_m", 0.9)), float(b.get("hw_max_m", 3.4)), clampf((wear - 0.15) / 0.85, 0.0, 1.0)) + band
	for i in _xf.size():
		if _state[i] == WHOLE and absf((_s0[i] + _s1[i]) * 0.5 - sc) < reach and _h01(i * 13 + 5) < 0.55:
			_crack(i, lerpf(1.0, dark, _h01(i * 17)))


func _crack(i: int, by: float) -> void:
	_whole.multimesh.set_instance_color(i, _shade[i] * Color(by, by, by))
	_loose.multimesh.set_instance_color(i, _shade[i] * Color(by, by, by))


## A section built back up (the siege lifted and the town mended it).
func _mend(section: int) -> void:
	for i in _xf.size():
		if _section[i] != section or _state[i] == WHOLE:
			continue
		if _bodies.has(i):
			_free_pair(_bodies[i])
			_bodies.erase(i)
		if _stays.has(i):
			_free_pair(_stays[i])
			_stays.erase(i)
		_state[i] = WHOLE
		_whole.multimesh.set_instance_transform(i, _laid(i))
		_whole.multimesh.set_instance_color(i, _shade[i])
		_loose.multimesh.set_instance_transform(i, _hidden())
	_heap.clear()
	_pending.erase(section)
	opened.emit()


## Stones whose course below no longer carries them fall too, course by course upward.
func _support(physical := true) -> void:
	var b_min := float(Data.num("walls", "fall.support_min", 0.34))
	var keys := _courses.keys()
	keys.sort()
	for c in keys:
		if not _courses.has(c - 1):
			continue
		var below: Array = _courses[c - 1]
		for i in _courses[c]:
			if _state[i] != WHOLE or _founded[i] == 1:
				continue
			var covered := 0.0
			for j in below:
				if _state[j] == WHOLE:
					covered += maxf(0.0, minf(_s1[i], _s1[j]) - maxf(_s0[i], _s0[j]))
			if covered / maxf(_s1[i] - _s0[i], 0.01) < b_min:
				_loosen(i, Vector3(_rng.randf_range(-0.4, 0.4), 0, _rng.randf_range(-0.4, 0.4)), physical and hot)


## Stones over a gap, while the fall runs: a stone is carried by the stones of
## the course below that stand, or lie still where they were laid; once those
## have moved away it slumps after them (checked a few times a second).
func _support_live() -> void:
	var b_min := float(Data.num("walls", "fall.support_min", 0.34))
	var keys := _courses.keys()
	keys.sort()
	var moved := {}
	for c in keys:
		if not _courses.has(c - 1):
			continue
		var below: Array = _courses[c - 1]
		for i in _courses[c]:
			if _state[i] != WHOLE or _founded[i] == 1:
				continue
			var covered := 0.0
			var any := false
			for j in below:
				var o := minf(_s1[i], _s1[j]) - maxf(_s0[i], _s0[j])
				if o <= 0.0:
					continue
				if _state[j] != WHOLE:
					any = true
					if not moved.has(j):
						var pair: Array = _bodies.get(j, _stays.get(j, []))
						var at: Vector3 = PhysicsServer3D.body_get_state(pair[0], PhysicsServer3D.BODY_STATE_TRANSFORM).origin if not pair.is_empty() else Vector3.INF
						moved[j] = at.distance_to(_xf[j].origin) > 0.3
					if moved[j]:
						continue
				covered += o
			if any and covered / maxf(_s1[i] - _s0[i], 0.01) < b_min:
				var side := -1.0 if _rng.randf() < 0.5 else 1.0
				_loosen(i, _normal(i) * side * _rng.randf_range(0.4, 1.4), true)


## The outer face's direction at a stone (metres frame).
func _normal(i: int) -> Vector3:
	return _chord_at((_s0[i] + _s1[i]) * 0.5)["n"]


## A foundation stone, set into the ground: it stays (a breach is open down to it).
func _footing(i: int) -> bool:
	return _yb[i] < _ground_at((_s0[i] + _s1[i]) * 0.5) - 0.05


## A stone comes out of the wall: a body that falls (hot), or straight to the rubble.
func _loosen(i: int, push: Vector3, physical := true) -> void:
	if _state[i] != WHOLE:
		return
	_whole.multimesh.set_instance_transform(i, _hidden())
	if not (physical and hot and is_inside_tree()):
		_state[i] = RUBBLE
		_loose.multimesh.set_instance_transform(i, _rubble_at(i))
		return
	_state[i] = LOOSE
	_warm(_xf[i].origin)
	if _stays.has(i):
		_free_pair(_stays[i])
		_stays.erase(i)
	var f: Dictionary = Data.value("walls", "fall", {})
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_RIGID)
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, _size[i] * _shrink * 0.46)  # a hair small: a stone never starts wedged in its neighbours
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_MASS, _size[i].x * _size[i].y * _size[i].z * float(f.get("density_t", 2.4)))
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, float(f.get("friction", 0.9)))
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_BOUNCE, float(f.get("bounce", 0.05)))
	PhysicsServer3D.body_set_space(body, _space)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, _xf[i].orthonormalized())
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, push)
	var spin := float(f.get("spin", 1.2)) * clampf(push.length() / 4.0, 0.15, 1.5)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * spin)
	_bodies[i] = [body, shape]
	_since[i] = 0.0
	_loose.multimesh.set_instance_transform(i, _laid(i))
	# The stones round it stand in its way as it falls.
	for j in _xf.size():
		if _state[j] == WHOLE and not _stays.has(j) and _xf[j].origin.distance_to(_xf[i].origin) < 3.0:
			_stays[j] = _static_box(_xf[j].orthonormalized(), _size[j] * _shrink * 0.46)


## Where a stone lies once it has come down without a fall to watch: heaped at
## the wall's foot round where it stood, more outside than in, the same each time.
func _rubble_at(i: int) -> Transform3D:
	var r := RandomNumberGenerator.new()
	r.seed = i * 7919 + 17
	var s := clampf((_s0[i] + _s1[i]) * 0.5 + r.randfn(0.0, 0.9), 0.0, _length)
	var side := 1.0 if r.randf() < 0.6 else -1.0
	var out := side * (absf(r.randfn(0.0, 1.6)) + (0.0 if r.randf() < 0.35 else _thick * 0.5))
	var key := Vector2i(int(floor(s / 0.7)), int(floor(out / 0.7)))
	var g := _ground_at(s)
	var top: float = _heap.get(key, g)
	_heap[key] = top + _size[i].y * 0.5
	var cd: Vector3 = _chord_at(s)["dir"]
	var basis := Basis(cd, Vector3.UP, cd.cross(Vector3.UP)).rotated(Vector3.UP, r.randf_range(-0.9, 0.9))
	basis = basis.rotated(basis.x, r.randf_range(-0.35, 0.35)).rotated(basis.z, r.randf_range(-0.35, 0.35))
	return Transform3D(basis * Basis.from_scale(_size[i] * _shrink), _local_at(s, out, top + _size[i].y * 0.4))


# --- the fall ----------------------------------------------------------------

## Near the camera: blows fall as bodies. Away from it, nothing simulates.
func set_hot(on: bool) -> void:
	if on == hot:
		return
	hot = on
	if not on:
		_settle_all()
		_cool()


## The wall's physics space, made at its first fall: gravity in metres, and the
## ground round the blow.
func _warm(at: Vector3) -> void:
	if not _space.is_valid():
		_space = PhysicsServer3D.space_create()
		PhysicsServer3D.space_set_active(_space, true)
		PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY, float(Data.num("walls", "fall.gravity", 9.8)))
		PhysicsServer3D.area_set_param(_space, PhysicsServer3D.AREA_PARAM_GRAVITY_VECTOR, Vector3.DOWN)
	var key := Vector2i(int(floor(at.x / 8.0)), int(floor(at.z / 8.0)))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var k := key + Vector2i(dx, dz)
			if not _patches.has(k):
				_patches[k] = _ground_patch(k)
	_quiet = 0.0


## An 8 m square of ground (with a margin) as the stones meet it.
func _ground_patch(k: Vector2i) -> Array:
	var faces := PackedVector3Array()
	var step := 1.0
	var o := Vector2(k.x * 8.0 - 0.5, k.y * 8.0 - 0.5)
	var hy := func(x: float, z: float) -> float:
		return (float(ground.call(position + Vector3(x, 0, z) * S)) - position.y) / S
	for gx in 9:
		for gz in 9:
			var x0 := o.x + gx * step
			var z0 := o.y + gz * step
			var a := Vector3(x0, hy.call(x0, z0), z0)
			var b := Vector3(x0 + step, hy.call(x0 + step, z0), z0)
			var c := Vector3(x0 + step, hy.call(x0 + step, z0 + step), z0 + step)
			var d := Vector3(x0, hy.call(x0, z0 + step), z0 + step)
			faces.append_array([a, b, c, a, c, d])
	var shape := PhysicsServer3D.concave_polygon_shape_create()
	PhysicsServer3D.shape_set_data(shape, {"faces": faces, "backface_collision": true})
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 1.0)
	PhysicsServer3D.body_set_space(body, _space)
	return [body, shape]


func _static_box(xf: Transform3D, half: Vector3) -> Array:
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, half)
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_add_shape(body, shape)
	PhysicsServer3D.body_set_param(body, PhysicsServer3D.BODY_PARAM_FRICTION, 0.9)
	PhysicsServer3D.body_set_space(body, _space)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	return [body, shape]


func _physics_process(delta: float) -> void:
	if _bodies.is_empty():
		if _space.is_valid():
			_quiet += delta
			if _quiet > float(Data.num("walls", "fall.cool_s", 12.0)) and not busy():
				_cool()
		return
	_check += delta
	if _check > 0.15:
		_check = 0.0
		_support_live()
	var settle := float(Data.num("walls", "fall.settle_s", 7.0))
	var mm := _loose.multimesh
	for i in _bodies.keys():
		var body: RID = _bodies[i][0]
		var t: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
		mm.set_instance_transform(i, Transform3D(t.basis * Basis.from_scale(_size[i] * _shrink), t.origin))
		_since[i] = float(_since[i]) + delta
		_warm(t.origin)  # the ground goes on under a stone flung far
		# (A body only just made reads as asleep until its first step.)
		var asleep := float(_since[i]) > 0.4 and bool(PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_SLEEPING))
		if asleep or float(_since[i]) > settle or t.origin.y < _ground_at(_s0[i]) - 6.0:
			# Settled: it stays where it lies, and later stones land on it.
			PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
			_stays[i] = _bodies[i]
			_bodies.erase(i)
			_since.erase(i)
			_state[i] = RUBBLE
	_quiet = 0.0


## Every falling stone stops where it is (the camera went away mid-fall).
func _settle_all() -> void:
	for i in _bodies.keys():
		_state[i] = RUBBLE
		_loose.multimesh.set_instance_transform(i, _rubble_at(i))
		_free_pair(_bodies[i])
	_bodies.clear()
	_since.clear()


## The space goes; what lies, lies (drawn, not simulated).
func _cool() -> void:
	if not _space.is_valid() or not _bodies.is_empty():
		return
	for d in [_stays, _patches]:
		for k in d:
			_free_pair(d[k])
		d.clear()
	PhysicsServer3D.free_rid(_space)
	_space = RID()


func _free_pair(pair: Array) -> void:
	PhysicsServer3D.free_rid(pair[0])
	PhysicsServer3D.free_rid(pair[1])


func _exit_tree() -> void:
	_settle_all()
	_cool()


# --- dust --------------------------------------------------------------------

## A burst of stone dust at a world point (Kenney's smoke puffs), `big` times the usual.
func dust(world_pos: Vector3, big := 1.0) -> void:
	if not is_inside_tree():
		return
	var d: Dictionary = Data.value("walls", "dust", {})
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = int(float(d.get("amount", 22)) * big)
	p.lifetime = float(d.get("life_s", 2.4))
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08 * big
	pm.direction = Vector3.UP
	pm.spread = 75.0
	pm.initial_velocity_min = 0.08 * big
	pm.initial_velocity_max = 0.3 * big
	pm.gravity = Vector3(0.02, 0.015, 0)
	pm.damping_min = 0.2
	pm.damping_max = 0.5
	pm.angle_min = -180
	pm.angle_max = 180
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.6))
	var gt := CurveTexture.new()
	gt.curve = grow
	pm.scale_curve = gt
	var col := Color.from_string(String(d.get("colour", "#a39580")), Color(0.64, 0.58, 0.5))
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
	g.colors = PackedColorArray([Color(col, 0.0), Color(col, 0.75), Color(col, 0.0)])
	var gtex := GradientTexture1D.new()
	gtex.gradient = g
	pm.color_ramp = gtex
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE * float(d.get("size", 0.32)) * sqrt(big)
	q.material = _dust_material()
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 4, 4))
	get_parent().add_child(p)
	p.global_position = world_pos
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _dust_material() -> StandardMaterial3D:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.albedo_texture = load(DUST % 4)
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.vertex_color_use_as_albedo = true
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.billboard_keep_scale = true
		_dust_mat.particles_anim_h_frames = 1
		_dust_mat.particles_anim_v_frames = 1
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _dust_mat


# --- the way through ---------------------------------------------------------

## The wall's standing foot, as world XZ outlines (one per closed run): what
## people walk round. A gap whose foot is open (no stone left below
## breach.open_below_m over breach.open_min_m) is a breach to walk through.
func foot() -> Array:
	var b: Dictionary = Data.value("walls", "breach", {})
	var below := float(b.get("open_below_m", 1.4))
	var min_gap := float(b.get("open_min_m", 1.0))
	var step := 0.25
	var n := int(ceil(_length / step))
	var closed := PackedByteArray()
	closed.resize(n)
	for i in _xf.size():
		var g := _ground_at((_s0[i] + _s1[i]) * 0.5)
		if _state[i] != WHOLE or _yb[i] > g + below or _yb[i] + _size[i].y < g + 0.4:
			continue  # above a walkable gap, or a foundation stone level with the ground
		for k in range(int(_s0[i] / step), mini(int(ceil(_s1[i] / step)), n)):
			closed[k] = 1
	# Gaps too narrow to pass count as wall.
	var k := 0
	while k < n:
		if closed[k] == 0:
			var e := k
			while e < n and closed[e] == 0:
				e += 1
			if (e - k) * step < min_gap and k > 0 and e < n:
				for q in range(k, e):
					closed[q] = 1
			k = e
		else:
			k += 1
	var out := []
	for ch in _chords:
		var a := int(float(ch["s0"]) / step)
		var z := mini(int((float(ch["s0"]) + float(ch["len"])) / step), n)
		var q := a
		while q < z:
			if closed[q] == 1:
				var e := q
				while e < z and closed[e] == 1:
					e += 1
				var p0 := _world_at(q * step, -_thick * 0.5)
				var p1 := _world_at(e * step, -_thick * 0.5)
				var p2 := _world_at(e * step, _thick * 0.5)
				var p3 := _world_at(q * step, _thick * 0.5)
				out.append(PackedVector2Array([Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector2(p2.x, p2.z), Vector2(p3.x, p3.z)]))
				q = e
			else:
				q += 1
	return out


## The top of the rubble under a world point (world y), or -INF where none lies:
## men storming a breach climb its ramp (army_assault.gd). A height grid of the
## fallen stones in half-metre cells, rebuilt at most twice a second.
func rubble_height(world: Vector3) -> float:
	var now := Time.get_ticks_msec()
	if now - _rubble_at_ms > 500:
		_rubble_at_ms = now
		_rubble_grid.clear()
		var mm := _loose.multimesh if _loose else null
		for i in _xf.size():
			if _state[i] != RUBBLE or mm == null:
				continue
			var t := mm.get_instance_transform(i)
			var half := maxf(_size[i].x, _size[i].z) * 0.5
			var top := t.origin.y + _size[i].y * 0.5
			for cx in range(floori((t.origin.x - half) / 0.5), floori((t.origin.x + half) / 0.5) + 1):
				for cz in range(floori((t.origin.z - half) / 0.5), floori((t.origin.z + half) / 0.5) + 1):
					var k := Vector2i(cx, cz)
					_rubble_grid[k] = maxf(float(_rubble_grid.get(k, -INF)), top)
	var l := _to_local(world)
	var top_m: float = _rubble_grid.get(Vector2i(floori(l.x / 0.5), floori(l.z / 0.5)), -INF)
	return position.y + top_m * S if top_m > -INF else -INF


## The breaches open now: each gap's middle on the ground (world), for troops.
func breaches() -> Array:
	var out := []
	var runs := foot()
	if runs.is_empty():
		return [_world_at(_length * 0.5)]
	var ends := []
	for r in runs:
		ends.append([along(Vector3(r[0].x, 0, r[0].y)), along(Vector3(r[1].x, 0, r[1].y))])
	ends.sort_custom(func(x, y): return x[0] < y[0])
	for i in ends.size() - 1:
		var a: float = ends[i][1]
		var z: float = ends[i + 1][0]
		if z - a > 0.9:
			var s := (a + z) * 0.5
			out.append(_world_at(s, 0.0, _ground_at(s)))
	return out


## A stable 0..1 from an integer.
static func _h01(n: int) -> float:
	return float(hash(n) % 10007) / 10007.0
