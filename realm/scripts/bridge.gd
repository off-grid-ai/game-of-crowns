extends Node
## Talks to the bridge (bridge/server.js): polls the world and the chronicle,
## and sends god commands and speed changes.

signal map_loaded(map: Dictionary)
signal world_updated(world: Dictionary)
signal chronicle_added(entries: Array)
signal command_done(ok: bool, text: String)
signal realm_changed
signal decrees_changed(list: Array)

var _reign_id := ""

const BASE := "http://127.0.0.1:8787"

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


func _poll() -> void:
	if not _map_loaded:
		_http_get("/map", _on_map)
	_http_get("/world", _on_world)
	_http_get("/chronicle?since=%d" % _last_seq, _on_chronicle)


func god(action: String, city_id: int, building := "") -> void:
	var body := {"action": action, "city": city_id}
	if building != "":
		body["building"] = building
	_post("/god", body, func(code, data):
		command_done.emit(code == 200, data.get("text", data.get("error", ""))))


func decree(action: String, city_id: int, building := "", to := -1) -> void:
	var body := {"action": action, "city": city_id}
	if building != "":
		body["building"] = building
	if to >= 0:
		body["to"] = to
	_post("/decree", body, func(code, data):
		command_done.emit(code == 200, data.get("text", data.get("error", ""))))


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


func rule_in_words(id: String, words: String, cb: Callable) -> void:
	_post("/court/say", {"id": id, "words": words}, cb)


func talk(city: int, i: int, you: Dictionary, said: String, cb: Callable) -> void:
	_post("/talk", {"city": city, "i": i, "you": you, "said": said}, cb)


func person_fell(id: String, how: String, cb: Callable) -> void:
	_post("/person/fall", {"id": id, "how": how}, cb)


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


func person(id: String, cb: Callable) -> void:
	_http_get("/person?id=%s" % id.uri_encode(), cb)


func court(cb: Callable) -> void:
	_http_get("/court", cb)


func answer_petition(id: String, option: String) -> void:
	_post("/court/answer", {"id": id, "option": option}, func(code, data):
		command_done.emit(code == 200, data.get("text", data.get("error", ""))))


func set_tithe(rate: float) -> void:
	_post("/tithe", {"rate": rate}, func(_c, _d): pass)


func list_chronicles(cb: Callable) -> void:
	_http_get("/chronicles", cb)


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
	map_loaded.emit(data)


func _on_world(data) -> void:
	var rid := String(data.get("reign", {}).get("id", ""))
	if _reign_id != "" and rid != "" and rid != _reign_id:
		# A different chronicle is now running: start over with its map and story.
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
	world_updated.emit(data)


func _on_chronicle(data) -> void:
	if data is Array and data.size() > 0:
		_last_seq = int(data[-1]["seq"])
		chronicle_added.emit(data)
