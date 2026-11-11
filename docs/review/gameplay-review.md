# Gameplay review: one reign, played headless

A demanding player's read of the loop (decisions, then the realm reacts), 2026-11-12.

**How it was played.** A private bridge (8788, Freeciv 5557, its own GOC_HOME in a scratchpad; never the
main 8787). A fresh 15-minute reign, "The Long Winter", Aldmere, default options, driven only through the
bridge's HTTP calls: /court, /decree, /court/answer, /court/close, /host/order, /tithe, /world, /chronicle.
I played the first 3.5 minutes of reign clock by hand (seasons 38 to 46; about 20 minutes of wall time,
because the clock stops while the court sits). Then a script answered each court card with the cheapest
answer it could pay for. A second test reign, "check reign shape", used the test clock to read each act's
interlude and the ending. No Godot, no renders.

**Caveat.** The title screen sends `opening: "v2"` (realm/scripts/title.gd:1368). My first reign was made
through the API without it, so it had no quiet until the first winter. That winter came two seasons in
(Summer 309 to Winter 309), so v2 would have bought about 80 seconds. Every other finding holds either way.

**The short verdict.** The bones are right: one court card at a time, a cost on every answer, ultimatums
before a rising, and a clock. But the numbers and the wiring break the promise. The end-game threat lands in
minute two. One cheap answer beats the rest, and then it doesn't do what it says. Seals leak. The Hand
reads out wrong numbers. And what the King decides mostly shows up as text, because the world-side
features are switched off.

---

## The top 10, by how much they hurt the player

### 1. The throne is under siege by minute two, and the King can't answer it
**What happens now.**
- The reign opens with three of six houses at the brink. First /world: Goldcrest 26, Stormhold 23,
  Highfell 25 (the rising line is 25, data/favour.json). The "wary" trust option should rest houses
  near 55 plus each house's lean (bridge/favourbook.js:178-181), but the reign starts from the baseline
  save's table.
- My first answer was the Hand's own pick: a feast for Thornvale. It cooled Goldcrest and Stormhold by 6
  each. One season later Stormhold sent an ultimatum and "whispers of a better claim". Turn 42, at about
  1:50 on the clock: "House Stormhold lays siege to Kingsmere with 8 companies."
- The crisis card offered two answers: the levy (20,000 crowns) and a buy-off (30,000). The treasury
  held 10,400. The bridge refused: `"the treasury holds 10,400 crowns; this costs 20,000"`. Closing the
  court cost me again: "The King said nothing while house stormhold's host marches on kingsmere. The
  loyal houses wonder whether the crown will act at all."
- Money: 50,000 crowns at the crowning, 2,400 after four seasons of ordinary answers.
- This breaks pillar 4 ("The last act names its threat at the three-quarter mark") and the fun bar's
  "Failure feels fair".

**What the reference does.** Frostpunk saves the Great Storm for the end. It's foreshadowed for days,
and the early days are for building. In CK3 a new ruler starts with vassals mostly content, and every
opinion modifier is listed. Total War warns of rebellion with a public-order countdown, turns ahead.

**The fix (one session).**
- No great house starts under 35. New tunable `startFloor: 35` in data/favour.json, applied when a
  chronicle is made.
- No usurper rumour before act 2. New tunable `usurperFromAct: 2` in data/opening.json, read by
  stakes.js:113.
- Every crisis card carries at least one answer the purse can pay. When nothing is affordable, offer
  a free answer with a favour cost: "Promise Stormhold a seat at council: Stormhold +10, Thornvale −8".
  That goes in counsel.js where the march card is built (line 66).
- Add a TUNING.md line for each.

### 2. The ward is a free win, and then it lies
**What happens now.**
- A ward costs 20 gold (2,000 crowns) and −5 favour. It stops the house rising for 20 seasons
  (bridge/data/decrees.json; crown.js:214-220; routes_decree.js:88). A 15-minute reign is about 22
  seasons, so one ward covers nearly the whole reign.
- In one sitting I warded Stormhold, Goldcrest, Highfell and Sunspire for 11,000 crowns in total.
- I warded Goldcrest a second time, and a third. The bridge took the money each time.
- The ultimatum card marks the ward as the pick: "Take their heir as your ward (they cannot rise for five
  years)". But its −5 leaves a house under 25. court.js:399 then marks the ultimatum `refused`.
