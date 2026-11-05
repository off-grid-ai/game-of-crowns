#!/usr/bin/env bash
#
# Cut a Game of Crowns Mac build: build/Game of Crowns.app and build/Game-of-Crowns-<version>-arm64.dmg.
#
# The app carries everything the realm needs, so a player needs no terminal and no Homebrew:
#   Contents/Resources/bridge        the Node bridge (bridge/, without chronicles)
#   Contents/Resources/runtime/node  Node (official nodejs.org build, pinned + checksummed)
#   Contents/Resources/runtime/freeciv  freeciv-server, its dylibs (dylibbundler) and its data
# No model ships with the game: the realm plays by its rules, and lords speak in their own
# words when Off Grid AI (https://github.com/off-grid-ai) is running Omni on the same Mac.
#
# Signing and notarisation follow Off Grid AI Desktop's release (OGAD .github/workflows/release.yml),
# with the same secrets:
#   CSC_LINK, CSC_KEY_PASSWORD     base64 Developer ID Application .p12 and its password
#                                  (or SIGN_IDENTITY naming one already in the keychain)
#   APPLE_API_KEY, APPLE_API_KEY_ID, APPLE_API_ISSUER   App Store Connect API key (.p8 path) for notarytool
# With none of these the build is ad-hoc signed: it runs on this Mac but Gatekeeper blocks it elsewhere.
#
# Usage: packaging/build-mac.sh            (export with Godot, bundle, sign, notarise, dmg)
#        SKIP_EXPORT=1 packaging/build-mac.sh   (reuse the last Godot export)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

APP="$ROOT/build/Game of Crowns.app"
CACHE="$ROOT/build/cache"
VERSION=$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' realm/export_presets.cfg)
DMG="$ROOT/build/Game-of-Crowns-$VERSION-arm64.dmg"
ENTITLEMENTS="$ROOT/packaging/entitlements.plist"
NODE_VERSION=v26.13.0
NODE_SHA256=d38bd5e5a2ddce6bbb5ce45e46e208337da4d51fffe611e567fd32073d6439f6
FREECIV_SERVER=${FREECIV_SERVER:-$(command -v freeciv-server)}
FREECIV_SHARE=${FREECIV_SHARE:-/opt/homebrew/share/freeciv}
GODOT=(arch -arm64 godot)

mkdir -p "$CACHE"
RES="$APP/Contents/Resources"
RT="$RES/runtime"

if [ -z "${SKIP_EXPORT:-}" ]; then
  echo "==> Godot export (release, macOS)"
  rm -rf "$APP"
  (cd realm && "${GODOT[@]}" --headless --path . --export-release "macOS" "$APP")
fi
test -d "$APP" || { echo "!! no export at $APP"; exit 1; }

echo "==> Apple Silicon only"
find "$APP/Contents/MacOS" "$APP/Contents/Frameworks" -type f | while read -r f; do
  if lipo -archs "$f" 2>/dev/null | grep -q x86_64; then lipo "$f" -thin arm64 -output "$f.arm64" && mv "$f.arm64" "$f"; fi
done

echo "==> Bridge"
rm -rf "$RES/bridge" "$RT"
rsync -a --exclude chronicles --exclude records.json --exclude scenarios.json --exclude __pycache__ \
  --exclude node_modules --exclude '*.log' --exclude saves --exclude state bridge/ "$RES/bridge/"
cp WORLD.md "$RES/WORLD.md"

echo "==> Node $NODE_VERSION"
tarball="$CACHE/node-$NODE_VERSION-darwin-arm64.tar.gz"
[ -f "$tarball" ] || curl -fsSL -o "$tarball" "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-arm64.tar.gz"
echo "$NODE_SHA256  $tarball" | shasum -a 256 -c -
rm -rf "$CACHE/node" && mkdir -p "$CACHE/node" && tar -xzf "$tarball" -C "$CACHE/node" --strip-components 1
mkdir -p "$RT/node/bin"
cp "$CACHE/node/bin/node" "$RT/node/bin/node"
cp "$CACHE/node/LICENSE" "$RT/node/LICENSE"

