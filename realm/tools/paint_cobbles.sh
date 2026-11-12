#!/usr/bin/env bash
# The square's and streets' setts painted so they read from roof height (01-town: warm light-grey cobbles with dark
# joints; round 2 review: our photo cobbles blurred to beige dirt from the town view). Paints Poly Haven's
# cobblestone_color (CC0; light grey setts, about 7 across the sheet) the kit_paint way: the stones lifted to a warm light grey and less saturated, the joints
# darkened from the set's own height map (so they stay pixel-aligned and tile), a soft highlight on each stone's crown.
#   realm/tools/paint_cobbles.sh [source folder]   (default ~/Downloads/Aldmere/polyhaven/textures/cobblestone_color)
# Writes realm/assets/ground/cobbles-painted.jpg; the game reads it through realm/data/towns.json paving.texture.
# Knobs (env): LIFT (stones' brightness %, 108), SAT (saturation %, 70), WARM (warm tint over the stones, #d9c7a8),
# WARM_MIX (%, 25), JOINT_LO/JOINT_HI (saturation % where stones end and joints start, 14/30), JOINT_DARK (joints' value, 0.3),
# CROWN (crown highlight strength, 0.25), CROP (% of the sheet kept, 100; a crop shows
# mirror seams where terrain.gd tiled() flips every other repeat).
set -euo pipefail
SRC="${1:-$HOME/Downloads/Aldmere/polyhaven/textures/cobblestone_color}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/assets/ground/cobbles-painted.jpg"
N="$(basename "$SRC")"
LIFT="${LIFT:-108}"; SAT="${SAT:-70}"; WARM="${WARM:-#d9c7a8}"; WARM_MIX="${WARM_MIX:-25}"
JOINT_LO="${JOINT_LO:-14}"; JOINT_HI="${JOINT_HI:-30}"; JOINT_DARK="${JOINT_DARK:-0.3}"; CROWN="${CROWN:-0.25}"; CROP="${CROP:-100}"
T="$(mktemp -d)"
magick "$SRC/${N}_diff_1k.jpg" -modulate "$LIFT,$SAT,100" \( +clone -fill "$WARM" -colorize 100 \) -compose blend -define compose:args="$WARM_MIX" -composite "$T/stone.png"
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
