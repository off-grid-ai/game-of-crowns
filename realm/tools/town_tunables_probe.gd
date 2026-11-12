extends SceneTree
## Headless probe for integration audit #20 in town life's files (villagers, village_*, npc_mind, town_scenes,
## town_life, town_dress/, chatter, people): every gameplay knob is a data row Mac can tune while playing
## (docs/TUNING.md), with the value it had as a const, and none is left a numeric const in the code. Each row:
## [script, name, data file, dotted path, value]. Engine and calibration constants stay in code (an arrival's
## quarter metre, a sidestep's most a frame, a caption's pixel size, a clip's pace at speed 1).
##   arch -arm64 godot --headless --path realm --script res://tools/town_tunables_probe.gd

const Data := preload("res://scripts/data.gd")
const KNOBS := [
	["villagers", "VIEW_RADIUS", "crowd", "villagers.view_radius", 30.0],
	["villagers", "MAX_PER_TOWN", "crowd", "villagers.most_per_town", 40],
	["villagers", "WALK_SPEED", "crowd", "villagers.walk_speed", 0.17],
	["villagers", "CHILD_REACH", "crowd", "villagers.child_reach", 0.36],
	["villagers", "CHILD_SIDE", "crowd", "villagers.child_side", 0.12],
	["villagers", "SPACE", "crowd", "villagers.space", 0.07],
	["village_talk", "TALK_REACH", "crowd", "villagers.talk_reach", 0.3],
	["village_talk", "MIND_TALK_SECS", "crowd", "villagers.talk_lapse_secs", 40.0],
	["village_slots", "SHOULDER", "crowd", "villagers.shoulder", 0.11],
	["village_slots", "SQUARE_EDGE", "crowd", "villagers.square_edge", 0.6],
	["village_slots", "KNOT", "crowd", "villagers.knot_clear", 0.26],
	["npc_mind", "GIVE_UP", "crowd", "minds.give_up_secs", 3.0],
	["npc_mind", "NEAR", "crowd", "minds.partner_near", 2.5],
	["npc_mind", "TALK_GAP", "crowd", "minds.talk_gap", 0.14],
	["npc_mind", "FRESH_MS", "crowd", "minds.news_fresh_ms", 90000],
	["npc_mind", "BOOKED_MS", "crowd", "minds.booked_ms", 20000],
	["npc_mind", "WAIT_SECS", "crowd", "minds.partner_wait_secs", 8.0],
	["npc_mind", "LINE_CAP", "crowd", "minds.line_cap_secs", 25.0],
	["npc_mind", "SETTLED", "crowd", "minds.settled_secs", 0.4],
	["npc_mind", "SETTLE", "crowd", "minds.settle_secs", 4.0],
	["town_life", "KEEPER_BACK", "town_scenes", "life.keeper_back", 0.07],
	["town_life", "LANE", "town_scenes", "life.lane", 0.06],
	["town_life", "HEART", "town_scenes", "life.heart", 0.2],
	["town_life", "HEAT", "town_scenes", "life.heat", 0.06],
	["town_life", "SITE_SHOWS", "town_scenes", "life.site_shows", 0.35],
	["chatter", "HEAR", "crowd", "chatter.hear", 2.6],
	["chatter", "TOWN_NEAR", "crowd", "chatter.town_near", 9.0],
	["chatter", "OWN_WORDS_SECS", "crowd", "chatter.own_words_secs", 5.0],
	["chatter", "SAID_FRESH_MS", "crowd", "chatter.said_fresh_ms", 300000],
	["chatter", "NEWS_FRESH_MS", "crowd", "minds.news_fresh_ms", 90000],
	["people", "SEEN_TO", "people", "seen_to", 18.0],
	["people", "NEAR_GONE", "people", "near_fade.gone", 0.08],
	["people", "NEAR_SOLID", "people", "near_fade.solid", 0.18],
]


func _init() -> void:
	preload("res://tools/watchdog.gd").arm(self, 30.0)
	var fails := 0
	var tuning := FileAccess.get_file_as_string("res://../docs/TUNING.md")
	if tuning == "":
		tuning = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/TUNING.md"))
	for k in KNOBS:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % k[0])
		if RegEx.create_from_string("(?m)^\\s*const %s :?=" % k[1]).search(src) != null:
			fails += 1
			print("FAIL %s.gd: %s is still a const in the code" % [k[0], k[1]])
		var v: Variant = Data.value(String(k[2]), String(k[3]), null)
		if v == null:
			fails += 1
			print("FAIL %s.json has no %s (%s.%s)" % [k[2], k[3], k[0], k[1]])
		elif not is_equal_approx(float(v), float(k[4])):
			fails += 1
			print("FAIL %s.json %s is %s, the const was %s" % [k[2], k[3], v, k[4]])
		var key := String(k[3]).get_slice(".", 0)
		if not tuning.contains("realm/data/%s.json`: `%s" % [k[2], key]):
			fails += 1
			print("FAIL docs/TUNING.md has no line for %s.json %s" % [k[2], key])
	print("TUNABLES %s (%d knobs, %d fails)" % ["PASS" if fails == 0 else "FAIL", KNOBS.size(), fails])
	quit(1 if fails > 0 else 0)
