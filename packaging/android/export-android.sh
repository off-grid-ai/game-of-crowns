#!/bin/bash
# Android export from a private real copy: textures capped at 1024 px, re-imported, then exported.
# First: cp -a realm ~/goc-android/realm (never export from the shared tree) and append
# packaging/android/android-preset.cfg to the copy's export_presets.cfg.
set -uo pipefail
R=~/goc-android/realm; cd $R
n=0
while IFS= read -r f; do
  if grep -q '^process/size_limit=' "$f"; then sed -i 's/^process\/size_limit=.*/process\/size_limit=1024/' "$f"
  else sed -i 's/^\[params\]$/[params]\n\nprocess\/size_limit=1024/' "$f"; fi
  n=$((n+1))
done < <(grep -rl --include='*.import' '^importer="texture"' .)
echo "textures capped: $n"
pgrep -af '[g]odot --path' | grep -v tailscaled
/usr/bin/time -f "import %e s" ~/.local/bin/godot --headless --path . --import > ../import.log 2>&1
tail -1 ../import.log; echo "import errors: $(grep -c ERROR ../import.log)"
rm -f ../goc.apk
/usr/bin/time -f "export %e s" ~/.local/bin/godot --headless --path . --export-debug Android ../goc.apk > ../export.log 2>&1
grep -E "ERROR|apksigner|export " ../export.log | sort | uniq -c | head
ls -la ../goc.apk
unzip -l ../goc.apk | tail -1
