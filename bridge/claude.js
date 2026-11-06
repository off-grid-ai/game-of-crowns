// Local language model for the moments that matter: a character's pivotal
// choice in their own voice, and turning the King's mood decrees ("everyone is
// more aggressive", "make Thornvale diplomatic") into numbers. Runs through the
// Off Grid AI Desktop local model gateway (OpenAI-compatible, on-device, free),
// always with Omni 2B or Omni 1.7B.
// If the gateway isn't running, callers fall back to the rule-based choice.

// The gateway's port moves between dev runs (7878 by default); find it by its /health name.
// A model the realm was pointed at by hand (GOC_LLM_URL), if any: used
// only when Off Grid AI Desktop isn't running, which also brings voices.
const OWN = process.env.GOC_LLM_URL;
const GATEWAYS = [process.env.OFFGRID_URL, ...Array.from({ length: 8 }, (_, i) => `http://127.0.0.1:${7878 + i}/v1`), OWN].filter(Boolean);

let lastWatched = 0;
let base = null;

// Only spend the Mac's CPU on voices while the player is watching.
export function watched() {
  lastWatched = Date.now();
}

export function isWatched() {
  return Date.now() - lastWatched < 15000;
}

export function usageToday() {
  return { engine: "Off Grid AI (local)", gateway: base, model, cost: 0 };
}

// Only Off Grid's small Omni models write for the realm: Omni 2B first, then
// Omni 1.7B (OFFGRID_MODEL overrides). Text only; no images or video.
const WANT = [process.env.OFFGRID_MODEL, /omni.*2b/i, /omni.*1\.?7b/i].filter(Boolean);
let model = null;
let warned = false;

async function gateway() {
  if (base && model) return base;
  for (const url of GATEWAYS) {
    try {
      const r = await fetch(url.replace(/\/v1$/, "/health"), { signal: AbortSignal.timeout(1500) });
      if (!(r.ok && (url === OWN || /off grid/i.test((await r.json()).name ?? "")))) continue;
      const list = await (await fetch(`${url}/models`, { signal: AbortSignal.timeout(3000) })).json();
      const ids = (list.data ?? list.models ?? []).map((m) => m.id ?? m.name ?? "").filter(Boolean);
      model = null;
      for (const w of WANT) {
        model = ids.find((id) => (typeof w === "string" ? id === w : w.test(id))) ?? null;
        if (model) break;
      }
      if (!model) {
        if (!warned) console.error(`offgrid: Omni 2B / Omni 1.7B isn't loaded in Off Grid AI (gateway has: ${ids.join(", ") || "none"}); the realm decides by its rules until it is.`);
        warned = true;
        return null;
      }
      warned = false;
      return (base = url);
    } catch { /* try the next */ }
  }
  return null;
}

// One queue for every call to the model. It has no call caps but one
// throughput, so thinking follows attention: hot (the player is waiting, or the
// mind is in front of them) before warm (the court's seasons, the stories,
// minds on screen) before cold. A call that has waited climbs a level every
// 30 seconds, so nothing starves.
const RANK = { hot: 0, warm: 1, cold: 2 };
const SLOTS = Math.max(1, Number(process.env.GOC_MODEL_SLOTS) || 1);
const queue = [];
const timings = [];
let running = 0;

function queued(pri, job) {
  return new Promise((resolve) => {
    queue.push({ pri: RANK[pri] === undefined ? "warm" : pri, at: Date.now(), job, resolve });
    pump();
  });
}

function pump() {
  while (running < SLOTS && queue.length) {
    const now = Date.now();
    const score = (q) => RANK[q.pri] - (now - q.at) / 30000;
    let best = 0;
    for (let i = 1; i < queue.length; i++) if (score(queue[i]) < score(queue[best])) best = i;
    const q = queue.splice(best, 1)[0];
    const start = Date.now();
    running++;
    q.job().catch(() => null).then((out) => {
      running--;
      timings.push({ pri: q.pri, waitMs: start - q.at, runMs: Date.now() - start, at: start });
      if (timings.length > 300) timings.shift();
      q.resolve(out);
      pump();
    });
  }
}

