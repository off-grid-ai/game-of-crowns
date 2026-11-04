#!/bin/zsh
# One render at a time, shared by every session: waits its turn for the GPU,
# then renders natively. Two Godots at once stall Metal ("timeout waiting for
# fence") and both renders fail, so every session renders through this.
#   realm/tools/render.sh <out.png> [godot args after --, e.g. --city=Stonefell --dist=7 --wait=70]
# Env: RES (default 2400x1380), LIMIT seconds (default 300).
cd "$(dirname "$0")/.."
LOCK=/tmp/goc-render.lock
OUT=$1; shift
# Ali's game comes first: while it's open (a Godot that isn't a render or a
# headless check), renders wait rather than make it lag.
playing() { pgrep -ifl godot | grep -v -e "--shot=" -e "--headless" -e "render.sh" | grep -qi godot; }
while playing; do sleep 10; done
until mkdir $LOCK 2>/dev/null; do
  # A lock left by a render that died frees itself.
  [ -f $LOCK/pid ] && ! kill -0 $(cat $LOCK/pid) 2>/dev/null && rm -rf $LOCK
  sleep 3
done
echo $$ > $LOCK/pid
trap 'rm -rf $LOCK' EXIT
arch -arm64 godot --path . --resolution ${RES:-2400x1380} -- --shot=$OUT "$@" > ${OUT%.png}.log 2>&1 &
pid=$!; t=0
while kill -0 $pid 2>/dev/null && [ $t -lt ${LIMIT:-300} ]; do sleep 2; t=$((t+2)); done
kill $pid 2>/dev/null
[ -f $OUT ] && echo "ok $OUT" || { echo "MISSING $OUT (log: ${OUT%.png}.log)"; exit 1; }
