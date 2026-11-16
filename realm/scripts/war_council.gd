extends RefCounted
## The war council: the one screen before the King declares war (docs/WAR.md step 1; EU4's declare-war screen, CK3's
## call to arms; Mac 2026-11-16: "going to war is a big thing and should be treated as such"). Every war order (the
## town card's, the houses table's, the Hand's) opens it instead of going straight out: who rides with him, who waits,
## who joins the foe, and with how many companies; the two hosts' sums and the odds; what it costs now and each
## season it runs; what it adds to the realm's alarm; what winning takes. Declare war (rightmost) sends the order;
## Not now puts it away. It keeps nothing of the realm's: everything is the bridge's council (war.js council, on
## /world players[].warCouncil), read from the one mirror. Owned by ui.gd; words: realm/data/ui.json war_council.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui.gd")
const Awareness := preload("res://scripts/awareness.gd")

var ui: UI
var _panel: PanelContainer
var _body: VBoxContainer
var _go: Callable


func _init(owner: UI) -> void:
	ui = owner


func _build() -> void:
	_panel = ui.glass_panel()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.card(_panel)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", T.GAP)
	_panel.add_child(_body)


func _w(key: String, fallback: String) -> String:
	return String(Data.value("ui", "war_council." + key, fallback))


## Opens the council on war against the house holding `city`; `go` sends the order when the King declares. When the
## realm has no council for that house (the crown's own, a house already at war), the order goes as it is.
func ask(city: int, go: Callable) -> void:
	var st: Node = Awareness.store()
	var owner := -1
	for c in st.rec("cities", []):
		if int(c.get("id", -2)) == city:
			owner = int(c.get("owner", -1))
	var p: Dictionary = {}
	for pl in st.rec("players", []):
		if int(pl.get("id", -2)) == owner:
			p = pl
	var k = p.get("warCouncil")
	if _panel == null or not (k is Dictionary):
		go.call()
		return
	_go = go
	_fill(String((p.get("house", {}) as Dictionary).get("name", p.get("name", ""))).replace("House ", ""), k, st)
	_panel.visible = true
	ui.ease_in(_panel)
	ui.fit_centre(_panel, Data.num("ui", "war_council.width", 640.0))
	_panel.reset_size()
	_panel.position.y = round((ui.get_viewport().get_visible_rect().size.y - _panel.size.y) * 0.45)


func _fill(foe: String, k: Dictionary, st: Node) -> void:
	for c in _body.get_children():
		c.queue_free()
	var head := T.label(_w("title", "War on {foe}").replace("{foe}", foe), T.TEXT)
	head.add_theme_font_size_override("font_size", int(Data.num("ui", "war_council.title_size", 24.0)))
	_body.add_child(head)
	# The odds, in a captain's words, and the two hosts as they would likely stand.
	var odds: String = ui.town_card._forecast(float(k.get("odds", 0.5))) if k.get("odds") != null else ""
	_line(_w("odds", "{odds}: {ours} companies with you against {theirs}").replace("{odds}", (odds.left(1).to_upper() + odds.substr(1)) if odds != "" else "The odds are unknown").replace("{ours}", str(int(k.get("ours", 0)))).replace("{theirs}", str(int(k.get("theirs", 0)))), T.TEXT)
	# The sides: three columns, every great house in one, the likely told from the possible in words.
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", T.GAP_WIDE)
	_body.add_child(cols)
	for side in [["crown", _w("with", "With you")], ["wait", _w("waits", "Waits")], ["foe", _w("against", "Against you")]]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(T.label(String(side[1]).to_upper(), T.DANGER if side[0] == "foe" else T.TEXT_3))
		var any := false
		for x in k.get("sides", []):
			if String(x.get("side", "")) != side[0]:
				continue
			any = true
			var said := String(x.get("house", ""))
			if side[0] != "wait":
				said += "  ·  %d %s" % [int(x.get("men", 0)), _w("companies", "companies")]
				said += "  ·  " + (_w("likely", "likely") if bool(x.get("likely", false)) else _w("may", "may"))
			var l := T.label(said, T.TEXT)
			col.add_child(l)
			var why := T.label(String(x.get("why", "")), T.TEXT_3)
			col.add_child(why)
		if not any:
			col.add_child(T.label(_w("none", "No house"), T.TEXT_3))
		cols.add_child(col)
	# The cost: now, each season it runs (rising with each war on), and the alarm toward a league.
	var price := int((st.rec("crown", {}).get("decrees", {}) as Dictionary).get("war", {}).get("cost", 0)) if st.rec("crown") is Dictionary else 0
	_line(_w("cost", "{price} now, then {upkeep} a season while it runs").replace("{price}", ui.crowns(price)).replace("{upkeep}", ui.crowns(int(k.get("upkeep", 0)))), T.TEXT)
	var al: Dictionary = k.get("alarm", {}) if k.get("alarm") is Dictionary else {}
	var after := int(al.get("now", 0)) + int(al.get("adds", 0))
	var near := after >= int(al.get("at", 100))
	_line(_w("alarm", "The realm's alarm rises {from} to {to} of {at}; at {at} the houses league against you").replace("{from}", str(int(al.get("now", 0)))).replace("{to}", str(after)).replace("{at}", str(int(al.get("at", 100)))) + ("  ·  " + _w("league", "a league will form") if near else ""), T.DANGER if near else T.TEXT_2)
	_line(_w("goal", "To win, take their {towns} towns one by one, the seat last. Lose, and they ask a town of you.").replace("{towns}", str(int(k.get("towns", 0)))), T.TEXT_2)
	# Not now, then Declare war: the rightmost is the order (UI.md: the button we want pressed stands right).
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", T.GAP)
	_body.add_child(row)
	row.add_child(ui.btn(_w("not_now", "Not now"), func(): _close()))
	var gate: Dictionary = ui.act_gate({"action": "war", "cost": price})
	var declare := ui.btn(_w("declare", "Declare war") + String(gate.get("suffix", "")), func():
		_close()
		if _go.is_valid():
			_go.call())
	declare.disabled = not bool(gate.get("enabled", true))
	declare.tooltip_text = String(gate.get("why", ""))
	T.primary(declare)
	row.add_child(declare)
	if declare.disabled:
		_line(String(gate.get("why", "")), T.DANGER)


func _line(text: String, tone: Color) -> void:
	var l := T.label(text, tone)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(l)


func _close() -> void:
	ui.ease_out(_panel, func(): _panel.visible = false)
