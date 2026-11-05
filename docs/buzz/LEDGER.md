# Downloads ledger

Kept by the downloads supervisor (every 15 minutes in the buzz session). Goal: get the game into people's hands. Newest run first.

## Needs Mac
- **Disk:** this Mac has ~4 GB free of 460 GB. It killed the first release run and will hurt other sessions' renders.
- **Promo art:** prompts for Codex in docs/buzz/asset-prompts.md (GitHub social preview, itch.io cover, key art). The social preview has to be set by hand in the repo's Settings.
- **itch.io:** account created 11-05; next, the project page (docs/buzz/channel-03-itch.md) and the upload with butler (the dmg is over itch's 1 GB web limit).
- **The lady's licence:** confirm the Sketchfab ownership claim for 'Princess Nun Royal Queen' (b9f22ea). A licence question only: .gitignore keeps body files out of git, so pushes publish no model files.
- **Approve the rest of the list below** (everything marked "proposed").

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
- **Explainer:** pass 2 planned (PASS2.md: 70% world, memory one beat); holding takes until the look pass and the main session's fixes are pushed.
- **Main session:** testing the lord work in Mac's relaunched game; then close-up stills (docs/buzz/images/zoom/live/) and the first-impression fixes 1–3 (docs/buzz/first-impression.md) before pushing.
- **Explainer session (goc-explainer):** briefed 11-05 13:25 by the buzz session: a 20–30 s clip of a lord remembering and a 60–90 s explainer, after the lord work lands; files to docs/buzz/video/.
- **Buzz session:** this ledger, the supervisor, drafts for the channels once the dmg exists.

## Runs

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
