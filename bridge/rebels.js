// A lord's rising, from the march to its end (casebook, The court: a lord's rebellion; CK3's faction war with its
// demands, Mount & Blade's rebel lord taken in the field). characters.js raises the rebel's host and marches it on
// the King's seat (realm_war_host tagged "rebel"); here the rising lives on until it ends one of two ways. While his
// host is on the road the rebel sends his terms to court (court.arcPetition, arc "rebel"): grant them and his men go
// home, refuse and the march goes on. Every man of his host fallen, the rising is crushed and the lord is brought to
// court in chains: hang him, pardon him, or ransom him to his house. One owner: meta.rebels {pid: {since, units,
// city, lord, terms, chains}}, the rising's men by id (the march's order lets them go at the walls; the rising
// doesn't). Numbers and words' prices: data/favour.json rebel. /world rebels.
import * as Lua from "./lua.js";
import { REBEL } from "./favour.js";
import { cityName, houseFor } from "./narrator.js";

const T = REBEL;

// His host raised and on the road (server.js war_host, tag "rebel").
export function risen(meta, ev, court) {
  const pid = Number(ev.owner);
  const units = String(ev.units ?? "").split(",").map(Number).filter((id) => id > 0);
  if (!units.length) return;
  const lord = court?.lordOfHouse?.(pid);
  (meta.rebels ??= {})[pid] = { since: Number(ev.turn), units, city: Number(ev.city), lord: lord?.id ?? null, terms: null, chains: null };
}

const others = (world, pid, d) => Object.fromEntries((world?.players ?? []).filter((p) => p.id !== pid && !houseFor(p).wild && !houseFor(p).crown && (world.cities ?? []).some((c) => c.owner === p.id)).map((p) => [p.id, d]));
const signed = (d) => `${d > 0 ? "+" : "−"}${Math.abs(d)}`;

// Each season: a rising whose men are all fallen is crushed; one still marching sends its terms, once.
export function season(ctx, turn) {
  const { meta, world, court, record } = ctx;
  if (!world || !meta.rebels) return;
  const alive = new Set((world.units ?? []).map((u) => u.id));
  for (const [k, r] of Object.entries(meta.rebels)) {
    const pid = Number(k);
    const lord = court?.people?.[r.lord];
    const house = world.players.find((p) => p.id === pid);
    if (!lord?.alive || !house) { delete meta.rebels[k]; continue; }
    if (r.chains != null) continue;  // before the King in chains: his answer ends it
    const men = r.units.filter((id) => alive.has(id));
    if (!men.length) {
      r.chains = turn;
      record({ turn, kind: "rebellion", text: `The rising of ${houseFor(house).name} is crushed. ${lord.name} is taken in the field and brought to Kingsmere in chains.`, city: r.city });
      const C = T.crushed;
      const ransom = Math.max(0, Math.min(C.ransom.gold, Math.floor(house.gold ?? 0)));
      court.arcPetition({ arc: "rebel", beat: `rebel-${pid}-${turn}-chains`, thread: `${lord.name} in chains`, from: lord,
        text: `${lord.name} kneels in chains before the throne, his banners in the mud of the road behind him. The court waits to see what the King does with a lord who marched on him.`,
        options: [
          { id: "hang", label: `Hang ${lord.name}`, favour: { [pid]: C.hang.house, ...others(world, pid, C.hang.others) }, hint: `${houseFor(house).name} ${signed(C.hang.house)} · every other great house ${signed(C.hang.others)}: they have seen the price`, result: `${lord.name} hangs before the gate of Kingsmere. His house will remember, and so will every lord who saw it.` },
          { id: "pardon", label: "Pardon him", favour: { [pid]: C.pardon.house, ...others(world, pid, C.pardon.others) }, hint: `${houseFor(house).name} ${signed(C.pardon.house)} · every other great house ${signed(C.pardon.others)}: a King who forgives a march`, result: `The King strikes off ${lord.name}'s chains with his own hand. ${lord.name} rides home owing him his life.` },
          ...(ransom > 0 ? [{ id: "ransom", label: `Ransom him to his house (${ransom} gold)`, favour: { [pid]: C.ransom.house }, hint: `+${ransom} gold · ${houseFor(house).name} ${signed(C.ransom.house)}`, result: `${houseFor(house).name} empties its chest to buy ${lord.name} back. He goes home poorer, and quieter.` }] : []),
        ] }, world);
      r.ransom = ransom;
      continue;
    }
    if (r.terms == null && turn - r.since >= T.terms.after) {
      r.terms = turn;
      const why = ctx.causeOf?.(pid);
      const gold = Math.round(T.terms.gold);
      court.arcPetition({ arc: "rebel", beat: `rebel-${pid}-${turn}-terms`, thread: `the terms of ${houseFor(house).name}`, from: lord,
        text: `A herald rides ahead of ${lord.name}'s host under a flag of truce. "My lord will turn his banners home, Your Grace, for ${gold} in gold and the King's word ${why ? `to make amends for ${why}` : "that his house will be heard at court"}. Refuse, and he comes on to ${cityName(r.city)}."`,
        options: [
          { id: "grant", label: `Grant his terms (${gold} gold)`, cost: gold, favour: { [pid]: T.terms.grant.house, ...others(world, pid, T.terms.grant.others) }, hint: `his host goes home · ${houseFor(house).name} ${signed(T.terms.grant.house)} · every other great house ${signed(T.terms.grant.others)}: a King who can be marched on`, result: `The King grants ${lord.name}'s terms. The rebel host turns for home, and the lords wonder who will march next.` },
          { id: "refuse", label: "Refuse: let him come", favour: others(world, pid, T.terms.refuse.others), hint: `the march goes on · every other great house ${signed(T.terms.refuse.others)}`, result: `The King sends the herald back with nothing. ${lord.name}'s host comes on.` },
        ] }, world);
    }
  }
}

// The King's answer (server.js court.onArcRuling, arc "rebel").
export function ruled(ctx, beat, option) {
  const { meta, world, court, send, record } = ctx;
  const [, k, , what] = String(beat).split("-");
  const r = meta.rebels?.[k];
  if (!r) return;
  const pid = Number(k);
  const lord = court?.people?.[r.lord];
  const turn = world?.turn ?? 0;
  if (what === "terms" && option === "grant") {
    // His men go home to their fields: the host is disbanded where it stands.
    for (const id of r.units) send(`lua cmd ${Lua.desert(id)}`);
    record({ turn, kind: "rebellion", text: `${lord?.name ?? "The rebel"}'s host breaks up on the road, and the men go home to their fields. The rising is over, bought.`, city: r.city });
    delete meta.rebels[k];
    return;
  }
  if (what !== "chains") return;
  if (option === "hang" && lord) court.die(lord, turn, world);
  if (option === "ransom" && r.ransom > 0) {
    const crown = ctx.crownOf?.();
    if (crown) send(`lua cmd ${Lua.pay(pid, crown.id, r.ransom)}`);
  }
  if (lord && option !== "hang") { court.remember(lord.id, option === "pardon" ? "I marched on the King and he forgave me. I owe him my life." : "I marched on the King, and my house bought me back in chains."); court.save(lord); }
  delete meta.rebels[k];
}

// For /world: each rising, its men still in the field, and whether its terms were sent or its lord is in chains.
export function view(meta, world) {
  const alive = new Set((world?.units ?? []).map((u) => u.id));
  return Object.entries(meta?.rebels ?? {}).map(([pid, r]) => ({ owner: Number(pid), since: r.since, city: r.city, lord: r.lord, units: r.units.filter((id) => alive.has(id)), terms: r.terms, chains: r.chains }));
}
