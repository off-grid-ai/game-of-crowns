# r/LocalLLaMA rubric (from STUDY.md: 48,023 posts, 42 project threads read)

## Finding
Unlike Show HN, where the title decided (docs/buzz/hn/RUBRIC.md), here the **post** separates winners from flops more than the title does.
- **Titles overlap heavily.** Winners average 5.9/8 and flops 4.2/8, and the best-scoring title of all belongs to a flop (the 144m-model village sim, 8/8, 17 pts).
- **What carries a post:**
  - a native video or picture
  - the stack and a real number
  - one design idea worth copying
  - honest disclosure with nothing sold in the post
  - the OP answering in the thread
- **What sinks one:** being removed (Rule 4), or reading as an ad.

## Gate (before scoring)
**The post itself shows the thing, with a video, GIF or screenshots in the post.** A link out to YouTube or X doesn't count.
- All 8 scored winners pass.
- Two flops that score well on paper fail it: the 144m villagers (18/24, linked to X) and WebGPU Unity NPCs (14/24, link to itch).
- Base rate: video reaches 50+ points 3.3× as often (22.1% vs 6.7%).

## Title (0–2 each, /8)
- **T1. Says plainly what it is:** a game, an NPC engine, a sim. Understood in one read.
- **T2. Names the model, its size or the hardware.** Base rate: 14.1% vs 6.3%.
- **T3. Carries one design idea or concrete result** the sub can argue with: "the model only plays NPCs", "a 4B model made me a netherite ingot", "256K context under 8GB".
- **T4. Clean:**
  - no "I built / I made" lead (6.7% vs 18.9%)
  - no question or "would you" (3.0% vs 8.9%)
  - no hype or overclaim ("feels emotions", "Mythos-level")

## Post (0–2 each, /16)
- **P1. Native video or GIF in the post** (2); screenshots (1).
- **P2. Stack named:** model and quant, runtime, machine.
- **P3. A measured number:** latency, t/s, RAM or VRAM, context. Base rate: 17.3% vs 5.1%.
- **P4. One technique explained well enough to copy.**
- **P5. Something to try today, free, and it works first time.** Repo or download.
- **P6. Bring your own model:** an OpenAI-compatible URL, not locked to one runtime.
- **P7. Disclosed and clean:**
  - "I'm the developer"
  - ties named
  - nothing sold or given away for comments
  - written by the poster (Rule 3)
- **P8. OP answers in the thread:** model, hardware, how.

## Scored: 8 winners, 10 flops
| Post | Pts | T1 | T2 | T3 | T4 | Title /8 | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | Post /16 | Total /24 | Gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NPC Engine Using Local Models | 1638 | 2 | 0 | 0 | 2 | 4 | 2 | 1 | 0 | 2 | 0 | 0 | 2 | 2 | 9 | 13 | ✓ |
| A 4B model made me a netherite ingot… | 525 | 1 | 2 | 2 | 2 | 7 | 2 | 1 | 1 | 2 | 0 | 0 | 1 | 2 | 9 | 16 | ✓ |
| Real-time AI… on an M3 Pro with Gemma E2B | 452 | 2 | 2 | 1 | 2 | 7 | 2 | 2 | 0 | 0 | 2 | 0 | 2 | 2 | 10 | 17 | ✓ |
| Open Dungeon… under 8GB RAM | 225 | 2 | 2 | 2 | 2 | 8 | 1 | 2 | 2 | 1 | 2 | 0 | 2 | 2 | 12 | 20 | ✓ |
| I made Warrior Quest… game state stays deterministic | 175 | 2 | 0 | 2 | 1 | 5 | 2 | 1 | 1 | 2 | 2 | 0 | 2 | 2 | 12 | 17 | ✓ |
| Anyworld… a local LLM is the Dungeon Master | 107 | 2 | 0 | 1 | 2 | 5 | 1 | 2 | 1 | 2 | 2 | 2 | 2 | 2 | 14 | 19 | ✓ |
| I bundled a fully local LLM inside my Unity game… | 98 | 2 | 0 | 1 | 1 | 4 | 2 | 0 | 1 | 1 | 1 | 0 | 2 | 2 | 9 | 13 | ✓ |
| Qwen3.5 on a mid tier $300 android phone (Mac) | 46 | 2 | 2 | 1 | 2 | 7 | 2 | 1 | 0 | 0 | 1 | 0 | 1 | 1 | 6 | 13 | ✓ |
| a 144m model makes most of my villagers' choices… | 17 | 2 | 2 | 2 | 2 | 8 | 0 | 2 | 2 | 2 | 0 | 0 | 2 | 2 | 10 | 18 | ✗ |
| Building a game where you talk to NPCs using Llama 3.1-8B-q4, 6GB VRAM | 18 | 2 | 2 | 1 | 2 | 7 | 2 | 2 | 2 | 1 | 0 | 0 | 2 | 2 | 11 | 18 | ✓ |
| WebGPU llama.cpp… Unity to drive NPC interactions | 10 | 2 | 1 | 1 | 2 | 6 | 0 | 2 | 0 | 1 | 2 | 0 | 2 | 1 | 8 | 14 | ✗ |
| I built NPCs that remember, gossip, and hold grudges… (removed, Rule 4) | 7 | 2 | 1 | 1 | 1 | 5 | 1 | 2 | 0 | 2 | 0 | 0 | 0 | 0 | 5 | 10 | ✓ |
| I built a local LLM NPC backend… NPC-to-NPC conversations | 7 | 2 | 0 | 1 | 1 | 4 | 0 | 0 | 0 | 1 | 2 | 0 | 2 | 2 | 7 | 11 | ✗ |
| Heart – Local AI companion that feels emotions | 0 | 1 | 0 | 1 | 0 | 2 | 2 | 1 | 0 | 1 | 1 | 0 | 2 | 2 | 9 | 11 | ✓ |
| Building a fully local AI roleplay app… would this interest you? | 4 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 2 | 3 | ✗ |
| Completely on-device… STT and TTS… Gemma 4 E4B (Mac) | 0 | 1 | 2 | 1 | 1 | 5 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 8 | ✓ |
| Claude Mythos-level intelligence… Qwythos-9B (Mac) | 0 | 1 | 2 | 0 | 0 | 3 | 2 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 6 | ✓ |
| Off Grid AI: your AI, on hardware you already own. (Mac) | 1 | 0 | 0 | 0 | 1 | 1 | 2 | 0 | 0 | 0 | 1 | 0 | 1 | 0 | 4 | 5 | ✓ |

