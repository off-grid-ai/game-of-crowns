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
## Given someone already in the realm, the same form reshapes them instead, with what they remember.
## host: the person's own page (lore.gd _person_page) to write in place, the form inside it; done(spec) then takes the
## written spec ({} on Cancel) instead of the signals, and the card saves it.
## Returns the form's action row (Cancel and Make it so), for a host card to pin below its scrolling column.
func show_character_form(house_id: int, house_name: String, opts: Dictionary, person := {}, host: Control = null, done := Callable()) -> Control:
	var editing := not person.is_empty()
	# One of the crown's family (the Lore's Edit, bridge royals.js): name, nature and story only; no lord, aim or vow.
	var royal := bool(person.get("royal", false))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	if host:
		host.add_child(v)
	else:
		if _form_panel:
			_form_panel.queue_free()
		_form_panel = ui.card(ui.glass_panel())
		_form_panel.offset_top = 70
		if ui._house_panel:
			ui._house_panel.visible = false
		_form_panel.add_child(v)
	# Put away: back to the card that hosts it, or the panel hidden (and the Lore told).
	var finish := func(spec: Dictionary) -> void:
		if host:
			done.call(spec)
			return
		_form_panel.visible = false
		ui.character_form_closed.emit()
	# ask: the form's own question (a new reign's "Who are you?"), skip: its Cancel's word (royal_sheet.gd).
	v.add_child(T.label(String(person["ask"]) if person.get("ask") else (("Change who %s is" % String(person.get("name", ""))) if editing else ("A new character for " + house_name))))
	# fixed (a person's page in the Lore): the given name is the King's to change, the surname is the house's (shown
	# beside it, its own Edit on the house page), and age and sex stay as their portrait is painted (Mac 2026-11-15).
	var fixed := bool(person.get("fixed", false))
	var full := String(person.get("name", ""))
	var surname := ""
	if fixed and full.contains(" "):
		surname = String(person["surname"]) if person.get("surname") is String else full.substr(full.find(" ") + 1)
	var name := LineEdit.new()
	name.placeholder_text = "Their given name" if fixed else "Their name, e.g. Ser Aldous Crane"
	name.text = full.trim_suffix(" " + surname) if surname != "" else full
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if surname != "":
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 10)
		v.add_child(name_row)
		name_row.add_child(name)
		var sn := T.prose(surname, T.SIZE_BODY, T.TEXT_2)
		sn.tooltip_text = "The house's name: change it on the house's own page"
		sn.mouse_filter = Control.MOUSE_FILTER_PASS
		name_row.add_child(sn)
	else:
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
	if fixed:
		gender.visible = false
		age.visible = false
		row.add_child(T.prose("%s, %d" % ["A woman" if gender.selected == 1 else "A man", int(age.value)], T.SIZE_BODY, T.TEXT_2))
	var role := OptionButton.new()
	var role_keys: Array = opts.get("roles", {}).keys()
	for k in role_keys:
		role.add_item(String(opts["roles"][k]).capitalize())
	role.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if editing:
		# A lord or a born bannerman has no sworn role to pick; a written-in one keeps theirs.
		role.visible = person.get("role_key") != null and not royal
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
	var want := T.label("What they want")
	want.visible = not royal
	v.add_child(want)
	var goal := OptionButton.new()
	goal.visible = not royal
	var goals: Array = opts.get("goals", []).duplicate()
	# Their aim now, always shown: a person of the book as written carries its words as `goal`, one of the reign its
	# kind with the words in `goals`.
	if editing and person.get("goal") != null and not goals.any(func(g): return g["kind"] == person["goal"]):
		var said: Array = person.get("goals", []) if person.get("goals") is Array else []
		goals.push_front({"kind": person["goal"], "text": String(said[0]) if not said.is_empty() else String(person["goal"])})
	for g in goals:
		goal.add_item(String(g["text"]).capitalize())
	for i in goals.size():
		if goals[i]["kind"] == person.get("goal"):
			goal.selected = i
	if goal.selected < 0 and goals.size() > 0:
		goal.selected = 0
	var aim_was := goal.selected
	v.add_child(goal)
	var loyal_row := HBoxContainer.new()
	loyal_row.add_child(T.label("Loyalty to their lord  "))
	var loyalty := HSlider.new()
	loyalty.min_value = 0
	loyalty.max_value = 100
	loyalty.value = int(person.get("loyalty", 60))
	loyalty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loyalty.scrollable = false  # the wheel scrolls the form, never moves their loyalty
	var loyalty_was := loyalty.value
	loyal_row.add_child(loyalty)
	loyal_row.visible = not royal
	v.add_child(loyal_row)
	# Their past, as their card tells it: yours to rewrite.
	v.add_child(T.label("Their story"))
	var story := TextEdit.new()
	story.scroll_fit_content_height = true  # it grows with what's written: the form scrolls, not the box
	story.text = String(person.get("story" if royal else "backstory", "")) if person.get("story" if royal else "backstory") is String else ""
	story.placeholder_text = "Their past: where they come from, what they lost, whom they hate"
	story.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	story.custom_minimum_size.y = 84
	v.add_child(story)
	var past := LineEdit.new()
	past.placeholder_text = "Something that happens to them now (they'll remember it)" if editing else "A moment they'll never forget"
	past.visible = not royal
	v.add_child(past)
	# What they remember (their history, as the King rewrites it; bridge characters.js edit / written.js memories):
	# one line each, forgotten with ×, up to eight.
	var mems := VBoxContainer.new()
	mems.add_theme_constant_override("separation", 6)
	var add_mem := func(text: String) -> void:
		var r := HBoxContainer.new()
		var e := LineEdit.new()
		e.text = text
		e.placeholder_text = "Something they'll never forget"
		e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(e)
		var x := Button.new()
		x.text = "×"
		x.flat = true
		x.focus_mode = Control.FOCUS_NONE
		x.tooltip_text = "Forget this"
		x.pressed.connect(func(): r.queue_free())
		r.add_child(x)
		mems.add_child(r)
	if editing and not royal:
		v.add_child(T.label("Remembers"))
		v.add_child(mems)
		var seen: Array = []
		for m in person.get("memories", []):
			if not seen.has(m):
				seen.append(m)
				add_mem.call(String(m))
		var more := Button.new()
		more.text = "+  Add a memory"
		more.flat = true
		more.focus_mode = Control.FOCUS_NONE
		more.alignment = HORIZONTAL_ALIGNMENT_LEFT
		more.add_theme_color_override("font_color", T.ACCENT)
		more.pressed.connect(func():
			if mems.get_child_count() < 8:
				add_mem.call(""))
		v.add_child(more)
	preload("res://scripts/spark.gd").attach(past, ui.get_tree().current_scene.get("bridge"), "character-past", func(): return "%s of %s; %s." % [name.text if name.text != "" else "A person", house_name, other.text if other.text != "" else "no quirks named"])
	var go := HBoxContainer.new()
	go.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(go)
	# Their own face from the player's photo (likeness.gd), for someone already in the realm.
	var Likeness := preload("res://scripts/likeness.gd")
	if editing and Likeness.one and not person.get("written", false) and str(person.get("id", "")) != "":
		var pid := str(person["id"])
		go.add_child(ui.btn("Add your photo", func(): Likeness.one.pick(pid, "a %s of about %d" % ["woman" if gender.selected == 1 else "man", int(age.value)])))
	go.add_child(ui.btn(String(person.get("skip", "Cancel")), func(): finish.call({})))
	go.add_child(ui.btn("Make it so" if editing else "Bring them into the realm", func():
		if name.text.strip_edges() == "":
			ui.toast("Give them a name first.")
			return
		var named := name.text.strip_edges().get_slice(" ", 0) + " " + surname if surname != "" else name.text.strip_edges()
		if royal:
			var rs := {"id": str(person.get("id", "")), "name": named, "gender": "female" if gender.selected == 1 else "male",
				"age": int(age.value), "traits": picked, "other": other.text.strip_edges(), "past": story.text.strip_edges().left(300)}
			if fixed:
				rs.erase("gender")
				rs.erase("age")
			if not host:
				ui.royal_edited.emit(rs)
			finish.call(rs)
			return
		var spec := {"house": house_id, "name": named, "gender": "female" if gender.selected == 1 else "male",
			"age": int(age.value), "traits": picked, "other": other.text.strip_edges(),
			"backstory": past.text.strip_edges(), "past": story.text.strip_edges().left(300)}
		if fixed:
			spec.erase("gender")  # as their portrait is painted: the bridge refuses a change
			spec.erase("age")
		# Their aim and loyalty change only when the player moved them (a reshaping never stirs a house on its own).
		if goals.size() > 0 and (not editing or goal.selected != aim_was):
			spec["goal"] = goals[goal.selected]["kind"]
		if not editing or loyalty.value != loyalty_was:
			spec["loyalty"] = int(loyalty.value)
		if role.visible and not role_keys.is_empty():
			spec["role"] = role_keys[role.selected]
		if editing:
			spec["id"] = str(person.get("id", ""))
			var memories: Array = []
			for r in mems.get_children():
				if not r.is_queued_for_deletion() and String((r.get_child(0) as LineEdit).text).strip_edges() != "":
					memories.append(String((r.get_child(0) as LineEdit).text).strip_edges())
			if not royal:
				spec["memories"] = memories
			if not host:
				ui.character_edited.emit(spec)
		else:
			ui.character_created.emit(spec)
		finish.call(spec)))
	return go
