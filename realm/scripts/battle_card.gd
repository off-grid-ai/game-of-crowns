extends Node
## The King's battle, when it is over (CK3's battle summary; casebook, War and sieges: the battle reads at a glance):
## where, who won, each side's men and losses, the fallen and the spoils, told once as a line of the chronicle
## (chronicle_panel.gd notice; Mac: no cards in the corner, the chronicle is the source of truth). It decides nothing: the cards are the bridge's (battles.js), read
## from the view's one mirror (awareness.gd battles). A card the realm already had when the view came up is not told.

const Data := preload("res://scripts/data.gd")
const T := preload("res://scripts/theme.gd")
const Awareness := preload("res://scripts/awareness.gd")
const FILE := "host_command"

var main: Node
var _seen := {}  # card id -> true: told, or there before the view came up
var _primed := false
var _t := 0.0


func _init(m: Node) -> void:
	main = m
	name = "BattleCard"


func _process(delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(delta)
		return
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	preload("res://scripts/perf_tools.gd").add("battle_card", Time.get_ticks_usec() - t0)  # its share of the frame (GOC_PERF_PROBE)


func _process_timed(delta: float) -> void:
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var store: Node = Awareness.store()
	if store == null or main.ui == null:
		return
	var cards: Array = store.battles()
	if not _primed:
		if store.rec("cities", []).is_empty():
			return  # the realm isn't read yet
		_primed = true
		for c in cards:
			_seen[String(c.get("id", ""))] = true
		return
	for c in cards:  # newest first: the newest untold one is told
		var id := String(c.get("id", ""))
		if id == "" or _seen.has(id):
			continue
		_seen[id] = true
		_show(c)
		return


## One battle told as a line of the chronicle (Mac: "let the chronicle be the source of truth"): "Victory near
## Redmarch. The Crown held the field: 520 troops, 150 lost. The raiders: 150 troops, 150 lost. Fallen: Captain …",
## with what the King won. Words in host_command.json result.
func _show(c: Dictionary) -> void:
	var words: Dictionary = Data.value(FILE, "result", {})
	var won := String(c.get("crown", "")) == "won"
	var parts := PackedStringArray([String(words.get("head_won" if won else "head_lost", "{place}")).format({"place": String(c.get("place", ""))}) + "."])
	for s in c.get("sides", []):
		var who := String(s.get("name", ""))
		if int(s.get("house", -1)) == int(c.get("victor", -2)):
			who += " " + String(words.get("victor", "held the field"))
		parts.append("%s: %s, %s." % [who, String(words.get("men", "{men} troops")).format({"men": main.ui.heads(int(s.get("men", 0)))}), String(words.get("lost_words", "{lost} lost")).format({"lost": main.ui.heads(int(s.get("lost", 0)))})])
	var fell: Array = c.get("fell", []) if c.get("fell") is Array else []
	if not fell.is_empty():
		var names := ", ".join(fell.map(func(n): return String(words.get("captain", "Captain {name}")).format({"name": String(n)})))
		parts.append(String(words.get("fell", "Fallen: {names}")).format({"names": names}) + ".")
	var reward: Variant = c.get("reward")
	if reward is Dictionary and not (reward as Dictionary).is_empty():
		var said := PackedStringArray()
		var rows: Dictionary = words.get("reward", {})
		for k in reward:
			if rows.has(k) and reward[k] != null:
				said.append(String(rows[k]).format({"n": main.ui.heads(int(reward[k])) if (reward[k] is int or reward[k] is float) else String(reward[k])}))
		if not said.is_empty():
			parts.append(", ".join(said) + ".")
	main.ui.chronicle.notice(" ".join(parts), {"kind": "battle", "loss": not won})
	# The moment before the numbers (Total War's result banner): the word, and where. The crown's side comes first
	# (bridge battles.js card).
	var sides: Array = c.get("sides", [])
	var theirs_lost := 0
	for i in range(1, sides.size()):
		theirs_lost += int((sides[i] as Dictionary).get("lost", 0))
	var ours_lost := int((sides[0] as Dictionary).get("lost", 0)) if not sides.is_empty() else 0
	var place := String(c.get("place", "")).strip_edges()
	if place != "":
		place = place.left(1).to_upper() + place.substr(1)
	var field: Vector3 = main.terrain.world_pos(float(c["x"]), float(c["y"])) if c.has("x") and c.has("y") else Vector3.INF
	main.ui.moment.show(preload("res://scripts/moment_banner.gd").word_for(won, ours_lost, theirs_lost), place, not won, field)
