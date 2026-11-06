extends CanvasLayer
## The character view: one named person up close, in a torchlit hall under
## their house's banner, with who they are, what they want and what they
## remember beside them. They're cast by people.gd from the Mixamo characters,
## by station and always the same body for the same person, and play any
## Mixamo move dropped into assets/hero/anims (FBX, without skin, retargeted
## at import like the crowd's moves), each one a button. The stage lives in
## its own 3D world, so the realm behind it is untouched.

const T := preload("res://scripts/theme.gd")
const Keys := preload("res://scripts/keys.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const People := preload("res://scripts/people.gd")
const ANIM_DIR := "res://assets/hero/anims"

signal closed
signal edit_requested(person: Dictionary, house: Dictionary)
signal control_requested(person: Dictionary, house: Dictionary)

var _viewport: SubViewport
var _stage: Node3D
var _cam: Camera3D
var _body: Node3D
var _player: AnimationPlayer
var _panel: PanelContainer
var _torches: Array[OmniLight3D] = []
var _orbit := 0.0
var _idle_for := 0.0
var _fidget_at := 6.0
var _clips := {}  # move name -> Animation, on the humanoid skeleton
var _people = People.new()


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
		_torches[i].light_energy = 3.4 + sin(t * 7.0 + i * 2.1) * 0.25 + sin(t * 13.0 + i) * 0.15


## Opens the view on a person (the /person record) of a house (world house dict).
## Where Back leads: the page you came from, named on the button.
var back_to := "the realm"
var _back_btn: Button


func open(person: Dictionary, house: Dictionary, from := "the realm") -> void:
	back_to = from
	if _back_btn:
		_back_btn.text = "  ←  Back to %s   (%s)  " % [back_to, Keys.label("back").get_slice(" / ", 0)]
	visible = true
	_orbit = 0.0
	_dress_stage(house, _family(person, house))
	_cast(person, house)
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
	# A torchlit hall, not a cellar: warm dark behind, enough light to see a face.
	env.background_color = Color(0.075, 0.06, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.3)
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_light_color = Color(0.14, 0.11, 0.08)
	env.fog_density = 0.03
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
	# A soft key from the front, as from a brazier at the viewer's side: the face
	# and clothes read; the torches still warm the edges.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.86, 0.7)
	key.light_energy = 0.8
	key.rotation = Vector3(deg_to_rad(-25), deg_to_rad(-20), 0)
	_stage.add_child(key)
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


func _dress_stage(house: Dictionary, family: Dictionary) -> void:
	for n in _stage.get_children():
		if n.is_in_group("hero_dressing"):
			n.queue_free()
	var col := Color.from_string(String(house.get("color", "#8a6d3b")), Color(0.55, 0.42, 0.25))
	# The house's banner hangs behind them, a little off to one side; one of a
	# lesser family stands between their own banner and their liege's.
	for x in [-1.3, 1.3]:
		var b: Node3D = Heraldry.standard(family if x < 0.0 and not family.is_empty() else house, col, 3.2)
		b.position = Vector3(x, 0, -1.6)
		b.add_to_group("hero_dressing")
		_stage.add_child(b)


# --- the person ------------------------------------------------------------------

func _cast(person: Dictionary, house: Dictionary) -> void:
	if _body:
		_body.queue_free()
	var key := str(person.get("id", person.get("name", "")))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var years := int(person.get("age", 30))
	var age := "child" if years < 14 else ("elder" if years > 60 else "adult")
	var tint := Color.from_string(String(house.get("color", "#888888")), Color.GRAY).lerp(Color.WHITE, 0.45)
	var model: Node3D = _people.make(rng, People.station(person), tint, age, "", str(person.get("gender", "")), key)
	model.scale /= People.S  # the stage is in metres, the realm at town scale
	_body = Node3D.new()
	_body.add_child(model)
	_stage.add_child(_body)
	_body.rotation.y = 0.25
	_player = model.get_node("Anim")
	_load_clips()
	var lib := AnimationLibrary.new()
	for move in _clips:
		lib.add_animation(move, _clips[move])
	_player.add_animation_library("hero", lib)
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
	for want in ["Breathing Idle", "Standing Idle", "Idle"]:
		if _clips.has(want):
			return want
	return _clips.keys()[0] if not _clips.is_empty() else ""


## Every Mixamo move in assets/hero/anims, keyed by a readable name. They're
## retargeted at import to the humanoid skeleton, so they play on any body
## people.gd makes, as the crowd's moves do.
func _load_clips() -> void:
	if not _clips.is_empty():
		return
	var dir := DirAccess.open(ANIM_DIR)
	if dir == null:
		return
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
					var move := f.get_basename().capitalize()
					var clip := People._in_place(anim.duplicate(true))
					clip.loop_mode = Animation.LOOP_LINEAR if _is_idle(move) else Animation.LOOP_NONE
					_clips[move] = clip
					break
		scene.free()


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
	back.text = "  ←  Back to %s   (%s)  " % [back_to, Keys.label("back").get_slice(" / ", 0)]
	_back_btn = back
	back.position = Vector2(24, 24)
	back.pressed.connect(close)
	add_child(back)


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
	# Their arms beside their name: a lesser family's own, their liege's smaller.
	var family := _family(p, house)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	if not family.is_empty():
		head.add_child(_arms(family, Color.WHITE, 40))
	var liege := _arms(house, Color.from_string(String(house.get("color", "#888")), Color.GRAY).lerp(Color.WHITE, 0.25), 40 if family.is_empty() else 22)
	if liege.texture:
		head.add_child(liege)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 2)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	var house_line := String(house.get("name", p.get("house", "")))
	if not family.is_empty():
		house_line = "The %s family  ·  sworn to %s" % [String(family["name"]).trim_prefix("House "), house_line.replace("House ", "")]
	var hl := T.label(house_line)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(hl)
	var title := T.title(String(p.get("name", "")), 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(title)
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
	var nature := ", ".join(p.get("traits", []))
	v.add_child(T.datum(nature.left(1).to_upper() + nature.substr(1), T.SIZE_BODY))
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
	take.visible = preload("res://scripts/features.gd").WALKING  # stepping into someone's boots: version 2
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


## The lesser family a person belongs to (from their surname), or {} for
## the house's own blood.
static func _family(p: Dictionary, house: Dictionary) -> Dictionary:
	var name := String(p.get("name", "")).strip_edges()
	var surname := name.get_slice(" ", name.get_slice_count(" ") - 1)
	if "House " + surname == String(house.get("name", p.get("house", ""))):
		return {}
	return Heraldry.family(surname)


static func _arms(house: Dictionary, tint: Color, px: int) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Heraldry.sigil(house)
	r.custom_minimum_size = Vector2(px, px)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = tint
	return r


func _para(text: String) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.text = text
	r.add_theme_font_size_override("normal_font_size", T.SIZE_BODY)
	r.add_theme_font_size_override("italics_font_size", T.SIZE_BODY)
	r.add_theme_color_override("default_color", T.TEXT_2)
	return r


