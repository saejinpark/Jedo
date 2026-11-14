#!/bin/zsh
# Renders the app icon into the asset catalog.
set -e
here=${0:A:h}
root=$here/../..
tmp=$(mktemp -d)
swiftc -O -module-name Icon $root/Jedo/Core/FrenchCurveData.swift $here/main.swift -o $tmp/icon
$tmp/icon $root/Jedo/Assets.xcassets/AppIcon.appiconset/AppIcon.png
