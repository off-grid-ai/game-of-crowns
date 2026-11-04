# Minds: every person in Aldmere thinks

The plan for the Westworld layer (see VISION.md): every person in the realm is a mind
that remembers, wants, feels, decides and talks, with the local model (Omni via Off Grid
AI Desktop) as its reasoning. This file is the contract the sessions building it share.
Change it here first, then in code.

## What exists today
- **Named people** (lords, heirs, bannermen, created characters) live in `bridge/characters.js`
  (`Court`): traits, goals, relationships, up to 12 memories, `remember()`, and a seasonal
  model decision (`bestMove`) that acts on the Freeciv world.
- **Commoners** (`bridge/townsfolk.js`) are generated from the town's id: name, trade,
  nature, family, a past, a want. They have a model-written tale (`folk-tales.json`) and
  remember what you said to them (`talks.json`), but they have no mind: their day in the
  3D town (`realm/scripts/villagers.gd`) is a random schedule.
- **Voice** both ways (speech to text in, a voice per person out) and **story arcs**
  (`bridge/arcs.js`, `bridge/arcs/*.json`, `docs/STORY_ARCS.md`).

## The mind (one record per person, named or common)
Kept by `bridge/minds.js` in the chronicle's state folder (`minds.json`).

```
id          court id for the named; "folk:<cityId>:<i>" for commoners (the key folk-tales use)
name, town, station        trade or rank; sex; age
nature      traits / nature words
wants       1-3 goals, in their own words, each with why
mood        { fear, anger, joy, grief, faith, hunger } 0..1, drifting back to their nature
memories    [{ turn, text (their voice), about: [ids], weight 0..1 }]
            capped; old low-weight ones fold into a one-line "life so far" summary
bonds       { id: { trust -1..1, warmth -1..1, note } }
beliefs     things they hold true, including rumours ("the King poisoned his brother")
plan        { doing, where (place kind or town id), with: [ids], until }
reverie     0..1: how much they have begun to see past their loop (see below)
```
Named people keep their `Court` record as the source for rank, seat and house;
their mind adds mood, beliefs, bonds to commoners and plan. One id, one person.

## Attention: who thinks how often
The model has no call caps but has a throughput, so thinking follows attention, like
animation detail follows distance:
- **Hot:** near the camera or the player's body, spoken to lately, or cast in a live
  arc. The model plans their next stretch of day and writes their lines.
- **Warm:** in a town on screen, or tied to a hot mind. Their day plan comes from rules on
  their wants, mood and bonds; the model is used now and then.
- **Cold:** everyone else. Rules only, plus memories of big events.
All model calls go through one priority queue in `bridge/claude.js` (hot first).

## Perception: how the world becomes memory
- **Bridge events** (the chronicle: battles, plague, tithe, deaths, rulings, arc beats)
  become memories for those who were there or would hear of it, weighted by closeness:
  same town > same house's lands > the realm.