- season.js:111-120 raises a refused house's banners without checking `warded`. Stakes: Stormhold
  warded until turn 59, yet `march: 8, riseAt: 45`. Chronicle, turn 45: "House Goldcrest's banners
  gather at Goldrock… in 2 seasons their host marches on Kingsmere", two seasons after "While the
  child lives at court, the house will not rise." Turn 46: Goldcrest besieges Stonefell.
- So the ward is dominant on price and false on its promise. Both kill trust.

**What the reference does.** In CK3 a hostage or ward is a real relationship. It costs a diplomatic
action, and the other side's opinion of it is shown. Reigns: every swipe costs one of four meters, and
the card says nothing that the game won't honour.

**The fix (one session).**
- Ward: cost 150, favour −15, once per house per reign, refused if already held (data/decrees.json,
  crown.js:214).
- season.js:111 skips a warded house.
- counsel.js stops marking the ward as the pick on an ultimatum.
- Give it a ledger axis (data/ledger.json `ward: {mercy: -1, says: "the heir taken hostage"}`), so the
  King's name remembers it.

### 3. Scarcity leaks: decrees at a sitting are free of the seal, and host orders and the tithe are free
**What happens now.**
- GAME_DESIGN pillar 1: "one court a season… and a few royal acts".
- seals.js:29 and :35 skip the seal for any decree while `meta.court.sitting != null`, not only for
  the ruling. In one sitting I gave five decrees, four wards and a levy, with `"sealed": false` on every
  one and the seals still showing 1 of 2.
- /host/order takes no seal and no gold. I sent three hosts in one second.
- /tithe is a free slider. I set it from 0 to 40% in two calls. The treasury went from 104 to 504 in
  two seasons.

**What the reference does.** Frostpunk: one law, then a cooldown. King of Dragon Pass, where seals
came from: two actions a season, whatever the screen. Total War: one move per army per turn.

**The fix (one session).**
- seals.js: only the decree that carries `matter` is free. Any other decree at a sitting takes a seal.
- data/hosts.json `ordersPerSeason: 1`.
- data/economy.json `tithe.changeEvery: 4` (once a year). The /tithe call refuses inside the window,
  and the top bar says "again in N seasons".

### 4. The Hand reads out wrong numbers, and his pick can make things worse
**What happens now.**
- The first card of a new reign: "House Thornvale grows cold to the crown: favour 6". The houses table
  said 60 for Thornvale, and so did favour.json.
- The likely cause: server.js:447-449 builds the counsel before `applyStartOptions()` and
  `applyOpeningMood()` run, and switchTo never rebuilds it. Proof: when I opened the second reign, its
  first reading still listed the first reign's "House Stormhold's host marches on Kingsmere".
- "House Thornvale grows too strong" opens with "undefined towns, more than any other house".
  counsel.js:180-184 reads `p.cities.length`, but /world players carry `cities` as a number. So the
  card fires every reign, for whichever house has the most units.
- I trusted the card and feasted Thornvale (60 to 75). That cooled two houses that were already cold,
  and it led straight to problem 1.

**What the reference does.** CK3's alerts are built from live state. They show only what you can act
on, and the tooltip lists every number behind it.

**The fix (one session).**
- server.js: build the counsel after the start options are applied, and set `counselStale = true` in
  switchTo.
- counsel.js:180: use the count of towns, not `.length`.
- Add a guard that drops any card text containing "undefined" or "NaN".

### 5. Cards vanish: the court sits and shuts without the King
**What happens now.**
- Turn 40, chronicle: "The court sits for the winter of 309: 1 matter waits for the King". The doors
  closed in the same season, before I answered anything. My 4-second poll never saw a card in /court.
- Turn 42: "Stormhold grows cold" was called to court, then dropped from the docket when the counsel
  turned it into "Stormhold's host marches".
- court.js:194 deletes any called matter whose key is no longer in `counselNow`, and closeIfDone then
  shuts the court. A matter's key is its text plus a turn, so a rise in urgency changes the key.
- The fun bar: "One thing at a time: moments of 'where did my card go?' None."

**What the reference does.** In Reigns the card stays until you swipe it. Frostpunk's promises stay on
screen until they are kept or broken.

