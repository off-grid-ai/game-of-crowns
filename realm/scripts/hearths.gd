extends Node
## Chimney smoke only where someone's home (the finesse catalogue; Manor Lords and Tiny Glade, where a
## house smokes because a family is in). Reads the shared fact villagers.who_is_home and lights or
## damps each house's chimney (towns.gd tags each with its doorstep, group "hearths"). It decides
## nothing about the people; towns with no townsfolk drawn keep their smoke as built.
## A starving town (the mirror's town mood, from the bridge's famine) burns little: only a share
## of its hearths smoke even with someone home, and those thinly (hearths.json hunger).
## Knobs: realm/data/hearths.json. --hearths=off leaves every chimney as built.

var main: Node
var _d := {"on": true, "every_sec": 1.0, "door_match": 0.35}
var _wait := 0.0


func _init(owner: Node) -> void:
	main = owner
	name = "Hearths"


func _ready() -> void:
	var f := FileAccess.open("res://data/hearths.json", FileAccess.READ)
	var j = JSON.parse_string(f.get_as_text()) if f else null
	if j is Dictionary:
		_d.merge(j, true)


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0 or not bool(_d.get("on", true)) or main.towns == null or main.villagers == null:
		return
	_wait = float(_d.get("every_sec", 1.0))
	var town_of := {}
	for id in main.towns.towns:
		town_of[main.towns.towns[id]["node"]] = id
	var home_by_town := {}
	var hungry_town := {}
	var aw: Object = Engine.get_meta("awareness") if Engine.has_meta("awareness") else null
	for h in get_tree().get_nodes_in_group("hearths"):
		var smoke := h as GPUParticles3D
		var root := smoke.get_parent() as Node3D if smoke else null
		if root == null or not town_of.has(root):
			continue
		var id: int = town_of[root]
		if not main.villagers.crowds.has(id):
			continue  # no townsfolk drawn here: the chimney stays as built
		if not home_by_town.has(id):
			home_by_town[id] = main.villagers.who_is_home(id)
		var door: Vector3 = root.global_transform * (smoke.get_meta("door") as Vector3)
		var lit := false
		for at in home_by_town[id]:
			if Vector2((at as Vector3).x - door.x, (at as Vector3).z - door.z).length() < float(_d.get("door_match", 0.35)):
				lit = true
				break
		if not hungry_town.has(id):
			hungry_town[id] = aw != null and String(aw.town(id).get_var(&"mood", "", false)) == "hunger"
		var thin := 1.0
		if hungry_town[id]:
			var hg: Dictionary = _d.get("hunger", {})
			if float(absi(hash(Vector2i(roundi(door.x * 100.0), roundi(door.z * 100.0)))) % 1000) / 1000.0 >= float(hg.get("share", 0.5)):
				lit = false  # nothing to cook: this hearth stays cold
			thin = float(hg.get("thin", 0.35))
		if not is_equal_approx(smoke.amount_ratio, thin):
			smoke.amount_ratio = thin
		if smoke.emitting != lit:
			smoke.emitting = lit
