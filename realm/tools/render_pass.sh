#!/bin/zsh
# The one render pass (top supervisor, 2026-11-12: no GPU or windowed runs until the look audit says every new asset is
# in; then ONE pass, off Mac's screen). Every frame the game is judged on, each beside its art target, in one folder.
#
#   realm/tools/render_pass.sh                 # frames, logs and side-by-sides in /tmp/goc-pass/<HHMM>/
#   OUT=/tmp/goc-pass/x realm/tools/render_pass.sh
#   ONLY="town muster" realm/tools/render_pass.sh   # just these frames (names below)
#
# Refuses while /tmp/goc-no-render exists (Mac's stop: `touch /tmp/goc-no-render`), while another windowed Godot is up
# (Mac's game, or another render), or while its ports are taken.
#
# Off-screen: every Godot window opens at --position 10000,10000 (off any display) with the project's
# display/window/size/no_focus set in the pass's own copy, so it never comes to the front or takes a click.
# Risk, untested on this Mac: macOS may stop drawing a window it thinks is off the desktop (render.sh retries a take that
# stalls on 'timeout waiting for fence'), or pull it back on screen. If the first frames stall, run with another OFF
# (engine flags, e.g. OFF="--audio-driver Dummy --position 0,2000" for a second display) and say so to the supervisor.
# Its own copy of the game: HEAD's code (git archive) in $OUT/tree, its realm/assets and realm/.godot linked to the
# shared tree's by tools/link_assets.sh (the one source of art, gitignored local files included, and its import cache),
# then a check-only of main.gd (it stops if HEAD doesn't compile). ASSETS.txt records the code commit and the art's
# state (a hash of realm/assets/armies, the art's newest file).
# One private bridge (8789, Freeciv 5558; PORT and FC to change) started fresh from that copy, so /world carries what
# HEAD's bridge sends (units' men: a1e42ae0); the pass checks it before the first frame and stops the bridge at the end.
#
# Frames (name: what, target, READY line):
#   town     the town view you start with, Kingsmere's square (01-town; READY 1, art step 6)
#   landuse  Kingsmere and the land round it, the town view drawn back (01-town; One store's land use)
#   realm    the realm map, standards and flags (02-realm; READY 3, 9)
#   muster   war's host forming and marching out along the road (03-army; READY 3, 4)
#   cavalry  a house-coloured host in line, close (03-army; READY 4, the Meshy army set)
#   battle   two hosts meet, then the rout runs along the line (03-army; READY 5)
#   siege    the siege taken: breach, storm, the town changing hands (04-siege; READY 6, 7)
#   command  a host in open ground clicked by its standard, then Besiege (03-army for the field; READY 8)
#   face     the same host given a line by a right drag (its own reign: one order a season a host; READY 8)
#   castle   Kingsmere's castle close from its gate side (01-town; the Meshy castle set)
#   street   the smallest town's street of houses at its town view (01-town; the Meshy house set)
#   crossing a ship at sea carrying a host, the cog (08-reinforce); skipped, and said, when no ship is at sea
set -u
R=$(cd "$(dirname "$0")/../.." && pwd)
STAMP=$(date +%H%M)
OUT=${OUT:-/tmp/goc-pass/$STAMP}
PORT=${PORT:-8789}; FC=${FC:-5558}
API=localhost:$PORT
ONLY=${ONLY:-"town landuse realm muster cavalry battle siege command face castle street crossing"}
TARGETS=$R/docs/art/target
say() { echo "$(date +%T) $*" | tee -a $OUT/pass.log; }

# --- the stops --------------------------------------------------------------------------------------------------------
[ -e /tmp/goc-no-render ] && { echo "render_pass: /tmp/goc-no-render is there (Mac's stop); nothing run"; exit 2; }
if pgrep -fl "^(arch -arm64 )?godot( |$)" | grep -v -e "--headless" | grep -q .; then
  echo "render_pass: a windowed Godot is up (Mac's game or another render); nothing run"; exit 2
fi
for p in $PORT $FC; do lsof -iTCP:$p -sTCP:LISTEN > /dev/null 2>&1 && { echo "render_pass: port $p is taken; set PORT and FC"; exit 2; }; done
mkdir -p $OUT/side $OUT/frames
say "render pass into $OUT at $(git -C $R log --oneline -1 | cut -c1-90)"