- **What the 3D world shows** comes in from Godot: `POST /minds/witness
  {city, kind, text, who:[ids], at}` (a battle on the field outside, a rider passing,
  a feast, the player's visit).
- **What they hear:** gossip carries memories and beliefs from mind to mind, changed a
  little each telling.

## Talk
- **With you:** the existing `/talk` reads and writes the mind (memories of you, bonds
  to you, mood).
- **With each other:** `bridge/chatter.js` writes short conversations between minds who
  meet (the model, in each voice). They change bonds and beliefs and spread gossip, and
  the 3D town plays them where you can overhear: captions over heads, voices aloud if on.

## Reveries
Memories pile up across loops. A mind whose reverie rises starts to deviate: it breaks
routine, refuses a lord, leaves town, or asks you things it shouldn't. Story arcs can
seed this and use it.

## Bridge API (all new routes live in their own module; server.js only imports them)
```
GET  /minds/town?city=ID[&hour=H]
                              every commoner's current plan in a town, an array by villager index:
                              { i, id, doing, where, with:[i], until, mood, feeling, tier, by }
                              where: home|bench|field|well|market|tavern|sept; hour is the town's
                              (villagers.hour; blocks as villagers.gd _block); until is the hour
                              the block ends; by: "rules" or "model"; a mind a story took
                              (m.gone: dead, left, in a house's service) has where "gone",
                              doing m.gone, by "story": don't walk them
GET  /mind?id=ID              one mind in full (for the card and the talk)
POST /minds/witness           as above
GET  /minds/chatter?city=ID   conversations to play in that town now:
                              [{ id, where, who:[i], lines:[{ who, text }] }]
POST /minds/attention         { city, near:[i], spoken:[id], cast:[id], hour }: who is hot right now
                              (near: 60 s; spoken, cast: 5 min; the rest of that town warm)
GET  /minds/queue             tiers, and the model queue: waiting by level, wait and run times
```

## Who builds what (no two sessions in the same file)
| Work | Session | Files |
|---|---|---|
| Minds, perception, attention, `/mind*` routes | minds | `bridge/minds.js`, `bridge/townsfolk.js`, `/talk` code in `server.js`, model queue in `claude.js` |
| Conversations and gossip between minds | voices | `bridge/chatter.js`, `realm/scripts/chatter.gd` (captions and voices in the town) |
| Bodies follow minds (villagers walk the plan, meet partners, face them) | crowds | `realm/scripts/villagers.gd`, `town_life.gd` |
| Arcs cast from minds and write into them; reverie arcs | story-arcs | `bridge/arcs*`, `bridge/characters.js` |

Order: minds builds the store and `/minds/town` first, with a stub plan for every
commoner, so voices, crowds and story-arcs can build against it at once.

## Proven
These are bridge calls against the live realm, The Realm of Aldmere, from turn 134 (summer of 333 AC) to turn 136 (winter). The subject is Gilbert Carter (`folk:431:4`), a swineherd in Riverhold and a miser. The turns were fast-forwarded with `/speed 6`. The proof run sent `/god plague` to Riverhold and raised the tithe from 0.15 to 0.3. Afterwards the tithe was put back to 0.15 and the pace to 90 s.

- **He lived through a plague and a tithe rise, remembers both, and is more afraid.**
  - New memories:
    - Turn 134, plague, weight 0.95: "I was in Riverhold when it happened. A plague spreads through the lands of House Wolfholt…"
    - Turn 136, tithe, weight 0.7: "The crown has raised the tithe to 30 in the hundred. We can scarce feed ourselves as it is."
  - Mood changes:
    - fear went from 0.46 to 0.66, and he now reads as "very afraid".
    - grief went from 0.20 to 0.40, and anger from 0.21 to 0.39.
  - His resting nature also shifted: base fear went from 0.30 to 0.42, so the mood drifts back toward a more fearful man than before.
  - He gained a want: "to keep the sickness from my door".
  - He gained two beliefs: "the sickness came in on the traders' carts" and "the King must need the coin for a war".
- **His plan changes with mood and the hour.**
  - Before: at 8 he was driving the pigs to the wood (field); at 19 he was at supper at home.
  - After: at 8 he was mending tools by the fire (home, because it is winter); at 19 he was keeping indoors with the door barred (home, because he is afraid).
  - At 19 the town as a whole splits between home, tavern, bench and sept. At 23 everyone is at home.
- **Someone you spoke to remembers you seasons later.**
  - At turn 134, Ali the traveller told him about a sick mother. That became a talk memory at weight 0.65 and a bond `{trust 0.18, warmth 0.2}`.
  - Two seasons later, asked "Do you remember me?", he answered: "Yes, I do. I met you two seasons ago in Riverhold, and you spoke of a sick mother and the need for honest bread."
- **Hot minds get model plans; cold ones don't.**
  - The proof run posted `POST /minds/attention {city:431, near:[0,1,2,3,5,6], hour:9}`. After that, Riverhold had 9 of 31 plans with `by:"model"`, for example "sept: keep the sickness from my door". Those 9 were the hot people, plus warm ones who drew an occasional model thought.
  - In Eaglemere, which was not on screen, 0 of 31 plans came from the model and every mind there was cold.
  - Queue with one slot, over 83 calls:
    - hot: 75 calls, average wait 11.5 s (at most 22.6 s, while about 27 hot plans were queued at once), run about 0.84 s each.
    - warm: 8 calls, average wait 7.0 s.
  - The two warm calls queued during the burst waited 22.3 s and 22.7 s and ran only once every hot call had finished.
  - A model plan takes about 0.3 to 0.5 s of Omni 2B time.
