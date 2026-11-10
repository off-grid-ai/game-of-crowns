extends RefCounted
## A townsperson's mind on LimboAI behaviour trees (docs/review/npc-activities.md):
## a person does activities made of steps, as in RimWorld's jobs and The Sims'
## activities, never one move on a loop. Stock LimboAI 1.8.1 composites and
## decorators; the only glue is four small tasks below (a run of a working move,
## a breaker, one move once, a step about the post).
##
## Rules every tree keeps:
## - a working move plays only in runs of 3-5, and a breaker or a step follows;
## - the same clip, breaker or activity never twice running;
## - each person on their own clock (a random first wait), so no crowd moves as one.

const People := preload("res://scripts/people.gd")
const SceneKinds := preload("res://scripts/scene_kinds.gd")
const Motion := preload("res://scripts/motion.gd")

# Breakers between runs (section 2's shared pools).
const REST := ["Weight_Shift", "Breathing_Idle", "Bored", "Relieved_Sigh", "Looking_Around"]
const LOOK := ["Looking_Around", "Thinking", "Look_Away"]
const SWIG := ["Drinking"]


## Plays a working move from `pool` for a run of lo..hi times (never the clip
## played last), then succeeds.
class PlayRun extends BTAction:
	@export var pool: Array = []
	@export var lo := 3
	@export var hi := 5
	var _left := 0.0

	func _enter() -> void:
		var last: String = blackboard.get_var(&"last_clip", "", false)
		var choices := pool.filter(func(c): return c != last and _has(c))
		var again := choices.is_empty()  # the only move there is was just played: once more, briefly
		if again:
			choices = pool.filter(func(c): return _has(c))
		if choices.is_empty():
			_left = 0.0
			return
		var clip: String = choices[randi() % choices.size()]
		blackboard.set_var(&"last_clip", clip)
		var n := 1 if again else randi_range(lo, hi)
		if Motion.is_once(clip):
			People.repeat(agent, clip)
		else:
			People.play(agent, clip)
		# A run is a few goes of a short move, never one long loop held: capped at
		# about 8 s, so a long clip (a dance) plays once or twice, then something else.
		_left = minf(_length(clip) * n, maxf(_length(clip), 8.0) if _length(clip) <= 8.0 else 8.0)

	func _tick(delta: float) -> Status:
		_left -= delta
		return RUNNING if _left > 0.0 else SUCCESS

	func _has(clip: String) -> bool:
		var ap: AnimationPlayer = agent.get_node_or_null("Anim")
		return ap != null and ap.has_animation(clip)

	func _length(clip: String) -> float:
		var ap: AnimationPlayer = agent.get_node_or_null("Anim")
		return maxf(0.8, ap.get_animation(clip).length) if ap and ap.has_animation(clip) else 2.0


## A breaker: one move from `pool` (not the one used last time) for 2-5 s.
class Breaker extends BTAction:
	@export var pool: Array = []
	var _left := 0.0

	func _enter() -> void:
		var last: String = blackboard.get_var(&"last_breaker", "", false)
		var last_clip: String = blackboard.get_var(&"last_clip", "", false)  # never the move just played, either side
		var ap: AnimationPlayer = agent.get_node_or_null("Anim")
		var choices := pool.filter(func(c): return c != last and c != last_clip and ap != null and ap.has_animation(c))
		if choices.is_empty():
			choices = ["Idle"]
		var clip: String = choices[randi() % choices.size()]
		blackboard.set_var(&"last_breaker", clip)
		blackboard.set_var(&"last_clip", clip)
		People.play(agent, clip)
		_left = randf_range(2.0, 5.0)

	func _tick(delta: float) -> Status:
		_left -= delta
		return RUNNING if _left > 0.0 else SUCCESS


