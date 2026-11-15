extends RefCounted
## The control plane: one strip along the bottom of the screen where the King reads his realm and acts (Mac 2026-11-16:
## "we need a control plane, where I can take action ... bottom of the screen", "even the stuff on the top ... will just
## go in the control plane", "see how other games do it and replicate"). Warcraft III's console and Age of Empires IV's
## bottom bar, left to right: the minimap (and the camera pad when Settings asks for it); the realm (the date, the goal
## and its step, the treasury and the seals); what is selected (a host's card and its orders, host_command.gd); the
## realm's own keys (the King, houses, chronicle, book, lore, ledger, pause, tour, settings, menu). The top of the screen
## is left to the realm and the cards that hang from it (the hosts' list, the chronicle, the houses table).
## Owned by ui.gd; each slot is filled by the piece's own owner (top_bar.gd, ui.gd _build_minimap, host_command.gd).
## Sizes: ui.json plane.

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")

var ui: Node
var bar: PanelContainer  # the strip itself, the full width of the screen along its foot
var map_slot: HBoxContainer  # the minimap, the camera pad beside it
var realm_slot: VBoxContainer  # the date and the goal, the treasury under them
var select_slot: HBoxContainer  # what is selected, centred in the room between the realm and the keys
var keys_slot: HBoxContainer  # the realm's keys, at the right


func _init(owner: Node) -> void:
	ui = owner


func build() -> void:
	bar = ui.glass_panel()
	bar.name = "ControlPlane"
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var edge := float(Data.num("ui", "plane.edge", 8.0))
	bar.offset_left = edge
	bar.offset_right = -edge
	bar.offset_bottom = -edge
	bar.mouse_filter = Control.MOUSE_FILTER_STOP  # a click on the strip is the strip's, never the land's under it
	bar.add_theme_stylebox_override("panel", T._box(T.SURFACE_SOLID, T.HAIRLINE, 12, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(Data.num("ui", "plane.gap", 16.0)))
	bar.add_child(row)
	map_slot = HBoxContainer.new()
	map_slot.add_theme_constant_override("separation", 6)
	row.add_child(map_slot)
	row.add_child(_rule())
	realm_slot = VBoxContainer.new()
	realm_slot.add_theme_constant_override("separation", 8)
	realm_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	realm_slot.custom_minimum_size.x = Data.num("ui", "plane.realm_width", 340.0)
	row.add_child(realm_slot)
	row.add_child(_rule())
	select_slot = HBoxContainer.new()
	select_slot.alignment = BoxContainer.ALIGNMENT_CENTER
	select_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(select_slot)
	row.add_child(_rule())
	keys_slot = HBoxContainer.new()
	keys_slot.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(keys_slot)


## Where the strip begins, on screen: every card that stands on the land keeps above it.
func top_y() -> float:
	if bar == null or not bar.is_visible_in_tree():
		return ui.get_viewport().get_visible_rect().size.y
	return bar.get_global_rect().position.y


## How much of the screen's foot the strip takes, its margin with it.
func room() -> float:
	return ui.get_viewport().get_visible_rect().size.y - top_y()


## A piece made for the plane, as a slot's child: a container without a box of its own (the strip is the box).
static func bare(p: PanelContainer) -> PanelContainer:
	p.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	return p


func _rule() -> Control:
	var r := ColorRect.new()
	r.color = T.HAIRLINE
	r.custom_minimum_size = Vector2(1, 0)
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
