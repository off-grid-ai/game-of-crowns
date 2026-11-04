#!/bin/bash
# Fires each god command at the first town and prints any Lua error Freeciv reports.
cd "$(dirname "$0")/.."
curl -s --retry 6 --retry-connrefused --retry-delay 1 localhost:8787/world -o /dev/null
sleep 5
C=$(curl -s localhost:8787/world | python3 -c 'import sys,json;w=json.load(sys.stdin);print(w["cities"][0]["id"])')
for a in bounty famine dragon army plague gold civil_war; do
  : > state/freeciv.log
  curl -s -X POST localhost:8787/god -d "{\"action\":\"$a\",\"city\":$C}" >/dev/null
  sleep 1
  echo "== $a"
  grep -A3 "lua error" state/freeciv.log | head -4
done
