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

async function complete(system, prompt, maxTokens = 220, retry = true) {
  const first = await completeOnce(system, prompt, maxTokens);
  if (first || !retry) return first;
  // The gateway may have been loading its model, or moved port; try once more.
  await new Promise((r) => setTimeout(r, 3000));
  return completeOnce(system, prompt, maxTokens);
}

async function completeOnce(system, prompt, maxTokens) {
  const url = await gateway();
  if (!url) return null;
  try {
    const res = await fetch(`${url}/chat/completions`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(90000), // the first call may wait for the model to load
      body: JSON.stringify({
        model,
        messages: [{ role: "system", content: system }, { role: "user", content: prompt + "\nRespond with only the JSON object." }],
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

// Someone in the realm answers you, face to face, in their own voice: what they
// are, what's happened to them and their town, who you are to them, and what
// you've said to each other before. They can be warm, wary, afraid or rude.
export async function speak(person, town, house, you, events, story, past, said) {
  const out = await complete(
    "You are an ordinary person in a gritty medieval realm (tone: Game of Thrones, Vikings), speaking aloud to someone in front of you. Stay in character. Plain, concrete speech of the period: no modern words, no fantasy cliches, no narration. 1 to 3 sentences.",
    `You are ${person.name}, ${person.age}, a ${person.woman ? "woman" : "man"}, ${person.trade} in ${town}, in the lands of ${house}. By nature ${person.nature ?? "ordinary"}. ${person.family}. Known for: ${person.past}. You want: ${person.wants}.
${story ? `Your life so far: ${story}\n` : ""}Lately in ${town} and the realm:
${events.map((e) => "- " + e).join("\n") || "- quiet seasons"}
You are speaking with ${you.name}${you.title ? `, ${you.title}` : ""} of ${you.house}${you.lord ? ", who rules this town; your lord" : ""}. Speak to them as your station and your nature demand.
${past.length ? "What you and they have said before:\n" + past.map((l) => `${l.who}: ${l.text}`).join("\n") + "\n" : ""}They say to you now: "${said}"
Return {"reply": "what you say back", "feeling": "one word: how you feel toward them now"}`,
    220,
  );
  return out && out.reply ? { reply: String(out.reply).replace(/^"|"$/g, ""), feeling: String(out.feeling ?? "") } : null;
}
