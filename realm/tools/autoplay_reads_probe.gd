extends SceneTree
## Headless check that the play harness reads what the game still has (the render pass's siege and breach frames,
## 2159: autoplay's breach step read main.scenes.get("_sieges") after the siege became its own scene kind (8419d7d3),
## got Nil ('Trying to assign value of type Nil to a variable of type Dictionary', siege.log:449, breach.log:517),
## framed nothing, and the frames showed town roofs). Every main.scenes.get("<name>") in autoplay.gd must name a
## member scenes.gd still declares. Exit 1 on a failure.
##   arch -arm64 godot --headless --path realm -s res://tools/autoplay_reads_probe.gd


func _init() -> void:
	var fails := 0
	var src := FileAccess.get_file_as_string("res://scripts/autoplay.gd")
	var scenes: Script = load("res://scripts/scenes.gd")
	var members := {}
	for p in scenes.get_script_property_list():
		members[String(p["name"])] = true
	var re := RegEx.new()
	re.compile("main\\.scenes\\.get\\(\"([A-Za-z_0-9]+)\"\\)")
	var n := 0
	for m in re.search_all(src):
		n += 1
		var name := m.get_string(1)
		if not members.has(name):
			print("FAIL autoplay.gd reads main.scenes.get(\"%s\"), which scenes.gd no longer has" % name)
			fails += 1
	print("autoplay reads of main.scenes: %d" % n)
	print("PASS" if fails == 0 else "FAIL %d" % fails)
	quit(1 if fails > 0 else 0)
