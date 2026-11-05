#!/bin/zsh
# Copies this cut's media from where it lives in the repo into assets/ (gitignored).
cd "$(dirname "$0")/.."
R=../../..; A=$R/realm/assets/audio
mkdir -p assets/play assets/world assets/audio assets/fonts
for f in 01-town 02-funded 03-ride-a 04-ride-b 05-ride-c 06-ride-d 07-ride-e 08-prices 09-after-a-season; do cp $R/docs/play/r31-ride/$f.jpg assets/play/; done
for s in seat_Riverhall seat_Lionmoor; do ffmpeg -loglevel error -y -i $R/realm/assets/intro/stills/$s.png -q:v 2 assets/world/$s.jpg; done
cp $R/media/brand-kit/logos/full-title-original.png assets/world/title.png
cp $R/realm/assets/fonts/{EBGaramond.ttf,Cinzel.ttf,OFL-EBGaramond.txt,OFL-Cinzel.txt} assets/fonts/
ffmpeg -loglevel error -y -i $A/music/tension_lament_of_the_war.ogg -c:a libmp3lame -q:a 2 assets/audio/lament.mp3
for s in sfx/coins.wav sfx/gallop.ogg sfx/toll_bell.ogg sfx/war_drums.ogg sfx/war_horn.ogg ui/page.wav ui/seal.wav; do
  ffmpeg -loglevel error -y -i $A/$s -c:a libmp3lame -q:a 2 assets/audio/$(basename ${s%.*}).mp3; done
echo ok
