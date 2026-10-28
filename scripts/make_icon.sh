#!/bin/zsh
# Renders the Quill logo (Views/Logo.swift) into Resources/AppIcon.icns.
set -euo pipefail
ROOT="${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$ROOT"
swift build -c release --product Quill >/dev/null
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
.build/release/Quill --render-icon "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/AppIcon.iconset/icon_512x512@2x.png" Resources/AppIcon.png
echo "Wrote Resources/AppIcon.icns"
