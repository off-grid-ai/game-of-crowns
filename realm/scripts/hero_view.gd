extends CanvasLayer
## The character view: one named person up close, in a torchlit hall under
## their house's banner, with who they are, what they want and what they
## remember beside them. They're the detailed Mixamo-rigged "hero layer"
## (assets/hero), separate from the light Quaternius crowds, and play any
## Mixamo move dropped into assets/hero/anims (FBX, without skin), each one a
## button. The stage lives in its own 3D world, so the realm behind it is
## untouched.

const T := preload("res://scripts/theme.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const ANIM_DIR := "res://assets/hero/anims"
# Body by who they are: [model, height in metres]. Each is a Mixamo rig.
const MEN := ["fuse_civilian_1", "fuse_civilian_2", "medieval_civilian_3"]
const WOMEN := ["fuse_woman_1"]
const KNIGHT := "knight"

signal closed
signal edit_requested(person: Dictionary, house: Dictionary)
signal control_requested(person: Dictionary, house: Dictionary)

var _viewport: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _body: Node3D
var _player: AnimationPlayer
var _panel: PanelContainer
var _moves: VBoxContainer
var _torches: Array[OmniLight3D] = []
var _orbit := 0.0
var _idle_for := 0.0
var _fidget_at := 6.0
var _clips := {}  # move name -> Animation (in Mixamo bone names, normalised)


func _ready() -> void:
	layer = 20
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 1)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(box)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	box.add_child(_viewport)
	_build_stage()
	_build_panel()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_fidget(delta)
	if not visible:
		return
	# A slow drift around them, low and to the side, never face-on.
	_orbit += delta * 0.06
	var yaw := 0.55 + sin(_orbit) * 0.35
	var at := Vector3(0, 1.05, 0)
	_cam.position = at + Vector3(sin(yaw), 0.0, cos(yaw)) * 3.6 + Vector3(0, 0.3, 0)
	_cam.look_at(at, Vector3.UP)
	# Frame them left of centre, clear of the panel on the right.
	_cam.h_offset = 0.75
	var t := Time.get_ticks_msec() / 1000.0
	for i in _torches.size():
		_torches[i].light_energy = 2.6 + sin(t * 7.0 + i * 2.1) * 0.25 + sin(t * 13.0 + i) * 0.15


## Opens the view on a person (the /person record) of a house (world house dict).
func open(person: Dictionary, house: Dictionary) -> void:
	visible = true
	_orbit = 0.0
	_dress_stage(house)
	_cast(person)
	_fill_panel(person, house)


func close() -> void:
	visible = false
	if _body:
		_body.queue_free()
		_body = null
	closed.emit()


# --- the stage -----------------------------------------------------------------

func _build_stage() -> void:
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.012, 0.01)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.27, 0.22)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.06, 0.05)
	env.fog_density = 0.04
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_stage.add_child(_cam)
	_cam.current = true
	# Stone underfoot, fading into the dark.
	var ground := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 6.0
	disc.bottom_radius = 6.0
	disc.height = 0.1
	ground.mesh = disc
	ground.position.y = -0.05
	var stone := StandardMaterial3D.new()
	var tex_path: String = preload("res://scripts/terrain.gd").art("res://assets/ground/square-cobbles.jpg", "res://assets/village/T_UnevenBrick_BaseColor.png")
	if ResourceLoader.exists(tex_path):
		stone.albedo_texture = load(tex_path)
	stone.uv1_scale = Vector3(6, 6, 6)
	stone.albedo_color = Color(0.6, 0.56, 0.52)
	stone.roughness = 0.9
	ground.material_override = stone
	_stage.add_child(ground)
	# A warm key from the torches, a cool rim from a high window behind.
	for side in [-1, 1]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(1.0, 0.62, 0.3)
		torch.omni_range = 7.0
		torch.shadow_enabled = side == 1
		torch.position = Vector3(1.7 * side, 2.2, 0.9)
		_stage.add_child(torch)
		_torches.append(torch)
		var flame := _flame()
		flame.position = torch.position
		_stage.add_child(flame)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.65, 0.85)
	rim.light_energy = 0.9
	rim.rotation = Vector3(deg_to_rad(-35), deg_to_rad(160), 0)
	_stage.add_child(rim)


