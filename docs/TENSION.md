# Tension: cause, effect, consequence

Mac, 2026-11-16: "we are lacking tension, there are some choices that are just too easy", "I need to think about game
theory and mechanics deeply: cause and effect, consequences". This is the plan every mechanic below is built against.

## The rules a choice must pass

1. **Scarce, shared means.** Every order spends something another order also needs: crowns, the season's seals,
   men, grain, favour, time. A cheap order that blocks nothing is no choice.
2. **Someone loses.** Every order helps one party and costs another (Frostpunk's laws, Reigns' two sides). The card
   names who.
3. **The realm answers.** The houses are players with interests, not scenery. A King who grows by force makes them
   balance against him (Waltz's balancing; EU4's aggressive expansion and coalitions); a King who keeps his word and
   wins makes the weak bandwagon to him (CK3's alliances).
4. **Costs that run on.** A war is not paid once: it drains every season it lasts (Total War's upkeep, CK3's levies).
   Running two at once costs more than twice one.
5. **Seen before it bites.** Every slow consequence has a meter, a clock or a line in the chronicle before it lands
   (UI.md: every decision is seen). No hidden numbers turning into a surprise defeat.
6. **Loops with brakes.** Every snowball (more towns, more crowns, more men) has a brake that grows with it
   (alarm, upkeep, unrest in taken towns).

## Built (2026-11-16)

- **Several wars at once** (`meta.wars`, docs/WAR.md step 1), each its own sides and plan.

- **Promises with a clock.** Three promises, each with its seasons; broken, every great house trusts the King less
  (-8), kept, +5 (`promises_king.json`).
- **A war has three answers that each hurt.** Judge for a side (the loser gives up a town and hates the King), make
  them stop (crowns; the winner robbed resents it), wed them (a bloc of two after) (`counsel.js warChoices`).
- **War upkeep.** Each house at war with the crown costs crowns every season, each more than the last
  (`war.json upkeep`). Two wars outrun the season's income; the treasury empties and the feasts and gifts stop.
- **Wars eat grain.** While the crown is at war every soldier of the crown eats one more food (War Levy), and on a
  second front one more again (Second Front): Freeciv's own food upkeep, so a second war starves towns that one war
  only pinched (`effects.ruleset`, war.js upkeep).
- **Alarm and the league.** Declaring war, marching on a town, judging a town away and taking a town raise the
  realm's alarm; quiet seasons ease it. At 100 the great houses not sworn to the King band together and go to war
  on him (`coalition.json alarm`). The meter stands in the control plane.

- **Gifts make rivals.** An order that warms a great house cools its rival by half as much: the house it is at war
  with, else its nearest neighbour; the order names it first ("Stormhold jealous") (`rivalry.json`).
- **Few orders a season.** Every order takes a royal seal, a chronicle matter's too; one comes each season, kept up to
  three (`seals.json`). Saying no is free.
- **Seen as it lands, and again later.** A card over the control plane shows what a choice moved; four seasons on the
  order comes back judged on the realm then (`reckoning.js`, `aftermath.js`).

## Next, in order

1. **Taken towns resent the crown.** A town won by force is restless for seasons (lower tithe, a chance to rise
   back to its old house) unless the King spends to settle it.
2. **Bandwagoning.** A King who keeps his promises and wins his wars draws the weak houses to swear to him unasked.