## A step about the post: walk to a spot within `reach` of it (or `back`
## paces straight back from the work), then succeed. Never off the post.
class Step extends BTAction:
	@export var reach := 0.25
	@export var back := 0.0
	var _to := Vector3.ZERO
	var _left := 0.0

	func _enter() -> void:
		var post: Vector3 = blackboard.get_var(&"post", agent.position, false)
		if back > 0.0:
			var fwd := Vector3(sin(agent.rotation.y), 0, cos(agent.rotation.y))
			_to = agent.position - fwd * back
		elif blackboard.get_var(&"at_post", true, false):
			_to = post + Vector3(randf_range(-reach, reach), 0.0, randf_range(-reach, reach))
		else:
			_to = post
		blackboard.set_var(&"at_post", _to.distance_to(post) < 0.05)
		var ground: Callable = blackboard.get_var(&"ground", Callable(), false)
		if ground.is_valid():
			_to.y = ground.call(_to)
		var flat := Vector2(_to.x - agent.position.x, _to.z - agent.position.z)
		if flat.length() > 0.01 and back <= 0.0:
			agent.rotation.y = atan2(flat.x, flat.y)
		People.play(agent, "Walk")
		_left = maxf(0.3, flat.length() / 0.17)
		agent.create_tween().tween_property(agent, "position", _to, _left)

	func _tick(delta: float) -> Status:
		_left -= delta
		if _left > 0.0:
			return RUNNING
		var face: float = blackboard.get_var(&"face", agent.rotation.y, false)
		agent.rotation.y = face  # back to facing the work
		return SUCCESS


## The activity's name goes on the blackboard; fails if it was the last one,
## so the selector tries another (never the same activity twice running).
class Begin extends BTAction:
	@export var name_ := ""

	func _tick(_delta: float) -> Status:
		if blackboard.get_var(&"last_activity", "", false) == name_ and blackboard.get_var(&"choices", 2, false) > 1:
			return FAILURE
		blackboard.set_var(&"last_activity", name_)
		return SUCCESS


static func run(pool: Array, lo := 3, hi := 5) -> BTTask:
	var t := PlayRun.new()
	t.pool = pool
	t.lo = lo
	t.hi = hi
	return t


static func once(clip: String) -> BTTask:
	return run([clip], 1, 1)


static func brk(pool: Array) -> BTTask:
	var t := Breaker.new()
	t.pool = pool
	return t


static func step(reach := 0.25, back := 0.0) -> BTTask:
	var t := Step.new()
	t.reach = reach
	t.back = back
	return t


static func seq(name: String, steps: Array) -> BTTask:
	var s := BTSequence.new()
	var b := Begin.new()
	b.name_ = name
	s.add_child(b)
	for t in steps:
		s.add_child(t)
	return s


