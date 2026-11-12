// Risings: a great house split by Freeciv's own civil war (casebook: Lords with their own needs, Norland; The
// funeral is the crisis, CK2; Defeat is a chapter, Kenshi; the failure The AI that doesn't play, Medieval II).
// The stories decide when, who and how it ends (bridge/arcs: a beat's `rising`, `risingOdds`, `risingEnd`; the
// King's answers are the story's court branches). This keeps only the realm's side of Freeciv's half
// (realm_rising in realmrules/script.lua: the split, the rebels' host and march, the assaults, settling itself
// after risings.seasons): the war declared by the one diplomacy writer, the odds and the end told, and which
// side holds each town for /world. The one owner of meta.risings. Design: docs/research/risings-civil-war-2026-11-12.md.
import * as chron from "./chronicles.js";
import * as Lua from "./lua.js";
import { houseFor, cityName } from "./narrator.js";

const state = (meta) => (meta.risings ??= { pending: {}, active: {} });
const save = (ctx) => (ctx.saveMeta ?? chron.saveMeta)(ctx.meta);  // a probe passes its own
const nameOf = (world, pid) => houseFor(world?.players?.find((p) => p.id === Number(pid)) ?? {}).name ?? "A house";
const townsOf = (world, pid) => (world?.cities ?? []).filter((c) => c.owner === Number(pid));

// A story splits a house (arcs.js `rising`): Freeciv's own odds decide; leader is who the loyal towns rise for.
export function rise(ctx, house, leader) {
  const { meta, send } = ctx;
  if (Object.values(state(meta).active).some((a) => a.house === Number(house))) return;
  state(meta).pending[house] = { leader };
  send(`lua cmd ${Lua.rising(Number(house), 0)}`);
  save(ctx);
}

// A story warns of it first (arcs.js `risingOdds`): the chance, told when Freeciv answers.
export function odds(ctx, house, claimant = null) {
  state(ctx.meta).pending[house] = { ...(state(ctx.meta).pending[house] ?? {}), claimant: claimant ?? state(ctx.meta).pending[house]?.claimant ?? null };
  ctx.send(`lua cmd ${Lua.risingOdds(Number(house))}`);
  save(ctx);
}

// What Freeciv reports: the odds, the split (or not), and how a rising ended.
export function event(ctx, ev) {
  const { world, meta, record, scene, diplomacy } = ctx;
  const r = state(meta);
  const turn = Number(ev.turn);
  const house = Number(ev.house);
  if (ev.kind === "rising_odds") {
    if (r.pending[house]) r.pending[house].odds = Number(ev.odds);  // the warning's town fact (townRising: brewing)
    save(ctx);
    record({ turn, kind: "unrest", text: `The captains put the chance that ${nameOf(world, house)} splits at ${ev.odds} in a hundred: ${ev.unhappy} of its ${ev.towns} towns are restless, ${ev.celebrating} are feasting. A feast or relief from the King lowers it.` });
    return;
  }
  if (ev.kind === "rising") {
    const p = r.pending[house] ?? {};
    delete r.pending[house];
    const rebel = Number(ev.rebel);
    if (rebel < 0) {
      record({ turn, kind: "decree", text: `${nameOf(world, house)}'s towns stay with their lord${p.leader ? `: none rises for ${p.leader}` : ""}.` });
      save(ctx);
      return;
    }
    const towns = String(ev.towns ?? "").split(",").filter(Boolean).map(Number);
    r.active[rebel] = { house, rebel, name: p.leader ?? p.claimant ?? "A pretender", turn, towns };
    diplomacy?.([rebel, house, 0, "War"]);  // Freeciv leaves the two at cease-fire; the one writer declares the war
    const muster = world?.cities?.find((x) => x.id === Number(ev.muster));
    if (muster) scene("muster", { x: muster.x, y: muster.y, city: muster.id, owner: rebel, strength: 0.8 });
    record({ turn, kind: "rebellion", text: `${nameOf(world, house)} is divided: ${towns.map(cityName).join(" and ")} rise for ${r.active[rebel].name}, and their host marches.`, city: towns[0] });
    save(ctx);
    return;
  }
  if (ev.kind === "rising_over") {
    const a = r.active[Number(ev.rebel)];
    delete r.active[Number(ev.rebel)];
    const lord = house >= 0 ? nameOf(world, house) : "the old house";
    const who = a?.name ?? "the pretender";
    const text = ev.how === "keep"
      ? (house < 0 || !townsOf(world, house).length ? `${lord} is no more: the towns that rose for ${who} hold it all.` : `The rising in ${lord} ends: the towns that rose for ${who} keep to themselves, a lesser house now.`)
      : `The rising in ${lord} ends: its towns go back to their lord.`;
    record({ turn, kind: "rebellion", text });
    if (ev.how === "keep" && house >= 0 && townsOf(world, house).length) diplomacy?.([Number(ev.rebel), house, 16, "Armistice"]);
    save(ctx);
  }
}

// A town in a rising, for /world (view.js), the one writer of it: while a story warns of it, the house's towns are
// "brewing" (Freeciv's odds, the claimant gathering men); once it splits, "risen", with which side holds the town
// and against whom. Null outside a rising.
export function townRising(meta, c) {
  for (const a of Object.values(meta?.risings?.active ?? {})) {
    if (c.owner === a.rebel) return { stage: "risen", side: "rebels", house: a.house, rebel: a.rebel, claimant: a.name };
    if (c.owner === a.house) return { stage: "risen", side: "lord", house: a.house, rebel: a.rebel, claimant: a.name };
  }
  const p = meta?.risings?.pending?.[c.owner];
  if (p) return { stage: "brewing", house: c.owner, odds: p.odds ?? null, claimant: p.claimant ?? p.leader ?? null };
  return null;
}
