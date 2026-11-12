extends SceneTree
## Headless check that every kind of scene the realm plays is its own class (integration audit #11; READY.md line 15,
## properly integrated; casebook, Immersion: "Let the world speak"), no GPU. For each row of scene_kinds.gd KINDS that
## names a class ("play"): the class loads and extends scene_kind.gd, and scenes.gd keeps no staging function of its
## own for that kind (the old one is gone: one place per kind). Then each moved kind is staged once on a stand-in realm
## (flat land, no towns) through scenes.gd's own dispatch, and what it sets down is counted.
##   arch -arm64 godot --headless --path realm --script res://tools/scene_kinds_probe.gd

const SceneKinds := preload("res://scripts/scene_kinds.gd")
const SceneKind := preload("res://scripts/scene_kind.gd")
const Scenes := preload("res://scripts/scenes.gd")

## The staging function scenes.gd had for each kind before it became a class: none may stand there now.
const OLD := {"feast": "_feast", "handover": "_handover", "grain": "_convoy", "tribute": "_convoy", "ward": "_convoy",
	"rider": "_rider", "muster": "_muster", "battle": "_battle", "siege": "_siege", "storm": "storm",
	"sack": "_burn", "razed": "_burn", "famine": "_refugees", "plague": "_refugees"}

## The kinds that are their own class by now (grows a kind a commit, till scenes.gd stages none itself).
const CLASSED := ["feast"]

## What each kind, staged on the stand-in, must set down: [the node's name under the stage, the least of its children].
const STAGED := {"feast": ["Feast", 10]}


class Land extends Node3D:
	func world_pos(tx: float, ty: float) -> Vector3:
		return Vector3(tx, 0, ty)
	func height_at(_x: float, _z: float) -> float:
		return 0.0
	func is_land(_x: float, _z: float) -> bool:
		return true
	func walkable(_x: float, _z: float) -> bool:
		return true


class Main extends Node:
	var towns = null
	var roads = null


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self)
	_run.call_deferred()


func _run() -> void:
	var fails := 0
	var moved: Array = []
	for k in SceneKinds.KINDS:
		var path := String(SceneKinds.of(k).get("play", ""))
		if path == "":
			continue
		moved.append(k)
		var cls: Variant = load(path)
		var ok: bool = cls is GDScript and _inherits(cls as GDScript, SceneKind)
		var old := String(OLD.get(k, ""))
		var left: bool = old != "" and Scenes.new().has_method(old)
		print("KINDS %-9s %s: %s, scenes.gd's own %s %s" % [k, path.get_file(), "a scene kind" if ok else "NOT a scene kind", old, "still there" if left else "gone"])
		if not ok or left:
			print("FAIL %s: its class isn't a scene_kind.gd, or scenes.gd still stages it itself" % k)
			fails += 1
	for k in CLASSED:
		if not moved.has(k):
			print("FAIL %s: no class of its own (scene_kinds.gd KINDS play)" % k)
			fails += 1
	var still: Array = SceneKinds.KINDS.keys().filter(func(k): return not moved.has(k) and OLD.has(k))
	print("KINDS moved %d: %s; still in scenes.gd: %s" % [moved.size(), str(moved), str(still)])
	# Staged once each, through scenes.gd's own dispatch.
	var main := Main.new()
	root.add_child(main)
	var land := Land.new()
	main.add_child(land)
	var stage: Node3D = Scenes.new()
	stage.terrain = land
	main.add_child(stage)
	for k in moved:
		if not STAGED.has(k):
			continue
		stage.kind(k).play({"kind": k, "owner": 1}, Vector3(10, 0, 10), {1: {"name": "Ashby", "color": "#884422"}})
		await process_frame
		var want: Array = STAGED[k]
		var n: Node = stage.get_node_or_null(String(want[0]))
		var count: int = n.get_child_count() if n else 0
		print("KINDS staged %-9s %s with %d things in it" % [k, want[0] if n else "nothing", count])
		if count < int(want[1]):
			print("FAIL %s: staged %d things, want at least %d" % [k, count, int(want[1])])
			fails += 1
	print("KINDS VERDICT: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(1 if fails > 0 else 0)


static func _inherits(s: GDScript, base: GDScript) -> bool:
	var b: Script = s
	while b:
		if b == base:
			return true
		b = b.get_base_script()
	return false
