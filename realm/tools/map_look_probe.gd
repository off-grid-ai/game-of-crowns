extends SceneTree
## Headless check that the realm at map zoom has one look (integration audit #8: old/new switches keep both
## paths; READY.md line 15, one path). The map marks (house standards, march lines, siege swords), the
## political map and the painted overview's held lands always draw, with no --map=v1/v2 switch, no `version`
## in data/map.json, and no v1 drawing left in realm_map.gd. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/map_look_probe.gd

const FILES := ["map_look.gd", "map_marks.gd", "map_labels.gd", "overview.gd", "realm_map.gd", "political_overlay.gd"]


func _init() -> void:
	var fails := 0
	for f in FILES:
		var src := FileAccess.get_file_as_string("res://scripts/" + f)
		for bad in ["--map=v", ".v2()", "_map_v2", "v2 :=", "_over_map.v2", "if v2"]:
			if src.contains(bad):
				print("FAIL %s keeps the old/new switch (%s)" % [f, bad])
				fails += 1
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/map.json"))
	if data.has("version"):
		print("FAIL data/map.json keeps a version switch")
		fails += 1
	var ML = load("res://scripts/map_look.gd")
	if not ML.politics():
		print("FAIL the political map is off at map zoom by default")
		fails += 1
	var rm: Script = load("res://scripts/realm_map.gd")
	if rm == null or rm.get_script_property_list().any(func(p): return p.name == "v2"):
		print("FAIL realm_map.gd keeps its v2 member")
		fails += 1
	# The chronicle's map (lore.gd) has no mirror: its hosts and sieges come from the bridge's realm map.
	var view = rm.new()
	view.data = {"towns": [{"x": 3, "y": 4, "title": "A", "besieged": true}], "armies": [{"x": 5, "y": 6, "companies": 2, "key": "House Goldcrest", "color": "#c90"}]}
	if view._hosts().size() != 1 or int(view._hosts()[0]["men"]) <= 0:
		print("FAIL the chronicle's map loses its hosts")
		fails += 1
	if view._sieges() != [Vector2(3, 4)]:
		print("FAIL the chronicle's map loses its sieges")
		fails += 1
	view.free()
	# v2 draws each thing v1 drew (GoC, 12 Nov: towns, the besieged ring, hosts, lands), from the mirror and without it.
	for mirror in [true, false]:
		var v = rm.new()
		v.size = Vector2(800, 600)
		v.data = {"tiles": [12, 12], "land": [[3, 4], [5, 6]], "towns": [{"x": 3, "y": 4, "title": "Ashford", "color": "#c90", "size": 2, "besieged": true}, {"x": 8, "y": 8, "title": "Seat", "color": "#36c", "capital": true}], "armies": [{"x": 5, "y": 6, "companies": 2, "key": "House Goldcrest", "color": "#c90"}]}
		v.center = Vector2(5.5, 5.5)
		if mirror:
			var row := []
			for x in 12:
				row.append("1")
			v.houses = {1: {"name": "House Goldcrest", "color": "#cc9900"}}
			v.owners = Array([]).duplicate()
			for y in 12:
				v.owners.append(",".join(row))
			v.hosts = [{"x": 5.0, "y": 6.0, "men": 400, "house": {"name": "House Goldcrest", "color": "#cc9900"}}]
			v.sieges = [Vector2(3, 4)]
		var how := "with the mirror" if mirror else "without the mirror (lore.gd)"
		var marks: Array = v._town_marks(Rect2(Vector2.ZERO, v.size)) if v.has_method("_town_marks") else []
		if marks.size() != 2 or not marks.any(func(m): return m["seat"] and m["named"]):
			print("FAIL v2 marks every town, the seat named, %s (%d marks)" % [how, marks.size()])
			fails += 1
		if v._sieges() != [Vector2(3, 4)]:
			print("FAIL v2 rings the besieged town %s" % how)
			fails += 1
		if v._hosts().size() != 1:
			print("FAIL v2 shows the host %s" % how)
			fails += 1
		var lands: Texture2D = v._lands_of()
		var img := lands.get_image() if lands else null
		if img == null or img.get_pixel(int((3 + 0.5) * 8), int((4 + 0.5) * 8)).a <= 0.0:
			print("FAIL v2 tints the house's lands %s" % how)
			fails += 1
		v.free()
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails else 0)
