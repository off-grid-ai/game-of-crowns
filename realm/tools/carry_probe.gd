extends SceneTree
## What a person carries reads as what their errand carries (no GPU). The arms' move is shared (Mixamo's Carrying),
## so the prop in hand decides what the load is: weapons.gd CLIP_TOOLS gives a move's own prop (a basket for
## Carrying), people.json loads gives a calling its own load over it. Made through people.gd as the game makes them,
## each row of CHECKS asks for the move on a person of that calling (folk.role, villagers.gd) and wants that prop in
## hand. Before people.json loads, the square's water carrier walked home from the well with a basket.
##   arch -arm64 godot --headless --path realm -s res://tools/carry_probe.gd

const CHECKS := [["water", "Carrying", "pail"], ["porter", "Carrying", "basket"], ["market", "Carrying", "basket"], ["water", "Watering", "pail"]]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var P = load("res://scripts/people.gd").new()
	root.add_child(P)
	var W := preload("res://scripts/weapons.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var fails := 0
	for c in CHECKS:
		var p: Node3D = P.make(rng, "townsfolk", Color.WHITE, "adult")
		p.set_meta("folk", {"town": 0, "i": 0, "role": String(c[0])})
		root.add_child(p)
		await process_frame
		W.hold_for(p, String(c[1]))
		var got := String(p.get_meta("tool", ""))
		var ok := got == String(c[2])
		fails += 0 if ok else 1
		print("CARRY %s %s's %s holds %s (want %s)" % ["ok  " if ok else "FAIL", c[0], c[1], got if got != "" else "nothing", c[2]])
		p.queue_free()
	print("CARRY VERDICT: %s" % ("PASS" if fails == 0 else "FAIL"))
	quit(1 if fails > 0 else 0)
