# War formations and war action: blocks and designs (2026-11-15)

Mac after the siege shot (pikes sideways, regiments as march columns, horse in single file, ram alone):
"you need actual war formation, and war action done properly". Research only; no code, no runs.

## What we have, and why it looks wrong

- A regiment is one rigid block: `army.gd _regiment` keeps slot positions (`local`) in the block's frame, one VAT
  MultiMesh, one node moved by `Mover.toward(spot, speed, look)`. Shapes: `line`, `column`, `deck` only
  (`army_formation.gd layout`). No facing order, no wheel, no slot following, no shape per kind.
- **Root cause of "march columns" (measured from the code, not a guess):** `layout` cuts a line's files by
  `sqrt(drawPerMan)`. With drawPerMan 0.05 that is x0.22: battle.json `field.frontage` [10,14] gives **2-3 files**,
  army.json `line.frontage.cavalry` [12,16] gives **3 files** at rank spacing 0.5. With ~40-48 figures a "line" is
  2-3 wide by 15-20 deep: a column. Horse at 3 x 14 with 0.5 between ranks reads as single file.
- **"Pikes sideways":** `Mover.toward(spot, speed, look)` slides the block to its spot while it faces `look`
  (`army_field.gd _advance`, `_charge` faces `-side`). A block crabs sideways instead of turning then marching.
- Melee (`_fight`): front figures play random attack/hit/block clips on timers; no pairing with the man opposite,
  no rank stepping up, the line never moves. Charge: one fixed `shock` loss, then it stays stuck in.
- Siege: engines and the ram are props (`siege_camp.gd _parked/_roll`); the storm's regiments stand on beats;
  the 6-man assault parties (`army_assault.gd`) are the only wall fight. No ladders, no tower docking, no crews
  in formation round the ram, defenders are 18 loose men.

## Candidates

| Candidate | What it gives | Maturity | Licence | Godot 4.7 fit | Effort |
|---|---|---|---|---|---|
| **0 A.D. Formation component + templates** (`simulation/components/Formation.js`, `templates/special/formations/*.xml`) | The best open formation *design*: shapes as data (square/triangle, WidthDepthRatio, Min/MaxColumns, ShiftRows, CenterGap, Sloppiness, SortingClasses, SortingOrder fill-from-sides/centre, separation multipliers, per-row animation variants), slot assignment (class blocks, then each unit takes its closest free offset), MaxTurningAngle (bigger turn = reform), auto column for long marches (>128 m), formation speed = slowest x multiplier | 15+ years, shipped | Code GPL-2+: **design and data shape only**, no code copied | Data maps 1:1 onto our army.json + `army_formation.gd` | Low: rewrite `layout` from the parameters |
| **Mount & Blade II: Bannerlord orders** | The order vocabulary players know: arrangement (Line, Shield Wall, Loose, Circle, Square, Skein=wedge, Column, Scatter), facing (face enemy / face direction), movement (advance, charge, fall back, hold), width; siege as lanes (each ladder/tower/breach a lane with attackers queued and defenders assigned) and engines worked by crews at standing points | Shipped, huge playerbase | Proprietary: **design only** (class names from community decompiles, unverified) | Orders map onto our LimboAI HSM rows | Design reference |
| **Total War (Shogun 2 → Warhammer III)** | Battle beats: approach at walk, charge at run inside charge range with a mass/charge bonus, matched-combat pairs on the contact line, rear ranks fill the front, push, cavalry cycle-charge (hit, ride out, reform, hit again), braced spears beat a frontal charge, morale waver then rout; sieges with ladders, towers docking, rams under cover | Shipped | Proprietary: **design only** | Our VAT clips (attack, block, hit, death) are enough for paired beats | Design reference |
| **Spring / Beyond All Reason CustomFormations** | Drag a line, units spread along it; slot assignment by Hungarian algorithm up to ~20 units, greedy linear above | Mature widget | GPL-2: **algorithm only** (Hungarian is textbook) | Regiments to places in a host line (≤20 at once) | Low |
| **Millington & Funge, *AI for Games* §3.7 "Coordinated movement"**; Pottinger, "Coordinated Unit Movement" (Gamasutra 1999, AoE); Jurney, "Company of Heroes Squad Formations Explained" (AI Game Programming Wisdom 4) | Two-level formation steering (an anchor walks the route; men steer to slots behind it), slot roles and cost-based assignment, wheel vs pivot, formation lags and catch-up | Textbook / shipped games | Books: designs free to implement | Direct fit to our anchor node + slots | The method we write to |
| **Godot NavigationServer3D avoidance (RVO2)** | Per-agent avoidance in the engine | Core engine | MIT | Native | Use for loose men only (rout, skirmish, wall-walk crowd); never for formed blocks |
| **LimboAI** (already in `addons/limboai`) | HSM + behaviour trees | Mature, active | MIT | In use (`army_mind.gd`) | Regiment orders and crew jobs become rows, not new machines |
| **Godot AStarGrid2D** (already, `army_ground.gd`) | Routes round held ground | Core | MIT | In use | Keep: anchors route on it |
| Godot 4 RTS kits (lampe-games/godot-open-rts MIT, ElementTech/godotrts MIT, RTS Advanced Lite MIT, philipbeaucamp rts-entity-controller, licence unstated) | Selection, group move to offsets, per-unit avoidance | Hobby / small | MIT mostly | Godot 4 | **No regimental formation, wheel or melee line in any of them.** Not worth integrating |
| OpenRA | Group moves, no formations | Mature | GPL-3 | n/a | Nothing to take |
| Ultimate Epic Battle Simulator | Scale proof only; no documented formation/combat system | Shipped | Proprietary | n/a | Nothing to take |
| Flow fields (Emerson, Game AI Pro ch. 23, Supreme Commander 2) | Many units to one goal | Shipped | Design | Overkill: our blocks route as one anchor | Skip |

