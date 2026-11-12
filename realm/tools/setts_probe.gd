extends SceneTree
## Headless guard: the square's and streets' setts are laid at the size the data asks for (towns.json paving.tile: game
## units one sheet of about 7 stones covers, 0.3: stones about 0.35 m, 01-town's). Round 12 (Kingsmere): stones about
## twice that. General problem: a repeating ground texture capped at a fixed count of copies (terrain.gd tiled: 12
## across), so a surface wider than 12 sheets stretches each sheet instead of repeating it. The rule: the copies asked
## for are the copies drawn; a wide surface spends fewer pixels per copy (the image kept within MOST_PX). Asserts, for
## the crown's square (its paving span, towns.json square_r x paving.square) and a long street run:
##   - the texture holds the copies asked for, a part copy too (its meta "copies"), so one sheet covers paving.tile on
##     the ground both ways (a street narrower than a sheet once squeezed a whole one in, stones squashed);
##   - its image stays within MOST_PX on a side.
## Exit 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/setts_probe.gd

const Terrain := preload("res://scripts/terrain.gd")
const Towns := preload("res://scripts/towns.gd")
const MOST_PX := 2048
const Data := preload("res://scripts/data.gd")


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails: Array[String] = []
	var pave: Dictionary = Data.value("towns", "paving", {})
	var tile := float(pave.get("tile", 0.3))
	var stone := String(pave.get("texture", ""))
	var square_r := float(Towns.market_knobs_for("crown").get("square_r", 2.1))
	var span := square_r * float(pave.get("square", 2.7))
	var terrain: Node3D = Terrain.new()
	for c in [["the crown's square", Vector2(span, span * float(pave.get("square_aspect", 0.92))), "plaza"], ["a long street run", Vector2(0.4, 9.0), "paved"]]:
		var size: Vector2 = c[1]
		var want := Vector2(size.x / tile, size.y / tile)
		var tex: Texture2D = terrain.tiled(stone, want.x, want.y, String(c[2]))
		if tex == null:
			fails.append("%s: no texture (is %s on this machine?)" % [c[0], stone])
			continue
		var got: Vector2 = Vector2(tex.get_meta("copies", Vector2(tex.get_width() / 256, tex.get_height() / 256)))
		var sheet := Vector2(size.x / got.x, size.y / got.y)
		print("CHECK setts %s: %.2f x %.2f units, asked %.2f x %.2f copies, drawn %.2f x %.2f, one sheet covers %.2f x %.2f units (want %.2f), image %dx%d" % [c[0], size.x, size.y, want.x, want.y, got.x, got.y, sheet.x, sheet.y, tile, tex.get_width(), tex.get_height()])
		if absf(sheet.x / tile - 1.0) > 0.06 or absf(sheet.y / tile - 1.0) > 0.06:
			fails.append("%s: one sheet covers %.2f x %.2f units, the data asks %.2f" % [c[0], sheet.x, sheet.y, tile])
		if maxi(tex.get_width(), tex.get_height()) > MOST_PX:
			fails.append("%s: image %dx%d over %d" % [c[0], tex.get_width(), tex.get_height(), MOST_PX])
	terrain.free()
	for f in fails:
		print("SETTS FAIL " + f)
	print("SETTS %s" % ("PASS" if fails.is_empty() else "FAIL (%d)" % fails.size()))
	quit(0 if fails.is_empty() else 1)
