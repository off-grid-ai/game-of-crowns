#!/usr/bin/env bash
#
# Cut a Game of Crowns Windows build: build/Game-of-Crowns-<version>-windows-x86_64/ and its .zip.
# Runs in Git Bash on GitHub's windows-latest (.github/workflows/build-windows.yml); needs curl, unzip, 7z, python.
#
# The folder carries everything the realm needs:
#   Game of Crowns.cmd       the launcher (runs runtime\launch.ps1: starts the game, then the bridge)
#   game\                    the Godot export (GameOfCrowns.exe + .pck)
#   bridge\                  the Node bridge (bridge/, without chronicles)
#   runtime\node             Node (official nodejs.org win-x64 build, pinned + checksummed)
#   runtime\freeciv          freeciv-server.exe with the DLLs it loads (bin\) and its data (share\freeciv),
#                            from Freeciv's own Windows build (files.freeciv.org, pinned + checksummed)
# Realms, records and logs go to %LOCALAPPDATA%\Game of Crowns.
#
# Nothing is signed: Windows SmartScreen warns on first run ("More info", "Run anyway").
#
# Usage: packaging/build-windows.sh               (bake, export with Godot, bundle, zip)
#        SKIP_EXPORT=1 packaging/build-windows.sh (reuse the last Godot export)
# Env:   GODOT (default: godot on PATH)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

CACHE="$ROOT/build/cache"
VERSION=$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' realm/export_presets.cfg | head -1)
NAME="Game-of-Crowns-$VERSION-windows-x86_64"
OUT="$ROOT/build/$NAME"
ZIP="$ROOT/build/$NAME.zip"
NODE_VERSION=v26.13.0
NODE_SHA256=dcc60d59a0746999f99064a01c020445d54d84228c691cdbf25b49ac3b59150a
# Freeciv's official Windows build of the Mac's version (Homebrew freeciv 3.2.7). Only the server is taken.
FREECIV_VERSION=3.2.7
FREECIV_SETUP=Freeciv-$FREECIV_VERSION-msys2-win64-10-gtk4-setup.exe
FREECIV_SHA256=ebe89a914243f3a552448c7ffce5fe1ebc73d5794ef086f92b7d5cd965364945
GODOT=${GODOT:-godot}
GAME_EXE=GameOfCrowns.exe

mkdir -p "$CACHE"
RT="$OUT/runtime"

if [ -z "${SKIP_EXPORT:-}" ]; then
  echo "==> Bake the models' merged meshes into the game (realm/tools/bake.gd)"
  (cd realm && "$GODOT" --headless --path . -s res://tools/bake.gd) || { echo "!! bake failed"; exit 1; }
  echo "==> Godot export (release, Windows Desktop)"
  rm -rf "$OUT"
  mkdir -p "$OUT/game"
  (cd realm && "$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/game/$GAME_EXE")
fi
test -f "$OUT/game/$GAME_EXE" || { echo "!! no export at $OUT/game/$GAME_EXE"; exit 1; }

echo "==> Bridge"
rm -rf "$OUT/bridge" "$RT"
mkdir -p "$OUT/bridge"
# Git Bash has no rsync: tar with the Mac's excludes.
tar -C bridge --exclude chronicles --exclude records.json --exclude scenarios.json --exclude __pycache__ \
  --exclude node_modules --exclude '*.log' --exclude ./saves --exclude ./state -cf - . | tar -C "$OUT/bridge" -xf -
cp WORLD.md "$OUT/WORLD.md"

echo "==> Node $NODE_VERSION"
zipball="$CACHE/node-$NODE_VERSION-win-x64.zip"
[ -f "$zipball" ] || curl -fsSL -o "$zipball" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-win-x64.zip"
echo "$NODE_SHA256  $zipball" | sha256sum -c -
rm -rf "$CACHE/node-win" && mkdir -p "$CACHE/node-win"
unzip -q "$zipball" -d "$CACHE/node-win"
mkdir -p "$RT/node/bin"
cp "$CACHE/node-win/node-$NODE_VERSION-win-x64/node.exe" "$RT/node/bin/node.exe"
cp "$CACHE/node-win/node-$NODE_VERSION-win-x64/LICENSE" "$RT/node/LICENSE"

echo "==> Freeciv $FREECIV_VERSION"
setup="$CACHE/$FREECIV_SETUP"
[ -f "$setup" ] || curl -fsSL -o "$setup" "https://files.freeciv.org/packages/windows/$FREECIV_SETUP"
echo "$FREECIV_SHA256  $setup" | sha256sum -c -
# The installer is NSIS: 7-Zip unpacks it without running it.
fc="$CACHE/freeciv-win"
rm -rf "$fc" && mkdir -p "$fc" && 7z x -y -o"$fc" "$setup" >/dev/null
server=$(find "$fc" -iname freeciv-server.exe | head -1)
test -n "$server" || { echo "!! no freeciv-server.exe in $FREECIV_SETUP"; exit 1; }
fcdir=$(dirname "$server")
data=$(find "$fc" -type d -path '*/data/nation' | head -1)
test -n "$data" || { echo "!! no Freeciv data in $FREECIV_SETUP"; exit 1; }
data=$(dirname "$data")
mkdir -p "$RT/freeciv/bin" "$RT/freeciv/share"
cp "$server" "$RT/freeciv/bin/freeciv-server.exe"
# Only the DLLs the server loads (the installer also carries the GTK client's): walk its imports with pefile.
python -m pip install --quiet pefile
python - "$RT/freeciv/bin/freeciv-server.exe" "$fcdir" "$RT/freeciv/bin" <<'PY'
import os, shutil, sys, pefile
exe, src, dst = sys.argv[1:]
have = {f.lower(): f for f in os.listdir(src) if f.lower().endswith(".dll")}
todo, seen = [exe], set()
while todo:
    pe = pefile.PE(todo.pop(), fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY["IMAGE_DIRECTORY_ENTRY_IMPORT"]])
    for imp in getattr(pe, "DIRECTORY_ENTRY_IMPORT", []):
        name = imp.dll.decode().lower()
        if name in have and name not in seen:
            seen.add(name)
            shutil.copy2(os.path.join(src, have[name]), dst)
            todo.append(os.path.join(src, have[name]))
