extends RefCounted
## Every key the game listens for, as Godot Input Map actions, so any of them
## can be changed in Settings → Controls. Defaults live here; your changes are
## kept in user://settings.cfg (section "keys") and applied at start.
## Use: Input.is_action_pressed(&"cam_left"), event.is_action_pressed(&"pause").

const PATH := "user://settings.cfg"

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
	["pace_walk", "Pace: walk", "The realm", [KEY_1]],
	["pace_ride", "Pace: ride", "The realm", [KEY_2]],
	["pace_gallop", "Pace: gallop", "The realm", [KEY_3]],
	["houses", "The great houses", "The realm", [KEY_H]],
	["chronicle", "The chronicle", "The realm", [KEY_C]],
	["ledger", "The ledger", "The realm", [KEY_L]],
	["court", "The court", "The realm", [KEY_K]],
	["lore", "The Lore of Aldmere", "The realm", [KEY_B]],
	["minimap", "Show or hide the minimap", "The realm", [KEY_M]],
	["back", "Close, step back", "The realm", [KEY_ESCAPE]],
	["walk_forward", "Walk forward", "Walking and fighting", [KEY_W, KEY_UP]],
	["walk_back", "Walk back", "Walking and fighting", [KEY_S, KEY_DOWN]],
	["walk_left", "Walk left", "Walking and fighting", [KEY_A, KEY_LEFT]],
	["walk_right", "Walk right", "Walking and fighting", [KEY_D, KEY_RIGHT]],
	["run", "Run (hold)", "Walking and fighting", [KEY_SHIFT]],
	["interact", "Talk, enter, mount", "Walking and fighting", [KEY_E]],
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
	return " / ".join(names)
