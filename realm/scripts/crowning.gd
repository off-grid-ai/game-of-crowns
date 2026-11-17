extends CanvasLayer
## The crowning: the King's first moment in his realm, as the storybook ends (docs/review/first-ten-minutes.md;
## CK3 shows your ruler and realm first, AoE IV opens on your own town). The camera on the crown's castle, the
## royal standard raised over its keep, the crown's fanfare, cheer and bells, and one line over the realm for a few
## seconds: "Long live <the King's name>, King of Aldmere". Then the Hand speaks (hand_prompts.gd). It decides
## nothing: the castle is the town's, the name the realm's own reading. Words and timings: data/opening.json crowning.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")
const Heraldry := preload("res://scripts/heraldry.gd")
const F := "opening"

var main: Node


static func on() -> bool:
	return bool(Data.value(F, "crowning.on", true))


func _init(owner: Node) -> void:
	main = owner
	name = "Crowning"
	layer = 20


func play() -> void:
	var seat := _seat()
	if seat.is_empty():
		queue_free()
		return
	main._frame_castle(int(seat["id"]))
	_raise_standard(int(seat["id"]))
	if main.get("sound") and main.sound.has_method("event"):
		main.sound.event("crown")
		main.sound.sounds_v2.announce("crowned")
	_line()


## The crown's seat (/world seatId).
func _seat() -> Dictionary:
	var want := int(main.awareness.rec("seatId", -1)) if main.awareness.rec("seatId") != null else -1
	for c in main.awareness.rec("cities", []):
		if int(c.get("id", -2)) == want:
			return c
	return {}


## The royal standard rises over the keep (the top of the castle's tallest piece).
func _raise_standard(seat_id: int) -> void:
	var t = main.towns.towns.get(seat_id)
	var castle: Node3D = (t["node"] as Node3D).get_node_or_null("Castle") if t is Dictionary and is_instance_valid(t.get("node")) else null
	if castle == null:
		return
	var top := -INF
	var at := castle.global_position
	for mi in castle.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		if box.end.y > top:
			top = box.end.y
			at = box.get_center()
	if top == -INF:
		return
	var crown := {}
	for h in (main.get("_houses") as Dictionary).values():
		if h is Dictionary and h.get("crown", false):
			crown = h
	var tall := Data.num(F, "crowning.standard", 1.2)
	var flag: Node3D = Heraldry.standard(crown, Heraldry.colour(crown, Color(0.72, 0.13, 0.16)), tall)
	main.add_child(flag)
	flag.global_position = Vector3(at.x, top - tall, at.z)
	var tw := flag.create_tween()
	tw.tween_property(flag, "global_position:y", top, Data.num(F, "crowning.rise", 2.5)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## The line over the realm: in the middle of the sky, a few seconds, then gone.
func _line() -> void:
	# The King's own name (bridge royals.js, /world royals.king: the name the player may have given him), not the
	# realm's reading of him.
	var king = preload("res://scripts/royal_sheet.gd").royals().get("king")
	var name_: String = String(king.get("name", "")) if king is Dictionary else ""
	var text := String(Data.value(F, "crowning.line", "Long live %s, King of Aldmere")) % (name_ if name_ != "" else "the King")
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	box.offset_top = Data.num(F, "crowning.top", 150.0)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var big := T.title(text, 34)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	big.add_theme_constant_override("shadow_offset_y", 2)
	box.add_child(big)
	var small := T.label(String(Data.value(F, "crowning.under", "The realm is yours")), T.ACCENT)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(small)
	box.modulate.a = 0.0
	# One layer at a time: the first card to come up (a lord rising, a town's card) takes the screen, and the line
	# gives way at once (ui.card_shown).
	if main.get("ui") and main.ui.has_signal("card_shown"):
		main.ui.card_shown.connect(func(_c):
			if is_instance_valid(box):
				box.create_tween().tween_property(box, "modulate:a", 0.0, Data.num(F, "crowning.yield", 0.25)).finished.connect(queue_free), CONNECT_ONE_SHOT)
	var tw := box.create_tween()
	tw.tween_property(box, "modulate:a", 1.0, 0.6)
	tw.tween_interval(Data.num(F, "crowning.seconds", 4.0))
	tw.tween_property(box, "modulate:a", 0.0, 0.8)
	tw.tween_callback(queue_free)
