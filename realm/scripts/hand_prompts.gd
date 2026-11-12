extends Node
## The Hand's prompts in a first reign (--opening=v2; docs/review/first-ten-minutes-plan.md item 5).
## Copies Against the Storm's envoy: a voice inside the world teaches, a few lines, each once, at the
## moment it matters, and never again after the first reign (Eremite: veterans skip the basics).
## The lines, their order and their moments are data (realm/data/opening.json): this only decides
## when each moment has come. It reads the realm (the store, awareness.gd) and the court's signals; it decides
## nothing about the realm itself.

const DATA := "res://data/opening.json"
const SEEN := "hand_prompts"  # settings.cfg section: which prompts this player has heard

var main: Node
var _prompts: Array = []
var _speaker := "The Hand"
var _due := {}  # prompt id -> seconds until it is spoken (once its moment has come)
var _said := {}  # prompt id -> true, kept in settings.cfg
var _landed := false
var _turning_seen := {}  # player id -> their turning when the King landed: a house turning since is news


func _init(owner: Node) -> void:
	main = owner
	name = "HandPrompts"


func _ready() -> void:
	var f := FileAccess.open(DATA, FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_prompts = d.get("prompts", [])
			_speaker = String(d.get("speaker", _speaker))
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	for p in _prompts:
		if bool(cfg.get_value(SEEN, String(p["id"]), false)):
			_said[String(p["id"])] = true
	var ui = main.get("ui")
	if ui:
		ui.court_waits_at.connect(func(_at, _c, _id): _moment("court_waits"))
		ui.petition_answered.connect(func(_id, _o): _moment("first_ruling"))
		ui.counsel_answered.connect(func(_k): _moment("first_ruling"))


## The King has landed in his realm (the intro's end): the clock for the first prompts starts.
func landed() -> void:
	_landed = true
	for p in main.awareness.rec("players", []):
		_turning_seen[int(p["id"])] = int(p.get("turning", 0))
	_moment("landed")


func _moment(on: String) -> void:
	if not _landed:
		return
	for p in _prompts:
		var id := String(p["id"])
		if String(p["on"]) == on and not _said.has(id) and not _due.has(id):
			_due[id] = float(p.get("after_sec", 0.0))


func _process(delta: float) -> void:
	if not _landed:
		return
	_watch_realm()
	for id in _due.keys():
		_due[id] = float(_due[id]) - delta
		if float(_due[id]) <= 0.0:
			_due.erase(id)
			_say(id)
			return  # one line at a time


## The realm's own moments: a house turning against the crown, the first winter.
func _watch_realm() -> void:
	if String(main.awareness.rec("date", {}).get("season", "")) == "winter":
		_moment("winter")
	for p in main.awareness.rec("players", []):
		if int(p.get("turning", 0)) > int(_turning_seen.get(int(p["id"]), 0)):
			_moment("house_turns")


func _say(id: String) -> void:
	for p in _prompts:
		if String(p["id"]) == id:
			main.ui.caption("%s: %s" % [_speaker, String(p["text"])])
	_said[id] = true
	if OS.get_environment("GOC_HAND") != "" or OS.get_environment("GOC_OPENING_CLOCK") != "":
		return  # a test run drives the game: the player's own profile keeps its first-reign prompts
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	cfg.set_value(SEEN, id, true)
	cfg.save("user://settings.cfg")