# --- the pass's own copy of the game ----------------------------------------------------------------------------------
F=$OUT/tree
rm -rf $F; mkdir -p $F
git -C $R archive HEAD realm bridge docs/art | tar -x -C $F
# The shared tree's art and its import cache, linked (One store's link_assets.sh, 67077a0f): the copy draws exactly what
# the shared tree draws and imports nothing of its own. (No copy of .godot after it: the link is the shared cache, and a
# copy onto it would nest 7 GB inside the shared tree.)
zsh $R/realm/tools/link_assets.sh $F >> $OUT/pass.log || { say "link_assets.sh failed"; exit 3; }
[ -L $F/realm/assets ] && [ -L $F/realm/.godot ] || { say "link_assets.sh left no links"; exit 3; }
# Off-screen and never focused: the copy's project only.
python3 -I - "$F/realm/project.godot" <<'EOF'
import sys, re
p = sys.argv[1]; s = open(p).read()
line = "window/size/no_focus=true"
if "[display]" in s:
    s = s.replace("[display]\n", "[display]\n\n" + line + "\n", 1)
else:
    s += "\n[display]\n\n" + line + "\n"
open(p, "w").write(s)
EOF
( cd $F/realm && perl -e 'alarm shift; exec @ARGV' 300 arch -arm64 godot --headless --check-only --path . -s scripts/main.gd > $OUT/check.log 2>&1 )
grep -q "SCRIPT ERROR\|Parse Error" $OUT/check.log && { say "check-only: HEAD's main.gd does not compile (see check.log); nothing rendered"; exit 3; }
{
  echo "code: $(git -C $R rev-parse --short HEAD) (git archive)"
  echo "art: realm/assets -> $(readlink $F/realm/assets), import cache -> $(readlink $F/realm/.godot), at $(date '+%F %T')"
  echo "armies hash: $(cd $R/realm/assets/armies && find . -type f -not -name '*.blend*' | sort | xargs md5 -q | md5 -q)"
  echo "newest art file: $(cd $R/realm/assets && find . -type f -not -name '*.import' -print0 | xargs -0 stat -f '%m %N' | sort -n | tail -1 | cut -d' ' -f2-)"
} > $OUT/ASSETS.txt
say "copy ready: $(head -1 $OUT/ASSETS.txt)"

