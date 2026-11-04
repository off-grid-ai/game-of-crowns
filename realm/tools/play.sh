#!/bin/zsh
# Play the running game by hand, from inside it (a test aid). Start the game with
# GOC_HAND=/tmp/goc-hand ./realm.sh, then send it steps, one per argument:
#   realm/tools/play.sh "tap court" "wait 1" "snap /abs/path/01.jpg" "look court"
# Steps are autoplay.gd's: wait s, tap action, hold action s, key K, click fx fy,
# snap path(.jpg|.png), look note, city Name dist. Prints what the game shows after.
DIR=${GOC_HAND:-/tmp/goc-hand}
rm -f $DIR/done.txt
print -l -- "$@" > $DIR/cmd.tmp && mv $DIR/cmd.tmp $DIR/cmd.txt
for i in {1..300}; do
  [ -f $DIR/done.txt ] && { cat $DIR/done.txt; echo; exit 0; }
  sleep 0.5
done
echo "the game didn't answer (is it running with GOC_HAND=$DIR?)"; exit 1
