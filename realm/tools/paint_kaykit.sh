#!/usr/bin/env bash
# The KayKit Forest trees' and bushes' colours repainted toward 01-town's (Mac, round 7: "look at the trees... no
# finesse"): KayKit's atlas holds each material as a vertical swatch, lit at the top and dark at the bottom, which its
# models' UVs run up the leaves; this paints the leaf swatch in 01-town's greens (a sunlit yellow-green top, a mid
# green, a deep shadow under the crown) and the trunk swatch from KayKit's orange to a bark brown. The rest is kept.
#   realm/tools/paint_kaykit.sh     (ImageMagick, headless)
# Reads realm/assets/nature/kaykit/forest_texture.png; writes forest_painted.png beside it (assets.json town_tree_round's
# dye names it). Knobs (env): LIGHT, MID, DARK (the leaves' top, middle and underside), BARK_LIGHT, BARK_DARK.
set -euo pipefail
D="$(cd "$(dirname "$0")/.." && pwd)/assets/nature/kaykit"
LIGHT="${LIGHT:-rgb(176,200,78)}"; MID="${MID:-rgb(104,150,54)}"; DARK="${DARK:-rgb(44,82,36)}"
BARK_LIGHT="${BARK_LIGHT:-rgb(128,90,56)}"; BARK_DARK="${BARK_DARK:-rgb(66,44,28)}"
S=$(magick identify -format "%w" "$D/forest_texture.png")  # the atlas side; each swatch is an eighth wide, a quarter tall
W=$((S / 8)); H=$((S / 4))
T="$(mktemp -d)"
magick -size ${W}x$((H * 45 / 100)) gradient:"$LIGHT-$MID" \( -size ${W}x$((H - H * 45 / 100)) gradient:"$MID-$DARK" \) -append "$T/leaf.png"
magick -size ${W}x${H} gradient:"$BARK_LIGHT-$BARK_DARK" "$T/bark.png"
magick "$D/forest_texture.png" "$T/leaf.png" -geometry +0+0 -composite "$T/bark.png" -geometry +0+${H} -composite "$D/forest_painted.png"
rm -rf "$T"
echo "paint_kaykit: wrote $D/forest_painted.png"
