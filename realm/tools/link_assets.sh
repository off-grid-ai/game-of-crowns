#!/bin/zsh
# A copy of the game (a film's git-archive copy, a probe's scratch copy, a worktree) uses the shared tree's art, never a
# second set (Mac, 2026-11-12: the art stays local; the shared tree's realm/assets is its one home). This links the
# copy's realm/assets to the shared tree's, and its realm/.godot (Godot's import cache of that art, 7 GB) too, so the
# copy draws exactly what the shared tree draws and imports nothing of its own. Whatever the copy held there before
# (git archive brings only fragments: .import files, licences) is replaced by the link.
#   zsh realm/tools/link_assets.sh <copy root>        the folder that holds the copy's realm/ (e.g. /tmp/film/)
#   zsh realm/tools/link_assets.sh <copy root> --own-cache   link the art only; the copy imports into its own .godot
# Checked by realm/tools/rules_check.sh asset-exists: every asset the game loads is in the shared tree.
set -e
SHARED=${0:A:h:h}  # the shared tree's realm/
[[ $# -ge 1 ]] || { print "usage: link_assets.sh <copy root> [--own-cache]"; exit 2; }
COPY=${1:A}/realm
[[ -d $COPY ]] || { print "link_assets: no realm/ in $1"; exit 1; }
[[ $COPY != $SHARED ]] || { print "link_assets: $1 is the shared tree itself"; exit 1; }
links=(assets)
[[ $2 == --own-cache ]] || links+=(.godot)
for x in $links; do
  if [[ -L $COPY/$x ]]; then
    rm $COPY/$x
  elif [[ -e $COPY/$x ]]; then
    rm -rf $COPY/$x  # the copy's own fragments of it: never a second set
  fi
  ln -s $SHARED/$x $COPY/$x
  print "link_assets: $COPY/$x -> $SHARED/$x"
done
