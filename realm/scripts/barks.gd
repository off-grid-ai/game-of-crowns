extends Node
## Every click answers (docs/PLAN.md, fun audit item 2). Copies Warcraft II's unit replies and
## Stronghold's lords: click a house's sigil and its lord says one line in the mood their favour puts
## them in; keep clicking the same one and they get annoyed. The line shows at once as a caption with a
## quill's scratch (under 0.2 s), then is spoken aloud through the game's voices when they're on.
## The lines are data (realm/data/barks.json); this only picks one: never one of the last few said.


const Data := preload("res://scripts/data.gd")  # the one loader of realm/data (data.gd)
var main: Node
var _d := {}
var _recent: Array[String] = []
var _clicks := {}  # target -> [count, last click ms]


func _init(owner: Node) -> void:
	main = owner
	name = "Barks"


func _ready() -> void:
	var d := Data.read("barks")
	if not d.is_empty():
		_d = d


## A house's sigil clicked: its lord answers, by their favour band.
func lord(pid: int) -> void:
	for p in main.awareness.rec("players", []):
		if int(p["id"]) != pid:
			continue
		var house := String((p.get("house", {}) as Dictionary).get("name", "The lord"))
		var pool: Array = _d.get("annoyed", []) if _pestered("lord%d" % pid) else (_d.get("lord", {}) as Dictionary).get(str(p.get("band", "steady")), [])
		_say(house, pool, {"name": house})
		return


## The King's host chosen (kind "select") or given an order ("order"): its captain answers; chosen again and
## again, curt (barks.json host, host_annoyed). Called by host_command.gd.
func host(kind: String, id: int) -> void:
	if kind == "order":
		main.ui.guide_mark(4)  # the Hand's fifth step: a host sent on its way
	var pestered := kind == "select" and _pestered("host%d" % id)
	var lines = (_d.get("host", {}) as Dictionary).get(kind, [])
	if lines is Dictionary:  # chosen: by what the host is doing (its order's kind; at ease with none)
		var cmd: Node = main.get_node_or_null("HostCommand")
		var order = (cmd.host(id) if cmd else {}).get("order")
		var doing := String((order as Dictionary).get("kind", "ease")) if order is Dictionary else "ease"
		lines = (lines as Dictionary).get(doing, (lines as Dictionary).get("ease", []))
	var pool: Array = _d.get("host_annoyed", []) if pestered else (lines as Array)
	_say("The captain", pool, {"name": "The captain", "gender": "male"})


## A townsman clicked: they say what's on their mind (the line the hover shows), else a greeting;
## pestered, they'd rather get back to work.
func folk(node: Node3D, line: String, voice: Dictionary) -> void:
	var pestered := _pestered("folk%d" % node.get_instance_id())
	var pool: Array = _d.get("folk_annoyed", []) if pestered else ([line] if line != "" else _d.get("folk", []))
	_say(String(voice.get("name", "")) if voice.get("name", "") != "" else "A townsman", pool, voice, line != "" and not pestered)


## The same target clicked again within click_memory_sec counts up; past annoyed_after, it's annoyed.
func _pestered(target: String) -> bool:
	var now := Time.get_ticks_msec()
	var c: Array = _clicks.get(target, [0, 0])
	var n: int = (int(c[0]) + 1) if now - int(c[1]) < int(float(_d.get("click_memory_sec", 8)) * 1000.0) else 1
	_clicks[target] = [n, now]
	return n > int(_d.get("annoyed_after", 3))


func _say(who: String, pool: Array, voice: Dictionary, own := false) -> void:
	var fresh := pool if own else pool.filter(func(l): return not _recent.has(String(l)))  # their own thought is theirs to repeat
	if fresh.is_empty():
		fresh = pool
	if fresh.is_empty():
		return
	var line := String(fresh[randi() % fresh.size()])
	_recent.append(line)
	while _recent.size() > int(_d.get("no_repeat", 10)):
		_recent.pop_front()
	main.ui.caption("%s: %s" % [who, line])
	main.sound.ui("quill")
	main._say_aloud(line, voice)
