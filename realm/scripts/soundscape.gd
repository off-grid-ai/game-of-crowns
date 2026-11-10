extends Node
## The realm's sound: ambience beds that follow the camera, stingers on events,
## music that follows the realm's mood, quiet UI sounds, and ducking under
## voices. Owns the audio buses (made at runtime; no bus layout file):
##   Master <- Music, Ambience, SFX, Voice, UI
## Music and Ambience also carry a compressor keyed by the Voice bus, so any
## line played on "Voice" pulls them down by itself; voice_started/ended adds a
## deeper, slower dip on top. Design and asset list: AUDIO.md.
##
## API (all safe to call every frame; missing files are skipped silently):
##   set_view(zoom_distance: float, near_town: Dictionary, season: String,
##            night: bool, weather := "clear")
##       Every frame (or a few times a second) from main.gd. zoom_distance is
##       rig.distance (0.35 close .. 260 whole realm). near_town is the town
##       under the camera, {} for none; keys read (all optional):
##       size:int, market/forge/church/tavern/coastal/river/north/siege:bool.
##       season: spring|summer|autumn|winter. weather: clear|rain|snow|storm.
##   set_interior(room: String)   great_hall|tavern|chapel|cottage, "" for out.
##   event(kind: String, at := Vector3.INF)
##       A stinger. Kinds: battle, battle_end, clash, horn, siege, feast,
##       death, crown (succession, coronation), marriage, alliance, dead
##       (the dead beyond the wall), famine, plague, rebellion (civil_war,
##       raid), sack (city_destroyed, razed), handover (city_transferred),
##       unit_killed. Unknown kinds do nothing. `at` places it in the world.
##   mood(kind: String)   calm|court|feast|tension|dead|battle. The realm's
##       standing mood; battle/feast/dead events lift it for a while on their own.
##   ui(kind: String)     click|open|close|page|seal|decree|parchment|quill|error.
##   footstep(surface: String, at: Vector3)   grass|wood|snow (the lord you control).
##   voice_started() / voice_ended()   around each spoken line.
##   voice_bus() -> String   "Voice": set the voice player's bus to this.
##   set_volume(bus: String, linear: float) / volume(bus) -> float

const ROOT := "res://assets/audio/"
const BUSES := {"Music": -6.0, "Ambience": -4.0, "SFX": -2.0, "Voice": 0.0, "UI": -8.0}
const DUCK_MUSIC_DB := -9.0  # extra dip while someone speaks
const DUCK_AMB_DB := -5.0
const FADE := 0.6  # seconds for an ambience layer to move halfway to its target

# Ambience layers: file and loudness (dB) at full presence.
const BEDS := {
	"realm_wind": ["ambience/realm_wind.ogg", -4.0],
	"realm_sea": ["ambience/realm_sea.ogg", -6.0],
	"shore_gulls": ["ambience/shore_gulls.ogg", -10.0],
	"town_day": ["ambience/town_day.ogg", -6.0],
	"town_bustle": ["ambience/town_bustle.ogg", -9.0],
	"market": ["ambience/market.ogg", -8.0],
	"forge": ["ambience/forge.ogg", -9.0],
	"tavern": ["ambience/tavern.ogg", -8.0],
	"birds_day": ["ambience/birds_day.ogg", -6.0],
	"forest": ["ambience/forest.ogg", -9.0],
	"night": ["ambience/night.ogg", -5.0],
	"crows": ["ambience/crows.ogg", -12.0],
	"rain": ["ambience/rain.ogg", -3.0],
	"storm": ["ambience/storm.wav", -4.0],  # rain and thunder (DoKashiteru, CC-BY 3.0)
	"rain_roof": ["ambience/rain_roof.ogg", -4.0],
	"snow_wind": ["ambience/snow_wind.ogg", -5.0],
	"campfire": ["ambience/campfire.ogg", -6.0],
	"river": ["ambience/river.ogg", -10.0],
	"dead_north": ["ambience/dead_north.ogg", -6.0],
	"battle": ["sfx/battle_loop.ogg", -2.0],
	"battle_far": ["sfx/battle_far.ogg", -6.0],
	"feast": ["sfx/feast_cheers.ogg", -6.0],
	"drums": ["sfx/war_drums.ogg", -6.0],
}

