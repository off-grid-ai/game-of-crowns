extends SceneTree
## Guard for the town's sounds (integration audit #6; READY.md line 15, properly integrated): the market, the forge,
## the tavern and the church bells are heard where those buildings stand, never guessed from the town's size. The
## store (awareness.gd) takes a saved /world (realm/tools/fixtures/town_build_world.json); two towns are stood as
## towns.gd records them (meta places: the square's market, tavern and sept; meta trades: the forge, the armoury):
##   a big town (Dundee, size 4, no Marketplace) that stood no market, forge or tavern: none of them heard;
##   a small town (Hamilton, size 2) that stood all of them: all heard, the bells too.
## A siege comes from the store's town scope. And the old guesses are gone: soundscape hears nothing a town didn't
## name (no size fallback) and main.gd's _listen guesses no building from size or Freeciv names.
## Prints CHECK lines; exits 1 on a fail.
##   arch -arm64 godot --headless --path realm -s res://tools/sound_town_probe.gd

const Scape := preload("res://scripts/soundscape.gd")
const FIX := "res://tools/fixtures/town_build_world.json"
const BIG := 297  # Dundee, size 4, no Marketplace
const SMALL := 332  # Hamilton, size 2

var fail := 0


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 60.0)
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("CHECK %s %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		fail += 1


func _town(places: Dictionary, trades: Array) -> Node3D:
	var n := Node3D.new()
	n.set_meta("places", places)
	n.set_meta("trades", trades.map(func(c): return {"component": c}))
	root.add_child(n)
	return n


func _run() -> void:
	var world: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIX))
	var store: Node = load("res://scripts/awareness.gd").new()
	root.add_child(store)
	await process_frame
	store.dispatch(store.SYNC, {"world": world})
	var scape: Node = Scape.new()
	root.add_child(scape)
	_check(scape.has_method("town_sounds"), "soundscape.town_sounds reads the town from the store and what it stood")
	if scape.has_method("town_sounds"):
		var bare := _town({"well": Vector3.ZERO}, ["barn"])
		var big: Dictionary = scape.town_sounds(BIG, bare)
		_check(big.get("size") == 4 and not big.get("market", true) and not big.get("forge", true) and not big.get("tavern", true) and not big.get("church", true),
			"a size-4 town that stood no market, forge, tavern or church hears none of them: %s" % big)
		var full := _town({"well": Vector3.ZERO, "market": Vector3.ONE, "tavern": Vector3.ONE, "sept": Vector3.ONE}, ["forge", "barn"])
		var small: Dictionary = scape.town_sounds(SMALL, full)
		_check(small.get("size") == 2 and small.get("market") and small.get("forge") and small.get("tavern") and small.get("church"),
			"a size-2 town that stood them all hears them all: %s" % small)
		_check(not small.get("siege", true), "no siege where the store has none")
		store.town(SMALL).set_var(&"besieged", true)
		_check(scape.town_sounds(SMALL, full).get("siege", false), "a siege from the store's town scope")
		_check(scape.town_sounds(-1, full).is_empty(), "no town, no town sounds")
	# No size fallback: a town that names no building hears none.
	scape.set_view(5.0, {"size": 8}, "summer", false, "clear")
	var t: Dictionary = scape._targets()
	_check(float(t.get("market", 1.0)) == 0.0 and float(t.get("forge", 1.0)) == 0.0 and float(t.get("tavern", 1.0)) == 0.0,
		"soundscape guesses nothing from size (market %s, forge %s, tavern %s)" % [t.get("market"), t.get("forge"), t.get("tavern")])
	var main_src := FileAccess.get_file_as_string("res://scripts/main.gd")
	var at := main_src.find("func _listen(")
	var body := main_src.substr(at, main_src.find("\nfunc ", at + 10) - at)
	_check(at >= 0 and not body.contains("\"size\", 1)) >=") and not body.contains("Marketplace") and not body.contains("Temple"),
		"main.gd's _listen guesses no building")
	print("VERDICT %s (%d failed)" % ["PASS" if fail == 0 else "FAIL", fail])
	quit(1 if fail > 0 else 0)
