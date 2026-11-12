#!/bin/zsh
# Batch 7: every view and change, rendered once, by the supervisor (CLAUDE.md: build everything, then
# render everything once). One Godot at a time through realm/tools/render.sh's queue. The shots and the
# reference each is judged beside are listed in docs/review/v15.json; docs/review/v15_apply.py puts the
# results on the review page.
#
#   docs/review/batch7.sh            # all of it, about 129 minutes [estimate: the launches' LIMITs and waits]
#   ONLY="towns fire" docs/review/batch7.sh   # some launches only: towns square castle moods rulings fields fire breach army battle hosts weather night
#   OUT=/tmp/goc-batch7 (default)    # frames, logs and clips land here
#
# It runs on its own private bridge (8788, Freeciv 5557) with a fresh reign named "Film batch 7", so the
# test hooks (a town's mood, a sack) answer and Mac's realm on 8787 is never touched. It stops that
# bridge when it ends. Nothing here edits the repo; v15_apply.py (run at the end) writes under docs/review.
R=${0:A:h:h:h}
OUT=${OUT:-/tmp/goc-batch7}
PORT=${PORT:-8788}; FC=${FC:-5557}
API=localhost:$PORT
ONLY=${ONLY:-towns square castle moods rulings fields fire breach army battle hosts weather night}
SW=()
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

# 2a. Kingsmere's fuller square (works-life's 5c3d1e70, 08de3013, a09db4fb): the same shots before (--crowd=off:
# no crier, beggars at the church step, guard patrol, dogs, children chasing, gossip knots) and after; the
# denser market (towns.json market.crown) stays on in both. The crowd takes about 10 s to form.
if want square; then
  for v in before after; do
    {
      print "wait 25"
      print "city Kingsmere 6 -25"; print "wait 10"; print "snap square-$v"
      print "city Kingsmere 4.5 -25"; print "wait 6"; print "snap square-street-$v"; burst square-clip-$v 24 0.2
      print "look square-$v-end"
    } > $OUT/square-$v.play
    if [ $v = before ]; then play square-$v 360 --crowd=off; else play square-$v 360; fi
    clip $OUT/square-$v square-clip-$v 5
  done
fi

# 2b. The castle (89de30e6, 9228f28c, a0bd512b; --castle-life=on --walls=stone): the seat's kit castle with its
# towers' banners, the guards on its walks, the bailey and its well; then its walls' wear staged on the test
# reign ({damage: {city, section, wear}} for every section) so its stone curtains crack and breach.
if want castle; then
  {
    print "wait 30"
    if has_step castle; then
      print "castle $SEAT 6 -22"; print "wait 8"; print "snap castle"
      print "castle $SEAT 2.5 -18"; print "wait 6"; print "snap castle-walls"; burst guards-clip 30 0.25
      print "castle $SEAT 3 -20 gate"; print "wait 4"; print "snap castle-gate"
      print "look castle-breach"; print "wait 4"
      print "castle $SEAT 4 -22"; print "wait 25"; print "snap castle-breached"
    else
      print "city $SEAT 6 -22"; print "wait 8"; print "snap castle"
    fi
    print "look castle-end"
  } > $OUT/castle.play
  rm -rf $OUT/castle
  ( for i in {1..900}; do
      if grep -q "look castle-breach$" $OUT/castle/play.log 2>/dev/null; then
        for sec in 0 1 2 3 4 5 6 7; do stage "{\"damage\":{\"city\":$SEATID,\"section\":$sec,\"wear\":0.85}}" > /dev/null; done
        say "castle: the seat's walls worn to a breach"; break
      fi
      grep -q "castle-end" $OUT/castle/play.log 2>/dev/null && break; sleep 1
    done ) &
  STAGER=$!
  play castle 480
  wait $STAGER  # the stager only: the bridge runs in the background too
  clip $OUT/castle guards-clip 5
  for sec in 0 1 2 3 4 5 6 7; do stage "{\"damage\":{\"city\":$SEATID,\"section\":$sec,\"wear\":0}}" > /dev/null; done
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

