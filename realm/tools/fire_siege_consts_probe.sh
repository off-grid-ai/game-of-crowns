#!/bin/zsh
# A guard (integration audit #20, "Move gameplay knobs to data rows"; READY.md line 15): the fire-and-siege thread's
# scripts keep no numeric gameplay const; a knob lives in a data row with its docs/TUNING.md line. Engine and
# render constants stay in code (named in ENGINE below, each with why). Counts what is left; exits 1 if any.
#   zsh realm/tools/fire_siege_consts_probe.sh
cd "${0:A:h}/.."
files=(scripts/towns.gd scripts/town_layout.gd scripts/town_fields.gd scripts/town_banners.gd scripts/walls.gd scripts/stone_wall.gd scripts/fire.gd scripts/siege_camp.gd scripts/scene_kinds/siege.gd scripts/scene_kinds/sack.gd)
# BUILD_BUDGET_MS: a frame's time budget for building (performance); SMOKE_LAYER: a render layer bit; FAR: a fire's draw distance (render).
ENGINE='^(BUILD_BUDGET_MS|SMOKE_LAYER|FAR)$'
left=()
for f in $files; do
  for n in $(grep -hoE '^(static )?const [A-Z_][A-Z0-9_]* *(: *[A-Za-z0-9]+)? *:?= *(-?[0-9.]+|Vector[23]i?\(|Color\(|\[ *-?[0-9])' $f | sed -E 's/^(static )?const ([A-Z0-9_]+).*/\2/'); do
    [[ $n =~ $ENGINE ]] || left+=("${f:t}:$n")
  done
done
print "CHECK fire-siege gameplay consts left in code: ${#left} ${left[*]}: $( (( ${#left} )) && print FAIL || print PASS)"
(( ${#left} == 0 ))
