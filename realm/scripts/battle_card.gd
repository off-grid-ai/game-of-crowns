extends Node
## The King's battle, when it is over: a result card (CK3's battle summary; casebook, War and sieges: the battle reads at
## a glance). Where and when, each side under its arms with its men and its losses and what it fielded, and who won,
## told once in the bottom-left corner (UI.md: what just happened), over the ticker, for host_command.json
## result.show_s seconds; a click puts it away. It decides nothing: the cards are the bridge's (battles.js), read
## from the view's one mirror (awareness.gd battles). A card the realm already had when the view came up is not told.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")
const Awareness := preload("res://scripts/awareness.gd")
const FILE := "host_command"

var main: Node
var _seen := {}  # card id -> true: told, or there before the view came up
var _primed := false
var _card: PanelContainer
var _t := 0.0
var _until := 0.0


func _init(m: Node) -> void:
	main = m
	name = "BattleCard"


func _process(delta: float) -> void:
	_t += delta
	if _card and _card.visible and Time.get_ticks_msec() / 1000.0 > _until:
		_put_away()
	if _t < 1.0:
		return
	_t = 0.0
	var store: Node = Awareness.store()
	if store == null or main.ui == null:
		return
	var cards: Array = store.battles()
	if not _primed:
		if store.rec("cities", []).is_empty():
			return  # the realm isn't read yet
		_primed = true
		for c in cards:
			_seen[String(c.get("id", ""))] = true
		return
	for c in cards:  # newest first: the newest untold one is told
		var id := String(c.get("id", ""))
		if id == "" or _seen.has(id):
			continue
		_seen[id] = true
		_show(c)
		return


## The card for one battle: "Victory at Redmarch" (gold) or "Defeat near Redmarch" (red), its season, then a row a side.
func _show(c: Dictionary) -> void:
	if _card:
		_card.queue_free()
	var words: Dictionary = Data.value(FILE, "result", {})
	var won := String(c.get("crown", "")) == "won"
	_card = main.ui.glass_panel()
	_card.anchor_left = 0.0
	_card.anchor_right = 0.0
	_card.anchor_top = 1.0
	_card.anchor_bottom = 1.0
	_card.grow_horizontal = Control.GROW_DIRECTION_END
	_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_card.offset_left = 12
	_card.offset_bottom = -float(words.get("above", 96))  # over the ticker
	_card.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 10, 10))
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_put_away())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_TIGHT)
	_card.add_child(v)
	var head := T.datum(String(words.get("head_won" if won else "head_lost", "{place}")).format({"place": String(c.get("place", ""))}), T.SIZE_TITLE - 4, T.ACCENT if won else T.DANGER)
	v.add_child(head)
	v.add_child(T.label(String(c.get("date", "")), T.TEXT_3))
	var houses: Dictionary = main._houses
	for s in c.get("sides", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", T.GAP)
		var house: Dictionary = houses.get(int(s.get("house", -1)), {})
		if not house.is_empty():
			row.add_child(main.ui.sigil_icon(house, 22))
		var who := VBoxContainer.new()
		who.add_theme_constant_override("separation", 0)
		var name_l := T.datum(String(s.get("name", "")), T.SIZE_DESC, T.TEXT)
		if int(s.get("house", -1)) == int(c.get("victor", -2)):
			name_l.text += "  " + String(words.get("victor", "held the field"))
		who.add_child(name_l)
		var kinds: Array = s.get("kinds", [])
		if not kinds.is_empty():
			who.add_child(T.label(", ".join(kinds.map(func(k): return String(k))), T.TEXT_3))
		row.add_child(who)
		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gap.custom_minimum_size.x = 24
		row.add_child(gap)
		row.add_child(T.datum(String(words.get("men", "{men} troops")).format({"men": main.ui.heads(int(s.get("men", 0)))}), T.SIZE_DESC, T.TEXT_2))
		var lost := T.datum(String(words.get("lost", "-{lost}")).format({"lost": main.ui.heads(int(s.get("lost", 0)))}), T.SIZE_DESC, T.DANGER if int(s.get("lost", 0)) > 0 else T.TEXT_3)
		row.add_child(lost)
		v.add_child(row)
	# The King's captains who fell there, by name (War, Every soldier has a name: Battle Brothers' fallen; bridge
	# captains.js: the card's fell).
	var fell: Array = c.get("fell", []) if c.get("fell") is Array else []
	if not fell.is_empty():
		var names := ", ".join(fell.map(func(n): return String(words.get("captain", "Captain {name}")).format({"name": String(n)})))
		var line := T.label(String(words.get("fell", "Fallen: {names}")).format({"names": names}), T.DANGER)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = 260
		v.add_child(line)
	main.ui.add_child(_card)
	_until = Time.get_ticks_msec() / 1000.0 + float(words.get("show_s", 14.0))
	_card.modulate.a = 0.0
	_card.create_tween().tween_property(_card, "modulate:a", 1.0, 0.3)


func _put_away() -> void:
	if _card == null:
		return
	var c := _card
	_card = null
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 0.0, 0.4)
	tw.tween_callback(c.queue_free)
