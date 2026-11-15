extends RefCounted
## Whether the realm is drawn at all (Mac 2026-11-15, the reign's end card over a world still drawn at 3.8M triangles:
## "what kind of state machine is this?"). Each screen that covers the whole window (the loading card, the painted
## map, the reign's end, a film being made) says so here while it is up; the land is drawn only when none does. The
## one writer of the window's disable_3d: no screen turns it on or off itself, so one closing can never draw the
## realm under another still open.

## Under a still screen (the reign's end, the painted map) the realm's view stops too: its people, armies, towns and
## land (main.gd puts them in VIEW) neither move nor think, as nothing of them can be seen (Mac 2026-11-15: "76 fps
## for a static page?", 740 figures still walking under the end card). Two covers don't stop it: the loading card
## (the realm is raised behind it) and a film (its own camera draws the realm off screen).
const VIEW := &"realm_view"
const RUNS_BEHIND := ["loading", "film"]
static var _covers := {}  # who covers the window now -> true


## `who` (a screen's name) covers the window (on) or no longer does.
static func cover(who: String, on: bool) -> void:
	if on:
		_covers[who] = true
	else:
		_covers.erase(who)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	tree.root.disable_3d = not _covers.is_empty()
	var still := _covers.keys().any(func(k): return not RUNS_BEHIND.has(k))
	for n in tree.get_nodes_in_group(VIEW):
		n.process_mode = Node.PROCESS_MODE_DISABLED if still else Node.PROCESS_MODE_INHERIT


## Whether anything covers the window now.
static func covered() -> bool:
	return not _covers.is_empty()
