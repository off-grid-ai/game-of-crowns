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
signal name_changed  # the player gave someone a new name, or rewrote who they are
var save_person := Callable()  # (person, spec, cb(code, d)) -> void: their rewrite, kept (main.gd)
var trait_options := Callable()  # (cb(options)) -> void: the natures a person may have
var rename_name := Callable()  # (from, to, cb) -> void: the player's own name for a word

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


## Escape is the top view's first: it closes the meeting before the menu or the
## realm underneath can take it.
func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.is_action_pressed(&"back")):
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
	# A real place, not a set: sky, ground and haze are one world (each house's
	# land is dressed in _dress_stage), lit by a low warm sun.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.fog_enabled = true
	env.fog_density = 0.006
	env.fog_aerial_perspective = 0.45  # the far land takes the sky's colour, as distance does
	env.fog_sky_affect = 0.4
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_env = env
	_stage.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_cam.far = 400.0
	_stage.add_child(_cam)
	_cam.current = true
	# The ground, wide enough to meet the haze; its look is the house's land.
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	_ground.mesh = plane
	_stage.add_child(_ground)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 40.0
	_sun.rotation = Vector3(deg_to_rad(-22), deg_to_rad(-40), 0)  # low, from the left and a little behind the viewer
	_stage.add_child(_sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.7, 0.75, 0.9)
	fill.light_energy = 0.35
	fill.rotation = Vector3(deg_to_rad(-30), deg_to_rad(150), 0)
	_stage.add_child(fill)


var _env: Environment
var _ground: MeshInstance3D
var _sun: DirectionalLight3D
var _trees: Node = null  # forest.gd, for its tree meshes in metres
var _fine_pines: Array = []  # the pine pack at its finest, for trees seen this close

## Each house's land as you'd stand in it: ground texture, its trees, its sky.
const LANDS := {
	"wolfholt": {"ground": "snow", "trees": "pine", "sky": Color(0.52, 0.62, 0.78), "horizon": Color(0.82, 0.84, 0.88), "sun": Color(1.0, 0.86, 0.72)},
	"highfell": {"ground": "rock", "trees": "pine", "sky": Color(0.42, 0.56, 0.78), "horizon": Color(0.78, 0.8, 0.84), "sun": Color(1.0, 0.9, 0.78)},
	"ironreach": {"ground": "rock", "trees": "pine", "sky": Color(0.45, 0.52, 0.6), "horizon": Color(0.7, 0.72, 0.74), "sun": Color(0.95, 0.88, 0.8)},
	"stormhold": {"ground": "grass", "trees": "pine", "sky": Color(0.42, 0.48, 0.58), "horizon": Color(0.72, 0.72, 0.7), "sun": Color(1.0, 0.84, 0.7)},
	"goldcrest": {"ground": "grass", "trees": "oak", "sky": Color(0.45, 0.6, 0.82), "horizon": Color(0.95, 0.82, 0.62), "sun": Color(1.0, 0.8, 0.55)},
	"thornvale": {"ground": "grass", "trees": "oak", "sky": Color(0.42, 0.6, 0.85), "horizon": Color(0.9, 0.84, 0.7), "sun": Color(1.0, 0.85, 0.62)},
	"sunspire": {"ground": "sand", "trees": "", "sky": Color(0.5, 0.62, 0.82), "horizon": Color(0.98, 0.82, 0.6), "sun": Color(1.0, 0.78, 0.5)},
	"crown": {"ground": "grass", "trees": "oak", "sky": Color(0.44, 0.6, 0.84), "horizon": Color(0.95, 0.84, 0.66), "sun": Color(1.0, 0.82, 0.58)},
}


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


## The painting behind a person of this house: res://assets/intro/art/house_<name>
## (jpg or png), else the seat's still in res://assets/intro/stills.
static func _backdrop_of(house: Dictionary) -> String:
	var name := String(house.get("key", house.get("name", "")))  # the house's own name: its painting, whatever the player calls it
	var key := "house_" + name.trim_prefix("House ").trim_prefix("The ").to_lower().replace(" ", "_")
	for ext in [".jpg", ".png"]:
		if ResourceLoader.exists("res://assets/intro/art/" + key + ext):
			return "res://assets/intro/art/" + key + ext
	var seat := String(house.get("seat", ""))
	if seat != "" and ResourceLoader.exists("res://assets/intro/stills/seat_%s.png" % seat):
		return "res://assets/intro/stills/seat_%s.png" % seat
	return ""


