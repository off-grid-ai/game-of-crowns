extends Node
## The microphone, for speaking to people instead of typing: a muted bus that
## records whatever it hears (Godot's own AudioEffectRecord). start(), then
## finish() hands back a WAV to send to the bridge, which turns it into words.

var _rec: AudioEffectRecord
var _player: AudioStreamPlayer


func listening() -> bool:
	return _rec != null and _rec.is_recording_active()


func start() -> void:
	if _rec == null:
		var bus := AudioServer.bus_count
		AudioServer.add_bus(bus)
		AudioServer.set_bus_name(bus, "Mic")
		AudioServer.set_bus_mute(bus, true)  # recorded, never played back
		_rec = AudioEffectRecord.new()
		AudioServer.add_bus_effect(bus, _rec)
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = "Mic"
		add_child(_player)
	_player.play()
	_rec.set_recording_active(true)


## Stop listening; the WAV bytes of what was said (empty if nothing was).
func finish() -> PackedByteArray:
	if not listening():
		return PackedByteArray()
	_rec.set_recording_active(false)
	_player.stop()
	var took := _rec.get_recording()
	if took == null:
		return PackedByteArray()
	var path := OS.get_user_data_dir() + "/speech.wav"
	took.save_to_wav(path)
	return FileAccess.get_file_as_bytes(path)
