#!/bin/zsh
# Batch 7: every view and change, rendered once, by the supervisor (CLAUDE.md: build everything, then
# render everything once). One Godot at a time through realm/tools/render.sh's queue. The shots and the
# reference each is judged beside are listed in docs/review/v15.json; docs/review/v15_apply.py puts the
# results on the review page.
#
#   docs/review/batch7.sh            # all of it, about 75 minutes [estimate: the launches' LIMITs and waits]
#   ONLY="towns fire" docs/review/batch7.sh   # some launches only: towns moods fire breach army hosts night
#   OUT=/tmp/goc-batch7 (default)    # frames, logs and clips land here
#
# It runs on its own private bridge (8788, Freeciv 5557) with a fresh reign named "Film batch 7", so the
# test hooks (a town's mood, a sack) answer and Mac's realm on 8787 is never touched. It stops that
# bridge when it ends. Nothing here edits the repo; v15_apply.py (run at the end) writes under docs/review.
R=${0:A:h:h:h}
OUT=${OUT:-/tmp/goc-batch7}
PORT=${PORT:-8788}; FC=${FC:-5557}
API=localhost:$PORT
ONLY=${ONLY:-towns moods fire breach army hosts night}
SW=(--look=one --trees=kit --ground=painted --wear=on --team=on --politics=on --castles=kit --houses=kit --towns=plots --fire=v2 --roadside=on)
B=(--bridge=http://127.0.0.1:$PORT)
FF=${FF:-/opt/homebrew/bin/ffmpeg}
mkdir -p $OUT; LOG=$OUT/batch.log
say() { echo "$(date +%T) $*" | tee -a $LOG; }
want() { [[ " $ONLY " == *" $1 "* ]]; }
# A harness step exists (autoplay.gd)? "site" and "work" frame a roadside site and a trade's building.
has_step() { grep -q "^[[:space:]]*\"$1\":" $R/realm/scripts/autoplay.gd; }
# burst <name> <frames> <gap s>: scenario lines for a clip's frames (name-01.png ...).
burst() { local k; for k in {1..$2}; do print "snap $(printf '%s-%02d' $1 $k)"; print "wait $3"; done; }
# play <launch> <limit s> [game flags...]: one launch playing $OUT/<launch>.play; frames in $OUT/<launch>/.
play() {
  local name=$1 limit=$2; shift 2
  say "launch $name: $*"
  curl -s -m 5 -o /dev/null -X POST $API/court/close
  LIMIT=$limit $R/realm/tools/render.sh $OUT/$name.png $B $SW "$@" --play=$OUT/$name.play --out=$OUT/$name >> $OUT/render.out 2>&1
  grep "^ *[0-9.]* *  \(site\|work\) " $OUT/$name/play.log 2>/dev/null | tee -a $LOG
  say "launch $name done: $(/bin/ls $OUT/$name 2>/dev/null | grep -c png) frames; script errors: $(grep -c 'SCRIPT ERROR\|SHADER ERROR' $OUT/$name.log 2>/dev/null)"
}
# clip <dir> <prefix> <fps>: the frames of a burst as a small looping mp4 beside them.
clip() { /bin/ls $1/$2-01.png > /dev/null 2>&1 && $FF -loglevel error -y -framerate $3 -i $1/$2-%02d.png -vf "scale=1600:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart $1/$2.mp4; }

say "batch 7 at $(git -C $R log --oneline -1 | cut -c1-70)"
pgrep -f "godot --path" > /dev/null && say "note: a Godot is running; these renders queue behind it"

# 1. The private bridge and its reign.
n=$(pgrep -f "^node server.js" | wc -l)
(( n >= 2 )) && { say "two private bridges are up already (the limit); stop one first"; exit 1; }
lsof -iTCP:$PORT -sTCP:LISTEN > /dev/null 2>&1 && { say "port $PORT is taken; set PORT and FC"; exit 1; }
H=$OUT/home; rm -rf $H; mkdir -p $H
( cd $R/bridge && PORT=$PORT FC_PORT=$FC GOC_HOME=$H nice -n 5 node server.js > $OUT/bridge.log 2>&1 ) &
cleanup() { P=$(lsof -tiTCP:$PORT -sTCP:LISTEN); [ -n "$P" ] && kill $P; sleep 2; pkill -f "freeciv-server -p $FC "; say "bridge stopped"; }
trap cleanup EXIT
trap "exit 1" TERM INT
for i in {1..60}; do curl -s -m 3 -o /dev/null "$API/world?peek=1" && break; sleep 1; done
r=$(curl -s -m 30 -X POST $API/chronicles -d '{"name":"Film batch 7","scenario":"aldmere","minutes":60,"wealth":"comfortable","options":{}}')
NID=$(print -r -- "$r" | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
[ -n "$NID" ] || { say "the reign wasn't made: $(print -r -- $r | head -c 200)"; exit 1; }
for i in {1..40}; do curl -s -m 5 $API/chronicles | grep -q "\"active\":\"$NID\"" && break; sleep 2; done
for i in {1..60}; do curl -s -m 5 $API/world | python3 -I -c "import json,sys; sys.exit(0 if len(json.load(sys.stdin).get('cities',[]))>5 else 1)" 2>/dev/null && break; sleep 3; done
say "reign $NID is up"
# The towns the shots use: the crown's seat (the feast), its nearest neighbour (the war), the next (the sack),
# then the next two (the hunger and the levy; the war town again if the realm is small).
read SEAT SEATID WAR WARID SACK SACKID HUNGER HUNGERID LEVY LEVYID MX MY MD <<< $(curl -s -m 8 $API/world | python3 -I -c "
import json,sys
w=json.load(sys.stdin); t=lambda c: c.get('title',c['name'])
s=[c for c in w['cities'] if c['id']==w.get('seatId')] or [c for c in w['cities'] if t(c)=='Kingsmere']
s=s[0]; d=lambda c:((c['x']-s['x'])**2+(c['y']-s['y'])**2)**.5
o=sorted([c for c in w['cities'] if c['id']!=s['id'] and ' ' not in t(c)], key=d)
a,b=o[0],o[1]
c=o[2] if len(o)>2 else a; e=o[3] if len(o)>3 else a
print(t(s),s['id'],t(a),a['id'],t(b),b['id'],t(c),c['id'],t(e),e['id'],(s['x']+a['x'])//2,(s['y']+a['y'])//2,int(max(14,min(45,2.4*d(a)))))")
say "seat $SEAT ($SEATID) feasts; $WAR ($WARID) is at war; $SACK ($SACKID) is sacked; $HUNGER ($HUNGERID) starves; $LEVY ($LEVYID) musters a levy; between the first two: tile $MX $MY at $MD"
stage() { curl -s -m 10 -X POST -H "X-Test: 1" $API/test/stage -d "$1" | head -c 160; }
: > $OUT/notes.txt
note() { print -r -- "$1" >> $OUT/notes.txt; say "note: $1"; }

# 2. The towns: Kingsmere and Goldrock close, at d14 and at d40; the roadside; the working buildings.
if want towns; then
  {
    print "wait 25"
    for T in Kingsmere Goldrock; do
      t=${T:l}
      print "city $T 4.5 -25"; print "wait 10"; print "snap $t-d4"
      print "city $T 6 -25"; print "wait 5"; print "snap $t-d6"
      print "city $T 14 -22"; print "wait 6"; print "snap $t-d14"
      print "city $T 40 -20"; print "wait 6"; print "snap $t-d40"
    done
    # The working buildings (works.gd): the forge, the stables and paddock, the mill.
    if has_step work; then
      # Each from the square first, so a town without the trade still shows its square (play.log says which).
      print "city Kingsmere 4.5 -25"; print "work Kingsmere forge 4.5 -25"; print "wait 8"; print "snap forge"; burst forge-clip 24 0.2
      print "city Kingsmere 4.5 -25"; print "work Kingsmere stables 5 -25"; print "wait 8"; print "snap stables"; burst stables-clip 24 0.2
      print "city Goldrock 8 -25"; print "work Goldrock mill 5 -25"; print "wait 8"; print "snap mill"; burst mill-clip 24 0.2
      # The barn's yard (2d5a2118): cows, sheep and pigs grazing and rooting, the yardhand milking and mucking out.
      print "city Kingsmere 4.5 -25"; print "work Kingsmere barn 4.5 -25"; print "wait 8"; print "snap barnyard"; burst barnyard-clip 24 0.2
    else
      # No step frames a trade's building yet: the square, where the inn, stables, paddock and forge stand.
      print "city Kingsmere 4.5 -25"; print "wait 8"; print "snap forge"; burst forge-clip 24 0.2
      print "life Kingsmere groom 4.5"; print "wait 6"; print "snap stables"; burst stables-clip 24 0.2
      print "city Goldrock 8 -25"; print "wait 8"; print "snap mill"; burst mill-clip 24 0.2
    fi
    # Life along the roads (roadside.gd): an inn, a hamlet, a bridge; carts and travellers on the road.
    if has_step site; then
      # Each from the road first, so a realm without the kind still shows the road (play.log says which).
      print "road Kingsmere 8"; print "site inn 0 6 -25"; print "wait 8"; print "snap inn"; burst inn-clip 24 0.2
      print "road Goldrock 8"; print "site hamlet 0 8 -25"; print "wait 8"; print "snap hamlet"
      print "road Kingsmere 16"; print "site bridge 0 6 -25"; print "wait 8"; print "snap bridge"
    else
      # No step frames a roadside site yet: the road out of each town, where the first inn stands 9 units on.
      print "road Kingsmere 8"; print "wait 8"; print "snap inn"; burst inn-clip 24 0.2
      print "road Goldrock 8"; print "wait 8"; print "snap hamlet"
      print "road Kingsmere 16"; print "wait 8"; print "snap bridge"
    fi
    print "road Kingsmere 5"; print "wait 8"; print "snap carts"; burst carts-clip 28 0.2
    print "look towns-end"
  } > $OUT/towns.play
  has_step work || note "forge, stables, mill: framed at the square (no 'work' step in the harness yet)"
  has_step site || note "inn, hamlet, bridge: framed along the road out of town (no 'site' step in the harness yet); check what's in frame"
  play towns 1200
  for c in forge-clip stables-clip mill-clip barnyard-clip inn-clip carts-clip; do clip $OUT/towns $c 5; done
fi

# 3. A war town next to a feast town.
if want moods; then
  # The works-life session's moods (moods.json): war (c49ee2c6: faster smiths, shut stalls, the levy in two rows,
  # soldiers on the inn's benches), feast (355e710a: bunting, the long tables, the minstrel), hunger (7d97840d:
  # cold chimneys, bare stalls, the granary queue), a levy marching out (955f4bb9: kin waving at the well).
  say "war: $(stage "{\"city\":$WARID,\"mood\":\"war\"}")  feast: $(stage "{\"city\":$SEATID,\"mood\":\"feast\"}")"
  say "hunger: $(stage "{\"city\":$HUNGERID,\"mood\":\"hunger\"}")  levy: $(stage "{\"muster\":$LEVYID}")"
  {
    print "wait 25"
    print "city $WAR 6 -25"; print "wait 10"; print "snap war-town"; burst war-clip 24 0.2
    if has_step work; then print "work $WAR inn 4.5 -25"; print "wait 6"; print "snap war-inn"; fi
    print "city $SEAT 6 -25"; print "wait 10"; print "snap feast-town"; burst feast-clip 24 0.2
    print "city $SEAT 3.5 -25"; print "wait 6"; print "snap feast-tables"
    print "city $HUNGER 6 -25"; print "wait 10"; print "snap hunger-town"
    print "city $LEVY 6 -25"; print "wait 10"; print "snap levy-town"; burst levy-clip 28 0.25
    print "tile $MX $MY $MD"; print "wait 8"; print "snap war-feast-wide"
    print "look moods-end"
  } > $OUT/moods.play
  play moods 720
  for c in war-clip feast-clip levy-clip; do clip $OUT/moods $c 5; done
  for c in $WARID $SEATID $HUNGERID; do stage "{\"city\":$c,\"mood\":\"calm\"}" > /dev/null; done
fi

# 4. Fire: a town sacked while the camera watches (--fire=v2), then what's left.
if want fire; then
  {
    print "wait 25"
    print "city $SACK 6 -25"; print "wait 10"; print "snap fire-before"
    print "look sack-now"; print "wait 6"
    print "snap fire-06s"; burst fire-clip 28 0.2
    print "wait 4"; print "snap fire-20s"
    print "wait 40"; print "snap fire-ruin"
    print "look fire-end"
  } > $OUT/fire.play
  rm -rf $OUT/fire
  ( for i in {1..900}; do grep -q "sack-now" $OUT/fire/play.log 2>/dev/null && { curl -s -m 5 -o /dev/null -X POST $API/court/close; say "sack: $(stage "{\"sack\":$SACKID}")"; break; }; sleep 1; done ) &
  play fire 600
  clip $OUT/fire fire-clip 5
fi

# 5. The wall breach and the storm through it (--walls=stone --siege --wall-demo; the storm is on with the demo,
# 959e850f): the wall cracks, crumbles and opens (about 20-30 s after the siege stands), the parties fight the
# holder's block in the gap, the losers fall back, the town is taken and put to the torch (--fire=v2).
if want breach; then
  {
    print "wait 25"
    if has_step breach; then print "breach 4 -25"; else print "look breach-front"; fi
    print "wait 12"; print "snap breach-cracked"
    print "wait 20"
    if has_step breach; then print "breach 3 -25"; fi
    print "snap breach"; burst breach-clip 30 0.2
    print "wait 4"; burst storm-clip 36 0.25
    print "wait 30"
    if has_step breach; then print "breach 3.5 -25"; fi
    print "snap storm-taken"
    print "wait 25"
    if has_step breach; then print "breach 7 -22"; fi
    print "snap storm-fire"
    print "look breach-end"
  } > $OUT/breach.play
  play breach 600 --walls=stone --siege --wall-demo
  for c in breach-clip storm-clip; do clip $OUT/breach $c 5; done
fi

# 6. The army by regiment (fcf18837; army_spike.gd frames the host itself at the shot's --dist): the line with a
# regiment selected, close (d12); the line from far, where it shows as blocks (d50); the column marching on the
# road (d25), with a clip.
if want army; then
  say "launch army line d12, regiment 0 selected"
  LIMIT=420 $R/realm/tools/render.sh $OUT/army-line-d12.png $B $SW --dist=12 --wait=90 --army-spike=6000 --army-shape=line --army-select=0 >> $OUT/render.out 2>&1
  grep "^ARMY" $OUT/army-line-d12.log | tail -3 >> $LOG
  say "launch army line d50"
  LIMIT=420 $R/realm/tools/render.sh $OUT/army-line-d50.png $B $SW --dist=50 --wait=90 --army-spike=6000 --army-shape=line >> $OUT/render.out 2>&1
  grep "^ARMY" $OUT/army-line-d50.log | tail -3 >> $LOG
  # Marching: frames snapped by the harness while the spike holds the camera on the column.
  { print "wait 60"; print "snap army-march"; burst army-clip 28 0.2; print "look army-end"; } > $OUT/army.play
  play army 480 --dist=25 --army-spike=6000 --army-shape=march
  clip $OUT/army army-clip 5
fi

# 6b. Commanding a host (3770f00c, --hosts=on): the crown's largest host ordered to march on the war town (through
# the bridge, as the card would), then selected by a click on its standard: the gold ring, the lit banner, the
# command card over the minimap, and its dotted route; then from higher, the whole route.
if want hosts; then
  read HOSTID HOSTMEN <<< $(curl -s -m 8 $API/world | python3 -I -c "
import json,sys
h=sorted(json.load(sys.stdin).get('hosts',[]), key=lambda h:-h.get('men',0))
print(h[0]['id'], h[0].get('men',0)) if h else print('', 0)")
  if [ -n "$HOSTID" ]; then
    say "host $HOSTID ($HOSTMEN men) marches on $WAR: $(curl -s -m 10 -X POST $API/host/order -d "{\"host\":$HOSTID,\"order\":\"march\",\"city\":$WARID}" | head -c 160)"
  else
    note "hosts: the reign has no host in the field; the shots show the land where one would stand (play.log says so)"
  fi
  {
    print "wait 25"
    print "host 0 6 -25"; print "wait 2"; print "snap host-selected"
    print "host 0 16 -22"; print "wait 3"; print "snap host-route"
    print "look hosts-end"
  } > $OUT/hosts.play
  play hosts 420 --hosts=on
fi

# 7. Night: the inn's windows lit (a test hour; the realm players get is always day in v1).
if want night; then
  {
    print "wait 25"
    if has_step work; then print "work Kingsmere inn 4.5 -25"; else print "city Kingsmere 4.5 -25"; fi
    print "wait 10"; print "snap night-inn"
    if has_step site; then print "site inn 0 6 -25"; print "wait 8"; print "snap night-road-inn"; fi
    print "look night-end"
  } > $OUT/night.play
  play night 420 --hour=21
fi

# 8. What came out, and onto the review page's folder.
say "frames:"
python3 -I $R/docs/review/v15_apply.py $OUT --check | tee -a $LOG
python3 -I $R/docs/review/v15_apply.py $OUT | tee -a $LOG
say "batch 7 done. Stills, clips and logs: $OUT. Publish list: $R/docs/review/v15-publish.json"
