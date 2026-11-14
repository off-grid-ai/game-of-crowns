extends SceneTree
## Bakes the one AnimationLibrary every person plays (people.gd LIBRARY): the Mixamo moves (assets/anims/mixamo), the
## UAL set (but its UAL_SKIP clips) and the close-up's gestures (HERO_ANIMS), each clip in place (People._in_place),
## the feet planted (_plant) and the turns unturned (_unturn, their measured turns kept as the library's "turned" meta).
## Loading the 184 FBX at startup held the app before its first frame (Mac's P0, "application not responding"); the
## game now reads this one file on Godot's background loader.
##
## Headless, no GPU: arch -arm64 godot --headless --path . -s res://tools/anim_library_bake.gd
## Re-run after a move is added or changed.

const People := preload("res://scripts/people.gd")


func _initialize() -> void:
	# Mixamo moves, retargeted at import to Godot's humanoid skeleton like the
	# outfits, so any Mixamo download plays on any townsperson. Each file is one
	# move, named for what the game asks for ("Walk", "Sword_Idle", "Praying").
	var lib := AnimationLibrary.new()
	var dir := DirAccess.open(People.ANIMS)
	for f in dir.get_files() if dir else []:
		if not f.ends_with(".fbx"):
			continue
		var packed := load(People.ANIMS + f) as PackedScene
		if packed == null:
			continue
		var src: Node = packed.instantiate()
		var players: Array = src.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			var player: AnimationPlayer = players[0]
			for n in player.get_animation_list():
				var a: Animation = player.get_animation(n)
				if a.length > 0.1:
					lib.add_animation(f.get_basename(), People._in_place(a.duplicate(true)))
					break
		src.free()
	# The UAL set, each clip under its own name unless the crowd has one already.
	if ResourceLoader.exists(People.UAL):
		var ual: Node = (load(People.UAL) as PackedScene).instantiate()
		for ap in ual.find_children("*", "AnimationPlayer", true, false):
			for n in (ap as AnimationPlayer).get_animation_list():
				var nm := String(n)
				if lib.has_animation(nm) or People.UAL_SKIP.any(func(k): return nm.contains(k)):
					continue
				var a: Animation = (ap as AnimationPlayer).get_animation(n)
				if a.length > 0.1:
					lib.add_animation(nm, People._in_place(a.duplicate(true)))
		ual.free()
	# The close-up's own gestures too (Shake No, Dismiss, Relieved Sigh, Talking
	# Hands...), retargeted the same way, named with underscores; a move the
	# crowd already has keeps the crowd's take.
	var hero_dir := DirAccess.open(People.HERO_ANIMS)
	for f in hero_dir.get_files() if hero_dir else []:
		if not f.ends_with(".fbx"):
			continue
		var name: String = String(f).get_basename().replace(" ", "_")
		if lib.has_animation(name):
			continue
		var packed := load(People.HERO_ANIMS + f) as PackedScene
		if packed == null:
			continue
		var src: Node = packed.instantiate()
		var players: Array = src.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			var player: AnimationPlayer = players[0]
			for n in player.get_animation_list():
				var a: Animation = player.get_animation(n)
				if a.length > 0.1:
					lib.add_animation(name, People._in_place(a.duplicate(true)))
					break
		src.free()
	People._plant(lib)
	People._unturn(lib)


	lib.set_meta("turned", People.TURNED)
	var err := ResourceSaver.save(lib, People.LIBRARY, ResourceSaver.FLAG_COMPRESS)
	print("ANIM LIBRARY %d clips -> %s (%s)" % [lib.get_animation_list().size(), People.LIBRARY, error_string(err)])
	quit(0 if err == OK else 1)
