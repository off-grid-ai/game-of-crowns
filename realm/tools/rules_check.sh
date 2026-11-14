#!/bin/zsh
# The project's architecture rules, checked (CLAUDE.md): a rule nobody checks drifts. Run before committing
# realm/scripts changes; prints each breach as file:line and exits 1 if any. Known breaches being moved onto the
# one way are listed in tools/rules_known.txt (file:rule); the list only ever shrinks.
#   one-way-to-move: nothing but mover.gd tweens or path-follows a body's position to travel.
#   One store (docs/TOWN_LIFE.md, goc-cpto): Freeciv -> bridge -> /world -> awareness.gd; everything else reads it.
#   raw-world: no script but the store (awareness.gd) and the bridge's client (bridge.gd) takes /world itself:
#     no world_updated connection, no `world: Dictionary` parameter, no read of bridge.world, no copy of its own.
#   view-fetch: no script but bridge.gd asks the bridge itself (an HTTPRequest of its own, or the bridge's address).
#   cross-mind-write: no script but the store writes into another mind's blackboard (x.blackboard.set_var,
#     get("blackboard"), or a blackboard taken from another node); a mind writes only its own `blackboard`.
cd "${0:A:h}/.."
known=tools/rules_known.txt
# Every game script, in every scripts subfolder (scene_kinds, town_dress...); scripts/tools holds probes, not the game.
srcs=(${(f)"$(print -l scripts/**/*.gd | grep -v '^scripts/tools/')"})
fail=0
check() {  # rule, pattern, files exempt (regex on the path)
  local rule=$1 pat=$2 exempt=$3
  for hit in $(grep -lE "$pat" $srcs | grep -vE "$exempt"); do
    if grep -qx "$hit:$rule" $known 2>/dev/null; then continue; fi
    grep -nE "$pat" $hit | sed "s#^#$hit:#;s#\$#   <- $rule#"
    fail=1
  done
  # A known breach that's gone comes off the list in the same change: the list only shrinks.
  for f in $(grep -E ":$rule\$" $known 2>/dev/null | cut -d: -f1); do
    if [[ ! -f $f ]] || ! grep -qE "$pat" $f; then echo "$f:$rule   <- fixed: take it off $known"; fail=1; fi
  done
}
check "one-way-to-move" 'tween_property\([^,]*, *"(global_)?position"|PathFollow3D\.new\(\)' \
  'scripts/(mover|intro|news_chips)\.gd'  # intro and news chips: screen-space UI slides, not travel
check "raw-world" 'world_updated\.connect|func [A-Za-z0-9_]+\([^)]*\bworld: Dictionary|bridge\.world\b|^var world\b|\.world = ' \
  'scripts/(awareness|bridge)\.gd'
check "view-fetch" 'HTTPRequest\.new\(\)|bridge\.BASE|bridge\.gd"\)\.BASE|127\.0\.0\.1:8787' \
  'scripts/(bridge|app_services)\.gd'  # app_services starts the packaged bridge; it asks it nothing
check "cross-mind-write" '[A-Za-z0-9_)]\.blackboard\.set_var\(|get\("blackboard"\)|=[^=]*[A-Za-z0-9_)]\.blackboard[[:space:]]*(#.*)?$' \
  'scripts/awareness\.gd'
