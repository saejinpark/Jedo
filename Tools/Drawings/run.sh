#!/bin/sh
# Draws the example drawings through the app's own engine in the booted
# simulator (a Debug build must be installed) and copies the exported
# papers to Tools/Drawings/examples.
set -e
here=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
python3 "$here/gen.py" "$tmp"
data=$(xcrun simctl get_app_container booted dev.pinocchio.Jedo data)
cp "$tmp"/*.json "$data/Documents/"
for name in plan skirt manga; do
  xcrun simctl terminate booted dev.pinocchio.Jedo 2>/dev/null || true
  rm -f "$data/Documents/$name.png"
  xcrun simctl launch booted dev.pinocchio.Jedo -JedoScript "$name" >/dev/null
  for _ in $(seq 1 40); do [ -f "$data/Documents/$name.png" ] && break; sleep 1; done
  sleep 1
  sips -Z 1400 "$data/Documents/$name.png" --out "$here/examples/$name.png" >/dev/null
done
xcrun simctl terminate booted dev.pinocchio.Jedo 2>/dev/null || true