func _flame() -> Node3D:
	var p := CPUParticles3D.new()
	p.amount = 18
	p.lifetime = 0.5
	p.direction = Vector3.UP
	p.spread = 10
	p.initial_velocity_min = 0.3
	p.initial_velocity_max = 0.6
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.75, 0.35))
	g.set_color(1, Color(0.9, 0.25, 0.05, 0.0))
	p.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.12, 0.12)
	var m := StandardMaterial3D.new()
	m.albedo_texture = preload("res://scripts/towns.gd").soft_dot()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	q.material = m
	p.mesh = q
	return p


func _dress_stage(house: Dictionary) -> void:
	for n in _stage.get_children():
		if n.is_in_group("hero_dressing"):
			n.queue_free()
	var col := Color.from_string(String(house.get("color", "#8a6d3b")), Color(0.55, 0.42, 0.25))
	# The house's banner hangs behind them, a little off to one side.
	for x in [-1.3, 1.3]:
		var b: Node3D = Heraldry.standard(house, col, 3.2)
		b.position = Vector3(x, 0, -1.6)
		b.add_to_group("hero_dressing")
		_stage.add_child(b)


# --- the person ------------------------------------------------------------------

func _cast(person: Dictionary) -> void:
	if _body:
		_body.queue_free()
	var female := str(person.get("gender", "male")) == "female"
	var role := str(person.get("role")) if person.get("role") else ""
	var knightly := role.to_lower().contains("knight") or role.to_lower().contains("sword")
	var pool: Array = WOMEN if female else ([KNIGHT] if knightly else MEN)
	var pick: String = pool[abs(hash(str(person.get("id", person.get("name", ""))))) % pool.size()]
	var path := "res://assets/hero/%s/scene.gltf" % pick
	if not ResourceLoader.exists(path):
		return
	var model: Node3D = (load(path) as PackedScene).instantiate()
	_body = Node3D.new()
	_body.add_child(model)
	_stage.add_child(_body)
	# Scale to a person's height (the rigs come in centimetres), feet on the floor.
	var box := _bounds(model)
	var tall := 1.72 if female else 1.8
	var k := tall / maxf(box.size.y, 0.001)
	model.scale = Vector3.ONE * k
	model.position = Vector3(-box.get_center().x, -box.position.y, -box.get_center().z) * k
	_body.rotation.y = 0.25
	_player = model.find_children("*", "AnimationPlayer", true, false)[0] if not model.find_children("*", "AnimationPlayer", true, false).is_empty() else null
	if _player == null:
		_player = AnimationPlayer.new()
		model.add_child(_player)
	_load_clips()
	var skel: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var lib := AnimationLibrary.new()
	for move in _clips:
		_clips[move]["name"] = move
		lib.add_animation(move, _for_skeleton(_clips[move], _player, skel))
	if _player.has_animation_library("hero"):
		_player.remove_animation_library("hero")
	_player.add_animation_library("hero", lib)
	_fill_moves()
	var first := _default_move()
	if first != "":
		play(first)


func play(move: String) -> void:
	if _player and _player.has_animation("hero/" + move):
		_player.play("hero/" + move, 0.4)
		# A gesture plays once, then they settle back into their stance.
		if not _is_idle(move) and move != "Dying":
			_player.queue("hero/" + _default_move())
	_idle_for = 0.0


## Stances loop; everything else is a gesture that plays once.
static func _is_idle(move: String) -> bool:
	return move.contains("Idle") or move.contains("Stance") or move in ["Weight Shift", "Walking", "Praying", "Sword And Shield"]


## Left alone, a person isn't a statue: every so often they shift, nod or sigh.
func _fidget(delta: float) -> void:
	if _player == null or not visible or _player.current_animation == "hero/Dying":
		return
	_idle_for += delta
	if _idle_for < _fidget_at:
		return
	_idle_for = 0.0
	_fidget_at = randf_range(9.0, 16.0)
	var calm := ["Weight Shift", "Look Away", "Relieved Sigh", "Nod Yes", "Thinking", "Acknowledge", "Standing Idle"]
	var pick: Array = calm.filter(func(m): return _clips.has(m))
	if not pick.is_empty():
		play(pick[randi() % pick.size()])


func _default_move() -> String:
	for want in ["Breathing Idle", "Standing Idle", "Idle", "Knight's Stance"]:
		if _clips.has(want):
			return want
	return _clips.keys()[0] if not _clips.is_empty() else ""


