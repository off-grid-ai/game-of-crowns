#!/usr/bin/env bash
#
# Cut a Game of Crowns Linux build: build/Game-of-Crowns-<version>-linux-x86_64/ and its .tar.xz.
#
# The folder carries everything the realm needs, so a player needs no terminal setup and no packages:
#   game-of-crowns           the launcher: starts the bridge, then the game (run this)
#   game/                    the Godot export (game-of-crowns.x86_64 + .pck)
#   bridge/                  the Node bridge (bridge/, without chronicles)
#   runtime/node             Node (official nodejs.org linux-x64 build, pinned + checksummed)
#   runtime/freeciv          freeciv-server, its shared libraries (lib/, found by a small LD_LIBRARY_PATH
#                            wrapper in bin/) and its data (share/freeciv)
# Realms, records and logs go to ~/.local/share/game-of-crowns (XDG_DATA_HOME).
#
# Runs on stock Ubuntu 22.04 and newer when freeciv-server was built on 22.04 (CI builds it there from
# Freeciv's own source: .github/workflows/build-linux.yml). Every library it needs except glibc's own ships
# in runtime/freeciv/lib, so the build host's glibc is the floor.
#
# Why .tar.xz, not .tar.gz: the Mac's zlib dmg of the same game came out over GitHub's 2 GB limit on a
# release's file (run 44160580763); xz is the LZMA the Mac switched to, and every Linux tar opens it.
#
# Usage: packaging/build-linux.sh               (bake, export with Godot, bundle, tar.xz)
#        SKIP_EXPORT=1 packaging/build-linux.sh (reuse the last Godot export)
# Env:   GODOT (default ~/.local/bin/godot), FREECIV_SERVER, FREECIV_SHARE
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

CACHE="$ROOT/build/cache"
VERSION=$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' realm/export_presets.cfg | head -1)
NAME="Game-of-Crowns-$VERSION-linux-x86_64"
OUT="$ROOT/build/$NAME"
TARBALL="$ROOT/build/$NAME.tar.xz"
NODE_VERSION=v26.13.0
NODE_SHA256=5848553868b402d3fabb5b09270649977780a390f832155721025a08b5104455
FREECIV_SERVER=${FREECIV_SERVER:-$(command -v freeciv-server || true)}
FREECIV_SHARE=${FREECIV_SHARE:-$(dirname "$(dirname "$(readlink -f "${FREECIV_SERVER:-/usr/bin/x}")")")/share/freeciv}
[ -d "$FREECIV_SHARE" ] || FREECIV_SHARE=/usr/share/games/freeciv
GODOT=${GODOT:-$HOME/.local/bin/godot}
GAME_BIN=game-of-crowns.x86_64

test -x "$FREECIV_SERVER" || { echo "!! no freeciv-server (set FREECIV_SERVER)"; exit 1; }
test -d "$FREECIV_SHARE" || { echo "!! no Freeciv data at $FREECIV_SHARE (set FREECIV_SHARE)"; exit 1; }

mkdir -p "$CACHE"
RT="$OUT/runtime"

