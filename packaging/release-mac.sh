#!/usr/bin/env bash
#
# Cut a public Mac release on this machine: build, sign and notarise Game of Crowns from the last
# commit (not the working tree, which other sessions may have half-changed), then publish the dmg
# as a GitHub Release.
#
# The build runs in a scratch folder: the committed files from `git archive HEAD`, plus the
# third-party art and Godot's import cache hard-linked from this working copy (the art stays out
# of git by licence, and hard links cost no disk).
#
# Needs: a Developer ID Application identity in the keychain, and for notarisation
#   APPLE_API_KEY (path to the .p8), APPLE_API_KEY_ID, APPLE_API_ISSUER
# Usage: packaging/release-mac.sh [--prerelease]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=off-grid-ai/game-of-crowns
FLAG=""; [ "${1:-}" = "--prerelease" ] && FLAG="--prerelease"

for v in APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  [ -n "${!v:-}" ] || { echo "!! $v is not set"; exit 1; }
done

SHA=$(git rev-parse --short HEAD)
SRC=$(mktemp -d "$HOME/.goc-release.XXXXXX")
trap 'rm -rf "$SRC"' EXIT
echo "==> Committed files at $SHA"
git archive HEAD | tar -x -C "$SRC"

echo "==> Art and import cache (hard links)"
git ls-files -o -i --exclude-standard realm/assets > "$SRC/.art-list"
rsync -a --link-dest="$ROOT/" --files-from="$SRC/.art-list" "$ROOT/" "$SRC/"
rm "$SRC/.art-list"
[ -d realm/.godot ] && rsync -a --link-dest="$ROOT/realm/.godot/" "$ROOT/realm/.godot/" "$SRC/realm/.godot/"

echo "==> Build, sign, notarise"
"$SRC/packaging/build-mac.sh"

DMG=$(ls "$SRC"/build/Game-of-Crowns-*-arm64.dmg)
spctl -a -vv -t open --context context:primary-signature "$DMG"
xcrun stapler validate "$DMG"

VERSION=$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' realm/export_presets.cfg)
TAG="v$VERSION-$(date +%Y%m%d)-$SHA"
echo "==> Release $TAG"
gh release create "$TAG" "$DMG" $FLAG -R "$REPO" --target "$(git rev-parse HEAD)" \
  --title "Game of Crowns $VERSION ($SHA)" \
  --notes "Free, nothing locked. For Macs with Apple Silicon. Open the dmg and drag Game of Crowns to Applications. On first run it downloads its 1.8 GB language model; the realm plays by its rules until the model is ready."
mkdir -p build && cp "$DMG" build/
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
