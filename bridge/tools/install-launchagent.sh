#!/bin/bash
# Keeps the realm alive whenever you're logged in: macOS starts the bridge at
# login and restarts it if it stops. Remove with: launchctl unload <plist> && rm <plist>
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.realm.bridge.plist"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.realm.bridge</string>
  <key>ProgramArguments</key>
  <array><string>$(command -v node)</string><string>$HERE/server.js</string></array>
  <key>WorkingDirectory</key><string>$HERE</string>
  <key>EnvironmentVariables</key><dict><key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HERE/bridge.log</string>
  <key>StandardErrorPath</key><string>$HERE/bridge.log</string>
</dict>
</plist>
EOF
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "The realm now runs whenever you're logged in."
