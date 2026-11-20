extends Node
## Touch scrolling on phones and tablets (Mac 2026-11-20: "you need to allow for scroll on mobile").
## Godot's ScrollContainer already scrolls when a finger drags it, but only if the drag reaches it: a button or a
## panel inside it stops the touch first. On a touch screen this lets every control inside a ScrollContainer pass
## the drag up (MOUSE_FILTER_PASS) while it still takes its own taps, and gives each list a small deadzone so a tap
## is not read as a scroll. On desktop it does nothing. One-finger drag on the map already pans (camera_rig.gd
## takes the touch as a left-button drag), and pinch zooms.

const DEADZONE_DEFAULT := 14

var _deadzone: int = int(preload("res://scripts/data.gd").num("ui", "touch.scroll_deadzone", DEADZONE_DEFAULT))


func _ready() -> void:
	if not (OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()):
		return
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(n: Node) -> void:
	if n is ScrollContainer:
		(n as ScrollContainer).scroll_deadzone = _deadzone
		return
	if not (n is Control) or (n as Control).mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			(n as Control).mouse_filter = Control.MOUSE_FILTER_PASS
			return
		if p is Viewport:
			return
		p = p.get_parent()
