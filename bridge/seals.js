// The royal seal (King of Dragon Pass, Six Ages: a few actions a season, and
// always something left undone). Each decree the King chooses between sittings
// takes a seal as well as its gold; a ruling while the court sits takes none:
// the realm asks there, here the King chooses. Seals come with each season and
// keep up to a bank, so a quiet season can be saved for a hard one. The one
// owner of the count is the reign's meta; the numbers are data (data/seals.json).

import fs from "node:fs";
import * as chron from "./chronicles.js";

export const SEALS = JSON.parse(fs.readFileSync(new URL("./data/seals.json", import.meta.url), "utf8"));

export const on = (meta) => Boolean(meta?.options?.seals ?? SEALS.on);
const bank = (meta) => (meta?.lastAct ? SEALS.bankLastAct : SEALS.bank);
const state = (meta) => (meta.seals ??= { n: SEALS.perSeason, spent: [] });

// Each season (season.js turn): the season's seal comes, kept up to the bank.
export function season(meta, turn) {
  if (!on(meta) || meta.status !== "running") return;
  const s = state(meta);
  s.n = Math.min(bank(meta), s.n + SEALS.perSeason);
  s.at = turn;
  chron.saveMeta(meta);
}

// Whether a decree may be given now: a ruling at court (a sitting, or an order that
// answers a matter put to him) always may; otherwise it takes a seal.
export function refuse(meta, ruling = false) {
  if (!on(meta) || ruling || meta.court?.sitting != null) return null;
  return state(meta).n >= 1 ? null : "No royal seal is left: the next comes with the season.";
}

// A decree given (routes_decree.js): its seal spent, unless the court sat for it.
export function spend(meta, action, turn, ruling = false) {
  if (!on(meta) || ruling || meta.court?.sitting != null) return false;
  const s = state(meta);
  s.n = Math.max(0, s.n - 1);
  s.spent = [...(s.spent ?? []), { turn, action }].slice(-200);
  chron.saveMeta(meta);
  return true;
}

// For /world: how many he holds and how many he can hold.
export const view = (meta) => (on(meta) ? { n: state(meta).n, of: bank(meta) } : null);
