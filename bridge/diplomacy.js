// The realm's one diplomacy writer (integration audit #14: moved out of server.js), for every truce and war the
// realm makes: the King's truce, the King's march, a story's war, a rising. Diplomacy between two houses lives
// in Freeciv itself; Freeciv 3.2's Lua and server commands can't change it (3.3 adds Player:cancel_pact and
// add_love; docs/research/freeciv-leverage-2026-11-12.md), but its save holds it: save, set both players'
// diplstate rows, and resume from that save. Freeciv then keeps it (a ceasefire ends by itself; a war lasts
// until its AI makes peace).
// The bridge lends what it owns (realm): proc() (Freeciv running), busy()/hold(v) (a realm switch or reload
// under way), stop()/start() (Freeciv), newestSave(), saves (the realm's save folder), turn(), timeReload(t0).
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { editRow } from "./savefile.js";

// pairs: [[houseA, houseB, seasons, state], ...] (state "Cease-fire", the default, or "War"), one reload.
export async function write(realm, pairs) {
  if (!realm.proc() || realm.busy() || !pairs.length) return false;
  realm.hold(true);
  const t0 = Date.now();
  try {
    await realm.stop();
    const save = realm.newestSave();
    if (!save) return false;
    let text = zlib.zstdDecompressSync(fs.readFileSync(save)).toString();
    for (const [a, b, turns = 16, state = "Cease-fire"] of pairs) text = setDipl(setDipl(text, a, b, turns, state), b, a, turns, state);
    const out = path.join(realm.saves, `realm-T${String(realm.turn() ?? 0).padStart(4, "0")}-diplomacy-${Date.now()}.sav.zst`);
    fs.writeFileSync(out, zlib.zstdCompressSync(Buffer.from(text)));
    return true;
  } finally {
    realm.start();
    realm.hold(false);
    // The hitch: how long the realm was without Freeciv while the diplomacy went in.
    realm.timeReload(t0);
  }
}

// A truce or a war, [houseA, houseB, seasons, state]: written now behind a sitting court, where the realm is
// already held and the card covers the screen; otherwise it waits for the next sitting (court.js sends them).
export function now(realm, meta, pair) {
  if (meta?.court?.sitting != null) write(realm, [pair]).catch((e) => console.log("diplomacy:", e.message));
  else (meta.pendingDiplomacy ??= []).push(pair);
}

// Player p's diplstate toward player q. A ceasefire: Freeciv's AI keeps its own war plan per rival (the "ai"
// table: love, spam, countdown, war_reason, ...); left alone it declares war again on its first turn, so the
// King's truce also drops the plan: no countdown, no reason (DAI_WR_NONE = 5). The grudge stays, cooled a
// tenth: a truce stops the swords, not the hatred, and war may come back when it ends. A war: the rows say
// "War", and each side's AI fights it as its own.
export function setDipl(text, p, q, turns, state = "Cease-fire") {
  const war = state === "War";
  text = editRow(text, p, "diplstate", q, (c) => {
    c[0] = war ? '"War"' : '"Cease-fire"';
    c[1] = war ? '"War"' : '"Cease-fire"';
    c[3] = war ? "0" : String(turns);
    c[4] = "0";
  });
  if (war) return text;
  return editRow(text, p, "ai", q, (c) => {
    const love = Number(c[0]) || 0;
    c[0] = String(love < 0 ? Math.round(love * 0.9) : love);
    c[2] = "-1";
    c[3] = "5";
  });
}

// One side of a pair as a new realm opens (fresh.js deals the openings): Freeciv's state and its AI's feelings and
// war plan.
export function setPair(text, p, q, state, turn, turnsLeft, love) {
  text = editRow(text, p, "diplstate", q, (c) => {
    c[0] = `"${state}"`;
    if (state !== "War") c[1] = `"${state}"`;
    if (c[2] === "0") c[2] = String(turn);  // they know each other now
    c[3] = String(turnsLeft);
    c[4] = "0";
  });
  return editRow(text, p, "ai", q, (c) => {
    c[0] = String(love);
    c[2] = "-1";  // no war already planned
    c[3] = "5";   // DAI_WR_NONE
  });
}
