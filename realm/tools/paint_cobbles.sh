#!/usr/bin/env bash
# The square's and streets' setts painted as round 11's square that Mac picked over 01-town's (2026-11-12, the
# r11 | r15 | 01-town sheet: "tbh I like the first one"): readable light-grey setts with clear dark joints from the
# town view. Paints Poly Haven's cobblestone_color (CC0; light grey setts, about 7 across the sheet, ~17 px a stone from
# the c01 camera at towns.json paving.tile 0.3) the kit_paint way: the stones lifted to a warm light grey and less
# saturated, the joints darkened (their tan earth found by saturation), a soft highlight on each stone's crown.
# Judged on the rendered frame by realm/tools/still_probe.py's setts line (round 15's real-size pebbles read as sand).
#   realm/tools/paint_cobbles.sh [source folder]   (default ~/Downloads/Aldmere/polyhaven/textures/cobblestone_color)
# Writes realm/assets/ground/cobbles-painted.jpg (or $OUT); the game reads it through realm/data/towns.json paving.texture.
# Knobs (env): LIFT (stones' brightness %, 108), SAT (saturation %, 70), HUE (hue turn, 100 none, below warmer/pinker; 100),
# WARM (warm tint over the stones, #d9c7a8), WARM_MIX (%, 25), JOINTS (sat: the joints found by their saturation, for
# tan joints between grey stones; height: by the set's height map, its local lows), JOINT_LO/JOINT_HI (where joints end
# and stones start: % of saturation for sat, of local height for height; 14/30), JOINT_DARK (joints' value, 0.3), CROWN
# (crown highlight strength, 0.25), CROP (% of the sheet kept, 100; a crop shows mirror seams where terrain.gd tiled()
# flips every other repeat).
# REPEAT (the painted sheet repeated REPEAT x REPEAT before the final 1024 resize, 1 none: more, smaller setts on one sheet,
# so a sett is a sixth of a person at the same paving.tile and the same number of tiled copies; art step 6,
# docs/art/STANDARDS.md section 2; set towns.json paving.stones_across to match).
# VARY (%, 0 none; 100: each sett up to 16% lighter or darker and 7% warmer or cooler): soft noise about a sett
# across, so the setts vary warm to cool as 01-town's do instead of one tint (art step 6, look audit: "an even grey grid").
set -euo pipefail
SRC="${1:-$HOME/Downloads/Aldmere/polyhaven/textures/cobblestone_color}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/assets/ground/cobbles-painted.jpg}"
N="$(basename "$SRC")"
LIFT="${LIFT:-108}"; SAT="${SAT:-70}"; HUE="${HUE:-100}"; WARM="${WARM:-#d9c7a8}"; WARM_MIX="${WARM_MIX:-25}"
JOINTS="${JOINTS:-sat}"; JOINT_LO="${JOINT_LO:-14}"; JOINT_HI="${JOINT_HI:-30}"; JOINT_DARK="${JOINT_DARK:-0.3}"; CROWN="${CROWN:-0.25}"; CROP="${CROP:-100}"; REPEAT="${REPEAT:-1}"; VARY="${VARY:-0}"
T="$(mktemp -d)"
magick "$SRC/${N}_diff_1k.jpg" -modulate "$LIFT,$SAT,$HUE" \( +clone -fill "$WARM" -colorize 100 \) -compose blend -define compose:args="$WARM_MIX" -composite "$T/stone.png"
# the joints: by the set's height map (JOINTS=height: the low ground between stones, pixel-aligned, so it tiles) or,
# for a set whose joints are tan earth between grey stones and whose height map doesn't isolate them, by saturation
# (JOINTS=sat); a median clears the speckle inside the warmer stones
if [ "$JOINTS" = height ]; then
  # the height over its local mean (a blurred copy, tiled), so a broad dip in the sheet doesn't darken a patch of stones
  magick "$SRC/${N}_disp_1k.jpg" -colorspace gray \( +clone -virtual-pixel tile -blur 0x12 \) -compose minus_src -composite \
    -evaluate add 50% -level "${JOINT_LO}%,${JOINT_HI}%" -blur 0x1 "$T/mask.png"
else
  magick "$SRC/${N}_diff_1k.jpg" -colorspace HSL -channel G -separate +channel -level "${JOINT_LO}%,${JOINT_HI}%" -negate -statistic median 5x5 -blur 0x1 "$T/mask.png"
fi
# joints: stone * (JOINT_DARK + (1 - JOINT_DARK) * mask)
magick "$T/mask.png" -fx "$JOINT_DARK + (1 - $JOINT_DARK) * u" "$T/shade.png"
# crowns: the height above its local mean (a blurred copy), as a soft highlight
magick "$SRC/${N}_disp_1k.jpg" -colorspace gray \( +clone -virtual-pixel tile -blur 0x12 \) -compose minus_src -composite -level 0%,25% "$T/crown.png"
magick "$T/stone.png" "$T/shade.png" -compose multiply -composite \( "$T/crown.png" -fx "u * $CROWN" \) -compose linear_dodge -composite -gravity northwest -crop "${CROP}%x${CROP}%+0+0" +repage "$T/sheet.png"
# REPEAT: the sheet side by side and stacked (it tiles seamlessly), then down to 1024
magick "$T/sheet.png" -write mpr:s +delete -size "$((1024 * REPEAT))x$((1024 * REPEAT))" tile:mpr:s -resize 1024x1024 "$T/tiled.png"
if [ "$VARY" -gt 0 ]; then
  # two soft grey noises about a sett across (seeded, so a re-run paints the same sheet): one lifts or dims each sett,
  # the other leans it warm (red up, blue down) or cool. terrain.gd tiled() mirrors every other copy, so the noise
  # needs no tiling of its own.
  magick -seed 7 -size 1024x1024 plasma: -colorspace gray -blur 0x28 -auto-level "$T/n1.png"
  magick -seed 11 -size 1024x1024 plasma: -colorspace gray -blur 0x40 -auto-level "$T/n2.png"
  A=$(echo "0.32 * $VARY / 100" | bc -l); W=$(echo "0.14 * $VARY / 100" | bc -l)
  magick "$T/tiled.png" "$T/n1.png" -fx "u*(1-$A/2+$A*v)" "$T/a.png"
  magick "$T/a.png" "$T/n2.png" -channel R -fx "u*(1-$W/2+$W*v)" "$T/b.png"
  magick "$T/b.png" "$T/n2.png" -channel B -fx "u*(1+$W/2-$W*v)" "$T/tiled.png"
fi
magick "$T/tiled.png" -quality 92 "$OUT"
rm -rf "$T"
echo "paint_cobbles: wrote $OUT"
