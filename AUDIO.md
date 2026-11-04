# Aldmere: sound and music

Roadmap item 11. The realm has had no sound at all; this is the plan and the first working layer.
Code: [`realm/scripts/soundscape.gd`](realm/scripts/soundscape.gd). Files: `realm/assets/audio/`. Sources and licences: [`realm/assets/audio/CREDITS.md`](realm/assets/audio/CREDITS.md).

## The bar

- **Real places, not a sound library.** Field recordings of wind, sea, villages, smithies, bells and crows. No synth whooshes, no cartoon UI.
- **Quiet by default.** You spend hours with it. The ambience is felt more than heard. Music comes and goes with long silences between pieces, like Manor Lords or Kingdom Come.
- **Voices win.** When a townsperson or petitioner speaks (Kokoro TTS), the music and ambience step back.
- **Mood follows the realm.** Medieval instruments, Game of Thrones / Vikings weight: lute and harp in peace, low strings and drums in war, a choir drone when the dead come. Never jaunty, never cheesy.

## Buses

Made at runtime by `soundscape.gd`. There is no bus layout file, so nothing else changes.

| Bus | Default | What goes there | Effects |
|---|---|---|---|
| Master | 0 dB | everything | |
| Music | −6 dB | the score | compressor keyed by Voice (−28 dB threshold, 4:1, 20 ms / 450 ms) |
| Ambience | −4 dB | beds (wind, town, birds, rain…) | compressor keyed by Voice; low-pass (1.1 kHz indoors, open outdoors) |
| SFX | −2 dB | stingers, clashes, footsteps | |
| Voice | 0 dB | Kokoro lines (townsfolk, petitioners) | |
| UI | −8 dB | clicks, panels, the seal | |
| Mic | muted | `mic.gd` records here (already exists) | |

**Loudness targets** (set when the files were made): music −16 LUFS integrated; ambience −24 LUFS; long SFX −18 LUFS; one-shots under 3 s peak at −3 dBFS (SFX) or −12 dBFS (UI). True peak at most −1.5 dBTP. Each bed then has its own trim in `BEDS`.

## Ducking under voices

Two layers, both automatic once the voice player is on the `Voice` bus:

1. **Sidechain.** Music and Ambience compressors listen to Voice, so a line pulls them down as it is spoken, about 4–6 dB.
2. **Deliberate dip.** `voice_started()` / `voice_ended()` take Music down another 9 dB and Ambience another 5 dB. Down in 0.15 s, back up over 0.9 s, so the bed never pumps between words. If a line never reports its end, it releases after 45 s.

Stingers (SFX) are not ducked: a horn during a speech should still be heard.

## Ambience: by place and zoom

The camera's distance (`rig.distance`, 0.35 close to 260 for the whole realm) blends three zones.

| Zone | Distance | Beds |
|---|---|---|
| **The realm** | 60 → 200 | `realm_wind` (high gusts), `realm_sea` (surf; always a little, Aldmere has coasts). Winter swaps the wind for `snow_wind`. |
| **Country** | between towns, low | `birds_day`, `forest`, light wind. Night: `night` (crickets, a tawny owl). Autumn and winter: `crows`. |
| **Town** | 14 → 60, near a town | `town_day` (rooster, birds, a village going about its day), `town_bustle` (scaled by town size) |
| **Streets** | 4 → 22 | `market` (size 4+ or `market`), `forge` (size 3+ or `forge`), `tavern` spill (louder at night), `shore_gulls` (coastal), `river` |

Over a town by day, church bells ring every 2–5 minutes (size 4+ or `church`).

**Seasons and weather.** Spring and summer: full birds. Autumn: half birds, crows. Winter: no birds or crickets, `snow_wind` over everything (stronger from high up). Rain or storm: `rain`, the bustle and market thin out. Snow: `snow_wind`.

**Night.** Birds, market and forge stop; crickets and owl come in; the tavern gets louder; calm music sits 3 dB lower.

**Indoors** (`set_interior`). The outside drops to a third and is low-passed to 1.1 kHz, as if through walls. The room's bed comes up: `campfire` (great hall, cottage, tavern), `tavern` (tavern), silence (chapel). Rain becomes `rain_roof`.

**Under siege** (`near_town.siege`). The town's life goes quiet; `war_drums` and `crows` take its place.

**The North when the dead rise.** With mood `dead`, towns marked `north` get `dead_north` (horns and voices in a cold wind).

Beds start at a random point in their loop, fade in and out with a 0.6 s half-life, and are freed when silent. Every loop was cut with an equal-power crossfade at the seam, so it has no click or gap.

## Event stingers

`event(kind, at)`. With `at`, the sound is placed in the world and heard from the camera; its range scales with zoom, so a battle seen from the whole realm is soft but there, and up close it surrounds you.

| Event | What you hear | And then |
|---|---|---|
| battle | distant war horn, then a charge yell | `battle_loop` clash bed for 40 s close up (`battle_far` from high); mood **battle** 60 s. `battle_end` stops it. |
| clash / unit_killed | one sword clash (3 variants, slight pitch change) | |
| siege | war horn, a catapult 4 s later | `war_drums` 45 s; mood **battle** 60 s |
| feast | cheering | `feast_cheers` (banquet, "skål") 50 s; mood **feast** 90 s |
| death / reign_end | funeral bell | mood **tension** 40 s |
| crown / succession / coronation | trumpet fanfare, cheer, church bells | |
| marriage | church bells, a cheer | |
| alliance | a soft fanfare | |
| dead (beyond the wall) | horde voices and horns, a wolf howl | `dead_north` 90 s; mood **dead** 120 s |
| famine | low choir drone, a tolling bell | mood **tension** 60 s |
| plague | tolling bell | |
| rebellion / civil_war / raid | war horn | mood **tension** 60 s |
| sack / razed / city_destroyed | near war horn, tolling bell | mood **tension** 60 s |
| handover / city_transferred | a far horn | |

