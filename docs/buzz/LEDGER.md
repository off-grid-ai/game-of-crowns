# Downloads ledger

Kept by the downloads supervisor (every 15 minutes in the buzz session). Goal: get the game into people's hands. Newest run first.

## Needs Mac
- **Disk:** this Mac has ~4 GB free of 460 GB. It killed the first release run and will hurt other sessions' renders.
- **Promo art:** prompts for Codex in docs/buzz/asset-prompts.md (GitHub social preview, itch.io cover, key art). The social preview has to be set by hand in the repo's Settings.
- **itch.io:** a free page for the dmg (needs your account).
- **The lady's licence:** confirm the Sketchfab ownership claim for 'Princess Nun Royal Queen' (b9f22ea). A licence question only: .gitignore keeps body files out of git, so pushes publish no model files.
- **Approve the rest of the list below** (everything marked "proposed").

## Recommendations
Current list: **downloads-first** (11-05 ~13:00), which replaced the virality list (~12:40), which replaced the first list (~12:20).

| Ask | Status |
|---|---|
| Lords keep a lasting record of the King's deeds | Approved by Mac ("Do all of it"); in progress (main session) |
| A lord brings a year-old deed up at court in his own words | Approved; in progress |
| The chronicle names the cause when a house cools, rebels or refuses the banners | Approved; in progress |
| Seasons 20 s instead of 90 s | Approved; in progress |
| Repo public | **Shipped** 11-05 13:09 (Mac approved; secrets scan clean) |
| Signed and notarised Mac dmg + GitHub Release | **Shipped** 11-05 14:03: v0.1-20261105-622eb2d, pre-release, notarised Developer ID (packaging/release-mac.sh) |
| First-run hook: model download at once, a lord remembering in the first reign | Proposed |
| A 20–30 s clip of a lord remembering | Proposed (after the lord work lands) |
| Windows build | Proposed |
| Friends as lords (naming screen; later Discord names) | Proposed, parked (later) |
| Saga card at the end of a reign | Proposed, parked |
| Lords answer outrageous rulings in character | Proposed, parked |
| Daily realm; watch mode with clip export | Proposed, parked |
| Community realm (Founders' Realm, weekly reign) | Proposed, parked (Mac: downloads first) |
| Art licences cleared; separate demo build | Dropped (Mac: not the bottleneck; the game is the demo) |

## In progress
- **Main session:** the four approved lord and pace changes (not yet committed).
- **Explainer session (goc-explainer):** briefed 11-05 13:25 by the buzz session: a 20–30 s clip of a lord remembering and a 60–90 s explainer, after the lord work lands; files to docs/buzz/video/.
- **Buzz session:** this ledger, the supervisor, drafts for the channels once the dmg exists.

## Runs

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
