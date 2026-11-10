extends RefCounted
## The character form: write your own character into a house, or reshape one
## already in the realm. Owned by ui.gd, which forwards its public call here
## (ui.show_character_form).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this form: its signals, its building blocks, its other cards

var _form_panel: PanelContainer


func _init(owner: UI) -> void:
	ui = owner


## Write your own character into a house: name, role, nature and aim. They
## join as a sworn member and act on what you gave them, season by season.
## Given someone already in the realm, the same form reshapes them instead.
func show_character_form(house_id: int, house_name: String, opts: Dictionary, person := {}) -> void:
	var editing := not person.is_empty()
	if _form_panel:
		_form_panel.queue_free()
	_form_panel = ui._card(ui._glass_panel())
	_form_panel.offset_top = 70
	if ui._house_panel:
		ui._house_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_form_panel.add_child(v)
	v.add_child(T.label(("Change who %s is" % String(person.get("name", ""))) if editing else ("A new character for " + house_name)))
	var name := LineEdit.new()
	name.placeholder_text = "Their name, e.g. Ser Aldous Crane"
	name.text = String(person.get("name", ""))
	v.add_child(name)
	preload("res://scripts/spark.gd").attach(name, ui.get_tree().current_scene.get("bridge"), "character-name", func(): return "A person of %s, in a medieval realm." % house_name)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var gender := OptionButton.new()
	gender.add_item("Man")
	gender.add_item("Woman")
	row.add_child(gender)
	var age := SpinBox.new()
	age.min_value = 14
	age.max_value = 80
	age.value = int(person.get("age", 32))
	age.prefix = "Age"
	gender.selected = 1 if str(person.get("gender", "")) == "female" else 0
	row.add_child(age)
	var role := OptionButton.new()
	var role_keys: Array = opts.get("roles", {}).keys()
	for k in role_keys:
		role.add_item(String(opts["roles"][k]).capitalize())
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editing:
		# A lord or a born bannerman has no sworn role to pick; a written-in one keeps theirs.
		role.visible = person.get("role_key") != null
		if role.visible and role_keys.has(person["role_key"]):
			role.selected = role_keys.find(person["role_key"])
	row.add_child(role)
	v.add_child(T.label("Their nature (up to three)"))
	var traits_box := HFlowContainer.new()
	var picked := []
	var known: Array = opts.get("traits", [])
	var others := []
	for t in person.get("traits", []):
		if known.has(t) and picked.size() < 3:
			picked.append(t)
		elif not known.has(t):
			others.append(t)
	for t in known:
		var b := Button.new()
		b.text = String(t)
		b.toggle_mode = true
		b.set_pressed_no_signal(picked.has(t))
		b.focus_mode = Control.FOCUS_NONE
		b.toggled.connect(func(on):
			if on and picked.size() >= 3:
				b.set_pressed_no_signal(false)
				return
			if on:
				picked.append(t)
			else:
				picked.erase(t))
		traits_box.add_child(b)
	v.add_child(traits_box)
	var other := LineEdit.new()
	other.placeholder_text = "Anything else, in your words: superstitious, loves his horses"
	other.text = ", ".join(others)
	v.add_child(other)
	preload("res://scripts/spark.gd").attach(other, ui.get_tree().current_scene.get("bridge"), "character-traits", func(): return "%s of %s." % [name.text if name.text != "" else "A person", house_name])
	v.add_child(T.label("What they want"))
	var goal := OptionButton.new()
	var goals: Array = opts.get("goals", []).duplicate()
	if editing and person.get("goal") != null and not goals.any(func(g): return g["kind"] == person["goal"]):
		goals.push_front({"kind": person["goal"], "text": String(person.get("goals", [""])[0])})
	for g in goals:
		goal.add_item(String(g["text"]).capitalize())
	for i in goals.size():
		if goals[i]["kind"] == person.get("goal"):
			goal.selected = i
	v.add_child(goal)
	var loyal_row := HBoxContainer.new()
	loyal_row.add_child(T.label("Loyalty to their lord  "))
	var loyalty := HSlider.new()
	loyalty.min_value = 0
	loyalty.max_value = 100
	loyalty.value = int(person.get("loyalty", 60))
	loyalty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loyal_row.add_child(loyalty)
	v.add_child(loyal_row)
	# Their past, as their card tells it: yours to rewrite.
	var story := TextEdit.new()
	story.text = String(person.get("backstory", "")) if person.get("backstory") is String else ""
	story.placeholder_text = "Their past: where they come from, what they lost, whom they hate"
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.custom_minimum_size.y = 84
	v.add_child(story)
	var past := LineEdit.new()
	past.placeholder_text = "Something that happens to them now (they'll remember it)" if editing else "A moment they'll never forget"
	v.add_child(past)
	preload("res://scripts/spark.gd").attach(past, ui.get_tree().current_scene.get("bridge"), "character-past", func(): return "%s of %s; %s." % [name.text if name.text != "" else "A person", house_name, other.text if other.text != "" else "no quirks named"])
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(go)
	go.add_child(ui._btn("Cancel", func(): _form_panel.visible = false))
	go.add_child(ui._btn("Make it so" if editing else "Bring them into the realm", func():
		if name.text.strip_edges() == "":
			ui.toast("Give them a name first.")
			return
		var spec := {"house": house_id, "name": name.text.strip_edges(), "gender": "female" if gender.selected == 1 else "male",
			"age": int(age.value), "traits": picked, "other": other.text.strip_edges(), "goal": goals[goal.selected]["kind"],
			"loyalty": int(loyalty.value), "backstory": past.text.strip_edges(), "past": story.text.strip_edges().left(300)}
		if role.visible and not role_keys.is_empty():
			spec["role"] = role_keys[role.selected]
		if editing:
			spec["id"] = str(person.get("id", ""))
			ui.character_edited.emit(spec)
		else:
			ui.character_created.emit(spec)
		_form_panel.visible = false))
