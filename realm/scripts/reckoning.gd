extends RefCounted
## What a choice changed, the moment it is made (Reigns' meters that move at the swipe, Frostpunk's consequence line;
## Mac 2026-11-16: "I can take any action and it doesn't feel like it's that impactful ... it's not very evident").
## A card centred over the control plane: one row for each thing the order or ruling moved, its name, from -> to, and
## the word for it ("much warmer", "15,000 spent", "the houses take fright"). Rows come in one after another, so each
## lands; the card holds while the mouse is on it, a click puts it away. Bad news reads in the loss colour and its word,
## never the colour alone (Mac is colour-blind). It keeps nothing of the realm's: the rows come whole from the bridge
## (bridge/reckoning.js) with the order's answer. Owned by ui.gd; words and timings: realm/data/ui.json reckoning.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI
var _panel: PanelContainer
var _grid: GridContainer
var _tw: Tween
var _head: Label
var _line: Label  # what came of an order, in the chronicle's words (aftermath); hidden for a choice's own answer


func _init(owner: UI) -> void:
	ui = owner


func _build() -> void:
	_panel = ui.glass_panel()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.mouse_entered.connect(func(): _hold())
	_panel.mouse_exited.connect(func(): _fade_later())
	_panel.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			_panel.visible = false)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", T.GAP)
	_panel.add_child(box)
	_head = T.label("", T.TEXT_3)
	box.add_child(_head)
	_line = T.label("", T.TEXT)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.custom_minimum_size.x = Data.num("ui", "reckoning.width", 460.0)
	box.add_child(_line)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", T.GAP_WIDE)
	_grid.add_theme_constant_override("v_separation", T.GAP_TIGHT)
	box.add_child(_grid)


## Shows the rows a choice moved ([{label, from, to, word, sign}]); nothing when it moved nothing. `said`: what came of
## an order seasons on (aftermath.js), headed "What came of it" with its line; empty for a choice's own answer.
func show(rows: Array, said := "") -> void:
	if _panel == null or (rows.is_empty() and said == ""):
		return
	_head.text = String(Data.value("ui", "reckoning.came" if said != "" else "reckoning.head", "What came of it" if said != "" else "What it changed")).to_upper()
	_line.text = said
	_line.visible = said != ""
	for c in _grid.get_children():
		c.queue_free()
	var size := int(Data.num("ui", "reckoning.size", 17.0))
	var cells: Array[Control] = []
	for r in rows.slice(0, int(Data.num("ui", "reckoning.most", 8.0))):
		if not r is Dictionary:
			continue
		var bad := int(r.get("sign", 0)) < 0
		var tone := T.DANGER if bad else T.TEXT
		var from := String(r.get("from", ""))
		for cell in [[String(r.get("label", "")), T.TEXT_2], [from + ("  →" if from != "" else ""), T.TEXT_3], [String(r.get("to", "")), tone], [String(r.get("word", "")), tone]]:
			var l := T.label(cell[0], cell[1])
			l.add_theme_font_size_override("font_size", size)
			l.modulate.a = 0.0
			_grid.add_child(l)
			cells.append(l)
	_grid.visible = not cells.is_empty()
	_panel.reset_size()
	_place()
	_panel.modulate.a = 1.0
	_panel.visible = true
	# Each row lands in turn (four cells a row), so the eye reads them as things happening, not a table.
	if _tw:
		_tw.kill()
	_tw = _panel.create_tween()
	var step := Data.num("ui", "reckoning.step", 0.18)
	for i in cells.size():
		_tw.parallel().tween_property(cells[i], "modulate:a", 1.0, 0.16).set_delay(step * float(i / 4))
	_tw.tween_interval(Data.num("ui", "reckoning.hold", 7.0))
	_tw.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tw.tween_callback(func(): _panel.visible = false)


## Centred over the control plane.
func _place() -> void:
	var vp := ui.get_viewport().get_visible_rect().size
	_panel.position = Vector2(round((vp.x - _panel.size.x) * 0.5), ui.plane.top_y() - _panel.size.y - 12.0)


func _hold() -> void:
	if _tw:
		_tw.kill()
	_panel.modulate.a = 1.0
	for c in _grid.get_children():
		(c as CanvasItem).modulate.a = 1.0


func _fade_later() -> void:
	if not _panel.visible:
		return
	_tw = _panel.create_tween()
	_tw.tween_interval(Data.num("ui", "reckoning.linger", 2.0))
	_tw.tween_property(_panel, "modulate:a", 0.0, 0.4)
	_tw.tween_callback(func(): _panel.visible = false)
