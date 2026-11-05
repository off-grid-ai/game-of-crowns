GOAL:    A stranger on Reddit sees a realm that runs itself, watches one real decision of the King's play out over a
         season, then the name and where to get it (downloads are the goal; v0.1 is out).
OUTPUT:  HyperFrames, 1920 x 1080, 30 fps. Plays muted on Reddit first: every line is on screen; sound is a bonus.
TIME:    44.3 s x 30 = 1329 frames. Bed: "Lament of the War" (Cethiel, CC0), entered at a strong bar, faded under the end.
LOOK:    The game's own world and panels. Two worlds:
         - World: clean low-angle takes (cinematics.gd, no interface), full-bleed, slow push 1.00 -> 1.06 over a shot.
         - Panels: the real play frames from one run (docs/play/r31-ride, Autumn 353 -> Summer 354), pushed in so the
           panel text reads at >= 28 px (source scale 0.75-1.1 of a 3600 px frame); the frame is never shown whole.
         Type: EB Garamond 500, display 104 px, tracking -0.01em, line-height 1.05, ink #E9E1D0 (warm stone, lifted),
         left-aligned at x 120, baseline zone y 760-960 over a 0 -> 55% charcoal (#151719) gradient from the bottom.
         Small line: Cinzel 600 30 px, tracking .12em, aged bronze #B7A17D. Accent = aged bronze, once per shot at most
         (a number that changes, the question mark of the last line).
OBJECTS: the realm (land, towns, roads, a castle); the chronicle (real lines); the town card for Goldrock with
         "FUND 18k cr Temple"; the notice "The crown pays for a temple in Goldrock. House Goldcrest is grateful.
         18,000 crowns · Goldcrest 57 -> 65"; "The King's rider, bound for Goldrock · Watch"; Goldrock a season later
         (Temple listed, "raising pikemen 46%"); the houses table row "Goldcrest · WAR · WOLFHOLT"; Cecily Stormhold's
         petition "The tithe has bled my coffers dry, Your Grace."
MOTION:  enter power3.out 0.5 s; camera pushes sine.inOut over the whole shot; pan between panel crops
         cubic-bezier(.45,0,.25,1) 0.9 s; lines enter by word, stagger 0.05 s, y 18 -> 0; nothing moves once read.
         Cuts are hard, or a 6-frame dip through charcoal between worlds.
SHOTS:
  s1  0.0-4.0   World: realm flyover. "A kingdom sim that runs itself." on screen at frame 0 (thumbnail); genre first.
  s2  4.0-9.0   Panels: the chronicle, pushed in; three real lines brighten in turn (plague, Goldcrest arming,
                Thornvale expects war). Line: "Houses farm, starve and go to war."
  s3  9.0-12.5  World: descent / a seat. "You're the King." then "You can't move a single soldier."
  s4  12.5-17.0 Panels: Goldrock's town card, camera on "FUND 18k cr Temple"; a hand cursor presses Temple (click);
                hard cut to the notice, "57 -> 65" in bronze (coins). Line: "So I paid for a temple."
  s5  17.0-22.0 Panels -> world: "The King's rider, bound for Goldrock · Watch", then the ride frames (r31 03-07)
                cropped to the road, stepped like a flipbook with a slow drift (gallop).
  s6  22.0-27.0 "A season later." Goldrock by the water (r31 09), then the push onto its card: Temple listed,
                "raising pikemen 46%" in bronze.
  s7  27.0-31.5 Panels: the houses table, Goldcrest's row, "WAR · WOLFHOLT". Line: "Goldcrest was at war."
  s8  31.5-35.5 Panels: Cecily Stormhold's petition, the quote pushed in (bell). Line: "And the court was filling up."
  s9  35.7-39.3 World (Lionmoor). "What would you have done?"
  s10 39.3-44.3 End card: the title art wipes in, "Free on Apple Silicon.", github.com/off-grid-ai/game-of-crowns.
BANNED:  a dark void with small floating UI; glow, particles; a title over a dimmed whole screenshot; a frame shown
         whole with every panel; "AI" on screen; a house count; any claim the run didn't show (the temple did not *cause*
         the pikemen: shown side by side, never said); "Introducing"; three cards in a row; text that drifts after it lands.
QA:      frames 0, 3.0, 6.5, 10.5, 14.0, 16.0, 19.0, 24.0, 26.0, 29.0, 33.5, 38.0, 40.5.
