# Game of Crowns: game design

How the game should play and feel. Lean on purpose: what a decision has to pass before it ships.
The vision is [VISION.md](VISION.md), the world and its systems are in [DESIGN.md](DESIGN.md), and the
screen rules are in [UI.md](UI.md). When this file and an idea disagree, change one of them out loud;
never quietly break it.

## The promise
**Find out what kind of king you'd be.** Seven great houses want your throne. You hold it with grain,
gold, marriages and your word at court, and when the reign ends history names you for how you ruled
(the Golden, the Bloody, the Meddler, the Deposed). Every feature serves that promise or it goes.

## The core loop
Once a season (40 seconds) the court sits and the world holds still. Petitioners bring their matters, one
at a time; the Hand speaks a line of counsel on each. You answer, refuse, or close the court and let your
silence answer. Then the doors shut and the realm moves: the camera shows you what you changed and
what the houses do without you. It comes back to you in later seasons. Repeat until the reign ends and
history gives you your name.

## Pillars
1. **Decisions matter because they're scarce.** One court a season: one matter early in the reign, rising
   to three at the climax, and a few royal acts. About one decision a minute, never a stream. Answered, a
   matter rests a year; none repeats within a reign. A house gets one royal favour a year. Gold can't buy
   everyone, and every answer costs favour, crowns or grain somewhere.
2. **Silence is a choice, with a price.** Matters left when you close the court settle themselves: the
   house it touches takes it as an answer, and the chronicle says "The King said nothing…". Ignored matters
   build into rebellions and riots, but a house always gives an ultimatum two seasons before it rises.
3. **Every decision is seen.** Before you choose, each answer marks the houses it helps and hurts. After,
   the change glows on the card, one line gives cause and effect, and when the court closes the camera goes
   to the biggest result: banners rise and fall, funded buildings appear, carts and feasts arrive.
4. **A reign has a shape.** Timed reigns only: 15, 30 or 60 minutes. Four acts, one per quarter of the
   clock, each ending on an interlude that traces two or three of your choices to what they caused. The
   King takes three ambitions at the start. The last act names its threat at the three-quarter mark and
   you watch it come. The name you're earning shows live, with the one close behind it, and the ending
   flies over the realm to the places your choices changed before history names you. No single random
   event ends a reign.
5. **The realm lives without you, but never behind your back.** Houses farm, marry, scheme and march on
   their own. The world pauses only while the court sits. Between courts the camera tours whatever matters
   most, and the land shows who holds it: each house's colour over its territory, at every zoom.
6. **Nothing competes for your attention.** One card at a time. The card you opened stays until you close
   it. The Hand never queues his own card; he speaks on the petitioner's, and pushes in only for a real
   crisis, at most once a year. Feedback is a glow, a count and one line, never another panel.

## The fun bar
Every feature, story, beat and change is scored against these thirteen lines before it ships, and after.
They come from the research in the fun brief (https://claude.ai/artifact/5T4M33vrEY2KABfzs3ypQZ):
design frameworks, twelve reference games, player reviews, and counts from real reigns. Each line
names the test that decides it. A change that lowers any line is a regression.

| Line | The test, in a 15-minute reign | Target |
|---|---|---|
| Room to breathe | Decisions per minute; share of time with no prompt up | ≤1 a minute; ≥60% quiet |
| One thing at a time | Moments of "where did my card go?" or "which card now?" | None |
| Worth watching | Quiet stretches where something on the board makes you lean in | Every season |
| The reign has a shape | Can you say at minute 10 what is coming, and roughly when? | Yes |
| It says who I am | Is the name you're earning on screen while you rule? | Always |
| People I care about | Name three lords and what each wants, unprompted | Yes; no two share a name |
| I can read the board | At minute 8, which house is rising and where? | Answered at a glance, and right |
| Every answer costs | Matters where you hesitate over 3 s | Most of them; no free option |
| Failure feels fair | After a setback, can you say why and what you'd change? | Yes; an ultimatum always came first |
| A story I'd retell | Afterwards, tell one story with a named lord in it | Yes, unprompted |
| I see what I did, fast | Time from your answer to a change where you're looking | Under 2 s, then in the world |
| My choices come back | Later matters that name an earlier ruling and ask differently because of it | Several a reign |
| Fresh every reign | Repeated matters or names within a reign; new things on the third reign | None; yes |
| I'm building something | Can the player point at the map and say "I made that, and I don't want to lose it"? | Yes, by minute 10 |
| Something of mine is pending | At any pause, how many things the player started are still unresolved? | At least two, one of them near |
| I learned a rule | At minute 10, one rule of the realm they didn't know at minute 2, and used | Yes |

Stories and beats pass it too, the player's own included: every beat names a person and what they want,
lands in an act, costs something whichever way it goes, can remember an earlier ruling, and never ends the
reign on its own. The beat form guides the author to all of that.

**Measure, don't guess.** Count from the chronicle of a real reign before and after a change (decisions
per minute, quiet share, repeats, time to feedback). Tag any figure that is an estimate. Borrow from what
players of these games reward and punish, by frequency, not from one review.

