# r/LocalLLaMA: what makes project posts land or flop (study, 6 Nov 2026)

For Game of Crowns: a kingdom sim whose lords' and villagers' words come from LFM3 Omni 2B on the Mac, through Off Grid AI (which Mac makes).

## How the data was collected
- Reddit and web search both refuse this machine (reddit.com returns 403 "blocked by network security", and the search tool can't reach reddit.com). So every post came from the Arctic Shift archive (arctic-shift.photon-reddit.com), which re-fetches scores after posting. The top post of the year reads 2,496 points there.
- **The whole sub for a year:** 48,023 posts, 1 Nov 2025 to 6 Nov 2026. Of those, 2,498 are project posts: titles starting "I/we built, made, created…", or the Showcase and I Built A Thing flairs. The base rates below come from those.
- **Read in full:** 42 project posts in our space (games, NPCs, sims, companions, small on-device models), each one's body, its top 15 comments, the OP's replies and any mod removals. That's 17 that did well and 25 flops, the flops including all of Mac's own r/LocalLLaMA posts since June. Mac's 12 r/LocalLLaMA posts came from his author history.
- **The rules:** `about/rules.json` is blocked here, so the rules come from the mods' own posts. Those are the 24 Apr 2026 rule update (1su3ao4), the one-week check-in (1t1a3j7) and two user threads on rules.
- **Scale:** the median post scores 1, the top 10% score 87 or more, and the top 1% score 754 or more. In this study, "did well" means 40+ points and "flop" means 25 or less.
- **Caveat:** posts from the last few days, such as 1xlzuf2 (2 Nov), may still be gaining.

## The rules that bite (from the mods, 24 Apr 2026)
- **Karma minimums, enforced instantly by Automod.** Rule 4 (self-promotion) is "the area of largest abuse" ([check-in, 120 pts](https://www.reddit.com/r/LocalLLaMA/comments/1t1a3j7/)).
  - Removals of project posts went from 18% before 24 Apr to **43% after**, 837 of 2,498 over the year.
  - The live project posts that survive the filter do better: 18.8% reach 50+ points, against 6.0% before.
- **Rule 3, low effort, now names undisclosed LLM-written posts.** The mods: "posting LLM written content without disclosure is deceitful and betrays the implicit trust in the community" ([rule update, 324 pts](https://www.reddit.com/r/LocalLLaMA/comments/1su3ao4/)).
- **The users police it too:**
  - "I would be even mildly interested if you would write your replies yourself instead of relying on AI" (16 pts, [1r5ki6g](https://www.reddit.com/r/LocalLLaMA/comments/1r5ki6g/)).
  - "Can you please describe image? Or is it slop?" on Mac's own post ([1ugcsfv](https://www.reddit.com/r/LocalLLaMA/comments/1ugcsfv/)).
- **Rule 4 removals hit real work too.**
  - "I built NPCs that remember, gossip, and hold grudges… Here's the architecture" was an 875-word technical write-up. It scored 7 and was removed, the mod comment reading "Rule 4" ([1rab1m4](https://www.reddit.com/r/LocalLLaMA/comments/1rab1m4/)).
  - World Forge, which opened "I apologize for the AI written promo", was removed under Rule 4 twice ([1txq6td](https://www.reddit.com/r/LocalLLaMA/comments/1txq6td/)).
- **What the mods named as slopster behaviour:** "they spam multiple subs at once with the same post" (rm-rf-rm, 1su3ao4).
- **Users have asked for less of it:** a weekly "I made this" megathread (28 pts, [1t3buyg](https://www.reddit.com/r/LocalLLaMA/comments/1t3buyg/)), and fewer "vibe coded agent memory systems every five minutes" (12 pts, 1su3ao4).

## Base rates over 2,498 project posts (share reaching 50+ points)
| Feature | With | Without |
|---|---|---|
| Video in the post | **22.1%** (n=312) | 6.7% |
| Video, within Showcase / I Built A Thing flairs only | **35.0%** (n=140) | 18.2% |
| Body has a measured number (t/s, ms, s, GB, %) | **17.3%** (n=717) | 5.1% |
| Body names the hardware | 14.9% | 5.6% |
| Title names a model or size | 14.1% | 6.3% |
| Title has a measured number | 15.8% | 7.3% |
| Body over 600 words | 19.4% | 8.0% |
| Body under 120 words | 5.4% | 12.4% |
| Title starts "I built / I made" (live posts) | **6.7%** (n=825) | 18.9% |
| The same, within the project flairs only | 12.7% (n=55) | 22.9% |
| Title is a question or "would you…" | **3.0%** | 8.9% |
| Says open source / MIT | 9.0% | 8.4% (no effect) |
| Discloses "I'm the developer" | 8.7% | 8.6% (no effect on score; it's about not being removed) |
| Game / NPC / sim in the title | 22.1% (n=68) | 8.2% |

For our niche, 52 live game/NPC/sim project posts scored a median of 3. Of those, 12 reached 50+ and 33 stayed at 10 or under.

## Patterns that separate winners from flops

### 1. Show it moving
Video is the strongest single signal: 22% against 7% overall, and 35% against 18% among project-flair posts. Mac's own history shows it too. His two r/LocalLLaMA posts that worked were short videos with one hard result, "Qwen3.5 on a mid tier $300 android phone" (46) and "Generated super high quality images in 10.2 seconds on a mid tier Android phone!" (37). The best technical flop in our niche had no media at all: the 144m-model village sim, 17, linked out to X.

### 2. Say which model, on what, and how fast
- The first question in almost every thread is "which model / what hardware":
  - "What model do you have running and what game engine did you use?" (15, Warrior Quest)
  - "What kind of hardware are you using?" (65, the 1,638-point NPC engine)
  - "Which LLM? The issue being, they take a lot of resources." (4, Unity game)
  - "what $300 phone did you try it on?" (Mac's 46-pointer)
- Bodies with a measured number land 3.4× as often.
- When the number is missing, people ask for it: "Do you have an estimate of how many tokens per second…" (3, Project Aura).

### 3. One design idea explained well enough to copy
The winners in our niche each teach one trick:
- **NPC Engine** (1,638): RAG injects only the NPC actions that fit the moment, "so the model isn't being overloaded with a giant list every turn".
- **Mica 4B** (525): the request is broken into "a chain of small multiple-choice questions". A commenter: "small models are way better at picking from 4 options than writing a plan" (5).
- **Warrior Quest** (175): "the model only plays NPCs and the actual game state stays deterministic". A commenter: "Very cool use of an LLM to augment a classic game type and not make it some weird gimmick" (6).
- **Open Dungeon** (225): Gemma 4 12B at 256K context in about 7.7 GB.

Depth alone doesn't save a post, though. The removed NPC-gossip post and the 144m villager post were both deep.

### 4. The sub's question for any LLM game: who owns the truth?
- "How do you ensure determinism though? Do you have a set of rules you force on the model to prevent drift?" (6, [1u0cpbm](https://www.reddit.com/r/LocalLLaMA/comments/1u0cpbm/))
- "what happens when an NPC asserts a fact the deterministic layer never authorized?" (5, Warrior Quest)
- "How did you integrate valid game actions with text?" (7, AGI-Llama)

And the sub's doubts about LLM NPCs in general ([1u3nn4j](https://www.reddit.com/r/LocalLLaMA/comments/1u3nn4j/)):
- "you still need to write characters, motives, what information they should have" (238)
- "Using any of the vram to host a model even a small one would be a tough ask" (53)
- "Fraction of the benefit for a whole lot of the cost" (9)
- characters "that talk out of their a**" (15)

A post that says plainly that rules hold the state, the model only speaks, and it all fits on a laptop answers all of those.

### 5. Let them bring their own model
"Bring your own model / OpenAI-compatible endpoint" is the most repeated request:
- "you will gain a lot more traction posting about this if you add support for an OpenAI compatible endpoint" (28, Open Dungeon)
- "Why force sh*tty ollama? Just let us input a URL. You're on a subreddit where literally everyone already has a running inference engine." (4, Open Dungeon)
- "I'd love the ability to just point it to local LAN openai compatible address" (3, Warrior Quest)
- "Can I point it to any open ai compatible api? Say llamacpp, kobold or openrouter?" (2, Heart)
- "set up an OpenAI style route… Olama or LMStudio" (7, Pokemon)
- "You wouldn't happen to be hiding *Ollama* under the floorboard… We don't take too kindly to that in this sub." (3, Warrior Quest)

**For us, this is how Off Grid AI will be read.** A game that only talks to its maker's own app reads as a funnel.

### 6. Something to try now, and it has to work
- "GitHub or didn't happen" (58, NPC Engine)
- The flops ask for interest instead of shipping: "would this interest you?" (4, [1r5ki6g](https://www.reddit.com/r/LocalLLaMA/comments/1r5ki6g/)), "Need feedback from Mac users before I release it" (4, [1olhjll](https://www.reddit.com/r/LocalLLaMA/comments/1olhjll/)).
- Broken first runs get called out:
  - "My attempt to download Windows binary release led me to 404 page" (openClaw, 5)
  - "heart.app crashes on start" (Heart, 0)
  - "The link to local-dream in the readme gives 404. might be hallucinated by your AI coding." (Mac's 37-pointer)
  - "Don't force download 1.8 gb on browser without asking permission. Bad." (33, the Gemma E2B NPCs)

### 7. Plain claims, no hype
- Overclaims get corrected in the top comment:
  - "If hyperbole were a person" (15) on Mac's "Claude Mythos-level intelligence, running locally on your fuckin' phone" (0, [1v1flet](https://www.reddit.com/r/LocalLLaMA/comments/1v1flet/)), plus "Can we please all report this trash".
  - "post wording is a bit misleading" (13) on the 3D avatar.
  - "Heart – Local AI companion that feels emotions" scored 0. It had hot/warm/cold memory, like ours, and a video.
- Asking a question in the title halves the hit rate.

### 8. Disclose, and don't sell in the post
- Warrior Quest says it straight: "I'm the developer, so this is self-promotion". It scored 175 with no accusations.
- Mac's STT/TTS post said "This is a pro feature, happy to send over a license key to the first 10 people that comment". It scored 0, with three deleted comments and "'pro feature' which has already been done locally" (3) ([1uq4q9e](https://www.reddit.com/r/LocalLLaMA/comments/1uq4q9e/)).
- Mac's 46-pointer had its sponsorship and "pro plan which will be coming soon" plug in the comments. The post itself didn't sell.

### 9. Be in the thread
- Every winner's OP answered the "which model / hardware / how" questions within the thread:
  - NPC Engine OP: "5090 with faster-qwen3-tts" (56)
  - Warrior Quest: "The model is qwen2.5 7B… I can't fit a bigger one on my 3060 Ti" (6)
- Mac's last four r/LocalLLaMA posts have **zero OP replies**.

## Mac's own record on r/LocalLLaMA
| Date | Post | Pts | What happened |
|---|---|---|---|
| 16 Feb | [Hated giving out all my data… privacy first offline mobile application](https://www.reddit.com/r/LocalLLaMA/comments/1r6jhd6/) | 15 | No media |
| 21 Feb | [Have you ever hesitated before typing something into ChatGPT…](https://www.reddit.com/r/LocalLLaMA/comments/1rb062y/) | 38 | Question post, 100 comments |
| 25 Feb | [Everything I learned building on-device AI into a React Native app](https://www.reddit.com/r/LocalLLaMA/comments/1renuky/) | 8 | 1,525 words, no media |
| 2 Mar | [Qwen3.5 on Off Grid!](https://www.reddit.com/r/LocalLLaMA/comments/1rj4ee5/) | 1 | Product name in the title |
| 3 Mar | [Qwen3.5 on a mid tier $300 android phone](https://www.reddit.com/r/LocalLLaMA/comments/1rjec8a/) | **46** | Video plus one hard fact, a day after "Qwen3.5 on Off Grid!" scored 1 |
| 5 Mar | [Generated super high quality images in 10.2 seconds on a mid tier Android phone!](https://www.reddit.com/r/LocalLLaMA/comments/1rla8xn/) | **37** | Video plus a number; the top comment teased the hype (25) |
| 9 Mar | [Auto detect LLM Servers in your n/w…](https://www.reddit.com/r/LocalLLaMA/comments/1rp93ja/) | 0 | |
| 26 Jun | [Getting real work out of a 4B local model: the distill-on-idle pipeline…](https://www.reddit.com/r/LocalLLaMA/comments/1ugcsfv/) | 0 | Also posted to 5 other subs that day; "is it slop?"; no OP replies |
| 7 Jul | [Completely on-device offline real time STT and TTS…](https://www.reddit.com/r/LocalLLaMA/comments/1uq4q9e/) | 0 | Pro feature and license keys for the first 10 commenters; posted to 6 subs the same day; no OP replies |
| 20 Jul | [Claude Mythos-level intelligence, running locally on your fuckin' phone…](https://www.reddit.com/r/LocalLLaMA/comments/1v1flet/) | 0 | "If hyperbole were a person" (15); 3 subs; no OP replies |
| 25 Sep | [[Research Proposal] Cognitive Sharding…](https://www.reddit.com/r/LocalLLaMA/comments/1wpjt4j/) | 0 | 6 subs the same day |
| 23 Oct | [Off Grid AI: your AI, on hardware you already own.](https://www.reddit.com/r/LocalLLaMA/comments/1xdkjye/) | 1 | 6 subs the same day; removed on r/selfhosted; no OP replies |

This matches brief.md: "Mac has exhausted them and they're allergic to him there." The last six posts read to the sub as exactly the pattern its mods are filtering: one post sent to several subs at once, a product name or hype in the title, and nobody home in the thread. The two that worked were the opposite: a video, one number, and modest hardware.

## Posts studied
Media is what's in the post itself. "Stack named" is the model, runtime and hardware given in the body or the OP's replies. Reactions come from the top comments.

### Did well (17)
| Pts | Cmts | Flair | Title | Media | Words | Stack named | Numbers | Disclosure | Reactions |
|---|---|---|---|---|---|---|---|---|---|
| 1638 | 231 | Discussion | [NPC Engine Using Local Models](https://www.reddit.com/r/LocalLLaMA/comments/1uibt9o/) | video | 126 | Parakeet 0.6, Gemma 4 26B A4B, Qwen3-TTS; 5090 (in reply) | none in post | none needed | "shame there is so much ai hate in gaming" (612); hardware? (65); "GitHub or didn't happen" (58); how does the RAG work |
| 525 | 59 | Showcase | [A 4B model made me a netherite ingot from bare hands…](https://www.reddit.com/r/LocalLLaMA/comments/1xhw2l0/) | video | 729 | Mica v0.5 4B (own model) | per-step probabilities | AI-translated, said in a reply | jokes (114); "piggybacking on baritone" (7); release the harness |
| 452 | 66 | Resources | [Real-time AI (audio/video in, voice out) on an M3 Pro with Gemma E2B](https://www.reddit.com/r/LocalLLaMA/comments/1sda3r6/) | video | 78 | Gemma E2B, M3 Pro | none | repo link | memes (65); "offline use" (50); "~800ms would be a game changer" |
| 258 | 29 | Other | [Built a 100% client-side AI that plays Pokemon Red - Qwen 2.5 1.5B via WebLLM…](https://www.reddit.com/r/LocalLLaMA/comments/1ql6cz7/) | gif | 138 | Qwen 2.5 1.5B, WebLLM | none | GitHub Pages | "fun project" (25); add an OpenAI-style route for bigger models (7) |
| 225 | 64 | Resources | [Open Dungeon: local roleplay with Gemma 4 QAT + inline Uncen-FLUX images… under 8GB RAM](https://www.reddit.com/r/LocalLLaMA/comments/1u3uw8e/) | image | 169 | Gemma 4 QAT Q4, Ollama, FLUX | 256K ctx at ~7.7 GB | MIT, Mac build | "add an OpenAI compatible endpoint" (28); "Ollama is just bloat" (21); "let us input a URL" |
| 214 | 55 | Other | [Control a 3D avatar with language instead of buttons](https://www.reddit.com/r/LocalLLaMA/comments/1tzgn87/) | gif | 273 | Qwen 3 0.6B + LoRA (in reply) | 22 MB adapter | own research | "so it maps to mixamo clips?" (72); "post wording is a bit misleading" (13) |
| 175 | 54 | Discussion | [I made Warrior Quest… where the model only plays NPCs and the actual game state stays deterministic](https://www.reddit.com/r/LocalLLaMA/comments/1wa84sa/) | video | 202 | Qwen2.5 7B, 3060 Ti (reply), Godot | 8 GB VRAM, 60–90 min demo | "I'm the developer, so this is self-promotion"; Steam | "Great use of AI" (30); which model? (15); NPC canon question (5); "hiding Ollama"; bring your own endpoint (3) |
| 172 | 17 | New Model | [FunctionGemma Physics Playground…](https://www.reddit.com/r/LocalLLaMA/comments/1ppwqki/) | video | 58 | FunctionGemma 270M, WebGPU | none | HF Space | "demo is extremely unconvincing" (20); "LLM for the sake of it" (6) |
| 107 | 41 | I Built A Thing | [Anyworld, a self-hosted multiplayer text RPG where a local LLM is the Dungeon Master](https://www.reddit.com/r/LocalLLaMA/comments/1wwkudj/) | image | 868 | llama.cpp, Gemma 4 26B-A4B Q4; OpenAI too | 128K ctx | repo | "I made something similar" (33); praise for the multiplayer design (14) |
| 98 | 74 | Other | [I bundled a fully local LLM inside my Unity game…](https://www.reddit.com/r/LocalLLaMA/comments/1u0cpbm/) | video | 245 | model not named | "10–20 s" for TTS | Steam game | "100% the future of gaming" (68); "How do you ensure determinism?" (6); "Which LLM?" (4); "gamers are hostile to LLM slop" |
| 80 | 26 | Funny | [AGI-Llama: Bringing Modern LLMs to 1980s Sierra Adventure Games](https://www.reddit.com/r/LocalLLaMA/comments/1powyhk/) | video | 205 | backends listed | none | open source; emoji bullets | "How did you integrate valid game actions with text?" (7); KoboldCPP support? |
| 78 | 14 | News | [LlamaTale v0.41.0 - Dungeons v2](https://www.reddit.com/r/LocalLLaMA/comments/1p3t4jg/) | none | 172 | none | none | GitHub; "AMA" | external API? (5); OP answered everything |
| 73 | 43 | I Built A Thing | [Running an LLM-driven town with 800+ persistent agents…](https://www.reddit.com/r/LocalLLaMA/comments/1x0ms0m/) | image | 2640 | hosted DeepSeek Flash (not local), said up front | 300–400 calls/day, 30K ctx | "I am the developer… used AI to translate" | "sick" (21); how to do it with llama-server KV cache (14); persistence question (9) |
| 64 | 37 | I Built A Thing | [Villager Simulation Game POC Created with Qwen3.8-27B-UD-Q3_K_XL.gguf - 16GB VRAM](https://www.reddit.com/r/LocalLLaMA/comments/1w8r0t9/) | none | 995 | full config | 75 t/s tg, 1700 t/s pp | demo link | bug notes (6); "share your run command" |
| 50 | 12 | Discussion | [Experiment: autonomous NPCs powered by Gemma 4 E2B in the browser](https://www.reddit.com/r/LocalLLaMA/comments/1uv3wnt/) | image | 259 | Gemma 4 E2B, 2060 laptop | none | MIT | "Don't force download 1.8 gb" (33); "try LFM 230M" (4) |
| 46 | 44 | News | [Qwen3.5 on a mid tier $300 android phone](https://www.reddit.com/r/LocalLLaMA/comments/1rjec8a/) (Mac) | video | 33 | Qwen3.5 2B | $300 phone | repo in comments | "what can we do with this small model?" (18); "how is your app different than PocketPal?" |
| 42 | 4 | Generation | [LLM-driven puzzle sandbox: anything you try becomes an action (Cosmic Egg)](https://www.reddit.com/r/LocalLLaMA/comments/1otpql6/) | video | 74 | "local LLMs" | none | upcoming game | "LLM Scribblenauts!" (8) |

### Flops (25)
| Pts | Cmts | Flair | Title | Media | Words | Stack named | Numbers | Disclosure | Reactions |
|---|---|---|---|---|---|---|---|---|---|
| 25 | 40 | Showcase | [Built a home for 5 local companions on Gemma 4 26B…](https://www.reddit.com/r/LocalLLaMA/comments/1xduy84/) | none | 366 | LM Studio, Gemma 4 26B QAT, 3070 Ti | 8 GB VRAM | "my Claudes build it" | memory drift feedback loop (7) |
| 22 | 2 | Other | [Made a video game that uses local LLMs](https://www.reddit.com/r/LocalLLaMA/comments/1rjh6ti/) | none | 112 | Qwen 3 1.7B + 8 LoRAs | none | itch link | "good creative idea" (2); Linux only |
| 18 | 28 | Discussion | [Building a game where you talk to NPCs using Llama 3.1-8B-q4, optimized for 6GB VRAM](https://www.reddit.com/r/LocalLLaMA/comments/1qc485u/) | video | 170 | Llama 3.1 8B Q4_K_M, llama-server, Vulkan | 5.3 GB at 4096 ctx | nothing to play | "Isn't this just role playing?" (8); "Why not a more modern model?" |
| 17 | 7 | Showcase | [a 144m model makes most of my villagers' choices, gemma 4 e4b only steps in when something goes wrong (6 gb laptop gpu)](https://www.reddit.com/r/LocalLLaMA/comments/1xlzuf2/) | none | 343 | julia-1 144M, Gemma 4 E4B | 0.81–0.90 confidence, 6 GB | links to X only | thoughtful replies; 4 days old |
| 15 | 15 | Discussion | [How am I building a hacking sim game themed on 90s with NPCs powered by AI](https://www.reddit.com/r/LocalLLaMA/comments/1pwd46f/) | none | 2021 | Llama 3 8B | none | none | "too heavy to run" (5); "cheat: use hardcoded lines" (5) |
| 10 | 7 | Other | [WebGPU llama.cpp running in browser with Unity to drive NPC interactions (demo)](https://www.reddit.com/r/LocalLLaMA/comments/1q5b7kf/) | none | 255 | llama.cpp WebGPU | none | itch demo | "Unity already has Sentis" (1) |
| 8 | 0 | Resources | [Colony – a simulation of an LLM within a colony of agents](https://www.reddit.com/r/LocalLLaMA/comments/1uertvl/) | video | 55 | none | none | GitHub | no comments |
| 8 | 9 | News | [Project Aura: Building an Open-Source, Fully Local AI Companion Baked into Custom AOSP…](https://www.reddit.com/r/LocalLLaMA/comments/1pn1buv/) | image | 577 | none | none | "cross-posting to a few related subs" | "custom ROM is alarming" (2); "tokens per second?" (3); "someone has to be the grownup" (5) |
| 7 | 1 | Discussion | [I built NPCs that remember, gossip, and hold grudges… fully local on Ollama. Here's the architecture](https://www.reddit.com/r/LocalLLaMA/comments/1rab1m4/) | image | 875 | Gemma 3 12B, Ollama, ChromaDB | none | none | **removed, Rule 4** |
| 7 | 10 | Resources | [I built a local LLM NPC backend focused on NPC-to-NPC conversations](https://www.reddit.com/r/LocalLLaMA/comments/1ulg0tv/) | YouTube link | 332 | not named | none | open source | "what game engine?" (1) |
| 7 | 14 | Resources | [What if you could direct your RP scenes with sliders… I built a local LLM frontend](https://www.reddit.com/r/LocalLLaMA/comments/1r7v05j/) | image (broken) | 335 | none | none | none | images deleted; 2 comments removed |
| 6 | 1 | Resources | [I built a social flight simulator to practice office politics…](https://www.reddit.com/r/LocalLLaMA/comments/1pcl2kf/) | image | 549 | local + Gemini SDK | none | none | 1 comment |
| 5 | 3 | Discussion | [Local-first AI NPC desktop… (openClaw Desktop)](https://www.reddit.com/r/LocalLLaMA/comments/1r5bt2s/) | image | 157 | none | none | emoji bullets | "download led me to 404" (1); a competitor plug |
| 5 | 13 | Funny | [I built a little game for my local agents to play via API…](https://www.reddit.com/r/LocalLLaMA/comments/1tdkra4/) | none | 153 | none | none | none | cute replies |
| 4 | 24 | Discussion | [Building a fully local AI roleplay app… would this interest you?](https://www.reddit.com/r/LocalLLaMA/comments/1r5ki6g/) | none | 221 | none | none | nothing to try | "write your replies yourself instead of relying on AI" (16); "how is this different than Silly Tavern?" (6) |
| 4 | 3 | Discussion | [Built a local AI assistant… Need feedback from Mac users before I release it](https://www.reddit.com/r/LocalLLaMA/comments/1olhjll/) | none | 82 | none | none | nothing to try | "set expectations early" (2) |
| 3 | 1 | New Model | [Releasing OpenRA-RL: A full-fledged RTS environment for local AI Agents](https://www.reddit.com/r/LocalLLaMA/comments/1rahgv3/) | video | 547 | none | none | team | 1 comment, removed |
| 2 | 8 | Other | [World Forge Project](https://www.reddit.com/r/LocalLLaMA/comments/1txq6td/) | none | 378 | none | none | "AI written promo" | **removed, Rule 4 ×2**; name clash |
| 2 | 2 | Discussion | [a game engine for ai chats, bc why not](https://www.reddit.com/r/LocalLLaMA/comments/1pavpxi/) | video | 644 | none | none | none | 1 comment |
| 1 | 6 | Resources | [Polyglot Air v2 is out!…](https://www.reddit.com/r/LocalLLaMA/comments/1p2hs47/) | image | 221 | Ollama / OpenAI | none | "a Star on GitHub would mean the world" | mod: "README still shows ollama" (3) |
| 0 | 15 | Resources | [Heart - Local AI companion that feels emotions](https://www.reddit.com/r/LocalLLaMA/comments/1ow369o/) | video | 173 | Ollama | none | repo | "how is this happening?" (4); "crashes on start"; point at any OpenAI API? |
| 0 | 8 | Resources | [Getting real work out of a 4B local model: the distill-on-idle pipeline…](https://www.reddit.com/r/LocalLLaMA/comments/1ugcsfv/) (Mac) | image | 275 | 4B | none | none | "is it slop?"; 1 removed; no OP replies |
| 0 | 11 | Resources | [Completely on-device offline real time STT and TTS with reasoning using Gemma 4 E4B](https://www.reddit.com/r/LocalLLaMA/comments/1uq4q9e/) (Mac) | video | 71 | Gemma 4 E4B | none | Pro feature, license keys for the first 10 commenters | "'pro feature' which has already been done locally" (3); 3 removed |
| 0 | 14 | News | [Claude Mythos-level intelligence, running locally on your fuckin' phone with Qwythos-9B](https://www.reddit.com/r/LocalLLaMA/comments/1v1flet/) (Mac) | video | 42 | Qwythos-9B | none | none | "If hyperbole were a person" (15); "Not this kind of content" (12); "report this trash" |
| 1 | 0 | Showcase | [Off Grid AI: your AI, on hardware you already own.](https://www.reddit.com/r/LocalLLaMA/comments/1xdkjye/) (Mac) | video | 53 | none | none | the product itself | no comments; 5 more subs the same day |

### Rules and context threads read
[r/LocalLLaMa Rule Updates](https://www.reddit.com/r/LocalLLaMA/comments/1su3ao4/) (324) · [New rules 1 week check-in](https://www.reddit.com/r/LocalLLaMA/comments/1t1a3j7/) (120) · [Rule suggestion: links to "I made this website" with full disclosure](https://www.reddit.com/r/LocalLLaMA/comments/1t3buyg/) (23) · [Alright, the mods gotta step it up](https://www.reddit.com/r/LocalLLaMA/comments/1vohx43/) (33) · [Why hasn't any mainstream game integrated LLMs into NPCs yet?](https://www.reddit.com/r/LocalLLaMA/comments/1u3nn4j/) (72)

## What r/LocalLLaMA will want to know about a game on a 2B model
From the threads above, in the order they get asked:
1. Which model, which quant, which runtime, which machine, and how fast.
2. Who owns the truth: what stops the model from inventing facts or actions? (Warrior Quest, Unity, AGI-Llama)
3. Can I point it at my own llama.cpp / LM Studio / Ollama URL? (6 threads)
4. Prompt shape for a small model: actions as a list, multiple choice, JSON or plain text. (Mica, NPC Engine)
5. Memory: how it stays consistent without blowing the context. (800-agent town, companions drift)
6. Where's the repo, and does it run first time?
7. With a company behind it: is this an ad, and what's paid?

## How commercial apps fare
- **Open and free is necessary but not enough.** "Says open source" has no effect on score (9.0% vs 8.4%).
- **Paid tiers hurt when they show up in the post.** Mac's Pro-feature post scored 0, and Polyglot's "a Star would mean the world" scored 1.
- **Commercial tools land when the post is about the result.** Warrior Quest (a Steam game, 175) and Slow Vale (hosted DeepSeek, 73) both disclosed plainly and led with the engineering.
- **The sub resents lock-in to one runtime.** The "hiding Ollama under the floorboard" line (Warrior Quest) is how a Game of Crowns that needs Off Grid AI would be read. Our answer has to be "point it at any OpenAI-compatible server".
