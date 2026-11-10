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
const Motion := preload("res://scripts/motion.gd")

# Breakers between runs (section 2's shared pools).
const REST := ["Weight_Shift", "Breathing_Idle", "Bored", "Relieved_Sigh", "Looking_Around"]
const LOOK := ["Looking_Around", "Thinking", "Look_Away"]
const SWIG := ["Drinking"]


## Plays a working move from `pool` for a run of lo..hi times (never the clip
## played last), then succeeds.
class PlayRun extends BTAction:
	var pool: Array = []
	var lo := 3
	var hi := 5
	var _left := 0.0

	func _enter() -> void:
		var last: String = blackboard.get_var(&"last_clip", "")
		var choices := pool.filter(func(c): return c != last and _has(c))
		if choices.is_empty():
			choices = pool.filter(func(c): return _has(c))
		if choices.is_empty():
			_left = 0.0
			return
		var clip: String = choices[randi() % choices.size()]
		blackboard.set_var(&"last_clip", clip)
		var n := randi_range(lo, hi)
		if Motion.is_once(clip):
			People.repeat(agent, clip)
		else:
			People.play(agent, clip)
		_left = _length(clip) * n

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
	var pool: Array = []
	var _left := 0.0

	func _enter() -> void:
		var last: String = blackboard.get_var(&"last_breaker", "")
		var ap: AnimationPlayer = agent.get_node_or_null("Anim")
		var choices := pool.filter(func(c): return c != last and ap != null and ap.has_animation(c))
		if choices.is_empty():
			choices = ["Idle"]
		var clip: String = choices[randi() % choices.size()]
		blackboard.set_var(&"last_breaker", clip)
		People.play(agent, clip)
		_left = randf_range(2.0, 5.0)

	func _tick(delta: float) -> Status:
		_left -= delta
		return RUNNING if _left > 0.0 else SUCCESS


## A step about the post: walk to a spot within `reach` of it (or `back`
## paces straight back from the work), then succeed. Never off the post.
class Step extends BTAction:
	var reach := 0.25
	var back := 0.0
	var _to := Vector3.ZERO
	var _left := 0.0

	func _enter() -> void:
		var post: Vector3 = blackboard.get_var(&"post", agent.position)
		if back > 0.0:
			var fwd := Vector3(sin(agent.rotation.y), 0, cos(agent.rotation.y))
			_to = agent.position - fwd * back
		elif blackboard.get_var(&"at_post", true):
			_to = post + Vector3(randf_range(-reach, reach), 0.0, randf_range(-reach, reach))
		else:
			_to = post
		blackboard.set_var(&"at_post", _to.distance_to(post) < 0.05)
		var ground: Callable = blackboard.get_var(&"ground", Callable())
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
		var face: float = blackboard.get_var(&"face", agent.rotation.y)
		agent.rotation.y = face  # back to facing the work
		return SUCCESS


## The activity's name goes on the blackboard; fails if it was the last one,
## so the selector tries another (never the same activity twice running).
class Begin extends BTAction:
	var name_ := ""

	func _tick(_delta: float) -> Status:
		if blackboard.get_var(&"last_activity", "") == name_ and blackboard.get_var(&"choices", 2) > 1:
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
static func give(person: Node3D, post: String, ground: Callable, seed: int, opening: Array = []) -> bool:
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
	# Posted: the post's activities, one at a time, at random.
	var work := BTRandomSelector.new()
	for a in acts:
		work.add_child(a)
	life.add_child(work)
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
	player.behavior_tree = bt
	player.blackboard.set_var(&"post", person.position)
	player.blackboard.set_var(&"face", person.rotation.y)
	player.blackboard.set_var(&"ground", ground)
	player.blackboard.set_var(&"danger", false)
	player.blackboard.set_var(&"choices", acts.size())
	person.add_child(player)
	return true


# --- villagers: farmers and market folk (slice 1) ------------------------------

## Walk to a place of the villager's day through villagers.gd's own routing
## (nav map, crowd avoidance, room in the square), with `gait` (Walk, or
## Carrying for a load: the carry blend), and succeed on arrival.
class GoTo extends BTAction:
	var where := "market"
	var gait := "Walk"
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
	var blocks: Array = []

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
	var mood := ""

	func _tick(_delta: float) -> Status:
		var a: Dictionary = blackboard.get_var(&"va")
		var v: Node = blackboard.get_var(&"vill")
		return SUCCESS if v._town_mood(a) == mood else FAILURE


static func plain(steps: Array) -> BTTask:
	var s := BTSequence.new()
	for t in steps:
		s.add_child(t)
	return s


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
	var work := BTRandomSelector.new()
	for x in acts:
		work.add_child(x)
	life.add_child(work)
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
	player.behavior_tree = bt
	# One in three is quick to anger or slow to cope: they shout in a riot and slump in a famine.
	player.blackboard.set_var(&"moody", role != "child" and rng.randf() < 0.35)
	player.blackboard.set_var(&"va", a)
	player.blackboard.set_var(&"ground", func(q: Vector3) -> float: return vill.terrain.height_at(q.x, q.z))
	player.blackboard.set_var(&"vill", vill)
	player.blackboard.set_var(&"post", person.position)
	player.blackboard.set_var(&"face", person.rotation.y)
	player.blackboard.set_var(&"choices", acts.size())
	player.blackboard.set_var(&"danger", false)
	person.add_child(player)
	a["mind"] = player
	return true
