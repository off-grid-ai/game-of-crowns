# The angle (2026-11-05, from all research so far)

Built from: brief.md (everything Mac has said), demand.md, fights.md, positioning.md, and three review sweeps (god sims, ruler games, living-character and AI games) across Steam, Google Play, the App Store and press.

## The one thing every audience complains about
**The world feels random, and what you do doesn't stick.**
- **God sims:** "It's a Randomizer, not a simulator!", "basically just a dice roll" (Ages of Conflict); "the kingdom system makes no sense" (WorldBox); "no interaction you can do once it's moving" (Fantasy Map Simulator).
- **Ruler games:** "Luck, rather than skill, is what determines how far you get"; "the swipes feel inconsequential"; the same choices "over. and over." (Reigns, top complaint in every version).
- **AI-character games:** "unnatural, repetitive, lacking depth" (Whispers from the Star, 99 mentions); the model breaks the game or forgets.

## The one thing every audience loves
**Stories with lasting consequences, about people.**
- RimWorld's top praise is its "emergent storytelling" and "memorable colonist personalities".
- CK3's is dynasty and succession drama.
- Fantasy Map Simulator players ask for named leaders, family trees, and story pop-ups so watching feels like "reading an epic saga".
- Game of Thrones fans want politics that is "sordid and personal", with grudges carried across generations. Every free GoT strategy game is pay-to-win.

## The angle
**Game of Thrones politics with Westworld people: every lord remembers what you did and acts on it, so nothing in the realm happens for no reason.**

Short form: **Every lord remembers.**

This is the cure for the shared complaint. Memory makes consequences stick. Lords acting on what they know makes every war traceable to a cause. The chronicle shows the chain reaction. And it's personal, which is what GoT fans want.

## What backs it up
| Pillar | Answers |
|---|---|
| **Every lord remembers and acts on it** (memory, his own plans, reacts to what he hears) | dice-roll worlds, inconsequential choices, repetition |
| **You can trace every chain reaction** (favour with named causes, the chronicle, the adviser) | "makes no sense", hidden logic, "can't tell why" |
| **A reign in minutes, years flying** | Reigns proved people want short ruler sessions; Thronefall and Polytopia show they stay when depth sits behind them |
| **Free, nothing locked, runs offline on your device** | paywalls (WorldBox, Ages of Conflict), pay-to-win (every free GoT game), AI games' server failures and lag |

## How to build the minds so they don't fail like the AI games
The evidence says players accept AI when the game logic stays in code and the model only gives it a voice; they reject it when it breaks the game, forgets, or repeats itself.
- The simulation decides what a lord does (favour, grudges, plans). The model says it, in his voice, from what really happened.
- Memory must never slip: a lord who forgets the thing he swore revenge for undoes the whole promise.
- Short lines over open chat. Expect players to try to break the lords.

## Truth check before posting
- **Shown today:** houses remember why their favour moved; a cold house whispers a better claim and marches on the capital; petitions are voiced by the local model.
- **Built but not on screen yet:** lords already keep memories and act on them (`bridge/characters.js`: a refused hand, unpaid loans, ignored petitions, the King taking sides). What's missing is a lord saying it on screen in his own words. That's the clip that sells the angle. Asked of the main session 2026-11-05; it's with Mac because the pace and chronicle changes touch frozen v1 behaviour.
- **Years flying:** the pace is 90 seconds a season, 6 minutes a year (`bridge/chronicles.js:72`). Needs about 15–20 seconds a season for "a reign in minutes".

## Where each audience is
- **r/SimulationGames, r/4Xgaming:** the angle as is.
- **r/CK3AGOT:** comments only: "sordid, personal politics in a five-minute reign".
- **r/Worldbox, Ages of Conflict and Fantasy Map Simulator discussions:** comments in "games like this" and "got bored" threads.
- **r/LocalLLaMA:** a separate post leading with the on-device minds.
