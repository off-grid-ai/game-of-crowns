// The Hand's counsel: the realm's matters, worst first, each with why it
// matters and the orders that answer it (counsel), the lesser occasions he
// raises in turn (plague, unrest, a thin granary, bare walls, a house too
// strong, a loyal one unrewarded, a full treasury, an heir of age), what a
// matter is for resting it (matterKey), and what the King's silence costs
// (lapseOf, lapse). Nothing here reads server.js: the realm's state and the
// bridge's own helpers come in as one context argument, built fresh by
// server.js on each call (server.js keeps wrappers of the same names).

import { houseFor, cityName } from "./narrator.js";
import { DECREES, bannersReady, ECONOMY } from "./crown.js";  // ECONOMY.thin: below it the treasury is thin (data/economy.json)
import { BANDS } from "./favour.js";
import { calendar } from "./stakes.js";
import * as chron from "./chronicles.js";
import { shortOf } from "./treasury.js";
import * as Director from "./director.js";

// The Hand of the King advises: the two or three most pressing matters in the
// realm, worst first, each with why it matters in one line and the decrees that
// answer it, so a new King always knows what to do next and learns by doing it.
export function counsel(ctx, players, cities, threat) {
  const { world, meta, court, stakes, deeds, favourWhy, lastSeason, favourOf, seasonsLeft, priceOf, yearlyKey, FAVOUR } = ctx;
  const out = [];
  const great = players.filter((p) => !p.house.wild && !p.house.crown && p.cities?.length !== 0);
  const seatOf = (pid) => cities.find((c) => c.owner === pid && c.capital) ?? cities.find((c) => c.owner === pid);
  const purse = players.find((p) => p.house.crown)?.gold ?? 0;
  // A ward is had of a house once a reign, and holds it for its seasons (data/decrees.json ward).
  const wardTaken = (pid) => (meta.oncePerHouse?.ward ?? {})[pid] != null || (stakes?.s.wards?.[pid] ?? -1) > (world?.turn ?? 0);
  const wardHurt = String(DECREES.ward.favour ?? -15).replace("-", "−");
  const wardYears = Math.round((DECREES.ward.seasons ?? 12) / 4);
  const wardFor = `they cannot rise for ${wardYears === 1 ? "a year" : `${["", "one", "two", "three", "four", "five", "six"][wardYears] ?? wardYears} years`}`;
  // A war or bond the King has stilled (his peace, or a royal match).
  const stilled = (x, y) => { const a = court?.lordOfHouse(x), b = court?.lordOfHouse(y); return !!(a && b && court.truce(a.id, b.id)); };
  // A house sliding toward rebellion.
  // Cold is below the banners' line (35): a house that would still answer isn't the Hand's worry.
  const cold = great.filter((p) => favourOf(p.id) < BANDS.steady).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
  if (cold && seatOf(cold.id)) {
    const f = favourOf(cold.id);
    // The Hand names what is cooling them most, from the house's ledger of causes.
    const drain = (favourWhy[cold.id] ?? []).filter((r) => r.d < 0).sort((a, b) => a.d - b.d)[0];
    // In words, never a number (the Hand speaks; the professional-feel audit): how deep it cuts.
    const depth = (d) => (d <= -15 ? "and it cuts deep" : d <= -8 ? "and they have not forgotten it" : "though it is a small thing");
    const cause = drain ? ` What cools them most: ${drain.why}, ${depth(drain.d)}.` : "";
    // A royal match binds the cold house to the most loyal one: both warm, and a long truce holds.
    const friend = great.filter((p) => p.id !== cold.id && !stilled(cold.id, p.id)).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const match = friend && matchFor(ctx, cold.id, friend.id) ? [{ label: `Wed them to ${friend.house.name.replace(/^House /, "")}`, action: "marriage", city: seatOf(cold.id).id, to: friend.id }] : [];
    // A taken town is answered by giving it back, if the other house still holds it.
    const took = meta.taken?.[cold.id];
    const back = drain?.why === "a town granted or taken" && took && cities.some((c) => c.id === took.city && c.owner === took.to)
      ? [{ label: `Return ${cityName(took.city)} to them`, action: "grant", city: took.city, to: cold.id }] : [];
    const lighter = drain?.why === "the royal tithe" && meta.tithe > 0 ? [{ label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" }] : [];
    // The two rules, plainly: under 25 the lord may rise any season; two houses
    // under 25 and one of them claims the throne.
    const angryNow = great.filter((p) => favourOf(p.id) < BANDS.cooling).length;
    const rule = f < BANDS.cooling
      ? `Under 25, their lord may raise his banners any season, likelier the colder he grows.${angryNow >= 2 ? "" : " One more house under 25 and a pretender will claim the throne."}`
      : "Under 25, a lord may raise his banners against you; two such houses and one claims the throne.";
    out.push({ urgency: f < BANDS.cooling ? 100 : 70, subject: cold.id, text: `${cold.house.name} grows cold to the crown: favour ${f}`,
      why: rule + cause,
      acts: [...back, ...lighter, { label: "Gift crowns", action: "gift", city: seatOf(cold.id).id }, { label: "A feast in their honour", action: "feast", city: seatOf(cold.id).id }, ...match] });
  }
  // The usurper by name, how long until they march, and how to stop it: the
  // whispers fade once the angry houses (under 25) are won back.
  const pretender = players.find((p) => p.id === threat.pretender);
  const claimant = pretender ? pretender.house.name : "A pretender";
  if (threat.usurper === "rumour") {
    const left = Math.max(1, 8 - (threat.turn - threat.since));
    const angry = great.filter((p) => favourOf(p.id) < BANDS.cooling).map((p) => p.house.name.replace(/^House /, ""));
    out.push({ urgency: 95, subject: pretender?.id ?? null, occur: threat.since, text: `${claimant} whispers of a better claim to the throne`,
      why: `In ${left} season${left === 1 ? "" : "s"} they march on Kingsmere, unless the angry houses are won back above 25: ${angry.join(", ") || "none now"}.`,
      acts: [pretender && seatOf(pretender.id) ? { label: `Gift crowns to ${claimant.replace(/^House /, "")}`, action: "gift", city: seatOf(pretender.id).id } : null, { label: "Buy off their claim", action: "buyoff" }, { label: "Call the banners", action: "banners" }].filter(Boolean) });
  } else if (threat.usurper !== "none") out.push({ urgency: 100, kind: "march", subject: pretender?.id ?? null, occur: threat.since, text: `${claimant}'s host marches on Kingsmere`,
    why: `${(threat.theirs * 200).toLocaleString("en-US")} of their men about the walls against ${(threat.ours * 200).toLocaleString("en-US")} of yours: ${threat.theirs > threat.ours ? "as things stand, the walls would fall" : "for now, the walls would hold"}. If Kingsmere falls, the crown is lost. Loyal houses (favour 35 and up) send men to the banners; the royal levy is yours to pay for. Or buy them off: gold for their claim.`, acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Buy them off", action: "buyoff" }] });
  // After a march: the King decides what becomes of the house that rose.
  const rose = players.find((p) => p.id === threat.ended);
  if (rose) {
    const towns = cities.filter((c) => c.owner === rose.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0));
    const loyal = great.filter((p) => p.id !== rose.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const name = rose.house.name.replace(/^House /, "");
    out.push({ urgency: 90, subject: rose.id, occur: threat.since, text: `The march is over. What of House ${name}?`,
      why: `They rose against the throne and went home (favour ${Math.round(favourOf(rose.id))}). Pardon them with a feast to win them back, hold their heir at court so they cannot rise, or take a town and give it to ${loyal ? loyal.house.name : "a loyal house"} so the realm sees the price of treason; a house driven below 25 may rise again.`,
      acts: [seatOf(rose.id) ? { label: "Pardon them with a feast", action: "feast", city: seatOf(rose.id).id } : null,
        seatOf(rose.id) && !wardTaken(rose.id) ? { label: `Take their heir as your ward (${name} ${wardHurt}; ${wardFor})`, action: "ward", city: seatOf(rose.id).id } : null,
        towns[0] && loyal ? { label: `Give ${towns[0].title ?? "a town"} to ${loyal.house.name.replace(/^House /, "")} (${name} −30, ${loyal.house.name.replace(/^House /, "")} +20)`, action: "grant", city: towns[0].id, to: loyal.id } : null].filter(Boolean) });
  }
  // A house that has turned: its lord's ultimatum, before any banners are raised.
  for (const p of great) {
    const t = meta.turning?.[p.id];
    if (t?.state !== "sent" || !seatOf(p.id)) continue;
    const lord = court?.lordOfHouse(p.id);
    const short = p.house.name.replace(/^House /, "");
    // The grievance is something the King did, by name and season ("You marched the
    // royal host on our walls, in the autumn of 309"); without one, the plain truth.
    const worst = (deeds[p.id] ?? []).filter((x) => x.d <= -8).sort((a, b) => a.d - b.d)[0];
    const when = worst ? calendar(worst.turn) : null;
    const grievance = worst ? `You ${worst.what}, in the ${when.season} of ${when.year}. Set that right` : `The crown has done nothing for ${short} since you were crowned. Set that right`;
    out.push({ urgency: 100, kind: "ultimatum", subject: p.id, occur: t.at, text: `${p.house.name} sends the crown an ultimatum`,
      why: `${lord ? lord.name : `The lord of ${short}`}: "${grievance}, or ${short} raises its banners." Answer with a favour they can see; silence is a refusal.`,
      acts: [{ label: "A feast in their honour", action: "feast", city: seatOf(p.id).id }, { label: "Gift crowns", action: "gift", city: seatOf(p.id).id },
        !wardTaken(p.id) ? { label: `Take their heir as your ward (${short} ${wardHurt}; ${wardFor})`, action: "ward", city: seatOf(p.id).id } : null].filter(Boolean) });
    for (let i = out.length - 2; i >= 0; i--) if (out[i].text.startsWith(`${p.house.name} grows cold`)) out.splice(i, 1);
  }
  // The pretender's own coldness is the usurper's story: one matter, not two.
  for (const who of [threat.usurper !== "none" ? pretender : null, rose].filter(Boolean)) {
    const i = out.findIndex((o) => o.text.startsWith(`${who.house.name} grows cold`));
    if (i >= 0) out.splice(i, 1);
  }
  // (Lowering the tithe sits on the cold house's matter when the tithe is its top cause.)
  // What the banners would bring today: two companies from the loyal (60+), one from the willing (35+).
  const bannerMen = !bannersReady(world?.turn ?? 0) ? 0 : great.reduce((n, p) => { const f = favourOf(p.id); const sh = f >= BANDS.loyal ? 0.25 : f >= BANDS.steady ? 0.125 : 0; return n + (sh ? Math.max(1, Math.round((p.units ?? 0) * sh)) : 0); }, 0) * 200;
  if (threat.north > 0) {
    const d = threat.dead ?? {};
    const gap = (d.next ?? 0) - threat.ours * 200 - bannerMen;
    const lord = players.find((p) => p.id === d.owner);
    const where = d.town ? `on ${d.town}${lord ? ` (${lord.house.crown ? "the crown's own" : lord.house.name})` : ""}` : "on the North";
    const when = d.in == null ? "" : d.in <= 1 ? " The next host comes next season." : ` The next host comes in ${d.in} seasons.`;
    // Once the King's own men outnumber the host, the Hand says so and advises
    // nothing more; if only the banners are needed, he advises only the banners.
    if ((d.next ?? 0) - threat.ours * 200 <= 0) d.hold = true;
    const onlyBanners = !d.hold && gap <= 0;
    out.push({ urgency: d.hold ? 40 : 75, occur: (world?.turn ?? 0) + (d.in ?? 0), text: d.hold ? "The dead come south, and you would hold" : "The dead come south",
      why: `${(d.last ?? 0).toLocaleString("en-US")} of them fell ${where} last time; ${(d.next ?? 0).toLocaleString("en-US")} will come with the next.${when} Against them: your ${(threat.ours * 200).toLocaleString("en-US")} fighting men${bannerMen ? `, and about ${bannerMen.toLocaleString("en-US")} more if you call the banners` : " (the banners are already called this year)"}: ${d.hold ? "your own men would hold" : gap <= 0 ? "with the banners, you would hold" : gap <= 1600 ? `you would lose by ${gap.toLocaleString("en-US")}: a levy (600) and sellswords (1,000) close it` : `you would lose by ${gap.toLocaleString("en-US")}, even with a levy and sellswords`}. If every northern town falls, the realm falls with it.`,
      acts: [{ label: "Call the banners", action: "banners" }, { label: "Raise the royal levy", action: "levy" }, { label: "Hire sellswords", action: "sellswords" }].filter((a) => !d.hold && (!onlyBanners || a.action === "banners")) });
  }
  // A town the King has fed this year isn't brought to him again while the grain lasts.
  const hungry = cities.find((c) => c.famine && !((meta.relieved?.[c.id] ?? -99) > (world?.turn ?? 0) - 4));
  if (hungry) out.push({ urgency: 80, occur: calendar(world?.turn ?? 0).year, text: `${hungry.title} is starving`, why: "A hungry town shrinks, riots, and blames its King.", acts: [{ label: "Send grain", action: "relief", city: hungry.id }] });
  // (Petitioners are the court's own: the Hand's matters stand beside them there.)
  // A war the King has stilled (his peace, or a royal match) is no longer the
  // Hand's worry, though the engine still counts the two houses at war.
  const war = great.find((p) => (p.atWarWith ?? []).some((o) => great.some((g) => g.id === o) && !stilled(p.id, o)));
  if (war) {
    const foe = great.find((g) => war.atWarWith.includes(g.id) && !stilled(war.id, g.id));
    // The Hand never offers an order he knows will be refused: a house too cold
    // to obey (under 40) is to be won first, and he says so.
    const cold = [war, foe].filter((p) => favourOf(p.id) < 40).sort((a, b) => favourOf(a.id) - favourOf(b.id))[0];
    // The King's answers to a war: stop it (by command if both are warm, else by
    // sending a loyal house to keep the peace), take a side (the weaker one), or
    // let them bleed. A royal match is the rare, dear bond.
    const [weak, strong] = [war, foe].sort((a, b) => (a.units ?? 0) - (b.units ?? 0));
    const keeper = great.filter((p) => p.id !== war.id && p.id !== foe.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const acts = [
      cold
        ? (keeper ? { label: `Send ${keeper.house.name.replace(/^House /, "")} to keep the peace`, action: "settle", city: seatOf(war.id)?.id, to: foe.id } : null)
        : { label: "Command peace", action: "peace", city: seatOf(war.id)?.id, to: foe.id },
      { label: `Back ${weak.house.name.replace(/^House /, "")}, the weaker (${((weak.units ?? 0) * 200).toLocaleString("en-US")} men to ${((strong.units ?? 0) * 200).toLocaleString("en-US")})`, action: "back", city: seatOf(weak.id)?.id, to: strong.id },
      { label: "Sit it out", ui: "sitout", war: `${war.id}:${foe.id}` },
      matchFor(ctx, war.id, foe.id) ? { label: "Wed them to each other", action: "marriage", city: seatOf(war.id)?.id, to: foe.id } : null,
    ].filter((a) => a && (a.ui || a.city !== undefined));
    const why = cold
      ? `${cold.house.name} is too cold to obey a royal peace (favour ${Math.round(favourOf(cold.id))}, it needs 40). Warm them first, or bind the two by marriage.`
      : "Every season of war burns fields and lowers the realm's peace. Both are warm enough to obey the King's peace.";
    out.push({ urgency: 50, text: `${war.house.name} and ${foe.house.name} are at war`, why, acts: acts.filter((a) => a.city !== undefined) });
  }
  if (purse < ECONOMY.thin) out.push({ urgency: 40, text: "The royal treasury is thin", why: "Every decree costs crowns; a higher tithe fills the purse but cools the houses.", acts: [{ label: "Raise the tithe", ui: "tithe_up" }] });
  if (!out.length) out.push({ urgency: 0, text: "The realm is quiet", why: "A good season to win a house's love before you need it.", acts: [] });
  // Every order shows its price before the King gives it, as the town card does: "Command peace  6k cr".
  // And what it does, so the King weighs effect against price: "Gift crowns  15k cr · +10".
  const DOES = { sellswords: "1,000 men", back: "+12 them, −12 the other", settle: "truce; keeper +6, both −3", sitout: "the war goes on",  tithe_down: `slower to cool; ${(Math.round(lastSeason.net * 50) / 1000).toFixed(1)}k less a season`, grant: "+20 them, −30 the holder", gift: "+10", feast: "+15", relief: "+12, eases it, cannot end it", marriage: "+8 each, bound in peace", peace: "+2 each, truce", banners: "+3 if they come", levy: "600 men", buyoff: "+25, others −2", alliance: "sworn 4 years, +5", march: "the host besieges; −25 them" };
  // The realm's lesser matters: plague, unrest, a thin granary, bare walls, a
  // house grown too strong, a loyal one unrewarded, a full treasury, an heir of
  // age. The Hand raises the one he has raised least lately, so his counsel
  // changes with the realm instead of saying the same thing every season.
  const turn = world?.turn ?? 0;
  const short = (h) => h.house.name.replace(/^House /, "");
  const ofHouse = (c) => great.find((p) => p.id === c.owner);
  const lacks = (c, b) => !(c.buildings ?? []).some((x) => String(x).startsWith(b)) && !meta.works?.[c.id];
  const occasions = [];
  const sick = cities.find((c) => c.plague && !c.famine);
  if (sick) occasions.push({ kind: "plague", urgency: 55, text: `Plague in ${sick.title}`, why: "The death-carts go out at night. Clean water slows it; a sept tends the dying and keeps the people from blaming the crown.",
    acts: [lacks(sick, "Aqueduct") ? { label: `Pay for an aqueduct in ${sick.title}`, action: "build", building: "aqueduct", city: sick.id } : null,
      lacks(sick, "Temple") ? { label: `Pay for a sept in ${sick.title}`, action: "build", building: "temple", city: sick.id } : null,
      { label: "Send grain", action: "relief", city: sick.id }].filter(Boolean) });
  const riot = cities.find((c) => c.disorder);
  if (riot) { const h = ofHouse(riot); occasions.push({ kind: "unrest", urgency: 55, text: `${riot.title} is in uproar`, why: "The people have stopped working and started shouting. Bread quiets a crowd; a sept or a market gives it something to lose.",
    acts: [{ label: "Send grain", action: "relief", city: riot.id }, lacks(riot, "Temple") ? { label: "Pay for a sept", action: "build", building: "temple", city: riot.id } : null,
      lacks(riot, "Marketplace") ? { label: "Pay for a market", action: "build", building: "market", city: riot.id } : null, h ? { label: `A feast for ${short(h)}`, action: "feast", city: riot.id } : null].filter(Boolean) }); }
  const lean = cities.filter((c) => !c.famine && c.granaryLow && (c.size ?? 0) >= 5 && lacks(c, "Granary")).sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
  if (lean) occasions.push({ kind: "granary", urgency: 40, text: `${lean.title}'s granary runs low`, why: `${lean.title} eats what it grows and keeps nothing back. One bad harvest and it starves; a granary carries it through.`,
    acts: [{ label: `Pay for a granary in ${lean.title}`, action: "build", building: "granary", city: lean.id }, { label: "Send grain now", action: "relief", city: lean.id }] });
  const fighting = great.filter((p) => (p.atWarWith ?? []).length);
  const bare = cities.filter((c) => fighting.some((p) => p.id === c.owner) && lacks(c, "City Walls") && (c.size ?? 0) >= 4).sort((a, b) => (b.size ?? 0) - (a.size ?? 0))[0];
  if (bare) { const h = ofHouse(bare); occasions.push({ kind: "walls", urgency: 45, text: `${bare.title} has no walls, and war is near`, why: `${h ? h.house.name : "Its house"} is at war, and ${bare.title} would fall to the first host that reaches it. Walls paid by the crown are remembered.`,
    acts: [{ label: `Pay for walls at ${bare.title}`, action: "build", building: "walls", city: bare.id }, h && favourOf(h.id) >= BANDS.sworn ? { label: `Swear an alliance with ${short(h)}`, action: "alliance", city: bare.id } : null].filter(Boolean) }); }
  const mighty = [...great].sort((a, b) => (b.cities?.length ?? 0) * 2 + (b.units ?? 0) - (a.cities?.length ?? 0) * 2 - (a.units ?? 0))[0];
  const avgTowns = great.reduce((n, p) => n + (p.cities?.length ?? 0), 0) / Math.max(1, great.length);
  if (mighty && (mighty.cities?.length ?? 0) >= avgTowns * 1.5 && seatOf(mighty.id) && !(stakes?.s.wards?.[mighty.id] > turn)) {
    const f = favourOf(mighty.id);
    occasions.push({ kind: "mighty", urgency: 45, text: `${mighty.house.name} grows too strong`, why: `${mighty.cities.length} towns, more than any other house. Today they kneel; a house that size could take the throne tomorrow. Bind them to you, or hold their heir at court.`,
      acts: [f >= 50 ? { label: `Swear an alliance with ${short(mighty)}`, action: "alliance", city: seatOf(mighty.id).id } : null,
        { label: `Take their heir as your ward`, action: "ward", city: seatOf(mighty.id).id },
        { label: `A feast in their honour`, action: "feast", city: seatOf(mighty.id).id }].filter(Boolean) });
  }
  const loyal = great.filter((p) => favourOf(p.id) >= 75 && seatOf(p.id)).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
  if (loyal) occasions.push({ kind: "loyal", urgency: 30, text: `${loyal.house.name} has served you well`, why: `Favour ${Math.round(favourOf(loyal.id))}: they answer every summons. Loyalty left unrewarded cools, and the other houses watch what it earns.`,
    acts: [{ label: `Swear an alliance with ${short(loyal)}`, action: "alliance", city: seatOf(loyal.id).id }, { label: "Gift crowns", action: "gift", city: seatOf(loyal.id).id },
      lacks(seatOf(loyal.id), "Marketplace") ? { label: `Pay for a market at ${seatOf(loyal.id).title}`, action: "build", building: "market", city: seatOf(loyal.id).id } : null].filter(Boolean) });
  const crownSeat = cities.find((c) => players.find((p) => p.id === c.owner)?.house.crown && c.capital);
  if (purse >= 600 && crownSeat) occasions.push({ kind: "rich", urgency: 30, text: "The royal treasury is full", why: "Gold in a chest wins nobody. Spend it where the realm will see it, or ease the tithe and let the houses keep more.",
    acts: [{ label: "Hold a feast at court", action: "feast", city: crownSeat.id }, meta.tithe > 0 ? { label: `Lower the tithe to ${Math.round(meta.tithe * 100) - 5}%`, ui: "tithe_down" } : null,
      lacks(crownSeat, "Marketplace") ? { label: "Pay for a market at Kingsmere", action: "build", building: "market", city: crownSeat.id } : null].filter(Boolean) });
  if (court) {
    for (const h of [...great].sort(() => 0.5 - ((turn * 7 + great.length) % 10) / 10)) {
      const lord = court.lordOfHouse(h.id);
      const heir = lord && court.alive().find((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 16);
      const match = heir && great.filter((g) => g.id !== h.id && seatOf(g.id)).map((g) => [g, court.lordOfHouse(g.id)]).find(([, l]) => l && court.alive().some((k) => k.parents?.includes(l.id) && !k.spouse && k.age >= 16 && k.gender !== heir.gender));
      if (heir && match && seatOf(h.id)) {
        const [other] = match;
        occasions.push({ kind: "match", urgency: 35, text: `${heir.name} of ${h.house.name} is of age to wed`, why: `A royal match with ${other.house.name} would bind both houses to the crown and to each other: no war between them while it holds.`,
          acts: [matchFor(ctx, h.id, other.id) ? { label: `Wed them to ${short(other)}`, action: "marriage", city: seatOf(h.id).id, to: other.id } : null, { label: "A feast for the betrothal talk", action: "feast", city: seatOf(h.id).id }].filter(Boolean) });
        break;
      }
    }
  }
  // Two of them at most. Those on the card stay a year (nothing swaps each
  // season); then the ones raised least lately come up. A matter the King has
  // answered (an order at its town) is put to rest for a year.
  const told = (meta.counselTold ??= {});
  const answered = meta.answeredAt ?? {};
  const open = occasions.filter((o) => o.acts.length && !o.acts.some((a) => a.city != null && turn - (answered[a.city] ?? -99) < 4));
  const now = meta.counselNow ?? { kinds: [], since: -99 };
  let lesser = turn - now.since < 4 ? open.filter((o) => now.kinds.includes(o.kind)) : [];
  if (!lesser.length) {
    lesser = open.sort((a, b) => (told[a.kind] ?? -99) - (told[b.kind] ?? -99) || b.urgency - a.urgency).slice(0, 2);
    for (const o of lesser) told[o.kind] = turn;
    meta.counselNow = { kinds: lesser.map((o) => o.kind), since: turn };
    if (lesser.length) chron.saveMeta(meta);
  }
  if (lesser.length) for (let i = out.length - 1; i >= 0; i--) if (out[i].urgency === 0) out.splice(i, 1);  // not "quiet" after all
  out.push(...lesser);
  // An order that can't be given now isn't offered: the banners answer once a year.
  // Once a year means once a year here too: the banners and the levy aren't
  // offered again until their year is out (the decree would refuse them anyway).
  // The threat the storyteller raised (director.js): a matter at its place, more urgent as it grows.
  const raised = Director.matter(meta);
  if (raised) out.push(raised);
  for (const o of out) o.acts = o.acts.filter((a) => !(a.action === "banners" && (!bannersReady(world?.turn ?? 0) || seasonsLeft("banners") > 0)) && !(a.action === "levy" && seasonsLeft("levy") > 0) && !(FAVOUR.has(a.action) && a.city != null && seasonsLeft(yearlyKey(a) ?? "") > 0));
  // An order offered once is not offered again under another matter (the
  // banners answer the usurper and the dead alike): the first matter keeps it.
  const given = new Set();
  for (const o of out.sort((a, b) => b.urgency - a.urgency)) o.acts = o.acts.filter((a) => {
    const k = `${a.action ?? a.ui}:${a.city ?? ""}:${a.to ?? ""}:${a.building ?? ""}`;
    if (given.has(k)) return false;
    given.add(k);
    return true;
  });
  // The Hand's own pick on each matter: the order that does most for its cost. Never the ward: an
  // heir taken hostage is the King's own hard choice, not the Hand's advice (gameplay review #2).
  const PREFER = ["court", "feast", "relief", "tithe_down", "banners", "peace", "settle", "buyoff", "marriage", "gift", "grant", "levy", "ward", "promise", "cede", "tithe_up"];
  for (const o of out) {
    const rank = (a) => { const i = PREFER.indexOf(a.action ?? a.ui); return i < 0 ? 99 : i; };
    const best = [...o.acts].sort((a, b) => rank(a) - rank(b))[0];
    if (best && o.acts.length > 1) best.pick = true;
  }
  for (const o of out) for (const a of o.acts) {
    // The price the crown will really pay (a share of a full treasury), never the base.
    if (DECREES[a.action]?.cost) {
      a.cost = priceOf(a.action);
      const short = shortOf(world?.players?.find((p) => houseFor(p).crown)?.gold ?? 0, a.cost);
      if (short) a.short = short;
      a.label += `  ${a.cost >= 10000 ? `${Math.round(a.cost / 1000) / 10}m` : `${Math.round(a.cost / 10)}k`} cr`;  // gold ×100 crowns
    }
    const does = DOES[a.action ?? a.ui];
    if (does && !a.label.includes("(")) a.label += ` · ${does}`;
  }
  // Every crisis has at least one answer the King can give (gameplay review #1): when the purse can
  // pay for none of its orders, the crown pays in something else. A march on Kingsmere is answered with
  // a royal town for their claim; any other, with a seat at the council promised to the house, paid
  // for in the favour of the house the King has favoured most (data/decrees.json promise, cede).
  const crownP = players.find((p) => p.house.crown);
  const payable = (a) => a.action && !a.short && DECREES[a.action] && !DECREES[a.action].off;
  for (const o of out) {
    if (!(o.urgency >= 75 || o.kind === "ultimatum") || o.acts.some(payable)) continue;
    const who = players.find((p) => p.id === o.subject);
    if (!who || who.house.crown || who.house.wild || !seatOf(who.id)) continue;
    const name = who.house.name.replace(/^House /, "");
    const spare = o.kind === "march" && crownP ? cities.filter((c) => c.owner === crownP.id && !c.capital).sort((a, b) => (a.size ?? 0) - (b.size ?? 0))[0] : null;
    if (spare) { o.acts.push({ label: `Cede ${spare.title ?? cityName(spare.id)} to ${name} for their claim`, action: "cede", city: spare.id, to: who.id }); continue; }
    if ((meta.oncePerHouse?.promise ?? {})[who.id] != null) continue;
    const rival = great.filter((p) => p.id !== who.id).sort((a, b) => favourOf(b.id) - favourOf(a.id))[0];
    const P = DECREES.promise;
    o.acts.push({ label: `Promise ${name} a seat at council (${name} +${P.favour}${rival ? `, ${short(rival)} ${String(P.rival).replace("-", "−")}` : ""})`, action: "promise", city: seatOf(who.id).id, ...(rival ? { to: rival.id } : {}) });
  }
  // Every matter the realm has, worst first: the court (courtYear) chooses
  // which are put to the King, and when.
  return out.sort((a, b) => b.urgency - a.urgency).filter((o) => !matterResting(ctx, o)).map((o) => ({ ...o, key: heardKey(o) }));
}

// What a matter is, for resting it after it is answered.
export const matterKey = (o) => o.kind ?? (/is starving$/.test(o.text) ? "starving" : o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, ""));
function matterResting(ctx, o) {
  const { world, meta } = ctx;
  const at = meta.mattersRest?.[matterKey(o)];
  return at != null && (world?.turn ?? 0) - at < 4;
}
// The matter itself, for "never twice in a reign": its words without numbers,
// and for a threat that comes again (a march, a host of the dead, a famine
// year) the time it came.
const heardKey = (o) => `${o.text.replace(/[\d.,]+/g, "#").replace(/:.*$/, "")}${o.occur != null ? `@${o.occur}` : ""}`;

// A royal match needs an unwed son or daughter of age from each house, one of
// each. The Hand offers a match only when this finds one.
export function matchFor(ctx, pa, pb) {
  const { court } = ctx;
  if (!court) return null;
  const [la, lb] = [pa, pb].map((pid) => court.lordOfHouse(pid));
  if (!la || !lb) return null;
  const unwed = (lord) => court.alive().filter((k) => k.parents?.includes(lord.id) && !k.spouse && k.age >= 15);
  for (const ka of unwed(la)) { const kb = unwed(lb).find((k) => k.gender !== ka.gender); if (kb) return [la, lb, ka, kb]; }
  return null;
}

// What the King's silence costs, matter by matter: the house it touches takes
// it as an answer, in its favour and in the chronicle.
export function lapseOf(ctx, o) {
  const { world, favourOf } = ctx;
  const ownerOf = (c) => world.players.find((p) => p.id === c.owner);
  const city = (o.acts ?? []).map((a) => world?.cities?.find((c) => c.id === Number(a.city))).find((c) => c && ownerOf(c) && !houseFor(ownerOf(c)).crown);
  const owner = city ? world.players.find((p) => p.id === city.owner) : null;
  const house = owner ? houseFor(owner).name : null;
  const loyal = (world?.players ?? []).filter((p) => !houseFor(p).wild && !houseFor(p).crown && favourOf(p.id) >= BANDS.steady);
  const t = o.text;
  const said = (rest) => `The King said nothing ${rest}`;
  if (/grows cold/.test(t) && owner) return { shift: { [owner.id]: -6 }, text: said(`to ${house}. They take it as an answer.`) };
  if (/is starving/.test(t) && owner) return { shift: { [owner.id]: -8 }, text: said(`while ${city.title ?? city.name} starved. ${house} counts its dead and remembers.`) };
  if (/at war/.test(t)) { const ids = o.acts.map((a) => world.cities.find((c) => c.id === Number(a.city))?.owner).concat(o.acts.map((a) => a.to)).filter((x) => x != null); return { shift: Object.fromEntries([...new Set(ids)].map((id) => [id, -3])), text: said("of the war, and it burns on. Both houses note whose side the crown was on: neither.") }; }
  if (o.kind === "plague" && owner) return { shift: { [owner.id]: -5 }, text: said(`while plague emptied ${city.title ?? city.name}. ${house} buries its dead alone.`) };
  if (o.kind === "unrest" && owner) return { shift: { [owner.id]: -5 }, text: said(`to the crowds of ${city.title ?? city.name}. They shout louder.`) };
  if (o.kind === "granary" && owner) return { shift: { [owner.id]: -3 }, text: said(`of ${city.title ?? city.name}'s empty granary. Its people store their grudge instead.`) };
  if (o.kind === "walls" && owner) return { shift: { [owner.id]: -4 }, text: said(`of ${city.title ?? city.name}'s walls. ${house} builds its own, and remembers who didn't.`) };
  if (o.kind === "loyal" && owner) return { shift: { [owner.id]: -5 }, text: said(`to ${house}'s loyalty. Unrewarded, it cools.`) };
  if (o.kind === "mighty" && owner) return { shift: { [owner.id]: 3 }, text: said(`as ${house} grew. They take the crown's silence for weakness, and grow bolder.`) };
  if (o.kind === "match" && owner) return { shift: { [owner.id]: -3 }, text: said(`of ${house}'s heir. Another house will make the match instead.`) };
  if (o.kind === "rich") return { shift: {}, text: said("while the gold sat in the royal chest. The houses saw it sit.") };
  if (/claim to the throne|marches on Kingsmere|march is over|dead come south/.test(t)) return { shift: Object.fromEntries(loyal.map((p) => [p.id, -2])), text: said(`while ${t.replace(/[:.].*$/, "").toLowerCase()}. The loyal houses wonder whether the crown will act at all.`) };
  return { shift: owner ? { [owner.id]: -4 } : {}, text: said(`of it: ${t.replace(/:.*$/, "").toLowerCase()}.`) };
}

export function lapse(ctx, m, turn) {
  const { meta, shiftFavour, record } = ctx;
  const told = m.lapse ?? { shift: {}, text: `The King said nothing of it: ${m.text}.` };
  if (Object.keys(told.shift).length) shiftFavour(Object.fromEntries(Object.entries(told.shift).map(([id, d]) => [Number(id), d])), "the King's silence");
  record({ turn, kind: "unrest", text: told.text });
  (meta.mattersRest ??= {})[m.key] = turn;
  meta.matter = null;
  chron.saveMeta(meta);
}
