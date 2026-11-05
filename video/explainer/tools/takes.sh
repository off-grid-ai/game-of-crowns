#!/bin/zsh
# Clean, low-angle takes of the realm for the explainer, filmed by
# realm/scripts/cinematics.gd through the shared render queue (realm/tools/render.sh:
# one Godot at a time, the player's game always first). 1080p frames -> MP4.
#   video/explainer/tools/takes.sh <out dir> [name ...]
cd "$(dirname "$0")/../../.."
OUT=${1:?out dir}; shift
mkdir -p $OUT
TAKES=(
  "realm --clip=realm --secs=12"
  "descent --clip=descent --secs=11"
  "seat_Goldrock --clip=seat --city=Goldrock --secs=10"
  "seat_Stonefell --clip=seat --city=Stonefell --secs=10"
  "feast --clip=feast --city=Stonefell --secs=8"
  "battle --clip=battle --city=Deepvale --secs=10"
  "dawn --clip=dawn --city=Stonefell --secs=12"
  "siege --clip=siege --city=Goldrock --secs=10"
)
for t in $TAKES; do
  args=(${=t}); name=$args[1]; args=($args[2,-1])
  [ $# -gt 0 ] && ! (( ${@[(Ie)$name]} )) && continue
  [ -f $OUT/$name.mp4 ] && continue
  for try in 1 2; do
    rm -rf "${OUT:?}/$name" ; rm -f $OUT/$name.png
    RES=1280x720 LIMIT=3600 GODOT_ARGS="--fixed-fps 30" realm/tools/render.sh $OUT/$name.png --wait=99999 --film=1920x1080 --frames=$OUT/$name $args
    grep -q CLIP_END $OUT/$name.log && [ -f $OUT/$name/00000.jpg ] && break
    echo "retake $name"
  done
  [ -f $OUT/$name/00000.jpg ] || { echo "NO TAKE $name"; continue; }
  ffmpeg -y -loglevel error -framerate 30 -i $OUT/$name/%05d.jpg -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart $OUT/$name.mp4
  echo "ok $name $(ls $OUT/$name | wc -l) frames"
done
