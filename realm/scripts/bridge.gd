extends Node
## Talks to the bridge (bridge/server.js): polls the world and the chronicle,
## and sends the King's decrees and speed changes.

signal map_loaded(map: Dictionary)
signal world_updated(world: Dictionary)
signal chronicle_added(entries: Array)
signal command_done(ok: bool, text: String)
signal realm_changed
signal decrees_changed(list: Array)
signal paid(cost: float)  # a decree went through and the treasury paid for it
signal sealed  # a decree took one of the King's royal seals (bridge seals.js)
signal ordered(city_id: int, matter: String)  # an order leaves the King's hand, before the realm answers (juice: the seal is heard at the click)

var _reign_id := ""

## The bridge's address: 8787, or another (--bridge=http://127.0.0.1:8850) for a
## film or a check run against a bridge of its own.
static var BASE: String = _base()


static func _base() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bridge="):
			return a.substr(9)
	return "http://127.0.0.1:8787"

var world: Dictionary = {}
var _last_seq := 0
var _map_loaded := false
var _busy := {}


func _ready() -> void:
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	timer.timeout.connect(_poll)
	add_child(timer)
	_poll()


## Asleep while the title menu is up: the map isn't loaded, so no land, towns
## or people are built or drawn until a chronicle is chosen. The world's
## summary still comes in (it's cheap, and the menu needs the reign for Continue).
var active := true


func wake() -> void:
	if not active:
		active = true
		_poll()


func _poll() -> void:
	if active and not _map_loaded:
		_http_get("/map", _on_map)
	_http_get("/world", _on_world)
	if active:
		_http_get("/chronicle?since=%d" % _last_seq, _on_chronicle)


func decree(action: String, city_id: int, building := "", to := -1, matter := "") -> void:
	ordered.emit(city_id, matter)
	var body := {"action": action, "city": city_id}
	if matter != "":
		body["matter"] = matter  # the court matter it answers: one request, a ruling (bridge routes_decree.js)
	if building != "":
		body["building"] = building
	if to >= 0:
		body["to"] = to
	_post("/decree", body, func(code, data):
		if code == 200 and float(data.get("cost", 0)) > 0:
			paid.emit(float(data["cost"]))
		if code == 200 and data.get("sealed", false):
			sealed.emit()
		command_done.emit(code == 200, data.get("text", data.get("error", ""))))


## The King's answer to the event card (bridge events.js): cb(ok, text).
func event_answer(choice: int, cb: Callable) -> void:
	_post("/event/answer", {"choice": choice}, func(code, data):
		cb.call(code == 200, String(data.get("text", data.get("error", "")))))


func set_mood(text: String) -> void:
	_post("/mood", {"text": text}, func(code, data):
		decrees(func(list): decrees_changed.emit(list))
		command_done.emit(code == 200, String(data.get("summary", data.get("error", "The mood is cleared.")))))


func decrees(cb: Callable) -> void:
	_http_get("/mood", cb)


func revoke_decree(id: String, cb: Callable) -> void:
	_post("/mood/revoke", {"id": id}, func(_c, d): cb.call(d if d is Array else []))


func character_options(cb: Callable) -> void:
	_http_get("/characters/options", cb)


## What you said into the microphone, as words (Off Grid's Whisper, via the bridge).
func reign_options(cb: Callable) -> void:
	_http_get("/reign/options", cb)


func set_reign_options(changes: Dictionary, cb: Callable) -> void:
	_post("/reign/options", changes, cb)


func counsel_answered(key: String) -> void:
	_post("/counsel/answer", {"key": key}, func(_c, _d): pass)


func ai_status(cb: Callable) -> void:
	_http_get("/ai", cb)


func hear(wav: PackedByteArray, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, resp):
		req.queue_free()
		var data = JSON.parse_string(resp.get_string_from_utf8())
		cb.call(data if data is Dictionary else {"error": "nothing was heard"}))
	req.request_raw(BASE + "/hear", ["Content-Type: audio/wav"], HTTPClient.METHOD_POST, wav)


## Someone's words spoken aloud (Off Grid's Kokoro, via the bridge): a ready
## AudioStream, or null if there's no voice to be had.
func voice(text: String, who: Dictionary, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, bytes):
		req.queue_free()
		cb.call(AudioStreamWAV.load_from_buffer(bytes) if code == 200 and bytes.size() > 44 else null))
	req.request(BASE + "/voice", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify({"text": text, "who": who}))


