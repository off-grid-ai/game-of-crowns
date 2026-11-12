#!/bin/zsh
# Focus: Kingsmere's square at the default town view against art target 01-town (docs/art/target/01-town.jpg).
# One short film (about 5 minutes [estimate]) of that one view with the current default switches: the hero frame
# (the view you start with: camera_rig.town_view, camera.json town_view), the same frame turned 15 degrees left and
# right, and one closer (0.7 of it). The hero sits about 40 degrees down at distance 6, the player's floor (camera.json town_view;
# docs/research/quality-deep-dive.md #1: 01-town reads 40-45). Every frame is framed by autoplay's "home" step
# (camera_rig.town_view: the castle behind the square), never "city" (its heading ignores the castle, so the wall
# stands in the foreground: round 1's ladder). Each frame is framed twice, the second time straight before its snap:
# the film's window takes real input (it comes to the front), and in round 1 something moved the view off Kingsmere
# during an 8 s wait (km-18_-3: the camera at the same distance between Kingsmere and Goldrock, as a click on the
# minimap or a pan would put it). Then side-by-side composites with 01-town into /tmp/goc-focus/<round>/. Run by the
# supervisor each round, after any batch (one Godot at a time through realm/tools/render.sh's queue).
#
#   docs/review/focus.sh                 # ROUND defaults to the time (HHMM)
#   ROUND=r3 docs/review/focus.sh        # frames, logs and composites in /tmp/goc-focus/r3/
#   CLOSER=0.7                           # the closer frame's share of the hero distance
#   LOOK=--look=v3 EXTRA=--cast=meshy    # the look switch (default --look=one) and any more switches
#
# Its own private bridge (8789, Freeciv 5558; PORT, FC to change) with a fresh reign named "Film focus", so Mac's
# realm on 8787 is never touched. It stops that bridge when it ends. Nothing here edits the repo.
R=${0:A:h:h:h}
ROUND=${ROUND:-$(date +%H%M)}
OUT=${OUT:-/tmp/goc-focus/$ROUND}
PORT=${PORT:-8789}; FC=${FC:-5558}
API=localhost:$PORT
CLOSER=${CLOSER:-0.7}
LOOK=${LOOK:---look=one}
SW=($LOOK ${=EXTRA} --trees=kit --ground=painted --wear=on --team=on --politics=on --castles=kit --houses=kit --towns=plots --fire=v2 --roadside=on --ui=v2 --dressing=on --castle-life=on --weather=v2 --landmarks=meshy)
B=(--bridge=http://127.0.0.1:$PORT)
TARGET=$R/docs/art/target/01-town.jpg
mkdir -p $OUT; LOG=$OUT/focus.log
say() { echo "$(date +%T) $*" | tee -a $LOG; }

say "focus round $ROUND at $(git -C $R log --oneline -1 | cut -c1-70)"
lsof -iTCP:$PORT -sTCP:LISTEN > /dev/null 2>&1 && { say "port $PORT is taken; set PORT and FC"; exit 1; }
H=$OUT/home; rm -rf $H; mkdir -p $H
( cd $R/bridge && PORT=$PORT FC_PORT=$FC GOC_HOME=$H nice -n 5 node server.js > $OUT/bridge.log 2>&1 ) &
cleanup() { P=$(lsof -tiTCP:$PORT -sTCP:LISTEN); [ -n "$P" ] && kill $P; sleep 2; pkill -f "freeciv-server -p $FC "; say "bridge stopped"; }
trap cleanup EXIT
trap "exit 1" TERM INT
for i in {1..60}; do curl -s -m 3 -o /dev/null "$API/world?peek=1" && break; sleep 1; done
r=$(curl -s -m 30 -X POST $API/chronicles -d '{"name":"Film focus","scenario":"aldmere","minutes":60,"wealth":"comfortable","options":{}}')
NID=$(print -r -- "$r" | python3 -I -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
[ -n "$NID" ] || { say "the reign wasn't made: $(print -r -- $r | head -c 200)"; exit 1; }
for i in {1..40}; do curl -s -m 5 $API/chronicles | grep -q "\"active\":\"$NID\"" && break; sleep 2; done
for i in {1..60}; do curl -s -m 5 $API/world | python3 -I -c "import json,sys; sys.exit(0 if len(json.load(sys.stdin).get('cities',[]))>5 else 1)" 2>/dev/null && break; sleep 3; done
say "reign $NID is up"

# The film: the hero frame, 15 degrees left and right, then closer (autoplay.gd's "home" step: the view you start
# with, turned by degrees and its distance scaled). Framed, a wait for the town to draw, then framed again so the
# snap takes the view as composed whatever moved it in the wait.
frame() { print "home Kingsmere $1 $2"; print "wait 6"; print "home Kingsmere $1 $2"; print "snap $3"; }
{
  print "wait 30"
  frame 0 1 hero
  frame 15 1 left15
  frame -15 1 right15
  frame 0 $CLOSER closer
  print "look focus-end"
} > $OUT/focus.play
curl -s -m 5 -o /dev/null -X POST $API/court/close
rm -rf $OUT/focus
LIMIT=300 GODOT_ARGS="--audio-driver Dummy" $R/realm/tools/render.sh $OUT/focus.png $B $SW --play=$OUT/focus.play --out=$OUT/focus >> $OUT/render.out 2>&1
grep "home\|settled" $OUT/focus/play.log 2>/dev/null | tee -a $LOG
say "film done: $(/bin/ls $OUT/focus 2>/dev/null | grep -c png) frames; script errors: $(grep -c 'SCRIPT ERROR\|SHADER ERROR' $OUT/focus.log 2>/dev/null)"

# Side by side with 01-town: hero | target, and every frame beside the target on one sheet.
arch -arm64 /usr/bin/python3 - "$OUT/focus" "$TARGET" "$OUT" <<'PY'
import sys, os
from PIL import Image, ImageDraw
src, target, out = sys.argv[1], sys.argv[2], sys.argv[3]
H = 720
def fit(p):
    im = Image.open(p).convert("RGB")
    return im.resize((round(im.width * H / im.height), H))
def label(im, text):
    d = ImageDraw.Draw(im)
    d.rectangle([0, 0, 12 + 9 * len(text), 30], fill=(0, 0, 0))
    d.text((6, 8), text, fill=(255, 255, 255))
    return im
t = label(fit(target), "01-town (target)")
frames = [(n, os.path.join(src, n + ".png")) for n in ("hero", "left15", "right15", "closer")]
frames = [(n, p) for n, p in frames if os.path.exists(p)]
for n, p in frames:
    f = label(fit(p), n)
    pair = Image.new("RGB", (f.width + t.width + 12, H), (20, 20, 20))
    pair.paste(f, (0, 0)); pair.paste(t, (f.width + 12, 0))
    pair.save(os.path.join(out, f"{n}-vs-01town.jpg"), quality=90)
if frames:
    tiles = [label(fit(p), n) for n, p in frames] + [t]
    w = max(x.width for x in tiles)
    cols = 2
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w + 12, rows * (H + 12)), (20, 20, 20))
    for i, x in enumerate(tiles):
        sheet.paste(x, ((i % cols) * (w + 12), (i // cols) * (H + 12)))
    sheet.save(os.path.join(out, "sheet.jpg"), quality=88)
print("composites:", len(frames), "frames")
PY
say "composites in $OUT (hero-vs-01town.jpg, sheet.jpg)"
