#!/bin/bash
# Makes the fixed starts as one chain of snapshots, each run on from the last (tools/baseline-chain.mjs):
#   baseline/aldmere_founding  the world built once (turn 1)
#   baseline/aldmere_year_one  run on from the founding to the spring of year one ("Aldmere, year one")
#   baseline/aldmere           run on from year one to nine years in ("Aldmere, nine years in")
# Headless, on a private bridge and Freeciv (8791/5591); every new Aldmere chronicle copies one (chronicles.js create).
# After it: bake the starts' views again (realm/tools/bake.gd).
#   tools/make-baseline.sh [--seed 1066] [--pace 3]
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
exec node tools/baseline-chain.mjs "$@"
