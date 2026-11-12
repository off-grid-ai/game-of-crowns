extends SceneTree
## Guard for the order main.gd shows a reading in (the army layer's reign replay, READY.md line 10: 60 view faults,
## companies with no figure or figures with no company, every one while the first reading was still laying the roads
## and the countryside). main._on_synced lays the roads and the countryside over several frames (awaits) on its first
## reading; whatever it syncs after that waits with it. The companies on the map (units.sync) are synced as soon as the
## towns stand, before that laying; the scenes, which walk the roads, after it. Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/sync_order_probe.gd

var fail := 0


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _init() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var at := src.find("func _on_synced(")
	var body := src.substr(at, src.find("\nfunc ", at + 10) - at)
	var towns := body.find("towns.sync(")
	var laying := body.find("if not _laying:")
	var units := body.find("units.sync(")
	var scenes := body.find("scenes.sync(")
	_check(towns >= 0 and laying > towns, "main._on_synced syncs the towns, then lays the roads and the countryside")
	_check(units > towns and units < laying, "the companies are synced before the laying's awaits (units.sync at %d, laying at %d)" % [units, laying])
	_check(body.count("units.sync(") == 1, "the companies are synced once a reading (%d)" % body.count("units.sync("))
	_check(scenes > laying, "the scenes, which walk the roads, after the roads are laid")
	print("VERDICT %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
