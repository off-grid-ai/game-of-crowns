extends RefCounted
## Walking as a character: the body you step into (control.gd), the voice you
## speak with (mic.gd) and the buildings you go inside (interior.gd), wired to
## the bridge (meeting, talking, falling) and the interface; stepping into the
## King (_walk_as_king) or anyone else (_take_control). Owned by main.gd, which
## keeps control, mic and interior as its own and forwards _take_control (the
## film harness and cinematics.gd call main._take_control).

const Main := preload("res://scripts/main.gd")
const Settings := preload("res://scripts/settings.gd")

var main: Main  # the realm you walk in: its bridge, towns, camera and interface


func _init(owner: Main) -> void:
	main = owner


## The walking body, the mic and the interiors, made and wired (from main._ready).
func _setup() -> void:
	# Taking control: the close-up gives way to the person, in their own town.
	main.mic = preload("res://scripts/mic.gd").new()
	main.add_child(main.mic)
	main.ui.mic = main.mic
	main.control = preload("res://scripts/control.gd").new()
	main.ui.walker = main.control  # Esc steps you out of walking, not just closes panels
	main.control.mic = main.mic
	main.control.terrain = main.terrain
	main.control.towns = main.towns
	main.control.villagers = main.villagers
	main.control.rig = main.rig
	main.add_child(main.control)
	main.interior = preload("res://scripts/interior.gd").new()
	main.interior.people = main.villagers._people
	main.add_child(main.interior)
	main.ui.walk_as_king.connect(_walk_as_king)
	main.hero.control_requested.connect(func(p, h):
		main.hero.close()
		_take_control(p, h))
	main.control.want_people.connect(func(town): main.bridge.town_people(town, func(d): main.control.meet(d if d is Array else [])))
	main.control.said.connect(func(town, i, text, person):
		var p: Dictionary = main.control._person
		main.bridge.talk(town, i, {"id": str(p.get("id", "")), "name": String(p.get("name", "")), "house": String(main._houses.get(int(p.get("house_id", -1)), {}).get("name", ""))}, text, func(code, d):
			var aloud: bool = d is Dictionary and d.has("reply") and Settings.get_value("voices")
			main.control.heard(d if d is Dictionary else {"error": "They say nothing."}, aloud)
			if aloud:
				main._say_aloud(String(d["reply"]), {"name": d.get("name", ""), "gender": d.get("gender", "")}, main.control.done_speaking), person))
	main.control.approached.connect(func(town, i, person):
		var p: Dictionary = main.control._person
		main.bridge.talk(town, i, {"id": str(p.get("id", "")), "name": String(p.get("name", "")), "house": String(main._houses.get(int(p.get("house_id", -1)), {}).get("name", ""))}, "", func(code, d):
			var aloud: bool = d is Dictionary and d.has("reply") and Settings.get_value("voices")
			main.control.heard(d if d is Dictionary else {"error": "They say nothing."}, aloud)
			if aloud:
				main._say_aloud(String(d["reply"]), {"name": d.get("name", ""), "gender": d.get("gender", "")}, main.control.done_speaking), person, true))
	main.control.spoke.connect(func(wav): main.bridge.hear(wav, main.control.understood))
	main.control.talk_to.connect(func(town, i):
		main.ui.show_folk_waiting()
		main.bridge.folk(town, i, func(d): main.ui.show_folk(d if d is Dictionary else {})))
	main.control.enter.connect(func(room, town, p):
		var name := ""
		for c in main.bridge.world.get("cities", []):
			if int(c["id"]) == town:
				name = String(c.get("title", c["name"]))
		if main.interior.open(room, p, main._houses.get(int(p.get("house_id", -1)), {}), name):
			main.control.set_process(false)  # one body at a time: the one indoors
			main.control.set_process_unhandled_input(false)
		else:
			main.ui.toast("Its doors are shut to you, for now."))
	main.control.fell.connect(func(p):
		main.bridge.person_fell(str(p.get("id", "")), "I fell to outlaws in the streets of %s." % String(p.get("seat", "my own town")), func(code, _d):
			main.ui.toast(("%s is dead. Their heir takes up the seat." % String(p.get("name", ""))) if code == 200 else "They fell, but the realm did not hear of it.")))
	main.interior.closed.connect(func():
		main.control.set_process(true)
		main.control.set_process_unhandled_input(true))


## The King is you, not one of the court's characters: he has a body of his
## own ("king", which the bridge knows to address as Your Grace), at his seat.
func _walk_as_king() -> void:
	# Pressed while walking: back to the realm from above.
	if main.control.active:
		main.control.stop()
		return
	for p in main.bridge.world.get("players", []):
		var h: Dictionary = p.get("house", {})
		if h.get("crown", false):
			var house: Dictionary = main._houses.get(int(p["id"]), h)
			house["id"] = int(p["id"])
			# The King goes where you are looking: the town nearest the camera,
			# else his own seat.
			var near: Dictionary = main.towns.nearest(main.rig.target, 12.0)
			var at := String(near.get("title", near.get("name", ""))) if not near.is_empty() else String(h.get("seat", "Kingsmere"))
			var king := {"id": "king", "name": "The King", "gender": "male", "rank": "king", "role": "King", "seat": at, "traits": []}
			_take_control(king, house)
			return
	main.ui.toast("The throne is empty.")


## Step into someone: they appear at their seat (or their house's chief town)
## and the camera drops low behind them. Esc gives the realm back.
func _take_control(p: Dictionary, h: Dictionary) -> void:
	# Walking the realm is version 2; test renders still reach it to build it.
	if not preload("res://scripts/features.gd").WALKING and not main._shot.has("path"):
		return
	var town := -1
	var owner := int(h.get("id", -1))
	for c in main.bridge.world.get("cities", []):
		if p.get("seat") and String(c.get("title", c["name"])) == String(p["seat"]):
			town = int(c["id"])
		elif town < 0 and int(c["owner"]) == owner and c.get("capital", false):
			town = int(c["id"])
	if town >= 0:
		main.towns.ensure(town)  # still being raised? raise it now
	if town < 0 or not main.towns.towns.has(town):
		main.ui.toast("%s is nowhere you can reach." % String(p.get("name", "They")))
		return
	p["house_id"] = owner
	main.control.start(p, h, town)
