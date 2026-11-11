# UI finesse pass (2026-11-12)

Mac: "I definitely don't want to compromise on the UI and the finesse." His screenshot that night: the chronicle
over a fifth of the town, and a column of +/-/arrow/rotate buttons that read as a debug tool. The rule (UI.md, the
memory rules): the world is the hero; panels compact, in the corners, closed by default; one accent; the game
decides, no key strips or debug pickers on screen. Measured from batch 7 and 8 frames at 2400x1380 and the code's
sizes (UI points; the films draw at about 1.5 px a point).

Behind `--ui=v2` (`--ui=v1` for the before shot); numbers in `realm/data/ui.json`. The default stays v1 until batch
8b, which is filming from this tree, has finished; then `version` flips to v2.

| Screen | Now | Reference | Fix (v2) |
|---|---|---|---|
| Camera pad, right edge | 104-point column of zoom, pan, turn, tilt and home buttons beside the minimap, fading in whenever the pointer drifts to that corner. Reads as a debug tool. | Age of Empires IV, Anno 1800: no camera buttons; mouse, edge pan and keys; a compass on the minimap at most. | Gone unless the player picks "always" in Settings (the camera moves by mouse, trackpad and keys, keys.gd). The minimap takes the right edge. |
| Town card (fallback, not pinned) | 580 points wide, centred over the middle of the screen: the town it describes is under it. | CK3's character and holding windows sit to one side; Anno's building panel bottom-left, narrow. | 400 wide, on the left under the date card, translucent. Pinned by its town as before (400). |
| Date card, top-left | Date, the reign's story, its aim and the next thing in one pill that grows with its text: about half the screen's width in batch 7/8. | AoE IV top bar: a compact age/time chip; CK3: date chip top-right, small. | Capped at `top.maxWidth` (520 points); long lines end in an ellipsis instead of widening the pill. |
| Chronicle drawer | 330 points wide, from under the bar to the minimap: a fifth of the screen when open. | CK3's message log: a narrow, short list; Anno's notification feed: a few lines at the edge. | 280 wide and at most `chronicle.height` (45%) of the screen tall, from the top right; scrolls. Closed by default (as now; the films opened it, shot_harness --chronicle). |
| Toast | 500 points wide, centred near the top. | AoE IV and Anno: a short line at the side of the screen. | 400 wide. |
| Court card, decree card, event card | Already pinned by their place (400) or the court's corner; the court no longer takes the camera (e87d2394); snaps put cards away (41fabfad). | CK3 event window, Frostpunk law book. | Unchanged in this pass (judge on film first). |
| Treasury and readings, top-centre | Mono numbers with an icon each, one accent (gold). | AoE IV/Anno resource bar. | Unchanged: already one row of icon and number. |
| Icon row, top-right | The King's keys, 44-point buttons with hover and pressed states. | AoE IV top-right menu. | Unchanged. |
| Minimap | Bottom-right, beside the camera pad. | AoE IV, Anno: bottom corner, flush. | Flush to the right edge once the pad is gone. |

Not done here, to judge on batch 9's frames first: the court card's own width, the ticker's lines, type sizes.
