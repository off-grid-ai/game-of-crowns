#!/bin/zsh
# Records the realm's calls (the big moments, announcer style) and the names said after some of them, in one voice:
# deep, slow, big, in a hall. Off Grid AI Desktop's Kokoro voices (its local gateway, /v1/audio/speech) into
# realm/assets/audio/voice/events/<moment>.ogg and realm/assets/audio/voice/names/<name>.ogg. Headless; OGAD running.
# The herald's building calls go the same way, in the same voice: voice/works/<building>/order_<n>.ogg (the King orders
# it) and built_<n>.ogg (it stands); and the street's own voices (the crier, the hawkers: voice/street/<who>_<n>.ogg) in
# plainer voices, near and dry. `record_calls.sh [calls|works|street]`: only that part (none: all of it).
set -e
PART=${1:-all}
OUT=${0:A:h}/../assets/audio/voice
TMP=$(mktemp -d)
GW=""
for p in {7878..7885}; do curl -s -m 2 http://127.0.0.1:$p/health | grep -qi "off grid" && GW=http://127.0.0.1:$p/v1 && break; done
[[ -n $GW ]] || { echo "Off Grid AI Desktop isn't running"; exit 1; }
VOICE=bm_daniel; PITCH=0.78; PACE=0.84; HALL=0.6
say() {  # folder | file | text  (VOICE PITCH PACE HALL as set)
  mkdir -p $OUT/$1
  curl -sf -m 60 $GW/audio/speech -H 'content-type: application/json' -d "{\"model\":\"kokoro\",\"input\":\"$3\",\"voice\":\"$VOICE\"}" -o $TMP/raw.wav
  local r=$(python3 -c "print(round(24000*$PITCH))") at=$(python3 -c "print(round($PACE/$PITCH,3))") e2=$(python3 -c "print(round($HALL*0.5,2))")
  ffmpeg -loglevel error -y -i $TMP/raw.wav -af "asetrate=$r,aresample=24000,atempo=$at,aecho=0.8:0.6:70|140:$HALL|$e2,highpass=f=60,loudnorm=I=-16:TP=-1.5,apad=pad_dur=0.3,adelay=60" -ac 1 -ar 22050 $TMP/fx.wav < /dev/null
  oggenc -Q -q 3 -o $OUT/$1/$2.ogg $TMP/fx.wav 2>/dev/null
  echo "$1/$2.ogg"
}
if [[ $PART == all || $PART == calls ]]; then
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
fi
# The herald's building calls (sounds.json works_calls; sound_v2.gd herald_work): three ways of each, never the same twice
# running. order: the King has ordered it built; built: it stands. sept is Freeciv's Temple, the game's word for a church.
if [[ $PART == all || $PART == works ]]; then
while IFS='|' read id txt; do say works/${id%/*} ${id#*/} "$txt"; done <<'LIST'
sept/order_1|Build the sept.
sept/order_2|Masons to the square. A sept for the faithful.
sept/order_3|The King wills a sept. Fetch the masons.
sept/built_1|The sept stands.
sept/built_2|The sept is raised. Ring the bell.
sept/built_3|The new sept stands. Let the town come and pray.
granary/order_1|Build the granary.
granary/order_2|The King wants a granary. Bring the timber.
granary/order_3|Dig the footings. A granary, by the King's word.
granary/built_1|The granary stands.
granary/built_2|The granary stands. Let winter come.
granary/built_3|The new granary is roofed. Fill it before the frost.
walls/order_1|Raise the walls.
walls/order_2|Stone and men to the walls, by the King's word.
walls/order_3|The King wants walls. Start at the gate.
walls/built_1|The walls stand.
walls/built_2|The walls are raised. Let them come.
walls/built_3|The new walls stand, gate and all.
market/order_1|Build the market.
market/order_2|The King wants a market. Clear the square.
market/order_3|Stalls and a market cross, by the King's word.
market/built_1|The market stands.
market/built_2|The market is open. Let the traders in.
market/built_3|The new market stands. Coin will follow.
barracks/order_1|Build the barracks.
barracks/order_2|The King wants a barracks. Bring the timber.
barracks/order_3|Quarters for the King's men, by his word.
barracks/built_1|The barracks stand.
barracks/built_2|The barracks are built. Send in the men.
barracks/built_3|The new barracks stand ready for the levy.
aqueduct/order_1|Build the aqueduct.
aqueduct/order_2|The King wants clean water. Dig the channel.
aqueduct/order_3|Stone for the aqueduct, by the King's word.
aqueduct/built_1|The aqueduct stands.
aqueduct/built_2|Clean water runs into the town.
aqueduct/built_3|The aqueduct is done. Let the town drink.
LIST
fi
# The street's voices (sounds.json crier, hawker; soundscape.gd plays them on the move, near the one who calls): the
# crier with the news in the square, the stallholders crying their wares. Plain voices, a little room, no hall.
if [[ $PART == all || $PART == street ]]; then
VOICE=bm_daniel; PITCH=0.92; PACE=0.95; HALL=0.15
while IFS='|' read id txt; do say street $id "$txt"; done <<'LIST'
crier_1|Hear ye! Hear ye!
crier_2|Gather round, all of you! News from Kingsmere!
crier_3|Hear the King's word!
crier_4|Hear ye! The crier speaks!
LIST
VOICE=am_adam; PITCH=0.9; PACE=1.0; HALL=0.12
while IFS='|' read id txt; do say street $id "$txt"; done <<'LIST'
hawker_1|Bread! Fresh bread!
hawker_2|Eels, fresh from the river!
hawker_3|Good wool, cheap today!
LIST
VOICE=am_michael; PITCH=0.88; PACE=1.0; HALL=0.12
while IFS='|' read id txt; do say street $id "$txt"; done <<'LIST'
hawker_4|Salt! Who will buy my salt?
hawker_5|Apples! Sweet apples!
hawker_6|Ale by the cup!
LIST
fi
rm -rf $TMP
