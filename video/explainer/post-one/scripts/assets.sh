#!/bin/zsh
# Copies this cut's media from where it lives in the repo into assets/ (gitignored).
cd "$(dirname "$0")/.."
R=../../..; A=$R/realm/assets/audio
mkdir -p assets/play assets/world assets/audio assets/fonts
cp $R/docs/play/r13-politics/05-court-oneline.jpg assets/play/b05.jpg
cp $R/docs/play/r13-politics/08-table-counsel.jpg assets/play/b08.jpg
cp $R/docs/play/r13-politics/09-ruling-card.jpg assets/play/b09.jpg
cp $R/docs/play/r14-siege/03-siege.jpg assets/play/b14s.jpg
cp $R/docs/play/r14-siege/06-odds.jpg assets/play/b14o.jpg
for s in seat_Riverhall seat_Lionmoor; do ffmpeg -loglevel error -y -i $R/realm/assets/intro/stills/$s.png -q:v 2 assets/world/$s.jpg; done
cp $R/media/brand-kit/logos/full-title-original.png assets/world/title.png
cp $R/realm/assets/fonts/{EBGaramond.ttf,Cinzel.ttf,OFL-EBGaramond.txt,OFL-Cinzel.txt} assets/fonts/
ffmpeg -loglevel error -y -i $A/music/battle_viking_march.ogg -c:a libmp3lame -q:a 2 assets/audio/march.mp3
for s in sfx/toll_bell.ogg sfx/war_drums.ogg sfx/war_horn.ogg ui/page.wav ui/seal.wav; do
  ffmpeg -loglevel error -y -i $A/$s -c:a libmp3lame -q:a 2 assets/audio/$(basename ${s%.*}).mp3; done
echo ok
