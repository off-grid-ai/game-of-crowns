extends RefCounted
## The realm paused, said where he looks (Mac 2026-11-16: "it keeps pausing on its own ... it doesn't explain it or
## represent the pause properly"; RimWorld's and Total War's pause: the word PAUSED on screen, and why). A small glass
## card at the top middle while the realm holds: "Paused", the reason (the matter that stopped it, when the realm
## stopped for him; chronicle_panel.gd _wait_for_him sets ui.pause_why), and how to go on (answer it, or the pause
## key). Gone the moment the realm moves. It decides nothing: ui.paused is the one owner. Words, never colour alone.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const Keys := preload("res://scripts/keys.gd")

var ui: Node
var _panel: PanelContainer
var _why: Label
var _how: Label


func _init(owner: Node) -> void:
	ui = owner


func _build() -> void:
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", T._box(T.SURFACE, T.HAIRLINE, 10, 12))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = float(Data.num("ui", "pause_note.at", 0.08))
	_panel.anchor_bottom = _panel.anchor_top
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.visible = false
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", T.GAP_TIGHT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(col)
	var head := T.label("Paused", T.TEXT)
	head.add_theme_font_size_override("font_size", int(Data.num("ui", "pause_note.size", 18)))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	_why = T.label("", T.TEXT_2)
	_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_why)
	_how = T.label("", T.TEXT_3)
	_how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_how)
	ui.add_child(_panel)


func update() -> void:
	if _panel == null:
		return
	_panel.visible = bool(ui.paused)
	if not _panel.visible:
		return
	var why := String(ui.get("pause_why"))
	_why.text = why
	_why.visible = why != ""
	_how.text = ("Answer it, or press %s to go on." if why != "" else "Press %s to go on.") % Keys.label("pause").get_slice(" / ", 0)
