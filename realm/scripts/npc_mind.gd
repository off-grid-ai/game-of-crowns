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
	return []


## Gives a person posted at a scene their mind: a BTPlayer whose tree picks among
## the post's activities at random (never the same twice running), with Danger
## first: struck or threatened, they react and get clear, then go back to work.
## `ground(p)` gives the ground height at a point. Returns false for an unknown post.
static func give(person: Node3D, post: String, ground: Callable, seed: int) -> bool:
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
	var first := BTRandomWait.new()  # each on their own clock
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
				seq("gossip", [go("well"), run(["Whispering", "Telling_A_Secret", "Laughing"], 2, 4), brk(LOOK)]),
			]
	return []


## A villager's mind: at night and dawn they go home and rest; through the day
## their role's activities, one at a time and never the same twice running.
static func give_villager(person: Node3D, a: Dictionary, vill: Node) -> bool:
	var acts := villager_activities(String(a.get("role", "")))
	if acts.is_empty():
		return false
	var life := BTDynamicSelector.new()
	var night := BTSequence.new()
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
	player.blackboard.set_var(&"va", a)
	player.blackboard.set_var(&"ground", func(q: Vector3) -> float: return vill.terrain.height_at(q.x, q.z))
	player.blackboard.set_var(&"vill", vill)
	player.blackboard.set_var(&"post", person.position)
	player.blackboard.set_var(&"face", person.rotation.y)
	player.blackboard.set_var(&"choices", acts.size())
	person.add_child(player)
	a["mind"] = player
	return true
