extends RefCounted
## The intro story: when it is due (_intro_due, read as each world report comes
## in), and telling it (_tell_the_story): the houses and their seats handed to
## the storybook (intro.gd), with the menu, interface and map names stepped
## aside and the costly systems held still while it plays. Owned by main.gd,
## whose menu and world report set and read these.

const Main := preload("res://scripts/main.gd")
const Settings := preload("res://scripts/settings.gd")

var main: Main  # the realm that owns the story: its bridge, menu, interface and storybook
var _intro_due := false
var _opened_in_intro := false  # a chronicle was opened while the intro played: no menu after it
var _back_to_menu := false  # the intro was asked for from the menu: the menu comes back after it


func _init(owner: Main) -> void:
	main = owner


## The realm's story as it stands: each house with its seat, told over stills,
## then a flight over the seats themselves.
func _tell_the_story() -> void:
	var houses: Array = []
	var seats := {}
	for p in main.awareness.rec("players", []):
		houses.append(p["house"])
	for c in main.awareness.rec("cities", []):
		if c.get("capital", false):
			for p in main.awareness.rec("players", []):
				if int(p["id"]) == int(c["owner"]):
					seats[String(p["house"].get("name", ""))] = [String(c.get("title", c["name"])), Vector2(float(c["x"]), float(c["y"]))]
	Settings.set_value("seen_intro", true)
	# The intro has the screen to itself: the menu, the interface and the map's
	# names step aside while it plays (it may fly over the live realm), and come
	# back as they were when it ends.
	var was := [main.title.visible]
	_opened_in_intro = false
	main.title.visible = false
	main.ui.visible = false
	main.labels.visible = false
	# What the intro hides needn't run under it: the people, soldiers and their
	# animation, chatter, the camera's director and the map's names stop while it
	# covers the screen (they cost 50-150 ms a frame and made the story stutter
	# at 12-30 fps); the land, towns, fields and the bridge go on building.
	var held := []
	for n in [main.villagers, main.units, main.scenes, main.labels, main.director, main.get_node_or_null("AnimLOD"), main.get_node_or_null("Chatter")]:
		if n and n.process_mode != Node.PROCESS_MODE_DISABLED:
			held.append([n, n.process_mode])
			n.process_mode = Node.PROCESS_MODE_DISABLED
	main.intro.finished.connect(func():
		for h in held:
			if is_instance_valid(h[0]):
				h[0].process_mode = h[1]
	, CONNECT_ONE_SHOT)
	main.intro.finished.connect(func():
		# The menu comes back only if no chronicle was opened meanwhile; the
		# interface follows the one rule (shown whenever the menu isn't), not
		# what was on screen when the intro began (a new realm began from the
		# menu, which left the interface hidden after the intro).
		main.title.visible = (was[0] or _back_to_menu) and not _opened_in_intro
		_back_to_menu = false
		main.ui.visible = not main.title.visible and not main._shot.has("clean")
		main.labels.visible = main.ui.visible
		# The King is in his realm now; the first court may sit (Reigns' first card).
		if main.ui.visible:
			main.bridge.opening("realm")
			# The crowning: the castle, the royal standard rising, the bells, his name (crowning.gd).
			var Crowning := preload("res://scripts/crowning.gd")
			if Crowning.on():
				var c = Crowning.new(main)
				main.add_child(c)
				c.play()
			if main.hand_prompts:
				main.hand_prompts.landed(), CONNECT_ONE_SHOT)
	main.intro.watching = _back_to_menu
	main.intro.play(houses, seats)
