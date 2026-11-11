extends Node
## The opening's clock (a test aid, GOC_OPENING_CLOCK=<file>; off in play): the first ten minutes
## measured as a first-launch player lives them (docs/review/first-ten-minutes-plan.md). Each moment
## is logged once, with seconds since launch: each screen as it first shows (splash, menu, form,
## forging, storybook), the reign begun, the King landing in his realm, the first court matter
## waiting on the map, the court card up, the first ruling, its result, and the first map news after
## it. Inputs come from the live hand (GOC_HAND=<dir>, autoplay.gd), which clicks as a player would.
## It reads the game; it changes nothing.

var main: Node
var _out: FileAccess
var _seen := {}
var _ruled := false
var _news_before := {}


func _init(owner: Node) -> void:
	main = owner
	name = "OpeningClock"


func _ready() -> void:
	_out = FileAccess.open(OS.get_environment("GOC_OPENING_CLOCK"), FileAccess.WRITE)
	_mark("launch")
	main.title.began.connect(func(): _mark("reign begun"))
	main.intro.finished.connect(func(): _mark("landed (storybook over)"))
	main.ui.court_waits_at.connect(func(_a, c, _i): _mark("first matter waits on the map: " + String(c)))
	main.ui.petition_answered.connect(func(_i, _o): _ruled = true; _news_before = main.news._news.duplicate(); _mark("first ruling"))
	main.ui.counsel_answered.connect(func(_k): _ruled = true; _news_before = main.news._news.duplicate(); _mark("first ruling (the Hand's matter)"))
	main.bridge.command_done.connect(func(ok, text): if _ruled: _mark("first ruling's result: %s %s" % ["ok" if ok else "refused", String(text).left(80)]))


func _process(_delta: float) -> void:
	var splash := main.get_node_or_null("Splash")
	if splash and splash.is_visible_in_tree():
		_mark("screen: splash")
	if main.title.visible:
		_mark("screen: menu")
		if _label_up("The reign"):
			_mark("screen: new reign form")
		if _label_up("The realm is being forged"):
			_mark("screen: forging")
	if main.intro.visible:
		_mark("screen: storybook")
	if main.ui.visible and not main.title.visible and not main.intro.visible:
		_mark("in the realm (interface up)")
	if main.ui.court._court_panel.visible:
		_mark("court card up")
	if _ruled and not main.news._news.is_empty() and main.news._news != _news_before:
		_mark("map news after the ruling: " + String(main.news._news.get("caption", "")).left(80))


## Whether a visible label begins with these words.
func _label_up(words: String) -> bool:
	for l in main.title.find_children("*", "Label", true, false):
		if l.is_visible_in_tree() and String(l.text).begins_with(words):
			return true
	return false


func _mark(what: String) -> void:
	if _seen.has(what.get_slice(":", 0)):
		return
	_seen[what.get_slice(":", 0)] = true
	_out.store_line("%7.1f %s" % [Time.get_ticks_msec() / 1000.0, what])
	_out.flush()
