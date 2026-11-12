extends RefCounted
## Every mind in the army layer (docs/research/army-layer-2026-11-12.md), made one way: a LimboAI state machine
## (LimboHSM, MIT, realm/addons/limboai) built from a row of data/army.json minds. A row names its states (what
## each does on entering, each frame and on leaving, and who may enter it), the events that lead from one to
## another, the events that lead to a state from any other, and where it starts. The doing is the fight's own
## (army_melee.gd and its stagings for men, army_field.gd for regiments): the row names their methods. A new kind
## of soldier or a new turn in a fight is a new row, not another hand-built machine.
##
## The one owning a mind is a Dictionary (a man, a regiment); its state's name is kept on it as state_name.

const Data := preload("res://scripts/data.gd")


## Makes the mind `kind` (data/army.json minds.<kind>) for `who`, carried by `body`, its states doing `owner`'s
## methods; starts it. Kept on who as hsm.
static func make(kind: String, who: Dictionary, body: Node, owner: Object) -> LimboHSM:
	var row: Dictionary = Data.value("army", "minds." + kind, {})
	var hsm := LimboHSM.new()
	hsm.name = "Mind"
	var states := {}
	var defs: Dictionary = row.get("states", {})
	for state_name in defs:
		var d: Dictionary = defs[state_name]
		var st := LimboState.new()
		st.name = String(state_name)
		hsm.add_child(st)
		states[state_name] = st
		var label := String(state_name)
		var enter := Callable(owner, String(d["enter"])) if d.has("enter") else Callable()
		st.call_on_enter(func():
			who["state_name"] = label
			if enter.is_valid():
				enter.call(who))
		if d.has("tick"):
			var tick := Callable(owner, String(d["tick"]))
			st.call_on_update(func(dt: float): tick.call(who, dt))
		if d.has("exit"):
			var leave := Callable(owner, String(d["exit"]))
			st.call_on_exit(func(): leave.call(who))
		if d.has("guard"):
			var guard := Callable(owner, String(d["guard"]))
			st.set_guard(func() -> bool: return bool(guard.call(who)))
	for t in row.get("go", []):
		hsm.add_transition(states[t[0]], states[t[1]], StringName(t[2]))
	var any: Dictionary = row.get("any", {})
	for ev in any:
		hsm.add_transition(hsm.ANYSTATE, states[any[ev]], StringName(ev))
	hsm.initial_state = states[row.get("start", defs.keys()[0])]
	body.add_child(hsm)
	hsm.initialize(body)
	hsm.set_active(true)
	who["hsm"] = hsm
	return hsm


## Tells a mind something happened (an event its row knows); nothing if it has none or is gone.
static func send(who: Dictionary, event: StringName) -> void:
	var hsm = who.get("hsm")
	if hsm != null and is_instance_valid(hsm) and (hsm as LimboHSM).is_active():
		(hsm as LimboHSM).dispatch(event)


## Stops a mind for good (a fallen man's body is cleared away; his place goes to a fresh man with his own).
static func stop(who: Dictionary) -> void:
	var hsm = who.get("hsm")
	if hsm != null and is_instance_valid(hsm):
		(hsm as LimboHSM).set_active(false)
