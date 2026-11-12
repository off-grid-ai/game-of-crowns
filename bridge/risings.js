// Risings: a great house split by Freeciv's own civil war (casebook: Lords with their own needs, Norland; The
// funeral is the crisis, CK2; Defeat is a chapter, Kenshi; the failure The AI that doesn't play, Medieval II).
// The one owner of a rising on the realm's side (meta.risings); the Freeciv half (the split, the rebels' host and
// march, the assaults, settling after risings.seasons) is realm_rising in realmrules/script.lua.
//   claim     a succession crisis (a child heir, no heir) or a house left cold too long names a claimant;
//             the chronicle warns, with Freeciv's own odds (realm_rising_odds), warnSeasons ahead
//   roll      Freeciv's odds decide (the King's feasts and relief lower them: celebrating towns)
//   rising    the house splits; the bridge's one diplomacy writer declares the war; the matter goes to court:
//             back the lord (the royal host marches on the rebels), back the claimant (a lesser house),
//             broker terms (the towns go back), or stay out (it settles itself)
//   over      crushed, won, or settled (Freeciv's realm_rising_end reports how)
// Design and the measurement behind it: docs/research/risings-civil-war-2026-11-12.md.
import fs from "node:fs";
import * as chron from "./chronicles.js";
import * as Lua from "./lua.js";
import { houseFor, cityName } from "./narrator.js";
import { BANDS } from "./favour.js";

export const RISINGS = JSON.parse(fs.readFileSync(new URL("./data/risings.json", import.meta.url), "utf8"));

const state = (meta) => (meta.risings ??= { claims: {}, active: {}, cold: {} });
const save = (ctx) => (ctx.saveMeta ?? chron.saveMeta)(ctx.meta);  // a probe passes its own
const nameOf = (world, pid) => houseFor(world?.players?.find((p) => p.id === Number(pid)) ?? {}).name ?? "A house";
const townsOf = (world, pid) => (world?.cities ?? []).filter((c) => c.owner === Number(pid));

// The man who would take the seat: the house's bannerman who thinks least of his lord, else its eldest
// other man of age; null if the house has no one (then there is no claim).
function claimantOf(court, pid) {
  const lord = court?.lordOfHouse(pid);
  const kin = (court?.alive() ?? []).filter((c) => c.playerId === Number(pid) && c !== lord && (c.age ?? 0) >= 16);
  const opinion = (c) => c.relationships?.[lord?.id]?.opinion ?? 0;
  return kin.filter((c) => c.rank === "bannerman").sort((a, b) => opinion(a) - opinion(b))[0] ?? kin.sort((a, b) => (b.age ?? 0) - (a.age ?? 0))[0] ?? null;
}

// A claim against a house's lord: once per house at a time, never against the crown (the usurper covers that).
export function claim(ctx, pid, why, turn) {
  const { world, meta, court, record, send } = ctx;
  const r = state(meta);
  const p = world?.players?.find((x) => x.id === Number(pid));
  if (!p || houseFor(p).crown || houseFor(p).wild || r.claims[pid] || Object.values(r.active).some((a) => a.house === Number(pid))) return;
  if (townsOf(world, pid).length < RISINGS.minTowns) return;
  const who = claimantOf(court, pid);
  if (!who) return;
  r.claims[pid] = { turn, why, claimant: who.id, name: who.name };
  const cause = why === "child" ? "a child sits the seat" : why === "noheir" ? "the lord died with no heir" : "the King has turned his back on the house";
  record({ turn, kind: "unrest", text: `${who.name} gathers men in ${nameOf(world, pid)}'s towns: ${cause}, and he says the seat should be his. In ${RISINGS.warnSeasons} seasons the house may split.` });
  send(`lua cmd ${Lua.risingOdds(pid)}`);  // the chance, told when Freeciv answers (event "rising_odds")
  save(ctx);
}

// Each season: houses left cold too long raise a claimant; claims whose warning has run are rolled.
export function season(ctx, turn) {
  const { world, meta, favourOf, send } = ctx;
  if (!world) return;
  const r = state(meta);
  for (const p of world.players ?? []) {
    if (houseFor(p).crown || houseFor(p).wild || !townsOf(world, p.id).length) continue;
    r.cold[p.id] = favourOf(p.id) < BANDS.cooling ? (r.cold[p.id] ?? 0) + 1 : 0;
    if (r.cold[p.id] >= RISINGS.coldSeasons) { r.cold[p.id] = 0; claim(ctx, p.id, "cold", turn); }
  }
  for (const [pid, c] of Object.entries(r.claims)) {
    if (turn - c.turn < RISINGS.warnSeasons) continue;
    delete r.claims[pid];
    r.rolling = { ...(r.rolling ?? {}), [pid]: c };
    send(`lua cmd ${Lua.rising(Number(pid), 0)}`);  // Freeciv's own odds decide (event "rising")
  }
  save(ctx);
}

