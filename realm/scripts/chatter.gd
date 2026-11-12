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
		if _probe and villagers.has_method("talk_counts"):
			var tc: Dictionary = villagers.talk.talk_counts(int(id))
			for k in tc:
				_counts[k] = int(_counts.get(k, 0)) + int(tc[k])
		for g in villagers.talk.gatherings(int(id)):
			_count("talking")
			var key := "%d:%d" % [int(id), int(g["key"])]
			if _playing.has(key) or Time.get_ticks_msec() - int(_asked.get(key, -60000)) < 45000:
				continue
			if _distance(g, cam) > HEAR:
				_count("too far")
				continue
			if not _in_view(g, cam):
				_count("out of view")
				continue
			_count("asked")
			_asked[key] = Time.get_ticks_msec()
			_ask(int(id), g, key)
	_report()


## Test aid (--crowdprobe): where overheard talk goes, every five seconds:
## gatherings talking near the camera, too far to hear, out of view, asked
## for words, and lines shown (the minds' own, or plain words).
var _probe := OS.get_cmdline_user_args().has("--crowdprobe")
var _counts := {}
var _counts_at := 0


func _count(what: String) -> void:
	if _probe:
		_counts[what] = int(_counts.get(what, 0)) + 1


func _report() -> void:
	_counts_at += 1
	if not _probe or _counts_at % 5 != 0:
		return
	print("CHECK talk heard: %s" % _counts)
	_counts = {}


## Every one of them on screen: nobody talks from behind a wall or the camera.
func _in_view(g: Dictionary, cam: Camera3D) -> bool:
	for n in g["nodes"]:
		if not is_instance_valid(n) or not (n as Node3D).is_visible_in_tree() or not cam.is_position_in_frustum((n as Node3D).global_position + Vector3(0, HEAD, 0)):
			return false
	return true


# --- what's on a person's mind (the hover over someone in the street) ---------

