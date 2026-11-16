extends RefCounted
## Who bleeds at blows (Total War's melee: attack against defence, the charge's shock, flank and rear, fatigue and
## nerve; the casebook's War and sieges: a battle is won on the field). The one decider of losses in a field battle:
## army_field.gd asks it each moment how many men each regiment loses to those fighting it, and lays them down.
## Mac 2026-11-16: "if that actually helps change the course of the battle", "troops need to have morale ... see that
## impact the outcome". Numbers in data/battle.json field.combat and data/battle_orders.json orders.<key>.defence.
##   - each regiment fighting r hits it with its kind's attack, by the share of its men still standing, its nerve and
##     its wind; from r's flank harder (flank), from its rear harder still (rear);
##   - r stands against it with its kind's defence and its order's (a shield wall's against foot and horse, its
##     shields against arrows), less when its wind is gone;
##   - wind (stamina 1 fresh .. 0 spent) drains at blows and on the run and comes back standing: a relieved line
##     comes back fresh, a line never relieved tires and bleeds.

const Data := preload("res://scripts/data.gd")
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
	elif st in ["charge", "rout"] or String(r.get("gait", "")) == "run":
		d = -_c("wind.run", 0.02)
	elif st in ["stand", "relieved", "hold", "volley"]:
		d = _c("wind.rest", 0.03)
	r["stamina"] = clampf(wind(r) + d * dt, 0.0, 1.0)


## Where a blow from `from` lands on r: 0 its front, 1 a flank, 2 its rear (by the angle off its facing).
static func face_hit(r: Dictionary, from: Vector3) -> int:
	var node: Node3D = r["node"]
	var fwd := Vector3(node.global_basis.z.x, 0, node.global_basis.z.z).normalized()
	var to := Vector3(from.x - node.global_position.x, 0, from.z - node.global_position.z)
	if to.length() < 0.001:
		return 0
	var c := fwd.dot(to.normalized())
	return 0 if c > _c("front_cos", 0.5) else (1 if c > _c("rear_cos", -0.5) else 2)


## How hard regiment `a` hits now (its kind's attack by the share standing, nerve and wind).
static func hits(a: Dictionary, nerve: float) -> float:
	var share := float(a.get("living", 0)) / maxf(float(a.get("figures", 1)), 1.0)
	return kind(a, "attack") * share * lerpf(_c("nerve_floor", 0.5), 1.0, nerve) * lerpf(_c("wind_floor", 0.6), 1.0, wind(a))


## Men r loses a second to `attackers` ([{r: regiment, nerve: float}]), fighting in order `order`; also marks r's
## `beset` (0 front only, 1 a flank, 2 its rear), which army_morale.gd reads.
static func loss_rate(r: Dictionary, attackers: Array, order: String) -> float:
	var sum := 0.0
	var beset := 0
	for x in attackers:
		var a: Dictionary = x["r"]
		var face := face_hit(r, (a["node"] as Node3D).global_position)
		beset = maxi(beset, face)
		var hit: float = hits(a, float(x["nerve"])) * [1.0, _c("flank", 1.8), _c("rear", 2.5)][face]
		var against := "horse" if String(a.get("role", "")) == "cavalry" else "foot"
		var guard := (kind(r, "horse") if against == "horse" else kind(r, "defence")) * (order_guard(order, against) if face == 0 else 1.0)
		sum += hit / maxf(guard * lerpf(_c("wind_floor", 0.6), 1.0, wind(r)), 0.05)
	r["beset"] = beset
	return _c("base", 1.6) * sum * float(r.get("men", 1)) / maxf(_c("men_ref", 140.0), 1.0)


## Men a charge's shock `shock` lays down in r, struck from `from` (its order's guard against horse or foot on its
## front, its kind's against a charge).
static func shock(r: Dictionary, shock: float, from: Vector3, horse: bool, order: String) -> int:
	var face := face_hit(r, from)
	var guard := (kind(r, "horse") if horse else kind(r, "defence")) * (order_guard(order, "horse" if horse else "foot") if face == 0 else 1.0)
	return int(round(shock * [1.0, _c("flank", 1.8), _c("rear", 2.5)][face] / maxf(guard, 0.05)))


## Arrows that land of `n` loosed at r in order `order` (its shields).
static func arrows(r: Dictionary, n: int, order: String) -> int:
	return int(round(float(n) / maxf(order_guard(order, "arrows") * kind(r, "arrows"), 0.05)))
