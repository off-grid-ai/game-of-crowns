# Game of Crowns: game design

How the game plays and feels: what every change has to pass. Decisions and scope live in
[VISION.md](VISION.md), the screen rules in [UI.md](UI.md), the world and the art in [DESIGN.md](DESIGN.md).
When an idea disagrees with this file, change one of them out loud; never quietly break it.

## The promise
**Find out what kind of king you'd be.** You are a war king from the first minute. Seven great houses
want your throne. You hold it with your army, your crowns and your word, and when the reign ends history
names you for how you ruled (the Golden, the Bloody, the Oathbreaker, the Deposed). Every feature serves
that promise or it goes.

## The game (Mac 2026-11-17: "this is the actual game now")
**Win every house's loyalty through alliances, war and campaigns.** A new king inherits a realm with no
friends: the great houses are neutral or against him, at least one is against him from the start, and
raiders and barbarians roam. War is the crux: hosts and bannermen marching out of the castle, campaigns
across the map, battles fought in formation on the field. Politics and famine run alongside, so there is
always something to do, but they serve the war, never replace it. The camera travels for war (a march,
a siege, a battle), never for a granary or a gift. Every story, event and matter is wired to this goal:
it wins a house over, turns one against him, or puts a host on the road.
After a victory he chooses: give the land to a minor house as its warden (a new loyal house), or show mercy
to the beaten one. Mercy can win them over, or make them think him weak and come back at him; his strength
decides which. That is how every house ends up loyal.

## The first ten minutes
- **0:00** Your royal host stands at Kingsmere, in your colours. One objective is on screen
  ("Raiders burn Ashford. Drive them off.").
- **0:30** Click the host, right-click Ashford. The men march. You win your first fight by minute two.
- **2–4** Crowns come in. You buy archers or a wall; either is affordable.
- **4–6** A lord brings a matter. You open his card when you choose, answer, and the realm keeps moving.
- **6–10** A rival besieges your ally. Relieve it or let it fall, and see what each costs.
- **By 10** You can point at the map and say "I took that, and I don't want to lose it".

## The core loop
See a threat, give an order, watch it play out, see the realm change, get paid, spend, meet the next
threat. Something to act on comes at least every 45 seconds: raiders, a lord's demand, a siege, a
starving town. Win the seven houses by sword or by oath, and history gives you your name.

## Pillars
1. **You always know what to do.** One objective is always on screen, with a reward you can see; each
   one leads to the next (Warcraft III's quest line, Thronefall's night).
2. **You can always do it.** The army is yours from the start. Crowns come every season and buy men,
   walls and favour; every first choice is one you can pay for.
3. **Command like a real-time strategy game.** Click to select, right-click to march, attack, besiege
   or relieve (Warcraft III, Total War). Every order is answered at once: a horn, a salute, men moving.
4. **Battles weigh something.** Dense formed armies in house colours, morale that breaks, walls that
   crack into a breach. What happened on the march shows on the field.
5. **The houses answer you.** Allies march with you, wronged lords rise. A house remembers a named act
   ("the broken oath at Kingsmere"), says so and acts on it, and always gives an ultimatum two seasons
   before it rises. No single random event ends a reign.
6. **The court is a side layer.** Lords bring matters on a card you open when you choose; time never
   stops. A matter has a visible deadline; left alone, it settles itself, the house takes your silence as
   an answer, and the chronicle says "The King said nothing…". Every answer costs favour, crowns or grain
   somewhere, and no matter repeats within a reign.
7. **Every decision is seen.** Before you choose, you see whom it helps and hurts. After, the result
   shows within two seconds where you're looking, then in the world (UI.md 13).
8. **A reign has a shape.** Timed reigns of 15, 30 or 60 minutes, in four acts. The last act names its
   threat at the three-quarter mark and you watch it come. The name you're earning shows live, and the
   ending flies over the places your choices changed before history names you.

## The fun bar
Every feature, beat and change is scored against these lines before it ships, and after. A change that
lowers any line is a regression.

| Line | The test, in a 15-minute reign | Target |
|---|---|---|
| I know what to do | At any moment, can you say your objective and how to start it? | Always |
| I can do it | Time from wanting to act to an order given | Seconds; never blocked by having nothing |
| Never idle | Longest stretch with nothing to act on | Under 45 s |
| My orders work | Time from a click to men answering on screen | Under 0.2 s |
| One thing at a time | Moments of "which card now?" or "where did it go?" | None |
| Battles weigh something | After a fight, can you say why you won or lost? | Yes |
| I can read the board | At minute 8, which house is rising and where? | At a glance, and right |
| Every answer costs | Choices where you hesitate over 3 s | Most; no free option |
| Failure feels fair | After a setback, can you say why and what you'd change? | Yes; a warning always came first |
| It says who I am | The name you're earning is on screen while you play | Always |
| People I care about | Name three lords and what each wants, unprompted | Yes; no two share a name or line |
| My choices come back | Later events that name an earlier act and play differently | Several a reign |
| I'm building something | Can you point at the map and say "I made that"? | Yes, by minute 10 |
| Something of mine is pending | Things you started that are still unresolved | At least two, one near |
| A story I'd retell | Afterwards, one story with a named lord in it | Yes, unprompted |
| Fresh every reign | Repeated matters or names within a reign; new things on the third reign | None; yes |

**Measure, don't guess.** Count from a real reign's chronicle before and after a change. Tag estimates.

## What keeps them playing
1. **A pattern still being learned.** A few consistent rules the player can read and use.
2. **Nested loops.** At any moment the player can say what he's doing and what he's waiting for.
3. **Tension in waves.** It rises, peaks and releases; quiet after a crisis; the ending gets the most care.
4. **Interesting decisions.** No option is always right; the situation changes the answer.
5. **Ownership.** He values what he took and built; give him places on the map that are his.
6. **The player is the hero.** The best moments happen because of him and are told that way.
7. **The middle and late game change.** Each act asks new questions, not bigger numbers.
8. **Variety and reaction.** Every move we have gets used; every action draws a fitting reaction (a blow
   parried or taken, a crowd answering its king). Repetition is a bug.

## Feedback ladder
- **This instant:** the order is acknowledged (sound, motion); a card marks whom an answer helps and hurts.
- **Within seconds:** men move, favour counts, one cause-and-effect line, the result in the world.
- **Within the act:** lords bring it up, with the season and the year.
- **End of the act:** an interlude traces two or three of your acts to what they caused.
- **End of the reign:** your name in history and the reign in numbers.

## How we decide
- **Win on play, not pixels.** Does this make the next ten minutes more gripping? If not, cut it.
- **Copy proven games.** Only the loop is ours. Command and battles follow Warcraft III and Total War;
  sieges Stronghold; the court card Reigns and Crusader Kings 3; pacing Thronefall. The research is the
  casebook ([docs/casebook](docs/casebook/README.md)).
- **Judge as a demanding player**, score against the fun bar, borrow what players reward by frequency.
- **The local model is optional.** It enhances what lords say; the game plays fully without it, and it is
  never the pitch.

## We don't
- Panels that compete with the world, dashboards, or a year-in-review screen.
- Debug pickers, animation lists or anything that makes the player do the game's job.
- Passive watching sold as a living world; choices with a fixed best answer or no visible result.
- Dark patterns (streaks, login rewards, nags) or endless reigns with no shape.
- Selling the mechanism ("lords remember", "AI NPCs"). Sell what the player gets.
