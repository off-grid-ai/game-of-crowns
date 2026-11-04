#!/bin/zsh
# The launch-video media kit: 4K stills and short clips of the realm, plus the
# intro's stills. Every take is a cinematics.gd move filmed at 3840x2160 in its
# own view (frame by frame at a fixed 30 fps, so the live frame rate doesn't
# matter), and goes through render.sh: one Godot at a time, Ali's game first.
# Clips are encoded with ffmpeg to H.264 at 4K and 1080p.
#   realm/tools/media.sh [intro|stills|clips|all] [name ...]
# Output: media/launch/stills, media/launch/clips; intro stills in
# realm/assets/intro/stills.
cd "$(dirname "$0")/../.."
ROOT=$PWD
STILLS=$ROOT/media/launch/stills
CLIPS=$ROOT/media/launch/clips
INTRO=$ROOT/realm/assets/intro/stills
WORK=$ROOT/media/launch/work
FF=/opt/homebrew/bin/ffmpeg
# The window is never filmed, so it stays small; the launch kit goes first in the queue.
export RES=1280x720 PRIORITY=1
mkdir -p $STILLS $CLIPS $INTRO $WORK
WHAT=${1:-all}; shift 2>/dev/null
ONLY=("$@")
SEATS=(Stonefell Goldrock Riverhall Eaglefell Crowfield Highfell Deepvale Lionmoor)

want() { [ ${#ONLY} = 0 ] || (( ${ONLY[(Ie)$1]} )); }

# A 4K still: the clip's move held at its end.
still() {
  local dir=$1 name=$2; shift 2
  want $name || return 0
  for try in 1 2 3; do
    rm -f $dir/$name.png
    LIMIT=600 GODOT_ARGS="--fixed-fps 30" realm/tools/render.sh $dir/$name.png --wait=99999 --secs=0 "$@"
    mv -f $dir/$name.log $WORK/still_$name.log 2>/dev/null
    # A GPU stall leaves no picture or a blank one (a few KB): take it again.
    [ -f $dir/$name.png ] && [ $(stat -f %z $dir/$name.png) -gt 500000 ] && return 0
    echo "retake $name"
  done
  rm -f $dir/$name.png
  return 1
}

# A clip: every frame of the move as a 4K JPEG, then 4K and 1080p MP4s, and its
# last frame kept as a still.
clip() {
  local name=$1; shift
  want $name || return 0
  local frames=$WORK/$name png=$WORK/$name.png
  for try in 1 2 3; do
    rm -rf $frames $png
    LIMIT=${CLIP_LIMIT:-3600} GODOT_ARGS="--fixed-fps 30" realm/tools/render.sh $png --wait=99999 --frames=$frames "$@"
    # Whole and not blank (a GPU stall), or take it again.
    grep -q "CLIP_END" $WORK/$name.log && [ $(stat -f %z $png 2>/dev/null || echo 0) -gt 500000 ] && break
    echo "retake $name"
  done
  [ -f $frames/00000.jpg ] || { echo "NO TAKE $name (log: $WORK/$name.log)"; return 1; }
  $FF -y -loglevel error -framerate 30 -i $frames/%05d.jpg -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -movflags +faststart $CLIPS/${name}_4k.mp4
  $FF -y -loglevel error -framerate 30 -i $frames/%05d.jpg -vf scale=1920:1080:flags=lanczos -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart $CLIPS/${name}_1080p.mp4
  [ -f $png ] && mv -f $png $STILLS/clip_$name.png
  rm -rf $frames
  echo "ok clip $name"
}

if [[ $WHAT == intro || $WHAT == all ]]; then
  # The pictures intro.gd shows, by name (see its pages).
  still $INTRO realm --clip=realm
  for s in $SEATS; do still $INTRO seat_$s --clip=seat --city=$s; done
  still $INTRO street --clip=street --city=Stonefell
  still $INTRO battle --clip=battle --city=Deepvale
  still $INTRO hero --clip=hero --lord=0
  still $INTRO hall --clip=hall --lord=0
  still $INTRO walk --clip=walk --lord=0
fi

if [[ $WHAT == stills || $WHAT == all ]]; then
  still $STILLS kingsmere --clip=descent
  still $STILLS siege --clip=siege --city=Goldrock
  still $STILLS duel --clip=duel --lord=0 --secs=2.2
  still $STILLS feast --clip=feast --city=Stonefell
  still $STILLS dawn --clip=dawn --city=Stonefell
fi

if [[ $WHAT == clips || $WHAT == all ]]; then
  clip realm --clip=realm --secs=12
  clip descent --clip=descent --secs=11
  for s in $SEATS; do clip seat_$s --clip=seat --city=$s --secs=10; done
  clip street --clip=street --city=Stonefell --secs=10
  clip battle --clip=battle --city=Deepvale --secs=10
  clip siege --clip=siege --city=Goldrock --secs=10
  clip duel --clip=duel --lord=0 --secs=8
  clip hall --clip=hall --lord=0 --secs=9
  clip walk --clip=walk --lord=0 --secs=9
  clip feast --clip=feast --city=Stonefell --secs=8
  clip dawn --clip=dawn --city=Stonefell --secs=12
fi