print(f"    {len(seen)} DLLs")
PY
# The server's rulesets, nations and scenarios; not the client's flags, music, sounds or themes.
mkdir -p "$RT/freeciv/share/freeciv"
tar -C "$data" --exclude ./flags --exclude ./stdmusic --exclude ./stdsounds --exclude ./themes -cf - . |
  tar -C "$RT/freeciv/share/freeciv" -xf -
"$RT/freeciv/bin/freeciv-server.exe" --version | head -1

echo "==> Launcher"
cat > "$RT/launch.ps1" <<'EOF'
# Game of Crowns. Starts the game, then the realm's bridge (bundled Node + Freeciv) watching the game's pid
# (GOC_PARENT_PID): the bridge puts Freeciv away when the game quits.
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
$data = Join-Path $env:LOCALAPPDATA 'Game of Crowns'
New-Item -ItemType Directory -Force -Path (Join-Path $data 'logs') | Out-Null
$game = Start-Process -FilePath (Join-Path $here 'game\GameOfCrowns.exe') -WorkingDirectory (Join-Path $here 'game') -PassThru
# A bridge already listening (a second window, a developer's own) is used as it is.
$busy = $false
try { $c = New-Object System.Net.Sockets.TcpClient; $c.Connect('127.0.0.1', 8787); $c.Close(); $busy = $true } catch {}
if (-not $busy) {
  $env:GOC_HOME = $data
  $env:GOC_PARENT_PID = "$($game.Id)"
  $node = Join-Path $here 'runtime\node\bin\node.exe'
  $app = Join-Path $here 'bridge\app.js'
  Start-Process -FilePath $node -ArgumentList "`"$app`"" -WorkingDirectory (Join-Path $here 'bridge') -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $data 'logs\bridge.log') -RedirectStandardError (Join-Path $data 'logs\bridge.err.log')
}
EOF
printf '@echo off\r\nstart "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%%~dp0runtime\\launch.ps1"\r\n' \
  > "$OUT/Game of Crowns.cmd"

echo "==> zip"
rm -f "$ZIP"
# Deflate64: smaller than Deflate, and Windows' own Explorer opens it.
(cd "$ROOT/build" && 7z a -tzip -mm=Deflate64 -mx=9 "$ZIP" "$NAME" >/dev/null)
size=$(stat -c %s "$ZIP")
[ "$size" -lt 2147483648 ] || echo "!! $ZIP is over 2 GiB: GitHub won't take it as a release file"

echo "==> Done"
du -sh "$OUT" "$ZIP"
