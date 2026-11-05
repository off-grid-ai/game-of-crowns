#!/usr/bin/env bash
#
# Cut a public Mac release on this machine: build, sign and notarise Game of Crowns from what's on
# GitHub (origin/main; not the working tree, which other sessions may have half-changed), then
# publish the dmg as a GitHub Release of that commit.
#
# The build runs in a scratch folder: the committed files from `git archive origin/main`, plus the
# third-party art and Godot's import cache hard-linked from this working copy (the art stays out
# of git by licence, and hard links cost no disk).
#
# Needs: a Developer ID Application identity in the keychain, and for notarisation
#   APPLE_API_KEY (path to the .p8), APPLE_API_KEY_ID, APPLE_API_ISSUER
# Usage: packaging/release-mac.sh [--prerelease] [commit]   (commit: a pushed commit; default origin/main)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=off-grid-ai/game-of-crowns
FLAG=""; [ "${1:-}" = "--prerelease" ] && { FLAG="--prerelease"; shift; }
WANT="${1:-origin/main}"

for v in APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  [ -n "${!v:-}" ] || { echo "!! $v is not set"; exit 1; }
done

git fetch -q origin main
FULL=$(git rev-parse "$WANT^{commit}")
SHA=$(git rev-parse --short "$FULL")
git merge-base --is-ancestor "$FULL" origin/main || { echo "!! $SHA is not on origin/main (push it first)"; exit 1; }
SRC=$(mktemp -d "$HOME/.goc-release.XXXXXX")
trap 'rm -rf "$SRC"' EXIT
echo "==> Building $SHA"
git archive "$FULL" | tar -x -C "$SRC"
# The packaging tools come from this working copy, so a fix to them applies before it is pushed.
cp "$ROOT/packaging/build-mac.sh" "$SRC/packaging/build-mac.sh"

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
gh release create "$TAG" "$DMG" $FLAG -R "$REPO" --target "$FULL" \
  --title "Game of Crowns $VERSION ($SHA)" \
  --notes "Free, nothing locked. For Macs with Apple Silicon. Open the dmg and drag Game of Crowns to Applications. Want the lords to speak in their own words? Run Off Grid AI (https://github.com/off-grid-ai) alongside it."
mkdir -p build && cp "$DMG" build/
echo "==> Done: https://github.com/$REPO/releases/tag/$TAG"