func rule_in_words(id: String, words: String, confirm: String, cb: Callable) -> void:
	_post("/court/say", {"id": id, "words": words, "confirm": confirm}, cb)


## Speak to someone: a townsperson (i, their place in the town's folk) or a
## named lord, lady or bannerman (person, their id).
## said "" with greet: they've just been approached and speak first.
func talk(city: int, i: int, you: Dictionary, said: String, cb: Callable, person := "", greet := false) -> void:
	var body := {"city": city, "i": i, "you": you, "said": said, "greet": greet}
	if person != "":
		body["person"] = person
	_post("/talk", body, cb)


func town_people(city: int, cb: Callable) -> void:
	_http_get("/town/people?city=%d" % city, cb)


func person_fell(id: String, how: String, cb: Callable) -> void:
	_post("/person/fall", {"id": id, "how": how}, cb)


## Someone of the starting cast rewritten from the menu's Lore (kept on this Mac).
func write_person(spec: Dictionary, cb: Callable) -> void:
	_post("/lore/written/person", spec, cb)


func edit_character(spec: Dictionary, cb: Callable) -> void:
	_post("/person", spec, cb)


func create_character(spec: Dictionary, cb: Callable) -> void:
	_post("/characters", spec, cb)


func folk(city: int, i: int, cb: Callable) -> void:
	_http_get("/townsfolk?city=%d&i=%d" % [city, i], cb)


func ledger(cb: Callable) -> void:
	_http_get("/ledger", cb)


func house(id: int, cb: Callable) -> void:
	_http_get("/house?id=%d" % id, cb)


## The v2 opening (docs/review/first-ten-minutes-plan.md): the King has landed in
## his realm ("realm"), so its first court may sit (the bridge's court.js waits for this).
func opening(at: String) -> void:
	_post("/reign/opening", {"at": at}, func(_c, _d): pass)


## A reign whose clock ran out goes on, endless, in the same realm.
func continue_reign(cb: Callable) -> void:
	_post("/reign/continue", {}, cb)


func lore(cb: Callable) -> void:
	_http_get("/lore", cb)


## Give a house or a person a name of the player's own (from: their own word,
## to: the player's; empty gives it back). The reply is every name given.
func rename(from: String, to: String, cb: Callable) -> void:
	_post("/names", {"from": from, "to": to}, func(c, d): cb.call(c, d))


## The player's own names for houses and people: {inner word: shown word}.
func names(cb: Callable) -> void:
	_http_get("/names", func(d): cb.call(d.get("names", {}) if d is Dictionary else {}))


## The book as written: the starting cast, read from the baseline realm.
func lore_written(cb: Callable) -> void:
	_http_get("/lore?as=written", cb)


## Aldmere as every new chronicle finds it: its towns and their houses, for the Lore's map.
func lore_map(cb: Callable) -> void:
	_http_get("/lore/map", cb)


## The realm map as the reign stands: towns as held now, hosts, sieges.
func realm_map(cb: Callable) -> void:
	_http_get("/lore/map?live=1", cb)


func person(id: String, cb: Callable) -> void:
	_http_get("/person?id=%s" % id.uri_encode(), cb)


func court(cb: Callable) -> void:
	_http_get("/court", cb)


## The King has read an act's interlude: the realm goes on.
func close_interlude() -> void:
	_post("/interlude/close", {}, func(_c, _d): pass)


## Closes the court: what the King left settles itself; cb gets what still stands (nothing).
func close_court(cb: Callable) -> void:
	_post("/court/close", {}, func(_c, d): cb.call(d if d is Array else []))


func answer_petition(id: String, option: String) -> void:
	_post("/court/answer", {"id": id, "option": option}, func(code, data):
		command_done.emit(code == 200, data.get("text", data.get("error", ""))))


func set_tithe(rate: float) -> void:
	_post("/tithe", {"rate": rate}, func(_c, _d): pass)


## A story of the player's own, from tags, a few lines, or both (see /stories/generate).
func generate_story(tags: Array, words: String, cb: Callable) -> void:
	_post("/stories/generate", {"tags": tags, "words": words}, func(c, d): cb.call(c, d))