**Verdict:** no Godot block exists for regimental formations or line battles (checked the asset library and
GitHub; the RTS kits stop at offset group moves). Per CLAUDE.md that is Mac's call: the proposal is to **port
proven designs** (0 A.D.'s formation data and assignment, Total War's battle beats, Bannerlord's siege lanes) onto
the blocks we already run (VAT MultiMesh, Mover, AStarGrid2D, LimboAI, army_morale.gd). The code is glue on our
own nodes, the design is copied, nothing hand-invented.

## Picks

- **Formations:** 0 A.D.'s template parameters as `data/formations.json` + Millington's two-level steering
  (anchor on the route, figures to slots with a lag) + 0 A.D. MaxTurningAngle (wheel under it, reform over it).
  Shapes: line, column, wedge (horse), shield wall (spears, tight, 1 rank of shields up), loose (archers,
  skirmish), square/circle (spears against horse). Frontage stops being cut by drawPerMan: a line is wider than deep.
- **Battle action:** Total War beats on our LimboAI rows: approach (walk, front square to the foe) → halt in bow
  range → charge (run, last few blocks) → contact line with front-rank pairs (each front figure paired with the
  nearest foe front figure, clips in step: attack against block or hit) → dead front slots filled from the rank
  behind → the contact line pushes toward the side losing. Volleys with a real ballistic angle from speed and
  gravity, arrows landing on the target block's slots and sticking. Horse: wedge, charge, ride through or out,
  reform, charge again; braced spears blunt it. Morale stays army_morale.gd's; rout is loose men on RVO.
- **Siege action:** Bannerlord's lanes + Total War/Stronghold crews: every ram, ladder, tower and breach is a lane
  with its own attacking party in formation and a defender block on the wall walk opposite. The ram moves under a
  crew in a tight block (testudo shape) with an escort regiment; ladders are carried by a party, raised, climbed;
  the tower is pushed by its crew and docks; archers on the walls volley at whatever lane comes closest.

## Integration plan (each step a few hours, cut into 10-minute items when built)

1. **Formation templates as data.** New `data/formations.json` (line, column, wedge, shield_wall, loose, square)
   with 0 A.D.'s fields; `army_formation.gd layout` reads a template, drops the drawPerMan file cut, fills by
   class with closest-free-slot assignment. *Replaces:* `line`/`column` blocks in army.json, battle.json
   `field.frontage`, the sqrt cut. *Mac sees:* field lines 8-12 wide and 4-5 deep, horse 6-8 abreast, archers loose.
2. **Facing and wheeling.** The regiment anchor turns before it walks: under MaxTurningAngle it wheels on its
   flank, over it the men about-face and the ranks reform; it never slides sideways more than a step. Figures
   follow their slots with a short lag (VAT instance writes on `ViewTier.spend_ok`). *Replaces:* `Mover.toward(...,
   look)` crabbing in `_advance`/`_charge`, `army.gd _reform`. *Mac sees:* pikes always point where the block goes.
3. **Column on the road, line on the field.** 0 A.D.'s distance switch: march in column, deploy into the template
   at deploy range with men filing to their new slots. *Replaces:* `_deploy`, `_stand_in_line` special cases.
   *Mac sees:* columns on roads opening into lines facing the enemy.
4. **Approach, charge, contact line.** Regiment rows in army.json `minds` get approach/charge/contact states;
   front-rank pairs with clips in step, rear rank steps up, line pushes by morale and losses. *Replaces:* `_fight`'s
   random swing timers and `surge`. *Mac sees:* two lines meet front to front, men stepping in, the line bending.
5. **Volleys.** Ballistic angle per arrow, draw/loose in step, arrows land in the target block and stick; the
   target raises shields (shield_wall template). *Replaces:* `_volley`'s fixed arc and kill dice. *Mac sees:*
   arching volleys landing on a block and men falling where they land.
6. **Horse.** Wedge template, charge with impact, cycle charge (ride out, reform, again), flank and rear first;
   braced spears blunt it. *Replaces:* `_charge`/`_flank` one-shot shock. *Mac sees:* a wedge crashing in and coming again.
7. **Rout as loose men.** Broken regiments leave the block for RVO agents running off; rally reforms them.
   *Replaces:* `_run` moving the rigid block. *Mac sees:* a line that breaks into running men.
8. **Siege lanes and crews.** A lane object per ram/ladder/tower/breach; the ram rolls inside its crew's tight
   block with an escort regiment; ladders carried, raised and climbed; tower pushed and docked. *Replaces:*
   `siege_camp.gd _parked/_roll` lone engines and the generic `assault` parties. *Mac sees:* the ram with men round it.
9. **Defenders on the walls.** Each lane gets a defender block on the wall walk (`walls.gd walk_toward`): archers
   volley at the nearest lane, melee meets the ladder tops, reserves shift to the lane in trouble. *Replaces:*
   `garrison` 18 spread men. *Mac sees:* manned walls fighting back at every ladder and the gate.

Every number goes in data with a TUNING.md line. Old paths go in the same change (no fallbacks).

## Sources

- 0 A.D. Formation.js: https://docs.wildfiregames.com/javascript/simulation/Formation.js.html
- 0 A.D. formation templates: https://code.wildfiregames.com/D3178 , https://trac.wildfiregames.com/wiki/XML.Entity.Traits.Formation
- Spring CustomFormations (Hungarian ≤20 units): https://springrts.com/phpbb/viewtopic.php?p=360844
- BAR line drag: https://beyondallreason.info/commands/move-line-drag
- Bannerlord formations: https://gamerempire.net/mount-blade-2-bannerlord-battle-formations-guide/ , https://docs.bannerlordmodding.com/
- Godot RTS kits: https://awesome.ecosyste.ms/projects/github.com%2Flampe-games%2Fgodot-open-rts ,
  https://awesome.ecosyste.ms/projects/github.com%2Felementtech%2Fgodotrts , https://godotengine.org/asset-library/asset/5562 ,
  https://philipbeaucamp.github.io/godot-rts-entity-controller/systems/movement
- Books: Millington & Funge, *AI for Games* (coordinated movement); AI Game Programming Wisdom 4 (Jurney, CoH squad
  formations); Pottinger, "Coordinated Unit Movement", Gamasutra 1999; Game AI Pro ch. 23 (Emerson, flow fields).
