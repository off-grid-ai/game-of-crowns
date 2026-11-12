extends SceneTree
## Headless check that the view's gameplay knobs in the files no thread was editing are data rows, not code
## (integration audit #20, Godot side; READY.md line 15; Mac tunes while playing): each [script, const, data file,
## path] below is read from realm/data through data.gd, no numeric `const` of that name is left in its script, and
## docs/TUNING.md names the row. The triage of every numeric const: docs/research/tunables-triage-2026-11-12.md.
## Exit 1 on any failure.   arch -arm64 godot --headless --path realm -s res://tools/tunables_view_probe.gd

const MOVED := [
	["anim_lod", "NEAR", "people", "lod.near"],
	["anim_lod", "STRIDE", "people", "lod.stride"],
	["anim_lod", "MIND_UNSEEN", "people", "lod.mind_unseen"],
	["anim_lod", "MIND_LAG", "people", "lod.mind_lag"],
	["particles", "FAR", "fire", "particles_far"],
	["army_assault", "WAVE", "siege", "assault.wave"],
	["army_assault", "FALL", "siege", "assault.fall"],
	["army_assault", "WALK_S", "siege", "assault.walk"],
	["army_assault", "RUN_S", "siege", "assault.run"],
	["army_melee", "CROWD_SEEN", "battle", "crowd_seen"],
	["blood", "MAX_STAINS", "battle", "blood_stains"],
	["combat", "REACH", "battle", "combat.reach"],
	["combat", "ARC", "battle", "combat.arc"],
	["combat", "FOLLOW", "battle", "combat.follow"],
	["combat", "DODGE", "battle", "combat.dodge"],
	["combat", "HURT_FOR", "battle", "combat.hurt_for"],
	["combat", "WEAK", "battle", "combat.weak"],
	["reign_cards", "ACT_SECONDS", "ui", "reign_cards.act_seconds"],
	["folk_tip", "NEAR", "ui", "folk_tip.near"],
	["folk_tip", "MARKS_NEAR", "ui", "folk_tip.marks_near"],
	["mic", "SPEECH", "ui", "mic.speech"],
	["mic", "QUIET_FOR", "ui", "mic.quiet_for"],
	["mic", "SHORTEST", "ui", "mic.shortest"],
	["director", "IDLE_SECONDS", "camera", "director.idle_seconds"],
	["director", "SHOT_SECONDS", "camera", "director.shot_seconds"],
	["camera_rig", "OVERVIEW", "camera", "rig.overview"],
	["camera_rig", "EASE", "camera", "rig.ease"],
	["camera_rig", "NEAREST", "camera", "rig.nearest"],
	["camera_rig", "STEEPEST", "camera", "rig.steepest"],
	["camera_rig", "GUARD", "camera", "rig.guard"],
	["camera_rig", "LENS_SPEED", "camera", "rig.lens_speed"],
	["camera_rig", "LENS_REACH", "camera", "rig.lens_reach"],
	["camera_rig", "LENS_EASE", "camera", "rig.lens_ease"],
	["weather_fx", "RAIN_DROPS", "weather", "drops.rain"],
	["weather_fx", "SNOW_FLAKES", "weather", "drops.snow"],
	["weather_fx", "PREVAILING_FROM", "weather", "prevailing_from"],
	["main", "DAY_SECONDS", "weather", "day_seconds"],
	["main", "UI_MIN", "ui", "scale.min"],
	["main", "UI_MAX", "ui", "scale.max"],
	["land3d", "FLOOD_S", "map", "flood_seconds"],
	["minimap", "FLOOD_S", "map", "flood_seconds"],
	["political_overlay", "RAZED_BURN", "map", "razed_burn"],
	["vegetation", "VEG_REACH", "ground", "wild.reach"],
	["presence", "NEAR_CAM", "crowd", "presence.near_cam"],
	["presence", "NOTICE", "crowd", "presence.notice"],
	["presence", "FRONT", "crowd", "presence.front"],
	["presence", "RESTED", "crowd", "presence.rested"],
	["presence", "SWITCH", "crowd", "presence.switch"],
	["presence", "GREET", "crowd", "presence.greet"],
	["presence", "GREET_AGAIN", "crowd", "presence.greet_again"],
	["army_skirmish", "ROW", "battle", "skirmish.row"],
	["army_skirmish", "SPAN", "battle", "skirmish.span"],
	["motion", "XFADE_HIT", "people", "motion.xfade_hit"],
	["motion", "SETTLE", "people", "motion.settle"],
	["motion", "XFADE_STAND", "people", "motion.xfade_stand"],
	["motion", "TURN_EASE", "people", "motion.turn_ease"],
	["motion", "STEP_FLOOR", "people", "motion.step_floor"],
	["motion", "STEP_CEIL", "people", "motion.step_ceil"],
	["units", "MARCH_SPEED", "army", "map.march_speed"],
	["units", "WOUNDED_HP", "army", "map.wounded_hp"],
	["countryside", "NEAR_TOWN", "countryside", "near_town"],
	["countryside", "CROP_SWAY", "countryside", "crop.sway"],
	["countryside", "CROP_CUT", "countryside", "crop.cut"],
	["countryside", "CROP_REACH", "countryside", "crop.reach"],
	["countryside", "TUFT_REACH", "countryside", "tuft_reach"],
	["forest", "NEAR", "forest", "near"],
	["forest", "MID", "forest", "mid"],
	["roads", "WIDTH", "ground", "roads.width"],
	["roads", "ROAD_REACH", "ground", "roads.reach"],
]


func _init() -> void:
	var data := preload("res://scripts/data.gd")
	var tuning := FileAccess.get_file_as_string("res://../docs/TUNING.md")
	if tuning.is_empty():
		tuning = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../docs/TUNING.md"))
	var bad := 0
	for row in MOVED:
		var src := FileAccess.get_file_as_string("res://scripts/%s.gd" % row[0])
		var re := RegEx.create_from_string("(?m)^const %s\\s*(?::\\s*\\w+\\s*)?:?=\\s*-?[0-9]" % row[1])
		if re.search(src):
			print("FAIL %s.gd keeps %s in code" % [row[0], row[1]]); bad += 1
		if data.value(row[2], row[3], null) == null:
			print("FAIL realm/data/%s.json has no %s" % [row[2], row[3]]); bad += 1
		var key: String = row[3].get_slice(".", row[3].get_slice_count(".") - 1)
		if tuning.find("realm/data/%s.json" % row[2]) < 0 or tuning.find("`%s`" % key) < 0 and tuning.find(".%s`" % key) < 0:
			print("FAIL docs/TUNING.md doesn't name %s.json %s" % [row[2], row[3]]); bad += 1
	print("%d knobs; " % MOVED.size() + ("PASS" if bad == 0 else "FAIL %d" % bad))
	quit(1 if bad else 0)