## A thought of their own, by what the town is going through (topic) and who
## they are (group): plain words, never addressed to anyone. {king} is the
## King's name where the realm knows it.
const MIND_LINES := {
	"war": {
		"common": ["Three lads went with the levy. Not a word from any of them.", "If the war comes up this road, the barn goes first.", "Salt pork and nails dearer every week. That's the war."],
		"soldier": ["Two nights on the wall, and the third coming.", "Every man on this watch counts the road, not the hours.", "The captain says they'll not come this far. Captains say that."],
		"clergy": ["Prayers for the levy at every bell.", "War fills the sept and empties the plate."],
		"gentry": ["The levy takes the best hands just when the fields want them.", "A war is a bill, and it comes due in the spring."],
		"child": ["Wat says he saw a knight with a red horse.", "We play at sieges now. I'm always the wall."],
	},
	"riot": {
		"common": ["They'll hang someone for this. Pray it's not a neighbour.", "Bread first, then shouting. That's how it always goes.", "Keep the shutters closed till it's over."],
		"soldier": ["Hold the door, keep the blade sheathed. Easier said.", "Half that crowd bought me ale last month."],
		"clergy": ["Anger does the devil's work for him.", "Someone must speak for them, before the watch does."],
		"gentry": ["The steward pushed too hard. Now everyone pays.", "Mobs forget fast. Ledgers don't."],
		"child": ["Mam says stay in. Everyone's shouting in the square."],
	},
	"hunger": {
		"common": ["One loaf, cut thin, to last till market.", "The granary keys hang at the steward's belt, and he eats.", "Nettle soup again."],
		"soldier": ["Short rations for the watch too. Nobody's fooled."],
		"clergy": ["The alms box is empty, and the line is longer.", "Feed them first. Sermons after."],
		"gentry": ["Grain's dear in every town this side of the river.", "Open the stores, or they'll open them for us."],
		"child": ["My belly sounds like a dog."],
	},
	"grief": {
		"common": ["Buried him on Tuesday. Still set his bowl out by habit.", "Too many black ribbons on the doors this year.", "Light a candle, say a name, get back to work."],
		"soldier": ["Good man. Should have been me on that post."],
		"clergy": ["Another name for the bell.", "The dead are easy. It's the widows who need the sept."],
		"gentry": ["The family will need help with the land now.", "A town feels a death in its markets for a season."],
		"child": ["Everyone's quiet at supper now."],
	},
	"feast": {
		"common": ["Ale on the crown's coin. Drink before they change their minds.", "First fat goose this year, and the whole street smelt it.", "Somebody fetch the piper, he's asleep under the cart."],
		"soldier": ["One cup. On watch after.", "Feasts are when the fights start. Keep an eye out."],
		"clergy": ["A good feast. Tomorrow the confessions.", "Joy is a kind of prayer too."],
		"gentry": ["A feast keeps a town sweet for a season.", "Someone counted the barrels. I hope it wasn't the steward."],
		"child": ["There's honey cakes! Real ones!"],
	},
	"king": {
		"common": ["{king} rode through once. Didn't stop.", "They say {king} keeps a fair court. They would say that.", "Tithe's up again, and {king}'s banner on every wagon."],
		"soldier": ["Sworn to {king}, paid by the steward, fed by nobody."],
		"clergy": ["God keep {king}, and keep {king} honest."],
		"gentry": ["{king}'s favour moves like weather. Best keep a cloak.", "Letters from {king}'s court want more than they say."],
		"child": ["Is {king} very tall? I bet he is."],
	},
	"winter": {
		"common": ["Woodpile's half what it should be.", "Ice on the well again. Took the axe to it.", "Cold enough to crack the ale."],
		"soldier": ["Frost on the spear by dawn."],
		"clergy": ["The cold takes the old ones first. Visit them."],
		"gentry": ["A long winter empties every cellar."],
		"child": ["The pond's frozen right across!"],
	},
	"harvest": {
		"common": ["Barley's in. Three wet days and it would have rotted.", "Every back in town aches this week.", "Good straw this year. Thatch before the rain."],
		"soldier": ["Harvest. Half the watch is in the fields."],
		"clergy": ["Tithe sheaves at the sept door by sundown."],
		"gentry": ["A fair yield, if the price holds.", "Count the carts twice."],
		"child": ["I found a nest in the barley."],
	},
	"everyday": {
		"common": ["The cart wheel needs a new rim before market.", "Rain by evening, by the look of it.", "Somebody's goat was in the cabbages again.", "Two pennies for a bad knife. Never again."],
		"soldier": ["Quiet day. Quiet days make a man nervous.", "Boots need mending, and the cobbler's drunk."],
		"clergy": ["The roof of the sept leaks over the third bench.", "Fewer at prayers when the sun's out."],
		"gentry": ["Rents are due at Michaelmas, and half of them are late.", "The mill needs a new stone."],
		"child": ["I can throw a stone over the well.", "Wat owes me a marble."],
	},
}
## Who reads which lines: the callings and stations a person can have, by group.
const MIND_GROUPS := {"pious": "clergy", "clergy": "clergy", "soldier": "soldier", "knight": "soldier", "archer": "soldier",
	"gentry": "gentry", "noble": "gentry", "child": "child"}
## What a person is called on the hover when the realm has no trade for them yet.
const CALLINGS := {"farmer": "farmer", "market": "market trader", "pious": "lay sister", "tavern": "tavern hand", "keeper": "shopkeeper",
	"gentry": "gentleman", "child": "child", "crafter": "craftsman", "idler": "idler", "soldier": "man of the watch", "knight": "knight",
	"archer": "archer", "noble": "noble", "clergy": "friar", "townsfolk": "townsman", "peasant": "peasant"}
## How long a line they spoke in a talk (the minds' own words) stays on their mind.
const SAID_FRESH_MS := 300000
const NEWS_FRESH_MS := 90000  # as FindPartner: news older than this isn't on their mind

var _trades := {}  # town id -> {villager index: trade}, from the bridge's /townsfolk
var _trades_asked := {}  # town id -> true once asked
var _said_by := {}  # person instance id -> {text, ms}: the last thing the minds had them say
var _better := {}  # person instance id -> Callable: who wants their own words when they come


## What's on someone's mind, for the hover over them: {trade, line}, at once.
## The line is the minds' own words when they've lately spoken (overheard
## talk), else a plain line from MIND_LINES by what the town is going through
## and who they are. `better`, if given, is called with a new {trade, line}
## when the minds put words in their mouth later.
func mind_line(person: Node3D, better := Callable()) -> Dictionary:
	if person == null or not is_instance_valid(person):
		return {}
	var who: Dictionary = villagers.who_is(person) if villagers and villagers.has_method("who_is") else {}
	var role := String(who.get("role", person.get_meta("role", "")))
	var town := int(who.get("town", _town_of(person)))
	var trade := String(CALLINGS.get(role, "townsman"))
	if who.has("i"):
		trade = String(_trades.get(town, {}).get(int(who["i"]), trade))
		_ask_trades(town)
	var pid := person.get_instance_id()
	if better.is_valid():
		_better[pid] = better
	var said: Dictionary = _said_by.get(pid, {})
	if not said.is_empty() and Time.get_ticks_msec() - int(said["ms"]) < SAID_FRESH_MS:
		return {"trade": trade, "line": said["text"], "own": true}
	var topic := _topic_of(person, town)
	var group := String(MIND_GROUPS.get(role, "common"))
	var lines: Array = MIND_LINES[topic].get(group, MIND_LINES[topic]["common"])
	var line: String = lines[hash(pid) % lines.size()]  # the same person keeps the same thought
	return {"trade": trade, "line": line.replace("{king}", _king_of(person)), "own": false, "topic": topic}