At most 12 stingers at once; extra ones are dropped, not queued.

## UI sounds

Few and quiet, and only where a real object would make one. `ui(kind)`:

| Kind | Sound | Use for |
|---|---|---|
| click | soft click | buttons in the corners |
| open / close | a book opening and closing | the chronicle, the character view, court |
| page | a page turning | paging the chronicle |
| seal / decree | a wax seal pressed | **a decree sealed**, a ruling given |
| parchment | parchment unrolling | a petition arriving |
| quill | a quill writing | while you type a reply |
| error | a dull knock | a blocked action ("First choose a town") |

A sound fired twice within 80 ms plays once. Hovering makes no sound.

## Music

`mood(kind)` sets the realm's standing mood; events lift it for a while and it falls back.

| Mood | When | Pieces | Feel |
|---|---|---|---|
| **calm** | peace, the default | Achaidh Cheide, Teller of the Tales, Shores of Avalon (MacLeod); Exploration, Harvest Season (RandomMind); Vikings at Shore (Eldritch Grim) | harp, lute, whistle, strings. 25–70 s of silence between pieces. |
| **court** | the throne room, court open, petitions | Suonatore di Liuto, Lord of the Land (MacLeod) | lute and strings, measured |
| **feast** | a feast | Master of the Feast (MacLeod) | a dance, drums and fiddle |
| **tension** | a usurper rising, rebellion, famine, a death | Darkest Child, Dark Times (MacLeod); Lament for a Warrior's Soul (RandomMind); Lament of the War (Cethiel) | low strings, slow |
| **dead** | the dead beyond the wall | Unseen Horrors (MacLeod); Something Approaches (Eldritch Grim) | drones, cold |
| **battle** | battle or siege | Five Armies, Heroic Age (MacLeod); For the King (Zhelanov); Viking March (nightm4re) | drums, brass, choir |

A mood change crossfades now (2 s into battle, 5 s otherwise). In calm and court a piece ends into silence; in the others the next follows. The same piece never plays twice in a row.

**Who sets the mood.** Suggested rules for `main.gd`: `dead` while the dead are risen (stakes `n.waves > 0`); `tension` while a claimant or rebellion is live or a town starves; `court` while the court or petition panel is open; otherwise `calm`. Battle and feast come from events by themselves.

## Wiring (for the main session)

1. Add the node: `var sound := preload("res://scripts/soundscape.gd").new(); add_child(sound)`.
2. Voices: in `_say_aloud`, set `_voice.bus = sound.voice_bus()` (instead of `"Master"`); call `sound.voice_started()` before `_voice.play()` and connect `_voice.finished` to `sound.voice_ended` once. A new line that cuts the last should call `voice_ended()` for the cut one first.
3. Every frame (in `_process`, next to `_update_labels`): `sound.set_view(rig.distance, town_info, season, sky3d.is_night(), weather)`. `town_info` is the nearest town within ~40 units of the camera's focus, as `{size, coastal, river, north, siege, market, forge, church, tavern}`, `{}` when none. Unknown keys fall back on size.
4. Events: where chronicle events arrive (`DIGEST_KINDS` and the bridge's scene calls), `sound.event(kind, terrain.world_pos(x, y))`. Battles: `event("battle", at)` when `scenes._battle` starts, `event("battle_end")` when it ends. The dead: `event("dead", at)` on the stakes wave, then `mood("dead")`.
5. Interiors: `sound.set_interior(room)` on entering, `set_interior("")` on leaving.
6. UI: `sound.ui("click")` etc. from `ui.gd` (a signal to main is enough). Decree sealed: `ui("seal")`.
7. Control: `sound.footstep("grass"|"wood"|"snow", body.global_position)` on each step of the walk cycle.
8. Godot must import the new files once: open the editor, or `arch -arm64 godot --headless --path realm --import`.
9. Git: `realm/assets/audio/` is about 100 MB and not in `.gitignore`. The licences allow it in the repo (CC0 / CC-BY / CC-BY-SA, credited); add it to `.gitignore` with the other third-party art if the repo should stay small.

## Not done yet

- **Nothing has been listened to.** The picks come from titles, descriptions, download counts and loudness measures. Audition every file before shipping; swap anything that rings false. Most likely to need a swap: `market` (a 10 s loop, short), `town_bustle` (an indoor crowd standing in for a street), `dead_voices`, and any MacLeod piece that reads too bright.
- **Freesound files are the public HQ previews** (OGG, about 192 kbps), not the original WAVs. Fine for beds. For full quality, log in to Freesound (Ali's account) and fetch the originals by the IDs in CREDITS.md.
- **Two beds sit under target:** `campfire` (−34 LUFS) and `forge` (−27 LUFS). Both are all transients (crackle, hammer blows), and pushing them to −24 would squash them. Their `BEDS` trim can lift them if they're too faint in the game.
- **Missing:** a crowd shouting in anger (riot), a burning town, hooves on a road, a ship's creak, a monastery choir (the chapel). Freesound CC0 had nothing good under those words.
- **Positional town beds.** Today the town beds are flat and follow "the town under the camera". Better: one `AudioStreamPlayer3D` per town square with the same beds, so panning across towns pans the sound. Do this when the view settles.
- **A settings panel** for the five bus volumes (`set_volume` / `volume` are ready).
