#!/bin/zsh
# The project's architecture rules, checked (CLAUDE.md): a rule nobody checks drifts. Run before committing
# realm/scripts changes; prints each breach as file:line and exits 1 if any. Known breaches being moved onto the
# one way are listed in tools/rules_known.txt (file:rule); the list only ever shrinks.
#   one-way-to-move: nothing but mover.gd tweens or path-follows a body's position to travel.
#   One store (docs/TOWN_LIFE.md, goc-cpto): Freeciv -> bridge -> /world -> awareness.gd; everything else reads it.
#   raw-world: no script but the store (awareness.gd) and the bridge's client (bridge.gd) takes /world itself:
#     no world_updated connection, no `world: Dictionary` parameter, no read of bridge.world.
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
}
check "one-way-to-move" 'tween_property\([^,]*, *"(global_)?position"|PathFollow3D\.new\(\)' \
  'scripts/(mover|intro|news_chips)\.gd'  # intro and news chips: screen-space UI slides, not travel
check "raw-world" 'world_updated\.connect|func [A-Za-z0-9_]+\([^)]*\bworld: Dictionary|bridge\.world\b' \
  'scripts/(awareness|bridge)\.gd'
check "view-fetch" 'HTTPRequest\.new\(\)|bridge\.BASE|bridge\.gd"\)\.BASE|127\.0\.0\.1:8787' \
  'scripts/(bridge|app_services)\.gd'  # app_services starts the packaged bridge; it asks it nothing
check "cross-mind-write" '[A-Za-z0-9_)]\.blackboard\.set_var\(|get\("blackboard"\)|=[^=]*[A-Za-z0-9_)]\.blackboard[[:space:]]*(#.*)?$' \
  'scripts/awareness\.gd'
exit $fail
