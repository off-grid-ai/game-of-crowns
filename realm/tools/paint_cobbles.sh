#!/usr/bin/env bash
# The square's and streets' setts painted so they read as stones from the town view (round 15: 6a7746cf's real-size
# pebbles, cobblestone_02 at 0.19 m, landed at 2-3 px a stone from the c01 camera and the square read as sand; judged on
# the rendered frame by realm/tools/still_probe.py's setts line, the albedo by realm/tools/cobble_probe.py). Paints Poly
# Haven's cobblestone_floor_08 (CC0; light, warm-grey rounded setts, about ten across the sheet, so at towns.json
# paving.tile 0.45 a stone is about 18 px from the c01 camera, as round 11's setts that read) the kit_paint way: the
# stones lifted and warmed toward 01-town's beige-grey, the joints darkened from the set's own height map (its local
# lows, so they stay pixel-aligned and tile, and a broad dip in the sheet doesn't blotch), a soft highlight on each crown.
#   realm/tools/paint_cobbles.sh [source folder]   (default ~/Downloads/Aldmere/polyhaven/textures/cobblestone_floor_08)
# Writes realm/assets/ground/cobbles-painted.jpg (or $OUT); the game reads it through realm/data/towns.json paving.texture.
# Knobs (env): LIFT (stones' brightness %, 122), SAT (saturation %, 100), HUE (hue turn, 100 none, below warmer/pinker; 95),
# WARM (warm tint over the stones, #e6cbbb), WARM_MIX (%, 35), JOINTS (height: the set's height map finds the joints;
# sat: their saturation, for a set with tan joints between grey stones), JOINT_LO/JOINT_HI (where joints end and stones
# start: % of local height for height, of saturation for sat; 42/54), JOINT_DARK (joints' value, 0.25), CROWN (crown
# highlight strength, 0.15), CROP (% of the sheet kept, 100; a crop shows mirror seams where terrain.gd tiled() flips
# every other repeat).
set -euo pipefail
SRC="${1:-$HOME/Downloads/Aldmere/polyhaven/textures/cobblestone_floor_08}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/assets/ground/cobbles-painted.jpg}"
N="$(basename "$SRC")"
LIFT="${LIFT:-122}"; SAT="${SAT:-100}"; HUE="${HUE:-95}"; WARM="${WARM:-#e6cbbb}"; WARM_MIX="${WARM_MIX:-35}"
JOINTS="${JOINTS:-height}"; JOINT_LO="${JOINT_LO:-42}"; JOINT_HI="${JOINT_HI:-54}"; JOINT_DARK="${JOINT_DARK:-0.25}"; CROWN="${CROWN:-0.15}"; CROP="${CROP:-100}"
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
magick "$T/stone.png" "$T/shade.png" -compose multiply -composite \( "$T/crown.png" -fx "u * $CROWN" \) -compose linear_dodge -composite -gravity northwest -crop "${CROP}%x${CROP}%+0+0" +repage -resize 1024x1024 -quality 92 "$OUT"
rm -rf "$T"
echo "paint_cobbles: wrote $OUT"
