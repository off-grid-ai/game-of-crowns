extends SceneTree
## A guard: a siege on screen storms only on Freeciv's assault and ends as Freeciv decided (READY.md line 6; the
## bridge half: bridge/tools/storm_probe.mjs). army_assault.gd with a breach already open: before storm() it hands out
## no gap (the massed host stands ready and fires arrows, the parties brace); storm(true) (Freeciv gave the
## besiegers the town) leaves the holder no fresh men, so its block wears down and breaks; storm(false) (the town
## held) leaves it more than any storm can spend. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/storm_view_probe.gd

const ArmyAssault := preload("res://scripts/army_assault.gd")


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	var fail := 0
	for taken in [true, false]:
		var a: Node = ArmyAssault.new()
		if not a.has_method("storm"):
			print("CHECK storm view: army_assault.gd has no storm(taken): FAIL")
			a.free()
			quit(1)
			return
		var key := Vector3i(1, 0, 1)
		a._held_at[key] = {"gap": Vector3(0.1, 0, 0.1), "inward": Vector3.FORWARD, "across": Vector3.RIGHT, "men": [], "reserve": 4, "phase": "hold", "at": 0.0}
		var before: bool = (a.breach() as Dictionary).is_empty()
		a.storm(taken)
		var gap: Dictionary = a.breach()
		var reserve := int(a._held_at[key]["reserve"])
		var ok := before and not gap.is_empty() and (reserve == 0 if taken else reserve > 1000)
		print("CHECK storm view (%s): no gap before the storm %s, the gap in it %s, the holder's fresh men %d (want %s): %s" % [
			"taken" if taken else "held", before, not gap.is_empty(), reserve, "0" if taken else "endless", "PASS" if ok else "FAIL"])
		if not ok:
			fail += 1
		a.free()
	print("CHECK storm view: %s" % ("PASS" if fail == 0 else "%d FAIL" % fail))
	quit(1 if fail > 0 else 0)
