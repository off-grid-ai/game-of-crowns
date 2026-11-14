// The King's promises (casebook, Binding promises; CK3's promises and hooks, Frostpunk's promises to the people). At
// court he may answer a plea with a promise instead of now (characters.js: a pledge option on grain and on a lord's
// want of land). One owner, meta.promises [{id, kind, text, house, lord, town, made, due, kept, broken}]. Each
// season (season.js) an open promise is kept when its thing is done (data/promises.json), or broken when its seasons
// run out: the house's favour and the lord's memory follow, the chronicle says it, and the town it was made for
// remembers (minds.js hearTown). /world `promises`: the open ones and the last decided.
import fs from "node:fs";
import { cityName } from "./narrator.js";

const P = JSON.parse(fs.readFileSync(new URL("./data/promises.json", import.meta.url), "utf8"));
export const PROMISES = P;

// What the King's word is worth (Warband's reputation, repeated games): his kept promises over all decided, each
// counted from data/promises.json trust.prior kept ones, so a first broken promise costs a little, a habit a lot.
export function trust(meta) {
  const d = (meta?.promises ?? []).filter((p) => p.kept != null || p.broken != null);
  const kept = d.filter((p) => p.kept != null).length;
  return (kept + P.trust.prior) / (d.length + P.trust.prior);
}

// The King promises (petitions.js, a pledge answer): kept in meta.promises from this season.
export function make(meta, { kind, text, house, lord, town, turn }) {
  const k = P[kind];
  if (!k) return null;
  const p = { id: `pr${turn}-${house}-${kind}`, kind, text, house, lord, town, made: turn, due: turn + k.due, kept: null, broken: null };
  meta.promises = [...(meta.promises ?? []).filter((x) => x.id !== p.id), p];
  return p;
}

// Whether a promise's thing is done now.
const DONE = {
  grain: (ctx, p) => ctx.world.cities.some((c) => c.owner === p.house && (c.buildings ?? []).includes(P.grain.store)),
  land: (ctx, p) => ctx.world.cities.find((c) => c.id === p.town)?.owner === p.house,
};

// The season's reckoning: each open promise kept, broken, or still waiting.
export function season(ctx, turn) {
  const { meta, world, record, shiftFavour, minds, court } = ctx;
  if (!world || !meta.promises?.length) return;
  for (const p of meta.promises.filter((x) => x.kept == null && x.broken == null)) {
    const k = P[p.kind];
    const done = DONE[p.kind]?.(ctx, p);
    if (!done && turn < p.due) continue;
    const lord = court?.people?.[p.lord];
    const where = p.town != null ? cityName(p.town) : null;
    if (done) {
      p.kept = turn;
      shiftFavour({ [p.house]: k.kept }, "a promise kept");
      record({ turn, kind: "court", text: `The King keeps his word to ${lord?.name ?? "the house"}: ${p.text}.`, city: p.town ?? undefined });
      if (lord) court.remember(lord.id, `The King promised me ${p.text}, and kept his word.`);
      if (p.town != null) minds?.hearTown(p.town, `The King promised ${p.text}, and he kept his word.`, "promise_kept");
    } else {
      p.broken = turn;
      shiftFavour({ [p.house]: k.broken }, "a promise broken");
      record({ turn, kind: "court", text: `The King promised ${lord?.name ?? "the house"} ${p.text}, and did not keep it.${where ? ` In ${where} they say the crown's word is wind.` : ""}`, city: p.town ?? undefined });
      if (lord) court.remember(lord.id, `The King promised me ${p.text}, and broke his word.`);
      if (p.town != null) minds?.hearTown(p.town, `The King promised ${p.text}, and broke his word.`, "promise_broken");
    }
    if (lord) court.save(lord);
  }
  const open = meta.promises.filter((x) => x.kept == null && x.broken == null);
  meta.promises = [...meta.promises.filter((x) => x.kept != null || x.broken != null).slice(-P.keep), ...open];
}

// For /world: the open promises and the decided ones the reign keeps.
export function view(meta) {
  return (meta?.promises ?? []).map((p) => ({ ...p, place: p.town != null ? cityName(p.town) : null }));
}
