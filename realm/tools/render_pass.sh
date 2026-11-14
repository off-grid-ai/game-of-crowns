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
#   midzoom  the map's middle zoom over Kingsmere at d25 and d40, beside 02-realm
#   muster   war's host forming and marching out along the road (03-army; READY 3, 4)
#   cavalry  a house-coloured host in line, close (03-army; READY 4, the Meshy army set)
#   battle   two hosts meet, then the rout runs along the line (03-army; READY 5)
#   siege    the siege taken: breach, storm, the town changing hands (04-siege; READY 6, 7)
#   court    the court's card over Kingsmere's square, answered, and its ruling in the town (05-court)
#   inn      the first roadside inn out from the seat, close and drawn back (06-inn)
#   sack     Kingsmere sacked: burning, then its burnt shells smouldering in the burnt ring (04-siege's town)
#   command  a host in open ground clicked by its standard, then Besiege (03-army for the field; READY 8)
#   face     the same host given a line by a right drag (its own reign: one order a season a host; READY 8)
#   walls    Kingsmere's walls whole, from outside and low (01-town)
#   breach   a breached section beside whole ones (--siege --wall-demo, no storm; 04-siege)
#   winter   Kingsmere under snow at the town view and drawn back (ground, roofs, leaves; the tracks through it)
#   seasons  the wood's edge and the fields in summer and in autumn (the nature set's seasonal leaves; 01-town)
#   host5    the host in column at 03-army's framing with all five kinds, 1500 men in the crown's colours (03-army)
#   castle   Kingsmere's castle close from its gate side (01-town; the Meshy castle set)
#   street   the smallest town's street of houses at its town view (01-town; the Meshy house set)
#   cities   a coastal, a small and a hill town at the town view, for their edge cases (01-town; picked off /map)
#   crossing the King's host at sea in the cog (08-reinforce): ordered over water (One store's crossing, d70ca994), then
#            framed once aboard, the reign paused while it is filmed (CROSS_WAIT, 900 s of the wall clock); skipped and
#            said when no march goes by sea
#   raid     men without banners at the crown's richest town, then one walking off to wild land (Wealth draws the raid;
#            03-army for the field): staged (bridge /test/stage {raid}), framed at the town (RAID_WAIT, 300 s) and again
#            once one is on the road out after the raid's seasons (RAID_LEAVE, 1200 s); each skipped and said on time-out
set -u
R=${RENDER_PASS_R:-$(cd "$(dirname "$0")/../.." && pwd)}  # the shared tree (its copy in $OUT inherits it)
STAMP=$(date +%H%M)
OUT=${OUT:-/tmp/goc-pass/$STAMP}
PORT=${PORT:-8789}; FC=${FC:-5558}
API=localhost:$PORT
ONLY=${ONLY:-"town landuse realm midzoom muster cavalry battle siege command face walls breach seasons winter host5 castle street cities court inn sack crossing raid"}
# The pass runs from its own copy of this script: zsh reads a script as it runs, so a commit to it mid-pass broke the
# first full pass (2159: 'parse error near fi' at line 229, ten lines added above it at 22:00 while it ran).
if [ -z "${RENDER_PASS_SELF:-}" ]; then
  mkdir -p $OUT
  cp "$0" $OUT/render_pass.sh
  RENDER_PASS_SELF=1 RENDER_PASS_R=$R OUT=$OUT exec zsh $OUT/render_pass.sh "$@"
fi
TARGETS=$R/docs/art/target
say() { echo "$(date +%T) $*" | tee -a $OUT/pass.log; }

# --- the stops --------------------------------------------------------------------------------------------------------
[ -e /tmp/goc-no-render ] && { echo "render_pass: /tmp/goc-no-render is there (Mac's stop); nothing run"; exit 2; }
if pgrep -fl "^(arch -arm64 )?godot( |$)" | grep -v -e "--headless" | grep -q .; then
  echo "render_pass: a windowed Godot is up (Mac's game or another render); nothing run"; exit 2
fi
for p in $PORT $FC; do lsof -iTCP:$p -sTCP:LISTEN > /dev/null 2>&1 && { echo "render_pass: port $p is taken; set PORT and FC"; exit 2; }; done
# Room on the disk: a pass writes a few GB of frames, and a full disk cut the first pass short (21:52, 'No space left on
# device' while the second copied the game). DISK_MIN GB free at the start (15).
FREE=$(df -g "$R" 2>/dev/null | awk 'NR==2 {print $4}')
[ -n "$FREE" ] && [ "$FREE" -lt ${DISK_MIN:-15} ] && { echo "render_pass: ${FREE} GB free on the disk (at least ${DISK_MIN:-15}); nothing run"; exit 2; }
mkdir -p $OUT/side $OUT/frames
say "render pass into $OUT at $(git -C $R log --oneline -1 | cut -c1-90)"

