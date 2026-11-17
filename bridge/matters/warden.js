// A great house beaten (Mac 2026-11-17, GAME_DESIGN "The game"): who holds its lands, what becomes of its lord, and a
// warden who defies the King. The land and its warden are warden.js's; these say what needs the King and how he may
// answer. The wrong warden costs him later (warden.js risk, defiesAt), so each candidate's card line says his nature,
// his loyalty, his tie to the beaten house and how he would hold, and the why says who his family is (lore.js).
import { Matter } from "./matter.js";
import * as W from "../warden.js";
import { cityName } from "../narrator.js";

export class Warden extends Matter {
  static kind = "warden";
  find(ctx, s) {
    const e = (ctx.meta.wardens ?? []).find((x) => x.warden == null);
    if (!e) return [];
    const picks = W.candidates(ctx, e);
    if (!picks.length) return [];
    const n = e.towns.length;
    // occur: a new matter each time a warden is to be named (one unseated is a new hearing, court.js heard).
    return [{ urgency: 100, subject: e.house, city: e.seat, occur: `${e.turn}.${(e.passed ?? []).length}`, places: e.towns,
      text: `Who holds ${e.name}'s lands?`,
      why: `${e.name} is beaten; its ${n === 1 ? "town" : `${n} towns`} (${e.towns.map(cityName).join(", ")}) need a warden to hold them for you. A loyal, steady house holds; an ambitious one, or one tied by blood to the beaten house, may defy you later. ${picks.map((x) => `${x.c.surname}: ${W.lore(x.c)}`).join(" ")}` }];
  }
  answers(ctx, s, m) {
    const e = W.of(ctx.meta, m.subject);
    return W.candidates(ctx, e).map((x) => ({ label: W.label(ctx, e, x), action: "warden", city: x.c.seat, to: e.house }));
  }
}

export class Fate extends Matter {
  static kind = "fate";
  find(ctx, s) {
    const e = (ctx.meta.wardens ?? []).find((x) => x.fate == null && ctx.court?.people?.[x.lord]?.alive);
    if (!e) return [];
    const lord = ctx.court.people[e.lord];
    return [{ urgency: 99, subject: e.house, city: e.seat, occur: e.turn,
      text: `${lord.name} of ${e.name} kneels before the King`,
      why: `The beaten lord waits on your word. Spare him and the houses who respect you think you great, those who think you weak grow bolder; behead him and every house fears you, the ones who liked you a little less. His kin remember either way.` }];
  }
  answers(ctx, s, m) {
    const lord = ctx.court.people[W.of(ctx.meta, m.subject).lord];
    return [{ label: `Spare ${lord.name}`, action: "spare", city: m.city, to: m.subject },
      { label: `Imprison ${lord.name}`, action: "imprison", city: m.city, to: m.subject },
      { label: `Behead ${lord.name}`, action: "behead", city: m.city, to: m.subject }];
  }
}

export class Defiant extends Matter {
  static kind = "defiant";
  find(ctx, s) {
    const e = (ctx.meta.wardens ?? []).find((x) => W.defies(x, s.turn));
    if (!e) return [];
    // occur: heard again each year he still defies (a defiance left stands, and comes back).
    return [{ urgency: 96, subject: e.house, city: e.seat, occur: `${e.defiesAt}.${Math.floor((s.turn - e.defiesAt) / 4)}`, places: e.towns,
      text: `${e.wardenName} defies the King`,
      why: `${W.defiance(ctx, e)}. While it defies you, ${e.name}'s lands are not yours. Buy its oath back, or strip it and name another warden.` }];
  }
  answers(ctx, s, m) {
    const e = W.of(ctx.meta, m.subject);
    return [{ label: `Buy back ${e.wardenName}'s oath`, action: "regrant", city: m.city, to: e.house },
      { label: `Strip ${e.wardenName} and name another`, action: "unseat", city: m.city, to: e.house }];
  }
  silence(ctx, s, m) {
    const d = W.WARDEN.silence.defy;
    return { shift: Object.fromEntries(s.great.map((p) => [p.id, d])), text: `The King let ${W.of(ctx.meta, m.subject).wardenName}'s defiance stand. The houses see a crown that cannot hold what it took.` };
  }
}
