# Round 5, after

Filmed 2026-11-10, 20:42–22:40 IST, on a private bridge (8850), never Mac's realm. Heads used: 6e48c46 (the after set), 17458fc (motion v2), 217d541 (the review capture), c53c1dd and 9da1be6 (the refilms). Minds on (`--limbo=all`) throughout, motion v2 from 17458fc on. Motion was read as frame strips at 4 fps (zoom at 7). The game's own CHECK lines were read for every shot that has one.

The review page has the screens: https://claude.ai/artifact/4PkjM4Z31UEeDdoGHrHczo (v10, commit 5b79ffb).

## Pass or fail, in the player's words

| Check | Result | What you see |
|---|---|---|
| The court holds through the season's turn (truce) | **Can't tell yet** | `/test/court {sit}` raises no court when nothing is due, and the tourney card was refused ("no lord can be dealt tourney now"). The rerun deals the first card any lord can take. |
| Talk heard at street level | **Fail** (6e48c46) | Seven frames over 21 s beside the folk: no words over anyone (talk-01, 04, 06). On d3fe54c the sweep and the "CHECK talk heard" funnel are in the last run. |
| War and riot read from the street | **Fail** (6e48c46) | Wide, close and street: a crowd in the square, with no barricade, standards or overturned cart in frame (dress-*). d3fe54c's dressing is in the last run. |
| Rain at realm, town and street height | **Pass** (7d078c6) | Staged rain now holds. Grey sky, soft light, fine streaks only at the street. Before the fix, staged rain fell away at the season's turn, leaving a blue sky over "rain". |
| Long white rain sticks | **Fail before 3411cc0** | One stick in about four frames crossed the lens (motion/crowd-walk-strip, v2-market-strip). Not seen in the 7d078c6 frames. |
| The camera from the realm to the street | **Pass** (c70c280) | Smooth all the way down; it stays oblique and ends in the castle yard by the fire. Before: it tipped almost straight down mid-zoom and ended on a lake shore. One frame grazes a tower's stone. |
| A town's choices beside the town | **Pass, with a flaw** | Saltkeep's card opens beside the town with "Starving: the granary is empty" first. Flaw: it covers the town's right third, and it stays open at the screen's edge when the camera leaves for Kingsmere. |
| Grain to a starving town | **Pass** | "Grain from the royal stores" sends wagons out of Kingsmere (review page: starving-grain). |
| Faces at court | **Pass** | Each matter waits on the map at its place. Clicking a face can't be filmed: the portrait marker has no words to press, so the harness needs a step for it. |
| Scar hover | **Pass** | "Men died fighting here in winter …" by the cursor. |
| The interface at rest | **Pass** | One-line heading and one treasury pill. Hovering opens "The story so far" and the treasury's breakdown. Before (6e48c46): a three-line heading and a bar. |
| Hover a townsperson | **Fail** (217d541) | No tooltip with the cursor mid-street. The rerun on c53c1dd hovers nine spots. |
| Stormwatch's orange balls | **Not reproduced** | A fresh sack and a battle marked at Stormwatch, filmed at 6 and 1.5 by day: no glowing spheres. Night is in the last run. |
| Feast at night, winter | **Partial** | Flame and glow sit low in the stone pit. One dancer stands inside the ring. About half the ring faces the fire. Night never came on time: `--hour` is ignored outside shots. |
| Crowds: bodies inside bodies | **Fail** | The game's CHECK on motion v2: walking crowd closest 0.88 m (good), gossip 0.08 m, market 0.00 m (234 pair-frames under half a metre), feast 0.00 m. Two Convoy rangers stood on the very same spot. |
| Kneeling at bare ground | **Fail** | A man on all fours stays in the market and the street through whole clips (v2-market-strip, v2-gossip-strip). |
| Bodies that pop | **Fail** | A kneeling man becomes a standing man on the same spot between two frames (v2-crowd-walk-strip, frames 6–7). A cart in the square vanishes between frames, with legs under it (before set). |
| Things in hands | **Fail** | No cup, tool or basket seen in a hand in the v2 market, gossip or feast clips. One man at the feast holds up a sword. |
| Staged scenes | **Partial** | Battle passes (oblique, the lines engaged). Siege frames a wall and stakes, no siege. Feast, handover, muster and convoy staged by shot flags never came into the harness's window; the review page uses the feast and grain-wagon clips instead. |
| The game stopping | **Fail, twice** | A night feast at street level froze for 150 s (worst frames 4.9 s and 7.4 s) on 83d7f87. The 9da1be6 refilm stopped answering on a street framing with Godot at 100% CPU; the hang sample came back empty. |
| Street speed, probe on | 26 fps | 38 ms a frame, physics 19–22 ms of it (6e48c46). |
| Shader errors (the new land seams) | **None** | Not one shader line in any GPU run's log. |
| Body sheet | **See the sheet** | bodies-sheet.jpg. heraklios wears what reads as a gas mask. Male_Peasant, Female_Peasant and Male_Ranger are glTF bodies outside the line-up tool's folder, so they render empty there. |

## Not stageable this round, and why

- Interlude and the reign's end: `/test/clock` came in late. They're in the last run.
- Ultimatum and court-ultimatum: no threat body for an ultimatum yet.
- Follow-house: needs a house's host in the field and the houses panel's follow press.
- Clicking a petitioner's face: needs a harness step (the marker has no text).
- Lore, the ledger, the intro and the tour: the first try crashed my bridge copy (WORLD.md missing), so the lore pages show "The realm is forming". Rerun in progress.

## The scripts' own faults (not the game's)

- The bridge copy lacked WORLD.md, so /lore crashed it. Fixed.
- `quiet` closed the court before the petition shot. Fixed in the rerun.
- The first scene clips were timed too early.
- Only the battle Godot loaded scripts in the 21:28:32–55 window; it was reshot.

## Last run (c0d529d, 22:33–22:58)

- **Truce: fail to stage.** A card was dealt, but no court card showed through 19 holds ("clear"), so whether the court holds through the season's turn is still unproven.
- **The petition's answers: not filmed.** The harness's answer step found "nothing to answer".
- **The game stopped answering again** at the start of the talk sweep (a plain 6 s wait). Talk, war and riot on d3fe54c, the market's hands and the hover reshoot never ran.
- Schemes, road, Stormwatch at night, the interlude and the reign's end, and the six role sheets were filmed. They aren't on the review page yet (v12 not published).

## Reshoots (11 Nov, 5a8990e and d522d77)

- **Truce: pass.** The court sat on one matter (the same id throughout) while the peace was commanded. The ceasefire reload ran (1.0 s) and the matter was still waiting after it. The realm held still while the court sat, so no season turned behind it.
- **Hover a townsperson: pass.** The trade and mind show by the cursor ("Miller: Good straw this year. Thatch before the rain.").
- **A town's choices: pass.** Saltkeep's card opens beside the town and is gone once the camera pans away.
- **Faces at court: pass.** Pressing the first face frames Saltkeep and stands the Hand's card beside it. The answers show sigils with ▲/▼ and the price in crowns.
- **Long rain sticks: still seen.** One stick crosses the lens in a street frame on 5a8990e.
- **The cast by role** (review page, bodies v2): peasant and townsfolk are the same twelve bodies in the same order. Soldier and knight look alike. Half the clergy aren't robed, and the nobles are knights, nuns and rangers.

- **Rain with the camera moving: pass** (b9f6f02). No white streaks in 28 frames. Separate problem: the street camera passes through market stalls, barrels and a passer-by, which turn see-through as it goes.
