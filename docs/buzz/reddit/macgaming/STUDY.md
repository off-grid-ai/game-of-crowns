# What wins and what flops on r/macgaming (game developers' own posts)

Studied 6 Nov 2026 for the Game of Crowns launch post. Rubric in [RUBRIC.md](RUBRIC.md), our post in [POST.md](POST.md).

## How the data was collected

- Reddit itself refused every request from this Mac (403 for curl and the fetch tools, blocked in the in-app browser). So the data comes from two public mirrors of Reddit:
  - **Arctic Shift** (arctic-shift.photon-reddit.com), a Reddit archive. Pulled every r/macgaming post from three windows (Jan to mid-Feb 2025, Aug to mid-Sep 2025, Mar to early Apr 2026): 7,012 posts, 244 of them flaired Self promotion. Its scores were taken about 36 hours after posting, so they run a little below today's. Post bodies, removal status and up to 100 comments per thread came from here.
  - **Redlib** (a Reddit front end) for live scores, the sidebar rules and searches: the Self promotion flair sorted by top, new and most comments, plus 14 searches ("I made", "my game", "solo dev", "demo steam", "free game", "native game", "strategy game" and others), 1,034 posts in all.
- For each post in the table below I read the title, the full body and the top comments, and counted the developer's own replies in the thread.
- "Winner" means 100 or more points and "flop" means under 20, or removed. The table gives the live score where Redlib had it, otherwise the archive's.
- Every post is a developer showing their own game. I left out tools, wrappers and ports, which are a different kind of post (and now the bulk of the sub, see "The mood right now").

## The rules, and what gets posts removed

The sidebar ("Standard Rules") says: **"Self-promotion is limited to once-daily. When self-promoting content, please provide as much meaningful information as possible, such as a detailed description, trailers, or screenshots. It is also required to properly format posts."** Approved posters can ask the mods for more. No piracy. A Self promotion flair exists, and every winner below used it.