# 3c. The fields through the year (works-life's 4144e005 field work, 65b89302 film hooks): each job held at its
# season ('field season t': the crops ripen to it and the hands follow) and framed on a sown field near the seat:
# the ox plough and the sowing in spring, weeding in summer, the reaping and the stooks then the gleaning in
# autumn, and a shepherd's flock on the fallow. Clips for the plough and the reaping.
if want fields; then
  {
    print "wait 25"
    if has_step field; then
      print "field spring 0.15 0 3 -22"; print "wait 8"; print "snap field-plough"; burst plough-clip 30 0.2
      print "field spring 0.5 0 3 -22"; print "wait 8"; print "snap field-sow"
      print "field summer 0.3 0 3 -22"; print "wait 8"; print "snap field-weed"
      print "field autumn 0.15 0 3 -22"; print "wait 8"; print "snap field-reap"; burst reap-clip 30 0.2
      print "field autumn 0.6 0 3 -22"; print "wait 8"; print "snap field-glean"
      print "field summer 0.4 0 9 -20"; print "wait 6"; print "snap fields-wide"
    else
      print "city $SEAT 9 -20"; print "wait 8"; print "snap fields-wide"
    fi
    if has_step flock; then print "field summer 0.5 0 9 -20"; print "flock 0 3 -22"; print "wait 8"; print "snap flock"; burst flock-clip 40 0.5; fi
    print "look fields-end"
  } > $OUT/fields.play
  has_step field || note "fields: no 'field' step in the harness; only the wide shot round the seat"
  play fields 600
  for c in plough-clip reap-clip flock-clip; do clip $OUT/fields $c 5; done
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
  # The camp and its engines first (9d299d6f, on with --wall-demo): the camp wide while the engines go up, an
  # engine through a whole throw, its stones hitting the wall; then the breach and the storm as before. With
  # only the engines throwing now, the wall opens about 60-80 s after they're built [estimate]: the waits allow it.
  {
    print "wait 25"
    if has_step camp; then print "camp 9 -20"; print "wait 4"; print "snap siege-camp"; fi
    if has_step engine; then print "engine 0 2.5 -18"; print "wait 14"; burst engine-clip 45 0.2; fi
    if has_step breach; then print "breach 4 -25"; else print "look breach-front"; fi
    burst stone-clip 40 0.2
    print "snap breach-cracked"
    print "wait 45"
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
  play breach 600 --siege --wall-demo
  for c in engine-clip stone-clip breach-clip storm-clip; do clip $OUT/breach $c 5; done
fi

# 6. The army by regiment (fcf18837; army_spike.gd frames the host itself at the shot's --dist): the line with a
# regiment selected, close (d12); the line from far, where it shows as blocks (d50); the column marching on the
# road (d25), with a clip.
if want army; then
  say "launch army line d12, regiment 0 selected"
  LIMIT=420 $R/realm/tools/render.sh $OUT/army-line-d12.png $B $SW --dist=12 --wait=90 --army-spike=6000 --army-shape=line --army-select=0 >> $OUT/render.out 2>&1
  grep "^ARMY" $OUT/army-line-d12.log | tail -3 >> $LOG
  say "launch army line d3, house arms on shields and chests (2d434625)"
  LIMIT=420 $R/realm/tools/render.sh $OUT/army-arms-d3.png $B $SW --dist=3 --wait=90 --army-spike=6000 --army-shape=line --army-select=0 >> $OUT/render.out 2>&1
  grep "^ARMY" $OUT/army-arms-d3.log | tail -3 >> $LOG
  say "launch army line d50"
  LIMIT=420 $R/realm/tools/render.sh $OUT/army-line-d50.png $B $SW --dist=50 --wait=90 --army-spike=6000 --army-shape=line >> $OUT/render.out 2>&1
  grep "^ARMY" $OUT/army-line-d50.log | tail -3 >> $LOG
  # Marching: frames snapped by the harness while the spike holds the camera on the column.
  { print "wait 60"; print "snap army-march"; burst army-clip 28 0.2; print "look army-end"; } > $OUT/army.play
  play army 480 --dist=25 --army-spike=6000 --army-shape=march
  clip $OUT/army army-clip 5
fi

# 6a. A field battle (army-ui's d3680bfa, 5891d912; --army-battle=<men a side>): two hosts deploy, volley, meet,
# the horse goes in on the flank, the beaten waver and run, the victors hold the field. The battle frames itself
# at the shot's --dist. Timings are army-ui's estimates from "BATTLE begins" (deploy takes about 40-70 s).
# Then the same close (d4) for men at blows, with a clip for motion.
if want battle; then
  {
    print "wait 70"; print "snap battle-1-lines-formed"
    print "wait 8"; print "snap battle-2-volleys"
    print "wait 12"; print "snap battle-3-fronts-meet"
    print "wait 12"; print "snap battle-4-flank"
    print "wait 10"; print "snap battle-5-waver-rout"
    print "wait 10"; print "snap battle-6-field-held"
    print "look battle-end"
  } > $OUT/battle.play
  play battle 480 --dist=10 --army-battle=3000
  grep "^BATTLE" $OUT/battle.log 2>/dev/null | tail -20 >> $LOG
  { print "wait 82"; print "snap battle-close"; burst battle-clip 30 0.2; print "look battle-close-end"; } > $OUT/battle-close.play
  play battle-close 420 --dist=4 --army-battle=3000
  clip $OUT/battle-close battle-clip 5
  # A battle in play (army-ui's 5a47b648, --battles=field): where the bridge reports a battle, one is staged
  # on open ground there, sized from the men who fought. It never moves the camera: Space jumps to the latest
  # news. Only shows a battle if this reign has had one by now; play.log and the frame say what it found.
  { print "wait 60"; print "key Space"; print "wait 5"; print "snap battle-in-play"; print "look battle-play-end"; } > $OUT/battle-play.play
  play battle-play 300 --battles=field
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
    print "tap host_hold"; print "rclick 0.65 0.45"; print "wait 2"; print "snap host-route"
    print "tap host_march"; print "click 0.3 0.4"; print "wait 2"; print "snap host-march-click"
    print "look hosts-end"
  } > $OUT/hosts.play
  play hosts 420 --hosts=on