echo "==> Freeciv ($("$FREECIV_SERVER" --version | head -1))"
mkdir -p "$RT/freeciv/bin" "$RT/freeciv/share"
cp "$(readlink -f "$FREECIV_SERVER")" "$RT/freeciv/bin/freeciv-server"
chmod u+w "$RT/freeciv/bin/freeciv-server"
dylibbundler -of -b -cd -x "$RT/freeciv/bin/freeciv-server" -d "$RT/freeciv/lib" -p @executable_path/../lib/ >/dev/null
# The server's rulesets, nations and scenarios; not the client's flags, music, sounds or themes.
rsync -aL --exclude flags --exclude stdmusic --exclude stdsounds --exclude themes "$FREECIV_SHARE/" "$RT/freeciv/share/freeciv/"
otool -L "$RT/freeciv/bin/freeciv-server" "$RT"/freeciv/lib/*.dylib | grep -q /opt/homebrew && { echo "!! Homebrew path left in Freeciv"; exit 1; }

echo "==> Sign"
KEYCHAIN=""
if [ -z "${SIGN_IDENTITY:-}" ] && [ -n "${CSC_LINK:-}" ]; then
  # As OGAD's CI does: the Developer ID goes into a throwaway keychain for this build only.
  KEYCHAIN="$CACHE/signing.keychain-db"
  security delete-keychain "$KEYCHAIN" 2>/dev/null || true
  security create-keychain -p goc "$KEYCHAIN"
  security set-keychain-settings -lut 3600 "$KEYCHAIN"
  security unlock-keychain -p goc "$KEYCHAIN"
  printf '%s' "$CSC_LINK" | base64 --decode > "$CACHE/cert.p12"
  security import "$CACHE/cert.p12" -k "$KEYCHAIN" -P "$CSC_KEY_PASSWORD" -T /usr/bin/codesign
  rm -f "$CACHE/cert.p12"
  security set-key-partition-list -S apple-tool:,apple: -s -k goc "$KEYCHAIN" >/dev/null
  security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
  SIGN_IDENTITY=$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')
fi
SIGN_IDENTITY=${SIGN_IDENTITY:--}
sign() {
  if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - --options runtime --entitlements "$ENTITLEMENTS" "$@"
  else
    codesign --force --sign "$SIGN_IDENTITY" ${KEYCHAIN:+--keychain "$KEYCHAIN"} --timestamp --options runtime --entitlements "$ENTITLEMENTS" "$@"
  fi
}
echo "    identity: $SIGN_IDENTITY"
# Inside out: every bundled program and library, then the app's frameworks, then the app.
find "$RT" -type f | while read -r f; do
  if file -b "$f" | grep -q Mach-O; then sign "$f"; fi
done
find "$APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 2>/dev/null | while read -r f; do sign "$f"; done
sign "$APP"
codesign --verify --strict --deep "$APP"

notarize() {
  # The upload to Apple sometimes drops partway (abortedUpload); try again before failing the build.
  for i in 1 2 3; do
    xcrun notarytool submit "$1" --key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER" --wait --timeout 60m && return 0
    echo "    notarisation attempt $i failed; retrying in 60s"; sleep 60
  done
  return 1
}
staple() {
  for i in 1 2 3 4 5 6 7 8 9 10; do
    xcrun stapler staple -v "$1" && return 0
    echo "    staple attempt $i lost Apple's ticket service; retrying in 30s"; sleep 30
  done
  return 1
}
NOTARIZE=""
if [ "$SIGN_IDENTITY" != "-" ] && [ -n "${APPLE_API_KEY:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
  NOTARIZE=1
  echo "==> Notarise the app"
  ditto -c -k --keepParent "$APP" "$CACHE/notarize.zip"
  notarize "$CACHE/notarize.zip"
  rm -f "$CACHE/notarize.zip"
  staple "$APP"
else
  echo "==> Not notarised (needs a Developer ID and APPLE_API_KEY, APPLE_API_KEY_ID, APPLE_API_ISSUER)"
fi

echo "==> DMG"
stage="$CACHE/dmg"
rm -rf "$stage" "$DMG" && mkdir -p "$stage"
ditto "$APP" "$stage/Game of Crowns.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Game of Crowns" -srcfolder "$stage" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$stage"
if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --sign "$SIGN_IDENTITY" ${KEYCHAIN:+--keychain "$KEYCHAIN"} --timestamp "$DMG"
fi
if [ -n "$NOTARIZE" ]; then
  echo "==> Notarise the dmg"
  notarize "$DMG"
  staple "$DMG"
  spctl --assess --type open --context context:primary-signature -v "$DMG"
fi
[ -n "$KEYCHAIN" ] && security delete-keychain "$KEYCHAIN"

echo "==> Done"
du -sh "$APP" "$DMG"
