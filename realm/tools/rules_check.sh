#!/bin/zsh
# The project's architecture rules, checked (CLAUDE.md): a rule nobody checks drifts. Run before committing
# realm/scripts changes; prints each breach as file:line and exits 1 if any. Known breaches being moved onto the
# one way are listed in tools/rules_known.txt (file:rule); the list only ever shrinks.
#   One way to move: nothing but mover.gd tweens or path-follows a body's position to travel.
cd "${0:A:h}/.."
known=tools/rules_known.txt
fail=0
check() {  # rule, pattern
  local rule=$1 pat=$2
  for hit in $(grep -lE "$pat" scripts/*.gd | grep -v "scripts/mover.gd" | grep -vE "scripts/(intro|news_chips).gd"); do  # screen-space UI slides, not travel
    if grep -qx "$hit:$rule" $known 2>/dev/null; then continue; fi
    grep -nE "$pat" $hit | sed "s#^#$hit:#;s#\$#   <- $rule#"
    fail=1
  done
}
check "one-way-to-move" 'tween_property\([^,]*, *"(global_)?position"|PathFollow3D\.new\(\)'
exit $fail
