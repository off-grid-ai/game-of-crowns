extends RefCounted
## Every key the game listens for, as Godot Input Map actions, so any of them
## can be changed in Settings → Controls. Defaults live here; your changes are
## kept in user://settings.cfg (section "keys") and applied at start.
## Use: Input.is_action_pressed(&"cam_left"), event.is_action_pressed(&"pause").

const PATH := "user://settings.cfg"
## A mouse button in the defaults: this plus its button index (keys are below it).
const MOUSE := 1 << 24

## [action, what it does, group, default keys]
const ACTIONS := [
	["cam_up", "Move north", "Camera", [KEY_W, KEY_UP]],
	["cam_down", "Move south", "Camera", [KEY_S, KEY_DOWN]],
	["cam_left", "Move west", "Camera", [KEY_A, KEY_LEFT]],
	["cam_right", "Move east", "Camera", [KEY_D, KEY_RIGHT]],
	["cam_fast", "Move faster (hold)", "Camera", [KEY_SHIFT]],
	["cam_turn_left", "Turn left", "Camera", [KEY_Q]],
	["cam_turn_right", "Turn right", "Camera", [KEY_E]],
	["cam_tilt_up", "Look further out", "Camera", [KEY_R]],
	["cam_tilt_down", "Look down", "Camera", [KEY_F]],
	["home", "Back to Kingsmere", "Camera", [KEY_Z]],
	["pause", "Pause or resume the realm", "The realm", [KEY_SPACE]],
	["houses", "The great houses", "The realm", [KEY_H]],
	["chronicle", "The chronicle", "The realm", [KEY_C]],
	["ledger", "The ledger", "The realm", [KEY_L]],
	["court", "The court", "The realm", [KEY_K]],
	["counsel", "The court (the Hand speaks there)", "The realm", [KEY_J]],
	["lore", "The Lore of Aldmere", "The realm", [KEY_B]],
	["minimap", "Show or hide the minimap", "The realm", [KEY_M]],
	["walk_king", "Walk the realm as the King", "The realm", [KEY_G]],
	["back", "Close, step back", "The realm", [KEY_ESCAPE]],
	["walk_forward", "Walk forward", "Walking and fighting", [KEY_W, KEY_UP]],
	["walk_back", "Walk back", "Walking and fighting", [KEY_S, KEY_DOWN]],
	["walk_left", "Walk left", "Walking and fighting", [KEY_A, KEY_LEFT]],
	["walk_right", "Walk right", "Walking and fighting", [KEY_D, KEY_RIGHT]],
	["run", "Run (hold)", "Walking and fighting", [KEY_SHIFT]],
	["interact", "Talk, enter, mount", "Walking and fighting", [KEY_E]],
	["attack", "Strike (draws your weapon first)", "Walking and fighting", [MOUSE + MOUSE_BUTTON_LEFT]],
	["draw", "Draw or sheathe your weapon", "Walking and fighting", [KEY_TAB]],
	["block", "Block (hold)", "Walking and fighting", [KEY_SPACE]],
	["dodge", "Dodge (with left or right, else back)", "Walking and fighting", [KEY_X]],
	["turn_left", "Turn the view left", "Walking and fighting", [KEY_Q]],
	["turn_right", "Turn the view right", "Walking and fighting", [KEY_R]],
]


## Registers every action with its defaults, then your changes over them.
static func apply() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for a in ACTIONS:
		var name := StringName(a[0])
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		InputMap.action_erase_events(name)
		var keys: Array = cfg.get_value("keys", a[0], a[3])
		for k in keys:
			if int(k) >= MOUSE:
				var mb := InputEventMouseButton.new()
				mb.button_index = int(k) - MOUSE
				InputMap.action_add_event(name, mb)
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = int(k)
			InputMap.action_add_event(name, ev)


## Binds an action to one key (replacing its keys) and remembers it.
static func rebind(action: String, keycode: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("keys", action, [keycode])
	cfg.save(PATH)
	apply()


## Every action back to its default keys.
static func reset() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	if cfg.has_section("keys"):
		cfg.erase_section("keys")
	cfg.save(PATH)
	apply()


## The keys an action is on now, as you'd write them: "W / Up".
static func label(action: String) -> String:
	var names := []
	for ev in InputMap.action_get_events(StringName(action)):
		if ev is InputEventKey:
			names.append(OS.get_keycode_string(ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode))
		elif ev is InputEventMouseButton:
			names.append({MOUSE_BUTTON_LEFT: "Click", MOUSE_BUTTON_RIGHT: "Right-click", MOUSE_BUTTON_MIDDLE: "Middle-click"}.get(ev.button_index, "Mouse %d" % ev.button_index))
	return " / ".join(names)