# Music by mood. Calm plays with long silences between pieces; the rest back to back.
const MUSIC := {
	"calm": ["calm_achaidh_cheide", "calm_teller_of_tales", "calm_shores_of_avalon", "calm_exploration", "calm_harvest_season", "calm_vikings_at_shore"],
	"court": ["court_suonatore_di_liuto", "court_lord_of_the_land"],
	"feast": ["feast_master_of_the_feast"],
	"tension": ["tension_darkest_child", "tension_dark_times", "tension_lament_warriors_soul", "tension_lament_of_the_war"],
	"dead": ["dead_unseen_horrors", "dead_something_approaches"],
	"battle": ["battle_five_armies", "battle_heroic_age", "battle_for_the_king", "battle_viking_march"],
}
const MUSIC_DB := {"calm": -4.0, "court": -5.0, "feast": -3.0, "tension": -3.0, "dead": -2.0, "battle": -1.0}
const CALM_GAP := Vector2(25.0, 70.0)  # seconds of silence between calm pieces

# Stingers: kind -> list of [takes, dB, delay s]; beds lifted: kind -> [bed, seconds].
# Takes split by "|" play as one AudioStreamRandomizer: never the same take twice
# running. The war horn sounds only for what's hostile (war, raids, rebellion,
# sacks, a lord's treachery: main.gd sends "horn"); a town handed over in peace
# gets a quiet fanfare.
const STINGS := {
	"battle": [["sfx/war_horn.ogg|sfx/war_horn_near.ogg", -2.0, 0.0], ["sfx/charge_yell.ogg", -4.0, 2.5]],
	"clash": [["sfx/sword_clash_1.wav|sfx/sword_clash_2.wav|sfx/sword_clash_3.wav", -6.0, 0.0]],
	"unit_killed": [["sfx/sword_clash_1.wav|sfx/sword_clash_2.wav|sfx/sword_clash_3.wav|sfx/hit_metal_0.wav|sfx/hit_metal_1.wav|sfx/hit_metal_2.wav|sfx/hit_plate_0.wav|sfx/hit_plate_1.wav|sfx/hit_plate_2.wav|sfx/hit_metal_3.ogg|sfx/hit_metal_4.ogg|sfx/hit_plate_3.ogg|sfx/hit_plate_4.ogg", -8.0, 0.0]],
	"horn": [["sfx/war_horn.ogg|sfx/war_horn_near.ogg", -3.0, 0.0]],
	"siege": [["sfx/war_horn.ogg|sfx/war_horn_near.ogg", -3.0, 0.0], ["sfx/catapult.ogg", -4.0, 4.0]],
	"feast": [["sfx/cheer.ogg", -6.0, 0.0]],
	"death": [["sfx/funeral_bell.ogg", -3.0, 0.0]],
	"crown": [["sfx/fanfare.ogg", -3.0, 0.0], ["sfx/cheer.ogg", -8.0, 3.0], ["ambience/church_bells.ogg", -8.0, 5.0]],
	"marriage": [["ambience/church_bells.ogg", -5.0, 0.0], ["sfx/cheer.ogg", -10.0, 4.0]],
	"alliance": [["sfx/fanfare.ogg", -8.0, 0.0]],
	"dead": [["sfx/dead_horde.ogg", -2.0, 0.0], ["sfx/wolf_howl.ogg", -6.0, 6.0]],
	"famine": [["sfx/famine_drone.ogg", -6.0, 0.0], ["sfx/toll_bell.ogg", -8.0, 2.0]],
	"plague": [["sfx/toll_bell.ogg", -5.0, 0.0]],
	"rebellion": [["sfx/war_horn.ogg|sfx/war_horn_near.ogg", -4.0, 0.0]],
	"sack": [["sfx/war_horn.ogg|sfx/war_horn_near.ogg", -3.0, 0.0], ["sfx/toll_bell.ogg", -8.0, 3.0]],
	"handover": [["sfx/fanfare.ogg", -14.0, 0.0]],
	"vigil": [["sfx/war_drums.ogg", -12.0, 0.0]],  # a slow drum while the town gathers in silence (a hanging, never shown)
	"rider": [["sfx/gallop.ogg", -8.0, 0.0]],  # the King's rider sets out
	"muster": [["sfx/march.ogg", -6.0, 0.0], ["sfx/charge_yell.ogg", -14.0, 1.5]],  # men gather and march out
}
const ALIASES := {"succession": "crown", "coronation": "crown", "reign_end": "death", "civil_war": "rebellion",
	"raid": "rebellion", "city_destroyed": "sack", "razed": "sack", "city_transferred": "handover"}
