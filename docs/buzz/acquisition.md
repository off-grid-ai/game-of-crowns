# Getting the first players (2026-11-05)

virality.md is how players bring more players. This is how the first ones arrive, from zero: no audience, no followers, a Reddit account with one quiet post.

## What a stranger has to do today
- **Download a Mac app** (Apple Silicon only), double-click, play. docs/SHIPPING.md: one script builds the app and dmg.
- **First run fetches a 1.8 GB model.** Until it's ready, lords decide by rules and have no voice of their own, so a first 5-minute reign may never show the hook.
- **Signing:** without the Developer ID secrets the build is ad-hoc signed, and Gatekeeper blocks it on every other Mac. The secrets live on the Off Grid AI Desktop repo.
- **No Windows build.** About 95% of Steam players and most streamers are on Windows.

So the first players are Mac gamers. Mac has ruled out the local-AI crowd (r/LocalLLaMA, Hacker News); see community.md for the gaming-first plan and the Discord.

## The funnel, and what breaks it
| Step | What decides it | What we do |
|---|---|---|
| **Sees it** | where we post, and whether the first 3 seconds hook | a 20–30s clip of a lord remembering, at the top of every post and the README |
| **Clicks** | the one-line promise | "A kingdom where every lord remembers what you did. Free and native on Apple Silicon." |
| **Installs** | Mac only, 1.8 GB, Gatekeeper | signed and notarised build; say the download size up front; GitHub Releases plus an itch.io page (itch shows downloads by referrer) |
| **Gets the hook in 5 minutes** | model not ready, no lord speaks | start the model download at once, and make the first reign show a lord remembering |
| **Tells someone** | virality.md: friends in the realm, the saga card | the card carries the game's name and link; naming a friend gives you someone to send it to |

## Wave 1: Mac gamers (now)
See community.md: r/macgaming, Mac gaming creators, the sim subs with a clip, comments in WorldBox and map-sim threads, r/godot. Every post invites people into the Discord, where they're written into the Founders' Realm.

**Target:** 300 downloads, 100 finished reigns, 100 Discord members.

## Wave 2: gamers and creators (needs a Windows build)
1. **30 cold DMs** to mid-size creators (10k–200k subscribers) who play WorldBox, Ages of Conflict, map sims, Manor Lords, or AI games. One line, the clip, a download link, and streamer mode (chat names become lords). Suck Up! went from cold DMs to the biggest streamers in two weeks.
2. **Short clips weekly** on TikTok and Shorts, mostly to hand to creators and subs; our own account starting from zero brings little on its own.
3. **A $300 Reddit ads test** on the best clip, kept only under $3 a download.
4. **Steam page** once Windows exists: free, nothing locked. Steam's own traffic is half of everything after that.

## What Mac's time goes on
Replying on post days (a few hours), the 30 DMs (an hour, messages drafted here), and nothing else recurring. Clips come from watch mode; drafts come from this session.

## Measure each step, by channel
Views → clicks (itch.io and GitHub referrers) → downloads → finished reigns (count only, with consent) → saga cards seen posted. Drop any channel that brings nothing after two tries.

## Build asks this adds (sent to the main session)
1. Signed and notarised Mac release (the secrets copied from Off Grid AI Desktop) and a GitHub Release with the dmg. Blocks wave 1.
2. First-run hook: begin the model download immediately with a progress line, and make the first reign show a lord remembering something, even if he speaks by rules until the model is ready.
3. A Windows build before wave 2.
