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
fail=0
check() {  # rule, pattern, files exempt (regex on the path)
  local rule=$1 pat=$2 exempt=$3
  for hit in $(grep -lE "$pat" scripts/*.gd | grep -vE "$exempt"); do
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
# one-way-to-move, the tween form: a tween_method whose lambda sets a position (within its first lines) walks a
# body by hand. A thrown thing (an arrow, a stone) flies an arc (`(1.0 - t)` in or just above it) and is not travel.
check_tween() {
  local rule="one-way-to-move-tween"
  for f in scripts/*.gd; do
    [[ $f == scripts/mover.gd ]] && continue
    local hits=$(awk '{b[FNR]=$0} END{for(l=1;l<=FNR;l++) if(b[l] ~ /tween_method\(/){w=""; for(i=l;i<=l+4&&i<=FNR;i++) w=w"\n"b[i]; a=""; for(i=(l>8?l-8:1);i<=l+4&&i<=FNR;i++) a=a"\n"b[i]; if(w ~ /position *=[^=]/ && a !~ /\(1\.0 - t\)/) print FILENAME":"l": "b[l]}}' $f)
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
for f in $(grep -lE 'Engine\.set_meta\(' scripts/*.gd); do
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
exit $fail