# --- the pass's own copy of the game ----------------------------------------------------------------------------------
F=$OUT/tree
rm -rf $F; mkdir -p $F
# One commit, read once: the copy is that commit and ASSETS.txt names it (g1 archived HEAD at 11:47 and read HEAD
# again at 11:49, after 194107ec landed, so it named a commit it hadn't drawn).
CODE=$(git -C $R rev-parse --short HEAD)
git -C $R archive $CODE realm bridge docs/art | tar -x -C $F
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
  echo "code: $CODE (git archive)"
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
new_reign() {  # a fresh reign "Render pass film": its own season, so each take's one order a season is its own; a film
  # reign (bridge chronicles.isTest) keeps the baseline's dice, so passes repeat, shows no reign name by the clock, and
  # answers the bridge's test hooks (routes_test.js: the raid frame's raid)
  local r=$(curl -s -m 30 -X POST $API/chronicles -d '{"name":"Render pass film","scenario":"aldmere","minutes":60,"wealth":"comfortable","options":{}}')
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
  # A played take saves its own frames and never the --shot still, so render.sh's 'MISSING <name>.png' is its normal end
  # (and Godot's 'recursive_mutex' abort on quit comes after the take's 'done'): its frames and 'done' are what count.
  if [ ${#play} -gt 0 ]; then
    say "$n: $(/bin/ls $OUT/frames/$n 2>/dev/null | grep -c png) frames, $(grep -c 'SCRIPT ERROR' $OUT/frames/$n.log 2>/dev/null) script errors, play $(grep -q ' done$' $OUT/frames/$n/play.log 2>/dev/null && echo done || echo 'cut short')"
  else
    say "$n: $(tail -1 $OUT/$n.out); $(grep -c 'SCRIPT ERROR' $OUT/frames/$n.log 2>/dev/null) script errors"
  fi
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
    print "hold cam_turn_left 0.6"; print "wait 2"; print "snap left"; print "home Kingsmere"; print "wait 4"
    print "squarelife Kingsmere 60"; print "look end"; } > $OUT/town.play
  shot town 2100 film $SW
  # The square's life against 01-town's (towns.json square.targets): the crowd measured on the square the film builds
  # (a headless run builds Kingsmere a 163 m2 square, the film's 1154 m2: only the pass can measure it).
  side town $OUT/frames/town/hero.png $TARGETS/01-town.jpg "READY 1, art step 6; $(grep -h 'CHECK square life' $OUT/frames/town/play.log 2>/dev/null | sed 's/.*open setts: //' | cut -c1-160)"
fi
if want landuse; then
  { print "wait 30"; print "home Kingsmere 0 4"; print "wait 6"; print "home Kingsmere 0 4"; print "wait 3"; print "snap land"; print "look end"; } > $OUT/landuse.play
  shot landuse 1500 film $SW
  side landuse $OUT/frames/landuse/land.png $TARGETS/01-town.jpg "land use round the town"
fi
if want realm; then
  { print "wait 30"; print "tile 33 74 60 3.14";  # 02-realm: several houses' lands with mountains and the sea: from the north over Stormwatch (47,69) toward Sunspire (42,85) and Rosehall's south, the Belia mountains about (26,80) (bridge/lua/world_setup_azgaar.lua seats; g4: the Kingsmere-Highfell frame was mostly sea and low isles)
   print "wait 8"; print "snap realm"; print "snap realm_ui ui"; print "look end"; } > $OUT/realm.play
  shot realm 1500 film $SW
  side realm $OUT/frames/realm/realm_ui.png $TARGETS/02-realm.jpg "READY 3, 9: standards and flags"
fi
# The map's middle zoom, between the town drawn back (d9.6) and the realm (d60, the atlas from 54): Kingsmere and the
# land round it at d25 and d40, the political map, names and hosts as they read there (Look, PLAN.md section 4).
if want midzoom; then
  { print "wait 30"; print "city Kingsmere 25 7"; print "wait 6"; print "city Kingsmere 25 7"; print "wait 3"; print "snap d25 ui"
    print "city Kingsmere 40 9"; print "wait 6"; print "snap d40 ui"; print "look end"; } > $OUT/midzoom.play
  shot midzoom 1500 film $SW
  side midzoom $OUT/frames/midzoom/d25.png $TARGETS/02-realm.jpg "the middle zoom, d25 over Kingsmere"
  side midzoom_40 $OUT/frames/midzoom/d40.png $TARGETS/02-realm.jpg "the middle zoom, d40 over Kingsmere"
fi
if want muster; then
  { print "muster formed 150"; print "snap formed"; print "muster out 150"
    for i in $(seq -f "%02g" 1 20); do print "snap m$i"; print "wait 1.5"; done
    print "muster halted 150"; print "snap halted"; print "look end"; } > $OUT/muster.play
  shot muster 2400 film $SW --muster --dist=5 --lead=2  # 03-army: the column on the road fills the frame (g3: small at 9)
  side muster $OUT/frames/muster/m10.png $TARGETS/03-army.jpg "READY 3: $(grep -h 'muster:' $OUT/frames/muster/play.log 2>/dev/null | tr '\n' ' ')"
fi
if want cavalry; then
  shot cavalry 900 still $SW --army-spike=600 --army-colours=houses --army-shape=line --dist=2.4 --wait=40
  side cavalry $OUT/frames/cavalry.png $TARGETS/03-army.jpg "READY 4, army_colour_probe"
fi
if want battle; then
  { print "wait 20"; print "clash 150"; print "wait 4"; print "snap meet"; print "rout 150"
    for i in $(seq -f "%02g" 1 16); do print "snap r$i"; print "wait 1"; done; print "look end"; } > $OUT/battle.play
  shot battle 2400 film --army-battle=600:foe --probe --dist=5  # 03-army's distance (g15: the town view's 2.4 held one regiment)
  side battle $OUT/frames/battle/meet.png $TARGETS/03-army.jpg "READY 5: $(grep -c 'breaks at' $OUT/frames/battle.log 2>/dev/null) breaks"
  side battle_rout $OUT/frames/battle/r08.png $TARGETS/03-army.jpg "READY 5: the rout along the line"
fi
if want siege; then
  { print "wait 20"; print "breach"; print "wait 1"
    for i in $(seq -f "%02g" 1 30); do print "snap s$i"; print "wait 1"; done; print "look end"; } > $OUT/siege.play
  shot siege 2400 film --siege=taken --wall-demo --probe
  side siege $OUT/frames/siege/s10.png $TARGETS/04-siege.jpg "READY 6: the breach and storm"
  side siege_taken $OUT/frames/siege/s30.png $TARGETS/04-siege.jpg "READY 7: $(grep -ciE 'taken|changes hands' $OUT/frames/siege.log 2>/dev/null) taken lines"
fi
# READY 8: the host in the field in the most open ground (autoplay _open_host: fewest trees round it; g5's command
# frame took the one farthest from any town, and it stood under a forest's canopy), so its men show.
if want command; then
  { print "wait 30"; print "host open 6"; print "wait 3"; print "snap selected ui"; print "order besiege"; print "wait 2"; print "snap ordered ui"
    print "wait 6"; print "snap marching ui"; print "look end"; } > $OUT/command.play
  shot command 1500 film $SW
  side command $OUT/frames/command/ordered.png $TARGETS/03-army.jpg "READY 8: $(grep -hE 'host selected|order besiege' $OUT/frames/command/play.log 2>/dev/null | head -2 | tr '\n' ' ')"
fi
if want face; then
  new_reign  # a new season of orders: Besiege above spent this host's one (bridge/data/hosts.json ordersPerHost)
  { print "wait 30"; print "host open 6"; print "wait 3"; print "rdrag 0.40 0.62 0.70 0.62"; print "snap faced ui"; print "wait 6"; print "snap formed ui"; print "look end"; } > $OUT/face.play
  shot face 1500 film $SW
  side face $OUT/frames/face/faced.png $TARGETS/03-army.jpg "READY 8: $(grep -hE 'host selected' $OUT/frames/face/play.log 2>/dev/null | head -1)"
fi
# Kingsmere's walls whole, from outside and low (01-town's walls; walls.gd: the kit curtain where a section is whole).
if want walls; then
  { print "wait 30"; print "city Kingsmere 10 -12"; print "wait 6"; print "city Kingsmere 10 -12"; print "wait 3"; print "snap walls"; print "look end"; } > $OUT/walls.play
  shot walls 1500 film $SW
  side walls $OUT/frames/walls/walls.png $TARGETS/01-town.jpg "Kingsmere's walls whole"
fi
# A breached section beside whole ones (--wall-demo: a wall across a staged siege's front worn by its stones; no storm).
if want breach; then
  { print "wait 45"; print "breach"; print "wait 3"; print "snap breach"; print "look end"; } > $OUT/breach.play
  shot breach 1800 film --siege --wall-demo --probe
  side breach $OUT/frames/breach/breach.png $TARGETS/04-siege.jpg "a breached section beside whole ones"
fi
# The wood's edge and the fields in summer and in autumn (the nature set's seasonal leaves; autoplay field holds the
# countryside's year at that season and frames the crown's first sown field from over the wood: tilt 7 at d6 is about 38
# degrees down, eye about 30 m up; pass 2243's "6 -20" was 11 degrees, the lens among the tree crowns).
if want seasons; then
  for se in summer autumn; do
    { print "wait 30"; print "field $se 0.5 0 6 7"; print "wait 6"; print "snap $se"; print "look end"; } > $OUT/season_$se.play
    shot season_$se 1500 film $SW --season=$se
    side season_$se $OUT/frames/season_$se/$se.png $TARGETS/01-town.jpg "the wood's edge and the fields in $se"
  done
fi
# Winter on Kingsmere at the town view and drawn back (--season=winter): snow on the ground, the roofs and the leaves,
# the roads and paths as trodden lines through it (Look: snow passed; ground.json winter, snow.gdshader).
if want winter; then
  { print "wait 30"; print "home Kingsmere"; print "wait 6"; print "home Kingsmere"; print "wait 3"; print "snap town"
    print "home Kingsmere 0 4"; print "wait 6"; print "snap land"; print "look end"; } > $OUT/winter.play
  shot winter 1500 film $SW --season=winter
  side winter $OUT/frames/winter/town.png $TARGETS/01-town.jpg "winter on Kingsmere at the town view"
  side winter_land $OUT/frames/winter/land.png $TARGETS/01-town.jpg "winter round Kingsmere, drawn back"
fi
# The host at 03-army's framing with all five kinds (pikemen, men-at-arms, archers, knights, cavalry): army.json's
# shares (0.3, 0.25, 0.2, 0.1, 0.15) give every kind a regiment at about ten regiments, so 1500 men, in column on the
# road at a high oblique, in the crown's colours.
if want host5; then
  shot host5 900 still $SW --army-spike=1500 --army-colours=crown --army-shape=march --dist=5 --wait=50
  side host5 $OUT/frames/host5.png $TARGETS/03-army.jpg "all five kinds: $(grep -h 'ARMY mustered' $OUT/frames/host5.log 2>/dev/null | grep -o 'regiments=[0-9]* {[^}]*}' | head -1)"
fi
# The rest of the look, each beside its target: the castle from its gate, a village street, a host crossing the sea.
world_pick() {  # world_pick village: the smallest town's name, from /world
  curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; d=json.load(sys.stdin)
cs=sorted(d.get('cities',[]), key=lambda c: c.get('size',0)); print(cs[0].get('title', cs[0].get('name','')) if cs else '')" 2>/dev/null
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
# Other cities at the town view, for their edge cases (Look, PLAN.md section 4): the coastal town with the most sea in its
# ring, the smallest town after the street's, and the town with the most hills and mountains in its ring (the bridge's
# /map tiles; a town named in two words is passed over, the play's steps split on spaces).
if want cities; then
  PICKS=$(curl -s -m 10 "$API/map" | perl -e 'alarm shift; exec @ARGV' 30 python3 -I -c "
import json,sys,urllib.request
m=json.load(sys.stdin)
T={(t[0],t[1]):t[2].split('|')[0] for t in m.get('tiles',[])}
d=json.load(urllib.request.urlopen('http://$API/world?peek=1', timeout=10))
cs=[c for c in d.get('cities',[]) if ' ' not in c.get('title', c.get('name','')) and c.get('title') != 'Kingsmere']
ring=lambda c,r: [T.get((c['x']+i,c['y']+j),'Ocean') for i in range(-r,r+1) for j in range(-r,r+1)]
name=lambda c: c.get('title', c.get('name',''))
sea=max(cs, key=lambda c: (sum(k in ('Ocean','Deep Ocean','Lake') for k in ring(c,1)), -c.get('size',0)))
small=sorted(cs, key=lambda c: c.get('size',0))[1:2] or cs[:1]
hill=max(cs, key=lambda c: sum(k in ('Hills','Mountains') for k in ring(c,2)))
print(name(sea), name(small[0]), name(hill))" 2>/dev/null)
  set -- ${=PICKS}
  if [ $# -lt 3 ]; then
    say "cities: no picks from /map and /world; no frames"
  else
    for pair in "coastal $1" "small $2" "hill $3"; do
      set -- ${=pair}
      { print "wait 30"; print "home $2"; print "wait 6"; print "home $2"; print "wait 3"; print "snap $1"; print "look end"; } > $OUT/city_$1.play
      shot city_$1 1500 film $SW
      side city_$1 $OUT/frames/city_$1/$1.png $TARGETS/01-town.jpg "a $1 town at the town view: $2"
    done
  fi
fi
# The court (05-court: a ruling's card, then its result playing out in the town): the court sat now (POST /test/court
# sit), the card framed over Kingsmere's square, answered, and the town 12 s later. Before the sack: the seat whole.
if want court; then
  curl -s -m 20 -o /dev/null -X POST -H 'X-Test: 1' $API/test/court -d '{"sit":true}'
  { print "wait 30"; print "home Kingsmere"; print "wait 6"; print "home Kingsmere"; print "wait 3"; print "snap card ui"
    print "answer"; print "wait 12"; print "snap ruled ui"; print "look end"; } > $OUT/court.play
  shot court 1500 film $SW
  side court $OUT/frames/court/card.png $TARGETS/05-court.jpg "the court's card over the square: $(grep -h 'answered:' $OUT/frames/court/play.log 2>/dev/null | head -1)"
  side court_ruled $OUT/frames/court/ruled.png $TARGETS/05-court.jpg "the ruling playing out in the town"
fi
# The inn on the great road (06-inn: an inn, horses, soldiers at tables, a merchant, a shrine and a milestone): the
# roadside's first inn out from the seat (autoplay site, roadside.gd), framed low and close, then drawn back.
if want inn; then
  { print "wait 30"; print "site inn 0 3 -20"; print "wait 6"; print "site inn 0 3 -20"; print "wait 3"; print "snap inn"
    print "site inn 0 6 -10"; print "wait 6"; print "snap inn_road"; print "look end"; } > $OUT/inn.play
  shot inn 1500 film $SW
  side inn $OUT/frames/inn/inn.png $TARGETS/06-inn.jpg "the first inn on the road: $(grep -h 'site inn' $OUT/frames/inn/play.log 2>/dev/null | sed -n 2p)"
  side inn_road $OUT/frames/inn/inn_road.png $TARGETS/06-inn.jpg "the inn and its stretch of road"
fi
# A sacked town (Look, PLAN.md section 4; 04-siege's town beyond the breach): Kingsmere's burnt ring and its burnt share
# staged in the bridge (POST /test/mark sack, /test/stage damage burnt 0.4, as a sack leaves them: damage.json
# burntOnSack), then put to the torch in the film (autoplay burn), framed while it burns and once the flames are out
# (the shells charred and smouldering: fire.json char.smoulder). After every other frame of Kingsmere: the seat stays
# burnt for the rest of the pass.
if want sack; then
  SEAT=$(curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; d=json.load(sys.stdin)
c=[c for c in d.get('cities',[]) if c['id']==d.get('seatId')]
print(c[0]['id'], c[0]['x'], c[0]['y'], c[0].get('title', c[0].get('name',''))) if c and ' ' not in c[0].get('title','') else None" 2>/dev/null)
  set -- ${=SEAT}
  if [ $# -lt 4 ]; then
    say "sack: no seat in /world; no frame"
  else
    curl -s -m 10 -o /dev/null -X POST -H 'X-Test: 1' $API/test/mark -d "{\"kind\":\"sack\",\"x\":$2,\"y\":$3,\"age\":0}"
    curl -s -m 10 -o /dev/null -X POST -H 'X-Test: 1' $API/test/stage -d "{\"damage\":{\"city\":$1,\"burnt\":0.4}}"
    { print "wait 30"; print "home $4 0 2"; print "wait 6"; print "home $4 0 2"; print "burn $4 40"; print "wait 18"; print "snap sack"
      print "wait 70"; print "snap after"; print "look end"; } > $OUT/sack.play
    shot sack 1800 film $SW
    side sack $OUT/frames/sack/sack.png $TARGETS/04-siege.jpg "$4 sacked, burning"
    side sack_after $OUT/frames/sack/after.png $TARGETS/04-siege.jpg "$4 after the sack: burnt shells, smoulder, the burnt ring"
  fi
fi
if want crossing; then
  new_reign  # its own season of orders
  # The King's host takes ship (One store's crossing, d70ca994: a march with no road over land walks to the nearest crown
  # port, boards the crown's hulls, sails, lands near the goal). The pass asks each march dry first (d94c3c83: by land or
  # by sea, nothing given) for every host and town, orders the quickest by sea, then waits (CROSS_WAIT, 900 s of the wall clock:
  # a season at the shore while the crown raises its Triremes, 7b10e42d) until it is aboard, and frames its lead company on
  # the hull: the cog.
  # Every wait here is bounded (group test 2 hung 11 h in this block): the dry asks stop after CROSS_ASK s, each call
  # has its own timeout and the python under perl's alarm, and the whole wait for aboard ends at CROSS_WAIT s of the
  # wall clock, whatever happens inside it.
  CROSS=$(curl -s -m 10 "$API/world?peek=1" | perl -e 'alarm shift; exec @ARGV' ${CROSS_ASK:-300} python3 -I -c "
import json,sys,time,urllib.request
d=json.load(sys.stdin); hs=d.get('hosts',[]); cs=d.get('cities',[])
end=time.time()+${CROSS_ASK:-300}-20
def ask(body):
    req=urllib.request.Request('http://$API/host/order', data=json.dumps(body).encode(), method='POST')
    try:
        return json.load(urllib.request.urlopen(req, timeout=20))
    except Exception:
        return {}
# Every host to every town, asked dry (d94c3c83: by land or by sea, nothing given); the quickest march by sea is ordered.
best=None
for h in hs:
    for c in cs:
        if time.time()>end:
            break
        a=ask({'host':h['id'],'order':'march','city':c['id'],'dry':True})
        if a.get('by')=='sea' and (best is None or int(a.get('seasons',99))<best[0]):
            best=(int(a.get('seasons',99)), h, c)
if best:
    _, h, c = best
    r=ask({'host':h['id'],'order':'march','city':c['id']})
    if r.get('ok'):
        print(h['id'], c.get('title', c.get('name','')), r.get('text','')[:120])
" 2>/dev/null)
  set -- ${=CROSS}
  HID=${1:-}
  if [ -z "$HID" ]; then
    say "crossing: no march of the King's host went by sea (no town across the water, port or free hull); no frame"
  else
    say "crossing: host $HID ordered over water: ${CROSS#* }"
    # The realm only runs while a window watches it (bridge server.js 'away': a /world?peek=1 doesn't count), so this
    # wait reads /world as a window does; and, as the hasty King does, it closes the court and an interlude that would
    # hold the season. Pass g2 polled with peek: the reign stood at T39 with the host on the shore, one season short of
    # its ship, for 11 hours.
    LEAD=""; T0=$SECONDS
    while [ -z "$LEAD" ] && [ $((SECONDS - T0)) -lt ${CROSS_WAIT:-900} ]; do
      curl -s -m 5 -o /dev/null -X POST $API/court/close
      curl -s -m 5 -o /dev/null -X POST $API/interlude/close
      LEAD=$(curl -s -m 10 "$API/world" | perl -e 'alarm shift; exec @ARGV' 20 python3 -I -c "
import json,sys; d=json.load(sys.stdin)
me=[x for x in d.get('hosts',[]) if str(x.get('id'))=='$HID' and x.get('aboard')]
print(min(me[0].get('units',[me[0]['id']])) if me else '')" 2>/dev/null)
      [ -z "$LEAD" ] && sleep 5
    done
    if [ -z "$LEAD" ]; then
      say "crossing: host $HID not aboard in ${CROSS_WAIT:-900} s; no frame"
    else
      # Held while it is filmed (bridge POST /pause, as the King's own pause): the window watches the realm, so the
      # seasons ran on while Godot loaded and its first 30 s passed, and pass g9 framed the strait after the ships had
      # landed the host and put out to sea (empty water and a point of grass). Paused the season the host is aboard,
      # the lens finds its lead company on the hull, at the shore it embarked from or under way; let go after.
      curl -s -m 5 -o /dev/null -X POST $API/pause
      { print "wait 30"; print "unit $LEAD 3"; print "wait 4"; print "snap crossing"; print "unit $LEAD 1.5"; print "wait 3"; print "snap cog"; print "look end"; } > $OUT/crossing.play
      shot crossing 1500 film $SW
      curl -s -m 5 -o /dev/null -X POST $API/resume
      side crossing $OUT/frames/crossing/crossing.png $TARGETS/08-reinforce.jpg "the King's host at sea in the cog (host $HID, company $LEAD)"
      side crossing_cog $OUT/frames/crossing/cog.png $TARGETS/08-reinforce.jpg "the cog close"
    fi
  fi
fi
if want raid; then
  # Wealth draws the raid: men without banners fall on the crown's richest town (bridge routes_test.js {raid}, the town a
  # lord's hired raid picks: realm.js richestTown), pillage round it for the raid's seasons, then walk off to wild land
  # (realmrules/script.lua realm_raids_turn, fc9a094c). Raiders are units of a wild player (Freeciv's barbarians: /world
  # players[].house.wild; g22 read them as 'no player's' and found none by Saltkeep, where six stood) new since the stage. Every wait is bounded and reads /world (the realm runs
  # only while a window watches it), closing the court and an interlude as the crossing's wait does.
  raider() {  # raider <x> <y> <near|out|any> <from season>: "id x y yaw" for the raiders by the town (x y the middle of
    # their densest knot: g29's midpoint of two pairs two tiles apart was empty grass),
    # the farthest one 2+ tiles out once the raid's seasons are over, or any still living; '' when none. yaw: the lens
    # on their side of the town looking back at it (camera_rig: the lens sits along (sin yaw, cos yaw) from its aim),
    # so the raiders stand in front with the town behind them, not lost among its roofs (g24 raid.jpg). The men by the
    # town are this raid's (raid.ids); the walk-off and 'any' follow only them, not another raid's (g24 raid_leave.jpg
    # framed a wild raider at 46,69, far from Saltkeep)
    curl -s -m 10 "$API/world" | perl -e 'alarm shift; exec @ARGV' 20 python3 -I -c "
import json,sys; d=json.load(sys.stdin)
wild={p['id'] for p in d.get('players',[]) if (p.get('house') or {}).get('wild')}
old={int(x) for x in open('$OUT/raid.before').read().split()}
x,y=$1,$2
us=[u for u in d.get('units',[]) if u.get('owner') in wild and u['id'] not in old]
try:
    mine={int(i) for i in open('$OUT/raid.ids').read().split()}
except OSError:
    mine=None
if '$3'!='near' and mine is not None:
    us=[u for u in us if u['id'] in mine]
far=lambda u: max(abs(u['x']-x),abs(u['y']-y))
import math
if '$3'=='any':
    u=us[0] if us else None
elif '$3'=='near':
    us=[u for u in us if far(u)<=3]; u=None
    if us:
        # the densest knot: the man with most raiders within a tile of him (nearest the town on a tie), its middle
        knot=lambda a: [v for v in us if max(abs(v['x']-a['x']),abs(v['y']-a['y']))<=1]
        a=max(us,key=lambda a: (len(knot(a)),-far(a))); k=knot(a)
        u={'id':a['id'],'x':sum(v['x'] for v in k)/len(k),'y':sum(v['y'] for v in k)/len(k)}
    open('$OUT/raid.ids','w').write(' '.join(str(v['id']) for v in us))
else:
    us=[u for u in us if far(u)>=2 and d.get('turn',0)>=$4]; u=max(us,key=far) if us else None
if u:
    dx,dy=u['x']-x,u['y']-y
    print('%d %.2f %.2f %.2f' % (u['id'],u['x'],u['y'],math.atan2(dx,dy) if (dx or dy) else 0.6))" 2>/dev/null
  }
  # raid_log <when> [lens]: the season and every raider (a wild player's man new since the stage: id, owner, tile, *
  # for this raid's own, the men found by the town) into the pass log, with the lens's aim when a snap is due; the
  # evidence for a raid frame that shows none (g25, g26: raid.jpg the same with no raider in it, the walk-off "gone
  # before one was seen (stepped 0 seasons)").
  raid_log() {
    say "raid log, $1: $(curl -s -m 10 "$API/world?peek=1" | perl -e 'alarm shift; exec @ARGV' 20 python3 -I -c "
import json,sys; d=json.load(sys.stdin)
wild={p['id'] for p in d.get('players',[]) if (p.get('house') or {}).get('wild')}
old={int(x) for x in open('$OUT/raid.before').read().split()}
try:
    mine={int(i) for i in open('$OUT/raid.ids').read().split()}
except OSError:
    mine=set()
us=[u for u in d.get('units',[]) if u.get('owner') in wild and u['id'] not in old]
print('season %s; %d raiders: %s' % (d.get('turn'), len(us), ' '.join('%d(%s)@%d,%d%s' % (u['id'], u['owner'], u['x'], u['y'], '*' if u['id'] in mine else '') for u in us) or '-'))" 2>/dev/null)${2:+; lens at $2}"
  }
  curl -s -m 10 "$API/world?peek=1" | python3 -I -c "
import json,sys; print(' '.join(str(u['id']) for u in json.load(sys.stdin).get('units',[])))" > $OUT/raid.before 2>/dev/null
  RAID=$(curl -s -m 10 -X POST -H 'X-Test: 1' $API/test/stage -d '{"raid":"crown"}' | python3 -I -c "
import json,sys; r=json.load(sys.stdin)
if r.get('ok'): print(r['city'], r['x'], r['y'], r['name'])" 2>/dev/null)
  set -- ${=RAID}
  if [ -z "${1:-}" ]; then
    say "raid: not staged (the crown holds no town, or the reign isn't a film's); no frame"
  else
    RX=$2; RY=$3; RNAME=${RAID#* * * }
    T_RAID=$(curl -s -m 10 "$API/world?peek=1" | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('turn',0))" 2>/dev/null)
    SEASONS=$(sed -n '/^\[raids\]/,/^\[/s/^seasons = "\([0-9]*\)"/\1/p' $F/bridge/data/realmrules/luadata.txt)
    say "raid: men without banners on $RNAME ($RX,$RY) in season ${T_RAID:-?}; they leave after ${SEASONS:-?} seasons"
    AT=""; T0=$SECONDS
    while [ -z "$AT" ] && [ $((SECONDS - T0)) -lt ${RAID_WAIT:-300} ]; do
      curl -s -m 5 -o /dev/null -X POST $API/court/close
      curl -s -m 5 -o /dev/null -X POST $API/interlude/close
      AT=$(raider $RX $RY near 0)
      [ -z "$AT" ] && sleep 5
    done
    raid_log "the wait by the town ended ($((SECONDS - T0)) s)"
    if [ -z "$AT" ]; then
      say "raid: no raider by $RNAME in ${RAID_WAIT:-300} s; no frame"
    else
      # Held while it is filmed (bridge POST /pause), as the crossing is: the seasons would run on while Godot loads.
      set -- ${=AT}
      curl -s -m 5 -o /dev/null -X POST $API/pause
      # The raiders' midpoint, a little back from their side of the town at roof height; then midway between them and the
      # walls, further back, the town behind them.
      MX=$(( ($2 + RX) / 2.0 )); MY=$(( ($3 + RY) / 2.0 ))
      { print "wait 30"; print "tile $2 $3 5 $4"; print "wait 4"; print "snap raid"; print "tile $MX $MY 6.5 $4"; print "wait 4"; print "snap raid_town"; print "look end"; } > $OUT/raid.play
      raid_log "paused for the snaps" "raid $2,$3 (dist 5, yaw $4), raid_town $MX,$MY (dist 6.5)"
      shot raid 1500 film $SW
      raid_log "after the snaps, still paused"
      curl -s -m 5 -o /dev/null -X POST $API/resume
      side raid $OUT/frames/raid/raid.png $TARGETS/03-army.jpg "raiders at $RNAME (their midpoint $2,$3)"
      side raid_town $OUT/frames/raid/raid_town.png $TARGETS/03-army.jpg "$RNAME under the raid"
    fi
    # The walk-off is a season or two (raids.leave_steps tiles a season to wild land, often near), too quick for a poll
    # (g25: "every raider gone before one was seen on the road out"). So the reign runs to the season before they leave
    # (raids.seasons after the stage, two seasons early in case the stage's season and Freeciv's differ), is paused, and
    # then goes a season at a time (resumed until /world's turn moves, paused again) until one of this raid's men stands
    # 2+ tiles out, filmed then, still paused. No raider by the town, none to watch leave: skipped at once (g22 sat 16
    # minutes on the GPU with nothing to film); it stops the moment none of this raid's men is left alive, after
    # raids.leave_seasons + 2 steps, or at RAID_LEAVE s of the wall clock.
    turn_now() { curl -s -m 10 "$API/world" | perl -e 'alarm shift; exec @ARGV' 20 python3 -I -c "import json,sys; print(json.load(sys.stdin).get('turn',0))" 2>/dev/null; }
    OUTR=""; T0=$SECONDS; LIVE=$AT
    LEAVE_AT=$(( ${T_RAID:-0} + ${SEASONS:-8} ))
    STEPS=$(( $(sed -n '/^\[raids\]/,/^\[/s/^leave_seasons = "\([0-9]*\)"/\1/p' $F/bridge/data/realmrules/luadata.txt) + 2 ))
    while [ -n "$AT" ] && [ -n "$LIVE" ] && [ "$(turn_now)" -lt $(( LEAVE_AT - 2 )) ] && [ $((SECONDS - T0)) -lt ${RAID_LEAVE:-1200} ]; do
      curl -s -m 5 -o /dev/null -X POST $API/court/close
      curl -s -m 5 -o /dev/null -X POST $API/interlude/close
      LIVE=$(raider $RX $RY any 0)
      TL=$(turn_now); [ "$TL" != "${TLOG:-}" ] && { raid_log "running to the leaving"; TLOG=$TL; }
      [ -n "$LIVE" ] && sleep 3
    done
    [ -n "$AT" ] && raid_log "paused before the leaving (it starts in season $LEAVE_AT)"
    [ -n "$AT" ] && curl -s -m 5 -o /dev/null -X POST $API/pause
    STEP=0
    while [ -n "$AT" ] && [ -n "$LIVE" ] && [ -z "$OUTR" ] && [ $STEP -lt $STEPS ] && [ $((SECONDS - T0)) -lt ${RAID_LEAVE:-1200} ]; do
      TN=$(turn_now); TS=$SECONDS
      curl -s -m 5 -o /dev/null -X POST $API/court/close
      curl -s -m 5 -o /dev/null -X POST $API/interlude/close
      curl -s -m 5 -o /dev/null -X POST $API/resume
      while [ "$(turn_now)" = "$TN" ] && [ $((SECONDS - TS)) -lt 180 ]; do sleep 1; done
      curl -s -m 5 -o /dev/null -X POST $API/pause
      STEP=$((STEP + 1))
      sleep 2  # the season's snapshot (server.js snapshot reads world.json 0.5 s after asking)
      OUTR=$(raider $RX $RY out $LEAVE_AT)
      [ -z "$OUTR" ] && LIVE=$(raider $RX $RY any 0)
      raid_log "step $STEP"
    done
    if [ -z "$AT" ]; then
      :  # said above: no raider by the town
    elif [ -z "$OUTR" ] && [ -z "$LIVE" ]; then
      curl -s -m 5 -o /dev/null -X POST $API/resume
      say "raid: every raider of $RNAME gone before one was seen on the road out (stepped $STEP seasons); no frame"
    elif [ -z "$OUTR" ]; then
      curl -s -m 5 -o /dev/null -X POST $API/resume
      say "raid: no raider 2+ tiles out of $RNAME after $STEP seasons stepped (${RAID_LEAVE:-1200} s bound); no frame"
    else
      # Framed on his tile, not his figure; the reign still paused from the step that found him.
      set -- ${=OUTR}
      { print "wait 30"; print "tile $2 $3 5 $4"; print "wait 4"; print "snap raid_leave"; print "look end"; } > $OUT/raid_leave.play
      raid_log "paused for the walk-off snap" "$2,$3 (dist 5, yaw $4)"
      shot raid_leave 1500 film $SW
      curl -s -m 5 -o /dev/null -X POST $API/resume
      side raid_leave $OUT/frames/raid_leave/raid_leave.png $TARGETS/03-army.jpg "a raider walking off from $RNAME to wild land (raider $1 at $2,$3)"
    fi
  fi
  # Freeciv's own account (realmrules RAID lines, units lost), kept with the pass: the chronicle's home may be cleared.
  FCLOG=$(print -l $H/chronicles/render-pass-film-*/state/freeciv.log(N) | head -1)
  if [ -n "$FCLOG" ]; then
    cp $FCLOG $OUT/raid.freeciv.log
    grep -E "RAID|BANNERS|[Bb]arbarian|destroyed|killed|lost" $FCLOG | tail -40 | while read -r l; do say "raid freeciv: $l"; done
  fi
fi
say "render pass done: $OUT/side/INDEX.md"
exit 0
