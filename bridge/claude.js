// Local language model for the moments that matter: a character's pivotal
// choice in their own voice, and turning the King's mood decrees ("everyone is
// more aggressive", "make Thornvale diplomatic") into numbers. Runs through the
// Off Grid AI Desktop local model gateway (OpenAI-compatible, on-device, free),
// always with Omni 2B or Omni 1.7B.
// If the gateway isn't running, callers fall back to the rule-based choice.

// The gateway's port moves between dev runs (7878 by default); find it by its /health name.
const GATEWAYS = [process.env.OFFGRID_URL, ...Array.from({ length: 8 }, (_, i) => `http://127.0.0.1:${7878 + i}/v1`)].filter(Boolean);

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
      if (!(r.ok && /off grid/i.test((await r.json()).name ?? ""))) continue;
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

async function complete(system, prompt, maxTokens = 220, retry = true, turns = []) {
  const first = await completeOnce(system, prompt, maxTokens, turns);
  if (first || !retry) return first;
  // The gateway may have been loading its model, or moved port; try once more.
  await new Promise((r) => setTimeout(r, 3000));
  return completeOnce(system, prompt, maxTokens, turns);
}

// Plain words, not JSON: what someone says aloud. Small models speak far
// better when they aren't also filling in a form.
async function say(system, turns, prompt, maxTokens = 160) {
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
  return complete(system, prompt);
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
    320,
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

// One of the common folk, told in full: a short story in their own life,
// woven from what has really happened in their town.
export async function folkTale(person, town, house, events) {
  const out = await complete(
    "You write short, grounded vignettes about ordinary people in a medieval realm. Plain, concrete, unsentimental; no fantasy clichés, no modern words.",
    `Person: ${person.name}, ${person.age}, ${person.woman ? "woman" : "man"}, ${person.trade} in ${town} (lands of ${house}). By nature ${person.nature ?? "ordinary"}. ${person.family}. Known for: ${person.past}. Wants: ${person.wants}.
What has happened in ${town} and the realm lately:
${events.map((e) => "- " + e).join("\n") || "- nothing much; quiet years"}
Write their story in 4 to 6 sentences, third person, past and present, tying their life to one or two of those events where it fits naturally. Let their nature show in what they do and say. Then one line they might say to a stranger, in their voice.
Return {"story": "...", "says": "..."}`,
    420,
  );
  return out && out.story ? { story: String(out.story), says: String(out.says ?? "") } : null;
}

// Someone in the realm answers you, face to face, in their own voice. Small
// models follow a conversation best as real turns: a short persona, what was
// said before as back-and-forth, and the latest words last, to be answered.
export async function speak(person, town, house, you, events, story, past, said) {
  const persona = `You are ${person.name}, ${person.age}, a ${person.woman ? "woman" : "man"}, ${person.trade} in ${town} (lands of ${house}). By nature ${person.nature ?? "ordinary"}; ${person.family}; you want ${person.wants}.${story ? ` ${story.split(". ").slice(0, 2).join(". ")}.` : ""}
Lately: ${events.slice(-3).join(" ") || "quiet seasons."}
You are talking with ${you.name}${you.lord ? ", your lord" : ""}. Call them "${you.address ?? "stranger"}". Gritty medieval realm. Reply with only what you say aloud: one to three full sentences in plain speech of the period, answering exactly what they just said. No narration, no quotation marks.`;
  const turns = past.slice(-6).map((l) => ({ role: l.who === person.name ? "assistant" : "user", content: l.text }));
  const reply = await say(persona, turns, said);
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
    6,
  );
  const n = Number(String(pick ?? "").match(/\d+/)?.[0]);
  const chosen = options[n - 1];
  return chosen ? { option: chosen.id } : null;
}

// The petitioner hears the King's ruling and answers him to his face.
export async function reactTo(petition, who, words, option) {
  const chosen = (petition.options ?? []).find((o) => o.id === option);
  if (!who || !chosen) return "";
  return (await say(
    `You are ${who.name} of ${who.house}, by nature ${(who.traits ?? []).join(", ") || "proud"}. You came to the King's court: ${petition.text} The King has ruled: ${chosen.label ?? chosen.id}. You are NOT the King; you answer him. Reply to his face with only what you say aloud: one or two sentences, plain speech of the period, as your nature demands. No narration, no quotation marks.`,
    [],
    `The King says: "${words}"`,
    90,
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