// What Freeciv reports: the odds, the split (or not), and how a rising ended.
export function event(ctx, ev) {
  const { world, meta, court, record, scene, diplomacy } = ctx;
  const r = state(meta);
  const turn = Number(ev.turn);
  const house = Number(ev.house);
  if (ev.kind === "rising_odds") {
    const c = r.claims[house];
    if (c) record({ turn, kind: "unrest", text: `The captains put the chance that ${nameOf(world, house)} splits at ${ev.odds} in a hundred: ${ev.unhappy} of its ${ev.towns} towns are restless, ${ev.celebrating} are feasting. A feast or relief from the King lowers it.` });
    return;
  }
  if (ev.kind === "rising") {
    const c = r.rolling?.[house];
    if (r.rolling) delete r.rolling[house];
    const rebel = Number(ev.rebel);
    if (rebel < 0) {
      if (c) record({ turn, kind: "decree", text: `${c.name}'s claim comes to nothing: ${nameOf(world, house)}'s towns stay with their lord.` });
      save(ctx);
      return;
    }
    const towns = String(ev.towns ?? "").split(",").filter(Boolean).map(Number);
    r.active[rebel] = { house, rebel, claimant: c?.claimant ?? null, name: c?.name ?? "A pretender", turn, towns };
    // Freeciv leaves the two at cease-fire; the realm's one diplomacy writer declares the war.
    diplomacy?.([rebel, house, 0, "War"]);
    const muster = world?.cities?.find((x) => x.id === Number(ev.muster));
    if (muster) scene("muster", { x: muster.x, y: muster.y, city: muster.id, owner: rebel, strength: 0.8 });
    record({ turn, kind: "rebellion", text: `${nameOf(world, house)} is divided. ${r.active[rebel].name} holds ${towns.map(cityName).join(" and ")} against his lord, and his host marches.`, city: towns[0] });
    const from = court?.alive().find((x) => x.id === r.active[rebel].claimant) ?? court?.lordOfHouse(house);
    if (from) court.arcPetition({ arc: "rising", beat: `rising-${rebel}`, thread: `the rising in ${nameOf(world, house)}`, from,
      text: `${r.active[rebel].name} has raised his banners in ${towns.map(cityName).join(" and ")}. ${nameOf(world, house)}'s lord asks the crown for help; the claimant asks only that the King keep out of it.`,
      options: [
        { id: "lord", label: "Back the lord", hint: `the royal host marches on the rebels · ${nameOf(world, house)} +${RISINGS.favour.lord}`, favour: { [house]: RISINGS.favour.lord }, result: `The King stands by ${nameOf(world, house)}'s lord. The royal host marches on the rebels.` },
        { id: "claimant", label: "Back the claimant", hint: `he keeps what he holds, a lesser house · ${nameOf(world, house)} ${RISINGS.favour.spurned}`, favour: { [house]: RISINGS.favour.spurned }, result: `The King recognises ${r.active[rebel].name}. What he holds is his.` },
        { id: "terms", label: "Broker terms", hint: `the towns go back to the lord, the claimant is pardoned · ${nameOf(world, house)} +${RISINGS.favour.terms}`, favour: { [house]: RISINGS.favour.terms }, result: `The King's herald brings both sides to terms. The towns go back to their lord.` },
        { id: "out", label: "Stay out of it", hint: "the rising settles itself, the side with more towns keeps them", result: "The King leaves the house to its quarrel." },
      ] }, world);
    save(ctx);
    return;
  }
  if (ev.kind === "rising_over") {
    const a = r.active[Number(ev.rebel)];
    delete r.active[Number(ev.rebel)];
    const lord = house >= 0 ? nameOf(world, house) : "the old house";
    const who = a?.name ?? "The pretender";
    const text = ev.how === "keep"
      ? (house < 0 || !townsOf(world, house).length ? `${lord} is no more: ${who} has taken it all.` : `The rising in ${lord} ends: ${who} keeps the towns he holds, a house of his own now.`)
      : `The rising in ${lord} ends: its towns go back to their lord.`;
    record({ turn, kind: "rebellion", text });
    // A claimant who keeps his towns makes peace with the lord he rose against.
    if (ev.how === "keep" && house >= 0 && townsOf(world, house).length) diplomacy?.([Number(ev.rebel), house, 16, "Armistice"]);
    save(ctx);
  }
}

// The King's answer at court (court.onArcRuling, arc "rising").
export function ruled(ctx, beat, option) {
  const { meta, send, marchOn, world } = ctx;
  const rebel = Number(String(beat).replace("rising-", ""));
  const a = state(meta).active[rebel];
  if (!a) return;
  if (option === "lord") {
    const target = townsOf(world, rebel).sort((x, y) => (y.size ?? 0) - (x.size ?? 0))[0];
    if (target) marchOn?.(target.id);
  }
  if (option === "claimant") send(`lua cmd ${Lua.risingEnd(rebel, "keep")}`);
  if (option === "terms") send(`lua cmd ${Lua.risingEnd(rebel, "return")}`);
  save(ctx);
}

// A town in a rising, for /world (view.js): which side holds it, and against whom. Null outside a rising.
export function townRising(meta, c) {
  for (const a of Object.values(meta?.risings?.active ?? {})) {
    if (c.owner === a.rebel) return { side: "rebels", house: a.house, rebel: a.rebel, claimant: a.name };
    if (c.owner === a.house) return { side: "lord", house: a.house, rebel: a.rebel, claimant: a.name };
  }
  return null;
}
