extends RefCounted
## The ✦ beside a free-text box: Off Grid AI writes it for you when it's empty,
## or carries on and finishes what you began. Without Off Grid AI it offers to
## get it instead. One for every box where your own words go.
##   Spark.attach(edit, bridge, "mood", func(): return "what the box knows")
## The box (a LineEdit or TextEdit, already in the tree) is set in a row with
## the button at its end.

const OFFGRID_URL := "https://getoffgridai.co/desktop"
const T := preload("res://scripts/theme.gd")


static func attach(edit: Control, bridge: Node, kind: String, context: Callable, compact := false) -> Button:
	var parent := edit.get_parent()
	if bridge == null or parent == null:
		return null  # no bridge to ask (a render, a test): the box stays as it is
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = edit.size_flags_horizontal | Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	parent.move_child(row, edit.get_index())
	parent.remove_child(edit)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.add_theme_color_override("font_color", T.ACCENT)
	b.add_theme_color_override("font_hover_color", T.TEXT)
	b.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(b)
	var ready := [true]
	var text_of := func() -> String: return String(edit.get("text")).strip_edges()
	var label := func() -> void:
		if not is_instance_valid(b):
			return
		if not ready[0]:
			b.text = "✦" if compact else "✦  Get Off Grid AI"
			b.tooltip_text = "Off Grid AI writes this for you, free and on your Mac. Click to get it."
		else:
			var begun: bool = text_of.call() != ""
			b.text = "✦" if compact else ("✦  Carry it on" if begun else "✦  Write it")
			b.tooltip_text = "Off Grid AI carries on what you began." if begun else "Off Grid AI writes it for you."
	bridge.ai_status(func(st):
		ready[0] = st is Dictionary and bool(st.get("words", false))
		label.call())
	edit.connect("text_changed", func(_a = null): label.call())
	b.pressed.connect(func():
		if not ready[0]:
			OS.shell_open(OFFGRID_URL)
			return
		b.disabled = true
		var was := b.text
		b.text = "✦  Writing…" if not compact else "…"
		bridge.write_for(kind, String(context.call()), text_of.call(), func(code, d):
			if not is_instance_valid(b):
				return
			b.disabled = false
			b.text = was
			if code == 200 and d is Dictionary and String(d.get("text", "")) != "":
				edit.set("text", String(d["text"]))
				if edit is LineEdit:
					(edit as LineEdit).caret_column = (edit as LineEdit).text.length()
				label.call()
			else:
				b.tooltip_text = String(d.get("error", "Off Grid AI didn't answer.")) if d is Dictionary else "Off Grid AI didn't answer."
				b.text = "✦  Busy, try again" if not compact else "✦"))
	label.call()
	return b
