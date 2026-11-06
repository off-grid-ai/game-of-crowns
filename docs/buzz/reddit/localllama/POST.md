# r/LocalLLaMA post: Game of Crowns (draft, not posted)

Built from STUDY.md and RUBRIC.md. Every technical claim is checked against the code and docs/MINDS.md (sources at the bottom).

## Read this first: should it go up at all?
- **Mac's own call (brief.md, 5 Nov):** "Not r/LocalLLaMA or the local-AI crowd: Mac has exhausted them and they're allergic to him there."
- **The data agrees about his recent record there.**
  - His last six r/LocalLLaMA posts scored 0, 0, 0, 0, 0 and 1. Most were sent to four to six subs the same day, with no replies from him in the thread.
  - That is the pattern the mods built the April rules to remove ("they spam multiple subs at once with the same post").
- **The sub also shows what works for him there.** His only two hits were a video plus one hard number on modest hardware: 46 and 37 points, both in March.
- **If he posts it, these are the conditions** (STUDY.md §8–9 and the rules):
  1. Post it here only, not cross-posted to other subs that day.
  2. Mac rewrites or edits the body in his own words. Rule 3 now treats undisclosed LLM-written posts as low effort, and the sub calls it out ("write your replies yourself instead of relying on AI", 16).
  3. Upload a native video in the post itself, not a YouTube link.
  4. Nothing about Off Grid's Pro tier beyond the one disclosure line. No keys, no "first 10 people".
  5. Mac stays in the thread for the first few hours and answers the model, hardware and "who owns the truth" questions himself.

## Title
**Recommended, A (8/8):**
A 2B model on your Mac writes what the lords and villagers say in this kingdom sim, and the rules decide what actually happens

**Option B (8/8):**
A rumour one villager made up reached 48 people in two towns. Every mind in this kingdom sim runs on rules and a 2B model.

**For comparison, Mac's HN title (5/8 here):** "A medieval kingdom sim where history names you for how you ruled". It's right for players and HN. This sub pays for the model and the design boundary, and that title carries neither.

**Why A over B:**
- A says up front what the sub asks every LLM game ("How do you ensure determinism?", "what happens when an NPC asserts a fact the deterministic layer never authorized?").
- Warrior Quest scored 175 with the same shape: "where the model only plays NPCs and the actual game state stays deterministic".
- A also meets the sub's doubts about LLM NPCs head on ("characters that talk out of their a**", "fraction of the benefit for a whole lot of the cost").
- B is the better curiosity hook. But its 48 was a bug Mac had to slow down, so it works better as the story inside the post than as the promise on top.

## Video (the gate: STUDY.md §1, RUBRIC.md)
- 40 to 60 seconds of real play, uploaded to Reddit.
- **Show:** a petitioner at court answering a ruling typed in your own words, then the camera low over a town while two villagers' lines appear over their heads.
- **Leave out:** debug panels and captions about how it works. The numbers go in the text.
- **Not the launch film.** It's painted marketing, and this sub wants to see the model's output in the game.

## Body (paste as plain text: no headers or bold; one blank line between paragraphs)

Game of Crowns is a medieval kingdom sim for Apple Silicon Macs. You're the king, seven great houses want your throne, and a season passes every 20 seconds. Everything the lords and townsfolk say comes from LFM3 Omni 2B [QUANT] running on the Mac through Off Grid AI. I'm the developer and I make Off Grid AI too, so this is self-promotion. Both are free and open source, and Off Grid has a paid Pro tier the game doesn't use. I built most of the game with Claude.

The model doesn't hold any game state. Freeciv runs the world, and rules pick what each lord is weighing this season, like a marriage offer or turning his coat. For the big choices the model makes the call and says the line in his voice, and the game checks what comes back. A choice only counts if it matches an option word for word, otherwise it's a no. When you set the realm's mood in a decree, the numbers get clamped to -50..50 and any trait has to come off a fixed list. If the call fails or the JSON is broken, the rules decide, so the game plays fine with no model at all.

What worked with a 2B, some of it after getting it wrong first:

JSON only for decisions. Anything a person says aloud is plain text, because the model talks far better when it isn't filling in a form at the same time.

A ruling you type in your own words is matched against a numbered list with a 6-token "only the number" answer. The petitioner's reply to your face is a second call.

A conversation between two villagers is one call that writes the whole scene. One call per line just echoed the last speaker.

Lines get cut to two sentences, and a line that repeats a word pair, or one word three times, is dropped instead of shown. Thinking is off for every call.

Every commoner keeps up to 16 weighted memories in their own words, six moods that drift back to their nature, their wants and beliefs, and a trust and warmth score for the people they know. Faint old memories fold into a one-line life so far. I told a swineherd about a sick mother, and two seasons later "Do you remember me?" got "Yes, I do. I met you two seasons ago in Riverhold, and you spoke of a sick mother and the need for honest bread."

Not everyone thinks with the model. People near the camera or that you've just spoken to get model-written plans and lines, the rest of a town on screen gets one now and then, and towns you're not watching run on rules. On my M5 with 32 GB a call runs in under a second, and a two-person conversation takes 4 to 6 seconds. With one model slot and about 27 plans queued at once, the ones on screen waited 11.5 s on average and 22.6 s at worst.

