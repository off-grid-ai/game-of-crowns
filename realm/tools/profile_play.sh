#!/bin/bash
# Profile real play with Godot's own profiler (tools/profiler.gd): the game launched as a player launches it, the
# Hand (GOC_HAND) clicks Continue and "Click to begin" through the real input path, the profiler records SECONDS of
# the realm in play, then tools/profile_report.py ranks every script function by its time a frame.
#   realm/tools/profile_play.sh <out dir> [port 6007] [seconds 60] [resolution 1920x1080]
# Needs the bridge up with a reign to continue (./realm.sh start). Each run side by side takes its own port and out
# dir. Run it in the background: it takes about four minutes.
set -u
OUT=$1; PORT=${2:-6007}; SECS=${3:-60}; RES=${4:-1920x1080}
cd "$(dirname "$0")/.."
mkdir -p "$OUT/hand"; rm -f "$OUT/go" "$OUT/prof.txt"
printf 'wait 30\nclick 0.4995 0.385\nwait 100\nclick 0.5 0.5\nwait 5\n' > "$OUT/hand/cmd.txt"
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} DISPLAY=${DISPLAY:-:0}
timeout 900 godot --headless --path . -s res://tools/profiler.gd -- --port=$PORT --start-file="$OUT/go" --seconds=$SECS --out="$OUT/prof.txt" > "$OUT/server.log" 2>&1 &
for i in $(seq 1 120); do grep -q listening "$OUT/server.log" 2>/dev/null && break; sleep 1; done
GOC_HAND="$OUT/hand" timeout 900 godot --path . --resolution $RES --disable-vsync --remote-debug tcp://127.0.0.1:$PORT > "$OUT/game.log" 2>&1 &
G=$!
sleep 175; touch "$OUT/go"  # the realm in play: Continue at 30 s, the court card clicked at 130 s
for i in $(seq 1 600); do grep -q "messages" "$OUT/server.log" 2>/dev/null && break; sleep 2; done
kill $G 2>/dev/null
grep -q "signal 11" "$OUT/game.log" && echo "THE GAME CRASHED (game.log)"
python3 -I tools/profile_report.py "$OUT/prof.txt" > "$OUT/report.txt"
head -40 "$OUT/report.txt"
