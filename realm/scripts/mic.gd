extends Node
## The microphone, for talking to people hands-free. In a conversation it
## listens all the time: it notices when you start speaking, waits for you to
## finish (a moment of quiet), and hands over what you said as a WAV, which the
## bridge turns into words. While the other person answers it holds still, so
## it never hears their voice and mistakes it for yours. Godot's own blocks: a
## muted bus with AudioEffectCapture (to hear the level) and AudioEffectRecord.

signal utterance(wav: PackedByteArray)  # you said something and stopped
signal state_changed(state: String)  # "listening" | "hearing" | "waiting" | "off"

static var SPEECH: float = preload("res://scripts/data.gd").num("ui", "mic.speech", 0.02)  # level (RMS) above which it's you talking (ui.json mic.speech)
static var QUIET_FOR: float = preload("res://scripts/data.gd").num("ui", "mic.quiet_for", 0.9)  # seconds of quiet that end what you're saying (ui.json mic.quiet_for)
static var SHORTEST: float = preload("res://scripts/data.gd").num("ui", "mic.shortest", 0.35)  # anything briefer is a cough, not words (ui.json mic.shortest)

var state := "off"
var _rec: AudioEffectRecord
var _cap: AudioEffectCapture
var _player: AudioStreamPlayer
var _quiet := 0.0
var _spoke := 0.0


## Listen, hands-free, until stop().
func listen() -> void:
	_ensure()
	if not _player.playing:
		_player.play()
	_become("listening")


## Hold still (they're answering); listen() again when they're done.
func hold() -> void:
	if _rec and _rec.is_recording_active():
		_rec.set_recording_active(false)
	if state != "off":
		_become("waiting")


func stop() -> void:
	hold()
	if _player:
		_player.stop()
	_become("off")


func _process(delta: float) -> void:
	if _cap == null:
		return
	var level := 0.0
	var frames := _cap.get_frames_available()
	if frames > 0:
		var buf := _cap.get_buffer(frames)
		var sum := 0.0
		for f in buf:
			sum += f.x * f.x + f.y * f.y
		level = sqrt(sum / (2.0 * frames))
	match state:
		"listening":
			if level > SPEECH:
				_rec.set_recording_active(true)
				_spoke = 0.0
				_quiet = 0.0
				_become("hearing")
		"hearing":
			_spoke += delta
			_quiet = _quiet + delta if level < SPEECH * 0.6 else 0.0
			if _quiet >= QUIET_FOR:
				_rec.set_recording_active(false)
				if _spoke - _quiet >= SHORTEST:
					var wav := _wav()
					_become("waiting")
					if not wav.is_empty():
						utterance.emit(wav)
				else:
					_become("listening")


func _ensure() -> void:
	if _rec != null:
		return
	var bus := AudioServer.bus_count
	AudioServer.add_bus(bus)
	AudioServer.set_bus_name(bus, "Mic")
	AudioServer.set_bus_mute(bus, true)  # recorded, never played back
	_cap = AudioEffectCapture.new()
	AudioServer.add_bus_effect(bus, _cap)
	_rec = AudioEffectRecord.new()
	AudioServer.add_bus_effect(bus, _rec)
	_player = AudioStreamPlayer.new()
	_player.stream = AudioStreamMicrophone.new()
	_player.bus = "Mic"
	add_child(_player)


func _wav() -> PackedByteArray:
	var took := _rec.get_recording()
	if took == null:
		return PackedByteArray()
	var path := OS.get_user_data_dir() + "/speech.wav"
	took.save_to_wav(path)
	return FileAccess.get_file_as_bytes(path)


func _become(s: String) -> void:
	if s != state:
		state = s
		state_changed.emit(s)
