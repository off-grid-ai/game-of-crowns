#!/bin/zsh
# Brings the intro's paintings into the game: each PNG in the source folder
# (default ~/Downloads/Aldmere/intro) becomes a JPG in realm/assets/intro/art,
# at most 3840 wide (never enlarged), small enough to keep in git.
# The names are the intro's page names (realm_land, house_wolfholt, tip_clock…).
#   realm/tools/intro_art.sh [source folder]
cd "$(dirname "$0")/.."
SRC=${1:-$HOME/Downloads/Aldmere/intro}
OUT=assets/intro/art
mkdir -p $OUT
for f in $SRC/[a-z]*.png(N); do  # lower-case names only: not the contact sheet
  w=$(sips -g pixelWidth $f | awk '/pixelWidth/ {print $2}')
  sips -s format jpeg -s formatOptions 84 $( (( w > 3840 )) && echo -Z 3840 ) $f --out $OUT/${f:t:r}.jpg > /dev/null && echo "ok ${f:t:r}.jpg $(du -h $OUT/${f:t:r}.jpg | cut -f1)"
done
# Godot imports the new pictures before the game can load them.
arch -arm64 godot --headless --path . --import > /dev/null 2>&1