## The engagement model
The fun bar keeps the player from being overwhelmed; this keeps them wanting to go on. Quiet time with
nothing of theirs at stake is dead air, not breathing room. From Koster, Hopson, Csikszentmihalyi and
Schell, Meier, self-determination theory, Swink, Costikyan and the IKEA effect:

1. **Fun is a pattern still being learned.** The realm has a few consistent rules the player can read and use.
2. **Nested loops, each closing with something felt.** At any moment the player can say what they're doing and what they're waiting for.
3. **Tension in waves.** It rises, releases and peaks; never flat.
4. **Interesting decisions.** No option is always right; the situation changes the answer.
5. **Competence, autonomy, relatedness.** He gets better, chooses what to do (not only how to answer), and cares about someone.
6. **Every input answered within a fifth of a second:** sound, motion, a change in the world.
7. **Uncertainty with stakes.** Something of his rides on an outcome he can partly read.
8. **Ownership.** What he built, he values; give him a place on the map that is his.
9. **Open loops.** Things he started and wants to see finish pull him to the next minute.
10. **The player is the hero.** The best moments happen because of him and are told that way.

What the best designers add (docs/review/designer-top10.md, Mac 2026-11-10: "fix these as well"):

11. **Repetition kills.** A reign has 15 to 60 decisions; each one comes from the realm's state, never a pool,
    and no situation returns within a reign.
12. **The middle and late game change.** Each act asks new questions, not bigger numbers.
13. **Tension rises and falls, and the ending gets the most care.** Quiet after a crisis; the peak and the end
    are what players remember.
14. **People remember what you did, not a number.** A house holds a grudge, or a debt, for a named act ("the
    broken oath at Kingsmere"), says so, and acts on it.
15. **Change big, test with real players, cut.** Take the problem from players, never their fix.

Never: passive watching sold as a living world; choices with a fixed best answer or no visible result;
dark-pattern loops (streaks, login rewards, nags). A reign has a clock and a real ending.

## Feedback ladder
- **This second:** the answer marks who it helps and hurts; your ruling's result glows on the card.
- **Within seconds:** the favour counts and glows; the cause-and-effect line; the result plays in the world.
- **Within the act:** lords bring it up at court, with the season and the year.
- **End of the act:** the interlude, choices traced to outcomes, the name you're earning.
- **End of the reign:** the ending screen, your name in history, the reign in numbers.

## How we decide
- **Our track (VISION.md, 2026-11-11):** we win on play, not on pixels. One kind of game, done really well:
  a short reign ruled from above. Graphics need to read clearly from roof height and above, nothing more.
- Judge as a demanding player: does this make the next ten minutes more gripping? If not, cut it.
- Score it against the fun bar above, with numbers from a real reign where they exist.
- Check what proven games do (Reigns, Frostpunk, Crusader Kings 3, King of Dragon Pass, Old World,
  Manor Lords, RimWorld) and borrow mechanics players already understand, in our world and our words.
- The model (an optional local one) enhances what the player says and reads. The game must play fully
  without it, and it is never the pitch.
- Variety and reaction make it real: every move we have gets used, nothing repeats on a loop, and every action
  draws a fitting reaction (a blow is parried, dodged or taken; a crowd answers its king). Repetition is a bug.
- Changes are built in batches and tested together: one run, filmed, every change judged on film, fixed, run again. Nothing risks what works.

## We don't
- A year-in-review screen, a new dashboard, or any panel that competes with the world.
- Debug pickers, animation lists or anything that makes the player do the game's job.
- Selling the mechanism ("lords remember", "the world runs itself", "AI NPCs"). Sell what the player gets.
- Endless reigns with no shape.
