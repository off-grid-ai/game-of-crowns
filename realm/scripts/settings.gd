extends RefCounted
## This Mac's own preferences for the game (voices aloud, their volume, and the
## like), kept in user://settings.cfg. The reign's choices live with the
## chronicle in the bridge instead; these are just how you like to play.

const PATH := "user://settings.cfg"
const DEFAULTS := {"voices": true, "voice_volume": 0.85, "mic": true}

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