## The activities of a scene post (section 2), each a sequence of steps.
static func post_activities(post: String) -> Array:
	match post:
		"build":
			return [
				seq("frame", [run(["Fixing_Kneeling"]), once("Getting_Up"), step(0.0, 0.15), brk(LOOK), step(0.0), run(["Interact"]), brk(REST + SWIG)]),
				seq("timber", [step(0.3), once("PickUp_Table"), step(0.0), once("PickUp_Table"), run(["Pushing"], 2, 3), brk(REST)]),
				seq("rubble", [once("PickUp_Table"), step(0.3), once("PickUp_Table"), brk(REST + SWIG)]),
			]
		"trade":
			return [
				seq("mind", [run(["Interact"]), once("Looking_Around"), once("PickUp_Table"), run(["Interact"]), brk(["Bored", "Weight_Shift", "Drinking", "Whispering"])]),
				seq("cry", [run(["Yelling"], 1, 2), once("Talking_Hands"), once("Waving"), brk(REST)]),
			]
		"buy":
			return [
				seq("browse", [once("Looking_Around"), once("PickUp_Table"), run(["Thinking", "Doubtful"], 1, 1), step(0.25), brk(LOOK)]),
				seq("haggle", [run(["Idle_Talking", "Arguing"], 2, 4), run(["Nod_Yes", "Shake_No"], 1, 1), once("PickUp_Table"), brk(["Pleased", "Looking_Around"])]),
			]
		"drill":
			return [
				seq("cuts", [run(["SS_Slash_1", "SS_Slash_2", "SS_Slash_3", "SS_Slash_4", "SS_Slash_5", "SS_Attack_3", "SS_Attack_4", "Sword_Attack"], 3, 4), brk(["Weight_Shift", "Breathing_Idle"])]),
				seq("thrusts", [run(["Spear_Thrust"], 3, 4), brk(["Weight_Shift", "Breathing_Idle"])]),
			]
		"bows":
			return [
				seq("loose", [once("Bow_Draw"), once("Bow_Aim"), once("Bow_Shoot"), once("Bow_Draw"), once("Bow_Aim"), once("Bow_Shoot"), brk(["Bow_Idle", "Weight_Shift"])]),
				seq("fetch", [step(0.5), once("PickUp_Table"), step(0.0), brk(["Bow_Idle", "Looking_Around"])]),  # out to the butts for the arrows, and back
			]
		"guard":  # the watch at a door the crowd presses on
			return [
				seq("hold", [run(["Sword_Idle", "SS_Idle_2", "SS_Block_Idle"], 2, 3), brk(["Weight_Shift", "Looking_Around"])]),
				seq("warn", [once("Spear_Thrust"), run(["Yelling"], 1, 2), once("Pointing_Forward"), brk(["Sword_Idle"])]),
				seq("watch", [once("Looking_Around"), step(0.12), run(["Sword_Idle"], 1, 2), brk(["Bored", "Weight_Shift"])]),
			]
		"riot":  # a rioter at the door
			return [
				seq("shout", [run(["Yelling", "Arguing"], 2, 4), once("Pointing_Forward"), brk(["Looking_Around", "Weight_Shift"])]),
				seq("press", [step(0.15), run(["Pushing"], 1, 2), once("Shove_Reaction"), step(0.0, 0.15), brk(["Arguing"])]),
				seq("throw", [once("Throw_Object"), run(["Yelling"], 1, 2), brk(["Looking_Around"])]),
			]
		"beg":  # the hungry at the town's edge
			return [
				seq("plead", [run(["Kneeling", "Praying"], 2, 3), brk(["Defeated", "Looking_Around"])]),
				seq("slump", [run(["Sitting_Ground", "Defeated"], 1, 2), brk(["Looking_Around"]), step(0.12)]),
				seq("ask", [step(0.15), once("Pointing_Arm_Bent"), run(["Defeated"], 1, 1), step(0.0)]),
			]
		"mourn":
			return [
				seq("weep", [run(["Crying"], 2, 3), brk(["Defeated"])]),
				seq("vigil", [run(["Kneeling", "Praying"], 2, 3), brk(["Crying", "Looking_Around"])]),
				seq("sit", [run(["Sitting_Ground"], 1, 2), brk(["Defeated"])]),
			]
		"refugee":
			return [
				seq("huddle", [run(["Sitting_Cross_Legged", "Sitting_Ground"], 1, 2), brk(["Looking_Around"])]),
				seq("rest", [run(["Sleeping_Idle"], 1, 1), once("Getting_Up"), brk(["Arm_Stretching", "Weight_Shift"])]),
				seq("wait", [run(["Defeated", "Looking_Around", "Thinking"], 1, 2), step(0.15), brk(["Crying", "Bored"])]),
			]
		"revel":  # round the feast's bonfire
			return [
				seq("dance", [run(["Dance"], 2, 4), brk(["Laughing", "Cheering"])]),
				seq("toast", [run(["Drinking"], 2, 3), run(["Cheering", "Laughing"], 1, 2), brk(["Weight_Shift"])]),
				seq("clap", [run(["Clapping", "Cheering"], 2, 3), step(0.15), brk(["Laughing"])]),
				seq("song", [run(["Lute_Playing"], 2, 3), brk(["Laughing"])]),
			]
	return []


## Gives a person posted at a scene their mind: a BTPlayer whose tree picks among
## the post's activities at random (never the same twice running), with Danger
## first: struck or threatened, they react and get clear, then go back to work.
## `ground(p)` gives the ground height at a point. Returns false for an unknown post.
static func give(person: Node3D, post: String, ground: Callable, seed: int, opening: Array = [], town := -1) -> bool:
	var acts := post_activities(post)
	if acts.is_empty():
		return false
	var life := BTDynamicSelector.new()
	# Danger: someone set danger on them (a riot turning, a raid): react, get clear, then calm.
	var danger := BTSequence.new()
	var check := BTCheckVar.new()
	check.variable = &"danger"
	check.check_type = LimboUtility.CHECK_EQUAL
	var yes := BBVariant.new()
	yes.saved_value = true
	check.value = yes
	danger.add_child(check)
	danger.add_child(once("React_Front"))
	danger.add_child(step(0.6))
	danger.add_child(run(["Terrified", "Looking_Around"], 1, 1))
	var calm := BTSetVar.new()
	calm.variable = &"danger"
	var no := BBVariant.new()
	no.saved_value = false
	calm.value = no
	danger.add_child(calm)
	life.add_child(danger)
	life.add_child(react())
	# Posted: the post's activities, one at a time, weighed by the town's state.
	life.add_child(weighed(acts))
	var root := BTSequence.new()
	for t in opening:  # once, at once, before the post's own life (a riot pair's scuffle, in step)
		root.add_child(t)
	var first := BTRandomWait.new()  # then each on their own clock
	first.min_duration = 0.5
	first.max_duration = 6.0
	root.add_child(first)
	var forever := BTRepeat.new()
	forever.forever = true
	forever.add_child(life)
	root.add_child(forever)
	var bt := BehaviorTree.new()
	bt.root_task = root
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(person)  # made at runtime, with no owner: LimboAI needs to be told its scene
	player.behavior_tree = bt
	player.blackboard.set_var(&"post", person.position)
	player.blackboard.set_var(&"face", person.rotation.y)
	player.blackboard.set_var(&"ground", ground)
	player.blackboard.set_var(&"danger", false)
	for v in [&"last_activity", &"last_clip", &"last_breaker"]:
		player.blackboard.set_var(v, "")
	player.blackboard.set_var(&"alert", false)
	player.blackboard.set_var(&"at_post", true)
	player.blackboard.set_var(&"choices", acts.size())
	person.add_child(player)
	_attach(player, town)
	return true


