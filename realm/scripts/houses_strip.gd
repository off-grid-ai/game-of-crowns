extends RefCounted
## The great houses at a glance (Crusader Kings III's realm list, Total War's faction strip; Mac 2026-11-16: "who is
## gaining power, who is with me, and who is against me, then I can click on them for the full view"). Top-left, one
## chip a house, strongest first: its sigil, its stance toward the King in a word (Sworn, Loyal, Content, Cold, Angry,
## At war) and an arrow when its power is rising or falling. The word carries the meaning, never the colour alone.
## A click opens the house (the same as its name in the table). Hidden while the full table is open.
## It keeps nothing of the realm's: it reads the mirror's players (bridge view.js: favour, wars, sworn, power,
## powerTrend) when the world is read. Owned by ui.gd; words and sizes: realm/data/ui.json houses_strip.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui.gd")
const Awareness := preload("res://scripts/awareness.gd")
const Heraldry = preload("res://scripts/heraldry.gd")

var ui: UI
var _panel: PanelContainer
var _row: HBoxContainer
var _said := 0  # what the chips were last built from


func _init(owner: UI) -> void:
	ui = owner


func _build() -> void:
	_panel = ui.glass_panel()
	_panel.add_theme_stylebox_override("panel", T._box(T.SURFACE, T.HAIRLINE, 10, 4))
	_panel.offset_left = 10
	_panel.offset_top = Data.num("ui", "plane.top", 12.0)
	_panel.visible = false
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 2)
	_panel.add_child(_row)
	if ui._houses_panel:
		ui._houses_panel.visibility_changed.connect(_show)


## The chips brought in line with the houses: rebuilt only when what they show changed.
func fill() -> void:
	if _panel == null:
		return
	var players: Array = []
	for p in Awareness.store().rec("players", []):
		var h: Dictionary = p.get("house", {})
		if p.get("favour") != null and not h.get("wild", false) and int(p.get("cities", 0)) > 0:
			players.append(p)
	players.sort_custom(func(a, b): return int(a.get("power", 0)) > int(b.get("power", 0)))
	var sig := hash([players.map(func(p): return [p["id"], _stance(p), _arrow(p), p.get("power", 0)]), Awareness.bands])
	if sig != _said:
		_said = sig
		for c in _row.get_children():
			c.queue_free()
		var head := T.label(String(Data.value("ui", "houses_strip.head", "By power")), T.TEXT_3)
		head.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_row.add_child(head)
		for p in players:
			_row.add_child(_chip(p))
	_show()


func _show() -> void:
	if _panel == null:
		return
	_panel.visible = _row.get_child_count() > 1 and not ui.cinema_on and not (ui._houses_panel and ui._houses_panel.visible)
	_panel.size = Vector2.ZERO


## Where the house stands with the King, in a word: at war with him, sworn to him, or its mood (the bridge's bands).
func _stance(p: Dictionary) -> String:
	var w: Dictionary = Data.value("ui", "houses_strip.words", {})
	if (p.get("wars", []) as Array).has("the Crown"):
		return String(w.get("war", "At war"))
	if p.get("sworn") != null or String(p.get("band", "")) == "sworn":
		return String(w.get("sworn", "Sworn"))
	return ui.mood(int(p["favour"]))


## Its power over the last year: up, down, or holding (houses_strip.rise: the percent that counts as a move).
func _arrow(p: Dictionary) -> String:
	var t := int(p.get("powerTrend", 0))
	var rise := int(Data.num("ui", "houses_strip.rise", 10.0))
	return " ▲" if t >= rise else (" ▼" if t <= -rise else "")


## A house's chip: its sigil, name and stance, then its power (bridge power.js) with an arrow if it is moving
## (Mac 2026-11-16: "how do I know which one is more powerful?"); the strip says it runs by power, strongest first.
func _chip(p: Dictionary) -> Button:
	var h: Dictionary = p["house"]
	var name := String(h.get("name", p.get("name", ""))).trim_prefix("House ")
	var stance := _stance(p)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.icon = Heraldry.sigil(h)
	b.add_theme_constant_override("icon_max_width", int(Data.num("ui", "houses_strip.sigil", 20.0)))
	b.add_theme_font_size_override("font_size", int(Data.num("ui", "houses_strip.size", 14.0)))
	b.text = "%s · %s   %d%s" % [name, stance, int(p.get("power", 0)), _arrow(p)]  # its power as a number, the arrow beside it (Mac: the bar read as an underline)
	# Against the King reads red and loud, with him bright, the rest muted: the word says it first.
	var against := stance in [String(Data.value("ui", "houses_strip.words.war", "At war")), ui.mood(0)]
	b.add_theme_color_override("font_color", T.DANGER if against else (T.TEXT if stance in [String(Data.value("ui", "houses_strip.words.sworn", "Sworn")), "Loyal"] else T.TEXT_2))
	var t := int(p.get("powerTrend", 0))
	var tips: Dictionary = Data.value("ui", "houses_strip.tips", {})
	b.tooltip_text = String(tips.get("line", "House {name}: {stance}, favour {favour} of 100\nPower {power} of 100 (men, land, people, crowns and grain, against the strongest house), {trend} over the year\nClick for the house")).format({
		"name": name, "stance": stance, "favour": int(p["favour"]), "power": int(p.get("power", 0)),
		"trend": ("up %d%%" % t) if t > 0 else (("down %d%%" % -t) if t < 0 else "holding")})
	var owner := int(p["id"])
	b.pressed.connect(func():
		ui.focus_house.emit(owner)
		ui.house_opened.emit(owner))
	return b