fi

# 3b. The King's rulings seen in the town (works-life's ac9e2ea7 bridge half, 8bcd3c42 view half; CK3, Manor
# Lords, Stronghold): one ruling at a time at the crown's seat, each staged when the scenario reaches its mark
# ({city, ruling: kind} on the test reign), then the square shot from roof height and a step back. The one
# before is cleared first. Relief, justice, grant and build first; feast and levy last (they also raise their
# scenes, which stay).
RULINGS=(relief justice grant build feast levy)
if want rulings; then
  {
    print "wait 25"
    for k in $RULINGS; do
      print "look ruling-$k"; print "wait 12"
      print "city $SEAT 4.5 -25"; print "wait 8"; print "snap ruling-$k"
      print "city $SEAT 7 -25"; print "wait 4"; print "snap ruling-$k-wide"
    done
    print "look rulings-end"
  } > $OUT/rulings.play
  rm -rf $OUT/rulings
  # The staging rides alongside the launch: each mark the scenario logs stages its ruling.
  ( staged=""; for i in {1..900}; do
      for k in $RULINGS; do
        if [[ " $staged " != *" $k "* ]] && grep -q "look ruling-$k\$" $OUT/rulings/play.log 2>/dev/null; then
          [ -n "$staged" ] && stage "{\"city\":$SEATID,\"ruling\":\"none\"}" > /dev/null
          say "ruling $k at $SEAT: $(stage "{\"city\":$SEATID,\"ruling\":\"$k\"}")"
          staged="$staged $k"
        fi
      done
      grep -q "rulings-end" $OUT/rulings/play.log 2>/dev/null && break; sleep 1
    done
    stage "{\"city\":$SEATID,\"ruling\":\"none\"}" > /dev/null; stage "{\"city\":$SEATID,\"mood\":\"calm\"}" > /dev/null ) &
  STAGER=$!
  play rulings 720
  wait $STAGER  # the stager only: the bridge runs in the background too
fi

# 6c. Weather (7d3e958d, e9b5aca7, 2730b25f; --weather=v2): rain held on the test reign ({weather: rain}), the
# seat close (wet dark roofs glinting, puddles, mud on the roads, half its people indoors) and whole, with a clip
# for the banners and grass in the wind; then a winter launch (--season=winter, {weather: snow}): snow on the
# roofs in patches and on the ground. The weather is set back to clear after.
if want weather; then
  say "rain: $(stage '{"weather":"rain"}')"
  {
    print "wait 40"
    print "city $SEAT 4.5 -25"; print "wait 8"; print "snap rain-close"; burst rain-clip 24 0.2
    print "city $SEAT 3 -22"; print "wait 6"; print "snap rain-square"
    print "city $SEAT 14 -22"; print "wait 6"; print "snap rain-town"
    print "look rain-end"
  } > $OUT/rain.play
  play rain 420
  clip $OUT/rain rain-clip 5
  say "snow: $(stage '{"weather":"snow"}')"
  {
    print "wait 60"
    print "city $SEAT 4.5 -25"; print "wait 8"; print "snap snow-close"
    print "city $SEAT 14 -22"; print "wait 6"; print "snap snow-town"
    print "look snow-end"
  } > $OUT/snow.play
  play snow 420 --season=winter
  stage '{"weather":"clear"}' > /dev/null
fi

# 7. Night: the inn's windows lit (a test hour; the realm players get is always day in v1).
if want night; then
  {
    print "wait 25"
    if has_step work; then print "work Kingsmere inn 4.5 -25"; else print "city Kingsmere 4.5 -25"; fi
    print "wait 10"; print "snap night-inn"
    if has_step site; then print "site inn 0 6 -25"; print "wait 8"; print "snap night-road-inn"; fi
    print "road Kingsmere 8"; print "wait 10"; print "snap night-road"  # only a torchlit patrol or a messenger by night
    if has_step castle; then print "castle Kingsmere 3 -20 gate"; print "wait 6"; print "snap night-castle-gate"; fi
    print "look night-end"
  } > $OUT/night.play
  play night 420 --hour=21
fi

# 8. What came out, and onto the review page's folder.
say "frames:"
python3 -I $R/docs/review/v15_apply.py $OUT --check | tee -a $LOG
python3 -I $R/docs/review/v15_apply.py $OUT | tee -a $LOG
say "batch 7 done. Stills, clips and logs: $OUT. Publish list: $R/docs/review/v15-publish.json"
