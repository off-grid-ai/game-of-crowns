extends RefCounted
## The road of the reign at a glance (Frostpunk's countdown to the storm, Thronefall's nights; Mac 2026-11-16: "it's
## not making it feel like I'm going through a story"): a thin track under the houses' strip, its four acts by name,
## the part of the reign gone filled, a mark where it stands now, and the time left; once the last act is named, what
## comes for the throne stands at its end in words. It decides nothing: the reign's clock, act names and the last act
## are the bridge's (reign view: elapsedMs, minutes, remainingMs, lastAct) and ui.json reign_cards.acts.
## Owned by ui.gd, updated with the reign (ui.set_reign). Words, not colour, carry it (Mac is colour-blind).

const T := preload("res://scripts/theme.gd")
const Data := preload("res://scripts/data.gd")
const UI := preload("res://scripts/ui.gd")

var ui: UI
var _panel: PanelContainer
var _bar: Control
var _now := 0.0  # the share of the reign gone
var _names := PackedStringArray()
var _act_lbl: Label
var _ahead: Label


func _init(owner: UI) -> void:
	ui = owner


func _build() -> void:
	_panel = ui.glass_panel()
	var _sb := T._box(T.SURFACE, T.HAIRLINE, 10, 4)
	_sb.content_margin_left = T.GAP_SECTION  # room inside the glass (Mac 2026-11-17: "solve spacing here")
	_sb.content_margin_right = T.GAP_SECTION
	_sb.content_margin_top = T.GAP_TIGHT + 2
	_sb.content_margin_bottom = T.GAP_TIGHT + 2
	_panel.add_theme_stylebox_override("panel", _sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.offset_left = 10
	_place()
	# Under the houses' strip by its real height and one gap, never into it (it measured 40 and the strip grew past it).
	var strip: Control = ui.houses_strip._panel
	strip.resized.connect(_place)
	strip.visibility_changed.connect(_place)
	_panel.custom_minimum_size.x = float(Data.num("ui", "reign_track.width", 420.0))
	_panel.visible = false
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", T.GAP_TIGHT)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	_act_lbl = T.label("")
	_act_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_act_lbl)
	_ahead = T.label("", T.TEXT_2)
	head.add_child(_ahead)
	v.add_child(head)
	_bar = Control.new()
	_bar.custom_minimum_size.y = 8
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)  # the panel is ui.glass_panel()'s, already in the interface's root
	for a in Data.value("ui", "reign_cards.acts", []):
		_names.append(String((a as Dictionary).get("name", "")) if a is Dictionary else "")



## Where the act card sits: under the houses' strip and a gap when it shows, at the plane's top when it doesn't.
func _place() -> void:
	var strip: Control = ui.houses_strip._panel if ui.houses_strip else null
	var top := float(Data.num("ui", "plane.top", 12.0))
	if strip and strip.visible:
		top = strip.offset_top + strip.size.y + T.GAP
	_panel.offset_top = top

func update(r: Dictionary) -> void:
	if _panel == null:
		return
	var minutes := float(r.get("minutes", 0))
	_panel.visible = minutes > 0.0 and String(r.get("status", "")) != "ended"
	if not _panel.visible:
		return
	_now = clampf(float(r.get("elapsedMs", 0)) / (minutes * 60000.0), 0.0, 1.0)
	var act := mini(3, int(_now * 4.0))
	var name := _names[act] if act < _names.size() else ""
	_act_lbl.text = ("ACT %s  ·  %s" % [["I", "II", "III", "IV"][act], name.to_upper()]) if name != "" else "ACT %s" % ["I", "II", "III", "IV"][act]
	var left := ""
	if r.get("remainingMs") != null:
		var secs := int(float(r["remainingMs"]) / 1000.0)
		left = "%d:%02d left" % [secs / 60, secs % 60]
	var la = r.get("lastAct")
	var threat := String(la.get("threat", "")) if la is Dictionary else ""
	_ahead.text = ("Coming: %s  ·  %s" % [threat, left]) if threat != "" else left
	_ahead.add_theme_color_override("font_color", T.DANGER if threat != "" else T.TEXT_2)
	_bar.queue_redraw()


## Four acts with hairline gaps, the reign gone filled, a mark where it stands now.
func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	var gap := 3.0
	var seg := (w - gap * 3.0) / 4.0
	for i in 4:
		var x := i * (seg + gap)
		_bar.draw_rect(Rect2(x, 2, seg, h - 4), Color(1, 1, 1, 0.12))
		var fill := clampf(_now * 4.0 - i, 0.0, 1.0)
		if fill > 0.0:
			_bar.draw_rect(Rect2(x, 2, seg * fill, h - 4), Color(T.ACCENT, 0.85 if i < 3 else 1.0))
	var at := clampf(_now * 4.0, 0.0, 4.0)
	var mx := floorf(at) * (seg + gap) + (at - floorf(at)) * seg
	_bar.draw_rect(Rect2(mx - 1.5, 0, 3, h), T.TEXT)
