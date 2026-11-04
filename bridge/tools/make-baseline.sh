#!/bin/bash
# Captures a running chronicle as the Aldmere baseline: the realm some years in,
# which every new Aldmere chronicle then starts from.
#   tools/make-baseline.sh <chronicle-id>
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/chronicles/$1"
DST="$HERE/baseline/aldmere"
[ -d "$SRC/saves" ] || { echo "no such chronicle: $1"; exit 1; }
rm -rf "$DST"
mkdir -p "$DST"
# The latest save only, so the realm resumes exactly there.
mkdir -p "$DST/saves"
cp "$(ls -t "$SRC"/saves/*.sav.zst | head -1)" "$DST/saves/"
for part in state characters data; do
  [ -d "$SRC/$part" ] && cp -R "$SRC/$part" "$DST/$part"
done
for f in realm.serv world_setup.lua court.json mood.json; do
  [ -f "$SRC/$f" ] && cp "$SRC/$f" "$DST/$f"
done
rm -f "$DST/state/folk-tales.json"  # the townsfolk's stories are written fresh in each chronicle
node -e '
const fs = require("fs");
const meta = JSON.parse(fs.readFileSync(process.argv[1] + "/meta.json", "utf8"));
const world = JSON.parse(fs.readFileSync(process.argv[1] + "/state/world.json", "utf8"));
fs.writeFileSync(process.argv[2] + "/baseline.json", JSON.stringify({ from: meta.id, turn: world.turn, land: meta.land, made: Date.now() }, null, 1));
' "$SRC" "$DST"
echo "baseline captured from $1 at turn $(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1]+"/baseline.json","utf8")).turn)' "$DST")"
