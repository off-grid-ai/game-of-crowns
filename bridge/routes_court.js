// The court's routes: what stands before the King (the docket), his rulings on
// petitions (by option, or in his own words), the Hand's matter answered, the court
// and the interlude closed, and the King's voice (heard) and the realm's (spoken).
// Moved verbatim from server.js's ROUTES table (consolidation C3, step 8): each
// handler is (ctx, req, res, url). Nothing here reads server.js: the bridge's
// state and helpers come in as one context argument (routeCtx), built fresh by
// server.js on each request; the realm's state is read through it (ctx.world,
// ctx.meta...) at the moment it is used, as the handlers read it before, so a
// snapshot or a switch of chronicle during an await is seen.

import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import * as Sittings from "./court.js";
import * as chron from "./chronicles.js";
import * as names from "./names.js";
import { speech, transcribe, voiceFor } from "./claude.js";
import { body, bytes, json } from "./http_util.js";
import { weigh } from "./routes_decree.js";

export async function counselAnswer(ctx, req, res, url) {
  // The King answered the Hand's matter: it rests a year, and the next one comes up (court.js).
  const { key } = await body(req);
  return json(res, 200, Sittings.answerMatter(ctx, key));
}

export async function court(ctx, req, res, url) {
  const { inCrowns, docket } = ctx;
  // The Hand's orders each weighed before choosing: what it costs, whom it warms, whom it cools.
  const items = docket().map((x) => (x.hand && x.acts ? { ...x, acts: x.acts.map((a) => ({ ...a, weighs: weigh(ctx, a) })) } : x));
  return json(res, 200, inCrowns(items));
}

export async function hear(ctx, req, res, url) {
  // What the King said into the microphone (a WAV), as words, by Off Grid's Whisper.
  const wav = await bytes(req);
  if (wav.length < 1000) return json(res, 400, { error: "nothing was heard" });
  const text = await transcribe(wav, ctx.meta.options?.language);
  return text ? json(res, 200, { text }) : json(res, 503, { error: "Your words were lost. (The local speech model isn't running.)" });
}

export async function sayAloud(ctx, req, res, url) {
  // Someone's words, spoken aloud by Off Grid's Kokoro: a voice of their own,
  // in the realm's language. WAV bytes; cached, so a line is only made once.
  const { text, who } = await body(req);
  const line = names.shown(String(text ?? "").trim().slice(0, 600));  // spoken in the player's names
  if (!line) return json(res, 400, { error: "nothing to say" });
  const voice = voiceFor(who ?? {}, ctx.meta.options?.language);
  const dir = path.join(ctx.P.state, "voices");
  const file = path.join(dir, crypto.createHash("sha1").update(voice + "|" + line).digest("hex") + ".wav");
  if (!fs.existsSync(file)) {
    const wav = await speech(line, voice);
    if (!wav) return json(res, 503, { error: "no voice (the local speech model isn't running)" });
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(file, wav);
  }
  res.writeHead(200, { "content-type": "audio/wav" });
  return res.end(fs.readFileSync(file));
}

export async function closeInterlude(ctx, req, res, url) {
  const { hold } = ctx;
  if (ctx.meta.interlude) ctx.meta.interlude.seen = true;
  chron.saveMeta(ctx.meta);
  if (ctx.meta.court?.sitting == null) hold(false);
  return json(res, 200, { ok: true });
}

export async function close(ctx, req, res, url) {
  const { closeCourt, inCrowns, docket } = ctx;
  closeCourt(ctx.world?.turn ?? 0);
  return json(res, 200, inCrowns(docket()));
}

export async function answer(ctx, req, res, url) {
  const { rule, closeIfDone } = ctx;
  ctx.counselStale = true;
  const { id, option } = await body(req);
  const before = ctx.court?.petitions?.find((x) => x.id === id);
  const out = rule(id, option);
  closeIfDone(ctx.world?.turn ?? 0);
  // The ruling becomes the town's talk (chatter.afterRuling; the crowd thinks out loud).
  if (!out.error && before) ctx.chatter?.afterRuling(rulingFor(ctx, before, option, out.text)).catch(() => {});
  // What the ruling paid or brought in shows now (the treasury, a house's purse), as a decree's does.
  if (!out.error) setTimeout(ctx.snapshot, 600);
  return json(res, out.error ? 400 : 200, out);
}

export async function say(ctx, req, res, url) {
  // The King answers a petition in his own words; nothing happens until he confirms it (court.js).
  const [code, out] = await Sittings.say(ctx, await body(req));
  return json(res, code, out);
}

// A ruling as the town will talk of it: where, what was said, whose favour it raised or cut.
function rulingFor(ctx, p, option, text) {
  const o = (p.options ?? []).find((x) => x.id === option) ?? {};
  const house = (pid) => ctx.world?.players?.find((x) => x.id === Number(pid))?.house?.name;
  const fav = Object.entries(o.favour ?? {});
  const city = p.city ?? p.place?.id ?? ctx.world?.cities?.find((c) => c.owner === ctx.court?.people?.[p.from]?.playerId && c.capital)?.id;
  return { city, text, helps: fav.filter(([, d]) => d > 0).map(([k]) => house(k)).filter(Boolean), hurts: fav.filter(([, d]) => d < 0).map(([k]) => house(k)).filter(Boolean) };
}
