#!/bin/zsh
# A guard (integration audit, "Less hand code": the siege engine and crew hand-lerped, siege_camp.gd): the ram and
# the siege tower travel to the wall the one way everything moves (CLAUDE.md "One way to move", mover.gd): the engine
# goes by its Mover, its crew push behind by theirs (toward), and nothing in siege_camp.gd lerps a body's position
# along its way. Exits 1 on a fail.
#   zsh realm/tools/siege_roll_probe.sh
cd "${0:A:h}/.."
f=scripts/siege_camp.gd
bad=0
grep -nE '\.lerp\(g\["to"\]|global_position = scenes\.(ground|stand)\(.*(lerp|- dir \* )' $f && { print "ROLL FAIL: siege_camp.gd sets a rolling engine's or its crew's position by hand"; bad=1; }
grep -qE 'Mover\.of\(m\)\.go\(|Mover\.of\(node\)\.go\(' $f || { print "ROLL FAIL: the engine doesn't go to the wall by its Mover"; bad=1; }
grep -qE '\.toward\(' $f || { print "ROLL FAIL: the crew don't push behind by their Movers (toward)"; bad=1; }
(( bad )) || print "ROLL PASS"
exit $bad