I didn't plan for the gossip. A brewer with no news made one up about a hedge witch selling fake herbs, and eight seasons later 48 people in two towns had heard it in four versions, one of them ending "and the priest knows it". That was far too fast, so towns nobody's watching now pass rumours on by rules once a minute, and a rumour dies six seasons after it's heard.

If you run it from source you can point it at your own OpenAI-compatible server with GOC_LLM_URL and OFFGRID_MODEL instead of Off Grid. The repo and the Mac download are here: https://github.com/off-grid-ai/game-of-crowns

Which 1 to 3B model would you put in the lords' heads?

## Before posting: Mac checks these (each one changes a line above)
1. **[QUANT]:** the Omni 2B quant Off Grid serves. Every winner named it; cut the bracket if it isn't known.
2. **"On my M5 with 32 GB":** confirm the MINDS.md timings were measured on this Mac (this machine is an Apple M5 with 32 GB).
3. **Off Grid Pro:** OGAD's repo describes an opt-in Pro. If it's free now (the 21 Jul "Making OGAM and OGAD free forever" post), change the line to "Both are free and open source."
4. **GOC_LLM_URL: test before claiming it.**
   - What the code does: `GOC_LLM_URL=http://127.0.0.1:8080/v1 OFFGRID_MODEL=<model id>`, used when Off Grid AI isn't running.
   - It needs `/health` to answer, and the model id to match exactly.
   - Run it once against llama-server from source.
   - If it fails, cut the paragraph and expect "let us input a URL" as the top comment (Open Dungeon's was 28 points).
5. **The repo's download works first time** on a clean Mac, and the README has no dead links. A 404 in the thread is a known killer.

## Score (RUBRIC.md)
- **Title A:** 8/8.
- **Post:**
  - P1 video 2, once it's recorded
  - P2 stack 2, once the quant is filled in
  - P3 numbers 2
  - P4 technique 2
  - P5 try it today 2
  - P6 own endpoint 1 (source only, untested)
  - P7 disclosure 2, if Mac edits it in his own words
  - That's 13/14 before the thread, and 15/16 with Mac answering in it.
- **Total:** 23/24, gate passed once the video is in.
- **What the rubric can't score:** Mac's history on the sub. That's why the conditions at the top matter more than the score.

## Questions to have answers ready for (from the threads studied)
1. **"Which model / quant / hardware / tokens per second?"** Omni 2B through Off Grid AI's local server. Give the quant, the M5 32 GB, and under a second per call.
2. **"What stops a lord inventing facts?"** He can't write state. Freeciv and the rules own it, the model's choice must match an option, numbers are clamped, and lines are only words. A rumour can be false; that's gossip, and the world doesn't change because of it.
3. **"Can I use my own llama.cpp / LM Studio?"** Yes from source, with GOC_LLM_URL (only if item 4 above passed).
4. **"Is this an Off Grid ad?"** The game plays on its rules with no model, it's MIT, and the endpoint is swappable.
5. **"Why Mac only?"** Godot and Freeciv build for Apple Silicon today; Windows is next.
6. **"Why not a bigger model?"** It has to run next to a 3D game on a laptop, and the model only writes words and makes yes/no calls.
7. **"Isn't this just roleplay with an LLM?"** No. There's a reign with grain, gold, marriages and seven houses, and it plays without the model.

## Sources for each claim
| Claim | Source |
|---|---|
| A season every 20 s | `bridge/chronicles.js:72` |
| Omni 2B, then 1.7B; OpenAI-compatible gateway; thinking off; temperature 0.8 | `bridge/claude.js` (WANT, sayOnce, completeOnce) |
| Rules pick the move; the model makes the pivotal call; a non-matching choice counts as no | `bridge/characters.js` bestMove / ask / act (`d.choice === "accept"`) |
| Failed or broken JSON falls back to the rules after one retry | `bridge/claude.js` complete / completeOnce |
| Decree numbers clamped to -50..50; traits from a fixed list | `bridge/claude.js` moodFrom |
| Speech in plain text, decisions in JSON | `bridge/claude.js` comment on `say` |
| Rulings matched by number with max 6 tokens; the reply is a second call | `bridge/claude.js` ruleFrom / reactTo |
| Two sentences; loop lines dropped | `bridge/claude.js` tidyLine |
| 16 memories per commoner; six moods; bonds; life so far | `bridge/minds.js` CAP, FEELINGS; `docs/MINDS.md` |
| The swineherd's reply | `docs/MINDS.md` Proven |
| Hot, warm and cold minds; 0.84 s per call; 11.5 s average and 22.6 s worst wait with one slot; 4–6 s conversations | `docs/MINDS.md` Proven |
| One call per scene, because one call per line echoed | `docs/MINDS.md` Talk between minds |
| The rumour: 48 people, two towns, turns 139 to 147, four versions, then throttled | `docs/MINDS.md` |
| GOC_LLM_URL and OFFGRID_MODEL | `bridge/claude.js` lines 8–12, 31 |
| Off Grid AI Desktop is open source with an opt-in Pro | GitHub off-grid-ai/OGAD description |