const LIFT_BED := {"battle": ["battle", 40.0], "siege": ["drums", 45.0], "feast": ["feast", 50.0], "dead": ["dead_north", 90.0]}
const LIFT_MOOD := {"battle": ["battle", 60.0], "siege": ["battle", 60.0], "feast": ["feast", 90.0], "dead": ["dead", 120.0],
	"death": ["tension", 40.0], "famine": ["tension", 60.0], "rebellion": ["tension", 60.0], "sack": ["tension", 60.0]}
const UI_SOUNDS := {"click": ["ui/click.wav", -6.0], "open": ["ui/open.wav", -4.0], "close": ["ui/close.wav", -6.0],
	"page": ["ui/page.wav", -6.0], "seal": ["ui/seal.wav", 0.0], "decree": ["ui/seal.wav", 0.0],
	"parchment": ["ui/parchment.wav", -3.0], "quill": ["ui/quill.wav", -4.0], "error": ["ui/error.wav", -8.0],
	"coins": ["sfx/coins.wav|sfx/coins_1.ogg|sfx/coins_2.ogg", -6.0]}  # the treasury pays for a decree
const MAX_STINGERS := 12

var _beds := {}  # name -> {player, level (0..1), target}
var _cache := {}  # path -> AudioStream or null
var _view := {"d": 120.0, "town": {}, "season": "summer", "night": false, "weather": "clear"}
var _interior := ""
var _lift_bed := {}  # bed -> seconds left
var _lift_mood := ["", 0.0]  # mood, seconds left
var _base_mood := "calm"
var _playing_mood := ""
var _music: Array[AudioStreamPlayer] = []
var _music_on := 0  # which of the two players is current
var _music_gap := 3.0  # silence left before the next piece
var _last_track := ""
var _speaking := 0
var _speak_time := 0.0
var _duck := 0.0  # 0..1
var _bells_in := 60.0
var _ui_last := {}
var _stingers := 0
var _lowpass: AudioEffectLowPassFilter
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	# Every clip anyone plays (people.gd): the work and the walking are heard in time with the move.
	preload("res://scripts/people.gd").listen(_on_clip)
	for bus in BUSES:
		_bus(bus, BUSES[bus])
	for bus in ["Music", "Ambience"]:
		var c := AudioEffectCompressor.new()
		c.sidechain = "Voice"
		c.threshold = -28.0
		c.ratio = 4.0
		c.attack_us = 20000.0
		c.release_ms = 450.0
		AudioServer.add_bus_effect(AudioServer.get_bus_index(bus), c)
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Ambience"), _lowpass)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	_music[0].finished.connect(_on_track_done.bind(0))
	_music[1].finished.connect(_on_track_done.bind(1))


# --- API ---------------------------------------------------------------------

func set_view(zoom_distance: float, near_town: Dictionary, season: String, night: bool, weather := "clear") -> void:
	_view = {"d": zoom_distance, "town": near_town, "season": season, "night": night, "weather": weather}