## Joins the town's scope (awareness.gd), when the realm has one.
static func _attach(player: BTPlayer, town: int) -> void:
	if town >= 0 and Engine.has_meta("awareness"):
		Engine.get_meta("awareness").attach(player, town)


# --- awareness: news, and the town's state (awareness.gd) ---------------------

## News just seen (awareness.perceive set `seen` and `alert`): turn to it, then
## react as the news is to them. Steel close by → Danger takes over (they run);
## further off they watch, point and keep clear. A feast draws cheers, grief
## tears, the King's banner what his name has earned. Then alert is cleared.
class React extends BTAction:
	var _left := 0.0

	func _enter() -> void:
		_left = 0.0
		var seen: Dictionary = blackboard.get_var(&"seen", {}, false)
		var kind := String(seen.get("kind", ""))
		var at: Vector3 = seen.get("at", agent.position)
		var flat := Vector2(at.x - agent.position.x, at.z - agent.position.z)
		if flat.length() > 0.01:
			agent.rotation.y = atan2(flat.x, flat.y)
		if blackboard.has_var(&"va"):
			var a: Dictionary = blackboard.get_var(&"va")
			a["route"] = PackedVector2Array()  # they stop where they are
		if SceneKinds.tone(kind) == SceneKinds.HOSTILE and float(seen.get("near", 1.0)) < 0.5:
			blackboard.set_var(&"danger", true)
			return
		var pool := reaction(kind, String(blackboard.get_var(&"king_name", "", false)))
		var ap: AnimationPlayer = agent.get_node_or_null("Anim")
		pool = pool.filter(func(c): return ap != null and ap.has_animation(c))
		if pool.is_empty():
			return
		var clip: String = pool[randi() % pool.size()]
		var Mo := preload("res://scripts/motion.gd")
		if Mo.is_once(clip):
			People.repeat(agent, clip)
		else:
			People.play(agent, clip)
		_left = clampf(ap.get_animation(clip).length * randi_range(2, 3), 2.0, 7.0)

	func _tick(delta: float) -> Status:
		_left -= delta
		if _left > 0.0:
			return RUNNING
		blackboard.set_var(&"alert", false)
		return SUCCESS

	## The moves a piece of news calls for. The King's name decides how his
	## banner is met: cheered, bowed to in fear, or barely looked at.
	static func reaction(kind: String, king: String) -> Array:
		var tone := SceneKinds.tone(kind)
		if tone == SceneKinds.HOSTILE:
			return ["Terrified", "Looking_Around", "Pointing_Forward"]
		if tone in [SceneKinds.GRIEF, SceneKinds.TROUBLE]:
			return ["Crying", "Kneeling", "Praying", "Defeated"]
		if tone == SceneKinds.JOY:
			return ["Cheering", "Clapping", "Laughing"]
		if kind == "king":
			var k := king.to_lower()
			if k.contains("good") or k.contains("merciful") or k.contains("just") or k.contains("generous") or k.contains("golden"):
				return ["Cheering", "Waving", "Clapping"]
			if k.contains("cruel") or k.contains("conqueror") or k.contains("tyrant") or k.contains("terrible") or k.contains("bloody"):
				return ["Bow", "Terrified", "Defeated"]
			if k.contains("idle") or k.contains("absent") or k.contains("weak"):
				return ["Looking_Around", "Bored"]
			return ["Waving", "Bow", "Looking_Around"]
		return ["Looking_Around", "Pointing_Forward", "Nodding"]


static func react() -> BTTask:
	return plain([flag(&"alert"), React.new()])


