#!/bin/zsh
# The realm's atlas for the far view: Azgaar's map drawn from its own data
# (azgaar_atlas.js), shaded with relief from the same eroded heights the 3D
# land is built from, at 4 pixels per Azgaar unit (3040×4800).
#   tools/make_atlas.sh [scratch dir]
set -e
cd "$(dirname "$0")/.."
T=${1:-$(mktemp -d)}
OUT=../realm/assets/maps/atlas.png
node tools/azgaar_atlas.js "data/Belia Full 2026-11-03-16-26.json" $T/atlas.svg
rsvg-convert -w 3040 -h 4800 $T/atlas.svg -o $T/flat.png
# Relief: light from the north-west; flat ground lands on 50% grey so the
# overlay only darkens slopes facing away and lifts those facing the light.
magick -size 1297x2048 -depth 16 -endian LSB gray:data/belia-eroded-1297x2048.u16 \
  -shade 315x45 -evaluate subtract 20.7% -resize 3040x4800\! \
  -sigmoidal-contrast 3x50% $T/shade.png
magick $T/flat.png $T/shade.png -compose overlay -composite $OUT
echo "atlas -> $OUT"