## A story of the player's own for the beat form: its roles, the menus of when
## and what, and the beats added so far.
func own_story(id: String, cb: Callable) -> void:
	_http_get("/stories/own?id=%s" % id.uri_encode(), cb)


## One beat of the player's own added to their story ({text, who, when, does}),
## or taken out ({remove: id}). The reply is the story as own_story gives it.
## Off Grid AI fills or carries on a free-text box of the given kind.
func write_for(kind: String, context: String, draft: String, cb: Callable) -> void:
	_post("/write", {"kind": kind, "context": context, "draft": draft}, func(c, d): cb.call(c, d))


## Off Grid AI writes a story's premise from tags (draft empty), or carries the draft on.
func premise_idea(tags: Array, draft: String, cb: Callable) -> void:
	_post("/stories/premise/idea", {"tags": tags, "draft": draft}, func(c, d): cb.call(c, d))


## Off Grid AI writes a beat for the story (draft empty), or carries the draft on.
func beat_idea(id: String, draft: String, cb: Callable) -> void:
	_post("/stories/beat/idea", {"story": id, "draft": draft}, func(c, d): cb.call(c, d))


func story_beat(id: String, beat: Dictionary, cb: Callable) -> void:
	var b := beat.duplicate()
	b["story"] = id
	_post("/stories/beat", b, func(c, d): cb.call(c, d))


## The stories a reign can be told by (arc files marked "reign"), each with its tags.
func stories(cb: Callable) -> void:
	_http_get("/arcs/templates", func(d):
		var out := []
		if d is Array:
			for t in d:
				if t is Dictionary and t.get("reign", false) and (t.get("problems", []) as Array).is_empty():
					out.append(t)
		cb.call(out))


func list_chronicles(cb: Callable) -> void:
	_http_get("/chronicles", cb)


## Save now (saves as reigns): Freeciv writes the realm to the reign's saves, and its card with it. cb(code, d).
func save_chronicle(cb: Callable) -> void:
	_post("/chronicles/save", {}, cb)


## A reign taken off the list (put aside by the bridge, not erased; never the one in play). cb(code, d).
func delete_chronicle(id: String, cb: Callable) -> void:
	_post("/chronicles/delete", {"id": id}, cb)


## The King steps down for his grown heir (bridge royals.js abdicate): cb(code, d), 409 with an error when he can't.
func abdicate(cb: Callable) -> void:
	_post("/abdicate", {}, cb)


## The King eases his stress (bridge royals.js rest): kind hunt | feast | pilgrimage; cb(code, d), 409 with why.
func king_rest(kind: String, cb: Callable) -> void:
	_post("/king/rest", {"kind": kind}, cb)


## The King says who he means to be, once a crowning (bridge royals.js setFocus): war, court, faith or coin.
func king_focus(focus: String, cb: Callable) -> void:
	_post("/king/focus", {"focus": focus}, cb)


func records(cb: Callable) -> void:
	_http_get("/records", cb)


func create_chronicle(name: String, scenario: String, minutes: int, fate := "normal", wealth := "comfortable", mood := "", options := {}, cb := Callable()) -> void:
	_post("/chronicles", {"name": name, "scenario": scenario, "minutes": minutes, "fate": fate, "wealth": wealth, "mood": mood, "options": options}, func(c, d):
		if cb.is_valid():
			cb.call(c, d))


func scenarios(cb: Callable) -> void:
	_http_get("/scenarios", cb)


func save_scenario(spec: Dictionary, cb: Callable) -> void:
	_post("/scenarios", spec, cb)


func open_chronicle(id: String) -> void:
	_post("/chronicles/open", {"id": id}, func(_c, _d): pass)


func set_paused(on: bool) -> void:
	_post("/pause" if on else "/resume", {}, func(_c, _d): pass)


func end_reign() -> void:
	_post("/reign/end", {}, func(_c, _d): pass)


func set_speed(seconds: int) -> void:
	_post("/speed", {"seconds": seconds}, func(_c, _d): pass)


func _http_get(path: String, cb: Callable) -> void:
	var key := path.split("?")[0]
	if _busy.get(key, false):
		return
	_busy[key] = true
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, body):
		_busy[key] = false
		req.queue_free()
		if code == 200 or (code == 503 and key == "/world"):
			var data = JSON.parse_string(body.get_string_from_utf8())
			if data != null:
				cb.call(data))
	req.request(BASE + path)


