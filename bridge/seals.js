// The royal seal (King of Dragon Pass, Six Ages: a few actions a season, and
// always something left undone). Every order the King gives takes a seal as well as its gold, the answer to a
// chronicle matter too (Mac 2026-11-16: "I can take any action"; every matter's order went free of the seal, so
// nothing was left undone). Saying no, sitting a war out or a petition's answer at court takes none. Seals come with each season and
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

// Whether an order may be given now: it takes a seal, whatever it answers.
export function refuse(meta) {
  if (!on(meta)) return null;
  return state(meta).n >= 1 ? null : "No royal seal is left: the next comes with the season.";
}

// An order given (routes_decree.js): its seal spent.
export function spend(meta, action, turn) {
  if (!on(meta)) return false;
  const s = state(meta);
  s.n = Math.max(0, s.n - 1);
  s.spent = [...(s.spent ?? []), { turn, action }].slice(-200);
  chron.saveMeta(meta);
  return true;
}

// For /world: how many he holds and how many he can hold.
export const view = (meta) => (on(meta) ? { n: state(meta).n, of: bank(meta) } : null);
