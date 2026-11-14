# The army layer: what it's built on (12 November 2026)

Ask: replace the hand-built army systems (`units.gd`, `battle_ai.gd`, `siege_ai.gd`, `siege_storm.gd`, `combat.gd`,
`tools/army_spike.gd`, and `tools/field_battle.gd`, a seventh) with one layer. Background:
[sim-physical-world-2026-11-12.md](sim-physical-world-2026-11-12.md) sections 5 and 8.

Tags: **[fact]** has a link or a file:line. **[judgement]** is my reading.

## Blocks surveyed

| Need | Candidate | Verdict |
|---|---|---|
| Where a man can stand on a field (water, houses, walls, breaches) | Godot **AStarGrid2D** (engine built-in; already used by terrain.gd:1416 and towns.gd:255) on a fine cell grid over the fight | **Pick.** Synchronous, no bake wait, cells refreshable when a wall breaks. |
| Same | Godot NavigationServer2D/3D Recast bake (town_nav.gd) | Kept for towns. For a moving fight its bake is async and a whole-region rebake per breach (town_nav.gd:38, 107) [fact]. |
| Crowd avoidance | Godot **RVO** (NavigationServer3D agents) | **Pick**, already proven here (villagers.gd:349, battle_ai.gd:765) [fact]. Moved into the Mover. |
| Flow fields for thousands | godot-tilemap-flowfields (Rust, 2022), GodotFlowField (Godot 3.2, "not ideal"), Godot-4-VectorFieldNavigation (~34 stars) [fact: [1](https://relatedrepos.com/gh/arnemileswinter/godot-tilemap-flowfields), [2](https://github.com/TheFamousRat/GodotFlowField), [3](https://relatedrepos.com/gh/D2klaas/Godot-4-VectorFieldNavigation)] | **Not taken.** None mature on 4.7/arm64. We don't need one: regiments move as one body (Total War's way) and close fights are a few dozen men, so one route per regiment or man on the grid is cheap. Revisit for thousands of free men. |
| Formations / RTS command | RTS Entity Controller (MIT, Godot 4.4), rluders/rts-framework (MIT) [fact: [asset 4784](https://godotengine.org/asset-library/asset/4784), [repo](https://awesome.ecosyste.ms/projects/github.com%2Frluders%2Frts-framework)] | **Not taken.** Selection and command scaffolds; no formations, no massed VAT drawing. Our command card (host_command.gd) already covers selection. Formation slots stay data rows in `data/army.json` (already there). |
| Each soldier's and regiment's decisions | **LimboAI** (MIT, in `addons/limboai`) | **Pick**, already in use. One builder makes every mind from a data row. |
| Drawing thousands | **godot_vat** (in addons) | Kept: the regiments' far look. |

## The layer

- **Ground**: `scripts/army_ground.gd`, one AStarGrid2D per fight, cells shut on water, buildings, walls (open again at a
  breach). `route(from, to)`, `stand(p)`.
- **Moving**: `scripts/mover.gd` only. New: a Mover may stand on a fight's ground (`on(ground)`), follow a way it was
  given on the ground (`follow`), steer each frame toward a moving mark round the men about it (`toward`, Godot RVO).
  A regiment is one body with one Mover; its men hold their slots in it.
- **Minds**: LimboHSMs built from rows (`data/army.json` minds): states, the clip each plays, the tick it runs,
  the events between them. A man's (line soldier, assault man, knight) and a regiment's.
- **Outcome**: the bridge's. Who loses comes in from Freeciv; the minds only play it out.

## What stays ours [judgement]

Formation slot maths, the duel's beats (blow, answer, land), the storm's waves. No block covers these.

## Takeover round (2026-11-12, after the usage limit)
- Item 1 (units.gd reads the store): already landed by one store in 3ade592b; units.gd not on rules_known.txt.
- Item 2: fec0dd15 one body set, one finish (units.<kind>.asset; no units_set/meshy/--units=; no look.on/--army-look/look_painted). army_probe 13.
  motion.v3 const: asked town life (local_906aade6) to drop villagers.gd:127, :696 and people.gd:1265, or OK me to.
- Item 3: autoplay `muster [phase] [most]` (formed/out/halted/gone) on army.gd march_phase(). Film: `--muster --dist=4`,
  play `muster formed`, `snap formed`, `muster out`, snaps every 3 s, `muster halted`, `snap halted`.
- Item 4: far-zoom stand-ins parked until a far-zoom fps number exists.
