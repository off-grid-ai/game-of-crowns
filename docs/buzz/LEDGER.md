# Downloads ledger

Kept by the downloads supervisor (every 15 minutes in the buzz session). Goal: get the game into people's hands. Newest run first.

## Needs Mac
- **Disk:** Mac freed ~20 GB; the 0.4 release build is running.
- **Promo art:** prompts for Codex in docs/buzz/asset-prompts.md (GitHub social preview, itch.io cover, key art). The social preview has to be set by hand in the repo's Settings.
- **itch.io:** public since ~19:00 on 6 Nov, devlog live. Left: a YouTube link for the trailer slot once the new video is up.
- **Launch is today, 6 Nov (Mac's call), runbook in docs/buzz/launch-today.md:** Mac posts r/macgaming at 19:00 IST, r/IndieGaming and r/godot at 19:20, sends creator emails from 19:30, and replies all evening. AppleGamingWiki page this week.
- **The lady's licence:** confirm the Sketchfab ownership claim for 'Princess Nun Royal Queen' (b9f22ea). A licence question only: .gitignore keeps body files out of git, so pushes publish no model files.
- **Approve the rest of the list below** (everything marked "proposed").

## Direction (agreed with Mac 11-05, from the main session)
1. Reign stories in acts, ending the reign in victory or fall; tagged by threat, enemy, feel, length (tags drive the simulation).
2. Built from beats on the arc engine (court matters, branches on rulings, a threat meter, reign end).
3. Generate a story from tags or a write-up (Off Grid AI or rules).
4. New Chronicle screen with story cards; an act/threat strip in play.
5. Powerful politics: alliances, march on a house, strip titles, hostages, council, spies, executions.
6. Balance pass: costs bite, repeated gifts weaken, rivals resent favourites, long wars cost the crown.
7. First ~20 stories, starting with The Usurper's Claim.
Engine support for court matters, rulings, a threat meter and the reign's end is built, not committed. All realms were archived; the game starts clean. Posts claim none of this until it ships.

## Recommendations
Current list: **downloads-first** (11-05 ~13:00), which replaced the virality list (~12:40), which replaced the first list (~12:20).

| Ask | Status |
|---|---|
| Lords keep a lasting record of the King's deeds | **Shipped** beb839b (pushed) |
| A lord brings a year-old deed up at court in his own words | **Shipped** beb839b (seen in the bridge: Bryony Thornvale on the tithe) |
| The chronicle names the cause when a house cools, rebels or refuses the banners | **Shipped** beb839b |
| Seasons 20 s instead of 90 s | **Shipped** beb839b (long reigns: Freeciv itself still takes 30–60 s a season, open) |
| Repo public | **Shipped** 11-05 13:09 (Mac approved; secrets scan clean) |
| Signed and notarised Mac dmg + GitHub Release | **Shipped** 11-05 14:03: v0.1-20261105-622eb2d, pre-release, notarised Developer ID (packaging/release-mac.sh) |
| No bundled model; recommend Off Grid AI (getoffgridai.co/desktop) | **Shipped** 1c04684, 0239e2c (Mac's call). Unverified: packaged build, and the court line on a Mac without Off Grid |
| A 20–30 s clip of a lord remembering | Proposed (after the lord work lands) |
| Windows build | Dropped for now (Mac 11-05: Mac only until demand is proven) |
| Look pass phase 2 (people, animals and life, ground detail, vegetation, shorelines, light and lens) | Approved by Mac ("better, but a lot more scope"); in progress (look-pass session) |
| First-impression fixes 1–3 (sunk people, captions, map progress text) | Captions (3e0517c) and map text (beb839b) shipped; sunk people in progress (main session diagnosing with close stills) |
| Look pass #1: capture profile (`--hq`, full res, MSAA+TAA, 8192 shadows) | **Shipped** beb839b |
| Look pass #2–4 and fixes 4–13 (grade, ground, buildings in the land, smoke, people) | **Shipped** 16d2715, 6e093d7, 7dd662a, 71962ea, 92456d6, 62fc53a (reviewed: clearly better). Open: people detail, a T-posed townsperson at Goldrock, castles on slabs |
| Friends as lords (naming screen; later Discord names) | Proposed, parked (later) |
| Saga card at the end of a reign | Proposed, parked |
| Lords answer outrageous rulings in character | Proposed, parked |
| Daily realm; watch mode with clip export | Proposed, parked |
| Community realm (Founders' Realm, weekly reign) | Proposed, parked (Mac: downloads first) |
| Art licences cleared; separate demo build | Dropped (Mac: not the bottleneck; the game is the demo) |

## In progress
- **Look-pass session (local_07cac2ca):** grade, ground, buildings, smoke, people, with before/after renders.
- **Look pass landed (11-05 17:05, retake the marketing shots):** morning grade on by default (62fc53a, `GOC_LOOK=noview` for the old look); ground at true texture scale and brown mud (16d2715); tavern stone apron cut (6e093d7); smoke as wisps (7dd662a); grass and flowers in the wind (71962ea); towns up to 80 people (92456d6). Before/after: docs/play/r37-look/before-after-*.jpg. Render stills with `--season=summer` (winter turns the ground grey). Left: grass blades near the camera, the T-posed townsperson at Goldrock, people detail.
- **Look pass phase 2 landed (11-05 17:55):** T-pose fixed and each townsperson idles and talks their own way (0f052ff); smoke from about half the hearths, yard clutter, footpaths from doors, the square laid whole with an edge, a horse at the tavern, reeds on the shores (935a1d8); deeper contact shadow (da4dee0). Pairs: docs/play/r37-look/phase2-*.jpg. Blocked on assets: medieval civilian bodies, animals, birds, washing lines (brief: side-session notes PEOPLE_ASSETS_BRIEF.md; asset session proposed).
- **Frame-rate pass (11-05 22:10, look-pass session):** Goldrock at town zoom, triangles 19.9 M to 4.9 M a frame: realm-wide grass and bushes drawn only near the camera (be809a3), woods in full only within 6 units, and every mesh simplifying at 4 px not 1 (3af06e3); towns of 40 people, crowds only round where you look, far ones stepped 1 frame in 4, GPU smoke, no reeds (be809a3). fps not yet at 30: about 10 in the real game at town zoom, held by foliage drawing and engine work under the terrain (hiding the forest halves the frame), and battles (Mixamo soldiers 10-30 k triangles each, 39 k-triangle horses). Off Grid test workers were using 3-4 cores during every measurement, so absolute fps is pessimistic. Next: Godot GPU profiler on the woods (alpha foliage, card distance) in the real game.
- **Explainer:** pass 2 planned (PASS2.md: 70% world, memory one beat); holding takes until the look pass and the main session's fixes are pushed.
- **Main session:** testing the lord work in Mac's relaunched game; then close-up stills (docs/buzz/images/zoom/live/) and the first-impression fixes 1–3 (docs/buzz/first-impression.md) before pushing.
- **Explainer session (goc-explainer):** briefed 11-05 13:25 by the buzz session: a 20–30 s clip of a lord remembering and a 60–90 s explainer, after the lord work lands; files to docs/buzz/video/.
- **Buzz session:** this ledger, the supervisor, drafts for the channels once the dmg exists.

## Runs

**2026-11-07 03:23:** Shipped: 3f28691 and 96d2879 (README: four gameplay screenshots from the itch page, with a caption about the realm); buzz checklist v10. Moved: on Mac's ask, the r/macgaming post now leads with "a free Game of Thrones world sim". Downloads: GitHub 4.

**2026-11-06 21:12:** Shipped:
- dec0c14: r/godot study. The post is on hold until the image-model assets are swapped.
- 1a96f3a: indie posts on Mac's final copy, with an AI-paintings line.
- cdd3464: 4X and sim posts on Mac's final copy.
- 6f055f2: r/LocalLLaMA post (22/24, Showcase flair).
- 134ef89: r/godot post on Mac's final copy.
- 40c460c: buzz checklist, with HN killed on submission (email hn@ycombinator.com) and one row per subreddit.

Moved: every Reddit post is now on Mac's final copy. HN item 50393044 is dead because of the account's history.

Needs Mac:
- r/macgaming. The US window closes ~22:30 IST.
- The creator emails.
- The HN restore email.

Downloads: GitHub 4. itch: ask Mac.

**2026-11-06 20:23:** Shipped:
- HN post, now final per Mac on 6 Nov: 2749f33, 77c10ea, 7f365b4, dde5276, 8dd1958, a5fc6e0, 78df33d, 03a5804. Off Grid AI is out of the post and disclosed in the first reply that asks.
- Reddit studies, each a year of posts with rubrics and rewritten posts:
  - 4384d54: r/4Xgaming and r/SimulationGames.
  - 278eb85: r/indiegames and r/IndieGaming. Both remove GenAI, so the painted film is held there.
  - 1c57b24: r/LocalLLaMA.
  - bbd0627: Mac's title scored.
- Buzz 0325e9a and aa3cb87: the r/macgaming step uses the study's post with an honest AI answer; r/IndieGaming is held.

Moved: Mac has changed direction: Hacker News and r/LocalLLaMA are now in play (the earlier "no HN or LocalLLaMA" in brief.md is superseded). Sessions reddit-macgaming, reddit-sim-4x, reddit-localllama, reddit-godot and reddit-indie each own a sub.

Needs Mac: post r/macgaming (window until ~22:30 IST), then the creator emails.

Downloads: GitHub 4.

**2026-11-06 20:08:** Shipped: 7dd0c70 and de7b2cc (a Hacker News post and rubric in docs/buzz/hn/, written by another session). Note: Mac's earlier direction was no Hacker News (brief.md). If he has changed his mind, that's his call; flagged to him. Moved: nothing public. Needs Mac: r/macgaming with the film (US window until ~21:30 IST), then the creator emails. Downloads: GitHub 4.

**2026-11-06 19:53:** Shipped: 4e22358 (README: the trailer link plays the launch film). Moved: both film cuts are public on the 0.5.1 release; the email link returns 200 and the byte size matches. Needs Mac: post r/macgaming with the film (US window until ~21:30 IST), then send the creator emails. Downloads: GitHub 4.

**2026-11-06 19:50:** Shipped: a58865a (the 0.5 launch film: 33s, Mac's final copy over the Codex paintings, with the real court card as proof; 16:9 and 9:16). Moved: the 0.5.1 devlog is live (Mac approved it here). The film is approved; the main session is attaching it to the 0.5.1 release; posts, emails and the checklist now point at it. Mac can post r/macgaming now. Downloads: GitHub 4.

**2026-11-06 19:23:** Shipped: fa1812d (roadmap: rule from your phone); 2a92455, 10f5f6d, 14fead0 and 5048f87 (README: opens on the painted throne room, a plain trailer link, download goes straight to the latest release, Coming soon as a checklist); buzz 86c610e (itch cover, banner and story screenshots from the launch paintings), 416915e (r/macgaming post without a version number). Moved: **0.5.1 is live on itch** (build #2313350). The itch cover, banner and first two screenshots are the Codex launch paintings, with six gameplay shots after them. The explainer is recutting the launch film from Codex's second set; posts go tonight if it's ready by ~21:15 IST, else tomorrow 19:00. Waiting on Mac: whether to publish the 0.5.1 devlog draft. Downloads: GitHub 4 (my own checks account for the 0.5 and 0.5.1 ones).

**2026-11-06 19:09:** Shipped: 0.5.1 released on GitHub as Latest, a full release (v0.5.1-20261106-b55fe8e; c396fef); 345a43b (README: "Coming soon", each item a GitHub issue to vote on); buzz 497303f and f0ca53c (Mac's launch-night checklist: https://claude.ai/artifact/R24TDPuL8BPwxe54XTZ8id). Moved: **itch is public** (Mac published it ~19:00) with his final copy and the 0.5 build. The "0.5 is out" devlog is live. Tags fixed (choices-matter, politics, fantasy added; 10/10). 0.5.1 is pushing to itch now. Mac is holding the Reddit posts and creator emails for a better explainer video: post tonight if it's ready by ~21:15 IST, else tomorrow 19:00 IST. Downloads: GitHub 4 (0.5.1: 0). itch numbers: ask Mac.

**2026-11-06 18:57:** Shipped: 3c04d04, 609a8f4 and 7e9f82a (launch film plan and Codex brief: a painted story of Gareth's grudge ending on the King's name in history, in Mac's final copy); 4a77409 (README: the new hook, the roadmap as one list, release history); buzz b799978, b17047f, df6373c and a26c9c6 (tonight's posts, emails, itch devlog and old drafts on Mac's final copy). Moved: Mac's final itch copy is live on the page: "Find out what kind of king you'd be", only what the player gets, no "it's early". 0.5.1 is being notarised for a full release today. Blocks: the itch page is still Draft (404), so the 19:00 r/macgaming post has nothing to link until Mac publishes. Downloads: GitHub 4.

**2026-11-06 18:38:** Shipped (on main): ce21596 (VISION: v2 is multiplayer in first and third person); 8e6ec14 (launch film: a Codex brief for six paintings telling Gareth Varn's grudge); b55fe8e (Settings drop the language and Type/Speak choices); 122d2b1 (a shared, editable roadmap checklist page); d69c3d1 (VISION: continents, your own maps and characters, deeper lore, magic). Moved: nothing public. Blocks: the itch page is still Draft (404), and Publish is due now at 18:40, before r/macgaming at 19:00. Downloads: GitHub 4.

**2026-11-06 18:24:** Shipped (on main, not in 0.5): a8233a7 (the reign ends on its own screen with the verdict; the Hand raises plague, unrest, thin granaries and more; one royal favour per house a year; cards wait their turn; the camera stays above roofs); da89092 (the Hand offers each order once). These are candidates for 0.5.1 on 13 Nov. Moved: nothing public. Blocks: the itch page is still Draft (public URL 404); Mac's Publish is due at 18:40. Downloads: GitHub 4 (0.5's one download is my own check).

**2026-11-06 17:55:** Shipped: 0.5 released (v0.5-20261106-f5ba354: court fix, notarised, both hook clips attached); 15a45cf (README as a sales page). Moved: the 0.5 dmg is on itch (channel mac, build #2312884, labelled 0.5; Gatekeeper: Notarized Developer ID). Left: Mac's Publish on itch (page and devlog) at 18:40, then the posts.

**2026-11-06 17:38:** Shipped: e9ba53d (README: the throne-hall painting on top, a trailer preview linking the full clip, the seven houses in their paintings). Moved: the 0.5 release build is running (scratch folder up, 18G free). Blocks: the 0.5 release (due ~18:00), then Mac's Publish on itch at 18:40. Downloads: GitHub 3.

**2026-11-06 17:23:** Shipped: aec70d7 (README: what's new is 0.5); 2c4981b (buzz: tonight's posts, itch description and devlog draft relabelled 0.5; the 18 Nov update is 0.6). Moved: Mac named the fixed build 0.5, since the 0.4 with the empty-court bug is already public. 0.5 is building, due ~18:00, and goes to itch with --userversion 0.5. itch still holds only the 0.3 build (page in Draft). Blocks: the 0.5 release, then Mac's Publish on itch. Downloads: GitHub 3 (0.4: 1).

**2026-11-06 17:08:** Shipped: 62b2ecd (9:16 hook clip: the grudge reads at phone size from the first frame); 9644fb4 (buzz: creator emails link the clip). Moved: fallback 0.4 released (v0.4-20261106-bef6218, pre-release, with both hook clips attached), but it still has the empty-court bug. The fixed 0.4 is building, due ~17:50, and is the one that goes to itch. Blocks: the fixed release, then Mac's Publish on itch at 18:40. Downloads: GitHub 2 (0.4: 0).

**2026-11-06 16:54:** Shipped: cdabd8f and ac99bd7 (the 0.4 hook clip, 27s, 16:9 and 9:16, end card on the itch link); f5ba354 (fix: the court card no longer opens as an empty bar); 21a396b and 30f0754 (buzz: subreddit flairs and timings; 30 creators checked, eight Mac-channel emails written). Moved: the clip is approved and goes on r/macgaming tonight. The 9:16 opening is being re-cut so the grudge reads on a phone (due tomorrow midday). The main session is releasing a fallback 0.4 around 17:15 and a fixed 0.4 around 18:00 with the clip attached. Blocks: the release (in progress), then Mac's Publish on itch at 18:40. Downloads: GitHub 2.

**2026-11-06 16:38:** Shipped: 8c6ea28 (launch video plan: the hook opens on a lord bringing up the King's tithe); c27703f and 6d9e5a4 (buzz: launch-day runbook, r/SimulationGames post for 0.4). Moved: Mac moved launch to today. The 0.4 release is building again after Mac freed disk (export done, signing next, expected ~17:15). The explainer has resumed the hook clip (due 18:45). itch page description is updated for 0.4 and the devlog is drafted. Agents are checking subreddit rules and building the creator list. Blocks: the release (in progress), Mac's Publish on itch. Downloads: GitHub 2.

**2026-11-06 late:** Studied zero-budget indie launches (Buckshot Roulette, Gambler's Table, The Hive, Content Warning, Digging a Hole, itch-first hits) into docs/buzz/launch.md: 8 Dec launch, creator emails from three weeks out, a hook clip that opens on the payoff, r/macgaming held for launch day, a 1.1 on 20 Dec. Build asks sent to the main session. itch page dressed. The disk filled during the 0.4 dmg build; I flagged it to the main session.

### 11-05 19:50
**Shipped:** the drier earth ring (6bcabd9); three plain CC BY townsfolk in the crowds (d658028); bodies without glowing trims, solid with cut-out hair, crowds spread in twos and threes (2673f86); before/after (a9c4950). Reviewed: keep.
**In progress:** stall keepers and buyers (look pass); medieval bodies wait on Mixamo.
**Needs Mac:** itch images and Publish; post r/macgaming. Downloads: GitHub 2.

### 11-05 19:20
**Moved:** itch processed the v0.3 build (channel mac, 0.3-0f052ff). The page is still a draft (public URL 404). Downloads: GitHub 2.
**Needs Mac:** itch images and Publish; then post r/macgaming.

### 11-05 19:05
**Moved:** v0.3 dmg uploaded to itch with butler (alichherawalla/game-of-crowns, channel mac); itch is processing it. Left for Mac on itch: the cover and screenshots (docs/buzz/images/itch/), then Publish.

### 11-05 18:40
**Moved:** v0.3 released: https://github.com/off-grid-ai/game-of-crowns/releases/tag/v0.1-20261105-0f052ff (pre-release, notarised, Gatekeeper accepted; from 0f052ff: lord memory, 20 s seasons, rider and T-pose fixes, look pass 1, no bundled model). The tag still reads 0.1 because realm/export_presets.cfg's version wasn't bumped. Pushing the dmg to itch with butler (alichherawalla/game-of-crowns:mac).

### 11-05 18:20
**Moved:** itch draft page made. v0.2 (3a62c90) failed twice at the very end (Apple's upload, then its timestamp server); both now retry. Skipping v0.2: v0.3 is building from 0f052ff (lord memory, 20 s seasons, rider fix, look pass phase 1, no bundled model, T-pose fix). Look phase 2 (935a1d8, da4dee0) waits for review.

### 11-05 17:35
**Shipped since 16:45:** the rider never sinks into a hill (3a62c90); two bad stills dropped (e2787b7); ground at true scale and dry mud (16d2715); the tavern's stone yard cut (6e093d7); smoke as wisps (7dd662a); grass and flowers in the wind (71962ea); towns up to 80 people (92456d6); the morning look on by default (62fc53a); look-pass renders (57e2963); no model in the app, recommend Off Grid AI (1c04684, 0239e2c); release tooling: notarisation retry, build any pushed commit (a5fa2f1, 0e0c7b6, 9e6033c).
**Moved:** v0.2 rebuilding from 3a62c90 after Apple's upload dropped; in its final notarisation. v0.3 from origin/main follows it.

### 11-05 16:45
**Shipped (beb839b, pushed):** every house keeps a lasting record of what the King did to it, and a lord raises a year-old deed at court; 20 s seasons; bridge stall fixes (30/30 fast replies over 10 min); no battles on mountainsides; no empty notice card; no progress text on the map; the full-quality capture profile (`--hq`); the look.gd hook. Also the explainer's commits (0e6e3e2, d3641af, 53e74a0, c39aa26, 21c3759, 4a6671f).
**Moved:** cutting v0.2 from beb839b now (packaging/release-mac.sh).
**Open:** people sunk in the ground (main session diagnosing); Freeciv 30–60 s a season in long reigns.

### 11-05 16:04
**Shipped:** explainer cuts committed as source (0e6e3e2; renders stay out of git). Downloads: 1.
**Moved:** Mac reviewed the footage (people half in the ground, captions behind roofs, map progress text); first-impression list sent to the main session; explainer holding final renders until fixes land.
**Blocking:** lord test, then fixes 1–3, then push and v0.2.

### 11-05 15:30
**Moved:** Mac said yes to relaunching his game for the main session to test the lord work; it commits and pushes once the lord's deed shows on screen, then v0.2.

### 11-05 15:20
**Shipped:** nothing since 14:05. Drafts ready to paste: r/macgaming, Mac creator DMs, itch.io page, r/SimulationGames, r/4Xgaming (docs/buzz/channel-0*.md). Downloads: 1.
**Blocking:** the approved lord and pace work, uncommitted since 12:38: the main session is waiting for Mac's OK to relaunch his game and test; none of the drafts posted yet (Mac).

### 11-05 14:05
**Moved:** first public build is out: https://github.com/off-grid-ai/game-of-crowns/releases/tag/v0.1-20261105-622eb2d (1.8 GB dmg, signed and notarised, Gatekeeper: accepted, source=Notarized Developer ID). Built from origin/main 622eb2d, so it has none of the in-progress lord and pace work.
**Next:** channel drafts, r/macgaming first. A fresh-Mac install test is worth doing before posting.

### 11-05 13:50
**Moved:** Mac chose to build on this Mac and keep the art off GitHub. The art upload is stopped and its draft deleted; the runner workflow is removed. packaging/release-mac.sh builds from origin/main in a scratch folder (art hard-linked), signs with the keychain's Developer ID, notarises and publishes a pre-release. First run started 13:50. Mac cleared ~25 GB.

### 11-05 13:40
**Shipped:** no game commits since the last run.
**Moved:** first release run (self-hosted) failed: the Mac's disk filled (418/460 GB already used). Per Mac, the release now runs on GitHub's macOS runner like OGAD: the self-hosted runner is removed from this Mac and GitHub; the art is uploading in 900 MB parts to the repo's private draft release `art-store` (packaging/upload-art.py); the new workflow is written, to commit with the art checksum when the upload ends.
**Blocking:** CSC_LINK and CSC_KEY_PASSWORD (Mac); the art upload.

### 11-05 13:19
**Moved:** issuer ID set (all three notarisation secrets in place); main pushed to origin (622eb2d) by the main session; first Release (Mac) run started as a pre-release: https://github.com/off-grid-ai/game-of-crowns/actions/runs/41989850181
**Blocking:** the run itself (it may stop for a keychain prompt on this Mac: click Always Allow).

### 11-05 13:20
**Moved:** `Release (Mac)` GitHub Action written after OGAD's (03a7413): self-hosted runner `goc-mac` on this Mac (the art stays out of git by licence, so the runner copies it from the working copy), signs with the keychain's Developer ID, notarises, staples, publishes a Release. Secrets APPLE_API_KEY and APPLE_API_KEY_ID set; outside contributors' PR workflows need approval. Repo made findable: description, 16 topics, README leads with the pitch and the download link.
**Blocking:** the issuer ID (Mac); the commits pushed to origin (main session) so the workflow can be run.

### 11-05 13:10
**Shipped since the morning (main, all sessions):** the clear view while watching (f1d7c86, 683ddfe, d1e4a28); watched scenes keep trees out of the shot (083bf6d); towns and life polish pass 2 (318b614); knights cast in plate, ladies in gowns (9783007, b9f22ea); README matches the game (c472f92); town cards offer only unbuilt buildings (5b482b4); the court says when someone comes (4e555f1); riders on the road (99b65ba, 3e0517c, 5c30bfe).
**Moved:** the repo is public: https://github.com/off-grid-ai/game-of-crowns (gitleaks: no leaks in 374 commits).
**Blocking:** no signed dmg, no release.