func set_interior(room: String) -> void:
	# The door, as he goes in or comes out: the one place the room changes.
	if room != _interior:
		var s: AudioStream = takes_of("sfx/door_open.wav|sfx/door_open_1.ogg" if room != "" else "sfx/door_close.wav|sfx/door_close_1.ogg|sfx/door_close_2.ogg|sfx/door_close_3.ogg")
		if s:
			_one_shot(s, "SFX", -8.0, Vector3.INF, _rng.randf_range(0.95, 1.05))
	_interior = room


## A scene the bridge staged (scenes.gd), heard where it happens: the kinds
## that have a sound of their own (a rider's gallop, a muster's march, a vigil's
## drum). War and the chronicle's news sound through event() as before.
const STAGED := ["vigil", "rider", "muster"]
func staged(kind: String, at := Vector3.INF) -> void:
	if kind in STAGED:
		event(kind, at)


func event(kind: String, at := Vector3.INF) -> void:
	kind = ALIASES.get(kind, kind)
	if kind == "battle_end":
		_lift_bed.erase("battle")
		if _lift_mood[0] == "battle":
			_lift_mood = ["", 0.0]
		return
	for s in STINGS.get(kind, []):
		_sting(s[0], s[1], s[2], at)
	if LIFT_BED.has(kind):
		_lift_bed[LIFT_BED[kind][0]] = LIFT_BED[kind][1]
	if LIFT_MOOD.has(kind):
		_lift_mood = [LIFT_MOOD[kind][0], LIFT_MOOD[kind][1]]


func mood(kind: String) -> void:
	if MUSIC.has(kind):
		_base_mood = kind


func ui(kind: String) -> void:
	if not UI_SOUNDS.has(kind):
		return
	var now := Time.get_ticks_msec()
	if now - int(_ui_last.get(kind, 0)) < 80:  # a double fire is one sound
		return
	_ui_last[kind] = now
	var s: AudioStream = takes_of(UI_SOUNDS[kind][0], 1.02)
	if s:
		_one_shot(s, "UI", UI_SOUNDS[kind][1], Vector3.INF, 1.0)


func footstep(surface: String, at: Vector3) -> void:
	var takes := PackedStringArray()
	for i in 5:
		takes.append("sfx/step_%s_%d.%s" % [surface, i, "ogg" if surface == "stone" else "wav"])
	var s: AudioStream = takes_of("|".join(takes), 1.08)
	if s:
		_one_shot(s, "SFX", -14.0, at, 1.0)


func voice_started() -> void:
	_speaking += 1
	_speak_time = 0.0


func voice_ended() -> void:
	_speaking = maxi(0, _speaking - 1)


func voice_bus() -> String:
	return "Voice"


func set_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(linear, 0.0001)))


func volume(bus: String) -> float:
	var i := AudioServer.get_bus_index(bus)
	return db_to_linear(AudioServer.get_bus_volume_db(i)) if i >= 0 else 0.0


# --- Every frame -------------------------------------------------------------

## Each frame, timed for the frame-cost probe (perf_tools.gd, GOC_PERF_PROBE=1; off in play).
func _process(delta: float) -> void:
	if not preload("res://scripts/perf_tools.gd").probing:
		_process_timed(delta)
		return
	var pt := Time.get_ticks_usec()
	_process_timed(delta)
	preload("res://scripts/perf_tools.gd").add("soundscape", Time.get_ticks_usec() - pt)


func _process_timed(delta: float) -> void:
	_tick_lifts(delta)
	_mix_beds(delta)
	_tick_bells(delta)
	_tick_music(delta)
	_tick_duck(delta)
	var pt := Time.get_ticks_usec()
	_tick_clips(delta)
	preload("res://scripts/perf_tools.gd").add("clip_sounds %d/%d" % [_near_clips.size(), _clips.size()], Time.get_ticks_usec() - pt)


func _tick_lifts(delta: float) -> void:
	for b in _lift_bed.keys():
		_lift_bed[b] -= delta
		if _lift_bed[b] <= 0.0:
			_lift_bed.erase(b)
	if _lift_mood[1] > 0.0:
		_lift_mood[1] -= delta
		if _lift_mood[1] <= 0.0:
			_lift_mood = ["", 0.0]