func _dress_stage(house: Dictionary, family: Dictionary) -> void:
	for n in _stage.get_children():
		if n.is_in_group("hero_dressing"):
			n.queue_free()
	var col := preload("res://scripts/heraldry.gd").colour(house, Color(0.55, 0.42, 0.25), "#8a6d3b")
	# Their own land around them: its ground, sky, trees and, far off, a castle.
	var who := "crown" if house.get("crown", false) else String(house.get("key", house.get("name", ""))).trim_prefix("House ").to_lower()
	var land: Dictionary = LANDS.get(who, LANDS["thornvale"])
	var sky: ProceduralSkyMaterial = _env.sky.sky_material
	sky.sky_top_color = land["sky"]
	sky.sky_horizon_color = land["horizon"]
	sky.ground_horizon_color = land["horizon"]
	sky.ground_bottom_color = land["horizon"].darkened(0.4)
	_env.fog_light_color = land["horizon"]
	_sun.light_color = land["sun"]
	_sun.light_energy = 1.35
	var g := StandardMaterial3D.new()
	var tex := "res://assets/ground/%s-albedo.jpg" % land["ground"]
	if ResourceLoader.exists(tex):
		g.albedo_texture = load(tex)
	var nrm := "res://assets/ground/%s-normal.jpg" % land["ground"]
	if ResourceLoader.exists(nrm):
		g.normal_enabled = true
		g.normal_texture = load(nrm)
	g.uv1_scale = Vector3(60, 60, 60)
	g.roughness = 0.95
	_ground.material_override = g
	if String(land["trees"]) != "" and preload("res://scripts/forest.gd").available():
		if _trees == null:
			_trees = preload("res://scripts/forest.gd").new()
			_trees._load()
		var pool: Array = []
		# Close enough to see, the pack's finest level of each tree: fuller crowns.
		if land["trees"] == "pine" and _fine_pines.is_empty():
			var scene: Node = (load(_trees.PACK) as PackedScene).instantiate()
			for kind in _trees.KINDS:
				var m: ArrayMesh = _trees._merge(scene, kind + "_LOD0")
				if m:
					_fine_pines.append(m)
			scene.free()
		pool.append_array(_fine_pines if land["trees"] == "pine" else [])
		var lo: int = 0 if land["trees"] == "pine" else _trees.OAK_FIRST
		var hi: int = _trees.OAK_FIRST if land["trees"] == "pine" else mini(_trees._full.size(), _trees.OAK_FIRST + 7)
		if pool.is_empty():
			for i in range(lo, hi):
				if i < _trees._full.size() and _trees._full[i] != null:
					pool.append(_trees._full[i])
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(who)
		for i in 90:
			if pool.is_empty():
				break
			# A wood behind and to the sides, never between them and you.
			var ang := rng.randf_range(-2.4, 2.4)
			var dist := rng.randf_range(18.0, 70.0)  # a wood at a distance: its edge, not single trees up close
			var at := Vector3(sin(ang) * dist, 0, -cos(ang) * dist)
			if at.z > -12.0:
				continue
			var t := MeshInstance3D.new()
			t.mesh = pool[rng.randi() % pool.size()]
			t.position = at
			t.rotation.y = rng.randf() * TAU
			t.scale = Vector3.ONE * rng.randf_range(0.8, 1.2)
			t.add_to_group("hero_dressing")
			_stage.add_child(t)
	# Low hills all round, far off in the haze, so the land rolls away instead of
	# ending in a ruled line at the sky.
	var hrng := RandomNumberGenerator.new()
	hrng.seed = hash(who + "hills")
	for i in 14:
		var hill := MeshInstance3D.new()
		var dome := SphereMesh.new()
		dome.radius = 1.0
		dome.height = 2.0
		dome.radial_segments = 24
		dome.rings = 12
		hill.mesh = dome
		hill.material_override = g
		var ang := (float(i) / 14.0) * TAU + hrng.randf_range(-0.2, 0.2)
		var far := hrng.randf_range(110.0, 170.0)
		hill.position = Vector3(sin(ang) * far, -6.0, -cos(ang) * far)
		hill.scale = Vector3(hrng.randf_range(45.0, 80.0), hrng.randf_range(10.0, 22.0), hrng.randf_range(30.0, 50.0))
		hill.rotation.y = ang
		hill.add_to_group("hero_dressing")
		_stage.add_child(hill)
	var castle: Node3D = preload("res://scripts/realistic.gd").make(preload("res://scripts/realistic.gd").one("castle"))
	if castle:
		castle.scale = Vector3.ONE / preload("res://scripts/realistic.gd").S  # its real size, in metres
		castle.position = Vector3(-20, 0, -85)  # off to the left, clear of the card
		castle.rotation.y = deg_to_rad(200)
		castle.add_to_group("hero_dressing")
		_stage.add_child(castle)
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
	var tint := preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888888").lerp(Color.WHITE, 0.45)
	var model: Node3D = _people.make(rng, People.station(person), tint, age, "", str(person.get("gender", "")), key)
	model.scale /= People.S  # the stage is in metres, the realm at town scale
	model.remove_from_group("people")  # on the close-up's stage, not in the realm: no crowd or ground check sees them
	_body = Node3D.new()
	_body.add_child(model)
	_stage.add_child(_body)
	_body.rotation.y = 0.25
	People.release(model)  # this stage drives the player itself
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
	_panel.anchor_bottom = 0.0  # as tall as what it says (_fit_panel), never a long empty card
	_panel.offset_left = -480  # room for a name and Edit on one line
	_panel.offset_right = -24
	_panel.offset_top = 24
	_panel.offset_bottom = 24
	_panel.theme = T.get_theme()  # the game's own type and buttons
	add_child(_panel)
	var back := Button.new()
	back.theme = T.get_theme()
	back.text = "  ←  Back to %s   (%s)  " % [back_to, Keys.label("back").get_slice(" / ", 0)]
	_back_btn = back
	back.position = Vector2(24, 24)
	back.pressed.connect(close)
	add_child(back)