## Every Mixamo move in assets/hero/anims, plus the knight's own stance, keyed
## by a readable name, with bone names normalised so any Mixamo rig can play it.
func _load_clips() -> void:
	if not _clips.is_empty():
		return
	var dir := DirAccess.open(ANIM_DIR)
	if dir:
		for f in dir.get_files():
			if not (f.ends_with(".fbx") or f.ends_with(".glb") or f.ends_with(".gltf")):
				continue
			# A file still downloading or not yet imported is skipped, not fatal.
			var packed := load(ANIM_DIR + "/" + f) as PackedScene
			if packed == null:
				continue
			var scene: Node = packed.instantiate()
			var ap: Array = scene.find_children("*", "AnimationPlayer", true, false)
			if not ap.is_empty():
				var a: AnimationPlayer = ap[0]
				for n in a.get_animation_list():
					var anim: Animation = a.get_animation(n)
					if anim.length > 0.1:
						_clips[f.get_basename().capitalize()] = _neutral(anim, scene)
						break
			scene.free()
	# The knight's sculpture carries a slow armed stance: everyone can use it.
	var kp := "res://assets/hero/%s/scene.gltf" % KNIGHT
	if ResourceLoader.exists(kp):
		var ks: Node = (load(kp) as PackedScene).instantiate()
		var ap: Array = ks.find_children("*", "AnimationPlayer", true, false)
		if not ap.is_empty():
			var a: AnimationPlayer = ap[0]
			var anim: Animation = a.get_animation(a.get_animation_list()[0])
			if anim.length > 0.1:
				_clips["Knight's Stance"] = _neutral(anim, ks)
		ks.free()


## The clip with each track keyed to a bare bone name ("hips", "leftforearm"),
## rotations only plus the hips' height as a share of the source's hips, so it
## fits any Mixamo body whatever its scale or the exporter's node names.
func _neutral(anim: Animation, scene: Node) -> Dictionary:
	var src: Skeleton3D = null
	var sk: Array = scene.find_children("*", "Skeleton3D", true, false)
	if not sk.is_empty():
		src = sk[0]
	var hip_rest := 1.0
	if src:
		var hb := _find_bone(src, "hips")
		if hb >= 0:
			hip_rest = maxf(absf(src.get_bone_global_rest(hb).origin.y), 0.001)
	var tracks := []
	for i in anim.get_track_count():
		var path := String(anim.track_get_path(i))
		var bone := _bare(path.get_slice(":", path.get_slice_count(":") - 1))
		var kind := anim.track_get_type(i)
		if kind == Animation.TYPE_ROTATION_3D or (kind == Animation.TYPE_POSITION_3D and bone == "hips"):
			var keys := []
			for k in anim.track_get_key_count(i):
				var v = anim.track_get_key_value(i, k)
				if kind == Animation.TYPE_POSITION_3D:
					v = v / hip_rest
				keys.append([anim.track_get_key_time(i, k), v])
			tracks.append({"bone": bone, "type": kind, "keys": keys})
	return {"length": anim.length, "tracks": tracks, "name": ""}


