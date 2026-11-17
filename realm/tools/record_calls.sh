#!/bin/zsh
# Records the realm's calls (the big moments, announcer style) and the names said after some of them, in one voice:
# deep, slow, big, in a hall. Off Grid AI Desktop's Kokoro voices (its local gateway, /v1/audio/speech) into
# realm/assets/audio/voice/events/<moment>.ogg and realm/assets/audio/voice/names/<name>.ogg. Headless; OGAD running.
set -e
OUT=${0:A:h}/../assets/audio/voice
TMP=$(mktemp -d)
GW=""
for p in {7878..7885}; do curl -s -m 2 http://127.0.0.1:$p/health | grep -qi "off grid" && GW=http://127.0.0.1:$p/v1 && break; done
[[ -n $GW ]] || { echo "Off Grid AI Desktop isn't running"; exit 1; }
VOICE=bm_daniel; PITCH=0.78; PACE=0.84; HALL=0.6
say() {  # folder | file | text
  mkdir -p $OUT/$1
  curl -sf -m 60 $GW/audio/speech -H 'content-type: application/json' -d "{\"model\":\"kokoro\",\"input\":\"$3\",\"voice\":\"$VOICE\"}" -o $TMP/raw.wav
  local r=$(python3 -c "print(round(24000*$PITCH))") at=$(python3 -c "print(round($PACE/$PITCH,3))") e2=$(python3 -c "print(round($HALL*0.5,2))")
  ffmpeg -loglevel error -y -i $TMP/raw.wav -af "asetrate=$r,aresample=24000,atempo=$at,aecho=0.8:0.6:70|140:$HALL|$e2,highpass=f=60,loudnorm=I=-16:TP=-1.5,apad=pad_dur=0.3,adelay=60" -ac 1 -ar 22050 $TMP/fx.wav < /dev/null
  oggenc -Q -q 3 -o $OUT/$1/$2.ogg $TMP/fx.wav 2>/dev/null
  echo "$1/$2.ogg"
}
while IFS='|' read id txt; do say events $id "$txt"; done <<'LIST'
danger|The realm is in danger!
revolt|Revolt!
famine|Famine!
plague|Plague!
victory|Victory!
heroic|Glorious victory!
pyrrhic|Bitter victory!
defeat|Defeat!
break|They break!
war_won|The war is won!
war_lost|The war is lost!
town_lost|Town lost!
retaken|Town retaken!
king_dead|The King is dead!
crowned|Long live the King!
LIST
while IFS='|' read id txt; do say names $id "$txt"; done <<'LIST'
wolfholt|Wolfholt!
goldcrest|Goldcrest!
ironreach|Ironreach!
thornvale|Thornvale!
stormhold|Stormhold!
sunspire|Sunspire!
highfell|Highfell!
kingsmere|Kingsmere!
LIST
rm -rf $TMP
