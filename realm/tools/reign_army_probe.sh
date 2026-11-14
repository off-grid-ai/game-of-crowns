#!/bin/zsh
# READY 10's army reign probe (tools/reign_army_probe.gd) on a private bridge (8861/5611), headless: a new
# chronicle, the pace set, a King answering the court (tools/reign_measure.py), and the real game watching every
# company's figure each season. Everything it starts it stops.
#   zsh realm/tools/reign_army_probe.sh [seasons=60] [pace seconds=8] [fault: vanish|freeze]
# Output in $SP/reign-army (default /tmp/goc-reign-army): bridge.log, king.log, game.log, result.txt.
SEASONS=${1:-60}
PACE=${2:-8}
FAULT=${3:-}
SP=${SP:-/tmp/goc-reign-army}
R=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$SP/reign-army${FAULT:+-$FAULT}; mkdir -p $OUT
H=$SP/state-home; rm -rf $H; mkdir -p $H
cd $R/bridge
PORT=8861 FC_PORT=5611 GOC_HOME=$H node server.js > $OUT/bridge.log 2>&1 &
BP=$!
KP=
cleanup() { [[ -n $KP ]] && kill $KP 2>/dev/null; kill $BP 2>/dev/null; sleep 2; pkill -f "freeciv-server -p 5611 "; }
trap cleanup EXIT
for i in {1..60}; do curl -s -m 3 -o /dev/null "localhost:8861/world?peek=1" && break; sleep 1; done
curl -s -m 90 -X POST localhost:8861/chronicles -H 'Content-Type: application/json' -d '{"name":"reign-army-probe"}' > $OUT/new.json
sleep 5
curl -s -m 10 -X POST localhost:8861/speed -H 'Content-Type: application/json' -d "{\"seconds\":$PACE}" > $OUT/speed.json
# The King: answers every court, interlude and event, as a hasty player does (minutes: the probe's own bound).
python3 -I $R/realm/tools/reign_measure.py 127.0.0.1:8861 90 $OUT/king > /dev/null 2>&1 &
KP=$!
cd $R
LIMIT=99999 perl -e 'alarm 5700; exec @ARGV' arch -arm64 godot --headless --fixed-fps 30 --path realm -s res://tools/reign_army_probe.gd -- \
  --bridge=http://127.0.0.1:8861 --shot=$OUT/never.png --wait=99999 --reign-seasons=$SEASONS ${FAULT:+--reign-fault=$FAULT} > $OUT/game.log 2>&1
CODE=$?
grep -E "^REIGN PROBE|SCRIPT ERROR" $OUT/game.log | head -80 > $OUT/result.txt
echo "exit $CODE" >> $OUT/result.txt
cat $OUT/result.txt