// What the queue holds now and how long calls of each level waited lately.
export function modelQueue() {
  const waiting = { hot: 0, warm: 0, cold: 0 };
  for (const q of queue) waiting[q.pri]++;
  const levels = {};
  for (const pri of Object.keys(RANK)) {
    const t = timings.filter((x) => x.pri === pri);
    if (!t.length) continue;
    const avg = (k) => Math.round(t.reduce((a, x) => a + x[k], 0) / t.length);
    levels[pri] = { calls: t.length, waitMs: avg("waitMs"), runMs: avg("runMs"), maxWaitMs: Math.max(...t.map((x) => x.waitMs)) };
  }
  return { slots: SLOTS, running, waiting, levels, recent: timings.slice(-30) };
}

async function complete(system, prompt, maxTokens = 220, retry = true, turns = [], pri = "warm") {
  const first = await queued(pri, () => completeOnce(system, prompt, maxTokens, turns));
  if (first || !retry) return first;
  // The gateway may have been loading its model, or moved port; try once more.
  await new Promise((r) => setTimeout(r, 3000));
  return queued(pri, () => completeOnce(system, prompt, maxTokens, turns));
}

// Plain words, not JSON: what someone says aloud. Small models speak far
// better when they aren't also filling in a form.
function say(system, turns, prompt, maxTokens = 160, pri = "warm") {
  return queued(pri, () => sayOnce(system, turns, prompt, maxTokens));
}

// A mind thinking in plain words, at its attention's level (minds.js).
export function think(system, prompt, pri = "cold", maxTokens = 80) {
  return say(system, [], prompt, maxTokens, pri);
}

async function sayOnce(system, turns, prompt, maxTokens) {
  const url = await gateway();
  if (!url) return null;
  try {
    const res = await fetch(`${url}/chat/completions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(90000),
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: system }, ...turns, { role: "user", content: prompt }],
        max_tokens: maxTokens,
        temperature: 0.8,
        chat_template_kwargs: { enable_thinking: false },
        reasoning_budget: 0,
      }),
    });
    if (!res.ok) {
      base = null;
      return null;
    }
    const text = String((await res.json()).choices?.[0]?.message?.content ?? "").trim();
    // Keep only the speech: no quotes, no "Name:" prefix, no stage directions.
    return text.replace(/^[\w .'-]{1,40}:\s*/, "").replace(/\*[^*]*\*/g, "").replace(/^["“]|["”]$/g, "").trim() || null;
  } catch (err) {
    console.error("offgrid:", err.message);
    base = null;
    return null;
  }
}

async function completeOnce(system, prompt, maxTokens, turns = []) {
  const url = await gateway();
  if (!url) return null;
  try {
    const res = await fetch(`${url}/chat/completions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(90000), // the first call may wait for the model to load
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: system }, ...turns, { role: "user", content: prompt + "\nRespond with only the JSON object." }],
        max_tokens: maxTokens,
        temperature: 0.8,
        chat_template_kwargs: { enable_thinking: false },
        reasoning_budget: 0,
      }),
    });
    if (!res.ok) {
      base = null;
      return null;
    }
    const data = await res.json();
    const text = data.choices?.[0]?.message?.content ?? "";
    return JSON.parse(text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1));
  } catch (err) {
    console.error("offgrid:", err.message);
    base = null;
    return null;
  }
}

// A character's pivotal decision, in their own voice. The model is local and
// free, so every one goes to it; rules decide only if it isn't running.
export async function decide(system, prompt) {
  const out = await complete(system, prompt);
  if (out && typeof out.line === "string") out.line = tidyLine(out.line);
  return out;
}

