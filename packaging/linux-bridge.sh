#!/bin/bash
# Starts the realm's bridge on Linux (after packaging/linux-setup.sh). Same as the Mac's launch agent:
# port 8787, Freeciv on 5556. For a private bridge (measurements), set PORT, FC_PORT and GOC_HOME.
#   packaging/linux-bridge.sh                 # the realm, in the background; log in bridge/bridge.log
#   PORT=8860 FC_PORT=5660 GOC_HOME=/tmp/r1 packaging/linux-bridge.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
export FREECIV_SERVER=/opt/freeciv/freeciv-server FREECIV_SHARE=/opt/freeciv/share/freeciv
HOME_DIR="${GOC_HOME:-$HERE/bridge}"
mkdir -p "$HOME_DIR/chronicles"
# Freeciv runs as `realm` and writes its saves and logs into the chronicles.
chown -R realm "$HOME_DIR/chronicles"
d="$HOME_DIR"; while [ "$d" != "/" ]; do chmod o+x "$d" 2>/dev/null || true; d=$(dirname "$d"); done
cd "$HERE"
nohup node bridge/server.js >> "${LOG:-$HOME_DIR/bridge.log}" 2>&1 &
echo "bridge pid $! on port ${PORT:-8787}"