**The fix (one session).**
- A called matter keeps its card until the King answers it or closes the court (court.js:194).
- Key matters by house and kind ("ultimatum:4"), not by text. A worse version replaces the card in
  place, with a short glow.

### 6. What the King decides barely shows in the world: those features are off by default
**What happens now.**
- realm/data/decisions.json has `"on": false`. That file holds the unrest crowds, the feast lanterns,
  the levy table and the garrison standard: GAME_DESIGN's "Within seconds… the result plays in the
  world".
- realm/data/host_command.json has `"on": false`. That is commanding the host, the Warcraft III ask.
- siege.json and fire.json are `"on": false` too.
- In a default reign, the feast, the levy, four wards and the walls come back as card text and a
  chronicle line. The one world mark I saw was the feast scene (`scenes: [{kind: "feast"…}]`).

**What the reference does.** Warcraft III: every order puts a marker on the ground and the unit moves at
once. Stronghold: the popularity reasons walk the streets as people. Anno 1800: what you fund rises where
you're looking.

**The fix (one session, plus the bundled gate).** Put decisions and host_command into the next bundled
render. Each switch either passes beside 07-unrest and 08-reinforce and goes on by default, or the
promise it carries comes out of the docs. Nothing new to build.

### 7. The royal host walks there and stands; it can't take anything
**What happens now.**
- `/host/order march` to Stormwatch: "19 seasons on the road". The order speed is 3 tiles a season
  (data/hosts.json), and a 15-minute reign has about 22 seasons.
- hosts.js:84-92: a march ends with the host standing outside the town. No battle, no siege, no capture.
  Fighting is a separate 25,000-crown "march" decree. So one verb, "march", is two systems.
- The ladder aim "Muster a royal host of 2,400 men" only counts men at Kingsmere. It went backward
  (1,600 to 1,200) when I sent men out.
- VISION's loop B ("taking a town turns it to the Crown") doesn't happen through the host.

**What the reference does.** In a Total War campaign, one turn's move covers a readable distance, and
moving onto an enemy army or town is the attack. In Warcraft III, attack-move is one order.

**The fix (one session).**
- One march: a host that reaches a town of a house at war with the crown, or one the King names as the
  enemy, lays siege through the decree march's existing path (crown.js `march`). Remove the separate
  decree.
- data/hosts.json `speed: 8`. That would cross the realm in about 6 seasons, roughly 4 minutes
  (estimate, from the 19 seasons at speed 3).
- The ladder aim counts the crown's men wherever they stand.

### 8. Goals don't pull, and the ending doesn't judge the King
**What happens now.**
- The three ambitions I was dealt:
  - "Twenty decrees" counts every chronicle line of kind `decree` (reign.js:106). That includes "The
    royal host has reached Goldrock", "The whispers fade" and "The realm as the King found it". I
    had 15 by season 41. This rewards spam.
  - "Fill the treasury to 200,000 crowns" means 2,000 gold, at about 95 a season (data/economy.json).
    That is about 25 idle seasons against a reign of 22 (estimate). You can't spend and still meet it.
  - "Win four houses to loyal" is the only real one.
- The last act names "the houses' own ambitions" (reign.js:90): no face and no date.
- The test reign ran its clock out with no orders and ended: "A steady hand. The realm endured and grew.
  He gave the realm no orders at all." Score 2,020. The verdict comes from average peace and population
  (reign.js:401), not from the King's deeds. A caveat: the test clock skips seasons, so idleness had no
  time to cost anything.
- Mid-reign, after six wards on four houses and a 40% tithe, the name showed "the Steadfast: He ruled without great
  wrongs or great deeds".

**What the reference does.** Frostpunk ends on a judgement of your laws ("Was it worth it?"). CK3's
legacy and lifestyle goals come from your situation. Total War names the victory and the enemy, with a
turn count.

**The fix (one session).**
- reign.js AMBITIONS: drop `decrees` and `treasury`. Draw three from the realm's own state at the
  crowning: "End the war between Goldcrest and Thornvale", "Keep Kingsmere unbesieged", "Wed two great
  houses".
- The last act always names a house and a season. With no pretender, the coldest house gets the march.
- The ending's line comes from the ledger's name (ledger.js epithetOf), with the peace numbers as
  support, never the other way round.

