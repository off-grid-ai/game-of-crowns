extends RefCounted
## Makes each regiment its Troop (troop.gd) by its kind: the one place a role is turned into a kind. A new kind of
## soldier is a new script and a row here, never another branch in the battle.

const Troop := preload("res://scripts/troop.gd")
const KINDS := {
	"melee": preload("res://scripts/troop_foot.gd"),
	"ranged": preload("res://scripts/troop_archer.gd"),
	"cavalry": preload("res://scripts/troop_horse.gd"),
}


## The regiment's troop (made the first time it is asked for, kept on it).
static func of(r: Dictionary) -> Troop:
	var t: Variant = r.get("troop")
	if t == null:
		t = (KINDS.get(String(r.get("role", "melee")), KINDS["melee"]) as GDScript).new(r)
		r["troop"] = t
	return t
