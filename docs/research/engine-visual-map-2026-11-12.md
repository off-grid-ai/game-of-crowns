# Engines against the screen (2026-11-12, army layer for the supervisor)

Mac: "combine the engines with the visuals". Source: the Freeciv thread's 40-season reign (/tmp/goc-reign/run2,
T38-T78, 31 -> 48 towns, 7 towns changed hands, 8 houses at 2-9 wars each), the store's slices (awareness.gd) and a
scan of every view script for a reader of each fact. "Changes" = seasons out of 40 in which the fact moved.

## 1. Engine facts and where they show

| Fact (changes) | On screen | Gap |
|---|---|---|
| Units x,y (every season, 2248 moves) | units.gd figure per company, marching | figures lagged (fixed 3f74c515), view syncs after the town build (main.gd) |
| Unit hp, activity | wounded / fortified stance (units.gd) | - |
| **Unit goto (40 of 52 set)** | crown hosts' orders only (map_marks) | **a house's host bound for a town is invisible** |
| **Ships (Trireme: 64 of 79 three-tile moves)** | a soldier walking the land | **wrong; transports only (Mac), model via look-audit** |
| Hosts (crown, orders, men) | army.gd host, command card, map banner | - |
| Armies in the field (houses) | map banners with men (map_marks) | - |
| Wars / atWarWith (55 changes) | political overlay, house card, top bar | not on the land itself |
| Truces, sworn | overlay, town banners | - |
| City size (209), buildings (22), building now (554) | town grows, buildings stand, site rises | - |
| Owner (7 handovers) | handover scene, banners, borders | - |
| Mood / disorder / famine / grief / celebrating | townsfolk minds, works, scenes | - |
| Granary low, food, progress, odds | town card numbers; granary_low -> works | food only as numbers |
| **City plague (4)** | only the passing "plague" scene (refugees) | **a sick town looks well between scenes** |
| City rapture (31) | none (celebrating covers part) | low |
| Damage / burnt (141) | walls crack and breach, burnt houses | - |
| Besieged, rising, levy, ruling | siege camp, map swords, works, scenes | - |
| Roads (25) | roads laid | - |
| Borders / owners (36) | land tint, minimap | - |
| Intrigue (10) | scheme marks on the map | - |
| Threat, peace, prosperity, souls | top bar, reign cards | numbers only |
| Favour, trend, effects (32) | houses panel, effect toasts | - |
| **House income (277), gold (262)** | none per house (purse net only, top bar) | **can't see who is rich** |
| Government (18) | none | low (Monarchy is all) |
| Scenes (13 kinds, 2500 in the reign) | every kind has a play (scene_kinds.gd) | - |
| Weather, season | sky, snow, sound | - |

## 2. Drawn with no engine fact (by design or not)
- Wildlife (animals.gd), forest, grass, rivers: ambient, by design.
- Castle folk (castle_folk.gd): generic guards and servants, not the house's men; low.
- Ships as soldiers (above): wrong, not ambient.
- Field battle men: one figure for ten men (drawPerMan, Mac's call), driven by the realm's battle and its victor.

## 3. Gaps ranked by what a player notices
1. Ships drawn as soldiers on land (army; model from look-audit, rules: transports only, Freeciv owner).
2. Company figures behind or missing after a season (army: fixed 3f74c515; main.gd's sync order: One store).
3. A house's host marching on a town is invisible until it arrives (army: map_marks draws every host's march).
4. A plagued town looks well between scenes (town: One store).
5. Who is rich: per-house income and gold unseen (UI: One store).
6. Wars only in the overlay, not on the land (army/look: later).
7. Rapture, government: unseen (low).
