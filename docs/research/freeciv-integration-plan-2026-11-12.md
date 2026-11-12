# Freeciv integration plan: a richer world with what Freeciv already has — 12 November 2026

Decided: deeper Freeciv leads ([what-were-getting-wrong](what-were-getting-wrong-2026-11-12.md)).
Commoners are groups. Nobles are named. Every house is a Freeciv player with its own gold.

## Is everything already in Freeciv?

Most of it. Freeciv already runs, saves and plays (its AI) all of this:

| Already in Freeciv (we only configure it) | Where |
|---|---|
| Houses with their own treasuries | Each house is a player; `bridge/lua/snapshot.lua:45` |
| Towns of people as groups; growth, starvation, unrest | City size, food box |
| People working land: farms, mines, forests | Worked tiles; Gold and Iron on hills/mountains (`realmrules/terrain.ruleset:758`) |
| Mine gold flowing to the owner's treasury | Tile trade → tax → that player's gold |
| Trades in town | Specialists, up to 20 kinds (`fc_types.h:411`); we have 3 (`cities.ruleset:47-79`) |
| Caravans and trade between towns | Trade routes and goods (`game.ruleset:666`) |
| Buildings with upkeep | Buildings ruleset |
| Saving all of it, Lua state included | Savegame; `script_server.c:387,399` |

## The real gaps (glue, not engines)

1. **Mines never run out.** Freeciv has no depletion. A short Lua script counts worked turns and removes the Gold resource (`edit.remove_extra`).
2. **We make gold from nothing.** `bridge/treasury.js:104` pays the crown 40 gold per market each turn. That goes; gold comes only from Freeciv's own taxes.
3. **Trades have modern names.** Entertainers, scientists, taxmen. Relabel them as medieval trades.
4. **The view doesn't know who works what.** The snapshot sends towns, not which tiles are worked. Godot can't put miners at a mine. [check: what Freeciv 3.2's Lua exposes about worked tiles]
5. **No goods in stock, no prices.** Freeciv has food, shields, trade and gold, but no grain or ore piles. Not needed for the first chain. Decide later.

## Phases

| # | What | Where | Effort [estimate] | Proof (state check on the private bridge, no renders) |
|---|---|---|---|---|
| 1 | Medieval trade names; gold yield tuned so a gold house is clearly rich; the Ashby lands get Gold-resource mountains; drop gold-from-nothing markets | `realmrules/*.ruleset`, `world_setup_azgaar.lua`, `treasury.js` | ½ day | After 20 turns Ashby out-earns a farming house; crown income equals Freeciv tax only |
| 2 | Mines run out: count worked turns per Gold tile, remove it at the limit, send an event ("the Ashby seam is spent") | `realmrules/script.lua`, `lua/events.lua` | 1 day | Seam spent at the set turn; Ashby income drops once; save and reload keeps the count |
| 3 | The bridge reports income by source, mines and turns left; chronicle lines; crown's choices to tax, borrow from or seize a gold house, using the gold transfer it already has (`campaigns.js:133`) | `lua/snapshot.lua`, `bridge/*.js` | 1–2 days | Snapshot shows per-house mine income; a tithe moves gold once |
| 4 | Godot shows it: miners at worked mines, carts on the road, an abandoned mine when spent | `realm/scripts` | 1–2 days | One batched render with everything else |
| 5 | Optional, later: grain and ore stocks and prices as a small Lua ledger, saved with the game | `script.lua` | Decide after phase 3 | — |

Every number (gold yield, seam life, tithe rate) goes in data with a `TUNING.md` line.

## The first proof

Ashby owns two gold mountains. Its miners work them; its gold climbs past every other house.
The crown taxes it. After N turns one seam runs out; Ashby's income drops once; the chronicle says so.
Save, reload: same gold, same seam count. Godot shows the miners leave the spent mine.

## Risks

- [check] Whether Lua can see which tiles a town works (phase 2 needs it to count only worked mines; fallback: count while the town is the tile's owner).
- [check] Which value types Freeciv's Lua save dump keeps (tables of numbers expected).
- Freeciv's AI won't plan around seams running out. Fine for now.