## What the person is thinking about: news they saw or heard (their mind's
## memory), else what their town is going through, else the season.
func _topic_of(person: Node3D, town: int) -> String:
	var mind := person.get_node_or_null("Mind")
	if mind and "blackboard" in mind:
		for m in mind.blackboard.get_var(&"memory", [], false):
			if Time.get_ticks_msec() - int(m.get("ms", 0)) < NEWS_FRESH_MS:
				var by_tone := {"hostile": "war", "trouble": "hunger", "grief": "grief", "joy": "feast", "crown": "king"}
				var t := String(by_tone.get(SceneKinds.tone(String(m.get("kind", ""))), ""))
				if t != "":
					return t
	var c: Dictionary = towns.towns.get(town, {}).get("data", {}) if towns else {}
	if c.get("disorder", false):
		return "riot"
	if c.get("famine", false):
		return "hunger"
	if c.get("atWar", false):
		return "war"
	if c.get("grief", false):
		return "grief"
	if c.get("celebrating", false):
		return "feast"
	if c.get("grasping", false):
		return "king"
	var season := String(villagers.terrain.season) if villagers and "terrain" in villagers and villagers.terrain else ""
	if season == "winter":
		return "winter"
	if season == "autumn":
		return "harvest"
	return "everyday"


func _king_of(person: Node3D) -> String:
	var mind := person.get_node_or_null("Mind")
	var k := String(mind.blackboard.get_var(&"king_name", "", false)) if mind and "blackboard" in mind else ""
	return k if k != "" else "the King"


## The town a person stands in: theirs as a villager, or the one whose Life holds them.
func _town_of(person: Node3D) -> int:
	if towns == null:
		return -1
	for id in towns.towns:
		var node: Node3D = towns.towns[id].get("node")
		if is_instance_valid(node) and node.is_ancestor_of(person):
			return int(id)
	return -1


## Each townsperson's trade, asked of the bridge once per town.
func _ask_trades(town: int) -> void:
	if town < 0 or _trades_asked.has(town) or bridge == null:
		return
	_trades_asked[town] = true
	bridge.townsfolk(town, func(_code, data):
		if not data is Dictionary:
			_trades_asked.erase(town)  # ask again next time
			return
		var out := {}
		for f in data.get("folk", []):
			out[int(f.get("i", -1))] = String(f.get("trade", ""))
		_trades[town] = out)


## The minds had `speaker` say `text` (a talk the model wrote): on their mind now.
func _heard(speaker: Node3D, text: String) -> void:
	var pid := speaker.get_instance_id()
	_said_by[pid] = {"text": text, "ms": Time.get_ticks_msec()}
	var cb: Callable = _better.get(pid, Callable())
	if cb.is_valid():
		_better.erase(pid)
		cb.call(mind_line(speaker))


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
	if bridge == null:
		_own_words(town, g, key)
		return
	bridge.minds_chatter(town, who, func(_code, data):  # a failed send answers (0, null): their own words
		if _playing.has(key):
			return  # plain words already said: these keep for the next time they meet
		if data is Array:
			for talk in data:
				if talk is Dictionary and not _played.has(talk.get("id", "")) and _same(talk.get("who", []), g["who"]):
					_played[talk["id"]] = true
					_play(town, g, key, talk)
					return
		_own_words(town, g, key))
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
	for g in villagers.talk.gatherings(town):
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
		if talk.has("id") and text.length() >= 20:
			_heard(speaker, text)  # the minds' own words: what's on their mind now
		_count("lines (minds)" if talk.has("id") else "lines (plain)")
		var secs := clampf(1.2 + text.length() * 0.05, 2.5, 4.5)  # a few seconds each: overheard, not a subtitle
		if villagers.has_method("give_floor"):
			villagers.talk.give_floor(town, int(g["key"]), i, secs + 0.6)
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
