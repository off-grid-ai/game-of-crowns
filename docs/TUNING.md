# Tuning while you play

Each line: to change X, edit `<file>`: `<key>`. Bridge files take effect after the bridge restarts
(`launchctl kickstart -k gui/$(id -u)/com.realm.bridge`); view files at the game's next launch.
Switches (`--name`) go after `--` on the game's command line.

## Camera (Builder 2)
- How close the camera may come (the roof-height floor): `realm/data/camera.json`: `floor`.
- How far a town, a castle or a followed host is framed from: `realm/data/camera.json`: `go_to.*`.
- How many headings "go to" tries before settling for the least blocked: `realm/data/camera.json`: `sight_steps`.

## Castles (Builder 2)
- Where a seat's castle may stand when the first search fails (headings, rings, sizes, water allowed at its edge): `realm/data/towns.json`: `castle.*`.

## The director: threats and the shape of a reign (Builder 2)
- How quiet the realm must be, and for how long, before a threat rises: `bridge/data/director.json`: `quietBelow`, `quietSeasons`, `quietByAct` (by act).
- The breather after any crisis, in seasons: `bridge/data/director.json`: `breather`.
- When the last act's finale lands, as a share of the reign's clock: `bridge/data/director.json`: `finale.landAt`.
- Each threat's growth, words and the orders that answer it: `bridge/data/director.json`: `threats.<kind>.*`.
- How a too-comfortable King draws envy: `bridge/data/director.json`: `pushback.*`.

## The King's season: royal seals (Builder 2)
- On or off for reigns that don't say: `bridge/data/seals.json`: `on`. A new reign can set it with `options.seals`.
- Seals a season, and how many he can keep: `bridge/data/seals.json`: `perSeason`, `bank`, `bankLastAct`.
- How near a threat must be to top the "next thing" line: `bridge/data/next.json`: `soon`.

## Decrees and their prices (Builder 2)
- Each decree's price and words: `bridge/data/decrees.json`: `<decree>.cost`, `.label`.

## The court (Builder 2)
- One court flow (in, decide, see it, out): the switch `--court=one` (off until filmed and judged).

## Not yet in data (to move)
- Sound levels and the music's silences: literals in `realm/scripts/soundscape.gd` (`BEDS`, `STINGS`, `MUSIC_DB`, `CALM_GAP`).
- The court's pace (seasons between sittings): `bridge/court.js` `courtEvery`.

## The opening, first ten minutes (Builder 1; `--opening=v2`)
- How long after the King lands in his realm the first court sits: `bridge/data/opening.json`: `firstCourtAfterLandingSec`.
- When it sits anyway if no landing is heard (the intro skipped): `bridge/data/opening.json`: `firstCourtWithoutLandingSec`.

## Townsfolk (Builder 1)
- Which towns' people have minds: `--limbo=none` (the old rules everywhere) or `--limbo=<ids>` (only those towns); default every town (`realm/scripts/town_life.gd`: `LIMBO_ALL`).
- Motion v3 (props follow the errand, rising through Getting_Up): `--motion=v3`; `--motion=v1` for the old motion.
