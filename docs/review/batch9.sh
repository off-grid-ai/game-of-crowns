#!/bin/zsh
# Batch 9: every shot on docs/review/batch9-list.md (all four sessions'), rendered once by the supervisor
# (CLAUDE.md: build everything, then render everything once), right after batch 8b. One Godot at a time through
# realm/tools/render.sh's queue. Every launch runs with the round's switches on (--ui=v2, the dressing, the
# landmarks: --landmarks=meshy unless a before shot sets LM=--landmarks=kit) and silent (no audio device), but
# the sound launch, which records. It starts with the import step: Meshy's pieces through Blender, then one
# headless Godot import pass. Close town shots stop at roof height (Mac: no close-up realism; at least 3.5 out,
# tilt -5). The shots and their references are in docs/review/v17.json; v17_apply.py puts them
# on the review page. Generated from the list (the fire-siege session); edit the launches here, not the list.
#
#   docs/review/batch9.sh            # all of it, about 137 minutes [estimate: the launches' LIMITs and waits]
#   ONLY="ladder fire" docs/review/batch9.sh   # some launches only: ladder settled clarity fire fixes meshy village fountain ui decisions breach hosts battle sound
#   OUT=/tmp/goc-batch9 (default)    # frames, logs and clips land here
#
# Its own private bridge (8788, Freeciv 5557; PORT, FC to change) with a fresh reign named "Film batch 9", so the
# test hooks (a town's mood, a sack, a muster, a ruling, a house's favour) answer and Mac's realm on 8787 is
# never touched. It stops that bridge when it ends. Nothing here edits the repo; v17_apply.py writes under docs/review.
R=${0:A:h:h:h}
OUT=${OUT:-/tmp/goc-batch9}
PORT=${PORT:-8788}; FC=${FC:-5557}
API=localhost:$PORT
ONLY=${ONLY:-ladder settled clarity fire fixes meshy village fountain ui decisions breach hosts battle sound}
SW=(--look=one --trees=kit --ground=painted --wear=on --team=on --politics=on --castles=kit --houses=kit --towns=plots --fire=v2 --roadside=on --ui=v2 --dressing=on --castle-life=on --weather=v2)
# The landmarks (--landmarks=meshy) ride on every launch through LM; a before shot sets LM=--landmarks=kit for its run.
LM=${LM:---landmarks=meshy}
# Films run silent (no audio device: faster, and no sound to wait on); the sound launch sets its own.
GODOT_ARGS_FILM=${GODOT_ARGS_FILM:---audio-driver Dummy}
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
  rm -rf $OUT/$name
  LIMIT=$limit GODOT_ARGS="${GODOT_ARGS-$GODOT_ARGS_FILM}" $R/realm/tools/render.sh $OUT/$name.png $B $SW ${=LM} "$@" --play=$OUT/$name.play --out=$OUT/$name >> $OUT/render.out 2>&1
  grep "^ *[0-9.]* *  \(site\|work\) " $OUT/$name/play.log 2>/dev/null | tee -a $LOG
  say "launch $name done: $(/bin/ls $OUT/$name 2>/dev/null | grep -c png) frames; script errors: $(grep -c 'SCRIPT ERROR\|SHADER ERROR' $OUT/$name.log 2>/dev/null)"
}
# stage_on <launch> <mark> <json...>: when the launch's scenario reaches "look <mark>", stage each on the test
# reign (a mood, a sack, a muster, a ruling). Runs alongside; settle_stagers after the launch waits for them.
STAGERS=()
stage_on() {
  local name=$1 mark=$2; shift 2
  ( for i in {1..900}; do
      if grep -q "look $mark\$" $OUT/$name/play.log 2>/dev/null; then
        for j in "$@"; do say "stage $mark: $(stage "$j")"; done; break
      fi
      grep -q "look $name-end" $OUT/$name/play.log 2>/dev/null && break; sleep 1
    done ) &
  STAGERS+=($!)
}
settle_stagers() { (( ${#STAGERS} )) && wait $STAGERS; STAGERS=(); }
# clip <dir> <prefix> <fps>: the frames of a burst as a small looping mp4 beside them.
clip() { /bin/ls $1/$2-01.png > /dev/null 2>&1 && $FF -loglevel error -y -framerate $3 -i $1/$2-%02d.png -vf "scale=1600:-2,fps=30" -c:v libx264 -pix_fmt yuv420p -an -movflags +faststart $1/$2.mp4; }

say "batch 9 at $(git -C $R log --oneline -1 | cut -c1-70)"
# 0. The import step: Meshy's pieces through Blender (realm/tools/meshy_import.sh), then one headless Godot import
# pass so every new or changed asset loads (only while no other Godot runs: this batch waits for it).
for i in {1..120}; do pgrep -f "godot --path" > /dev/null || break; say "import: a Godot is running; waiting"; sleep 15; done
$R/realm/tools/meshy_import.sh 2>&1 | grep "^MESHY" | tee -a $LOG | cut -c1-120
arch -arm64 godot --headless --path $R/realm --import > $OUT/import.log 2>&1
say "import done: $(grep -c 'ERROR' $OUT/import.log) errors in its log"
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
r=$(curl -s -m 30 -X POST $API/chronicles -d '{"name":"Film batch 9","scenario":"aldmere","minutes":60,"wealth":"comfortable","options":{}}')
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
owner_of() { curl -s -m 8 $API/world | python3 -I -c "import json,sys; print(next((c.get('owner',-1) for c in json.load(sys.stdin)['cities'] if c['id']==$1), -1))"; }
stage() { curl -s -m 10 -X POST -H "X-Test: 1" $API/test/stage -d "$1" | head -c 160; }
: > $OUT/notes.txt
note() { print -r -- "$1" >> $OUT/notes.txt; say "note: $1"; }

# 1-3. The distance ladder (#7): Kingsmere at the rig's own pitch, the old low tilts, Goldrock with a court due.
if want ladder; then
  {
    print "wait 30"
    for d in 6 10 16 30 50; do print "city Kingsmere $d"; print "wait 6"; print "snap kingsmere-$d"; done
    print "city Kingsmere 14 -22"; print "wait 6"; print "snap kingsmere-14-low"
    print "city Kingsmere 40 -20"; print "wait 6"; print "snap kingsmere-40-low"
    for d in 6 10 16 30; do print "city Goldrock $d"; print "wait 6"; print "snap goldrock-$d"; done
    print "look ladder-end"
  } > $OUT/ladder.play
  play ladder 480
fi

# 4-8. Settled frames and true clip gaps (#10, #15), film shots free of panels (#3): the forge snapped settled, a clip at 0.2 s, the same with its panels kept; the army still that caught the main menu.
if want settled; then
  {
    print "wait 30"
    print "work Kingsmere forge 4.5 -5"; print "snap forge"; burst forge-clip 24 0.2
    print "snap forge-ui ui"
    print "look settled-end"
  } > $OUT/settled.play
  play settled 360
  clip $OUT/settled forge-clip 5
  say "launch army line d12"
  LIMIT=420 GODOT_ARGS="$GODOT_ARGS_FILM" $R/realm/tools/render.sh $OUT/army-line-d12.png $B $SW ${=LM} --dist=12 --wait=90 --army-spike=6000 --army-shape=line >> $OUT/render.out 2>&1
  grep "^ARMY\|SHOT waiting" $OUT/army-line-d12.log | tail -3 >> $LOG
fi

# 9. Clarity before/after (#1): the same frames with --clarity=old, then as it is.
if want clarity; then
  for v in old new; do
    {
      print "wait 30"
      print "city Kingsmere 6 -25"; print "wait 6"; print "snap kingsmere-$v"
      print "city Goldrock 6 -25"; print "wait 6"; print "snap goldrock-$v"
      print "work Kingsmere forge 4.5 -5"; print "wait 4"; print "snap forge-$v"
      print "look clarity-$v-end"
    } > $OUT/clarity-$v.play
    if [ $v = old ]; then play clarity-$v 300 --clarity=old; else play clarity-$v 300; fi
  done
fi

# 10. A sack burns where it's seen (#2): the sacked town framed, the sack staged, snaps at +6, +20, +45, +90 s and a clip from +8 s.
if want fire; then
  {
    print "wait 30"
    print "city $SACK 6 -25"; print "wait 6"; print "snap fire-before"
    print "look sack-now"; print "wait 6"; print "snap fire-06s"
    print "wait 2"; burst fire-clip 30 0.2
    print "wait 6"; print "snap fire-20s"
    print "wait 25"; print "snap fire-45s"
    print "wait 45"; print "snap fire-90s"
    print "look fire-end"
  } > $OUT/fire.play
  stage_on fire sack-now "{\"sack\":$SACKID}"
  play fire 480
  settle_stagers
  clip $OUT/fire fire-clip 5
  grep -c "fire.gd" $OUT/fire.log 2>/dev/null | sed 's/^/fire.gd errors: /' >> $LOG
fi

# 12-18. Batch 7's fixes: the bailey's campfire and drill (no orb, no pads), the feast's bonfire, the far mountains, field hedges, a watermill only on water.
if want fixes; then
  {
    print "wait 30"
    if has_step castle; then print "castle Kingsmere 4 -5"; else print "city Kingsmere 40"; fi
    print "wait 8"; print "snap bailey"
    print "city Kingsmere 30"; print "wait 6"; print "snap mountains"
    if has_step field; then print "field summer 0.3 0 9 -20"; else print "city Goldrock 16 -20"; fi
    print "wait 6"; print "snap hedges"
    if has_step work; then print "work Goldrock mill 5 -25"; print "wait 6"; print "snap goldrock-mill"; print "work $HUNGER mill 5 -25"; print "wait 6"; print "snap dry-mill"; fi
    print "look feast-now"; print "wait 14"
    print "city $SEAT 3.5 -5"; print "wait 6"; print "snap feast-bonfire"
    print "look fixes-end"
  } > $OUT/fixes.play
  stage_on fixes feast-now "{\"city\":$SEATID,\"mood\":\"feast\"}"
  play fixes 420
  settle_stagers
  stage "{\"city\":$SEATID,\"mood\":\"calm\"}" > /dev/null
fi

# 19-24. Meshy's pieces in place, before (--landmarks=kit) and after (--landmarks=meshy): the forge, the lumber mill, the treasury, the whole town. The catapult and guard tower show in the breach launch.
if want meshy; then
  for v in kit meshy; do
    {
      print "wait 30"
      print "work Kingsmere forge 4.5 -5"; print "wait 6"; print "snap forge-$v"
      print "work Goldrock mill 5 -25"; print "wait 6"; print "snap mill-$v"
      print "work Kingsmere guild 6 -25"; print "wait 6"; print "snap treasury-$v"
      print "city Kingsmere 14"; print "wait 6"; print "snap town-$v"
      print "look meshy-$v-end"
    } > $OUT/meshy-$v.play
    LM=--landmarks=$v play meshy-$v 360
  done
fi

# 25-32. The village and mood builder's fixes: stables and paddock (near and far), the levy marching out, war, hunger, the road, the inn, the mills.
if want village; then
  say "war: $(stage "{\"city\":$WARID,\"mood\":\"war\"}")  hunger: $(stage "{\"city\":$HUNGERID,\"mood\":\"hunger\"}")"
  {
    print "wait 30"
    print "work Kingsmere stables 4.5 -5"; print "wait 6"; burst stables-clip 24 0.2
    print "work Kingsmere stables 14 -22"; print "wait 4"; burst stables-far-clip 24 0.2
    print "city $WAR 6 -25"; print "wait 8"; print "snap war"
    print "city $HUNGER 6 -25"; print "wait 8"; print "snap hunger"
    print "road Kingsmere 5"; print "wait 6"; burst road-clip 28 0.2
    print "work Kingsmere inn 4.5 -5"; print "wait 6"; print "snap inn"
    print "work Kingsmere mill 5 -25"; print "wait 6"; burst mill-clip 30 0.2
    print "look muster-now"; print "wait 10"
    print "city Kingsmere 6 -25"; print "wait 4"; burst levy-clip 40 0.5
    print "road Kingsmere 5"; print "wait 2"; burst levy-road-clip 40 0.5
    print "look village-end"
  } > $OUT/village.play
  stage_on village muster-now "{\"muster\":$SEATID}"
  play village 600
  settle_stagers
  for c in stables-clip stables-far-clip road-clip mill-clip levy-clip levy-road-clip; do clip $OUT/village $c 5; done
  for c in $WARID $HUNGERID; do stage "{\"city\":$c,\"mood\":\"calm\"}" > /dev/null; done
fi

# The fountain and the crowd's clothes (batch 8 look2): both centrepieces close, the crowd at Kingsmere and in a smaller town.
if want fountain; then
  {
    print "wait 30"
    print "city Goldrock 3.5 -5"; print "wait 6"; print "snap goldrock-fountain"
    print "city Kingsmere 3.5 -5"; print "wait 6"; print "snap kingsmere-statue"
    print "city Kingsmere 6 -25"; print "wait 8"; print "snap kingsmere-crowd"
    print "city $LEVY 6 -25"; print "wait 8"; print "snap village-crowd"
    print "look fountain-end"
  } > $OUT/fountain.play
  play fountain 360
  say "crowd errors (villagers.gd) across launches: $(grep -c 'villagers.gd' $OUT/*.log 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
fi

# The UI finesse pass (docs/review/ui-pass.md): the same frames with --ui=v1, then --ui=v2.
if want ui; then
  for v in v1 v2; do
    {
      print "wait 30"
      print "city Kingsmere 10 -3"; print "hover 0.97 0.9"; print "wait 3"; print "snap ui-town-$v ui"
      print "tap chronicle"; print "wait 2"; print "snap ui-chronicle-$v ui"; print "tap chronicle"
      print "town Rosehall"; print "wait 3"; print "snap ui-towncard-$v ui"
      print "look ui-$v-end"
    } > $OUT/ui-$v.play
    play ui-$v 300 --ui=$v
  done
fi

# 35-37. The King's decisions in the world (--decisions=on): unrest at a cold house's seat, a feast's lanterns, the levy's table at Kingsmere.
if want decisions; then
  COLD=$(owner_of $WARID)
  say "cold house $COLD: $(stage "{\"favour\":{\"$COLD\":20}}")"
  {
    print "wait 30"
    print "city $WAR 10"; print "wait 8"; print "snap unrest"
    print "look feast-decree"; print "wait 2"
    print "city $SEAT 8 -25"; print "wait 2"; print "snap lanterns-2s"; print "wait 18"; print "snap lanterns-20s"
    print "look levy-decree"; print "wait 10"
    print "city Kingsmere 8"; print "wait 6"; print "snap levy-table"
    print "look decisions-end"
  } > $OUT/decisions.play
  stage_on decisions feast-decree "{\"city\":$SEATID,\"ruling\":\"feast\"}"
  stage_on decisions levy-decree "{\"city\":$SEATID,\"ruling\":\"levy\"}"
  play decisions 420 --decisions=on
  settle_stagers
  stage "{\"city\":$SEATID,\"ruling\":\"none\"}" > /dev/null; stage "{\"city\":$SEATID,\"mood\":\"calm\"}" > /dev/null
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
    if has_step engine; then print "engine 0 3.5 -5"; print "wait 14"; burst engine-clip 45 0.2; fi
    if has_step breach; then print "breach 4 -5"; else print "look breach-front"; fi
    burst stone-clip 40 0.2
    print "snap breach-cracked"
    print "wait 45"
    if has_step breach; then print "breach 3.5 -5"; fi
    print "snap breach"; burst breach-clip 30 0.2
    print "wait 4"; burst storm-clip 36 0.25
    print "wait 30"
    if has_step breach; then print "breach 3.5 -5"; fi
    print "snap storm-taken"
    print "wait 25"
    if has_step breach; then print "breach 7 -3"; fi
    print "snap storm-fire"
    print "look breach-end"
  } > $OUT/breach.play
  play breach 720 --walls=stone --siege --wall-demo
  for c in engine-clip stone-clip breach-clip storm-clip; do clip $OUT/breach $c 5; done
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


# 40. The field battle in play (army-ui's field_battle.gd): Space to the latest news once the reign has had a fight.
if want battle; then
  # A battle in play (army-ui's 5a47b648, --battles=field): where the bridge reports a battle, one is staged
  # on open ground there, sized from the men who fought. It never moves the camera: Space jumps to the latest
  # news. Only shows a battle if this reign has had one by now; play.log and the frame say what it found.
  { print "wait 60"; print "key Space"; print "wait 5"; print "snap battle-in-play"; print "look battle-play-end"; } > $OUT/battle-play.play
  play battle-play 300 --battles=field
fi

# 41-48. The realm's sound v2 (--sound=v2), recorded with each clip (--record-audio): the square near and far, the yard and paddock, the mills, a levy, dawn and night. The sack, the siege and the court are heard in their own launches when those run with --sound=v2.
if want sound; then
  {
    print "wait 30"
    print "city Kingsmere 4.5 -5"; print "wait 10"; print "snap sound-square-near"
    print "city Kingsmere 14"; print "wait 8"; print "snap sound-square-14"
    print "city Kingsmere 40"; print "wait 8"; print "snap sound-square-40"
    print "work Kingsmere barn 4.5 -5"; print "wait 10"; print "snap sound-yard"
    print "work Kingsmere stables 4.5 -5"; print "wait 10"; print "snap sound-paddock"
    print "work Kingsmere mill 5 -25"; print "wait 10"; print "snap sound-mill"
    print "look sound-muster"; print "wait 10"
    print "road Kingsmere 5"; print "wait 15"; print "snap sound-levy"
    print "look sound-end"
  } > $OUT/sound.play
  stage_on sound sound-muster "{\"muster\":$SEATID}"
  GODOT_ARGS="" play sound 420 --sound=v2 --record-audio=$OUT/sound.wav
  settle_stagers
  for h in 5.5 23; do
    { print "wait 30"; print "city Kingsmere 6 -25"; print "wait 15"; print "snap sound-hour-$h"; print "look sound-hour-$h-end"; } > $OUT/sound-hour-$h.play
    GODOT_ARGS="" play sound-hour-$h 240 --sound=v2 --hour=$h --record-audio=$OUT/sound-hour-$h.wav
  done
fi

# What came out, and onto the review page's folder.
say "frames:"
python3 -I $R/docs/review/v17_apply.py $OUT --check | tee -a $LOG
python3 -I $R/docs/review/v17_apply.py $OUT | tee -a $LOG
say "batch 9 done. Stills, clips, sound and logs: $OUT. Publish list: $R/docs/review/v17-publish.json"
