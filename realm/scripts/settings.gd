extends RefCounted
## This Mac's own preferences for the game (voices aloud, their volume, and the
## like), kept in user://settings.cfg. The reign's choices live with the
## chronicle in the bridge instead; these are just how you like to play.

const PATH := "user://settings.cfg"
const DEFAULTS := {"voices": true, "voice_volume": 0.85, "talk": "type", "seen_intro": false, "vol_master": 1.0, "vol_music": 0.7, "vol_ambience": 0.8, "vol_sfx": 0.8, "vol_ui": 0.4, "camera_pad": "near", "graphics": "smooth", "camera_speed": 1.0, "frame_rate": "off", "last_king": {}, "pause_when_needed": true, "hand_lessons": true}  # talk: "type" | "speak"; graphics: "smooth" | "beautiful"; camera_pad: "always" | "near" | "never"; frame_rate: "off" | "rate" | "details" (fps_meter.gd); hand_lessons: the Hand teaches as things first happen (off: only when called, the ? or F12); last_king: who you were in the last chronicle begun (title.gd: name, gender, age)

static var _cfg: ConfigFile


static func get_value(key: String) -> Variant:
	_load()
	if key == "graphics" and not _cfg.has_section_key("play", key):
		return graphics_default()
	return _cfg.get_value("play", key, DEFAULTS.get(key))


## How the realm is drawn until the player chooses, by the machine's tier (data/hardware.json tiers, first fit wins):
## Finest on a graphics card of its own (a PC's NVIDIA or AMD card draws a town at full 4K with every pass on, in under
## 10 ms) or a Mac's Max or Ultra chip, Beautiful on a Mac's Pro or plain chip with 16 GB, Smooth on anything less.
static func graphics_default() -> String:
	var name := RenderingServer.get_video_adapter_name()
	var discrete := RenderingServer.get_video_adapter_type() == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU
	var ram_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	for rule: Dictionary in preload("res://scripts/data.gd").value("hardware", "tiers", []):
		if rule.has("discrete") and bool(rule["discrete"]) != discrete:
			continue
		if rule.has("name_has") and not (rule["name_has"] as Array).any(func(w) -> bool: return name.contains(String(w))):
			continue
		if ram_gb < float(rule.get("min_ram_gb", 0.0)):
			continue
		return String(rule.get("preset", "smooth"))
	return "smooth"


static func set_value(key: String, value: Variant) -> void:
	_load()
	_cfg.set_value("play", key, value)
	_cfg.save(PATH)


static func _load() -> void:
	if _cfg == null:
		_cfg = ConfigFile.new()
		_cfg.load(PATH)  # a missing file is fine: everything has a default
