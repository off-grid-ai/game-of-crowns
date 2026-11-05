# Realm — working vision

The one place where decisions live. New ideas get added here. They don't replace what's already decided unless we say so explicitly.

## The game in one line
A living medieval-fantasy world that runs on its own on your laptop. You are its King: you watch it, rule it, and live with what your rulings set in motion.

## Decided
- **Setting:** Game of Thrones *era and feel* (medieval, great houses, castles), with mythical touches (the dead beyond the wall, wildlings). No dragons: dropped 2026-11-03. It doesn't need to be Westeros or use GoT names.
- **One age.** Medieval throughout. Tech grows within it (wooden forts become stone castles), but there's no march to industrial or sci-fi.
- **Self-running.** Villages grow into towns and kingdoms at their own pace. It keeps going while you're away (it catches up when reopened).
- **You are the King.** The great houses are your vassals and run themselves. Your goal: **keep the peace while the realm prospers.** Royal tools: grain and gold to houses, raise the royal army, grant or strip castles, raise buildings. Famine, plague and the dead are fate testing your reign (with a sandbox "god" mode to trigger them yourself). The HUD shows Peace and Prosperity.
- **Deep cause and effect.** Famine, abundance, plague, faith, unrest and war ripple through the simulation. Different peoples react differently, and their history changes them.
- **Look:** like Manor Lords (rich stylized 3D). Top-down by default, zoom smoothly into a city and into buildings to see people working.
- **People animated** with Mixamo (or an equivalent free library).
- **We are system integrators.** Every layer, including the simulation itself, comes from an existing open project. Our code is glue: connecting the pieces, translating one's output into another's input, and giving you narrative control. Before writing anything, ask "who has already built this?"
- **Closest existing game:** WorldBox (right loop, visuals too low quality). Manor Lords is the visual reference, not a substitute.

- **Personal use only, so licences don't matter.** GPL engines, 0 A.D. art, Sketchfab models and so on are all fair game. Pick on quality and fit alone.

- **Scenarios and restarts.** Start a new realm any time from a scenario: map size, land and climate, which houses exist, how rich and aggressive they are, starting wars or alliances, how often fate strikes. Save scenarios to replay them.
- **Track everything.** Treasury, food, population, armies and towns per house and for the realm, with history charts over time.

## What it is, underneath (added 2026-11-05)
- **Westworld in a Game of Thrones world.** An interactive world simulation: the people in it aren't scenery, they're minds. Each one remembers, wants, decides and acts on their own, and talks with you and with each other.
- **Our edge is the local model (Off Grid AI Desktop).** With no call caps and no cloud cost, every NPC can have a mind of its own, not just the named lords.
- **You are guest and Ford at once.** You walk among them and talk (they remember you), and you write their narratives (story arcs), which they then live out in their own way.

## v1: what ships (frozen 2026-11-05)
Nothing new goes in unless it blocks the bar below; ideas go to v1.1.
- **In v1:** the world, towns, seasons, crops, coast and rivers; battles on open ground with no one inside a building, and the mounted messenger; every person a mind (memory, mood, plans, talk with you by voice and with each other, gossip that travels); story arcs, commoners included; the double-click Mac app.
- **The bar:** one combined check passes (no one inside a building or sunk, no script errors, screenshots look right); Ali plays a session from the app and it holds up (speed as it stands is fine, Ali 2026-11-05); signed with the Off Grid AI Developer ID.
- **Release calls (2026-11-05, agreed):** always day for v1, with no day/night toggle (nights return in v1.1 with lit windows and torches); no tall grass inside towns; a richer colour grade; conversations as captions, not spoken; arc beats in short fixed lines with one line of colour from the model; any scene that fails the final pass (duel, siege, interiors, close-up battle) stops playing rather than being fixed.
- **Playing as a character is version 2 (2026-11-05, Ali):** in v1 you are the King on the throne and rule from above: the realm, the court, decrees, the houses, the chronicle, and anyone you click on. Walking as the King or any lord (streets, talking face to face, fighting, riding, interiors) is built and kept, switched off by one flag, `realm/scripts/features.gd` `WALKING`.
- **The reign is a story, and the King plays politics (2026-11-05, Mac):** in v1 the King can buy every house's love and nothing comes for his throne. This is a gap that blocks shipping, so it goes in v1.
  - **Reign stories.** Every chronicle has a main story that comes for the throne, told in acts, and the reign ends when it ends: survive it and you win, fail and you fall. Progress shows in play (the act, and how near the threat is to the throne).
  - **Stories are data made of beats** (the arc engine, `bridge/arcs/`, `docs/STORY_ARCS.md`). A beat can bring a choice to the King's court, branches follow his ruling, and a story carries a threat meter and can end the reign. There are built-in beats and the player's own beats (files now, a form later). Stories only read the realm through conditions and act through the court's levers: loose coupling, so stories are added without touching code.
  - **Tags** say what a story is and set the dials of the reign: threat (usurper, rebellion, intrigue, war, faith, plague and famine, the dead, money, invasion, succession), who's against you, feel (fast-paced, slow-burn, gritty, violent, aggressive, cunning, tragic, political, mysterious, epic), length (short, a reign, a dynasty), hardness.
  - **The New Chronicle screen** offers story cards filtered by tags, "let the realm decide", or **generate your own** from tags, a write-up or both. With Off Grid AI the model casts and words it within the beats; without it, rules assemble one from tags. Every generated story is checked before it begins.
  - **Powerful politics:** alliances (an oath that binds a house to the King's wars), March on a house (the royal host attacks), stripping titles, hostages, summoning the council, spies, executing traitors. Freeciv has no diplomacy in its scripting, so these are the bridge's own levers, with Freeciv fighting the battles.
  - **Balance:** decree costs bite against the treasury, gifts lose force when repeated, rivals resent the King's favourites, and long wars cost the crown. Gold is never the answer to everything.
  - **A catalogue of about 20 stories**, each with versions, starting with The Usurper's Claim.
- **No model in the app (2026-11-05, Mac):** the game ships no model and downloads none. It plays by its rules, and lords speak in their own words when Off Grid AI (getoffgridai.co/desktop) is running. Settings and, once, the court say so.
- **v1.1:** mouse-look controls; levies raised from a town's real commoners; live reactions to what happens in front of people; more reverie arcs; 120 fps; the launch kit.

## Approach
1. Survey existing building blocks properly (codebases, art, sim content, engine kits). *Done: see BUILDING_BLOCKS.md.*
2. Choose the stack from that survey, together. *Proposed: Godot 4 + Quaternius art + Azgaar world seed.*
3. Proof: one living valley built from those pieces, so you can judge quality before committing.
4. Then the full realm.

## Open questions
- Platform: browser (three.js) vs Unity vs Godot. Decide after the survey.
- Budget for paid art packs (e.g. Synty), if free art isn't good enough.
- How you steer the narrative: direct events only, or also "story arcs" you set up (e.g. "make House X rise, then betray Y")?