func _fill_panel(p: Dictionary, house: Dictionary, editing := false) -> void:
	for c in _panel.get_children():
		_panel.remove_child(c)  # out of the card's measure at once, so it shrinks to what's new
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
	# As tall as everything in it once the words have wrapped, up to the screen's
	# height; it measures again whenever its content grows.
	v.minimum_size_changed.connect(func(): _fit_panel(scroll, v))
	_fit_panel.call_deferred(scroll, v)
	# Their arms beside their name: a lesser family's own, their liege's smaller.
	var family := _family(p, house)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	v.add_child(head)
	if not family.is_empty():
		head.add_child(_arms(family, Color.WHITE, 40))
	var liege := _arms(house, preload("res://scripts/heraldry.gd").colour(house, Color.GRAY, "#888").lerp(Color.WHITE, 0.25), 40 if family.is_empty() else 22)
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
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head_row := HBoxContainer.new()  # the house line, and Edit at its end: the name below gets the full width
	names.add_child(head_row)
	head_row.add_child(hl)
	var title := T.title(String(p.get("name", "")), 24)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF  # one line beside Edit
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	# Their first name is yours to change: Edit turns the name itself into the
	# field, full width; Enter keeps it, Esc leaves it. The realm keeps its own
	# underneath, and every page and line uses yours.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	names.add_child(title_row)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if rename_name.is_valid():
		var own := String(p.get("key", p.get("name", ""))).get_slice(" ", 0)
		var first := String(p.get("name", "")).get_slice(" ", 0)
		var rest := String(p.get("name", "")).substr(first.length())
		var edit_b := Button.new()
		edit_b.text = "Edit"
		edit_b.flat = true
		edit_b.focus_mode = Control.FOCUS_NONE
		edit_b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		edit_b.add_theme_color_override("font_color", T.TEXT_3)
		edit_b.add_theme_font_size_override("font_size", T.SIZE_DESC)
		head_row.add_child(edit_b)
		var field := LineEdit.new()
		field.visible = false
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", 22)
		field.text = first
		field.placeholder_text = "Their first name"
		names.add_child(field)
		var shut := func():
			field.visible = false
			title_row.visible = true
		edit_b.pressed.connect(func():
			title_row.visible = false
			field.visible = true
			field.grab_focus()
			field.select_all())
		field.gui_input.connect(func(e: InputEvent):
			if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
				shut.call()
				field.accept_event())
		field.text_submitted.connect(func(t: String):
			var to := t.strip_edges()
			rename_name.call(own, "" if to == own else to, func(code, d):
				if code == 200:
					title.text = (to if to != "" else own) + rest
					shut.call()
					name_changed.emit()
				else:
					field.text = String(d.get("error", "That name won't do.")) if d is Dictionary else "That name won't do."))
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
	if editing:
		_editor(v, p, house)
		return
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
	if not p.get("backstory") and p.get("story"):
		p = p.duplicate()
		p["backstory"] = p["story"]  # the book as written calls their past their story
	if p.get("backstory"):
		v.add_child(T.label("Their story"))
		v.add_child(_para(String(p["backstory"])))
	var change := Button.new()
	change.text = "Change who they are"
	change.flat = true
	change.focus_mode = Control.FOCUS_NONE
	change.add_theme_color_override("font_color", T.ACCENT)
	# The card turns into its own editor: their story, what they remember, their
	# nature, their loyalty. From the menu it rewrites the starting cast.
	change.pressed.connect(func(): _fill_panel(p, house, true))
	change.visible = save_person.is_valid()
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