## What each bed should be at from the view: 0 silent .. 1 full.
func _targets() -> Dictionary:
	var d: float = _view["d"]
	var town: Dictionary = _view["town"]
	var season: String = _view["season"]
	var night: bool = _view["night"]
	var weather: String = _view["weather"]
	var day := 0.0 if night else 1.0
	var far := smoothstep(60.0, 200.0, d)  # the whole realm
	var near := 0.0 if town.is_empty() else 1.0 - smoothstep(14.0, 60.0, d)  # in a town
	var close := 0.0 if town.is_empty() else 1.0 - smoothstep(4.0, 22.0, d)  # in its streets
	var country := (1.0 - far) * (1.0 - near)  # between towns, low over the land
	var size := clampf(float(town.get("size", 3)) / 8.0, 0.25, 1.0)
	var green: float = {"spring": 1.0, "summer": 1.0, "autumn": 0.5, "winter": 0.0}.get(season, 1.0)
	var winter := 1.0 if season == "winter" else 0.0
	var wet := 1.0 if weather in ["rain", "storm"] else 0.0
	var snowing := 1.0 if weather == "snow" else 0.0
	var siege := 1.0 if town.get("siege", false) else 0.0
	var t := {}
	t["realm_wind"] = maxf(far * (1.0 - 0.6 * winter), 0.25 * country)
	t["realm_sea"] = far * 0.7 + near * (1.0 if town.get("coastal", false) else 0.0) * 0.6
	t["shore_gulls"] = near * day * (1.0 if town.get("coastal", false) else 0.0)
	t["town_day"] = near * day * (1.0 - 0.5 * winter) * (1.0 - siege)
	t["town_bustle"] = near * day * size * (1.0 - 0.6 * wet) * (1.0 - siege)
	t["market"] = close * day * (1.0 if town.get("market", int(town.get("size", 0)) >= 4) else 0.0) * (1.0 - 0.7 * wet) * (1.0 - siege)
	t["forge"] = close * day * (1.0 if town.get("forge", int(town.get("size", 0)) >= 3) else 0.0)
	t["tavern"] = close * (1.0 if town.get("tavern", int(town.get("size", 0)) >= 3) else 0.0) * (0.9 if night else 0.3)
	t["birds_day"] = (country + near * 0.4) * day * green * (1.0 - wet)
	t["forest"] = country * 0.6 * day * green
	t["night"] = (country + near) * (1.0 - far) * (1.0 - day) * green * (1.0 - wet)
	t["crows"] = (country + near * 0.5) * (1.0 - green) * day * 0.7 + siege * 0.5
	t["rain"] = wet * (1.0 - 0.5 * far)
	t["storm"] = (1.0 if weather == "storm" else 0.0) * (1.0 - 0.5 * far)
	t["snow_wind"] = maxf(winter * (0.35 + 0.65 * far), snowing)
	t["river"] = near * (1.0 if town.get("river", false) else 0.0) * 0.8
	t["dead_north"] = (1.0 if town.get("north", false) and _base_mood == "dead" else 0.0) * maxf(near, far)
	t["battle"] = 0.0
	t["battle_far"] = 0.0
	t["feast"] = 0.0
	t["drums"] = siege * near
	if _interior != "":
		# Indoors: the room's own bed, the weather heard through the roof, the town muffled.
		for k in t:
			t[k] *= 0.35
		t["rain_roof"] = wet
		t["campfire"] = 0.0 if _interior == "chapel" else 1.0
		t["tavern"] = 1.0 if _interior == "tavern" else t["tavern"]
	# Events lift their beds; a battle is louder close than seen from far off.
	for b in _lift_bed:
		var left: float = minf(1.0, _lift_bed[b] / 6.0)  # fades over its last six seconds
		if b == "battle":
			t["battle"] = maxf(t.get("battle", 0.0), left * (1.0 - smoothstep(10.0, 80.0, d)))
			t["battle_far"] = maxf(t.get("battle_far", 0.0), left * smoothstep(10.0, 80.0, d) * 0.8)
		else:
			t[b] = maxf(t.get(b, 0.0), left)
	return t


