#!/bin/zsh
# READY.md line 7, "Capture a town", end to end on a private bridge and Freeciv (8788 / 5557, its own GOC_HOME;
# never Mac's realm), state only, no GPU: the game itself runs headless (capture_chain_probe.gd) against the bridge,
# a hasty King (reign_measure.py) answers the court so the seasons turn. Exits as the Godot probe does (1: a link of
# the chain broke; 2: the setup didn't come up).
#   zsh realm/tools/capture_chain_probe.sh
cd "${0:A:h}/../.."
ROOT=$PWD
PORT=8788 FC_PORT=5557
OUT=$(mktemp -d /tmp/goc-capture.XXXX)
mkdir -p $OUT/home
cleanup() { kill -9 ${king:-} ${bridge:-} 2>/dev/null; pkill -KILL -f "freeciv-server -p $FC_PORT " 2>/dev/null; }
trap cleanup EXIT INT TERM
# Load rule: at most two private bridges besides the main one (8787).
for i in {1..180}; do
  n=$(pgrep -f 'node.*server.js' | wc -l | tr -d ' ')
  (( n - 1 < 2 )) && break
  (( i == 1 )) && print "  waiting for a private bridge slot ($((n - 1)) running)"
  sleep 10
done
pkill -KILL -f "freeciv-server -p $FC_PORT " 2>/dev/null
(cd bridge && PORT=$PORT FC_PORT=$FC_PORT GOC_HOME=$OUT/home exec node server.js > $OUT/bridge.log 2>&1) &
bridge=$!
for i in {1..150}; do grep -q 'Bridge listening' $OUT/bridge.log && break; sleep 0.2; done
grep -q 'Bridge listening' $OUT/bridge.log || { print "CAPTURE CHAIN: the private bridge didn't start"; tail -15 $OUT/bridge.log; exit 2; }
curl -s -X POST -H 'content-type: application/json' -d '{"name":"Capture check","scenario":"aldmere","minutes":0}' http://127.0.0.1:$PORT/chronicles > /dev/null
for i in {1..120}; do
  curl -s http://127.0.0.1:$PORT/world 2>/dev/null | python3 -I -c 'import json,sys; w=json.load(sys.stdin); sys.exit(0 if w.get("turn",0)>0 and w.get("players") else 1)' 2>/dev/null && break
  sleep 1
done
curl -s -X POST -H 'content-type: application/json' -d '{"seconds":3}' http://127.0.0.1:$PORT/speed > /dev/null
python3 -I realm/tools/reign_measure.py 127.0.0.1:$PORT 20 $OUT/king.json > /dev/null 2>&1 &
king=$!
print "  private bridge on $PORT, Freeciv on $FC_PORT; out $OUT"
arch -arm64 godot --headless --path realm -s res://tools/capture_chain_probe.gd -- --bridge=http://127.0.0.1:$PORT 2>&1 | tee $OUT/godot.log | grep -E '^(CHECK|CAPTURE|  [a-z])'
# The verdict line decides (Godot may abort on quit with the whole game up, after its verdict).
grep -q '^CAPTURE CHAIN PASS' $OUT/godot.log && exit 0
grep -q '^CAPTURE CHAIN' $OUT/godot.log && exit 1
exit 2