// What a player reads from the small local model, kept readable: at most two
// sentences, no wrapping quotes, and a line that loops on itself ("a liege's
// liege, not my liege's liege") or repeats a phrase is dropped, not shown.
export function tidyLine(text) {
  let t = String(text ?? "").replace(/\s+/g, " ").trim().replace(/^["'“]+|["'”]+$/g, "");
  const sentences = t.match(/[^.!?]+[.!?]+|[^.!?]+$/g) ?? [];
  // The chronicle wraps a line in its own quotes: none inside it.
  t = sentences.slice(0, 2).map((x) => x.trim()).join(" ").replace(/["“”]/g, "").replace(/\s+/g, " ").trim();
  // Content words only: a looping line repeats a pair of them, or one word thrice.
  const words = t.toLowerCase().replace(/[^a-z' -]/g, " ").split(/\s+/).filter((w) => w.length > 3);
  const pairs = new Set();
  const counts = {};
  for (let i = 0; i < words.length; i++) {
    counts[words[i]] = (counts[words[i]] ?? 0) + 1;
    if (counts[words[i]] >= 3) return "";
    if (i + 1 < words.length) {
      const pair = `${words[i]} ${words[i + 1]}`;
      if (pairs.has(pair)) return "";
      pairs.add(pair);
    }
  }
  return t.length > 220 ? t.slice(0, t.lastIndexOf(" ", 217)) + "…" : t;
}

const TRAITS = ["ambitious", "honourable", "greedy", "vengeful", "pious", "cunning", "craven", "brave", "lustful", "content", "paranoid", "generous", "proud", "patient", "wrathful", "just"];

// The King's decree in words -> who it applies to and how they change.
// Scope can be the whole realm, houses, named characters, or a group.
export async function moodFrom(text, houses, names = []) {
  const out = await complete(
    "You turn a king's decree about the people of a medieval realm into a precise JSON instruction for a simulation. Pick the narrowest scope that matches the decree.",
    `Decree: "${text}"
Great houses: ${houses.join(", ")}.
Some character names: ${names.slice(0, 60).join(", ")}.
Return {
 "scope": "all" | "houses" | "characters" | "group",
 "houses": [exact house names, if scope is houses],
 "characters": [exact character names, if scope is characters],
 "group": {"rank": "lord"|"bannerman"|"heir"|"any", "gender": "male"|"female"|"any", "minAge": n, "maxAge": n, "trait": "a trait or empty"} (if scope is group),
 "aggression": n, "loyalty": n, "ambition": n, "caution": n, "cunning": n, "piety": n, "greed": n,
 "addTraits": [traits to give, from: ambitious honourable greedy vengeful pious cunning craven brave lustful content paranoid generous proud patient wrathful just],
 "removeTraits": [traits to take away],
 "goal": "a new personal goal in first person, or empty",
 "summary": "one short sentence describing the change"
}
Numbers are integers from -50 to 50 (0 = unchanged). "Strategic" = more cunning and caution. "Diplomatic" = less aggression, more caution and cunning.`,
    320, true, [], "hot",
  );
  if (!out) return null;
  const clamp = (v) => Math.max(-50, Math.min(50, Math.round(Number(v) || 0)));
  const lower = (a) => (Array.isArray(a) ? a.map((x) => String(x).toLowerCase()) : []);
  const scope = ["all", "houses", "characters", "group"].includes(out.scope) ? out.scope : "all";
  return {
    id: `d${Date.now().toString(36)}`, text, scope, summary: String(out.summary ?? text),
    houses: houses.filter((h) => lower(out.houses).some((x) => x.includes(h.replace("House ", "").toLowerCase()))),
    characters: lower(out.characters),
    group: out.group ?? {},
    aggression: clamp(out.aggression), loyalty: clamp(out.loyalty), ambition: clamp(out.ambition),
    caution: clamp(out.caution), cunning: clamp(out.cunning), piety: clamp(out.piety), greed: clamp(out.greed),
    addTraits: lower(out.addTraits).filter((t) => TRAITS.includes(t)), removeTraits: lower(out.removeTraits).filter((t) => TRAITS.includes(t)), goal: String(out.goal ?? "").trim(),
  };
}

// Without the local model, the King's word is still read: by its keywords.
// Cruder than the model, but the realm never waits on it.
const WORDS = [
  [/aggress|warlike|war|bloody|restless|bold|fierce|angry/, { aggression: 30 }],
  [/peace|calm|gentle|diplomat|quiet/, { aggression: -30, caution: 20 }],
  [/loyal|faithful to|obedien/, { loyalty: 30 }],
  [/disloyal|rebel|defiant|treacher/, { loyalty: -30 }],
  [/ambiti|hungry for|grasping for power/, { ambition: 30 }],
  [/content|humble|satisfied/, { ambition: -30 }],
  [/careful|cautious|wary|strategic/, { caution: 30, cunning: 15 }],
  [/reckless|rash/, { caution: -30 }],
  [/cunning|scheming|clever|sly/, { cunning: 30 }],
  [/pious|devout|godly|holy/, { piety: 30 }],
  [/godless|impious/, { piety: -30 }],
  [/greed|grasping|miserly/, { greed: 30 }],
  [/generous|charitable|open-handed/, { greed: -30 }],
];

export function moodRules(text, houses, names = []) {
  const t = String(text).toLowerCase();
  const out = { aggression: 0, loyalty: 0, ambition: 0, caution: 0, cunning: 0, piety: 0, greed: 0 };
  for (const [re, add] of WORDS) {
    const m = re.exec(t);
    if (!m) continue;
    // "less loyal", "not so warlike": a negation just before the word turns it round.
    const flip = /\b(less|not|no longer|fewer|not so)\s+(\w+\s+)?$/.test(t.slice(0, m.index)) ? -1 : 1;
    for (const [k, v] of Object.entries(add)) out[k] += v * flip;
  }
  const hs = houses.filter((h) => t.includes(h.replace("House ", "").toLowerCase()));
  const cs = names.filter((n) => t.includes(n.toLowerCase())).map((n) => n.toLowerCase());
  const rank = /\blords?\b/.test(t) ? "lord" : /bannerm[ae]n/.test(t) ? "bannerman" : /\bheirs?\b/.test(t) ? "heir" : null;
  const scope = cs.length ? "characters" : hs.length ? "houses" : rank ? "group" : "all";
  const clamp = (v) => Math.max(-50, Math.min(50, v));
  return {
    id: `d${Date.now().toString(36)}`, text, scope, summary: String(text).trim(),
    houses: hs, characters: cs, group: rank ? { rank, gender: "any" } : {},
    ...Object.fromEntries(Object.entries(out).map(([k, v]) => [k, clamp(v)])),
    addTraits: [], removeTraits: [], goal: "",
  };
}

// A townsperson's life without the model: told plainly from what the realm
// knows of them. The model, when it's there, tells it better later.
export function folkPlain(person, town) {
  const they = person.woman ? "She" : "He";
  return {
    story: `${person.name} is a ${person.trade} in ${town}, ${person.age} years old, ${person.family}. ${person.past ? person.past.charAt(0).toUpperCase() + person.past.slice(1) + "." : ""} ${they} wants ${person.wants}.`.replace(/\s+/g, " ").trim(),
    says: "",
  };
}

// One of the common folk, told in full: a short story in their own life,
// woven from what has really happened in their town.
export async function folkTale(person, town, house, events) {
  // A small model given the realm's news retells all of it: hand it one
  // happening at most, and ask for their life, not the realm's.
  const event = events.find(Boolean);
  const out = await complete(
    "You write short, grounded vignettes about ordinary people in a medieval realm. Plain, concrete, unsentimental; no fantasy clichés, no modern words. You write about the one person, never about lords, houses or wars they only heard of.",
    `Person: ${person.name}, ${person.age}, ${person.woman ? "woman" : "man"}, ${person.trade} in ${town} (lands of ${house}). By nature ${person.nature ?? "ordinary"}. ${person.family}. Known for: ${person.past}. Wants: ${person.wants}.
${event ? `Something that happened nearby lately: ${event}` : "The seasons here have been quiet."}
Write their story in 3 or 4 short sentences, third person: their work, their household, what they want and why. Mention the happening only if it changed their own day, in a few words. Let their nature show in what they do. Then, separately, one line they might say to a stranger, in their voice.
Return {"story": "...", "says": "..."}`,
    300, true, [], "hot",
  );
  if (!out || !out.story) return null;
  const says = String(out.says ?? "").trim();
  // The story ends before the line they'd say: that is shown on its own.
  const story = (String(out.story).match(/[^.!?]+[.!?]+['"’”]?/g) ?? [String(out.story)])
    .map((x) => x.trim())
    .filter((x) => !/might say|would say|says to (a|any) stranger/i.test(x))
    .slice(0, 4)
    .join(" ");
  return { story, says };
}

// Someone in the realm answers you, face to face, in their own voice. Small
// models follow a conversation best as real turns: a short persona, what was
// said before as back-and-forth, and the latest words last, to be answered.
export const TONGUES = { en: "English", de: "German", es: "Spanish", fr: "French", it: "Italian", pt: "Portuguese", hi: "Hindi" };

// `mind` is what their mind brings (minds.js): how they feel, what they recall of you.
export async function speak(person, town, house, you, events, story, past, said, language = "en", mind = "") {
  const persona = `You are ${person.name}, ${person.age}, a ${person.woman ? "woman" : "man"}, ${person.trade} in ${town} (lands of ${house}). By nature ${person.nature ?? "ordinary"}; ${person.family}; you want ${person.wants}.${story ? ` ${story.split(". ").slice(0, 2).join(". ")}.` : ""}
Lately: ${events.slice(-3).join(" ") || "quiet seasons."}${mind ? `\n${mind}` : ""}
You are talking with ${you.name}${you.lord ? ", your lord" : ""}. Call them "${you.address ?? "stranger"}". Gritty medieval realm. Reply with only what you say aloud: one to three full sentences in plain speech of the period, answering exactly what they just said. No narration, no quotation marks.${language !== "en" ? ` Speak only in ${TONGUES[language] ?? "English"}.` : ""}`;
  const turns = past.slice(-6).map((l) => ({ role: l.who === person.name ? "assistant" : "user", content: l.text }));
  const reply = await say(persona, turns, said, 160, "hot");
  return reply ? { reply } : null;
}

// The King's ruling in his own words -> which of the petition's choices he
// means, and what the petitioner says back to his face. A small model picks
// reliably from a numbered list with a one-number answer, and speaks well in
// plain words; so it's two short asks, not one form.
export async function ruleFrom(petition, who, words) {
  const options = petition.options ?? [];
  if (!options.length) return null;
  const list = options.map((o, i) => `${i + 1}. ${o.label ?? o.id}${o.hint ? ` (${o.hint})` : ""}`).join("\n");
  const pick = await say(
    "You decide which ruling a king means. Answer with only the number of the ruling.",
    [],
    `Petition: ${petition.text}\nRulings:\n${list}\nThe king says: "${words}"\nWhich ruling does the king mean? Only the number.`,
    6, "hot",
  );
  const n = Number(String(pick ?? "").match(/\d+/)?.[0]);
  const chosen = options[n - 1];
  return chosen ? { option: chosen.id } : null;
}

// The petitioner hears the King's ruling and answers him to his face.
export async function reactTo(petition, who, words, option, language = "en") {
  const chosen = (petition.options ?? []).find((o) => o.id === option);
  if (!who || !chosen) return "";
  return (await say(
    `You are ${who.name} of ${who.house}, by nature ${(who.traits ?? []).join(", ") || "proud"}. You came to the King's court: ${petition.text} The King has ruled: ${chosen.label ?? chosen.id}. You are NOT the King; you answer him. Reply to his face with only what you say aloud: one or two sentences, plain speech of the period, as your nature demands. No narration, no quotation marks.${language !== "en" ? ` Speak only in ${TONGUES[language] ?? "English"}.` : ""}`,
    [],
    `The King says: "${words}"`,
    90, "hot",
  )) ?? "";
}

// Kokoro's voices on the Off Grid gateway, by language (the realm's tongue)
// and sex. Each person keeps one voice for life: picked from their name.
const VOICES = {
  en: { female: ["bf_emma", "af_sarah", "af_heart", "af_river"], male: ["bm_daniel", "am_michael", "am_adam"] },
  de: { female: ["df_anna"], male: ["bm_daniel"] },
  es: { female: ["ef_dora"], male: ["em_alex"] },
  fr: { female: ["ff_siwis"], male: ["bm_daniel"] },
  it: { female: ["if_sara"], male: ["im_nicola"] },
  pt: { female: ["pf_dora"], male: ["pm_mateusz"] },
  hi: { female: ["hf_alpha"], male: ["hm_omega", "hm_psi"] },
};

export function voiceFor(who, language = "en") {
  const set = VOICES[language] ?? VOICES.en;
  const list = who.gender === "female" || who.woman ? set.female : set.male;
  let h = 0;
  for (const ch of String(who.name ?? "")) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return list[h % list.length];
}

// Text to speech through the gateway: WAV bytes, or null if it isn't there.
export async function speech(text, voice) {
  const url = await gateway();
  if (!url) return null;
  try {
    const res = await fetch(`${url}/audio/speech`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(60000),
      body: JSON.stringify({ input: text, voice }),
    });
    return res.ok ? Buffer.from(await res.arrayBuffer()) : null;
  } catch (err) {
    console.error("offgrid speech:", err.message);
    return null;
  }
}

// Speech to text through the gateway (Whisper): the words, or null.
export async function transcribe(wav, language = "en") {
  const url = await gateway();
  if (!url) return null;
  try {
    const form = new FormData();
    form.append("file", new Blob([wav], { type: "audio/wav" }), "speech.wav");
    if (language) form.append("language", language);
    const res = await fetch(`${url}/audio/transcriptions`, { method: "POST", body: form, signal: AbortSignal.timeout(60000) });
    if (!res.ok) return null;
    const out = await res.json();
    return String(out.text ?? "").trim() || null;
  } catch (err) {
    console.error("offgrid hearing:", err.message);
    return null;
  }
}

// For the settings page: is Off Grid there, which model writes, and can it
// speak and listen.
export async function aiStatus() {
  const url = await gateway();
  const out = { gateway: null, model: null, words: false, voices: false, hearing: false, note: "" };
  for (const g of GATEWAYS) {
    try {
      const r = await fetch(g.replace(/\/v1$/, "/health"), { signal: AbortSignal.timeout(1500) });
      if (!r.ok) continue;
      const h = await r.json();
      if (!/off grid/i.test(h.name ?? "")) continue;
      out.gateway = g;
      out.voices = h.modalities?.speech === "ready";
      out.hearing = h.modalities?.transcription === "ready";
      break;
    } catch { /* next */ }
  }
  out.model = url ? model : null;
  out.words = Boolean(url && model);
  out.note = !out.gateway ? "Give the lords their own words: run Off Grid AI."
    : !out.words ? "Load Omni 2B in Off Grid AI to give the lords their own words."
    : "";
  return out;
}

// --- story arcs ---------------------------------------------------------------------

// One of the people in a story arc speaks as a beat of it happens. The arc
// decides what happens and its line is fixed; this is the one line of colour
// in their voice, or nothing.
export async function arcLine(who, thread, happening, alsoIn = []) {
  const rank = who.rank === "lord" ? (who.gender === "female" ? "Lady" : "Lord") : who.folk ? `a ${who.station} in the lands` : who.rank;
  const said = await say(
    `You are ${who.name}, ${who.age}, ${who.gender === "female" ? "a woman" : "a man"}, ${rank} of ${who.house}. By nature ${(who.traits ?? []).join(", ") || "ordinary"}. You want to ${who.goals?.[0]?.text ?? "endure"}. You remember: ${(who.memories ?? []).slice(-4).join(" ") || "little worth telling"}${alsoIn.length ? ` You are also caught up in ${alsoIn.join(" and ")}.` : ""}
Gritty medieval realm. You are living through ${thread}. Speak as yourself, in the first person, to someone beside you as it happens: one short sentence, plain speech of the period, as your nature demands. Don't describe what is happening; say what you feel or mean to do about it. No narration, no quotation marks, no names of speakers.`,
    [],
    `What is happening: ${happening}`,
    60,
  );
  return colour(said, happening, who.name);
}

// One sentence at most, and none if it only tells the beat over again or
// speaks as somebody else.
export function colour(said, happening, name = "") {
  const first = String(said ?? "").match(/^[^.!?]+[.!?]?/)?.[0]?.trim() ?? "";
  if (first.length < 8) return null;
  // A small model sometimes speaks as someone else in the beat: "I am <another>".
  const claimed = first.match(/\bI am ([A-Z][a-z]+(?: [A-Z][a-z]+)?)/)?.[1];
  if (claimed && name && !name.startsWith(claimed.split(" ")[0])) return null;
  const bag = (x) => String(x).toLowerCase().match(/[a-z']{4,}/g) ?? [];
  const told = new Set(bag(happening));
  const words = bag(first);
  const echo = words.length ? words.filter((w) => told.has(w)).length / words.length : 1;
  return echo > 0.5 ? null : first.slice(0, 160).replace(/[,;:]?\s*$/, (m) => (/[.!?]$/.test(first.slice(0, 160)) ? "" : "."));
}

// The King describes a story in plain words; the model picks the arc whose
// shape fits it best and names it. The beats keep their tested lines: a small
// model retells them badly, so the only words it adds are each speaker's one
// line of colour as the story plays.
// A beat for the player's own story, from Off Grid AI: a fresh one when the box
// is empty, or the player's own line carried on and finished. People only by
// their tags in braces ({warden}), so the story fills in who they are.
export async function beatIdea({ name, about, roles, beats, draft }) {
  const people = roles.map((r) => `{${r.id}} (${r.label})`).join(", ");
  const before = beats.length ? `\nAlready in the story:\n${beats.slice(-4).map((b) => `- ${b}`).join("\n")}` : "";
  const ask = draft
    ? `Carry this on and finish it, keeping its words: "${draft}"`
    : "Write one new turn of the story, something that could happen next.";
  const out = await say("You write one turn of a story in a medieval realm's chronicle: one or two plain, specific sentences, at most 40 words, no quotation marks. Name people only by their tags in braces, exactly as given; never invent other names for them.", [],
    `Story: ${name}. ${about}\nPeople: ${people}${before}\n${ask}`, 90);
  return String(out ?? "").replace(/^["“]|["”]$/g, "").replace(/\s+/g, " ").trim().slice(0, 300) || null;
}

// A premise for a story of the player's own: from the tags they picked (or a
// surprise when none), or their own words carried on and finished.
export async function premiseIdea({ tags, draft }) {
  const feel = tags.length ? `Its tags: ${tags.join(", ")}.` : "Surprise me: any threat to a medieval king's throne.";
  const ask = draft ? `Carry this premise on and finish it, keeping its words: "${draft}"` : `Write the premise. ${feel}`;
  const out = await say("You write premises for stories that threaten a king's throne in a medieval realm: one or two vivid, specific sentences, at most 35 words, no names of real places, no quotation marks.", [], ask, 80);
  return String(out ?? "").replace(/^["“]|["”]$/g, "").replace(/\s+/g, " ").trim().slice(0, 300) || null;
}

// Any free-text box in the game: Off Grid AI writes it fresh, or carries on and
// finishes what the player began. Each kind says what the box is for; context is
// what the box knows (the story, the petition, the house…).
const WRITE = {
  "chronicle-name": ["You name chronicles of a medieval reign: two to five evocative words, no quotation marks.", 16],
  "mood": ["You set the opening mood of a medieval realm in one short clause: its peace, its fears, who trusts whom. At most 20 words.", 50],
  "character-name": ["You name people of a medieval realm: a given name and a family or place name, with a title if they'd have one. Only the name.", 16],
  "character-traits": ["You describe a medieval person's quirks as a short comma-separated list of three or four, at most 12 words.", 30],
  "character-past": ["You write one line of a medieval person's past that they'd always remember: specific, at most 25 words.", 60],
  "ruling": ["You are a medieval King answering a petitioner at court, in the first person, in one or two plain sentences, at most 35 words. Rule decisively.", 80],
  "speech": ["You are a medieval King speaking to someone you've met in your realm: one short, natural line, at most 20 words, in character.", 50],
};
export async function writeFor(kind, context, draft) {
  const [system, tokens] = WRITE[kind] ?? [];
  if (!system) return null;
  const ask = draft ? `${context}\nCarry this on and finish it, keeping its words: "${draft}"` : `${context}\nWrite it.`;
  const out = await say(`${system} No quotation marks.`, [], ask, tokens);
  return String(out ?? "").replace(/^["“]|["”]$/g, "").replace(/\s+/g, " ").trim().slice(0, 300) || null;
}

export async function arcFromWords(words, shapes) {
  if (shapes.length === 1) return arcNamed(words, shapes[0]);
  const list = shapes.map((s, i) => `${i + 1}. ${s.name}: ${s.about}`).join("\n");
  const pick = await say("You match a story idea to the closest story shape. Answer with only the number.", [], `Story idea: "${words}"\nShapes:\n${list}\nWhich shape fits the idea best? Only the number.`, 6);
  const shape = shapes[Number(String(pick ?? "").match(/\d+/)?.[0]) - 1] ?? null;
  return shape ? arcNamed(words, shape) : null;
}

async function arcNamed(words, shape) {
  const name = await say("You name stories in a medieval chronicle. Answer with only the name: two to five words, no quotation marks.", [], `Story: "${words}". Its name:`, 16);
  return { shape: shape.id, name: name?.replace(/["“”.]/g, "").trim().slice(0, 40) || null };
}
