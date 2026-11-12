extends RefCounted
## Every kind of scene the realm plays, in one table (DRY): what it is to the
## people who see it, how far the news carries, how the minimap marks it, how
## much the camera director cares and what its caption says. The bridge sends
## the kind (world.scenes); scenes.gd, director.gd, minimap.gd, awareness.gd and
## the sound read their part of it here, and nowhere else.

## The tones: what a scene is to whoever sees it.
const HOSTILE := "hostile"  # steel and fire: people run if close, watch if not
const TROUBLE := "trouble"  # want and sickness
const GRIEF := "grief"  # a death, a vigil
const JOY := "joy"  # a feast
const CROWN := "crown"  # the King's own doing on the roads
const NEUTRAL := "neutral"

## kind -> {tone, reach (world units), power (0-1), interest (director), dist
## (camera distance), caption (with %s for the town), play (the class that stages it: scene_kind.gd's; scenes.gd keeps one of each class), fleeing (how many
## refugees leave the town), burn ([seconds, size] of the fire set in it)}.
const KINDS := {
	"siege": {"tone": HOSTILE, "reach": 5.0, "power": 0.9, "interest": 10, "dist": 7.0, "caption": "The siege of %s", "play": "res://scripts/scene_kinds/siege.gd"},
	"storm": {"tone": HOSTILE, "reach": 6.0, "power": 1.0, "interest": 10, "dist": 7.0, "caption": "%s is stormed", "play": "res://scripts/scene_kinds/siege.gd"},  # Freeciv's assault on a siege (campaigns.js stormScene)
	"battle": {"tone": HOSTILE, "reach": 5.0, "power": 0.9, "interest": 9, "dist": 8.0, "caption": "Battle near %s", "play": "res://scripts/scene_kinds/battle.gd"},
	"sack": {"tone": HOSTILE, "reach": 6.0, "power": 1.0, "interest": 9, "dist": 8.0, "caption": "%s is sacked", "fleeing": 7, "burn": [45.0, 1.0], "play": "res://scripts/scene_kinds/sack.gd"},
	"razed": {"tone": HOSTILE, "reach": 7.0, "power": 1.0, "interest": 9, "dist": 9.0, "caption": "%s burns", "fleeing": 10, "burn": [70.0, 2.0], "play": "res://scripts/scene_kinds/sack.gd"},
	"raid": {"tone": HOSTILE, "reach": 4.0, "power": 0.9, "interest": 6, "dist": 7.0, "caption": "Raiders at %s"},
	"struck": {"tone": HOSTILE, "reach": 1.2, "power": 0.8, "interest": 0, "dist": 4.0, "caption": ""},
	"fire": {"tone": HOSTILE, "reach": 1.8, "power": 0.9, "interest": 0, "dist": 5.0, "caption": ""},  # a house catching (fire.gd): the near run (batch 9: at 1.0 the square carried on beside it), the rest come to the bucket line
	"handover": {"tone": HOSTILE, "reach": 3.0, "power": 0.6, "interest": 3, "dist": 8.0, "caption": "%s changes hands", "play": "res://scripts/scene_kinds/handover.gd"},
	"famine": {"tone": TROUBLE, "reach": 3.0, "power": 0.6, "interest": 5, "dist": 6.0, "caption": "Famine in %s", "fleeing": 5, "play": "res://scripts/scene_kinds/refugees.gd"},
	"plague": {"tone": TROUBLE, "reach": 3.0, "power": 0.6, "interest": 5, "dist": 6.0, "caption": "Plague in %s", "fleeing": 3, "play": "res://scripts/scene_kinds/refugees.gd"},
	"vigil": {"tone": GRIEF, "reach": 2.5, "power": 0.9, "interest": 4, "dist": 5.0, "caption": "A vigil at %s"},
	"death": {"tone": GRIEF, "reach": 2.5, "power": 0.8, "interest": 4, "dist": 5.0, "caption": "Mourning at %s"},
	"feast": {"tone": JOY, "reach": 2.5, "power": 0.7, "interest": 3, "dist": 6.0, "caption": "A feast at %s", "play": "res://scripts/scene_kinds/feast.gd"},
	"grain": {"tone": CROWN, "reach": 1.5, "power": 0.4, "interest": 4, "dist": 9.0, "caption": "The King's grain on the road to %s", "play": "res://scripts/scene_kinds/convoy.gd"},
	"tribute": {"tone": CROWN, "reach": 1.2, "power": 0.3, "interest": 3, "dist": 9.0, "caption": "The King's gold on the road to %s", "play": "res://scripts/scene_kinds/convoy.gd"},
	"wagon": {"tone": CROWN, "reach": 1.2, "power": 0.3, "interest": 2, "dist": 9.0, "caption": "Wagons on the road to %s"},
	"muster": {"tone": CROWN, "reach": 2.5, "power": 0.6, "interest": 4, "dist": 6.0, "caption": "The King's levy musters at %s", "play": "res://scripts/scene_kinds/muster.gd"},
	"rider": {"tone": CROWN, "reach": 1.5, "power": 0.5, "interest": 3, "dist": 9.0, "caption": "The King's rider, bound for %s", "play": "res://scripts/scene_kinds/rider.gd"},
	"king": {"tone": CROWN, "reach": 2.0, "power": 0.8, "interest": 3, "dist": 9.0, "caption": "The King's banner passes %s"},
	"ward": {"tone": CROWN, "reach": 2.0, "power": 0.5, "interest": 2, "dist": 9.0, "caption": "A ward on the road to %s", "play": "res://scripts/scene_kinds/convoy.gd"},
}

## A kind the table doesn't know: news all the same, heard a little way off.
const DEFAULT := {"tone": NEUTRAL, "reach": 3.0, "power": 0.5, "interest": 1, "dist": 7.0, "caption": "%s"}

## The minimap's mark for each tone.
const PING := {HOSTILE: Color(0.95, 0.25, 0.2), TROUBLE: Color(1.0, 0.7, 0.2), CROWN: Color(1.0, 0.85, 0.45),
	GRIEF: Color(0.75, 0.75, 0.85), JOY: Color(1.0, 0.85, 0.45)}


static func of(kind: String) -> Dictionary:
	return KINDS.get(kind, DEFAULT)


static func tone(kind: String) -> String:
	return String(of(kind)["tone"])


## The minimap's colour for a kind, or none (a transparent colour) for a quiet one.
static func ping(kind: String) -> Color:
	return PING.get(tone(kind), Color(0, 0, 0, 0))
