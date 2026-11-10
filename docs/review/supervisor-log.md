# Supervisor log

Mac is away. The supervisor ("Casebook: Top Games") runs a check every 10 minutes and keeps both builders
moving through `consolidation-plan.md`, the awareness work and the world-object jobs. It decides every
design call from the casebook and Mac's rules. This log is the report for Mac when he's back.

## Log

- **15:45.** Autonomous mode starts. Done so far today:
  - The news chip.
  - The stuck-drill fix; LimboAI townsfolk for slices 1 and 2; the clone fix.
  - The decision drought fixed (the realm holds when unwatched).
  - A real Freeciv ceasefire; every reign new (seeded tensions); the goal earned.
  - Snow, sound variety, silent sounds wired, scars and ruins, tree variety.
  - The King's name from deeds; decisions shown in the world; a lighter HUD; borders for war, truce and oath.
  - Asset audit, state catalogue, state-architecture and principles audits, and the consolidation plan
    (0eecd77).
- **15:45.** Now: the NPC builder is on A2 (one definition per realm state, proof running). Builder 2 is on traffic.gd.
- **15:50 check.** Landed: A1+A2 (f3316ec), A4/B3/B4 (2a026d8), B2 helpers (b46f16e), B5 decrees as data and handlers (3dcbd0b, 7195c83), the land reading the mirror (36695f2), towns growing as sites (36be65a, d568bff), traffic with one decider (b34937f, 841bab8), A3 (de69dc6), A5 (ebadce5), and more sound takes (fc53f7d). Ruled: urgent matters (famine, siege) jump the court rotation. Drift fixed: Builder 2 edited awareness.gd (the NPC builder's file) and swept lines; it must now request mirror fields instead. Both builders are busy; films not yet run.
- **Builder 2: animals left out, not parked.** Using the signed-in Sketchfab account needs Mac's own yes in Builder 2's chat (its rules: a download from his account), so it took the no-login route. No source passes the look and alive tests: Poly Haven has only a still rat; Quaternius' and Kenney's animals are toy-style (and banned in the asset audit); OpenGameArt has no realistic animated farm animals. The realistic ones (elk, chicken, cow, sheep) are on Sketchfab only: elk https://sketchfab.com/3d-models/787834f9caa2474d9f1814b807c072d7 , chicken https://sketchfab.com/3d-models/4ab19d3a675343959815ae770f8b178e , cow https://sketchfab.com/3d-models/4fe2c9d43532498081a30f1794758954 , sheep https://sketchfab.com/3d-models/b99698502dea4905b916fce0bcf2dfc0 (all CC-BY). If they ever land in ~/Downloads, Builder 2 wires them.
- **Builder 2: sound licences.** rain_roof.ogg (CC-BY-SA) replaced with Kresiek's CC0 rain loop; no CC-BY-SA sound remains. The 27 unlicensed hashed files in ~/Downloads/Aldmere/audio/src and the unreadable JC Sounds archive stay excluded until their licence is proven.
- **Builder 2: weather.** One owner now: the mirror's realm scope (snow in winter, else clear); the sound reads it there (1f4f41a, 7b31945). Nothing in the realm brings rain or storm yet; a storm bed is ready for when something does.

- **16:00 check.** Landed: the court hears a crisis first, and counsel is read once a season (a82db5c); wounded soldiers limp, from Freeciv's hp (f837de0); talk takes two and news spreads through gossip (8fe04b6); the minimap seams (5bbeaa8); the server.js routes table (1351802); the court, Houses, town and ledger panels out of ui.gd (3,616 → 2,671 lines). Unblocked: the freeciv.js helper waited on a turn that the unwatched-hold rule kept frozen; it was told to poll as a window. Both builders are busy; films are due at about 17:45, or when phases A and B are done.
- **16:10 check.** Landed: siege relief, a besieged lord's plea with three choices that count toward the King's name (2674fe2); freeciv.js split out of server.js (c6ca5d4); the chronicle, house card, rank strip, camera pad and reign cards out of ui.gd (c621275, ce70b79, bb7f8fc); the reviewer's three fixes (1f249db: talks hold together, crisis pleas match their crisis, one year). Unblocked: the NPC builder's server.js changes travel as a patch into builder 2's split. Open debt: the mirror still has its own fallback reading of town war, grief and prosperity (4a503e0); it's deleted when the patch lands.
- **16:20 check.** Landed: view.js (C3 step 3, /world as a pure projection) carrying the NPC builder's state hooks (9546032, b9f0600); the mirror keeps no reading of its own (b812a1a; debt paid); the top bar, commoner card, form, news chips, shot_harness.gd and news out of ui.gd and main.gd (4cc1a49, 1c93bce); a null-safe mirror (3256d06); Eve staged for her eye check (526aae4). The grouped film session is running on a private snapshot bridge (port 8850); Mac's realm is untouched. Ruled: the 6 targets that can't be staged get test hooks for round 2 (the King's epithet, hour, wounded soldiers, growth, the court over the reload, Eve).
- **16:30 check.** Landed: court cards drawn from the realm, every card gated and none on dice alone (72efebc); the land follows the realm's season (a7ed6dc, my ruling A: the date and the land agree, with a smooth settle); campaigns.js split out (006a003, C3 step 4); one rule for whether a town's people have minds (d6bfd47); round 2 stage hooks (3563855); petition answers as handlers have begun (b45a0ee, B6). ui.gd is 3,616 → 1,174 lines and main.gd 1,991 → 1,045. Round 1 film results are not in yet; the NPC builder was idle and has been asked for them and set back to work.