## Sets the next activity's odds from the town's state, read up the scopes
## (awareness.gd): the selector after it picks by these weights. The state
## shifts what people already do; it never adds a second system.
class Weigh extends BTAction:
	func _tick(_delta: float) -> Status:
		var sel := get_parent().get_child(get_index() + 1) as BTProbabilitySelector
		if sel == null:
			return SUCCESS
		for i in sel.get_child_count():
			var act := sel.get_child(i)
			var begin = act.get_child(0) if act.get_child_count() > 0 else null
			var name_: String = begin.name_ if begin != null and "name_" in begin else ""
			sel.set_weight(i, weight(name_, blackboard))
		return SUCCESS

	## How likely an activity is now, from the town's and the realm's state.
	static func weight(act: String, bb: Blackboard) -> float:
		var w := 1.0
		var war: bool = bb.get_var(&"at_war", false, false)
		var mood := String(bb.get_var(&"mood", "", false))
		var grief: bool = bb.get_var(&"grief", false, false)
		var rich: bool = bb.get_var(&"prosperity", false, false)
		var sour: bool = bb.get_var(&"grasping", false, false) or float(bb.get_var(&"favour", 100.0, false)) < 35.0
		var winter := String(bb.get_var(&"season", "", false)) == "winter"
		var merry := act in ["dance", "song", "toast", "clap", "lute"]
		var play := act in ["play", "tag", "hide", "sit"]
		# States that have activities of their own, unlikely otherwise.
		if act == "road":
			return 4.0 if war else 0.0
		if act == "mutter":
			return 3.0 if sour else 0.0
		if war:
			w *= {"hold": 3.0, "watch": 3.0, "warn": 2.0, "browse": 0.5, "haggle": 0.5, "gossip": 1.5, "chat": 1.5}.get(act, 1.0)
			if play:
				w *= 0.2
		if mood == "hunger" and merry:
			w *= 0.1
		if grief:
			w *= 0.05 if merry or play else ({"pray": 3.0, "vigil": 3.0, "weep": 3.0, "prayers": 3.0}.get(act, 1.0))
		if rich:
			w *= {"browse": 2.0, "haggle": 2.0, "carry": 2.0, "lute": 3.0, "song": 2.0, "promenade": 2.0, "sell": 2.0}.get(act, 1.0)
		if sour and act in ["greet", "preach", "song"]:
			w *= 0.3  # a cold shoulder for the crown's own
		if winter and act in ["lounge", "nap", "sit", "tag", "hide", "dig", "weed", "tend"]:
			w *= 0.3
		return w


## Activities a state brings out, offered to every calling (weight 0 unless
## the state holds): watching the road in wartime, muttering knots when the
## crown grasps or is hated.
static func state_activities() -> Array:
	return [
		seq("road", [go("home"), once("Looking_Around"), run(["Pointing_Forward", "Looking_Around", "Thinking"], 1, 2), brk(["Weight_Shift"])]),
		seq("mutter", [go("well"), run(["Whispering", "Arguing", "Telling_Secret"], 2, 3), once("Shove_Reaction"), brk(LOOK)]),
	]


## The pick among a list of activities: Weigh, then a weighted pick.
static func weighed(acts: Array) -> BTTask:
	var sel := BTProbabilitySelector.new()
	for a in acts:
		sel.add_child(a)
	return plain([Weigh.new(), sel])


# --- villagers: farmers and market folk (slice 1) ------------------------------

## Walk to a place of the villager's day through villagers.gd's own routing
## (nav map, crowd avoidance, room in the square), with `gait` (Walk, or
## Carrying for a load: the carry blend), and succeed on arrival.
class GoTo extends BTAction:
	@export var where := "market"
	@export var gait := "Walk"
	var _started := false

	func _enter() -> void:
		var a: Dictionary = blackboard.get_var(&"va")
		var v: Node = blackboard.get_var(&"vill")
		var rng: RandomNumberGenerator = a["rng"]
		var to: Vector3 = a["home"]
		match where:
			"field": to = v._near(a["field"], rng, 0.25)
			"bench": to = a["bench"]
			"home": to = a["home"]
			_: to = v._at(a, where)
		a["gait"] = gait
		v._route_to(a, to)
		_started = true

	func _tick(_delta: float) -> Status:
		var a: Dictionary = blackboard.get_var(&"va")
		if not (a["route"] as PackedVector2Array).is_empty():
			return RUNNING
		# Arrived: this is now their post, and they face the way they came in.
		blackboard.set_var(&"post", agent.position)
		blackboard.set_var(&"face", agent.rotation.y)
		blackboard.set_var(&"at_post", true)
		a["gait"] = "Walk"
		return SUCCESS