if [ -z "${SKIP_EXPORT:-}" ]; then
  echo "==> Bake the models' merged meshes into the game (realm/tools/bake.gd)"
  (cd realm && "$GODOT" --headless --path . -s res://tools/bake.gd) || { echo "!! bake failed"; exit 1; }
  echo "==> Godot export (release, Linux)"
  rm -rf "$OUT"
  mkdir -p "$OUT/game"
  (cd realm && "$GODOT" --headless --path . --export-release "Linux" "$OUT/game/$GAME_BIN")
fi
test -x "$OUT/game/$GAME_BIN" || { echo "!! no export at $OUT/game/$GAME_BIN"; exit 1; }

echo "==> Bridge"
rm -rf "$OUT/bridge" "$RT"
rsync -a --exclude chronicles --exclude records.json --exclude scenarios.json --exclude __pycache__ \
  --exclude node_modules --exclude '*.log' --exclude /saves --exclude /state bridge/ "$OUT/bridge/"
cp WORLD.md "$OUT/WORLD.md"

echo "==> Node $NODE_VERSION"
tarball="$CACHE/node-$NODE_VERSION-linux-x64.tar.gz"
[ -f "$tarball" ] || curl -fsSL -o "$tarball" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-linux-x64.tar.gz"
echo "$NODE_SHA256  $tarball" | sha256sum -c -
rm -rf "$CACHE/node-linux" && mkdir -p "$CACHE/node-linux" && tar -xzf "$tarball" -C "$CACHE/node-linux" --strip-components 1
mkdir -p "$RT/node/bin"
cp "$CACHE/node-linux/bin/node" "$RT/node/bin/node"
cp "$CACHE/node-linux/LICENSE" "$RT/node/LICENSE"

echo "==> Freeciv ($("$FREECIV_SERVER" --version | head -1))"
# The real server sits in libexec/ under its own name, so the bridge's `pkill -f "freeciv-server -p <port> "`
# still finds it; bin/freeciv-server (what bridge/app.js runs) points it at lib/ and execs it.
mkdir -p "$RT/freeciv/bin" "$RT/freeciv/libexec" "$RT/freeciv/lib" "$RT/freeciv/share"
cp "$(readlink -f "$FREECIV_SERVER")" "$RT/freeciv/libexec/freeciv-server"
chmod 755 "$RT/freeciv/libexec/freeciv-server"
# Every library ldd resolves, except glibc's own (those must come from the player's system).
ldd "$RT/freeciv/libexec/freeciv-server" | awk '/=> \// {print $3}' | while read -r lib; do
  case "$(basename "$lib")" in
    linux-vdso*|ld-linux*|libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|libresolv.so*|libutil.so*) ;;
    *) cp -L "$lib" "$RT/freeciv/lib/" ;;
  esac
done
cat > "$RT/freeciv/bin/freeciv-server" <<'EOF'
#!/bin/sh
# Freeciv with the libraries it shipped with (runtime/freeciv/lib).
here=$(dirname "$(readlink -f "$0")")/..
LD_LIBRARY_PATH="$here/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" exec "$here/libexec/freeciv-server" "$@"
EOF
chmod 755 "$RT/freeciv/bin/freeciv-server"
# The server's rulesets, nations and scenarios; not the client's flags, music, sounds or themes.
rsync -aL --exclude flags --exclude stdmusic --exclude stdsounds --exclude themes "$FREECIV_SHARE/" "$RT/freeciv/share/freeciv/"
LD_LIBRARY_PATH="$RT/freeciv/lib" ldd "$RT/freeciv/libexec/freeciv-server" | grep -q "not found" && { echo "!! a Freeciv library is missing"; exit 1; }
"$RT/freeciv/bin/freeciv-server" --version | head -1

echo "==> Launcher"
cat > "$OUT/game-of-crowns" <<EOF
#!/usr/bin/env bash
# Game of Crowns. Starts the realm's bridge (bundled Node + Freeciv), then the game.
# The bridge watches the game's pid (GOC_PARENT_PID: this script's pid, which the game takes over by exec)
# and puts Freeciv away when the game quits or dies.
here=\$(dirname "\$(readlink -f "\$0")")
export GOC_HOME="\${GOC_HOME:-\${XDG_DATA_HOME:-\$HOME/.local/share}/game-of-crowns}"
mkdir -p "\$GOC_HOME/logs"
# A bridge already listening (a second window, a developer's own) is used as it is.
if ! (exec 3<>/dev/tcp/127.0.0.1/8787) 2>/dev/null; then
  GOC_PARENT_PID=\$\$ "\$here/runtime/node/bin/node" "\$here/bridge/app.js" >>"\$GOC_HOME/logs/bridge.log" 2>&1 &
fi
exec "\$here/game/$GAME_BIN" "\$@"
EOF
chmod 755 "$OUT/game-of-crowns"

echo "==> tar.xz"
rm -f "$TARBALL"
tar -C "$ROOT/build" -cf - "$NAME" | xz -T0 -6 > "$TARBALL"
size=$(stat -c %s "$TARBALL")
[ "$size" -lt 2147483648 ] || echo "!! $TARBALL is over 2 GiB: GitHub won't take it as a release file"

echo "==> Done"
du -sh "$OUT" "$TARBALL"
