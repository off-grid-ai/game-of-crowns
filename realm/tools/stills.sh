#!/bin/zsh
# Renders the intro and launch-video stills into realm/assets/intro/stills:
# one Godot at a time, natively, at 4K, without the interface. Each render is
# given up to five minutes. Usage: realm/tools/stills.sh [log dir]
cd "$(dirname "$0")/../.."
OUT=realm/assets/intro/stills
LOG=${1:-/tmp}
mkdir -p $OUT

shot() {
  local name=$1; shift
  arch -arm64 godot --path realm --resolution 3840x2160 -- --shot=$PWD/$OUT/$name.png --clean "$@" > $LOG/still_$name.log 2>&1 &
  local pid=$!
  local t=0
  while kill -0 $pid 2>/dev/null && [ $t -lt 300 ]; do sleep 2; t=$((t+2)); done
  kill $pid 2>/dev/null
  [ -f $OUT/$name.png ] && echo "ok $name" || echo "MISSING $name"
}

shot realm --wait=70
for seat in Stonefell Goldrock Riverhall Eaglefell Crowfield Highfell Deepvale Lionmoor; do
  shot seat_$seat --city=$seat --dist=7 --wait=70
done
shot street --city=Stonefell --dist=2.5 --wait=70
shot battle --city=Deepvale --battle --wait=70
shot hero --hero=0 --wait=60
shot hall --control=0 --interior=great_hall --wait=300
shot walk --control=0 --wait=300
