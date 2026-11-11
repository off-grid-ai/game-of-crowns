#!/bin/zsh
# Local image-to-3D for the bake-off catalogue: TRELLIS (v1, MIT) on Apple Silicon via trellis-mac-mps,
# open models only (DINOv2, TRELLIS-image-large). Backgrounds cut by cutout.py, so no rembg model.
#   realm/tools/bakeoff/local_batch.sh <bakeoff dir> [names...]   (default: the catalogue in visibility order)
# Skips names whose <name>_trellis.glb exists. Uses the Mac GPU: run only when no render is queued.
B=$1; shift
T=~/code/ai3d/trellis-mac-mps
PY=$T/.venv/bin/python
HERE=${0:A:h}
NAMES=(farmhouse_barn armoury unit_knight unit_man_at_arms unit_spearman unit_archer unit_heavy_cavalry unit_war_elephant unit_axeman unit_warhammer unit_crossbowman unit_light_cavalry unit_cannon unit_general townhouse_2 townhouse_3 cottage cottage_2 cottage_3 market_stall inn church forge barracks stables mill watermill granary manor guard_tower gatehouse haystack pen well cart wagon crops trees cow chicken horse ox pig sheep goat dog barrels crates banner_pole anvil weapon_rack)
(( $# )) && NAMES=($@)
mkdir -p "$B/cutouts" "$B/ai3d"
for n in $NAMES; do
  [ -f "$B/ai3d/${n}_trellis.glb" ] && { echo "skip $n"; continue; }
  arch -arm64 $PY -I "$HERE/cutout.py" "$B/concepts/$n.png" "$B/cutouts/$n.png" || continue
  t=$SECONDS
  (cd $T && arch -arm64 env SPARSE_BACKEND=pytorch ATTN_BACKEND=sdpa PYTORCH_ENABLE_MPS_FALLBACK=1 \
    $PY scripts/run_real_pipeline.py "$B/cutouts/$n.png" ${n}_trellis --out-dir "$B/ai3d" --skip-previews --texture-size 2048) \
    > "$B/ai3d/local_$n.log" 2>&1
  [ -f "$B/ai3d/${n}_trellis.glb" ] && echo "ok $n $((SECONDS-t))s" || echo "FAILED $n (log: $B/ai3d/local_$n.log)"
done
