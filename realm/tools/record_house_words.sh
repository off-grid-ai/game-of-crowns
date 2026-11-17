#!/bin/zsh
# Records each great house's words (and the Crown's) in every ruler's voice with Off Grid AI Desktop's Kokoro
# voices (its local gateway, /v1/audio/speech) into realm/assets/audio/voice/houses/<house>/<profile>.ogg.
# Headless; OGAD must be running. Which profile speaks is chosen in play from the house's ruler (sound_v2.gd
# voice_profile; sounds.json house_words.profiles), so a new lord needs no new recording.
set -e
OUT=${0:A:h}/../assets/audio/voice/houses
TMP=$(mktemp -d)
GW=""
for p in {7878..7885}; do curl -s -m 2 http://127.0.0.1:$p/health | grep -qi "off grid" && GW=http://127.0.0.1:$p/v1 && break; done
[[ -n $GW ]] || { echo "Off Grid AI Desktop isn't running"; exit 1; }
# Profile | Kokoro voice | pitch | pace
PROFILES=(
  "old_man|bm_daniel|0.80|0.80"
  "man|am_adam|0.88|0.92"
  "young_man|am_michael|0.98|1.0"
  "old_woman|bf_emma|0.86|0.84"
  "woman|af_sarah|0.95|0.93"
  "young_woman|af_heart|1.03|1.0"
)
# House | what is said | hall echo
HOUSES=(
  "wolfholt|Hold... fast.|0.5"
  "goldcrest|Wealth is strength.|0.3"
  "ironreach|The sea provides!|0.35"
  "thornvale|Root, and thorn.|0.3"
  "stormhold|We weather all!|0.45"
  "sunspire|The sun waits.|0.4"
  "highfell|Sworn, and steadfast.|0.55"
  "crown|One realm.|0.6"
)
for h in $HOUSES; do
  IFS='|' read id txt e <<< "$h"
  mkdir -p $OUT/$id
  for pr in $PROFILES; do
    IFS='|' read prof v p t <<< "$pr"
    curl -sf -m 60 $GW/audio/speech -H 'content-type: application/json' -d "{\"model\":\"kokoro\",\"input\":\"$txt\",\"voice\":\"$v\"}" -o $TMP/raw.wav
    r=$(python3 -c "print(round(24000*$p))"); at=$(python3 -c "print(round($t/$p,3))"); e2=$(python3 -c "print(round($e*0.5,2))")
    ffmpeg -loglevel error -y -i $TMP/raw.wav -af "asetrate=$r,aresample=24000,atempo=$at,aecho=0.8:0.5:60|110:$e|$e2,highpass=f=70,loudnorm=I=-18:TP=-2,apad=pad_dur=0.25,adelay=80" -ac 1 -ar 22050 $TMP/fx.wav < /dev/null
    oggenc -Q -q 3 -o $OUT/$id/$prof.ogg $TMP/fx.wav 2>/dev/null
    echo "$id/$prof.ogg"
  done
done
rm -rf $TMP
