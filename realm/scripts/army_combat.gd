extends RefCounted
## Who falls at blows (Total War's melee: attack against defence, fatigue and the larger host's heart; the casebook's
## War and sieges: a battle is won on the field). The one decider of losses in a field battle: army_field.gd asks it,
## for every man at grips each moment of the field, the odds his blow fells his man (blow), and for every volley how
## many arrows land (arrows).
## Mac 2026-11-16: "if that actually helps change the course of the battle", "troops need to have morale ... see that
## impact the outcome". Numbers in data/battle.json field.combat and data/battle_orders.json orders.<key>.defence.
##   - each man at grips with a man of r strikes with his kind's attack, his host's morale (the larger host's
##     heart: army_field.gd _morale) and his wind, from wherever he stands (Mac 2026-11-17: 2.5 s
##     a kill; a man in the press is struck from every side, so no side counts more);
##   - r stands against it with its kind's defence and its order's (a shield wall's against foot and horse, its
##     shields against arrows), less when its wind is gone;
##   - wind (stamina 1 fresh .. 0 spent) drains at blows and on the run and comes back standing: a troop long at
##     blows tires and falls faster.

const Data := preload("res://scripts/data.gd")
const Troops := preload("res://scripts/troops.gd")
const F := "battle"


static func _c(key: String, fallback: float) -> float:
	return Data.num(F, "field.combat." + key, fallback)


## The kind's own number (field.combat.kinds.<role>.<what>): attack, defence, horse (its defence against a charge).
static func kind(r: Dictionary, what: String) -> float:
	return Data.num(F, "field.combat.kinds.%s.%s" % [String(r.get("role", "melee")), what], 1.0)


## Its order's defence against a kind of blow (battle_orders.json orders.<key>.defence.<foot|horse|arrows>), 1 if
## the order gives none.
static func order_guard(order: String, against: String) -> float:
	return float(Data.value("battle_orders", "orders.%s.defence.%s" % [order, against], 1.0))


## Its wind now, 1 fresh.
static func wind(r: Dictionary) -> float:
	return float(r.get("stamina", 1.0))


## Wind over `dt` by what it does: at blows it drains (fight), running or charging faster (run), standing or falling
## back it comes back (rest).
static func breathe(r: Dictionary, dt: float) -> void:
	var st := String(r.get("state_name", ""))
	var d := 0.0
	if st == "fight":
		d = -_c("wind.fight", 0.012)
	elif st == "charge" or String(r.get("gait", "")) == "run":
		d = -_c("wind.run", 0.02)
	elif st in ["stand", "relieved", "hold", "volley"]:
		d = _c("wind.rest", 0.03)
	r["stamina"] = clampf(wind(r) + d * dt, 0.0, 1.0)


## The odds that one blow of a man of `a` fells the man of r he fights, each moment of the field (field_cells.gd tick; Mac 2026-11-17: "it shouldn't take so long to kill"): blow
## times his kind's attack, his host's morale and his wind and his order's attack, over r's guard
## (its kind's defence, or against a horseman its guard against horse; its order's guard; its wind).
static func blow(a: Dictionary, morale: float, order_a: String, r: Dictionary, order_r: String) -> float:
	var hit: float = kind(a, "attack") * morale * lerpf(_c("wind_floor", 0.6), 1.0, wind(a)) \
		* order_guard(order_a, "attack")
	var against := Troops.of(a).strikes_as()
	var guard := (kind(r, "horse") if against == "horse" else kind(r, "defence")) * order_guard(order_r, against)
	return _c("blow", 0.104) * hit / maxf(guard * lerpf(_c("wind_floor", 0.6), 1.0, wind(r)), 0.05)


## Arrows that land of `n` loosed at r in order `order` (its shields).
static func arrows(r: Dictionary, n: int, order: String) -> int:
	return int(round(float(n) / maxf(order_guard(order, "arrows") * kind(r, "arrows"), 0.05)))