## Succeeds while the villager's part of the day is one of `blocks`.
class BlockIs extends BTCondition:
	@export var blocks: Array = []

	func _tick(_delta: float) -> Status:
		var a: Dictionary = blackboard.get_var(&"va")
		return SUCCESS if String(a.get("block", "")) in blocks else FAILURE


## A field task for the season (villagers._field_work): planting, watering,
## picking; nothing to do in winter (fails, so another activity is picked).
class FieldRun extends PlayRun:
	func _enter() -> void:
		var a: Dictionary = blackboard.get_var(&"va")
		var v: Node = blackboard.get_var(&"vill")
		var tend: String = v._field_work(a["rng"])
		pool = [tend] if tend != "" else []
		super._enter()

	func _tick(delta: float) -> Status:
		return FAILURE if pool.is_empty() else super._tick(delta)


static func go(where: String, gait := "Walk") -> BTTask:
	var t := GoTo.new()
	t.where = where
	t.gait = gait
	return t


static func block_is(blocks: Array) -> BTTask:
	var t := BlockIs.new()
	t.blocks = blocks
	return t


## Danger first: struck, or someone struck beside them. A flinch, a run for
## home, a look round, then calm and back to the day.
static func villager_danger() -> BTTask:
	var danger := BTSequence.new()
	var check := BTCheckVar.new()
	check.variable = &"danger"
	check.check_type = LimboUtility.CHECK_EQUAL
	var yes := BBVariant.new()
	yes.saved_value = true
	check.value = yes
	danger.add_child(check)
	danger.add_child(once("React_Front"))
	danger.add_child(go("home", "Running"))
	danger.add_child(run(["Terrified", "Looking_Around"], 1, 1))
	var calm := BTSetVar.new()
	calm.variable = &"danger"
	var no := BBVariant.new()
	no.saved_value = false
	calm.value = no
	danger.add_child(calm)
	return danger


