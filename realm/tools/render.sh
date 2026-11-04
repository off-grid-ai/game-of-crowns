#!/bin/zsh
# One render at a time, shared by every session: waits its turn for the GPU,
# then renders natively. Two Godots at once stall Metal ("timeout waiting for
# fence") and both renders fail, so every session renders through this.
# Ali's game always comes first: renders wait while it's open, and a render
# caught running when the game opens is stopped and retried after it closes.
#   realm/tools/render.sh <out.png> [godot args after --, e.g. --city=Stonefell --dist=7 --wait=70]
# Env: RES (default 2400x1380), LIMIT seconds (default 300), PRIORITY=1 to go
# ahead of other renders (the launch kit), GODOT_ARGS engine
# flags before the -- (a movie: "--write-movie out.avi --fixed-fps 30").
cd "$(dirname "$0")/.."
LOCK=/tmp/goc-render.lock
OUT=$1; shift
# Ali's game: a Godot that isn't a render, a movie take or a headless check.
# (Only real Godot binaries count: the shells and greps that mention "godot" in
# their own command lines, this check included, must not.)
playing() { pgrep -fl "^(arch -arm64 )?godot( |$)" | grep -v -e "--shot=" -e "--write-movie" -e "--headless" | grep -q .; }
# PRIORITY=1 (the launch kit) goes first: other renders hold back while any
# prioritised render is waiting or running.
PRI=/tmp/goc-render.priority
mkdir -p $PRI
[ -n "$PRIORITY" ] && touch $PRI/$$
first() {
  [ -n "$PRIORITY" ] && return 0
  for f in $PRI/*(N); do kill -0 ${f:t} 2>/dev/null && return 1; rm -f $f; done
  return 0
}
until first && mkdir $LOCK 2>/dev/null; do
  # A lock left by a render that died frees itself.
  [ -f $LOCK/pid ] && ! kill -0 $(cat $LOCK/pid) 2>/dev/null && rm -rf $LOCK
  sleep 3
done
echo $$ > $LOCK/pid
trap 'rm -rf $LOCK $PRI/$$' EXIT
for attempt in 1 2 3 4 5 6; do
  while playing; do sleep 10; done
  arch -arm64 godot --path . --resolution ${RES:-2400x1380} ${=GODOT_ARGS} -- --shot=$OUT "$@" > ${OUT%.png}.log 2>&1 &
  pid=$!; t=0; yielded=0
  while kill -0 $pid 2>/dev/null && [ $t -lt ${LIMIT:-300} ]; do
    sleep 2; t=$((t+2))
    if playing; then kill $pid 2>/dev/null; yielded=1; break; fi
  done
  kill $pid 2>/dev/null
  [ $yielded = 1 ] && continue
  break
done
[ -f $OUT ] && echo "ok $OUT" || { echo "MISSING $OUT (log: ${OUT%.png}.log)"; exit 1; }
