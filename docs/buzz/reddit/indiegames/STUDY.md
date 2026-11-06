# r/indiegames: what wins and what flops (study, 6 Nov 2026)

## Bottom line
- **Don't post Game of Crowns here until a mod says yes.** The sub bans generative-AI games. Users cite "Rule 12" ([1vn7vha](https://www.reddit.com/r/indiegames/comments/1vn7vha/), 2,166 pts, 1,561 comments), and on 29 Oct a mod posted "Generative ai games are banned on this sub" and asked people to report them ([1xip8l2](https://www.reddit.com/r/indiegames/comments/1xip8l2/), 1,201 pts). Our launch film, itch cover and intro/loading screens are AI-painted, and the lords can speak through a local model. The painted film would get reported and removed.
- If a mod clears it, post **real gameplay as a Reddit-hosted video** with the "Video" flair, and a title that says what the player does. That combination wins here. "Free", platforms, store words and a game name at the front lose.

## How the data was collected
- Reddit blocks automated reads from this machine (403 on `reddit.com/*.json`, and the in-app browser refuses reddit.com). I used **Arctic Shift**, a public Reddit archive (`arctic-shift.photon-reddit.com`). It stores each post twice, the second time about 36 hours or more after posting, so the scores below are the settled ones, not the first-hour ones.
- **All 49,839 posts** from 3 Nov 2025 to 3 Nov 2026, plus full bodies and comment trees (up to 400 comments) for the 33 posts in the tables. Instead of `search.json` I filtered the full year by keyword ("my game", released, free, strategy, medieval, kingdom, AI), which covers the same ground with nothing missing.
- "Dev post" means the title or the first 300 characters of the body use I/my/we/our: 33,354 of the 49,839 posts.
- **Rules:** `about/rules.json` is blocked. Sources: the sidebar text (archived), a 2018 Wayback copy of the rules ("Not an image/gif/video showing game footage" was a removal reason; AutoModerator required footage), AutoModerator's reply on every post, and what users and mods say about Rule 12. **The current rule wording is unconfirmed.** Read /about/rules logged in before posting.

## What the whole year says
The median score is 1 and the 90th percentile is 8. Only 2.15% of dev posts reach 100 points, so "did well" means 200 or more. The table shows how much more or less likely a post with each feature was to reach 100, against that 2.15% base rate.

| Feature (dev posts) | n | Reach 100+ | vs base | Score ≤1 |
|---|---|---|---|---|
| Title says "no AI" / handmade | 209 | 7.2% | ×3.3 | 43% |
| Title gives time spent ("3 years") | 1,434 | 5.4% | ×2.5 | 55% |
| Media: Reddit-hosted video | 17,035 | 3.3% | ×1.5 | 54% |
| Title "I'm making / I made a game where/about…" | 893 | 2.9% | ×1.4 | 64% |
| Title has genre words | 4,982 | 2.4% | ×1.1 | 61% |
| Body empty | 13,100 | 2.5% | ×1.2 | 71% |
| Body over 1,200 characters | 1,951 | 1.2% | ×0.6 | 63% |
| Title is a question | 2,258 | 1.2% | ×0.6 | 59% |
| Title led by the name (colon or dash) | 6,823 | 1.2% | ×0.5 | 69% |
| Title says "free" | 1,331 | 1.1% | ×0.5 | 74% |
| Body links a store or itch | 1,865 | 1.0% | ×0.5 | 76% |
| Text or link post, no media | 7,097 | 0.6% | ×0.3 | 81% |
| Media: YouTube link | 2,129 | 0.05% | ×0.0 | 68% |
| Title says Mac/macOS | 25 | 0% | ×0 | 76% |