static func villager_activities(role: String) -> Array:
	match role:
		"farmer":
			var tend := FieldRun.new()
			tend.lo = 3
			tend.hi = 5
			return [
				seq("tend", [go("field"), tend, brk(REST + SWIG), step(0.2), run(["Pick_Fruit", "Planting", "Watering"], 3, 5), brk(LOOK)]),
				seq("dig", [go("field"), run(["Digging", "Dig_And_Plant"]), once("Wiping_Sweat"), brk(REST)]),
				seq("weed", [go("field"), run(["Fixing_Kneeling"]), brk(["Relieved_Sigh", "Arm_Stretching", "Weight_Shift"]), step(0.2), run(["Fixing_Kneeling"])]),
				seq("chores", [go("bench"), once("PickUp_Table"), run(["Fixing_Kneeling", "Interact"]), run(["Push_Heavy"], 1, 2), brk(REST)]),
			]
		"market":
			return [
				seq("browse", [go("market"), once("Looking_Around"), once("PickUp_Table"), run(["Thinking", "Doubtful"], 1, 1), brk(LOOK)]),
				seq("haggle", [go("market"), run(["Idle_Talking", "Arguing"], 2, 4), run(["Nod_Yes", "Shake_No"], 1, 1), brk(["Pleased", "Looking_Around"])]),
				seq("carry", [go("market"), once("PickUp_Table"), go("home", "Carrying"), once("PickUp_Table"), brk(REST)]),
				seq("gossip", [go("well"), run(["Whispering", "Telling_Secret", "Laughing"], 2, 4), brk(LOOK)]),
			]
		"pious":  # the priest and the devout
			return [
				seq("pray", [go("sept"), run(["Praying", "Kneeling"], 2, 3), brk(LOOK)]),
				seq("preach", [go("well"), run(["Talking", "Idle_Talking"], 2, 3), once("Bow"), brk(["Weight_Shift"])]),
				seq("alms", [go("bench"), once("PickUp_Table"), go("sept", "Carrying"), once("PickUp_Table"), brk(REST)]),
				seq("tend", [go("sept"), run(["Interact", "Fixing_Kneeling"]), brk(REST)]),
			]
		"tavern":  # a drinker
			return [
				seq("drink", [go("tavern"), run(["Drinking"], 2, 3), run(["Laughing", "Telling_Secret", "Idle_Talking"], 2, 3), brk(["Drunk_Idle", "Weight_Shift"])]),
				seq("sit", [go("tavern"), step(0.3), run(["Sitting_Drinking"], 2, 3), brk(["Laughing"])]),
				seq("song", [go("tavern"), run(["Clapping", "Cheering"], 2, 3), run(["Dance"], 1, 2), brk(["Laughing"])]),
				seq("home", [go("tavern"), run(["Drinking"], 1, 2), go("home", "Injured_Walk"), brk(["Drunk_Idle", "Weight_Shift"])]),
			]
		"keeper":  # the tavern keeper
			return [
				seq("serve", [go("tavern"), once("PickUp_Table"), step(0.3), once("PickUp_Table"), run(["Idle_Talking", "Nodding"], 1, 2), brk(REST)]),
				seq("counter", [go("tavern"), run(["Interact"]), brk(["Wiping_Sweat", "Weight_Shift"])]),
				seq("barrels", [go("bench"), once("PickUp_Table"), go("tavern", "Carrying"), once("PickUp_Table"), brk(REST)]),
				seq("lute", [go("tavern"), run(["Lute_Playing"], 2, 3), brk(["Bored"])]),
			]
		"gentry":
			return [
				seq("promenade", [go("market"), once("Looking_Around"), run(["Nodding", "Idle_Talking", "Whispering"], 1, 2), brk(["Weight_Shift"])]),
				seq("prayers", [go("sept"), run(["Praying"], 2, 3), brk(LOOK)]),
				seq("greet", [go("well"), once("Bow"), run(["Talking", "Telling_Secret", "Laughing"], 2, 3), once("Waving")]),
			]
		"child":
			return [
				seq("play", [go("home"), run(["Dance", "Waving", "Laughing"], 2, 3), brk(["Looking_Around"])]),
				seq("tag", [go("well", "Running"), run(["Dodge_Left", "Dodge_Right"], 2, 3), go("home", "Running"), brk(["Laughing"])]),
				seq("hide", [go("bench", "Sneak"), run(["Looking_Around"], 1, 1), go("well", "Running"), brk(["Laughing"])]),
				seq("sit", [go("well"), run(["Sitting_Cross_Legged", "Sitting_Ground"], 1, 2), brk(["Waving"])]),
				seq("errand", [go("market"), once("PickUp_Table"), go("home", "Carrying"), once("PickUp_Table")]),
			]
		"crafter":
			return [
				seq("craft", [go("bench"), run(["Hammer_Swing", "Interact", "Fixing_Kneeling"]), once("Wiping_Sweat"), brk(REST)]),
				seq("fetch", [go("well"), once("PickUp_Table"), go("bench", "Carrying"), once("PickUp_Table"), brk(REST)]),
				seq("sell", [go("market"), run(["Idle_Talking", "Arguing"], 2, 3), run(["Nodding"], 1, 1), brk(LOOK)]),
			]
		"idler":
			return [
				seq("chat", [go("well"), run(["Idle_Talking", "Talking", "Laughing", "Whispering"], 2, 4), brk(LOOK)]),
				seq("lounge", [go("bench"), run(["Sitting_Ground", "Sitting_Idle", "Sitting_Cross_Legged"], 1, 2), brk(["Arm_Stretching", "Bored"])]),
				seq("watch", [go("market"), run(["Looking_Around", "Bored", "Thinking"], 1, 2), brk(REST)]),
				seq("nap", [go("home"), run(["Sleeping_Idle"], 1, 1), brk(["Arm_Stretching"])]),
			]
	return []


## Succeeds while the villager's town is in `mood` (villagers._town_mood:
## feast, riot, hunger).
class MoodIs extends BTCondition:
	@export var mood := ""

	func _tick(_delta: float) -> Status:
		if blackboard.get_parent() != null:  # the town's scope (awareness.gd): the one mirror
			return SUCCESS if String(blackboard.get_var(&"mood", "", false)) == mood else FAILURE
		var a: Dictionary = blackboard.get_var(&"va")
		var v: Node = blackboard.get_var(&"vill")
		return SUCCESS if v._town_mood(a) == mood else FAILURE


static func plain(steps: Array) -> BTTask:
	var s := BTSequence.new()
	for t in steps:
		s.add_child(t)
	return s


## Succeeds in `season` (the realm scope's season).
class SeasonIs extends BTCondition:
	@export var season := ""

	func _tick(_delta: float) -> Status:
		return SUCCESS if String(blackboard.get_var(&"season", "", false)) == season else FAILURE


static func season_is(season: String) -> BTTask:
	var t := SeasonIs.new()
	t.season = season
	return t


static func mood_is(mood: String) -> BTTask:
	var t := MoodIs.new()
	t.mood = mood
	return t


static func flag(name: StringName) -> BTTask:
	var check := BTCheckVar.new()
	check.variable = name
	check.check_type = LimboUtility.CHECK_EQUAL
	var yes := BBVariant.new()
	yes.saved_value = true
	check.value = yes
	return check