## The King's grain, gold or rider reached its town: the bridge credits it.
func scene_arrived(s: Dictionary) -> void:
	_post("/scene/arrived", {"kind": s.get("kind", ""), "city": s.get("city", -1), "label": s.get("label", ""), "sent": s.get("at", 0)}, func(_c, _d): pass)


## A fire arrow or a sack's spread set one of a town's houses alight (fire.gd): the town's damage fact keeps it
## burnt (bridge damage.js kindled), through a reload, till the realm rebuilds it.
func kindled(city: int, home: String) -> void:
	_post("/scene/kindled", {"city": city, "home": home}, func(_c, _d): pass)


## The townsfolk's minds (bridge/minds.js), asked for by the town's people and their talk: the view's one client
## asks, so no view holds an HTTPRequest of its own. Each callback gets (code, data); data is null on a failure.

## Each townsperson of a town and their trade.
func townsfolk(city: int, cb: Callable) -> void:
	_ask_minds("/townsfolk?city=%d" % city, {}, 10.0, cb)


## The minds' talk for exactly these people (the model may take a while on its first call).
func minds_chatter(city: int, who: PackedStringArray, cb: Callable) -> void:
	_ask_minds("/minds/chatter?city=%d&who=%s&wait=1" % [city, ",".join(who)], {}, 90.0, cb)


## A town's plan for the hour: who is where (bridge/minds.js).
func minds_town(city: int, hour: int, cb: Callable) -> void:
	_ask_minds("/minds/town?city=%d&hour=%d" % [city, hour], {}, 5.0, cb)


## The King is looking at these townsfolk: their minds wake first.
func minds_attention(body: Dictionary) -> void:
	_ask_minds("/minds/attention", body, 5.0, Callable())


## Townsfolk saw something happen: it goes into their memories.
func minds_witness(body: Dictionary) -> void:
	_ask_minds("/minds/witness", body, 5.0, Callable())


func _ask_minds(path: String, body: Dictionary, secs: float, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = secs
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, bytes):
		req.queue_free()
		if cb.is_valid():
			cb.call(code, JSON.parse_string(bytes.get_string_from_utf8()) if code == 200 else null))
	var err := req.request(BASE + path) if body.is_empty() else req.request(BASE + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		req.queue_free()
		if cb.is_valid():
			cb.call(0, null)


## A test hook of a film reign (X-Test: /test/court, /test/stage, /test/mark, /test/clock), its body as written:
## render_pass.sh's one run stages its views through it (autoplay.gd post). cb(code, text).
func test_hook(path: String, body: String, cb: Callable) -> void:
	var req := HTTPRequest.new()
	req.timeout = 30.0
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, resp):
		req.queue_free()
		cb.call(code, (resp as PackedByteArray).get_string_from_utf8()))
	req.request(BASE + path, ["Content-Type: application/json", "X-Test: 1"], HTTPClient.METHOD_POST, body)


func _post(path: String, body: Dictionary, cb: Callable) -> void:
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, resp):
		req.queue_free()
		var data = JSON.parse_string(resp.get_string_from_utf8())
		cb.call(code, data if data is Dictionary or data is Array else {}))
	req.request(BASE + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))


func _on_map(data) -> void:
	_map_loaded = true
	preload("res://scripts/perf_tools.gd").mark("bridge answered: map")
	map_loaded.emit(data)


func _on_world(data) -> void:
	var rid := String(data.get("reign", {}).get("id", ""))
	if _reign_id != "" and rid != "" and rid != _reign_id:
		# A different chronicle is now running: start over with its map and story.
		print("REALM CHANGED %s -> %s at %.1f s" % [_reign_id, rid, Time.get_ticks_msec() / 1000.0])
		_reign_id = rid
		_map_loaded = false
		_last_seq = 0
		world = {}
		realm_changed.emit()
		return
	_reign_id = rid
	if not data.has("turn"):
		return
	world = data
	preload("res://scripts/perf_tools.gd").mark("first /world")
	world_updated.emit(data)


func _on_chronicle(data) -> void:
	if data is Array and data.size() > 0:
		_last_seq = int(data[-1]["seq"])
		chronicle_added.emit(data)
