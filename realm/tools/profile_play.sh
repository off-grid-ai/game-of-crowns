#!/bin/bash
# Profile real play with Godot's own profiler (tools/profiler.gd): the game launched as a player launches it, the
# Hand (GOC_HAND) clicks Continue and "Click to begin" through the real input path, the profiler records SECONDS of
# the realm in play, then tools/profile_report.py ranks every script function by its time a frame.
#   realm/tools/profile_play.sh <out dir> [port 6007] [seconds 60] [resolution 1920x1080]
# Needs the bridge up with a reign to continue (./realm.sh start). Each run side by side takes its own port and out
# dir. Run it in the background: it takes about four minutes.
# Its window opens off the screen (--position, as tools/render.sh does): nothing lands on the player's desktop.
set -u
OUT=$1; PORT=${2:-6007}; SECS=${3:-60}; RES=${4:-1920x1080}
cd "$(dirname "$0")/.."
# One game at a time on the machine (Mac 2026-11-19: "why are we picking up so many instances of the game"): the
# lock every render takes (tools/render.sh), so a profile waits for a render or another profile and the other way.
LOCK=/tmp/goc-render.lock
until mkdir $LOCK 2>/dev/null; do
  [ -f $LOCK/pid ] && ! kill -0 "$(cat $LOCK/pid)" 2>/dev/null && rm -rf $LOCK  # left by a run that died
  sleep 3
done
echo $$ > $LOCK/pid
trap 'rm -rf $LOCK' EXIT
mkdir -p "$OUT/hand"; rm -f "$OUT/go" "$OUT/prof.txt"
# The same view every run, so runs compare: Continue, the court card clicked away, the King's own view of Kingsmere
# (the Hand's home), a frame saved as the profile starts (start.png) and as it ends (end.png): proof of what was measured.
rm -f "$OUT/hand/done.txt"
printf 'wait 30\nbutton Continue\nwait 100\nclick 0.5 0.5\nwait 5\nhome Kingsmere 0 1\nwait 10\nsnap start\n' > "$OUT/hand/cmd.txt"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
timeout 900 godot --headless --path . -s res://tools/profiler.gd -- --port=$PORT --start-file="$OUT/go" --seconds=$SECS --out="$OUT/prof.txt" > "$OUT/server.log" 2>&1 &
for i in $(seq 1 120); do grep -q listening "$OUT/server.log" 2>/dev/null && break; sleep 1; done
GOC_HAND="$OUT/hand" timeout 900 godot --path . --resolution $RES --position 10000,10000 --disable-vsync --remote-debug tcp://127.0.0.1:$PORT > "$OUT/game.log" 2>&1 &
G=$!
for i in $(seq 1 300); do [ -f "$OUT/hand/done.txt" ] && break; sleep 1; done
touch "$OUT/go"  # the realm in play, framed
for i in $(seq 1 600); do grep -q "messages" "$OUT/server.log" 2>/dev/null && break; sleep 2; done
rm -f "$OUT/hand/done.txt"; printf 'snap end\n' > "$OUT/hand/cmd.txt"
for i in $(seq 1 60); do [ -f "$OUT/hand/done.txt" ] && break; sleep 1; done
kill $G 2>/dev/null
grep -q "signal 11" "$OUT/game.log" && echo "THE GAME CRASHED (game.log)"
python3 -I tools/profile_report.py "$OUT/prof.txt" > "$OUT/report.txt"
head -40 "$OUT/report.txt"
echo "frames: $OUT/hand/start.png $OUT/hand/end.png"
