#!/bin/zsh
# The motion probe on a private bridge (8860/5610), headless: one run per argument set.
SP=${SP:-/tmp/goc-motion}
R=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$SP/motion; mkdir -p $OUT
TAG=${1:-before}
H=$SP/state-home/motion; mkdir -p $H
cd $R/bridge
PORT=8860 FC_PORT=5610 GOC_HOME=$H node server.js > $OUT/bridge-$TAG.log 2>&1 &
BP=$!
cleanup() { kill $BP 2>/dev/null; sleep 2; pkill -f "freeciv-server -p 5610 "; }
trap cleanup EXIT
for i in {1..60}; do curl -s -m 3 -o /dev/null "localhost:8860/world?peek=1" && break; sleep 1; done
# a test reign (seed 1066), so the town is the same every run
curl -s -m 60 -X POST localhost:8860/chronicles -H 'Content-Type: application/json' -d '{"name":"motion-check"}' > $OUT/new-$TAG.json
sleep 5
cd $R
arch -arm64 godot --headless --fixed-fps 60 --path realm -- --bridge=http://127.0.0.1:8860 --shot=$OUT/never-$TAG.png --wait=900 --city=Kingsmere --dist=3 --limbo=all --motion-probe=60 ${=GAME_EXTRA} > $OUT/game-$TAG.log 2>&1
grep -E "^MOTION|SCRIPT ERROR" $OUT/game-$TAG.log | head -20 > $OUT/result-$TAG.txt
echo done >> $OUT/result-$TAG.txt
