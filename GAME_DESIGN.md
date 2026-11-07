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
A matter is put to you, from the Hand or a petitioner, one at a time. You answer it, refuse it, or let
it burn down, and the realm answers for you. You see what that changed straight away and in the world,
and it comes back to you later. Repeat until the reign ends and history gives you your name.

## Pillars
1. **Decisions matter because they're scarce.** One matter at a time, each on a fuse (a bar that drains;
   three watched seasons). Answered, it rests a year. A house gets one royal favour a year. Gold can't buy
   everyone, and no answer is free.
2. **Silence is a choice, with a price.** When a fuse runs out, the realm decides: the house it touches
   takes it as an answer, and the chronicle says "The King said nothing…". Ignored matters build into
   rebellions and riots.
3. **Every decision is seen.** What moved, and why, shows where it lives: the favour counts to its new
   value and glows (gold up, red down), and one line gives cause and effect. Then the world shows it:
   banners rise and fall, funded buildings appear, carts and feasts arrive. The camera goes there only for
   the biggest moments, never while the King is using a card.
4. **A reign has a shape.** Timed reigns only: 15, 30, 45 or 60 minutes. A story comes for the throne
   in acts, landing at the quarters. Each act ends on an interlude that traces two or three of your choices
   to what they caused. A running verdict ("If your reign ended today: the Meddler") shifts as you rule,
   and the ending names you.
5. **The realm lives without you, but never behind your back.** Houses farm, marry, scheme and march on
   their own. The world only pauses for a decision that matters, and only until you decide. Only seasons
   you watch burn a fuse.
6. **Nothing competes for your attention.** One card from the game at a time; others queue. Nothing
   appears, swaps or moves under your mouse. Feedback is a glow, a count and one line, never another panel.

## Feedback ladder
- **This second:** the fuse bar drains; your decree's result card.
- **Within seconds:** the favour counts and glows; the cause-and-effect line; the result plays in the world.
- **Within the act:** lords bring it up at court, with the season and the year.
- **End of the act:** the interlude, choices traced to outcomes, the name you're earning.
- **End of the reign:** the ending screen, your name in history, the reign in numbers.

## How we decide
- Judge as a demanding player: does this make the next ten minutes more gripping? If not, cut it.
- Check what proven games do (Reigns, Frostpunk, Crusader Kings 3, King of Dragon Pass) and borrow
  mechanics players already understand, in our world and our words.
- The model (an optional local one) enhances what the player says and reads. The game must play fully
  without it, and it is never the pitch.
- Changes are built in batches and tested together: one run, filmed, every change judged on film, fixed, run again. Nothing risks what works.

## We don't
- A year-in-review screen, a new dashboard, or any panel that competes with the world.
- Debug pickers, animation lists or anything that makes the player do the game's job.
- Selling the mechanism ("lords remember", "the world runs itself", "AI NPCs"). Sell what the player gets.
- Endless reigns with no shape.
