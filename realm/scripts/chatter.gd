extends Node3D
const PerfTools := preload("res://scripts/perf_tools.gd")  # the frame-cost probe
## What the townsfolk say to each other, overheard. When the camera comes
## close to a gathering in the street, the bridge's minds write their talk
## (bridge/chatter.js) and it plays here: each line a short caption over the
## speaker's head, in turn, the last fading as the next begins (and, when
## SPOKEN, aloud in that person's own voice, quieter further off).

const Settings := preload("res://scripts/settings.gd")

var villagers: Node3D  # villagers.gd: who stands in which gathering
var towns: Node3D
var bridge: Node  # bridge.gd, for its address and the voices
var sound: Node  # soundscape.gd: hushes the town while someone speaks

## Overheard talk is read, not heard, in v1 (VISION.md, release calls): set
## true to have each line spoken in the speaker's own voice when voices are on.
const SPOKEN := false
## Close enough to overhear: the camera within this of a gathering.
const HEAR := 2.6
## A talking town: its centre within this of the camera.
const TOWN_NEAR := 9.0
const CAPTION_PX := 13  # spoken words on screen, as UI.md sets small type
const SPEECH := preload("res://assets/fonts/EBGaramond-Italic.ttf")
const HEAD := 0.25  # a caption's height over the speaker's feet

var _asked := {}  # gathering key -> when its talk was asked for (msec)
var _playing := {}  # gathering key -> the talk being played
var _played := {}  # talk id -> true: never the same talk twice
var _tags: Array[Label3D] = []
var _check := 0.0
var _waiting: Array[HTTPRequest] = []  # talks asked for and not yet written
var _shot_on_talk := OS.get_cmdline_user_args().has("--chatter")
var _said := {}  # line set -> how many of it have been used: each set's lines in turn, never the same twice running

const SceneKinds := preload("res://scripts/scene_kinds.gd")
## How long a talk in view waits for the minds' words before plain words of
## its own are said instead: talk is never silent while the model warms up.
const OWN_WORDS_SECS := 5.0
## Plain words for when the minds have none: by the news the talk is about
## (its tone), or else by the gathering's kind. Each a short exchange, the
## speakers taking turns.
const OWN_WORDS := {
	"hostile": [
		["Riders on the east road at first light.", "Then bar the door tonight and keep the children in."],
		["They say the lord's men fell back.", "Fell back, or ran? Either way they're coming here.", "God keep us."],
		["Smoke over the hill since noon.", "That's a farm burning, not a field."],
	],
	"trouble": [
		["Bread's gone up again.", "Gone up? There's none to buy by midday."],
		["Two more sick on the lane.", "Keep your well bucket to yourself, then."],
		["The barrow's empty, same as last week.", "Same as the week before. Someone's eating well."],
	],
	"grief": [
		["They buried him this morning.", "He was a good man. Never owed a penny."],
		["Light a candle for her at the sept.", "I have. Twice."],
		["His wife won't come out of the house.", "Leave bread at the door. She'll take it in the night."],
	],
	"joy": [
		["There's ale at the square tonight!", "Then I'm not working past noon."],
		["Did you hear the piper?", "Heard him? I danced with his sister.", "Poor girl."],
		["A good year, this.", "Don't say it aloud. You'll wake the tax man."],
	],
	"crown": [
		["The King's banner went by.", "Did he look at us?", "He looked at the road."],
		["Wagons for the crown again.", "Our grain, their wagons."],
		["A rider from the King, bound north.", "Good news rides slower than that."],
	],
	"drink": [
		["Another one, and put it on the miller's slate.", "The miller will have your hide."],
		["To the harvest!", "To the harvest. And to it being over."],
		["This ale's half water.", "Then drink twice as much."],
	],
	"haggle": [
		["Three pennies for that? It's half rotten.", "Two, then, and you carry it yourself."],
		["Fresh this morning, I swear it.", "Which morning?"],
		["I'll give you a penny and my thanks.", "Your thanks won't feed my mule."],
	],
	"mutter": [
		["The steward took a third this year.", "A third? He took half from the Coopers."],
		["Keep your voice down.", "Why? They can't take more than all of it."],
		["Who sits on that throne, I ask you.", "Not one of us, that's who."],
	],
	"talk": [
		["Rain by evening, you'll see.", "My knee says the same."],
		["Your boy was at my apples again.", "Then your apples should taste worse."],
		["The well rope's fraying.", "Then don't be the one at the bottom of it."],
		["Have you seen the smith's new apprentice?", "I've heard him. All morning.", "He'll learn."],
		["Off to market?", "If my legs get me there."],
	],
}


