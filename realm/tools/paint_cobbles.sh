#!/usr/bin/env bash
# The square's and streets' setts painted to 01-town's (supervisor, 2026-11-12: warmer and rounder setts; checked by
# realm/tools/cobble_probe.py against 01-town's own cobbles: hue, saturation, value, joints, stone size). Paints Poly
# Haven's cobblestone_02 (CC0; small rounded pebbles in sandy joints, about 0.19 m each at towns.json paving.tile 0.8)
# the kit_paint way: the stones lifted, turned a little pinker and less saturated toward 01-town's warm grey-beige, a
# warm wash over them; the joints kept as the set has them (JOINT_DARK 1: 01-town's joints are soft), no crown highlight.
#   realm/tools/paint_cobbles.sh [source folder]   (default ~/Downloads/Aldmere/polyhaven/textures/cobblestone_02)
# Writes realm/assets/ground/cobbles-painted.jpg (or $OUT); the game reads it through realm/data/towns.json paving.texture.
# Knobs (env): LIFT (stones' brightness %, 140), SAT (saturation %, 72), HUE (hue turn, 100 none, below warmer/pinker; 92),
# WARM (warm tint over the stones, #e6cbbb), WARM_MIX (%, 25), JOINT_LO/JOINT_HI (saturation % where stones end and joints
# start, 14/30), JOINT_DARK (joints' value, 1.0: as the set has them), CROWN (crown highlight strength, 0), CROP (% of the
# sheet kept, 100; a crop shows mirror seams where terrain.gd tiled() flips every other repeat).
set -euo pipefail
SRC="${1:-$HOME/Downloads/Aldmere/polyhaven/textures/cobblestone_02}"
OUT="${OUT:-$(cd "$(dirname "$0")/.." && pwd)/assets/ground/cobbles-painted.jpg}"
N="$(basename "$SRC")"
LIFT="${LIFT:-140}"; SAT="${SAT:-72}"; HUE="${HUE:-92}"; WARM="${WARM:-#e6cbbb}"; WARM_MIX="${WARM_MIX:-25}"
JOINT_LO="${JOINT_LO:-14}"; JOINT_HI="${JOINT_HI:-30}"; JOINT_DARK="${JOINT_DARK:-1.0}"; CROWN="${CROWN:-0}"; CROP="${CROP:-100}"
T="$(mktemp -d)"
magick "$SRC/${N}_diff_1k.jpg" -modulate "$LIFT,$SAT,$HUE" \( +clone -fill "$WARM" -colorize 100 \) -compose blend -define compose:args="$WARM_MIX" -composite "$T/stone.png"
# the joints: this set's are tan earth between grey stones, so its saturation finds them (its height map doesn't
# isolate them); a median clears the speckle inside the warmer stones
magick "$SRC/${N}_diff_1k.jpg" -colorspace HSL -channel G -separate +channel -level "${JOINT_LO}%,${JOINT_HI}%" -negate -statistic median 5x5 -blur 0x1 "$T/mask.png"
# joints: stone * (JOINT_DARK + (1 - JOINT_DARK) * mask)
magick "$T/mask.png" -fx "$JOINT_DARK + (1 - $JOINT_DARK) * u" "$T/shade.png"
# crowns: the height above its local mean (a blurred copy), as a soft highlight
magick "$SRC/${N}_disp_1k.jpg" -colorspace gray \( +clone -virtual-pixel tile -blur 0x12 \) -compose minus_src -composite -level 0%,25% "$T/crown.png"
magick "$T/stone.png" "$T/shade.png" -compose multiply -composite \( "$T/crown.png" -fx "u * $CROWN" \) -compose linear_dodge -composite -gravity northwest -crop "${CROP}%x${CROP}%+0+0" +repage -resize 1024x1024 -quality 92 "$OUT"
rm -rf "$T"
echo "paint_cobbles: wrote $OUT"
