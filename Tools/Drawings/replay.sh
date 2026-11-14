#!/bin/sh
# Draws a script through the app in the booted simulator: replay.sh script.json [pace seconds] [pictures...]
# Without a pace it draws at once and prints where the exported paper is.
set -e
json=$1; pace=$2; name=$(basename "$json" .json)
data=$(xcrun simctl get_app_container booted dev.pinocchio.Jedo data)
cp "$json" "$data/Documents/"; shift; [ $# -gt 0 ] && shift
for f in "$@"; do cp "$f" "$data/Documents/"; done
xcrun simctl terminate booted dev.pinocchio.Jedo 2>/dev/null || true
rm -f "$data/Documents/$name.png" "$data/Documents/$name.txt"
if [ -n "$pace" ] && [ "$pace" != 0 ]; then
  xcrun simctl launch booted dev.pinocchio.Jedo -JedoScript "$name" -JedoPace "$pace" >/dev/null
else
  xcrun simctl launch booted dev.pinocchio.Jedo -JedoScript "$name" >/dev/null
  n=0; until [ -f "$data/Documents/$name.txt" ] || [ $n -gt 90 ]; do sleep 1; n=$((n+1)); done
  cat "$data/Documents/$name.txt"; echo "$data/Documents/$name.png"
fi
