extends SceneTree
## Guard for the view's one store (awareness.gd; READY.md line 11, docs/TOWN_LIFE.md), no GPU needed. A fake bridge
## sends a /world; the store must take it itself (world_updated -> SYNC), fill every slice (records, realm, towns,
## land, hosts), say `synced` once, carry each scene as news once to the minds within reach, and change a mind only
## through its actions (JOIN, ASSIGN). A new chronicle (realm_changed) clears the records.
##   arch -arm64 godot --headless --path realm --script res://tools/store_probe.gd

const Watchdog := preload("res://tools/watchdog.gd")
const Awareness := preload("res://scripts/awareness.gd")

var _fails: Array[String] = []


class FakeBridge extends Node:
	signal world_updated(world: Dictionary)
	signal realm_changed


class FakeTerrain extends Node3D:
	var width := 8
	func world_pos(x: float, y: float) -> Vector3:
		return Vector3(x, 0, y)


func _ok(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		_fails.append(what)


func _init() -> void:
	Watchdog.arm(self, 60.0)
	_run.call_deferred()


func _run() -> void:
	var bridge := FakeBridge.new()
	root.add_child(bridge)
	var terrain := FakeTerrain.new()
	root.add_child(terrain)
	var store: Node = Awareness.new()
	store.bridge = bridge
	store.terrain = terrain
	root.add_child(store)
	var synced := [0]
	store.synced.connect(func(): synced[0] += 1)
	var cleared := [0]
	store.cleared.connect(func(): cleared[0] += 1)
	# A mind joins its town with its own state, through the store.
	var body := Node3D.new()
	root.add_child(body)
	var mind := BTPlayer.new()
	body.add_child(mind)
	store.attach(mind, 7, {"post": Vector3(1, 0, 1), "firefight": false})
	_ok(mind.is_in_group("minds") and int(mind.get_meta("town")) == 7, "JOIN: the mind is in its town")
	_ok(mind.blackboard.get_var(&"post", null, false) == Vector3(1, 0, 1), "JOIN: its starting state landed")
	var world := {"turn": 12, "turnSeconds": 40.0, "bands": {"loyal": 80, "steady": 50, "cooling": 30},
		"date": {"season": "winter"}, "crown": {"treasury": 300, "tithe": 0.2},
		"players": [{"id": 1, "favour": 40, "house": {"name": "Ashford", "crown": true}}, {"id": 2, "house": {"name": "Vane"}}],
		"cities": [{"id": 7, "owner": 1, "x": 1, "y": 1, "atWar": true, "mood": "uneasy", "damage": {"burnt": 0.25}}],
		"units": [{"type": "Pikemen", "owner": 2, "x": 5, "y": 5}],
		"scenes": [{"id": "s1", "kind": "rider", "owner": 1, "x": 1, "y": 1}, {"id": "s2", "kind": "muster", "city": 7, "turn": 12, "x": 1, "y": 1}],
		"marks": [[1, 1]], "seatId": 7}
	bridge.world_updated.emit(world)
	_ok(synced[0] == 1, "SYNC: the store took /world itself and said synced once")
	_ok((store.rec("cities", []) as Array).size() == 1 and int(store.rec("seatId", -1)) == 7, "records: cities and the seat")
	_ok(store.houses_by_id().get(2, {}).get("name", "") == "Vane" and store.city(7).get("owner") == 1, "records: houses by id, a city by id")
	_ok(int(store.realm.get_var(&"turn", 0, false)) == 12 and String(store.realm.get_var(&"season", "", false)) == "winter", "realm: turn and season")
	_ok(String(store.realm.get_var(&"weather", "", false)) == "snow" and Awareness.season_seconds == 40.0, "realm: weather and the season's length")
	var bb: Blackboard = store.town(7)
	_ok(bool(bb.get_var(&"at_war", false, false)) and bool(bb.get_var(&"levy", false, false)) and bool(bb.get_var(&"crown_town", false, false)), "towns: at war, levy, the crown's")
	_ok(is_equal_approx(float(bb.get_var(&"burnt", 0.0, false)), 0.25), "towns: burnt share")
	_ok((store.realm.get_var(&"armies", [], false) as Array).size() == 1 and (store.realm.get_var(&"marks", [], false) as Array).size() == 1, "hosts and land")
	_ok(mind.blackboard.get_var(&"at_war", false) == true, "a mind reads its town up the chain")
	var memory: Array = mind.blackboard.get_var(&"memory", [], false)
	_ok(memory.size() == 2 and memory.any(func(m): return m["kind"] == "king"), "news: the King's rider and the muster reached the mind")
	bridge.world_updated.emit(world)
	_ok((mind.blackboard.get_var(&"memory", [], false) as Array).size() == 2 and synced[0] == 2, "news: each scene is news once")
	store.assign(mind, {"firefight": true})
	_ok(mind.blackboard.get_var(&"firefight", false, false) == true, "ASSIGN: a decider's part lands on the mind")
	bridge.realm_changed.emit()
	_ok(store.rec("cities") == null and synced[0] == 2 and cleared[0] == 1, "a new chronicle clears the records, says cleared, redraws nothing")
	print("STORE PROBE: %s" % ("PASS" if _fails.is_empty() else "FAIL (%d)" % _fails.size()))
	quit(0 if _fails.is_empty() else 1)