func _process(delta: float) -> void:
	if not PerfTools.probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfTools.add("chatter", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	_follow()
	_check -= delta
	if _check > 0.0:
		return
	_check = 1.0
	var cam := get_viewport().get_camera_3d()
	if cam == null or villagers == null or not villagers.has_method("gatherings"):
		return
	for id in towns.towns:
		var node: Node3D = towns.towns[id]["node"]
		if not is_instance_valid(node) or node.global_position.distance_to(cam.global_position) > TOWN_NEAR:
			continue
		for g in villagers.gatherings(int(id)):
			var key := "%d:%d" % [int(id), int(g["key"])]
			if _playing.has(key) or Time.get_ticks_msec() - int(_asked.get(key, -60000)) < 45000:
				continue
			if _distance(g, cam) > HEAR or not _in_view(g, cam):
				continue
			_asked[key] = Time.get_ticks_msec()
			_ask(int(id), g, key)


## Every one of them on screen: nobody talks from behind a wall or the camera.
func _in_view(g: Dictionary, cam: Camera3D) -> bool:
	for n in g["nodes"]:
		if not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree() or not cam.is_position_in_frustum((n as Node3D).global_position + Vector3(0, HEAD, 0)):
			return false
	return true


## Nothing left hanging on the bridge when the game closes.
func _exit_tree() -> void:
	for req in _waiting:
		req.cancel_request()
	_waiting.clear()


func _distance(g: Dictionary, cam: Camera3D) -> float:
	var d := INF
	for n in g["nodes"]:
		if is_instance_valid(n):
			d = minf(d, (n as Node3D).global_position.distance_to(cam.global_position))
	return d


## The minds' talk for exactly these people (hot: they're in view).
func _ask(town: int, g: Dictionary, key: String) -> void:
	var who := PackedStringArray()
	for i in g["who"]:
		who.append(str(i))
	var req := HTTPRequest.new()
	req.timeout = 90.0
	add_child(req)
	_waiting.append(req)
	req.request_completed.connect(func(_r, code, _h, bytes):
		_waiting.erase(req)
		req.queue_free()
		if _playing.has(key):
			return  # plain words already said: these keep for the next time they meet
		var data = JSON.parse_string(bytes.get_string_from_utf8()) if code == 200 else null
		if data is Array:
			for talk in data:
				if talk is Dictionary and not _played.has(talk.get("id", "")) and _same(talk.get("who", []), g["who"]):
					_played[talk["id"]] = true
					_play(town, g, key, talk)
					return
		_own_words(town, g, key))
	if req.request(bridge.BASE + "/minds/chatter?city=%d&who=%s&wait=1" % [town, ",".join(who)]) != OK:
		_own_words(town, g, key)
		return
	# The minds may take a while (the model's first call loads it): not this talk's silence.
	get_tree().create_timer(OWN_WORDS_SECS).timeout.connect(func(): _own_words(town, g, key))


## Plain words of their own (OWN_WORDS), when the minds have none for them yet
## and the two are still talking where the camera can hear.
func _own_words(town: int, g: Dictionary, key: String) -> void:
	if not is_inside_tree() or _playing.has(key) or not _talking(town, int(g["key"])):
		return
	var topic := String(g.get("topic", ""))
	var set_name := SceneKinds.tone(topic) if topic != "" else ""
	if not OWN_WORDS.has(set_name):
		set_name = String(g.get("kind", "talk")) if OWN_WORDS.has(String(g.get("kind", ""))) else "talk"
	var sets: Array = OWN_WORDS[set_name]
	var n := int(_said.get(set_name, randi() % sets.size()))
	_said[set_name] = n + 1
	var who: Array = g["who"]
	var lines := []
	for k in (sets[n % sets.size()] as Array).size():
		lines.append({"who": int(who[k % who.size()]), "text": sets[n % sets.size()][k]})
	_play(town, g, key, {"lines": lines})


## Gathering `key` of the town is still going, everyone in it in place.
func _talking(town: int, key: int) -> bool:
	for g in villagers.gatherings(town):
		if int(g["key"]) == key:
			return true
	return false


func _same(a: Array, b: Array) -> bool:
	var x := a.map(func(v): return int(v))
	var y := b.map(func(v): return int(v))
	x.sort()
	y.sort()
	return x == y


## The lines in turn: each held long enough to read (or to be heard), then
## fading as the next speaker begins. Stops if the gathering breaks up.
func _play(town: int, g: Dictionary, key: String, talk: Dictionary) -> void:
	_playing[key] = talk
	var prev: Label3D = null
	for line in talk.get("lines", []):
		var i := int(line.get("who", -1))
		var at: int = Array(g["who"]).map(func(v): return int(v)).find(i)
		if at < 0 or not is_instance_valid(g["nodes"][at]) or not (g["nodes"][at] as Node3D).visible or not _talking(town, int(g["key"])):
			break
		var speaker: Node3D = g["nodes"][at]
		var text := String(line.get("text", ""))
		var secs := clampf(1.2 + text.length() * 0.05, 2.5, 4.5)  # a few seconds each: overheard, not a subtitle
		if villagers.has_method("give_floor"):
			villagers.give_floor(town, int(g["key"]), i, secs + 0.6)
		if prev:
			_fade(prev, 0.4)
		prev = _caption(speaker, text)
		if _shot_on_talk and talk["lines"].find(line) == 1:
			# Test aid (--shot ... --chatter): the picture is taken as the second line is read.
			_shot_on_talk = false
			get_tree().create_timer(1.0).timeout.connect(func(): get_parent().call("_take_shot"))
		var heard := await _speak(speaker, text, line)
		await get_tree().create_timer(maxf(0.3, secs - heard)).timeout
		if not is_inside_tree():
			return
	if prev:
		_fade(prev, 1.5)
	_playing.erase(key)


## Their words aloud, from where they stand, in their own voice. Returns the
## seconds already spent speaking (0 with voices off).
func _speak(speaker: Node3D, text: String, line: Dictionary) -> float:
	if not SPOKEN or not Settings.get_value("voices"):
		return 0.0
	var start := Time.get_ticks_msec()
	var got := [null]
	var done := [false]
	bridge.voice(text, {"name": line.get("name", ""), "gender": line.get("gender", "")}, func(stream):
		got[0] = stream
		done[0] = true)
	while not done[0] and Time.get_ticks_msec() - start < 12000:
		await get_tree().process_frame
	if got[0] == null or not is_instance_valid(speaker):
		return (Time.get_ticks_msec() - start) * 0.001
	var voice := AudioStreamPlayer3D.new()
	voice.stream = got[0]
	voice.bus = sound.voice_bus() if sound else "Master"
	voice.unit_size = 0.8  # full voice at arm's length, fading across a street
	voice.max_distance = HEAR * 2.0
	voice.volume_db = linear_to_db(maxf(0.01, float(Settings.get_value("voice_volume"))))
	speaker.add_child(voice)
	voice.position = Vector3(0, 0.2, 0)
	if sound:
		sound.voice_started()
	voice.play()
	await voice.finished
	if sound:
		sound.voice_ended()
	voice.queue_free()
	return (Time.get_ticks_msec() - start) * 0.001


## A caption over someone's head, lifted a line for each older caption close by.
func _caption(speaker: Node3D, text: String) -> Label3D:
	var tag := Label3D.new()
	tag.text = text
	# A whisper you notice (UI.md: 13 px; the world is the interface): the same
	# small size on screen at every zoom, the serif of spoken words, on a soft
	# dark backing so it reads over snow or shadow.
	tag.font = SPEECH
	tag.fixed_size = true
	tag.font_size = CAPTION_PX * 2  # drawn at twice the size, shown at CAPTION_PX: crisp
	tag.pixel_size = 0.5 / _px_per_unit()
	tag.outline_size = 14
	tag.width = 300.0
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = Color(0.98, 0.94, 0.84, 0.0)
	tag.outline_modulate = Color(0.06, 0.05, 0.04, 0.0)
	tag.set_meta("speaker", speaker)
	add_child(tag)
	_tags.append(tag)
	tag.tree_exiting.connect(func(): _tags.erase(tag))
	_follow()
	var tw := tag.create_tween().set_parallel()
	tw.tween_property(tag, "modulate:a", 1.0, 0.25)
	tw.tween_property(tag, "outline_modulate:a", 0.55, 0.25)
	return tag


func _fade(tag: Label3D, seconds: float) -> void:
	if not is_instance_valid(tag):
		return
	var tw := tag.create_tween().set_parallel()
	tw.tween_property(tag, "modulate:a", 0.0, seconds)
	tw.tween_property(tag, "outline_modulate:a", 0.0, seconds)
	tw.chain().tween_callback(tag.queue_free)


## Captions ride on their speakers' heads. Where one would cover an older one
## on screen (near or far, any gathering), it goes just above it, so none
## overprint.
func _follow() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var placed: Array[Rect2] = []
	for tag in _tags:
		var speaker = tag.get_meta("speaker")
		if not is_instance_valid(speaker):
			continue
		var at: Vector3 = (speaker as Node3D).global_position + Vector3(0, HEAD, 0)
		if cam.is_position_behind(at):
			tag.global_position = at
			continue
		# How many pixels a world unit spans at the speaker's depth.
		var base := cam.unproject_position(at)
		var px := absf(cam.unproject_position(at + Vector3(0, 1, 0)).y - base.y)
		# The caption's size on screen is fixed (fixed_size): its box in pixels.
		var on := tag.pixel_size * _px_per_unit()
		var w := tag.width * on
		var h := tag.font_size * 1.25 * on * _rows(tag)
		var box := Rect2(base.x - w * 0.5, base.y - h, w, h)
		var moved := true
		while moved:
			moved = false
			for r in placed:
				if box.intersects(r):
					box.position.y = r.position.y - h - 2.0
					moved = true
		placed.append(box)
		tag.global_position = at + Vector3(0, (base.y - box.end.y) / maxf(px, 0.001), 0)


## Screen pixels per world unit at one unit's distance (what fixed_size labels are drawn at).
func _px_per_unit() -> float:
	var cam := get_viewport().get_camera_3d()
	var fov := cam.fov if cam else 50.0
	return get_viewport().get_visible_rect().size.y / (2.0 * tan(deg_to_rad(fov) * 0.5))


func _rows(tag: Label3D) -> int:
	return maxi(1, ceili(tag.text.length() * tag.font_size * 0.5 / tag.width))