# one-way-to-move, the tween form: a tween_method whose lambda sets a position anywhere in its body (the lines indented
# under it) walks a body by hand across the map. A thrown thing (an arrow, a stone) flies an arc (`(1.0 - t)` in it or
# just above it) and is not travel. Every scripts subfolder (scene_kinds, town_dress...) is scanned.
check_tween() {
  local rule="one-way-to-move-tween"
  for f in $srcs; do
    [[ $f == scripts/mover.gd ]] && continue
    local hits=$(awk 'function ind(x){match(x, /^\t*/); return RLENGTH} {b[FNR]=$0} END{for(l=1;l<=FNR;l++) if(b[l] ~ /tween_method\(/){w=b[l]; for(i=l+1;i<=FNR&&(b[i] ~ /^[ \t]*$/ || ind(b[i])>ind(b[l]));i++) w=w"\n"b[i]; a=w; for(i=(l>8?l-8:1);i<l;i++) a=a"\n"b[i]; if(w ~ /position *=[^=]/ && a !~ /\(1\.0 - t\)/) print FILENAME":"l": "b[l]}}' $f)
    if [[ -n $hits ]]; then
      grep -qx "$f:$rule" $known 2>/dev/null && continue
      print -r -- "$hits" | sed "s#\$#   <- $rule#"; fail=1
    elif grep -qx "$f:$rule" $known 2>/dev/null; then
      echo "$f:$rule   <- fixed: take it off $known"; fail=1
    fi
  done
}
check_tween
#   one-writer: each fact has one writer (goc-cpto, docs/GROUND_TRUTH.md). The store's scopes are written only by the
#   store; a fact in tools/facts.txt (key owner) is set only by its owner; Engine holds handles, never a copy of a fact
#   (the allowed Engine keys are the facts.txt rows marked engine).
check "one-writer" '(\brealm|town\([^)]*\))\.set_var\(' 'scripts/awareness\.gd'
facts=tools/facts.txt
while read -r key owner scope; do
  [[ -z $key || $key == \#* || $scope == engine ]] && continue
  check "one-writer-$key" "set_meta\\(\"$key\"" "$owner"
done < $facts
allowed=$(awk '$3=="engine"{printf "%s%s", s, $1; s="|"}' $facts)
for f in $(grep -lE 'Engine\.set_meta\(' $srcs); do
  hits=$(grep -nE 'Engine\.set_meta\(' $f | grep -vE "Engine\.set_meta\(\"($allowed)\"")
  if [[ -n $hits ]]; then
    grep -qx "$f:engine-copy" $known 2>/dev/null && continue
    print -r -- "$hits" | sed "s#^#$f:#;s#\$#   <- engine-copy#"; fail=1
  elif grep -qx "$f:engine-copy" $known 2>/dev/null; then
    echo "$f:engine-copy   <- fixed: take it off $known"; fail=1
  fi
done
#   one-scale: metres to world units is Units.M (scripts/world_units.gd); no script keeps its own 0.12 (audit #17).
check "one-scale" '^const [A-Z_]*(S|SCALE) := 0\.12\b' 'scripts/world_units\.gd'
#   one-loader: realm/data is read only through data.gd (Data.read/value/num); one-colour: a data colour becomes a
#   Color only through Data.colour (audit #18).
check "one-loader" 'FileAccess\.(open|get_file_as_string)\(("res://data/|DATA\b)|"res://data/[a-z_]+\.json"' 'scripts/data\.gd'
check "one-colour" 'func _rgb|Color\(float\([A-Za-z_]+\[0\]\), *float\([A-Za-z_]+\[1\]\), *float\([A-Za-z_]+\[2\]\)' 'scripts/data\.gd'
#   unread-switch: every switch a launch script hands the game (realm/tools render/play/stills/media.sh, the rounds in
#   docs/review/*.sh) is read by some script (its "--name in a .gd), so a switch that does nothing can't ride a launch
#   line (the look audit, a65fa3c3). Godot's, git's and the apply scripts' own flags are not the game's.
not_game='path|headless|resolution|fixed-fps|audio-driver|import|check|oneline'
launch=(tools/render.sh tools/play.sh tools/stills.sh tools/media.sh ../docs/review/*.sh)
for sw in $(grep -hv '^[[:space:]]*#' $launch | grep -oE -- '--[a-z][a-z0-9-]*' | sort -u); do
  [[ ${sw#--} =~ "^($not_game)\$" ]] && continue
  grep -qF -- "\"$sw" scripts/**/*.gd tools/*.gd 2>/dev/null && continue
  echo "$sw   <- unread-switch: passed by $(grep -lv '^[[:space:]]*#' $launch | xargs grep -l -- "$sw" | tr '\n' ' ')but read by no script"; fail=1
done
#   one-ground: where a body may stand is ground.gd's one answer (Mac: 'OOP, SOLID, SRP, SSOT, DRY'; troops in the
#   sea and townsfolk in houses were every placer's own idea of clear ground). No script but the ground and the walk
#   maps it shares footprints with (nav_ground, town_nav, army_ground) reads the footprints off what's standing; and no
#   script that sets down people, beasts, carts or camps asks the terrain for land or water itself: it asks
#   Ground.is_clear / nearest_clear / area_clear.
check "one-ground" 'inside_something\(|NavGround\.all\(|TownNav\.footprints\(' \
  'scripts/(ground|nav_ground|town_nav|army_ground)\.gd'
placers=(${(f)"$(print -l scripts/{scenes,units,villagers,control,npc_mind,town_life,town_scenes,castle_life,castle_folk,gold_mines,siege_camp,camp_kit,animals,army,army_*}.gd scripts/scene_kinds/*.gd scripts/town_dress/*.gd(N) | grep -vE 'scripts/(army_ground|town_dress/quay)\.gd')"})  # quay: turns its edge to the water, sets nobody down
for f in $placers; do
  [[ -f $f ]] || continue
  hits=$(grep -nE 'terrain\.(is_land|walkable)\(' $f)
  if [[ -n $hits ]]; then
    grep -qx "$f:one-ground-water" $known 2>/dev/null && continue
    print -r -- "$hits" | sed "s#^#$f:#;s#\$#   <- one-ground-water#"; fail=1
  elif grep -qx "$f:one-ground-water" $known 2>/dev/null; then
    echo "$f:one-ground-water   <- fixed: take it off $known"; fail=1
  fi
done
#   asset-exists: every asset file the game loads (docs/art/assets-loaded.txt, generated by tools/asset_manifest.py) is
#   in the shared tree's realm/assets, the art's one home (Mac, 2026-11-12: the art stays local, never in git; a copy
#   links it with tools/link_assets.sh). A loaded file gone from it fails.
manifest=../docs/art/assets-loaded.txt
if [[ -f $manifest ]]; then
  while IFS= read -r p; do
    [[ -e $p ]] || { echo "$p: the game loads it and realm/assets hasn't it   <- asset-exists"; fail=1; }
  done < <(grep -v '^#' $manifest | cut -f1 | sed 's#^res://##')
fi
exit $fail
