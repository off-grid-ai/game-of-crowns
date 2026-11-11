# Batch 9: shots to film (batch7-review #1, #3, #7, #10, #15)

One Godot at a time on a private bridge, every still and clip together. Each line says what it must prove. Read
play.log's "settled in … distance … deg down" line after every framing step: it is the ladder's proof.

## The distance ladder (#7)

The camera's floor is 6 (camera.json `floor`; Mac: no close-up realism), so d4 and d6 are one frame by design:
the log now says "under the camera's floor". Batch 7's d14 and d40 went wrong for two other reasons: tilts of -22 and
-20 made the lens skim the land at 10-16 degrees (a far, low view reads as "close"), and Goldrock's d4 framed
Rosehall because a court sitting took the camera (fixed, e87d2394).

1. **Kingsmere ladder at the rig's own pitch:** `city Kingsmere 6`, `city Kingsmere 10`, `city Kingsmere 16`,
   `city Kingsmere 30`, `city Kingsmere 50` (no tilt), a snap after each. Judge: each step visibly further and
   higher; play.log distances 6, 10, 16, 30, 50, pitch rising with distance (about 30 up to 40 degrees down).
2. **The same with the old low tilts** (`city Kingsmere 14 -22`, `city Kingsmere 40 -20`): for the record of why
   batch 7 read backwards; with clarity on, the lens now tips up where roofs block it (the log's pitch says by how much).
3. **Goldrock 6, 10, 16, 30** at default tilt, with a court sitting due: the frame stays on Goldrock (the court
   waits at its place; Space would take you there).

## Settled frames, true clip gaps (#10, #15)

4. **forge and forge-clip** (`work Kingsmere forge 4.5 -25`, then snap and a 24-frame clip at 0.2): the first frame
   already settled (no orbit in frames 1-13); clip frames 0.2 s of game time apart (check a walker's stride between
   frames, or play.log's timestamps).
5. **breach clips** (`breach 4 -25`, 30 frames at 0.2): no cut inside a clip.
6. **army-line-d12** (`--army-spike=6000 --army-shape=line --dist=12 --wait=90`): the army, not the main menu
   (log: "SHOT waiting for the realm" if the title was up).
7. **The breach launch's log**: no `field_work.gd:86` errors (92185fe7). (fire.gd:170's 178 errors are fire's own.)

## Panels and the court (#1, #3)

8. **Film shots without panels**: every breach/siege snap free of the town card, the court card and the chronicle
   (41fabfad), and no court sitting moving the camera mid-film (e87d2394). One `snap name ui` keeps them, to check.
9. **Clarity before/after** (#1): batch 8's shots 8-12 (`--clarity=old` for the before).