# --- one private bridge, fresh ----------------------------------------------------------------------------------------
H=$OUT/home; rm -rf $H; mkdir -p $H
( cd $F/bridge && PORT=$PORT FC_PORT=$FC GOC_HOME=$H nice -n 5 node server.js > $OUT/bridge.log 2>&1 ) &
cleanup() { P=$(lsof -tiTCP:$PORT -sTCP:LISTEN); [ -n "$P" ] && kill $P; sleep 2; pkill -f "freeciv-server -p $FC "; say "bridge stopped"; }
trap cleanup EXIT
trap "exit 1" TERM INT
for i in {1..60}; do curl -s -m 3 -o /dev/null "$API/world?peek=1" && break; sleep 1; done
new_reign() {  # a fresh reign "Render pass": its own season, so each take's one order a season is its own
  local r=$(curl -s -m 30 -X POST $API/chronicles -d '{"name":"Render pass","scenario":"aldmere","minutes":60,"wealth":"comfortable","options":{}}')
  local id=$(print -r -- "$r" | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
  [ -n "$id" ] || { say "the reign wasn't made: $(print -r -- $r | head -c 200)"; return 1; }
  for i in {1..40}; do curl -s -m 5 $API/chronicles | grep -q "\"active\":\"$id\"" && break; sleep 2; done
  for i in {1..60}; do curl -s -m 5 $API/world | python3 -I -c "import json,sys; sys.exit(0 if len(json.load(sys.stdin).get('cities',[]))>5 else 1)" 2>/dev/null && break; sleep 3; done
  curl -s -m 5 -o /dev/null -X POST $API/court/close
  say "reign $id is up"
}
new_reign || exit 3
W=$(curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; d=json.load(sys.stdin); u=d.get('units',[])
print(len(d.get('players',[])), len(d.get('cities',[])), len(u), sum(1 for x in u if 'men' in x))" 2>/dev/null)
set -- ${=W}
if [ -z "$W" ] || [ "${1:-0}" -lt 2 ] || [ "${2:-0}" -lt 6 ]; then say "ABORT: empty realm (players/cities: ${W:-none})"; exit 3; fi
if [ "${3:-0}" -gt 0 ] && [ "${4:-0}" -lt "${3:-0}" ]; then say "ABORT: /world units carry no men (${4:-0} of ${3:-0}): the bridge is not HEAD's"; exit 3; fi
say "realm ok: players $1, cities $2, units $3 with men $4"

# --- frames -----------------------------------------------------------------------------------------------------------
SW=(--look=one --trees=kit --ground=painted --wear=on --team=on --politics=on --castles=kit --houses=kit --towns=plots --fire=v2 --roadside=on --ui=v2 --dressing=on --castle-life=on --weather=v2 --landmarks=meshy)
B=(--bridge=http://127.0.0.1:$PORT)
OFF=${OFF:-"--audio-driver Dummy --position 10000,10000"}  # engine flags for every window: off any display
export RES=1920x1080
want() { [[ " $ONLY " == *" $1 "* ]]; }
# shot <name> <limit s> <fps: still|film> <args...>: a still (--wait) or a played take (--play=$OUT/<name>.play)
shot() {
  local n=$1 limit=$2 kind=$3; shift 3
  local ga="$OFF"; [ $kind = film ] && ga="$OFF --fixed-fps 24"
  local play=(); [ -f $OUT/$n.play ] && play=(--play=$OUT/$n.play --out=$OUT/frames/$n)
  LIMIT=$limit GODOT_ARGS="$ga" $F/realm/tools/render.sh $OUT/frames/$n.png $B "$@" $play > $OUT/$n.out 2>&1
  say "$n: $(tail -1 $OUT/$n.out); $(/bin/ls $OUT/frames/$n 2>/dev/null | grep -c png) frames, $(grep -c 'SCRIPT ERROR' $OUT/frames/$n.log 2>/dev/null) script errors"
}
# side <name> <frame png> <target jpg> [note]: the frame beside its target, one picture in $OUT/side
side() {
  local n=$1 f=$2 t=$3
  [ -f "$f" ] || { say "side $n: no frame ($f)"; return; }
  ffmpeg -loglevel error -y -i $t -i $f -filter_complex "[0]scale=960:540[a];[1]scale=960:540[b];[a][b]hstack" -q:v 3 $OUT/side/$n.jpg \
    && echo "| $n | $(basename $t) | side/$n.jpg | ${4:-} |" >> $OUT/side/INDEX.md
}
echo "| frame | target | side-by-side | log |" > $OUT/side/INDEX.md
echo "|---|---|---|---|" >> $OUT/side/INDEX.md

if want town; then
  { print "wait 30"; print "home Kingsmere"; print "wait 6"; print "home Kingsmere"; print "wait 3"; print "snap hero"; print "snap hero_ui ui"
    print "hold cam_turn_left 0.6"; print "wait 2"; print "snap left"; print "look end"; } > $OUT/town.play
  shot town 1500 film $SW
  side town $OUT/frames/town/hero.png $TARGETS/01-town.jpg "READY 1, art step 6"
fi
if want landuse; then
  { print "wait 30"; print "home Kingsmere 0 4"; print "wait 6"; print "home Kingsmere 0 4"; print "wait 3"; print "snap land"; print "look end"; } > $OUT/landuse.play
  shot landuse 1500 film $SW
  side landuse $OUT/frames/landuse/land.png $TARGETS/01-town.jpg "land use round the town"
fi
if want realm; then
  { print "wait 30"; print "home Kingsmere 0 26"; print "wait 8"; print "snap realm"; print "snap realm_ui ui"; print "look end"; } > $OUT/realm.play
  shot realm 1500 film $SW
  side realm $OUT/frames/realm/realm_ui.png $TARGETS/02-realm.jpg "READY 3, 9: standards and flags"
fi
if want muster; then
  { print "muster formed 150"; print "snap formed"; print "muster out 150"
    for i in $(seq -f "%02g" 1 20); do print "snap m$i"; print "wait 1.5"; done
    print "muster halted 150"; print "snap halted"; print "look end"; } > $OUT/muster.play
  shot muster 2400 film $SW --muster --dist=9 --lead=2
  side muster $OUT/frames/muster/m10.png $TARGETS/03-army.jpg "READY 3: $(grep -h 'muster:' $OUT/frames/muster/play.log 2>/dev/null | tr '\n' ' ')"
fi
if want cavalry; then
  shot cavalry 900 still $SW --army-spike=600 --army-colours=houses --army-shape=line --dist=2.4 --wait=40
  side cavalry $OUT/frames/cavalry.png $TARGETS/03-army.jpg "READY 4, army_colour_probe"
fi
if want battle; then
  { print "wait 20"; print "clash 150"; print "snap meet"; print "rout 150"
    for i in $(seq -f "%02g" 1 16); do print "snap r$i"; print "wait 1"; done; print "look end"; } > $OUT/battle.play
  shot battle 2400 film --army-battle=600:foe --probe
  side battle $OUT/frames/battle/meet.png $TARGETS/03-army.jpg "READY 5: $(grep -c 'breaks at' $OUT/frames/battle.log 2>/dev/null) breaks"
  side battle_rout $OUT/frames/battle/r08.png $TARGETS/03-army.jpg "READY 5: the rout along the line"
fi
if want siege; then
  { print "wait 20"; print "breach 3 -25"; print "wait 1"
    for i in $(seq -f "%02g" 1 30); do print "snap s$i"; print "wait 1"; done; print "look end"; } > $OUT/siege.play
  shot siege 2400 film --siege=taken --wall-demo --probe
  side siege $OUT/frames/siege/s10.png $TARGETS/04-siege.jpg "READY 6: the breach and storm"
  side siege_taken $OUT/frames/siege/s30.png $TARGETS/04-siege.jpg "READY 7: $(grep -ciE 'taken|changes hands' $OUT/frames/siege.log 2>/dev/null) taken lines"
fi
# READY 8: the host in the most open ground (the farthest from any town), so its men show, not a glow among houses.
open_host() {
  curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; d=json.load(sys.stdin); hs=d.get('hosts',[]); cs=d.get('cities',[])
if not hs: print(0); sys.exit()
far=lambda h: min(((h['x']-c['x'])**2+(h['y']-c['y'])**2) for c in cs) if cs else 0
print(max(range(len(hs)), key=lambda i: far(hs[i])))" 2>/dev/null || echo 0
}
if want command; then
  N=$(open_host)
  { print "wait 30"; print "host $N 6 -25"; print "wait 3"; print "snap selected ui"; print "order besiege"; print "wait 2"; print "snap ordered ui"
    print "wait 6"; print "snap marching ui"; print "look end"; } > $OUT/command.play
  shot command 1500 film $SW
  side command $OUT/frames/command/ordered.png $TARGETS/03-army.jpg "READY 8: $(grep -hE 'host selected|order besiege' $OUT/frames/command/play.log 2>/dev/null | head -2 | tr '\n' ' ')"
fi
if want face; then
  new_reign  # a new season of orders: Besiege above spent this host's one (bridge/data/hosts.json ordersPerHost)
  N=$(open_host)
  { print "wait 30"; print "host $N 6 -25"; print "wait 3"; print "rdrag 0.40 0.62 0.70 0.62"; print "snap faced ui"; print "wait 6"; print "snap formed ui"; print "look end"; } > $OUT/face.play
  shot face 1500 film $SW
  side face $OUT/frames/face/faced.png $TARGETS/03-army.jpg "READY 8: $(grep -hE 'host selected' $OUT/frames/face/play.log 2>/dev/null | head -1)"
fi
# The rest of the look, each beside its target: the castle from its gate, a village street, a host crossing the sea.
world_pick() {  # world_pick village|ship: the smallest town's name, or a ship's unit id (MapLook.SHIPS), from /world
  curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; d=json.load(sys.stdin); want=sys.argv[1]
if want=='village':
    cs=sorted(d.get('cities',[]), key=lambda c: c.get('size',0)); print(cs[0].get('title', cs[0].get('name','')) if cs else '')
else:
    ships={'Trireme','Caravel','Galleon','Frigate','Transport'}
    us=[u for u in d.get('units',[]) if u.get('type') in ships]; print(us[0]['id'] if us else '')" "$1" 2>/dev/null
}
if want castle; then
  { print "wait 30"; print "castle Kingsmere 4 -20 gate"; print "wait 4"; print "snap castle"; print "look end"; } > $OUT/castle.play
  shot castle 1500 film $SW
  side castle $OUT/frames/castle/castle.png $TARGETS/01-town.jpg "the castle from its gate (the Meshy castle set)"
fi
if want street; then
  V=$(world_pick village)
  { print "wait 30"; print "home ${V:-Kingsmere} 0 1"; print "wait 6"; print "home ${V:-Kingsmere} 0 1"; print "wait 3"; print "snap street"; print "look end"; } > $OUT/street.play
  shot street 1500 film $SW
  side street $OUT/frames/street/street.png $TARGETS/01-town.jpg "a village street: ${V:-none found, Kingsmere}"
fi
if want crossing; then
  SHIP=$(world_pick ship)
  if [ -z "$SHIP" ]; then
    say "crossing: no ship at sea in this reign; no frame (the crossing needs a host ordered over water)"
  else
    { print "wait 30"; print "unit $SHIP 3"; print "wait 4"; print "snap crossing"; print "look end"; } > $OUT/crossing.play
    shot crossing 1500 film $SW
    side crossing $OUT/frames/crossing/crossing.png $TARGETS/08-reinforce.jpg "a host at sea in its cog (unit $SHIP)"
  fi
fi
say "render pass done: $OUT/side/INDEX.md"
exit 0