const DAY := ["work", "work2", "meal", "evening"]


## What the town's mood does to a villager's day, ahead of their calling: a
## feast pulls everyone to the bonfire; in a riot the angry ones shout in the
## square and the rest bar their doors and watch; hunger slumps the frail at
## their doors and the empty stalls.
static func villager_moods() -> Array:
	var feast := plain([mood_is("feast"), block_is(DAY), go("well"), run(["Dance", "Cheering", "Clapping", "Drinking"], 2, 3), brk(["Laughing"])])
	var angry := BTSelector.new()
	angry.add_child(plain([flag(&"moody"), go("well"), run(["Yelling", "Arguing"], 2, 4), once("Pointing_Forward"), brk(LOOK)]))
	angry.add_child(plain([go("home"), run(["Looking_Around", "Terrified"], 1, 2)]))
	var riot := plain([mood_is("riot"), block_is(DAY), angry])
	var hunger := plain([mood_is("hunger"), block_is(DAY), flag(&"moody"), go("home"), run(["Defeated", "Praying", "Looking_Around"], 1, 2), brk(["Crying", "Defeated"])])
	return [feast, riot, hunger]


## A villager's mind: at night and dawn they go home and rest; through the day
## their role's activities, one at a time and never the same twice running.
static func give_villager(person: Node3D, a: Dictionary, vill: Node) -> bool:
	var role := String(a.get("role", ""))
	var rng: RandomNumberGenerator = a["rng"]
	if role == "tavern" and int(a["i"]) % 4 == 0:
		role = "keeper"  # one in four of the tavern's folk keeps it
	var acts := villager_activities(role)
	if acts.is_empty():
		return false
	var life := BTDynamicSelector.new()
	life.add_child(villager_danger())
	life.add_child(react())
	for m in villager_moods():
		life.add_child(m)
	var night := BTSequence.new()
	if role in ["tavern", "keeper"]:
		# The tavern keeps late: its folk are there till the night's end, home at dawn.
		night.add_child(block_is(["night"]))
		night.add_child(go("tavern"))
		night.add_child(run(["Drinking", "Idle_Talking", "Laughing"] if role == "tavern" else ["Interact", "Idle_Talking"], 1, 2))
		night.add_child(brk(["Drunk_Idle", "Weight_Shift"] if role == "tavern" else REST))
		life.add_child(night)
		night = BTSequence.new()
		night.add_child(block_is(["dawn"]))
	else:
		night.add_child(block_is(["night", "dawn"]))
	night.add_child(go("home"))
	night.add_child(brk(["Idle", "Breathing_Idle"]))
	life.add_child(night)
	if not role in ["tavern", "keeper"]:
		# Winter evenings are spent indoors: home early, the square left to the few.
		life.add_child(plain([season_is("winter"), block_is(["evening"]), go("home"), brk(["Idle", "Breathing_Idle"])]))
	life.add_child(weighed(acts + state_activities()))
	var root := BTSequence.new()
	var first := BTRandomWait.new()
	first.min_duration = 0.5
	first.max_duration = 6.0
	root.add_child(first)
	var forever := BTRepeat.new()
	forever.forever = true
	forever.add_child(life)
	root.add_child(forever)
	var bt := BehaviorTree.new()
	bt.root_task = root
	var player := BTPlayer.new()
	player.name = "Mind"
	player.set_scene_root_hint(person)  # made at runtime, with no owner: LimboAI needs to be told its scene
	player.behavior_tree = bt
	# One in three is quick to anger or slow to cope: they shout in a riot and slump in a famine.
	player.blackboard.set_var(&"moody", role != "child" and rng.randf() < 0.35)
	player.blackboard.set_var(&"va", a)
	player.blackboard.set_var(&"ground", func(q: Vector3) -> float: return vill.terrain.height_at(q.x, q.z))
	player.blackboard.set_var(&"vill", vill)
	player.blackboard.set_var(&"post", person.position)
	player.blackboard.set_var(&"face", person.rotation.y)
	for v in [&"last_activity", &"last_clip", &"last_breaker"]:
		player.blackboard.set_var(v, "")
	player.blackboard.set_var(&"alert", false)
	player.blackboard.set_var(&"at_post", true)
	player.blackboard.set_var(&"choices", acts.size())
	player.blackboard.set_var(&"danger", false)
	person.add_child(player)
	a["mind"] = player
	_attach(player, int(a.get("town", -1)))
	return true
