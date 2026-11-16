#!/usr/bin/env bash
#
# Cut a public Mac release: build and sign Game of Crowns on this machine from what's on
# GitHub (origin/main; not the working tree, which other sessions may have half-changed), then
# publish the dmg as a GitHub Release of that commit.
#
# The build runs in a scratch folder: the committed files from `git archive origin/main`, plus the
# third-party art and Godot's import cache hard-linked from this working copy (the art stays out
# of git by licence, and hard links cost no disk).
#
# Needs: a Developer ID Application identity in the keychain. Notarising is GitHub's (.github/workflows/notarise.yml,
#   with the App Store Connect key in the repo's secrets): this uploads the signed dmg to a draft release and starts it;
#   the workflow notarises, staples and publishes. NOTES_FILE: the release notes (default: the short line below).
# Usage: packaging/release-mac.sh [--prerelease] [--version X.Y] [commit]   (commit: a pushed commit; default origin/main)
# --version stamps the build with X.Y (realm/export_presets.cfg in the scratch copy) and records it in this working copy.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
REPO=off-grid-ai/game-of-crowns
FLAG=""; [ "${1:-}" = "--prerelease" ] && { FLAG="--prerelease"; shift; }
STAMP=""; [ "${1:-}" = "--version" ] && { STAMP="$2"; shift 2; }
WANT="${1:-origin/main}"

security find-identity -v -p codesigning | grep -q "Developer ID Application" || { echo "!! no Developer ID Application identity in the keychain"; exit 1; }

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
if [ -n "$STAMP" ]; then
  sed -i '' -E "s/^(application\/(short_)?version=)\"[^\"]*\"/\1\"$STAMP\"/" "$SRC/realm/export_presets.cfg"
fi

echo "==> Art and import cache (hard links)"
git ls-files -o -i --exclude-standard realm/assets > "$SRC/.art-list"
rsync -a --link-dest="$ROOT/" --files-from="$SRC/.art-list" "$ROOT/" "$SRC/"
rm "$SRC/.art-list"
[ -d realm/.godot ] && rsync -a --link-dest="$ROOT/realm/.godot/" "$ROOT/realm/.godot/" "$SRC/realm/.godot/"

echo "==> Build, sign, notarise"
"$SRC/packaging/build-mac.sh"

DMG=$(ls "$SRC"/build/Game-of-Crowns-*-arm64.dmg)
codesign --verify --verbose "$DMG"

VERSION=$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' "$SRC/realm/export_presets.cfg")
TAG="v$VERSION-$(date +%Y%m%d)-$SHA"
echo "==> Draft release $TAG, then notarised and published on GitHub (.github/workflows/notarise.yml)"
NOTES=(--notes "Free, nothing locked. For Macs with Apple Silicon. Open the dmg and drag Game of Crowns to Applications. Want the lords to speak in their own words? Run Off Grid AI (https://getoffgridai.co/desktop) alongside it.")
[ -n "${NOTES_FILE:-}" ] && NOTES=(--notes-file "$NOTES_FILE")
gh release create "$TAG" "$DMG" --draft $FLAG -R "$REPO" --target "$FULL" --title "Game of Crowns $VERSION ($SHA)" "${NOTES[@]}"
gh workflow run notarise.yml -R "$REPO" -f tag="$TAG"
mkdir -p build && cp "$DMG" build/
if [ -n "$STAMP" ]; then
  sed -i '' -E "s/^(application\/(short_)?version=)\"[^\"]*\"/\1\"$STAMP\"/" realm/export_presets.cfg
  git commit -q -m "Version $STAMP (released as $TAG)" -- realm/export_presets.cfg || true
fi
echo "==> Drafted: https://github.com/$REPO/releases/tag/$TAG (published once notarised: gh run list -R $REPO -w notarise.yml)"