func _for_skeleton(clip: Dictionary, player: AnimationPlayer, skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = clip["length"]
	a.loop_mode = Animation.LOOP_LINEAR if _is_idle(clip.get("name", "")) else Animation.LOOP_NONE
	var root := player.get_node(player.root_node)
	var skel_path := String(root.get_path_to(skel))
	var hb := _find_bone(skel, "hips")
	var hip_rest := absf(skel.get_bone_global_rest(hb).origin.y) if hb >= 0 else 1.0
	for t in clip["tracks"]:
		var b := _find_bone(skel, t["bone"])
		if b < 0:
			continue
		var i := a.add_track(t["type"])
		a.track_set_path(i, "%s:%s" % [skel_path, skel.get_bone_name(b)])
		for k in t["keys"]:
			var v = k[1]
			if t["type"] == Animation.TYPE_POSITION_3D:
				v = v * hip_rest
			if t["type"] == Animation.TYPE_ROTATION_3D:
				a.rotation_track_insert_key(i, k[0], v)
			else:
				a.position_track_insert_key(i, k[0], v)
	return a


## "mixamorig_LeftForeArm_018" / "mixamorig:LeftForeArm" -> "leftforearm"
static func _bare(name: String) -> String:
	var n := name.to_lower()
	for p in ["mixamorig:", "mixamorig_", "mixamorig1:", "mixamorig1_", "mixamorig2_"]:
		n = n.trim_prefix(p)
	var parts := n.split("_")
	if parts.size() > 1 and parts[-1].is_valid_int():
		parts.remove_at(parts.size() - 1)
	return "".join(parts).replace(":", "")


static func _find_bone(skel: Skeleton3D, bare: String) -> int:
	for b in skel.get_bone_count():
		if _bare(skel.get_bone_name(b)) == bare:
			return b
	return -1


static func _bounds(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var b: AABB = xf * (mi as MeshInstance3D).get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


# --- who they are ------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	T.glass(_panel)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -380
	_panel.offset_right = -24
	_panel.offset_top = 24
	_panel.offset_bottom = -24
	add_child(_panel)
	var back := Button.new()
	back.text = "  ←  Back to the realm   (Esc)  "
	back.position = Vector2(24, 24)
	back.pressed.connect(close)
	add_child(back)
	# The moves run down the left edge, clear of the person and the panel.
	var list := ScrollContainer.new()
	list.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list.anchor_bottom = 1.0
	list.offset_left = 24
	list.offset_right = 214
	list.offset_top = 92
	list.offset_bottom = -24
	add_child(list)
	_moves = VBoxContainer.new()
	_moves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_moves.add_theme_constant_override("separation", 2)
	list.add_child(_moves)


func _fill_panel(p: Dictionary, house: Dictionary) -> void:
	for c in _panel.get_children():
		c.queue_free()
	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 26 if side != "right" else 18)
	_panel.add_child(pad)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pad.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)
	v.add_child(T.label(String(house.get("name", p.get("house", ""))).to_upper()))
	v.add_child(T.title(String(p.get("name", "")), 26))
	var rank := str(p["role"]) if p.get("role") else (str(p["rank"]).capitalize() if p.get("rank") else "")
	if str(p.get("gender", "")) == "female":
		rank = {"Lord": "Lady", "Bannerman": "Bannerwoman", "Heir": "Heiress"}.get(rank, rank)
	var line := "%s, %d" % [rank, int(p.get("age", 0))] if rank != "" else "Aged %d" % int(p.get("age", 0))
	if p.get("seat"):
		line += "  ·  of %s" % String(p["seat"])
	v.add_child(T.datum(line, T.SIZE_BODY, T.TEXT_2))
	if house.get("words"):
		v.add_child(T.datum("“%s”" % String(house["words"]), T.SIZE_DESC, T.ACCENT))
	v.add_child(HSeparator.new())
	v.add_child(T.label("Nature"))
	v.add_child(T.datum(", ".join(p.get("traits", [])).capitalize(), T.SIZE_BODY))
	var loyal := int(p.get("loyalty", 50))
	v.add_child(T.label("Loyalty to their liege (of 100)"))
	var bar := ProgressBar.new()
	bar.max_value = 100
	bar.value = loyal
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 6)
	v.add_child(bar)
	var goals: Array = p.get("goals", [])
	if not goals.is_empty():
		v.add_child(T.label("Wants to"))
		for g in goals:
			v.add_child(_para("·  " + String(g)))
	if p.get("backstory"):
		v.add_child(T.label("Their story"))
		v.add_child(_para(String(p["backstory"])))
	var change := Button.new()
	change.text = "Change who they are"
	change.pressed.connect(func(): edit_requested.emit(p, house))
	var take := Button.new()
	take.text = "Take control"
	take.add_theme_color_override("font_color", T.ACCENT)
	take.pressed.connect(func(): control_requested.emit(p, house))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(take)
	row.add_child(change)
	v.add_child(row)
	var mem: Array = []
	for m in p.get("memories", []):
		if not mem.has(m):
			mem.append(m)
	if not mem.is_empty():
		v.add_child(T.label("Remembers"))
		for i in range(mem.size() - 1, -1, -1):
			v.add_child(_para("[i]“%s”[/i]" % String(mem[i])))


func _para(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.add_theme_font_size_override("normal_font_size", T.SIZE_BODY)
	r.add_theme_font_size_override("italics_font_size", T.SIZE_BODY)
	r.add_theme_color_override("default_color", T.TEXT_2)
	return r


func _fill_moves() -> void:
	for c in _moves.get_children():
		c.queue_free()
	for idle in [true, false]:
		_moves.add_child(T.label("Stance" if idle else "Gesture"))
		for move in _clips:
			if _is_idle(move) != idle:
				continue
			var b := Button.new()
			b.text = move
			b.flat = true
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.add_theme_font_size_override("font_size", T.SIZE_DESC)
			b.add_theme_color_override("font_color", T.TEXT_2)
			b.pressed.connect(play.bind(move))
			_moves.add_child(b)
		if idle:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 10)
			_moves.add_child(gap)