func _mix_beds(delta: float) -> void:
	var t := _targets()
	var k := 1.0 - pow(0.5, delta / FADE)
	_lowpass.cutoff_hz = lerpf(_lowpass.cutoff_hz, 1100.0 if _interior != "" else 20000.0, k)
	for name in BEDS:
		var want: float = clampf(t.get(name, 0.0), 0.0, 1.0)
		var bed: Dictionary = _beds.get(name, {})
		if bed.is_empty():
			if want < 0.01:
				continue
			var s: AudioStream = _load(BEDS[name][0], true)
			if s == null:
				continue
			var p := AudioStreamPlayer.new()
			p.bus = "Ambience"
			p.stream = s
			p.volume_db = -80.0
			add_child(p)
			# Start somewhere in the loop so two visits don't sound the same.
			p.play(_rng.randf() * maxf(0.0, s.get_length() - 1.0))
			bed = {"player": p, "level": 0.0}
			_beds[name] = bed
		bed["level"] = lerpf(bed["level"], want, k)
		var p: AudioStreamPlayer = bed["player"]
		if bed["level"] < 0.005 and want < 0.01:
			p.queue_free()
			_beds.erase(name)
			continue
		p.volume_db = BEDS[name][1] + linear_to_db(maxf(bed["level"], 0.0001))


## Church bells now and then over a town by day (and for crowns, deaths, weddings).
func _tick_bells(delta: float) -> void:
	_bells_in -= delta
	if _bells_in > 0.0:
		return
	_bells_in = _rng.randf_range(120.0, 300.0)
	var town: Dictionary = _view["town"]
	if town.is_empty() or _view["night"] or _interior != "" or not town.get("church", int(town.get("size", 0)) >= 4):
		return
	var near := 1.0 - smoothstep(10.0, 60.0, float(_view["d"]))
	if near > 0.1:
		_sting("ambience/church_bells.ogg", -10.0 + linear_to_db(near), 0.0, Vector3.INF)


# --- Moves, heard ----------------------------------------------------------------

## The sounds a move makes, at fractions of its cycle: a walk's two footfalls,
## a hammer's blow, an axe's bite. Keyed by the clip as it plays (people.gd's
## hook), never a timer of its own guessing; only for people near the camera.
const CLIP_SOUNDS := {
	"Walk": ["step", [0.0, 0.5]], "Walking": ["step", [0.0, 0.5]], "Carry_Walk": ["step", [0.0, 0.5]],
	"Injured_Walk": ["step", [0.0, 0.5]], "SS_Walk": ["step", [0.0, 0.5]], "GS_Walk": ["step", [0.0, 0.5]],
	"Axe_Walk": ["step", [0.0, 0.5]], "Running": ["step", [0.0, 0.5]], "Carrying": ["step", [0.0, 0.5]],
	"Hammer_Swing": ["sfx/hammer.wav|sfx/hammer_1.wav|sfx/hammer_2.wav|sfx/hammer_3.wav|sfx/hammer_4.wav", [0.45]],
	"Axe_Down": ["sfx/chop.wav|sfx/chop_1.ogg|sfx/chop_2.ogg|sfx/chop_3.ogg|sfx/chop_4.ogg|sfx/chop_5.ogg", [0.5]],
}
const HEARD_WITHIN := 14.0  # game units from the camera: further, a move makes no sound
var _clips := {}  # person -> [clip, period, start (s), looping, hits fired, cycle]
var _near_clips: Array = []  # the people with a sounding move near the camera, renewed twice a second
var _near_in := 0.0


func _on_clip(person: Node3D, clip: String, period: float, looping: bool) -> void:
	if CLIP_SOUNDS.has(clip) and period > 0.05:
		_clips[person] = [clip, period, Time.get_ticks_msec() / 1000.0, looping, 0, 0]
	else:
		_clips.erase(person)  # a new move ends the old one's sounds