## Who they are, open to rewrite: their story, what they remember, their nature
## and their loyalty. Save keeps it; Cancel leaves them as they were.
func _editor(v: VBoxContainer, p: Dictionary, house: Dictionary) -> void:
	v.add_child(T.label("Their story"))
	var story := TextEdit.new()
	story.text = String(p.get("backstory", p.get("story", ""))) if (p.get("backstory") or p.get("story")) else ""
	story.placeholder_text = "Where they come from, what they lost, whom they hate"
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.custom_minimum_size.y = 110
	v.add_child(story)
	v.add_child(T.label("Remembers"))
	var mems := VBoxContainer.new()
	mems.add_theme_constant_override("separation", 6)
	v.add_child(mems)
	var add_mem := func(text: String) -> void:
		var r := HBoxContainer.new()
		var e := LineEdit.new()
		e.text = text
		e.placeholder_text = "Something they'll never forget"
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(e)
		var x := Button.new()
		x.text = "×"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = "Forget this"
		x.pressed.connect(func(): r.queue_free())
		r.add_child(x)
		mems.add_child(r)
	var seen: Array = []
	for m in p.get("memories", []):
		if not seen.has(m):
			seen.append(m)
			add_mem.call(String(m))
	var more := Button.new()
	more.text = "+  Add a memory"
	more.flat = true
	more.focus_mode = Control.FOCUS_NONE
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	more.add_theme_color_override("font_color", T.ACCENT)
	more.pressed.connect(func():
		if mems.get_child_count() < 8:
			add_mem.call(""))
	v.add_child(more)
	v.add_child(T.label("Nature (up to four)"))
	var picked: Array = (p.get("traits", []) as Array).duplicate()
	var natures := HFlowContainer.new()
	natures.add_theme_constant_override("h_separation", 6)
	natures.add_theme_constant_override("v_separation", 6)
	v.add_child(natures)
	if trait_options.is_valid():
		trait_options.call(func(opts):
			var all: Array = opts.get("traits", []) if opts is Dictionary else []
			picked = picked.filter(func(t): return all.has(t))
			for t in all:
				var b := Button.new()
				b.text = String(t).capitalize()
				b.toggle_mode = true
				b.focus_mode = Control.FOCUS_NONE
				b.button_pressed = picked.has(t)
				b.toggled.connect(func(on):
					if on and not picked.has(t):
						if picked.size() >= 4:
							b.set_pressed_no_signal(false)
							return
						picked.append(t)
					elif not on:
						picked.erase(t))
				if is_instance_valid(natures):
					natures.add_child(b))
	v.add_child(T.label("Loyalty to their liege"))
	var loyalty := HSlider.new()
	loyalty.min_value = 0
	loyalty.max_value = 100
	loyalty.value = int(p.get("loyalty", 50))
	v.add_child(loyalty)
	var note := T.label("")
	note.visible = false
	v.add_child(note)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.flat = true
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.pressed.connect(func(): _fill_panel(p, house))
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Save"
	save.focus_mode = Control.FOCUS_NONE
	save.add_theme_color_override("font_color", T.ACCENT)
	row.add_child(save)
	save.pressed.connect(func():
		var memories: Array = []
		for r in mems.get_children():
			if not r.is_queued_for_deletion():
				var t := String((r.get_child(0) as LineEdit).text).strip_edges()
				if t != "":
					memories.append(t)
		var spec := {"id": str(p.get("id", "")), "backstory": story.text.strip_edges(), "past": story.text.strip_edges(),
			"memories": memories, "traits": picked, "loyalty": int(loyalty.value)}
		save.disabled = true
		save_person.call(p, spec, func(code, d):
			save.disabled = false
			if code == 200:
				var now := p.duplicate()
				now["backstory"] = spec["backstory"]
				now["story"] = spec["backstory"]
				now["memories"] = memories
				if not picked.is_empty():
					now["traits"] = picked
				now["loyalty"] = spec["loyalty"]
				_fill_panel(now, house)
				name_changed.emit()
			else:
				note.text = String(d.get("error", "That didn't save.")) if d is Dictionary else "That didn't save."
				note.visible = true))


## The card as tall as what it says, up to the screen's height (then it scrolls).
func _fit_panel(scroll: ScrollContainer, v: Control) -> void:
	if not is_instance_valid(v) or not v.is_inside_tree():
		return
	var room := get_viewport().get_visible_rect().size.y - 48.0 - 52.0
	scroll.custom_minimum_size.y = minf(v.get_combined_minimum_size().y, room)
	_panel.reset_size()


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


