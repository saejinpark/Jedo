#!/bin/sh
# Copies the stroke log off the iPad (or a booted simulator with --sim) and summarises it.
set -e
cd "$(dirname "$0")"
DEVICE=${DEVICE:?set DEVICE to your iPad identifier from: xcrun devicectl list devices}
OUT=${OUT:-./strokes.jsonl}
if [ "$1" = "--sim" ]; then
  cp "$(xcrun simctl get_app_container booted dev.pinocchio.Jedo data)/Documents/strokes.jsonl" "$OUT"
else
  xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier dev.pinocchio.Jedo --source Documents/strokes.jsonl --destination "$OUT" >/dev/null
fi
python3 summary.py "$OUT" "${2:-40}"