What actually got removed (18 of the 244 archived self-promo posts, 7%, the same as the sub overall):
- **New or karma-less accounts.** AutoModerator removes posts from accounts under 1 hour old, or with comment karma below 0: "Your submission has been automatically removed, as you do not meet the minimum account age requirements to post" ([Bolo](https://www.reddit.com/r/macgaming/comments/1rmzae4/), [ice kart level](https://www.reddit.com/r/macgaming/comments/1rpxnhf/), [music production game](https://www.reddit.com/r/macgaming/comments/1s1jfuh/)).
- **Reposting.** A GZDoom launcher posted three times in a row: two copies removed by moderators. A PSX horror game posted four times in an hour: three copies removed by Reddit's spam filter, and the survivor got 1 point.
- A commenter on Imperium quoted a rule, "individual games are limited to 1 thread per 48 hours". It's not in the sidebar I could read, so treat it as likely but unconfirmed. Imperium posted twice in 15 days and got 3, then 0.

Nothing was removed for being self-promotion as such, for an AI disclosure, or for a store link.

## The mood right now (Oct to Nov 2026)

- The sub is flooded with "I built a wrapper/launcher/port" posts, many made with AI. ["Stop bloating this subreddit"](https://www.reddit.com/r/macgaming/comments/1xj9k38/) (185 points, 97 comments, 30 Oct) asks for a megathread for "all the sudden devs that made yet another great wrapper with AI". The top reply, 57 points: "Now it's just endless trash 'I built'". Another reply, 30 points: "Claude, how do I work with other people?"
- In the Redlib sample, 212 posts from 1 Oct to 3 Nov 2026: the hits are ports and tools (Mario Kart World native 1,171, an Overwatch app 1,164). Original indie games mostly scored 0 to 15. The exceptions were [SuperCitycon](https://www.reddit.com/r/macgaming/comments/1xjlcc0/) (370) and [My Beautiful Faraway](https://www.reddit.com/r/macgaming/comments/1x5nqx0/) (176).
- So a launch post today competes with a flood, and readers have an itchy trigger for anything that smells AI-made.

## Every post studied

Title forms: **Stake** = first person with a real feeling or cost (nervous, quit my job, shaking). **Dev** = first person, no stake. **Premise** = names what you do in the game. **Catalogue** = "Name: tagline", "Name - tagline", version numbers, a launch date as the whole news. Dev replies = the developer's own comments in the thread.

### Winners (100+)

| Score | Cmts | Dev replies | Title (exact) | Title form | Media | Body | Dev disclosure | Price, store | What commenters said |
|---|---|---|---|---|---|---|---|---|---|
| 1121 | 107 | 31 | [I "didn't" quit my job to pursue the dream of making this game. I made it on M3 Max MBP in my spare time after a full-time job, a toddler, and a newborn. It's called MEATSHOT](https://www.reddit.com/r/macgaming/comments/1iq4rso/) | Stake, Mac personal | video | none | title is the story | Steam, unreleased | "Reminds me a lot of GunZ"; "Where can we download the game?" (no link in post) |
| 1119 | 49 | 16 | [Developing a WW1 tank horror game entirely on a Macbook!](https://www.reddit.com/r/macgaming/comments/1ra6du8/) | Premise, Mac personal | gallery | 291, two lines + Steam link | implied | Steam wishlist | "you had me at WWI" (76); one sharp note that Steam said not Mac-compatible (38) |
| 1011 | 131 | 23 | [My friend and I are making a minimalist freeriding skiing game and today we finally got it running smooth on macOS! Looking for feedback/testing 🎿](https://www.reddit.com/r/macgaming/comments/1ikmktz/) | Stake ("finally"), premise | video | none | "My friend and I" | free test build | "Alto on steroids"; players reporting how it runs on their M1 Pro |
| 696 | 182 | 25 | [Releasing my game on Mac in 2 weeks. I thought I'd be excited but honestly? I'm more nervous than anything... would you play a game like this? 🤷](https://www.reddit.com/r/macgaming/comments/1gh70yc/) | Stake, question | video | none | title | Steam demo | "Don't be nervous, be proud"; bug reports from the demo; one PirateSoftware jab |
| 554 | 206 | 36 | [My free demo runs on Mac and I'd be pumped if you guys played it...](https://www.reddit.com/r/macgaming/comments/1ezekq8/) | Stake | video | none | title | free demo, Steam | long play notes; "whats it called?" (name missing) |
| 523 | 63 | 32 | [I'm a solo indie dev from Sweden and I developing my game with a Mac-First mindset. And the performance is smooooth! Try the demo for free on Steam and tell me what you think.](https://www.reddit.com/r/macgaming/comments/1sv6b44/) | Dev, Mac personal | video | 574, casual, one paragraph on the game + link | "I develop my game on a Mac for Mac" | free demo, Steam | "happy to see game developers thinking about Mac first" |
| 483 | 78 | 21 | [I finally did the cliché and quit my job to finish MEATSHOT. Full-time work + two kids + game dev… it almost broke me. Time to go all in.](https://www.reddit.com/r/macgaming/comments/1p3xoq9/) | Stake | video | none | title | Steam, unreleased | "Hope it pays off buddy!" (55); "What's the genre?"; "Is it a native app?" |
| 451 | 40 | 12 | [My hand-drawn, relaxing tram simulator will come to macOS next month via Steam](https://www.reddit.com/r/macgaming/comments/1h4mb6v/) | Premise, dev | video | none | "My" | Steam | "Wishlisted!"; "Please release it on the Mac App Store too" |
| 447 | 64 | 31 | [I am thrilled to announce that my game will soon be available on both the Mac App Store and Steam, catering to the Mac gaming community.](https://www.reddit.com/r/macgaming/comments/1lf6he6/) | Stake ("thrilled") | video | none | title | Mac App Store, Steam | top comment "what is it about?" (26); "no Mac demo :(" |
| 370 | 60 | 17 | [SuperCitycon, my new city builder. Built on Mac, for Mac](https://www.reddit.com/r/macgaming/comments/1xjlcc0/) | Dev, Mac personal | video | 1,858, personal, plain, with an AI disclaimer ("Coding — AI assisted... This game isn't vibe-coded. It's my life's work") | "my" | free demo, Steam | "waiting for a mac native city builder"; "SimCity 2000 vibes"; "is there an economy underneath?" No AI pushback. |
| 328 | 29 | 14 | [I am happy to announce the official launch of my game inspired by Limbo on November, which will be available on Mac. How does it feel?](https://www.reddit.com/r/macgaming/comments/1oc5j7c/) | Stake ("happy"), question | video | 209, two lines + link | "my game" | Steam demo | "on Steam I can see only Windows version" |
| 256 | 33 | 15 | [I'm delighted to announce that my game will soon be available to Mac users. Here's a trailer to give you a glimpse of what's to come.](https://www.reddit.com/r/macgaming/comments/1mi3be6/) | Stake ("delighted") | video | none, link in dev's first comment | "my game" | Steam wishlist | "Are you releasing on the Appstore?" |
| 240 | 55 | 21 | [I'm developing a dystopian RPG where you explore a brutalist megastructure, slay lost souls, and guide humanity to a digital afterlife. Considering adding Mac support if it resonates with you guys!](https://www.reddit.com/r/macgaming/comments/1ioyf7q/) | Premise, dev | image | none, dev explains in a comment | "I'm developing" | not on Mac yet | "Mac please :-)" (27) |
| 193 | 25 | 7 | [100 reviews milestone reached, 2 days after release. 93% positive. I'm shaking](https://www.reddit.com/r/macgaming/comments/1iqlvk9/) | Stake | image | none | title | paid, Steam | "Bought the game straight up to support indie devs supporting the Mac" |
| 191 | 27 | 11 | [Report anomalies in living paintings (looking for Mac playtesters who like weird games)](https://www.reddit.com/r/macgaming/comments/1ri09q3/) | Premise | video | 761, personal, signed "Thomas" | "Hi solo-dev here!" | private playtest | "Amazing idea!"; "Severance mixed with classic art" |
| 176 | 17 | ? | [my indie game just released on steam with native macOS support](https://www.reddit.com/r/macgaming/comments/1x5nqx0/) | Dev | gallery | 671, lowercase, chatty, no bullets | "my indie game" | paid, Steam | (thread not in the archive yet) |
| 139 | 19 | 9 | [Mac gamers, do you agree that there should be more 3D Metroidvania games? I'm developing one inspired by Moebius! The demo is available on Steam!](https://www.reddit.com/r/macgaming/comments/1it9401/) | Question, dev | video | none | "I'm developing" | Steam demo | a player found the "Mac demo" downloaded Windows files |
| 138 | 15 | 3 | [It took a whole weekend but I finally ported my game to Mac ready for release!](https://www.reddit.com/r/macgaming/comments/1ruhwog/) | Stake ("finally") | gallery | 360, the messy truth ("My macbook is SO slow") | title | none given | top comment: "How are you gonna self promote and not name the game dawg" |
| 107 | 19 | 8 | [Our underwater world is coming for Mac too!](https://www.reddit.com/r/macgaming/comments/1mujw38/) | Dev | video | 82, link only | "Our" | Steam | "What are the system requirements?" |

Also read: [Dawnfolk launch-day post](https://www.reddit.com/r/macgaming/comments/1invatf/) ("I'm losing my mind... Send help", 73 points, 12 dev replies), [Slender Threads](https://www.reddit.com/r/macgaming/comments/1iu62p2/) (93), [Piece by Piece](https://www.reddit.com/r/macgaming/comments/1rskng0/) (96).

### In between (20 to 99, Oct to Nov 2026)

| Score | Cmts | Title (exact) | Note |
|---|---|---|---|
| 46 | 6 | [Our game runs native on Mac from day one. No Rosetta, no wrappers](https://www.reddit.com/r/macgaming/comments/1xfw8w6/) | ends on "what do indie games usually get wrong on Mac?" |
| 43 | 2 | [I'm developing a historical city builder on my MacBook Air, demo available on Steam](https://www.reddit.com/r/macgaming/comments/1x9qybo/) | the closest genre match to ours; Mac personal, no stake |
| 30 | 9 | [Salt and Soil has a free Mac demo — build a homestead and pass it down through generations](https://www.reddit.com/r/macgaming/comments/1xf4gor/) | family strategy, very close to our theme; catalogue-form title |
| 24 | 4 | [I'm making a 2D retro football game on my Mac, and the Steam page just went up!](https://www.reddit.com/r/macgaming/comments/1xov6bu/) | discloses AI coding help, no pushback |
| 21 | 16 | [Solo dev looking for Mac players to test my free demo on different M chips](https://www.reddit.com/r/macgaming/comments/1xcp64s/) | a testing ask brings comments, not upvotes |

### Flops (under 20, or removed)

| Score | Cmts | Dev replies | Title (exact) | Title form | Media | Body | Dev disclosure | Price, store | What happened |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | [Imperium, a turn-based space 4X, is out today with a native universal Mac build](https://www.reddit.com/r/macgaming/comments/1xm2e6z/) | Catalogue | video | 618, press release, "AI tools were used across the workflow", utm link | none in voice | paid, Steam | silence; its second post in 15 days |
| 3 | 2 | 1 | [Imperium, a turn-based space 4X, is a native universal Mac build. Free demo in Steam Next Fest](https://www.reddit.com/r/macgaming/comments/1x945tu/) | Catalogue | video | 648, same template | none | free demo | a commenter cites the 48-hour rule |
| 0 | 1 | 0 | [Barely Civilized now has a native Mac build. It runs well on my M5 Air, and I'd love to hear how it runs on yours.](https://www.reddit.com/r/macgaming/comments/1xfeigg/) | Catalogue + Mac personal | text + YouTube link | 3,277, bold headings, "Hey everyone! I'm ArTchie from ArTchie Studios" | studio | paid pre-alpha | one comment, from a Windows player |
| 1 | 0 | 0 | [Ballot or Barracks v0.62.0 has a macOS build — 251 playable countries and territories](https://www.reddit.com/r/macgaming/comments/1xgv5mz/) | Catalogue (version) | text | 905, manual-like, Gatekeeper instructions | "I'm the developer" | free, itch zip | silence. A strategy game on itch, like ours. |
| 0 | 0 | 0 | [VentiKenny: a free voxel sandbox adventure for Apple Silicon Macs (M3 or newer)](https://www.reddit.com/r/macgaming/comments/1xm7d2v/) | Catalogue | YouTube | 1,626, bullet list, "AI disclosure: generative AI tools assisted with code and graphics, and helped prepare this post" | "Developer self-promotion:" | free, itch zip | silence |
| 0 | 0 | 0 | [I'm a solo dev and I just updated my two free native Mac games: UBOOTSIM (WWII U-boat sim) and SailorSim (sailing sim)](https://www.reddit.com/r/macgaming/comments/1xlcfw7/) | Dev, two products | video | 1,371, bold bullets | "solo dev" | free, Mac App Store | silence |
| 1 | 3 | 1 | [I ported Ares (the classic 90s Mac space strategy game) to Windows, with some modern upgrades](https://www.reddit.com/r/macgaming/comments/1xby2yg/) | Dev | text | 1,459, "using Claude... I'm not a programmer" | yes | free | a Windows port in a Mac sub |
| 3 | 0 | 0 | [Would you play Gnome Nook on Mac? I'm making a cozy game about sorting 9,600 gnomes](https://www.reddit.com/r/macgaming/comments/1xd7l8e/) | Question, premise | video | 1,051, careful | "I'm the developer" | not on Mac | silence; there's nothing to play on a Mac |
| 4 | 0 | 0 | [StrainBorn: a roguelite where you play as the virus, free beta on Mac with full controller support](https://www.reddit.com/r/macgaming/comments/1xk0h2y/) | Catalogue, premise | video | 1,022, bold bullets | "I'm a solo dev" | free TestFlight | silence; posted 04:04 UTC |
| 5 | 0 | 0 | [The Rusted launches November 2 on macOS](https://www.reddit.com/r/macgaming/comments/1xdq0yt/) | Catalogue (date) | video | 201, hype | "our" | Steam | silence |
| 6 | 1 | 1 | [For the past year I've been developing my game on the M2 Macbook Air. It's a low spec game but I'm still grateful to my M2s strength over the years :,)](https://www.reddit.com/r/macgaming/comments/1xco691/) | Dev, Mac personal | video | none, game never named | implied | none | silence |
| 3 | 0 | 0 | [Glowsea — a jellyfish stealth adventure for your Mac browser (free demo)](https://www.reddit.com/r/macgaming/comments/1xjsejx/) | Catalogue | text | 946 | "We're Shapemo" | free, browser | silence (posted twice) |
| 14 | 0 | 0 | [Knights of Frontier Valley - classic RPG, now also on Mac](https://www.reddit.com/r/macgaming/comments/1x8a5t4/) | Catalogue | video | 1,070, "All art is hand-made with no AI involved" | "I am solo-developing" | Steam, Rosetta only | silence |
| 9 | 6 | 3 | [My naval roguelite in one captain's log: buy a gun, rake a stern, sign a pact, sink, rebuild, sail out again](https://www.reddit.com/r/macgaming/comments/1wwgsaj/) | Premise, dev | video | 1,551, bold bullets, AI-asset disclosure | "Solo dev here" | Steam demo | two polite comments |
| 12 | 18 | 12 | [Solo dev here. I built an F2P (PvP & PvE) native Apple Silicon card game from scratch using Swift and Metal.](https://www.reddit.com/r/macgaming/comments/1sajl73/) | Dev, stack | video | 18,960 (codes and essays) | yes | free, App Store | the dev replied 12 times; the comments were about free codes |
| 13 | 0 | 0 | [Looking for testers: Free Dune-inspired roguelike (Sands) now has a Mac build](https://www.reddit.com/r/macgaming/comments/1n5msjd/) | Catalogue | video | 735, itch link | "solo dev" | free, itch | silence |
| 15 | 2 | 1 | [War on Wheels - Turn-Based, Physics Controlled, Tactical Car Combat.](https://www.reddit.com/r/macgaming/comments/1rw2f2p/) | Catalogue | video | 156 | "We" | Steam page | "Could listen to the sound track over and over" |
| 9 | 0 | 0 | [My visual novel game Chick'n Mushroom Soup is released on Steam and playable on MacOS!](https://www.reddit.com/r/macgaming/comments/1rmb6bn/) | Dev | video | 729, bold store copy | "our first game" | paid, Steam | silence |
| 7 | 0 | 0 | [Developed my roguelite 100FRIENDS entirely on my Macbook. Free demo is out today!](https://www.reddit.com/r/macgaming/comments/1rvl5lh/) | Dev, Mac personal | YouTube | 320, "If you liked Peglin..." + links | implied | free demo | silence; posted 20:26 UTC |
| 7 | 0 | 1 | [We're building a music sandbox game optimized for Mac. Free demo on Steam, looking for feedback.](https://www.reddit.com/r/macgaming/comments/1s3fwyt/) | Dev | text | 1,368, link list | "we're a small team" | free demo | one warm comment |
| 4 | 0 | 0 | [I spent the last year making a match-3 shoot 'em up. It's out today, with Mac support at launch!](https://www.reddit.com/r/macgaming/comments/1npmqsd/) | Stake, premise | image | 324 | "my" | $3, Steam | silence. A counterexample: stake title, still flopped. |
| 3 | 0 | 0 | [Norman Lives - Survive IF you can in this Multiplayer RPG.](https://www.reddit.com/r/macgaming/comments/1rqqyj9/) | Catalogue | image | 618, feature bullets | "our" | — | silence |
| 3 | 0 | 0 | [Four player chess game coming to Mac and IOS](https://www.reddit.com/r/macgaming/comments/1s8nhun/) | Catalogue | YouTube | none | none | — | silence |
| 2 | 0 | 0 | [I'm making an Open World Adventure set in the American Frontier !](https://www.reddit.com/r/macgaming/comments/1sbsigj/) | Dev, premise | video | 762, a recut after earlier feedback | "solo passion project" | Steam | silence; posted 22:54 UTC |
| 2 | 0 | 0 | [Developed a tiny game entirely on my MacBook Air - A tiny arcade game about a square who has to avoid other squares and chase a green circle! Is it any fun?](https://www.reddit.com/r/macgaming/comments/1rlx8kp/) | Mac personal, question | link | none | implied | web | the same dev posted near-identical "tiny game" posts five times in March |
| 1 | 1 | 0 | [Bolo - Multiplayer Tank Battles](https://www.reddit.com/r/macgaming/comments/1rn9xlb/) | Catalogue | text | 367, "I've been vibe coding some new life into an old Mac classic" | yes | free, web | its first copy was removed by AutoModerator |
| 1 | 0 | 0 | [Psx Horror Game for MAC - low specs](https://www.reddit.com/r/macgaming/comments/1n3y2h4/) | Catalogue | text + YouTube | 90 | none | — | three duplicate copies removed by Reddit |
| removed | | | [Bolo - Multiplayer Tank Battles](https://www.reddit.com/r/macgaming/comments/1rmzae4/) | | | | | | AutoModerator: account under 1 hour old |
| removed | | | [We added an ice kart level to our beat making game](https://www.reddit.com/r/macgaming/comments/1rpxnhf/) | | | | | | AutoModerator: account age |
| removed | | | [Our music production game runs on mac. We asked a producer to check it out and here's what they made.](https://www.reddit.com/r/macgaming/comments/1s1jfuh/) | | | | | | AutoModerator: comment karma below 0 |

## What separates winners from flops

Counts on the 224 archived self-promo posts that weren't removed (archive scores, which run low), and on 185 game-developer posts from the Redlib sample (live scores, 2024 to 3 Nov 2026).

**Title (the biggest lever you control)**
- **A real feeling or cost in the title wins.** Titles with words like nervous, shaking, finally, quit my job, thrilled: median 58 against 7 in the archive (n=11 vs 213); 56% reached 100+ in the live sample against 20% (n=16 vs 169). MEATSHOT ("it almost broke me") 483, "I'm more nervous than anything" 696, "I'm shaking" 193. There's one clear counterexample: "I spent the last year making a match-3 shoot 'em up" got 4, with a still image.
- **First person beats brand voice.** Median 33 against 14.5 with live scores; 28% vs 13% reached 100+.
- **"Name: tagline" and catalogue titles lose.** 9% reached 100+, against 25% for everything else. 9 of the 14 October flops in the table open with the game's name ("Imperium, a turn-based space 4X, is out today", "Ballot or Barracks v0.62.0", "VentiKenny: a free...", "The Rusted launches November 2"); only one of the 19 winners does (SuperCitycon).
- **Mac said personally helps, a little.** "Made it on M3 Max MBP", "entirely on a Macbook", "Mac-First": median 33.5 against 13, but the share reaching 100+ barely moves (25% vs 22%). "Has a native Mac build" alone is what every flop says.
- **Doesn't predict:** naming the genre or premise in the title (the flops do it more than the winners do), "free" in the title (no change in median), title length, questions in the title (they hurt in the archive and helped in the live sample).

**Media**
- **Native video wins.** 28% of video posts reached 100+ against 12% of text posts; in the archive, 16 of 81 videos reached 50+ against 3 of 54 text posts and 3 of 36 link posts. A YouTube link isn't the same thing: 100FRIENDS, VentiKenny and Barely Civilized all linked YouTube and got 0 to 7.
- Every game winner's video was gameplay. In the comments, the winners still drew "what is it about?" and "what's the genre?", so the clip alone doesn't say what you do.

**Body**
- Body length doesn't predict (archive medians: none 6, under 1,000 chars 8, over 1,000 chars 10). Half of the winners have **no body at all**.
- **Voice does predict.** The winners' bodies are short and sound like a person ("My macbook is SO slow", "Thanks and have a lovely weekend, Thomas"); SuperCitycon's long body is still plain speech. The October flops read like store pages: "Hi r/macgaming! I'm X, the solo developer of Y", bold feature bullets, "What you can play:", utm-tagged links, closing calls for hardware reports. In the scored set, winners average 1.9 of 2 on body voice and flops 0.6.
- **Name the game and give the link**, or the thread asks for them ("How are you gonna self promote and not name the game dawg", "whats it called?", "Where can we download the game?"). It's hygiene, though: the flops do it just as well.

**Dev disclosure and AI**
- Winners say plainly that they made it, in the title or the first line ("My friend and I", "I'm a solo indie dev from Sweden"). Nobody was punished for saying so.
- AI disclosures: SuperCitycon (AI-assisted coding, "isn't vibe-coded... my life's work") got 370 with no pushback; the football game got 24 with none. Imperium, VentiKenny, Ares, Bolo and Pirate Twist disclosed AI and got 0 to 9, but they also had every other flop trait. **Evidence is thin either way**, and the mood thread shows the trigger is there.

**Timing**
- Posts made 12:00 to 15:59 UTC did best in the archive (12 of 52 reached 50+, mean 66), against 1 of 31 for 00:00 to 03:59 UTC. Weekend means were higher, weekend medians weren't. It's a weak signal: WW1 tank horror got 1,119 at 20:22 UTC.

**Thread behaviour (strongest single difference, but partly a result)**
- Winners' developers replied 3 to 36 times (median 16); 13 of 14 scored flops got 0 or 1 replies. Comments come first and the replies follow, so this is partly effect, not cause. But the winners reply to everything: bug reports, "what engine?", "Mac App Store?".
- The Covenant Cards developer replied 12 times and still got 12 points. Replies don't rescue a thread that's about free codes.

**Rule pitfalls**
- One post per game. Don't repost a flop: Imperium went 3, then 0; the Glowsea and "tiny game" developers reposted and got 1 to 3.
- Post from an account that's older than an hour and has non-negative comment karma.
- Use the Self promotion flair.

## Where the evidence is thin

- Live scores only exist for posts Redlib's search returned, and its "top" sorts favour older hits, so the year comparison (2024 to 2025 looked far easier than 2026) is biased. October 2026 is genuinely hard for original games, but by how much isn't measurable here.
- I scored the rubric knowing which posts won, so its separation is optimistic. It needs testing on posts it hasn't seen.
- The archive's comments stop at 100 per thread; dev-reply counts on the biggest threads are floors.
- Only one strategy or kingdom game won (SuperCitycon). The close comparables (Salt and Soil 30, Pixel Metropolis 43, Ballot or Barracks 1, Imperium 0 and 3) suggest our genre starts below average here.
- No itch-linked game in the sample reached 100. Ballot or Barracks and VentiKenny were itch zips that needed Gatekeeper instructions; every winner linked Steam. Two cases can't separate itch from everything else they did.
