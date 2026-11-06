# Game of Crowns 0.4 launch video: plan

Brief from the buzz session (2026-11-06). Downloads are the goal. ~40 s at 16:9 plus a 9:16 cut, with burned-in
captions, every line in Mac's voice. It shows only what's in 0.4 on main.

## The hook clip first (docs/buzz/launch.md, db6fe27): the payoff in the first 3 seconds
Never open on a menu, a logo or the map. Beautiful mode.
| s | Shot | Line |
|---|---|---|
| 0–3 | The court: Osric Stormhold's petition, live in The Grain Lords (Spring 329-ish): "Since the autumn of 311, you bled us with the tithe, year after year. House Stormhold has not forgotten it, Your Grace." | (his words are the caption, pushed in) |
| 3–6 | "Eighteen years earlier" over the tithe control the King sets (Tithe 20 %, − +) | Eighteen years earlier. |
| 6– | the realm running: a busy town, years passing, Stormhold's favour on the houses table | Every lord remembers what you did. |
The 18 years must match the in-game date at the moment of filming (311 to the current year).

## Beats and lines for the 40 s launch film (draft; mac-voice then no-ai-slop before the build)
| # | Shot (live game, Beautiful, Movie Maker 30 fps) | Line |
|---|---|---|
| 1 | The strongest moving shot: a busy town in morning light (or the war table) | A kingdom that runs itself. |
| 2 | Drawing back until the painted map of Aldmere takes over, then diving into a town | — |
| 3 | A lord's card with their past: Beatrix Strand, "Served the Wolfholt bride her last cup at Goldrock as a girl, and has never told what was in it." | Every lord remembers what you did. |
| 4 | Edit beside a name: the name becomes the field and a new name is typed in | Rename anyone. Your brother can be the one who turns on you. |
| 5 | Meet: Cecily Goldcrest in Goldcrest's oak grove, then a Wolfholt lord in snow and pines; a petition at court | Meet them in their own land. |
| 6 | End card: the Off Grid AI seal, "Game of Crowns. Free on Apple Silicon.", github.com/off-grid-ai/game-of-crowns | |

The game's launch (the seal, the war table, the storybook intro) is recorded too; its seal goes on the end card.

## Capture
- Only with the main session's "yours": Mac is playing pid 58564.
- `realm.sh start` (the bridge), then
  `GOC_HAND=/tmp/goc-hand arch -arm64 godot --path realm --write-movie <scratch>/take.avi --fixed-fps 30 -- --hq`,
  driven by `realm/tools/play.sh` (button, town, city, wheel, hover, click, scroll, snap). Quit after each take.
- The disk has 4.7 GB free: keep takes short, convert each AVI to H.264 at once, and delete the AVI.
- Typing a name: play.sh's `key` sends no characters to a text field, so try macOS keystrokes (System Events). If
  that's refused, use the screen-review frames of the renamed card.
- Avoid Goldrock's square for close shots (a townsperson is in a T-pose).

## The painted film, aligned to the 0.5 copy (2026-11-06, Mac: "Find out what kind of king you'd be")
Paintings from Codex (CODEX_BRIEF.md, ~/Downloads/Aldmere/launch/) carry the story; one real court card is the proof;
the reign-end throne painting (docs/play/v05/throne.jpg) carries the promise. The names are the game's real epithets
(bridge/stakes.js: the Golden, the Bloody, the Meddler, the Deposed...); the film never says which one Gareth's
grudge earns, because each comes from the whole reign.
| s | Picture | Words |
|---|---|---|
| 0–4 | launch_gareth_hall | "Ten years ago, you took our enemy's side in war. House Thornvale has not forgotten it." |
| 4–7 | launch_war_315 | Ten years ago, you took a side. |
| 7–10 | launch_boy_orchard | He was fourteen. |
| 10–13 | launch_years | He never forgot. |
| 13–17 | the real court card (docs/review/screens/court.jpg) | Every lord remembers what you did. |
| 17–20 | launch_gathering | And they act on it. |
| 20–26 | throne.jpg, the names fade in one by one | Find out what kind of king you'd be. |
| 26–31 | launch_kingsmere_dusk + seal + title | Free on Apple Silicon. / alichherawalla.itch.io/game-of-crowns |