## The moves' sounds, timed from when each move began: far people cost nothing
## per frame. Only those near the camera (renewed twice a second) are walked.
func _tick_clips(delta: float) -> void:
	if _clips.is_empty() or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_near_in -= delta
	if _near_in <= 0.0:
		_near_in = 0.5
		_near_clips.clear()
		for person in _clips.keys():
			if not is_instance_valid(person):
				_clips.erase(person)
			elif cam.global_position.distance_to((person as Node3D).global_position) <= HEARD_WITHIN:
				_near_clips.append(person)
	var now := Time.get_ticks_msec() / 1000.0
	for person in _near_clips:
		if not is_instance_valid(person) or not _clips.has(person):
			continue
		var c: Array = _clips[person]
		var sound: Array = CLIP_SOUNDS[c[0]]
		var t: float = now - float(c[2])
		var cycle := int(t / float(c[1]))
		if not c[3] and cycle > 0:
			_clips.erase(person)  # a move played once is over
			continue
		if cycle != int(c[5]):
			c[5] = cycle
			c[4] = 0
		var f: float = (t - cycle * float(c[1])) / float(c[1])
		var hits: Array = sound[1]
		while int(c[4]) < hits.size() and f >= float(hits[c[4]]):
			c[4] = int(c[4]) + 1
			var at: Vector3 = (person as Node3D).global_position
			if sound[0] == "step":
				footstep(("stone" if _interior in ["chapel", "great_hall"] else "wood") if _interior != "" else ("snow" if _view["season"] == "winter" else "grass"), at)
			else:
				var s: AudioStream = takes_of(sound[0], 1.08)
				if s:
					_one_shot(s, "SFX", -12.0, at, 1.0)


# --- Music -------------------------------------------------------------------

func _current_mood() -> String:
	return _lift_mood[0] if _lift_mood[0] != "" else _base_mood


func _tick_music(delta: float) -> void:
	var want := _current_mood()
	var cur := _music[_music_on]
	if want != _playing_mood:
		# A new mood cuts in now (a quick fade for battle, a slow one otherwise).
		_playing_mood = want
		_start_track(want, 2.0 if want == "battle" else 5.0)
		return
	if not cur.playing:
		_music_gap -= delta
		if _music_gap <= 0.0:
			_start_track(want, 3.0)
	# Calm music sits lower at night.
	if want == "calm" and cur.playing and not _fading:
		cur.volume_db = lerpf(cur.volume_db, MUSIC_DB["calm"] - (3.0 if _view["night"] else 0.0), 1.0 - pow(0.5, delta / 2.0))


var _fading := false


func _start_track(m: String, fade: float) -> void:
	var names: Array = MUSIC.get(m, [])
	var pool := names.filter(func(n): return n != _last_track and ResourceLoader.exists(ROOT + "music/%s.ogg" % n))
	if pool.is_empty():
		pool = names.filter(func(n): return ResourceLoader.exists(ROOT + "music/%s.ogg" % n))
	var old := _music[_music_on]
	if pool.is_empty():
		_fade_player(old, -80.0, fade, true)
		return
	var pick: String = pool[_rng.randi() % pool.size()]
	var s: AudioStream = _load("music/%s.ogg" % pick)
	if s == null:
		return
	_last_track = pick
	_music_on = 1 - _music_on
	var p := _music[_music_on]
	p.stream = s
	p.volume_db = -40.0
	p.play()
	_fade_player(p, MUSIC_DB.get(m, -4.0), fade, false)
	if old.playing:
		_fade_player(old, -80.0, fade, true)


func _fade_player(p: AudioStreamPlayer, to_db: float, secs: float, stop_after: bool) -> void:
	_fading = true
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, secs).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(func():
		_fading = false
		if stop_after:
			p.stop())


func _on_track_done(which: int) -> void:
	if which != _music_on:
		return
	var m := _current_mood()
	_music_gap = _rng.randf_range(CALM_GAP.x, CALM_GAP.y) if m in ["calm", "court"] else 1.5


# --- Ducking -----------------------------------------------------------------