**Flair** (same content, different label): Video 5.4% reach 100, Personal Achievement 4.6%, Image 3.4%, Upcoming 2.2%, Promotion 1.3% (n=13,959), Need Feedback 0.8%. Part of this is who picks which flair, but a launch trailer posted as "Video" did fine ([1w77z24](https://www.reddit.com/r/indiegames/comments/1w77z24/), 855).

**Timing** barely matters. By weekday the range is 2.0–2.4%. By hour (UTC): 09–12 is best at 2.8% and 18–21 worst at 1.5%. Post between 14:30 and 17:30 IST.

Store-link counts look only at each body's first 400 characters, so they undercount long bodies.

## What separates winners from flops

**1. The title is a verb the player does, in plain words.** Winners name an action you can picture before you watch: "you eliminate others by typing the number on their forehead" (4,388), "monsters only move when you blink" (1,996), "escaping a country that won't let you leave" (1,055), "Dracula is tired of so-called heroes invading his castle" (1,423; top comment: "Immediately parseable", 58). Flops name the product or the genre: "Hey everyone! I just released my demo for Tiny Throne, a roguelike deckbuilder with city-building mechanics" (1), "Stick Infinite Kingdom: Bringing epic stickman warfare to a 3D Action RTS" (1), "Our mountain city builder, Laysara: Summit Kingdom, just launched in 1.0" (3, from a real studio).

**2. Reddit-hosted video is close to required, and a YouTube link kills the post.** Every winner but two uses a Reddit-hosted clip of 19–95 seconds (the exceptions: a gif gallery and a single image). Even release posts that link a trailer on YouTube upload a Reddit video first ([1xin46c](https://www.reddit.com/r/indiegames/comments/1xin46c/), 531). One YouTube-link post in 2,000 reached 100.

**3. Nothing on how the clips open.** Reddit's video host is blocked here, so I couldn't watch them. What comments praise is a clip you understand at once ("Immediately parseable"). Treat that as a hint, not a measurement.

**4. Keep the body short or leave it empty.** Winners use 0–500 characters: one line on what you do, sometimes a thank-you or the time it took. Flops paste press releases and feature bullets ([1x3tlvu](https://www.reddit.com/r/indiegames/comments/1x3tlvu/), 1,638 characters, 1 pt; [1vxqfs6](https://www.reddit.com/r/indiegames/comments/1vxqfs6/) with ✓ bullets and a "Play free" button, 3).

**5. "Free" and platform lists in the title hurt.** The closest match to our post is a satire strategy game with a crowned gator at a summit. The twist was good, the title ended "is out now, free on iPhone and web", and it scored 0 ([1xlg2m6](https://www.reddit.com/r/indiegames/comments/1xlg2m6/), posted Sunday 22:14 UTC).

**6. A human stake helps.** "It took me 3 years" (1,186), "5 years in the making… hitting 1.0" (427), "We took your advice and added a playable mother character" (2,316, OP replied 77 times).

**7. Being in the thread goes with winning,** but it's an effect as much as a cause, because flops get one or two comments to answer. Most winners' OPs replied 4 to 77 times (two replied once or not at all), while most flops had no reply from the OP.

**8. AI is the biggest factor in this sub right now.**
- It's against the rules: "Rule 12 already clarifies that genAI posts arent allowed" (144 pts, in 1vn7vha), and the mod's post asking people to report AI games.
- AI art is spotted and called out even when it isn't AI. The second comment on "It took me 3 years" (1,186) was "Are the backgrounds AI?" (65), and the OP had to deny it.
- Capsule and promo art gets the same treatment: "If your Steamfest game uses AI for capsule art, it'll just get skipped" (1,039). Our launch film is promo art painted by AI, which is exactly this case.
- Code is treated more gently, but not settled. "So code development as well? Code auto complete?" (186) pushed back on a blanket ban. In r/IndieGaming's big thread, most top comments accept AI code and reject AI art.
- "No AI" sells: "No AI, just handcrafted art" (583), and "itch.io has added a No AI tag" was the sub's #2 post of the year (3,008).
- **Evidence on AI characters (LLM dialogue) is thin here:** 194 posts mention LLMs, ChatGPT, Claude or vibe coding, with a median score of 1, and the only three over 100 aren't about AI characters. The r/IndieGaming study has the direct cases (removed, "No.", "FUCK NO").

**9. Rule pitfalls:** AutoModerator checks for footage (2018 rules). The sidebar asks for gifs or video so people "can see what the game is about". Bodies of some promo posts were removed (Dadi Kingdom "rule as the king", [1wamqsc](https://www.reddit.com/r/indiegames/comments/1wamqsc/); a free strategy MMO, [1vbpzn2](https://www.reddit.com/r/indiegames/comments/1vbpzn2/)), reason unknown. Our earlier note says feedback posts may not link your own game (2024).

## What doesn't predict
Body length (empty or 400 characters, both fine), weekday, "you" in the title by itself, genre words by themselves, and emoji. Two wins break the pattern. A genre-only title, "isometric strategy game i've been working on" (1,109), won on its art: no body, a gif gallery, and the top comment asked for a better video. A strong twist died behind "free on iPhone and web" (0).

## Compared with r/IndieGaming
Both reward a player-action title and Reddit-hosted video, and both punish YouTube links, "free", name-first titles and AI art. r/indiegames is the smaller sub (2.15% of dev posts reach 100 against 3.8%), it's harsher on question titles (×0.6 against ×1.1), and its AI ban is a written rule with a mod asking for reports. r/IndieGaming removes under a "GenAI" reason but let a post with disclosed AI music and code through. See [../indiegaming/STUDY.md](../indiegaming/STUDY.md).

## The Hacker News finding, tested here
On Hacker News, titles separated winners from flops and bodies didn't. That holds here too. Title features swing from ×0.5 to ×3.3, while body length only moves things between ×0.6 and ×1.2. In the scored sample, winners' titles average 6.3/8 against 2.3/8 for flops. Here, though, the media matters as much as the title: posts with no video almost never win, whatever the title says.

## Every post studied
Media is how the post was uploaded. Body is the number of characters, links counts the distinct URLs in the body, and OP replies counts the archived comments by the poster.

### Winners (dev posts, 200+ points)

| Pts | Cmts | OP replies | Date (UTC) | Title | Media | Body | Links | Notes |
|---|---|---|---|---|---|---|---|---|
| 4388 | 305 | 9 | 2026-10-03 Sat 12:17 | [I'm making a game where you eliminate others by typing the number on their forehead](https://www.reddit.com/r/indiegames/comments/1wwluai/im_making_a_game_where_you_eliminate_others_by/) | Reddit video 60s | 0 | 0 | Upcoming flair; empty body; hook is the verb; Steam link left to a comment |
| 2316 | 163 | 77 | 2026-06-09 Tue 03:41 | [We took your advice and added a playable mother character to our game! Here is the new trailer for Flip-Flop Fury :)](https://www.reddit.com/r/indiegames/comments/1u0twm2/we_took_your_advice_and_added_a_playable_mother/) | Reddit video 38s | 476 | 0 | Video flair; 'took your advice' story; OP replied 77 times; no link in body |
| 1996 | 168 | 9 | 2026-10-24 Sat 13:52 | [I made a game where monsters only moves when you blink, and the game watches you through your webcam](https://www.reddit.com/r/indiegames/comments/1xe98ap/i_made_a_game_where_monsters_only_moves_when_you/) | Reddit video 83s | 373 | 2 | Upcoming; webcam twist; top comment is a privacy objection (311) but still won |
| 1423 | 85 | 13 | 2026-04-22 Wed 14:43 | [I'm making a game where Dracula is tired of so-called heroes invading his castle](https://www.reddit.com/r/indiegames/comments/1ssnk37/im_making_a_game_where_dracula_is_tired_of/) | Reddit video 19s | 283 | 1 | Video flair; 'Immediately parseable' (58); YouTube link only as the full-trailer extra |
| 1186 | 123 | 28 | 2026-04-22 Wed 14:05 | [It took me 3 years, now it's finally time to show my adventure game project](https://www.reddit.com/r/indiegames/comments/1ssmikn/it_took_me_3_years_now_its_finally_time_to_show/) | Reddit video 60s | 90 | 1 | Promotion; '3 years'; second comment asks 'Are the backgrounds AI?' (65), OP denied |
| 1109 | 53 | 6 | 2026-07-30 Thu 12:31 | [isometric strategy game i've been working on](https://www.reddit.com/r/indiegames/comments/1vasbi4/isometric_strategy_game_ive_been_working_on/) | gallery | 0 | 0 | Promotion; GENRE-ONLY title, gifs carried it; rubric miss |
| 1055 | 166 | 4 | 2026-10-10 Sat 12:43 | [I'm making a game about escaping a country that won't let you leave](https://www.reddit.com/r/indiegames/comments/1x2eeay/im_making_a_game_about_escaping_a_country_that/) | Reddit video 23s | 130 | 0 | Upcoming; one-line body, 'solo in Godot' |
| 1063 | 141 | 71 | 2026-09-16 Wed 09:02 | [I made a game about going on a date with a girl you met online… in a town that really doesn’t want you there](https://www.reddit.com/r/indiegames/comments/1whrwdk/i_made_a_game_about_going_on_a_date_with_a_girl/) | Reddit video 38s | 481 | 0 | Video flair; open playtest; OP replied 71 times |
| 855 | 72 | 11 | 2026-09-04 Fri 15:43 | [Out today: My remote work simulator where you’re secretly a worm. It’s called “Worming from Home!”](https://www.reddit.com/r/indiegames/comments/1w77z24/out_today_my_remote_work_simulator_where_youre/) | Reddit video 59s | 298 | 0 | Video flair; 'Out today' launch post that worked: the joke leads, the name trails |
| 531 | 107 | 32 | 2026-10-29 Thu 15:28 | [We just released our cyberpunk shopkeeper sim, Probably Stolen, and out of nowhere, it's now in Steam's Top 15 most-played games. We're blown away.](https://www.reddit.com/r/indiegames/comments/1xin46c/we_just_released_our_cyberpunk_shopkeeper_sim/) | Reddit video 95s | 374 | 1 | Promotion; release + real numbers (200k sold); Reddit video, YouTube only in body |
| 660 | 16 | 1 | 2025-12-03 Wed 15:10 | [One year of progress on our city-building strategy about a fantasy settlement on a train](https://www.reddit.com/r/indiegames/comments/1pd6qhl/one_year_of_progress_on_our_citybuilding_strategy/) | image | 0 | 0 | Promotion; single before/after image; 'one year of progress' |
| 214 | 31 | 16 | 2026-02-24 Tue 17:30 | [I made a teaser trailer for my very first video game, a narrative-heavy medieval roadtrip](https://www.reddit.com/r/indiegames/comments/1rdmnmi/i_made_a_teaser_trailer_for_my_very_first_video/) | Reddit video 29s | 294 | 1 | Promotion; medieval; 'very first video game', 29s teaser; own-site link |
| 427 | 58 | 18 | 2026-08-06 Thu 10:47 | [5 years in the making and our post-apocalyptic farming sim is finally hitting 1.0!](https://www.reddit.com/r/indiegames/comments/1vh0rx3/5_years_in_the_making_and_our_postapocalyptic/) | Reddit video 50s | 0 | 0 | Video flair; '5 years', 1.0 launch; regulars congratulate |
| 583 | 29 | 0 | 2026-05-08 Fri 12:58 | [No AI, just handcrafted art](https://www.reddit.com/r/indiegames/comments/1t777bl/no_ai_just_handcrafted_art/) | Reddit video 31s | 324 | 2 | Promotion; 'No AI, just handcrafted art'; top comment: 'the new locally sourced ingredients' (78) |

### Flops (comparable dev posts, 0-4 points)

| Pts | Cmts | OP replies | Date (UTC) | Title | Media | Body | Links | Notes |
|---|---|---|---|---|---|---|---|---|
| 0 | 2 | 1 | 2026-11-01 Sun 22:14 | [My satire strategy game where a crowned gator hosts a summit of lying world leaders is out now, free on iPhone and web](https://www.reddit.com/r/indiegames/comments/1xlg2m6/my_satire_strategy_game_where_a_crowned_gator/) | Reddit video 16s | 0 | 0 | strategy satire; 'out now, free on iPhone and web'; Sunday 22:14 UTC; strong twist still died |
| 0 | 3 | 1 | 2026-04-09 Thu 14:15 | [My strategy game Mech Tech is LIVE on Kickstarter!](https://www.reddit.com/r/indiegames/comments/1sgquha/my_strategy_game_mech_tech_is_live_on_kickstarter/) | Reddit video 74s | 106 | 0 | strategy; Kickstarter ask in title |
| 1 | 2 | 1 | 2026-04-11 Sat 17:15 | [Hey everyone! I just released my demo for Tiny Throne, a roguelike deckbuilder with city-building mechanics.](https://www.reddit.com/r/indiegames/comments/1siovss/hey_everyone_i_just_released_my_demo_for_tiny/) | YouTube link | 0 | 0 | 'Hey everyone! I just released my demo for Tiny Throne'; YouTube link; genre list; same title posted in 3 subs |
| 1 | 1 | 0 | 2026-09-08 Tue 12:14 | [Dadi Kingdom, our medieval fantasy RPG where you rule as the king, is competing in the DevGAMM Awards 2026](https://www.reddit.com/r/indiegames/comments/1wamqsc/dadi_kingdom_our_medieval_fantasy_rpg_where_you/) | Reddit video 57s | 9 | 0 | medieval 'rule as the king'; name first; award news; body removed |
| 1 | 1 | 1 | 2026-08-12 Wed 19:54 | [Cozy strategy mahjong game, but not another one, this one is fully free and without ads.](https://www.reddit.com/r/indiegames/comments/1vmor87/cozy_strategy_mahjong_game_but_not_another_one/) | Reddit video 65s | 1028 | 1 | 'fully free and without ads'; body is a speech about ads |
| 1 | 1 | 0 | 2026-10-12 Mon 05:34 | [Island Shield, a browser strategy game with multiplayer mode. (no ads, no cookies, no p2w)](https://www.reddit.com/r/indiegames/comments/1x3tlvu/island_shield_a_browser_strategy_game_with/) | Reddit video 108s | 1638 | 3 | free browser strategy; 1,638-char body with feature list and credits |
| 1 | 1 | 0 | 2025-12-19 Fri 21:22 | [Campaign mode arrives in the demo of the turn-based strategy game Tabletop Fantasy War!](https://www.reddit.com/r/indiegames/comments/1pqwqu6/campaign_mode_arrives_in_the_demo_of_the/) | Reddit video 101s | 1180 | 0 | strategy demo update; press-release body |
| 1 | 1 | 0 | 2026-07-31 Fri 12:47 | [I made a free military strategy MMO for mobile - deep economy, real PvP, no pay-to-win [Build & Conquer]](https://www.reddit.com/r/indiegames/comments/1vbpzn2/i_made_a_free_military_strategy_mmo_for_mobile/) | gallery | 9 | 0 | 'I made a free military strategy MMO'; spec list title; removed |
| 3 | 1 | 0 | 2026-02-28 Sat 00:19 | [Our mountain city builder, Laysara: Summit Kingdom, just launched in 1.0 on Steam & consoles!](https://www.reddit.com/r/indiegames/comments/1rgnrom/our_mountain_city_builder_laysara_summit_kingdom/) | YouTube link | 0 | 0 | kingdom city builder 1.0; YouTube link; name first (real studio, still 3 pts) |
| 3 | 1 | 1 | 2026-08-25 Tue 05:08 | [I made a minimalist railway strategy game about one evolving junction](https://www.reddit.com/r/indiegames/comments/1vxqfs6/i_made_a_minimalist_railway_strategy_game_about/) | text | 494 | 2 | free browser strategy; checkmark feature bullets; 'Play free' CTA |
| 1 | 1 | 0 | 2026-09-06 Sun 21:25 | [As a small indie team, we developed our medieval action game The Thandor in UE5. Here is our first vertical slice trailer!](https://www.reddit.com/r/indiegames/comments/1w98qoi/as_a_small_indie_team_we_developed_our_medieval/) | Reddit video 73s | 123 | 1 | medieval; 'in UE5' stack in title; wishlist-only body |
| 2 | 1 | 0 | 2026-10-23 Fri 21:10 | [We made a puzzle game about bridgemancy: conjure bridges to rescue villagers from a crumbling kingdom](https://www.reddit.com/r/indiegames/comments/1xdq6tk/we_made_a_puzzle_game_about_bridgemancy_conjure/) | gif | 984 | 1 | kingdom puzzle; free demo; long rules explanation |
| 0 | 4 | 2 | 2026-04-09 Thu 20:45 | [Solo dev cultivation deckbuilder where your realm changes how combat works](https://www.reddit.com/r/indiegames/comments/1sh1s8a/solo_dev_cultivation_deckbuilder_where_your_realm/) | YouTube link | 703 | 0 | 'Solo dev cultivation deckbuilder'; genre-led; YouTube |
| 1 | 1 | 0 | 2026-07-06 Mon 12:08 | [Stick Infinite Kingdom: Bringing epic stickman warfare to a 3D Action RTS](https://www.reddit.com/r/indiegames/comments/1uovhb7/stick_infinite_kingdom_bringing_epic_stickman/) | YouTube link | 672 | 1 | 'Stick Infinite Kingdom:' name first; marketing bullets |

### AI evidence threads

| Pts | Cmts | OP replies | Date (UTC) | Title | Media | Body | Links | Notes |
|---|---|---|---|---|---|---|---|---|
| 2166 | 1561 | 17 | 2026-08-13 Thu 11:19 | [AI art in your game should be an instant ban from this sub](https://www.reddit.com/r/indiegames/comments/1vn7vha/ai_art_in_your_game_should_be_an_instant_ban_from/) | text | 75 | 0 | 'AI art in your game should be an instant ban'; users cite Rule 12 (genAI posts not allowed) |
| 1201 | 544 | 15 | 2026-10-29 Thu 16:46 | [Please report all these AI slop posts](https://www.reddit.com/r/indiegames/comments/1xip8l2/please_report_all_these_ai_slop_posts/) | text | 358 | 0 | Mod post: 'Generative ai games are banned on this sub'; asks users to report |
| 1039 | 291 | 21 | 2026-10-20 Tue 15:01 | [If your Steamfest game uses AI for capsule art, it'll just get skipped.](https://www.reddit.com/r/indiegames/comments/1xaugsf/if_your_steamfest_game_uses_ai_for_capsule_art/) | text | 353 | 0 | 'If your Steamfest game uses AI for capsule art, it'll just get skipped' |
| 3008 | 478 | 0 | 2026-11-03 Tue 06:40 | [itch.io has added a No AI tag](https://www.reddit.com/r/indiegames/comments/1xmluvl/itchio_has_added_a_no_ai_tag/) | image | 0 | 0 | itch.io adds a No AI tag (3,008 pts, the sub's #2 post of the year) |
| 102 | 23 | 8 | 2025-11-06 Thu 16:41 | [I'm making a fulfillment center sim inspired by Papers, Please — what do you think?](https://www.reddit.com/r/indiegames/comments/1oq3vim/im_making_a_fulfillment_center_sim_inspired_by/) | Reddit video 15s | 490 | 0 | Papers-Please-like sim; no AI mention, normal reception (control) |
