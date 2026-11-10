extends RefCounted
## The commoner's card: one of the common folk, met in the street, and their
## story. Owned by ui.gd, which forwards its public calls here (ui.show_folk and
## the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this card: its signals, its building blocks, its other cards

var _folk_panel: PanelContainer


func _init(owner: UI) -> void:
	ui = owner


func _folk_shell() -> VBoxContainer:
	if _folk_panel:
		_folk_panel.queue_free()
	# The court waits behind a commoner's card, and is back when it closes.
	if ui._court_panel.visible:
		ui._court_panel.visible = false
		ui._court_waiting = true
	_folk_panel = ui.card(ui.glass_panel())
	_folk_panel.offset_top = 70
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_folk_panel.add_child(v)
	return v


func show_folk_waiting() -> void:
	var v := _folk_shell()
	v.add_child(T.label("One of the common folk", T.TEXT_3))
	v.add_child(T.datum("They stop, and look up at you…", 16, T.TEXT_2))
	v.add_child(ui.btn("Close", close_folk))


func close_folk() -> void:
	if _folk_panel:
		_folk_panel.visible = false
	if ui._court_waiting:
		ui._court_waiting = false
		ui._show_audience()  # built afresh: set aside behind the digest, its card was cleared


## One of the common folk, met in the street: who they are, and their story.
func show_folk(d: Dictionary) -> void:
	if d.is_empty() or d.has("error") or not d.has("person"):
		close_folk()
		if d.has("error"):
			ui.toast(String(d["error"]))
		return
	var p: Dictionary = d["person"]
	var v := _folk_shell()
	ui._put_town_away()
	var head := HBoxContainer.new()
	v.add_child(head)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	names.add_child(T.title(String(p.get("name", "")), 22))
	names.add_child(T.label("%s, %d  ·  %s  ·  %s" % [String(p.get("trade", "")).capitalize(), int(p.get("age", 0)), p.get("family", ""), d.get("town", "")], T.TEXT_2))
	if String(p.get("nature", "")) != "":
		names.add_child(T.label("Known to be %s" % p["nature"], T.ACCENT))
	head.add_child(ui.btn("Close", close_folk))
	var story := RichTextLabel.new()
	story.bbcode_enabled = true
	story.fit_content = true
	story.custom_minimum_size = Vector2(240, 0)
	story.text = String(d.get("story", ""))
	if String(d.get("says", "")) != "":
		story.text += "\n\n[i]“%s”[/i]" % String(d["says"]).replace("\"", "")
	v.add_child(story)
	v.add_child(T.label("Wants %s" % p.get("wants", ""), T.TEXT_3))
