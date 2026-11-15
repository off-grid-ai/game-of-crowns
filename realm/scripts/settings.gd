extends RefCounted
## This Mac's own preferences for the game (voices aloud, their volume, and the
## like), kept in user://settings.cfg. The reign's choices live with the
## chronicle in the bridge instead; these are just how you like to play.

const PATH := "user://settings.cfg"
const DEFAULTS := {"voices": true, "voice_volume": 0.85, "talk": "type", "seen_intro": false, "vol_master": 1.0, "vol_music": 0.7, "vol_ambience": 0.8, "vol_sfx": 0.8, "vol_ui": 0.4, "camera_pad": "near", "graphics": "smooth", "camera_speed": 1.0, "frame_rate": "off", "last_king": {}, "pause_when_needed": true, "hand_lessons": true}  # talk: "type" | "speak"; graphics: "smooth" | "beautiful"; camera_pad: "always" | "near" | "never"; frame_rate: "off" | "rate" | "details" (fps_meter.gd); hand_lessons: the Hand teaches as things first happen (off: only when called, the ? or F1); last_king: who you were in the last chronicle begun (title.gd: name, gender, age)

static var _cfg: ConfigFile


static func get_value(key: String) -> Variant:
	_load()
	return _cfg.get_value("play", key, DEFAULTS.get(key))


static func set_value(key: String, value: Variant) -> void:
	_load()
	_cfg.set_value("play", key, value)
	_cfg.save(PATH)


static func _load() -> void:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)  # a missing file is fine: everything has a default