### 9. The chronicle is a firehose, and it contradicts itself
**What happens now.**
- 9 to 15 chronicle lines a season (turns 38 to 44: 6, 15, 13, 10, 3, 10, 9). That's about one every
  4 seconds. Most are other houses' business: maesters charting stars, towns founded, hawking parties,
  a barefoot anchoress.
- It opens with 37 seasons from before the crowning, including "Yolande Thornvale raises the banners of
  House Thornvale against the crown!"
- It contradicts itself. "House Stormhold's banners gather… in 2 seasons their host marches"
  appears on turns 43 and 46, while that host had been at Kingsmere's walls since turn 42.
- The fun bar: "≥60% quiet", "I can read the board".

**What the reference does.** CK3 and Total War filter the feed to your realm by default, and the rest is
opt-in. Anno 1800 ranks notifications and hides the low ones.

**The fix (one session).**
- New realm/data/ticker.json: the kinds the ticker shows (decree, court, unrest about the crown, battles
  at crown or sworn towns, rebellion, reign_end). Everything else stays in the chronicle drawer only.
- The view starts the ticker at `meta.ambitionsFrom.turn`.
- season.js:111 skips a house whose host already marches (stakes `usurper.house`).

### 10. People don't hold together, so nobody is worth caring about
**What happens now.**
- One house's head has three names. /world: "Lady Isolde Thornvale". The court card: "Yolande
  Thornvale". The first counsel: "Ysolde Thornvale".
- House Ironreach is listed in `fallen` from the first second. Yet "Ysolde Ironreach of House Ironreach
  comes to court", pays raiders, smuggles gold to Redsands and takes the town (turns 36 to 43).
- Every ultimatum opens "The crown has done nothing for Stormhold since you were crowned" (counsel.js:91),
  in minute one, and the same season the King feasted the house next door.
- Lowercase house names in the King's own record: "house stormhold's host marches on kingsmere"
  (counsel.js:311, `.toLowerCase()` on the whole line).
- The fun bar: "People I care about: name three lords and what each wants".

**What the reference does.** In CK3 each person has one name, one portrait and one place in every list.
A dead or landless house leaves the play.

**The fix (one session).**
- Every speaker line is resolved through `court.lordOfHouse` (counsel.js:85 already does; the ultimatum
  and /world name don't).
- Arcs and the court skip characters of houses in `fallen`.
- The ultimatum's grievance falls back to "You have done nothing for us in N seasons", using the
  turns since the crowning.
- Drop `.toLowerCase()` and keep the matter's own casing.

---

## Cut list (noise to remove)
- **Gift crowns.** The feast is cheaper (10,000 against 15,000) and warms more (+15 against +10).
  From the card, the gift is strictly worse.
- **Three peace verbs** (peace, settle, back): keep one, "Make them stop", with a price that scales by
  how cold the houses are.
- **The "march" decree beside the host's march order**: one verb (problem 7).
- **Sellswords beside the levy**: same job, same screen. Keep the levy.
- **"Twenty decrees" and "200,000 crowns" ambitions** (problem 8).
- **The Hand's "grows too strong" card**: it fires every reign on a bug, and the ward it offers is the
  exploit in problem 2.
- **The Marshal's second line in the "next" strip** ("The Hand: … · The Marshal: …"): two advisers
  competing for one glance. Keep one prompt.
- **Off-realm chronicle lines in the ticker** (techs, founded towns, other houses' hawking and
  preaching): drawer only.
- **The pre-crowning chronicle** in the reign's view.
- **The ward as a town-card decree.** Keep it only as a court answer, once per house per reign.

## What's right, and worth keeping
- The first card came 30 seconds after landing, with a face and a want ("settle the old grudge").
- Every answer is weighed before you choose (`weighs: helps/hurts`). That's the feedback ladder's first
  rung, done.
- Prices rise as you repeat yourself (the feast went 100, then 125). The ledger names a heavy tithe.
- The clock stops while the court sits. Ultimatums do come before a rising.

## Numbers from this play (for the before and after)
- Wall time per minute of reign clock: about 5 to 6, hand-played (court sitting in 59% of 4-second
  samples; that includes my thinking time, so it's an estimate).
- Orders given in the first four seasons: 11 decrees and 3 host orders, with 2 seals spent.
- Chronicle lines a season: 9.4 on average (turns 38 to 44).
- From the first ruling to a siege at the King's seat: 4 seasons.
