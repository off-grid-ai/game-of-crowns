# r/LocalLLaMA post: Game of Crowns (draft, not posted)

- **The body is Mac's final copy (6 Nov), unchanged.** It's the same text as docs/buzz/hn/POST.md.
- **What this sub needs is added around it, from STUDY.md and RUBRIC.md:**
  - the title
  - the flair
  - the video
  - a short second section with the disclosure and the technical facts
- Every technical claim is checked against the code (sources at the bottom).
- Mac answers the model questions in the thread himself.

## Read this first: should it go up at all?
- **Mac's own call (brief.md, 5 Nov):** "Not r/LocalLLaMA or the local-AI crowd: Mac has exhausted them and they're allergic to him there."
- **His record there agrees.**
  - His last six r/LocalLLaMA posts scored 0, 0, 0, 0, 0 and 1. Most were sent to four to six subs the same day, with no replies from him.
  - That's the pattern the April rules were built to remove.
- **What has worked for him there:** a video plus one hard number on modest hardware (46 and 37 points, March).
- **If he posts it:**
  1. Post it to r/LocalLLaMA only, not cross-posted to other subs that day.
  2. Upload the video natively, in the post.
  3. Keep the disclosure line in the post itself. It decides whether a post survives Rule 4: the 875-word "NPCs that remember, gossip, and hold grudges" post was removed under it.
  4. Nothing about Off Grid's Pro tier beyond that one line. No keys, no "first 10 people".
  5. Mac stays in the thread for the first few hours. Every winner's OP answered "which model, what hardware" there.

## Title
**Recommended, A (8/8 on RUBRIC.md):**
A 2B model on your Mac writes what the lords and villagers say in this kingdom sim, and the rules decide what actually happens

**Option B (7/8):** the HN title with the model added:
A medieval kingdom sim where history names you for how you ruled. The lords' words come from an optional 2B model on your Mac.

**HN title as is (5/8 here):** "A medieval kingdom sim where history names you for how you ruled".
- Right for players and HN.
- But titles here without a model or size reach 50+ at 6.3%, against 14.1% with one.

**Why A:**
- It answers what this sub asks every LLM game: who owns the truth. "How do you ensure determinism?" and "what happens when an NPC asserts a fact the deterministic layer never authorized?" both came up.
- Warrior Quest scored 175 with the same shape: "where the model only plays NPCs and the actual game state stays deterministic".

## Flair
**Showcase.** It replaced "I Built A Thing" on 14 Oct 2026. Its live posts score a median of 13, and 28.7% reach 50+, against 6 and 18.9% under the old flair.

## Video (the gate: STUDY.md §1)
- 40 to 60 seconds of real play, uploaded to Reddit, not a YouTube link.
- **Show:** a petitioner at court answering a ruling typed in your own words, then the camera low over a town while villagers' lines appear over their heads.
- **Leave out:** debug panels. Don't use the painted launch film; this sub wants the model's output in the game.

## Body (paste as plain text; one blank line between paragraphs)

Game of Crowns is a medieval kingdom sim. You're the king, and seven great houses want your throne. You hold it with grain, gold, marriages and your rulings at court. Side against a house in a war, and ten years later its lord stands up at court to remind you. When your reign ends, history names you: the Golden, the Bloody, or the Deposed.

I wanted my own Game of Thrones story, so I built one where you can rename anyone, rewrite their past and pick the story that comes for your throne. A season passes every 20 seconds, so a whole reign fits in an evening.

With an optional local model, you can answer petitioners in your own words instead of picking from a list, and it can write you a new story for your next reign.

It's free and open source on Apple Silicon Macs, with Windows next. I built it with Claude on top of Freeciv, and I'm happy to go into how any of it works.

For this sub, the model side. I'm the developer, and I also make Off Grid AI, the free and open source local app the model runs in, so this is self-promotion. Off Grid has a paid Pro tier. The game doesn't use it.

The model is LFM3 Omni 2B [QUANT], running on the Mac through Off Grid AI. Without it, the game plays on its own rules.

The model never holds game state. Freeciv runs the world, and rules pick what each lord is weighing. For the big choices the model makes the call and writes his line, and the game checks it. A choice only counts if it matches an option word for word. If a call fails or the JSON breaks, the rules decide.

What worked on a 2B. JSON only for decisions, and plain text for anything said aloud, because it talks far better when it isn't filling in a form. A ruling in your own words gets matched to a numbered list with a 6-token "only the number" answer. A conversation between two villagers is one call that writes the whole scene, because one call per line just echoed. Thinking is off.

