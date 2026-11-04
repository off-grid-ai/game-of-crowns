#!/bin/bash
# Opens Game of Crowns. The world itself (Freeciv + bridge) keeps running in the
# background after you close the window.
#   ./realm.sh          open the view (waking the realm if needed)
#   ./realm.sh status   turn, year and towns
#   ./realm.sh stop     put the realm to sleep (it saves first)
#   ./realm.sh start    wake it without opening the view
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LOG="$HERE/bridge/bridge.log"
PLIST="$HOME/Library/LaunchAgents/com.realm.bridge.plist"

running() { curl -s -o /dev/null --max-time 1 http://127.0.0.1:8787/world; }

# On Apple Silicon, always run Godot natively: a shell under Rosetta would
# otherwise start it as Intel, several times slower.
godot_native() {
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then arch -arm64 godot "$@"; else godot "$@"; fi
}

wake() {
  if running; then return; fi
  echo "Waking the realm…"
  if [ -f "$PLIST" ]; then
    launchctl load "$PLIST" 2>/dev/null || true
  else
    nohup node "$HERE/bridge/server.js" >> "$LOG" 2>&1 &
  fi
  for _ in $(seq 1 30); do running && break; sleep 1; done
}

case "${1:-open}" in
  stop)
    if [ -f "$PLIST" ]; then
      launchctl unload "$PLIST" 2>/dev/null || true
    else
      pkill -f "node $HERE/bridge/server.js" || true
    fi
    echo "The realm sleeps (saved)."
    ;;
  start)
    wake
    ;;
  status)
    if running; then
      curl -s http://127.0.0.1:8787/world | python3 -c '
import sys, json
w = json.load(sys.stdin)
if "turn" not in w:
    print("The realm is forming…")
else:
    print("Turn %d, %d towns, %d houses alive" % (w["turn"], len(w["cities"]), sum(1 for p in w["players"] if p["cities"])))'
    else
      echo "The realm is asleep."
    fi
    ;;
  open)
    wake
    # Import any new art (banners, textures) dropped into realm/assets first.
    godot_native --headless --path "$HERE/realm" --import >/dev/null 2>&1 || true
    godot_native --path "$HERE/realm" >/dev/null 2>&1 &
    ;;
esac
