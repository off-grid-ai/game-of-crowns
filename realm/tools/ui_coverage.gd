extends Node
## How much of the screen the interface covers at rest (UI.md §1: under 10%).
## Test runs only: main.gd adds it for --ui-coverage=<seconds>. Once the realm has
## formed and that long has passed, at the normal town view, with no panel opened, it marks every visible drawn
## control (panels, buttons, labels, pictures) on a fine grid and prints the
## share covered, and the biggest controls by what they cover.
##   UI coverage: 7.4% of 1600x920 (target under 10%) ...

const CELL := 8.0  # pixels per grid cell

var _left := 0.0
var _done := false
var _root: Node  # the interface's root control (ui.gd root): its children are the cards


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui-coverage="):
			_left = float(a.substr(14))
	# Headless has no window of its own: measure on the size the game is played at.
	get_tree().root.size = Vector2i(1600, 920)


func _process(delta: float) -> void:
	if _done:
		return
	# Counted from when the realm has formed (main's land and towns laid), not from launch.
	if not get_parent().get("_settled"):
		return
	_left -= delta
	if _left > 0.0:
		return
	_done = true
	var ui: Node = get_parent().get("ui")
	# At rest: no card the King opened (a test start selects a town; the court counts as it is).
	ui.call("_put_town_away")
	await get_tree().process_frame
	await get_tree().process_frame
	_root = ui.get("root")
	var screen := get_viewport().get_visible_rect().size
	var cols := int(ceil(screen.x / CELL))
	var rows := int(ceil(screen.y / CELL))
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	var by := {}
	for n in ui.find_children("*", "Control", true, false):
		var c: Control = n
		if not c.is_visible_in_tree() or c.modulate.a < 0.05 or c.self_modulate.a < 0.05:
			continue
		if not _draws(c):
			continue
		var r := c.get_global_rect().intersection(Rect2(Vector2.ZERO, screen))
		if r.size.x < 1.0 or r.size.y < 1.0:
			continue
		var cells := 0
		for y in range(int(r.position.y / CELL), int(ceil(r.end.y / CELL))):
			for x in range(int(r.position.x / CELL), int(ceil(r.end.x / CELL))):
				if grid[y * cols + x] == 0:
					grid[y * cols + x] = 1
					cells += 1
		if cells > 0:
			by[_name(c)] = int(by.get(_name(c), 0)) + cells
	var covered := 0
	for b in grid:
		covered += b
	var share := 100.0 * covered / float(cols * rows)
	print("UI coverage: %.1f%% of %dx%d (target under 10%%)" % [share, int(screen.x), int(screen.y)])
	var names := by.keys()
	names.sort_custom(func(a, b): return by[a] > by[b])
	for k in names.slice(0, 12):
		print("UI   %5.1f%%  %s" % [100.0 * by[k] / float(cols * rows), k])
	get_tree().quit()


## Whether a control paints something of its own (not an empty layout box).
func _draws(c: Control) -> bool:
	if c is PanelContainer or c is Panel:
		return c.has_theme_stylebox("panel") and not (c.get_theme_stylebox("panel") is StyleBoxEmpty)
	if c is Label:
		return (c as Label).text.strip_edges() != ""
	if c is RichTextLabel:
		return (c as RichTextLabel).text.strip_edges() != ""
	if c is BaseButton or c is TextureRect or c is ColorRect or c is LineEdit or c is ProgressBar:
		return true
	return false


## The control by the top-level card it belongs to (the child of the interface's
## root), named with where it stands, so the report reads as the screen does.
func _name(c: Control) -> String:
	var n: Node = c
	while n.get_parent() and n.get_parent() != _root and not (n.get_parent() is CanvasLayer):
		n = n.get_parent()
	var top := n as Control
	if top == null:
		return String(c.name)
	var r := top.get_global_rect()
	var words := ""
	for l in top.find_children("*", "Label", true, false):
		if (l as Label).is_visible_in_tree() and (l as Label).text.strip_edges() != "":
			words = (l as Label).text.strip_edges().left(28)
			break
	return "%s at %d,%d %dx%d \"%s\"" % [top.get_class(), int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y), words]