Each villager keeps up to 16 memories in their own words, six moods that drift back to their nature, and trust and warmth toward the people they know. Only people near the camera, or that you've just spoken to, think with the model. Towns you're not watching run on rules. On my M5 with 32 GB a call takes under a second, and a two-person conversation takes 4 to 6 seconds.

Repo and download: https://github.com/off-grid-ai/game-of-crowns

## Before posting: Mac checks these
1. **[QUANT]:** the Omni 2B quant Off Grid serves. Every winner named it; cut the bracket if it isn't known.
2. **"On my M5 with 32 GB":** confirm the MINDS.md timings were measured on this Mac.
3. **Off Grid Pro:** if it's free now (the 21 Jul "Making OGAM and OGAD free forever" post), change the line to "Off Grid is free and open source."
4. **The download works first time** on a clean Mac, and the README has no dead links. A 404 in the thread is a known killer.
5. **The post makes no promise of other model servers.** Expect "let us input a URL" in the thread (it was Open Dungeon's top ask, 28 pts). Answer honestly: Off Grid AI today. Don't promise more.

## Score (RUBRIC.md)
- **Title A:** 8/8.
- **Post:**
  - P1 video 2, once recorded
  - P2 stack 2, once the quant is in
  - P3 numbers 2
  - P4 technique 2
  - P5 try it today 2
  - P6 own endpoint 0 (not offered)
  - P7 disclosure 2
  - P8 Mac in the thread 2
  - That's 14/16.
- **Total:** 22/24, gate passed once the video is in.
- **Not scored:** Mac's history on the sub. That's why the conditions at the top matter more than the score.

## Questions to have answers ready for (from the threads studied)
1. **Which model / quant / hardware / speed?** Omni 2B through Off Grid AI. Give the quant, the M5 32 GB, and under a second per call.
2. **What stops a lord inventing facts?** He can't write state. Freeciv and the rules own it, the model's choice must match an option, decree numbers are clamped to -50..50, and traits come off a fixed list. A villager can repeat a false rumour; that's gossip, and the world doesn't change.
3. **Can I use my own llama.cpp / LM Studio / Ollama?** Off Grid AI today. Don't promise more (Mac, 6 Nov).
4. **Is this an Off Grid ad?** The game plays on its rules with no model at all, and it's MIT.
5. **Memory without blowing the context?** Up to 16 weighted memories per villager; faint old ones fold into a one-line life so far. The proof: two seasons after Mac told a swineherd about a sick mother, "Do you remember me?" got "I met you two seasons ago in Riverhold, and you spoke of a sick mother…".
6. **Latency with lots of minds?** Hot minds first, warm ones now and then, cold ones on rules. With one model slot and about 27 plans queued, the on-screen ones waited 11.5 s on average (22.6 s worst).
7. **Anything surprising?** A brewer made up a rumour about a hedge witch, and in eight seasons 48 people in two towns had heard it in four versions. It was too fast, so unwatched towns now pass rumours on by rules once a minute, and a rumour dies six seasons after it's heard.
8. **Why not a bigger model?** It runs next to a 3D game on a laptop, and the model only writes words and makes calls the rules check.
9. **Isn't this just roleplay with an LLM?** No. It's a reign with grain, gold, marriages and seven houses, and it plays without the model.

## Sources for each claim
| Claim | Source |
|---|---|
| A season every 20 s | `bridge/chronicles.js:72` |
| Omni 2B, then 1.7B, via Off Grid AI; thinking off | `bridge/claude.js` (WANT, sayOnce, completeOnce) |
| Rules pick the move; the model makes the pivotal call; a non-matching choice counts as no | `bridge/characters.js` bestMove / ask / act |
| Failed or broken JSON falls back to the rules after one retry | `bridge/claude.js` complete / completeOnce |
| Decree numbers clamped to -50..50; traits from a fixed list | `bridge/claude.js` moodFrom |
| Speech in plain text, decisions in JSON | `bridge/claude.js` comment on `say` |
| Rulings matched by number, max 6 tokens | `bridge/claude.js` ruleFrom |
| 16 memories per villager; six moods; bonds; life so far | `bridge/minds.js` CAP, FEELINGS; `docs/MINDS.md` |
| Hot, warm and cold minds; under a second per call (0.84 s); 4–6 s conversations; queue waits | `docs/MINDS.md` Proven |
| One call per scene, because one call per line echoed | `docs/MINDS.md` Talk between minds |
| The swineherd; the rumour | `docs/MINDS.md` Proven |
| Off Grid AI Desktop is open source with an opt-in Pro | GitHub off-grid-ai/OGAD description |
