#!/bin/zsh
# Every Meshy piece that has landed (data/meshy.json pieces; downloads in ~/code/goc-kits/meshy/<src>/) through
# realm/tools/meshy_import.py (Blender, headless, CPU) into realm/assets/meshy/<name>/. A piece not downloaded yet
# is skipped and named. Then, only if asked: --godot-import lets Godot import the new files (one headless editor
# pass; it touches .godot, so only when no other Godot runs), --r2 copies the art to the R2 bucket
# (realm/tools/r2_sync.sh: binaries stay out of git, as .gitignore says).
#   realm/tools/meshy_import.sh [--godot-import] [--r2]
R=${0:A:h:h:h}
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
for name in $(python3 -I -c "import json; print(' '.join(json.load(open('$R/realm/data/meshy.json'))['pieces']))"); do
  out=$("$BLENDER" -b --factory-startup -P $R/realm/tools/meshy_import.py -- $name 2>&1 | grep "^MESHY")
  echo "${out:-MESHY $name: Blender said nothing (see its log)}"
done
if [[ " $* " == *" --godot-import "* ]]; then
  pgrep -f "godot" > /dev/null && { echo "MESHY a Godot is running: import later (arch -arm64 godot --headless --path realm --import)"; } || arch -arm64 godot --headless --path $R/realm --import > /dev/null 2>&1 && echo "MESHY imported into Godot"
fi
[[ " $* " == *" --r2 "* ]] && $R/realm/tools/r2_sync.sh
