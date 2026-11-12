#!/bin/zsh
# A guard (integration audit #19, docs/research/integration-audit-2026-11-12.md): no stale .uid files. Godot writes a
# .uid beside every script; when the script goes, its .uid must go with it, or the project keeps a dead id that a
# new file can collide with. Lists each .uid in realm/scripts and realm/tools whose script is gone; exits 1 if any.
#   zsh realm/tools/uid_probe.sh
cd "${0:A:h}/.."
bad=0
for u in scripts/**/*.uid(N) tools/**/*.uid(N); do
  if [[ ! -f ${u%.uid} ]]; then print "UID stale: $u (its script ${${u%.uid}:t} is gone)"; bad=1; fi
done
(( bad )) && print "UID FAIL" || print "UID PASS"
exit $bad
