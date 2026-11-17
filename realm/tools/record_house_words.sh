#!/bin/zsh
# Records each great house's words with Off Grid AI Desktop's Kokoro voices (its local gateway,
# /v1/audio/speech) into realm/assets/audio/voice/houses/<house>.ogg. Headless; OGAD must be running.
# Each line: id | Kokoro voice | what is said | pitch | pace | hall echo.
set -e
OUT=${0:A:h}/../assets/audio/voice/houses
TMP=$(mktemp -d)
GW=""
for p in {7878..7885}; do curl -s -m 2 http://127.0.0.1:$p/health | grep -qi "off grid" && GW=http://127.0.0.1:$p/v1 && break; done
[[ -n $GW ]] || { echo "Off Grid AI Desktop isn't running"; exit 1; }
while IFS='|' read id v txt p t e; do
  curl -sf -m 60 $GW/audio/speech -H 'content-type: application/json' -d "{\"model\":\"kokoro\",\"input\":\"$txt\",\"voice\":\"$v\"}" -o $TMP/raw.wav
  r=$(python3 -c "print(round(24000*$p))"); at=$(python3 -c "print(round($t/$p,3))"); e2=$(python3 -c "print(round($e*0.5,2))")
  ffmpeg -loglevel error -y -i $TMP/raw.wav -af "asetrate=$r,aresample=24000,atempo=$at,aecho=0.8:0.5:60|110:$e|$e2,highpass=f=70,loudnorm=I=-18:TP=-2,apad=pad_dur=0.25,adelay=80" -ac 1 -ar 22050 $TMP/fx.wav < /dev/null
  oggenc -Q -q 3 -o $OUT/$id.ogg $TMP/fx.wav
  echo "$id.ogg"
done <<'LIST'
wolfholt|bm_daniel|Hold... fast.|0.86|0.85|0.5
goldcrest|bf_emma|Wealth is strength.|0.97|0.95|0.3
ironreach|am_adam|The sea provides!|0.84|0.95|0.35
thornvale|af_heart|Root, and thorn.|1.0|0.92|0.3
stormhold|am_michael|We weather all!|0.9|1.0|0.45
sunspire|em_alex|The sun waits.|0.94|0.85|0.4
highfell|af_river|Sworn, and steadfast.|0.96|0.9|0.55
crown|bm_daniel|One realm.|0.8|0.82|0.6
LIST
rm -rf $TMP
