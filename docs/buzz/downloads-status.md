# Downloads: status (kept by the downloads supervisor)

Goal: get the game into people's hands. Plan: acquisition.md. Updated each supervisor run.

## Blockers to the first download, in order
| # | Ask | Owner | Status (2026-11-05 start) |
|---|---|---|---|
| 1 | Repo public (open source) | Mac | **Done** 11-05 13:09: public, secrets scan clean |
| 2 | Signed and notarised Mac dmg | buzz session | **Done** 11-05 14:03 (notarised, stapled, Gatekeeper accepted). Earlier: Not built. 11-05 13:06: a Developer ID Application identity is in this Mac's keychain (Wednesday Solutions, 84V6KCAC49), so signing can run here (`SIGN_IDENTITY`); notarisation still needs the App Store Connect API key (none found locally) |
| 3 | GitHub Release with the dmg | buzz session | **Done** 11-05 14:03: v0.1-20261105-622eb2d (pre-release). Earlier: No releases. 11-05 13:40: Release (Mac) workflow moving to GitHub's runner; needs CSC_LINK/CSC_KEY_PASSWORD from Mac |
| 4 | Free itch.io page with the dmg | buzz session | 11-06 17:08: fallback 0.4 on GitHub (v0.4-20261106-bef6218, empty-court bug); the fixed build ships as 0.5 (~18:00) and goes to itch. 16:38: v0.3 dmg on itch; cover, 8 screenshots, 0.4 description, launch devlog drafted. 0.4 dmg goes up when the release lands (~17:15). **Launch is today**: Mac publishes at 18:40 IST |
| 5 | First-run hook (model download at once; a lord remembering in the first reign) | main session | Asked |
| 6 | A lord remembering on screen + a 20–30s clip | main session / goc-media | Lord memory shipped (court petitions name the season and year). Hook clip done 16:52 (docs/buzz/video, 16:9 and 9:16); goes to r/macgaming tonight and onto the 0.4 GitHub release |
| 7 | Windows build | main session | Asked, after 1–6 |

## Channels (once 1–6 are done)
| Channel | Posted | Downloads |
|---|---|---|
| r/macgaming | today 19:00 IST (Mac) | – |
| Andrew Tsai + Mac creators (DMs) | – | – |
| itch.io browse (tags) | – | – |
| r/SimulationGames | – | – |
| r/4Xgaming | – | – |
| WorldBox / map-sim threads (comments) | – | – |
| r/godot | – | – |

## Downloads per week
| Week | GitHub | itch.io | Total |
|---|---|---|---|
| 11-05 | 2 (v0.1: 1, v0.3: 1) | page still draft | 2 |
