# God-game leftovers (2026-11-10)

Mac: "this is from when I was trying to make a god game, but I'm not anymore. I play as the king."
A read-only sweep looked for places where the **player** is a deity. In-world faith stays: septons, prayers, "the King's blessing" on a match, "the gods decide" a trial.

## Cut
| Where | What | Owner | Status |
|---|---|---|---|
| `realm/scripts/bridge.gd` | `god()` posting to `/god`; header said "god commands" | Builder 1 | done |
| `realm/scripts/main.gd` | `ui.god_action` wiring, `_on_god_action` | Builder 1 | done |
| `bridge/tools/test-god.sh` | fires every god command | Builder 1 | done |
| `realm/scripts/ui.gd:7` | `signal god_action` (never emitted) | Builder 2 | to do |
| `bridge/god.js` | `godCommand`: drought, "the gods bless", plague, "the gods raise an army", "whisper treason", "by divine will" a building rises, free settlers and gold | Builder 2 | to do |
| `bridge/routes_decree.js:15, 183-191` | the `godCommand` import, `god()` handler, `record({kind:"god"})`; header names "the god commands" | Builder 2 | to do |
| `bridge/server.js:968` | `POST /god` route | Builder 2 | to do |
| `bridge/minds.js:330` | the `kind === "god"` → "bounty" branch | Builder 2 | to do |
| `realm/scripts/town_panel.gd:89-93` | the hidden Fate box kept "for v2's god mode" | Builder 2 | to do |
| `realm/scripts/houses_panel.gd:45-46` | the comment recording "Proclaim your word" | Builder 2 | to do |
| `realm/scripts/folk_card.gd` (once `commoner_card.gd`) | the commoner chat card, "They stop, and look up at you…" | Builder 2 | to do: cut for the hover tooltip |

## Reframe for a king
| Where | Change | Owner |
|---|---|---|
| `bridge/god.js` `scar()`, `healLua()` | move to `bridge/blight.js` as `blightLua` and `regrowLua` (the realm's own famines and plagues blight land). Not `marks.js`, because `marks.json` already holds battle marks. | Builder 2 |
| `bridge/server.js:519-523` | the `"scar"` event becomes `"blight"` and `blights.json` | Builder 2 |
| `bridge/season.js:19, 185-197` | import `regrowLua` from `blight.js`; rename `healScars` to `healBlights` (the wording stays) | Builder 2 |
| `realm/scripts/villagers.gd:287-288` | the comment "looked at from above … turns up to face the watcher" becomes "the King stops to look at…" | Townsfolk look |

## Keep (in-world faith, about 40 places)
Sept prayers and vigils (npc_mind, town_life, interior), "God keep us" (chatter), "the septons can bless your reign" (lore), "Petitioners kneel before you" (intro, fealty), the King's blessing on matches and pacts (characters, petitions, dilemmas, ledger), the Freeciv wonders (narrator), and the omens vignette (a mood signal, not a power).