## Does it separate them?
- **Averages:** winners 16.0/24 (lowest 13), flops 10.4/24.
- **A total of 13+ is necessary but not sufficient.** All 8 winners clear it, and so do 3 of the 10 flops: the 144m villagers (18), the 6GB Llama NPC game (18) and WebGPU Unity (14).
- **The fix is the gate.**
  - The media gate catches two of those flops (144m, WebGPU), leaving 8/8 winners and 1/10 flops passing gate plus 13.
  - A "something to try today" gate would be wrong: the 1,638-point NPC engine and the 525-point Minecraft agent had nothing to download.
- **What still gets through:** the 6GB Llama 3.1 8B game, posted in Jan 2026 with nothing to play. Its thread asked "Why not a more modern model?" and "Isn't this just role playing with the LLM?". An old model and no novelty aren't in the rubric. Check them by hand: is the model current, and is the idea something the sub hasn't seen this month?

## What doesn't predict
- **The title on its own** (see above).
- **Technical depth on its own.** The removed NPC-gossip post (875 words of architecture) and the 144m post (P4 = 2) both flopped.
- **Saying "open source".** 9.0% vs 8.4%.
- **Disclosure, for score.** 8.7% vs 8.6%. It decides whether the post survives Rule 4 and the "is this an ad" thread, not how high it goes.
- **Body length, past about 120 words.** Over 600 words does a little better (19.4%), but the 1,638-pointer had 126.
- **Not tested here:** timing, and the poster's own history. Mac's history matters a lot (STUDY.md), and the rubric can't see it.

## Our posts
| Post | T1 | T2 | T3 | T4 | Title /8 | P1 | P2 | P3 | P4 | P5 | P6 | P7 | P8 | Post /16 | Total /24 | Gate |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Planned line (virality.md): "Game of Thrones x Westworld, open source: every lord runs on a local model, offline." | 1 | 1 | 1 | 0 | 3 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 4 | ✗ |
| Mac's HN title: "A medieval kingdom sim where history names you for how you ruled" | 2 | 0 | 1 | 2 | 5 | | | | | | | | | | | |
| **Title A (recommended):** "A 2B model on your Mac writes what the lords and villagers say in this kingdom sim, and the rules decide what actually happens" | 2 | 2 | 2 | 2 | **8** | | | | | | | | | | | |
| **Title B:** "A rumour one villager made up reached 48 people in two towns. Every mind in this kingdom sim runs on rules and a 2B model." | 2 | 2 | 2 | 2 | **8** | | | | | | | | | | | |
| **POST.md body**, once the video is recorded, the quant added and Mac has edited it in his own words | | | | | | 2 | 2 | 2 | 2 | 2 | 1 | 2 | (2) | **13/14 now, 15/16 with Mac in the thread** | **23/24** | ✓ once the video is in |

Why the planned line scores low:
- It's a trademark mashup, which mac-voice rules out.
- "Every lord runs on a local model" overclaims, because rules decide and cold minds never call the model.
- It has no size, no number and no media.

Why the HN title scores 5 here:
- It's the right title for players and for HN.
- But r/LocalLLaMA pays for the model and the design boundary. Titles without a model or size hit 50+ at 6.3% against 14.1% with one.
- It says nothing this sub would argue with.

P6 is 1, not 2, because `GOC_LLM_URL` works only when running from source and is untested against llama-server (see POST.md).
