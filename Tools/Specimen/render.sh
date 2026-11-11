#!/bin/zsh
# Renders pencil specimens with the app's Core code. Output: Tools/Specimen/out/
set -e
here=${0:A:h}
root=$here/../..
mkdir -p $here/out
swiftc -O -module-name Specimen \
  $root/Jedo/Core/*.swift $here/main.swift -o $here/out/specimen 2>&1 | grep -v "^$" || true
time $here/out/specimen $here/out
