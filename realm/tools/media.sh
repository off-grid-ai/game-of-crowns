#!/bin/zsh
# The launch-video media kit: 4K stills and short clips of the realm, plus the
# intro's stills. Every render goes through render.sh (one Godot at a time,
# Ali's game first). Clips are Movie Maker takes (cinematics.gd, frame by
# frame at 30 fps, so the live frame rate doesn't matter), cut to the move and
# encoded with ffmpeg to H.264 at 4K and 1080p.
#   realm/tools/media.sh [stills|clips|intro|all] [name ...]
# Output: media/launch/stills, media/launch/clips; intro stills in
# realm/assets/intro/stills. Env: RES (default 3840x2160).
cd "$(dirname "$0")/../.."
ROOT=$PWD
STILLS=$ROOT/media/launch/stills
CLIPS=$ROOT/media/launch/clips
INTRO=$ROOT/realm/assets/intro/stills
WORK=$ROOT/media/launch/work
FF=/opt/homebrew/bin/ffmpeg
export RES=${RES:-3840x2160}
mkdir -p $STILLS $CLIPS $INTRO $WORK
WHAT=${1:-all}; shift 2>/dev/null
ONLY=("$@")
SEATS=(Stonefell Goldrock Riverhall Eaglefell Crowfield Highfell Deepvale Lionmoor)

want() { [ ${#ONLY} = 0 ] || (( ${ONLY[(Ie)$1]} )); }

# A still: render.sh at 4K without the interface.
still() {
  local dir=$1 name=$2; shift 2
  want $name || return 0
  rm -f $dir/$name.png
  LIMIT=420 realm/tools/render.sh $dir/$name.png --clean "$@"
  mv -f $dir/$name.log $WORK/still_$name.log 2>/dev/null
}

# A clip: a Movie Maker take of one cinematics.gd move, cut to where the move
# starts (cinematics prints CLIP_START <frame>), then 4K and 1080p MP4s and a
# still of its last frame.
clip() {
  local name=$1; shift
  want $name || return 0
  local avi=$WORK/$name.avi png=$WORK/$name.png
  rm -f $avi $png ${avi%.avi}*.wav
  # Movie Maker's MJPEG at its best quality, only for these takes.
  print '[editor]\nmovie_writer/mjpeg_quality=0.95' > realm/override.cfg
  LIMIT=${CLIP_LIMIT:-2400} GODOT_ARGS="--write-movie $avi --fixed-fps 30" realm/tools/render.sh $png --wait=99999 "$@"
  rm -f realm/override.cfg
  local start=$(grep -o 'CLIP_START [0-9]*' $WORK/$name.log | awk '{print $2}')
  [ -z "$start" ] || [ ! -f $avi ] && { echo "NO TAKE $name (log: $WORK/$name.log)"; return 1; }
  local ss=$(echo "scale=3; $start / 30" | bc)
  $FF -y -loglevel error -ss $ss -i $avi -c:v libx264 -preset slow -crf 14 -pix_fmt yuv420p -an -movflags +faststart $CLIPS/${name}_4k.mp4
  $FF -y -loglevel error -i $CLIPS/${name}_4k.mp4 -vf scale=1920:1080:flags=lanczos -c:v libx264 -preset slow -crf 16 -pix_fmt yuv420p -movflags +faststart $CLIPS/${name}_1080p.mp4
  mv -f $png $STILLS/clip_$name.png
  rm -f $avi
  echo "ok clip $name"
}

if [[ $WHAT == intro || $WHAT == all ]]; then
  # What intro.gd shows, by name (see its pages).
  still $INTRO realm --wait=70
  for s in $SEATS; do still $INTRO seat_$s --city=$s --dist=7 --wait=70; done
  still $INTRO street --city=Stonefell --dist=2.5 --wait=70
  still $INTRO battle --city=Deepvale --battle --wait=70
  still $INTRO hero --hero=0 --wait=60
  still $INTRO hall --control=0 --interior=great_hall --wait=300
  still $INTRO walk --control=0 --wait=300
fi

if [[ $WHAT == stills || $WHAT == all ]]; then
  still $STILLS realm --wait=70
  still $STILLS kingsmere --city=Kingsmere --dist=9 --wait=70
  for s in $SEATS; do still $STILLS seat_$s --city=$s --dist=7 --wait=70; done
  still $STILLS street --city=Stonefell --dist=2.5 --wait=70
  still $STILLS battle --city=Deepvale --battle --wait=70
  still $STILLS siege --city=Goldrock --siege --wait=90
  still $STILLS duel --control=0 --duel --wait=300
  still $STILLS hero --hero=0 --wait=60
  still $STILLS hall --control=0 --interior=great_hall --wait=300
  still $STILLS feast --city=Stonefell --feast --dist=2.2 --wait=40
  still $STILLS dawn --city=Stonefell --dist=9 --time=0.26 --wait=70
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