func _tick_duck(delta: float) -> void:
	if _speaking > 0:
		_speak_time += delta
		if _speak_time > 45.0:  # a line that never said it ended
			_speaking = 0
	var want := 1.0 if _speaking > 0 else 0.0
	# Fast down (0.15 s), slow back up (0.9 s), so speech never fights the bed.
	_duck = lerpf(_duck, want, 1.0 - pow(0.5, delta / (0.15 if want > _duck else 0.9)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), BUSES["Music"] + DUCK_MUSIC_DB * _duck)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambience"), BUSES["Ambience"] + DUCK_AMB_DB * _duck)


# --- Helpers -----------------------------------------------------------------

func _bus(name: String, db: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		i = AudioServer.bus_count
		AudioServer.add_bus(i)
		AudioServer.set_bus_name(i, name)
		AudioServer.set_bus_send(i, "Master")
	AudioServer.set_bus_volume_db(i, db)


func _load(rel: String, loop := false) -> AudioStream:
	var key := rel + ("#loop" if loop else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	if ResourceLoader.exists(ROOT + rel):
		s = load(ROOT + rel)
		if s and loop:
			s = s.duplicate()  # the bed loops; the same file as a one-shot does not
			if s is AudioStreamOggVorbis:
				s.loop = true
			elif s is AudioStreamWAV:
				s.loop_mode = AudioStreamWAV.LOOP_FORWARD
				s.loop_end = int(s.get_length() * s.mix_rate)
	_cache[key] = s
	return s


## The takes of one sound ("a|b|c") as Godot's AudioStreamRandomizer: each
## play picks a take, never the one before, at a slightly different pitch.
## One randomizer per set, kept, so it remembers what it played last.
func takes_of(files: String, pitch := 1.03) -> AudioStream:
	var key := "takes:" + files
	if _cache.has(key):
		return _cache[key]
	var r := AudioStreamRandomizer.new()
	r.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	r.random_pitch = pitch
	for f in files.split("|"):
		var s: AudioStream = _load(f)
		if s:
			r.add_stream(-1, s)
	var out: AudioStream = r if r.streams_count > 1 else (r.get_stream(0) if r.streams_count == 1 else null)
	_cache[key] = out
	return out


## A stinger: `files` may hold takes split by "|" (see takes_of).
func _sting(files: String, db: float, delay: float, at: Vector3) -> void:
	var s: AudioStream = takes_of(files)
	if s == null:
		return
	var pitch := 1.0 if s is AudioStreamRandomizer else _rng.randf_range(0.97, 1.03)  # a single take still varies
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(_one_shot.bind(s, "SFX", db, at, pitch))
	else:
		_one_shot(s, "SFX", db, at, pitch)


func _one_shot(s: AudioStream, bus: String, db: float, at: Vector3, pitch: float) -> void:
	if _stingers >= MAX_STINGERS:
		return
	_stingers += 1
	var p: Node
	if at == Vector3.INF or not is_inside_tree() or get_viewport().get_camera_3d() == null:
		var flat := AudioStreamPlayer.new()
		flat.stream = s
		flat.bus = bus
		flat.volume_db = db
		flat.pitch_scale = pitch
		p = flat
		add_child(flat)
		flat.play()
		flat.finished.connect(_done.bind(flat))
	else:
		# Placed in the world, heard from the camera: scaled to the zoom, so a battle
		# seen from the whole realm is soft but still there.
		var pos := AudioStreamPlayer3D.new()
		pos.stream = s
		pos.bus = bus
		pos.volume_db = db
		pos.pitch_scale = pitch
		pos.unit_size = maxf(6.0, float(_view["d"]) * 0.8)
		pos.max_distance = maxf(60.0, float(_view["d"]) * 5.0)
		pos.attenuation_filter_cutoff_hz = 9000.0
		pos.top_level = true
		add_child(pos)
		pos.global_position = at
		pos.play()
		pos.finished.connect(_done.bind(pos))
		p = pos


func _done(p: Node) -> void:
	_stingers = maxi(0, _stingers - 1)
	p.queue_free()
