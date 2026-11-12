extends RefCounted
## Who is who and where in the towns' crowds (integration audit #10, villagers.gd split): the villager under a click
## (who_at), who a body is (who_is), who is home (who_is_home: hearths light their windows and smoke), and the town's
## feast fire (fire_of). Read-only answers over villagers.gd's crowds; villagers keeps the bodies, this answers for them.

var v: Node  # villagers.gd: the bodies and their towns


func _init(owner: Node) -> void:
	v = owner


## The villager nearest a point on the ground, within reach of a click:
## {town, i} so the bridge can say who they are, or empty.
func who_at(p: Vector3, reach := 0.35) -> Dictionary:
	var best := {}
	var best_d := reach
	for id in v.crowds:
		var list: Array = v.crowds[id]
		for i in list.size():
			var n: Node3D = list[i]["node"]
			var d := Vector2(n.position.x - p.x, n.position.z - p.z).length()
			if d < best_d:
				best_d = d
				best = {"town": int(id), "i": i, "node": n}
	return best


## Who a person on the ground is, for a word about them (chatter.mind_line):
## a villager's town, index and calling, or empty for anyone else.
func who_is(n: Node) -> Dictionary:
	return n.get_meta("folk", {}) if n else {}  # set at spawn: asked every look-round, never a search of every town


## Who's home (a shared fact, one owner; the finesse catalogue): the town's doorsteps with someone home
## now, as world positions -> how many. Home is gone in for the night (walked there and hidden indoors,
## this script's own night rule), or by day standing at their own door. Read by hearths.gd (chimney
## smoke only where someone's home) and the windows lit at dusk.
func who_is_home(id: int, reach := 0.3) -> Dictionary:
	var out := {}
	for a in v.crowds.get(id, []):
		if not a["placed"] or not PackedVector2Array(a["route"]).is_empty():
			continue
		var n: Node3D = a["node"]
		var h: Vector3 = a["home"]
		var inside: bool = a["block"] == "night" and not n.visible
		if inside or Vector2(n.position.x - h.x, n.position.z - h.z).length() < reach:
			out[h] = int(out.get(h, 0)) + 1
	return out


## The town's lit feast fire: [where (town-local), how far its reach goes],
## or empty. One fire per feast: town_life's bonfire, or a wedding feast's
## (scenes.gd), each recorded on the town's Life as "fires".
func fire_of(town: int) -> Array:
	var node: Node3D = v.towns.towns.get(town, {}).get("node")
	var life: Node = node.get_node_or_null("Life") if is_instance_valid(node) else null
	var fires: Array = life.get_meta("fires", []) if life else []
	return fires[0] if not fires.is_empty() else []
