extends RefCounted
## The rank strip: the houses' ladder over the minimap, shown on hover over the
## map. Owned by ui.gd, which builds its Control in _build_minimap and forwards
## its public calls here (ui._rank_houses and the rest).

const T := preload("res://scripts/theme.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI  # the interface that owns this strip: its signals, its building blocks


func _init(owner: UI) -> void:
	ui = owner


## The great houses by power (towns, then men-at-arms), strongest on the left,
## over the map their colours wash. When the order changes the houses slide to
## their new places: the one that rose glows gold, the one that fell dims.
var _ranks: Control
var _rank_chips := {}  # house id -> its sigil
var _rank_order: Array = []


func _rank_houses(players: Array, fallen: Array = []) -> void:
	# A house with no town but a host in the field still fights: it stays on the ladder.
	var great := players.filter(func(p): return not p["house"].get("wild", false) and not p["house"].get("crown", false) and (int(p.get("cities", 0)) > 0 or int(p.get("units", 0)) > 0))
	var power := func(p): return int(p.get("cities", 0)) * 2 + int(p.get("units", 0))
	great.sort_custom(func(a, b): return power.call(a) > power.call(b))
	great = great.slice(0, 7)  # the seven great houses, never more on the strip
	var order := great.map(func(p): return int(p["id"]))
	var most := maxf(1.0, float(power.call(great[0]))) if not great.is_empty() else 1.0
	# The strip's width shared by every chip it shows, the fallen included.
	var slot := UI.MINIMAP_SIZE.x / maxf(1.0, float(mini(7, order.size() + fallen.size())))
	for id in _rank_chips.keys():
		if not order.has(id):
			_rank_chips[id].queue_free()
			_rank_chips.erase(id)
	for i in order.size():
		var p: Dictionary = great[i]
		var id: int = order[i]
		var col := Color.from_string(String(p["house"].get("color", "#888")), Color.GRAY)
		var chip: Control = _rank_chips.get(id)
		var fresh := chip == null
		if fresh:
			chip = Control.new()
			chip.mouse_filter = Control.MOUSE_FILTER_STOP
			# Click a house to follow its host in the field (or see its seat).
			chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			chip.tooltip_text = "Follow %s's host" % String(p["house"].get("name", "this house"))
			chip.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					ui.house_followed.emit(id))
			# Its place: a number, small, top-left.
			var place := Label.new()
			place.name = "Place"
			place.add_theme_font_override("font", T.mono)
			place.add_theme_font_size_override("font_size", 10)
			place.add_theme_color_override("font_color", T.TEXT_3)
			place.position = Vector2(3, 0)
			place.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(place)
			var icon := ui.sigil_icon(p["house"], 22)
			icon.size = Vector2(22, 22)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.name = "Sigil"
			chip.add_child(icon)
			# Its power, as a bar in the house's own colour (the colour of its land).
			for n in ["Track", "Power"]:
				var bar := ColorRect.new()
				bar.name = n
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				chip.add_child(bar)
			# Turning against the King: an ember by the sigil, not a bar that reads as rank.
			var ember := Panel.new()
			ember.name = "Ember"
			var dot := StyleBoxFlat.new()
			dot.bg_color = T.DANGER
			dot.set_corner_radius_all(4)
			ember.add_theme_stylebox_override("panel", dot)
			ember.size = Vector2(8, 8)
			ember.mouse_filter = Control.MOUSE_FILTER_IGNORE
			chip.add_child(ember)
			_ranks.add_child(chip)
			_rank_chips[id] = chip
		# The slots widen or narrow as houses fall or rise.
		chip.size = Vector2(slot, 40)
		(chip.get_node("Place") as Label).text = str(i + 1)
		(chip.get_node("Sigil") as Control).position = Vector2((slot - 22.0) * 0.5, 4)
		var track := chip.get_node("Track") as ColorRect
		track.color = Color(col.r, col.g, col.b, 0.22)
		track.position = Vector2(5, 31)
		track.size = Vector2(slot - 10.0, 4)
		var bar := chip.get_node("Power") as ColorRect
		bar.color = col
		bar.position = Vector2(5, 31)
		bar.size = Vector2(maxf(2.0, (slot - 10.0) * float(power.call(p)) / most), 4)
		var turning := float(p.get("turning", 0.0))
		var ember := chip.get_node("Ember") as Panel
		ember.position = Vector2((slot + 22.0) * 0.5 - 2.0, 3)
		ember.visible = turning > 0.0
		ember.modulate.a = 0.55 + 0.45 * turning
		chip.tooltip_text = "%d. %s\n%d towns  ·  %s men-at-arms  ·  favour %d" % [i + 1, String(p["house"].get("name", "")), int(p.get("cities", 0)), ui.heads(int(p.get("units", 0)) * 200), int(p.get("favour", 0))]
		if turning > 0.0:
			chip.tooltip_text += "\n" + ("Turned against you: their ultimatum is on its way." if turning >= 1.0 else "Turning against you. Left under 25, they send an ultimatum before they rise.")
		var was := _rank_order.find(id)
		if fresh or was < 0 or was == i:
			chip.position.x = i * slot
			continue
		var tw := ui.create_tween().set_parallel()
		tw.tween_property(chip, "position:x", i * slot, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		chip.modulate = Color(1.9, 1.6, 0.9) if i < was else Color(0.45, 0.45, 0.45)
		tw.tween_property(chip, "modulate", Color.WHITE, 1.4).set_delay(0.2)
	_rank_order = order
	# The houses that have fallen keep their place at the end, dimmed: seven
	# sigils always, and the realm remembers who is gone.
	for n in _ranks.get_children():
		if n.has_meta("fallen"):
			n.queue_free()
	var left := mini(fallen.size(), 7 - order.size())
	for k in left:
		var h: Dictionary = fallen[k]
		var chip := Control.new()
		chip.set_meta("fallen", true)
		chip.size = Vector2(slot, 40)
		chip.position.x = (order.size() + k) * slot
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.modulate = Color(1, 1, 1, 0.35)
		chip.tooltip_text = "%s has fallen: no town flies its banner." % String(h.get("name", ""))
		var icon := ui.sigil_icon(h, 22)
		icon.size = Vector2(22, 22)
		icon.position = Vector2((slot - 22.0) * 0.5, 4)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)
		_ranks.add_child(chip)
