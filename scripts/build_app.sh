#!/bin/zsh
# Builds Quill with Xcode's toolchain and assembles build/Quill.app.
# Usage: scripts/build_app.sh [debug|release]   (default: release)
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIG="${1:-release}"
XCODE_CONFIG=$([[ "$CONFIG" == "debug" ]] && echo Debug || echo Release)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

cd "$ROOT"
DERIVED="$ROOT/build/DerivedData"
APP="$ROOT/build/Quill.app"

echo "==> xcodebuild ($XCODE_CONFIG) using $DEVELOPER_DIR"
xcodebuild -scheme Quill -configuration "$XCODE_CONFIG" -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" -skipPackagePluginValidation build \
  | grep -E "error:|warning: unre|BUILD (SUCCEEDED|FAILED)|\*\*" || true
PRODUCTS="$DERIVED/Build/Products/$XCODE_CONFIG"
[[ -x "$PRODUCTS/Quill" ]] || { echo "Build failed: $PRODUCTS/Quill missing"; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$PRODUCTS/Quill" "$APP/Contents/MacOS/Quill"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# SwiftPM resource bundles (if any dependency ships them).
for b in "$PRODUCTS"/*.bundle(N); do cp -R "$b" "$APP/Contents/Resources/"; done
# Dynamic frameworks (if any).
for f in "$PRODUCTS"/PackageFrameworks/*.framework(N); do cp -R "$f" "$APP/Contents/Frameworks/"; done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Quill" 2>/dev/null || true

rmdir "$APP/Contents/Frameworks" 2>/dev/null || true
# Prefer the stable local identity (scripts/create_signing_identity.sh) so macOS keeps
# Accessibility/Microphone grants across rebuilds; fall back to ad-hoc.
IDENTITY=$(security find-identity -p codesigning 2>/dev/null | awk '/"Dictate Local Signing"/ {print $2; exit}')
SIGN_ID="${IDENTITY:--}"
[[ -n "$IDENTITY" ]] && echo "==> Signing (Dictate Local Signing)" || echo "==> Signing (ad-hoc)"
# ~/Documents may be iCloud-synced, which attaches xattrs that codesign rejects.
xattr -cr "$APP"
codesign --force --deep --options runtime --entitlements Resources/Quill.entitlements --sign "$SIGN_ID" "$APP"
codesign --verify --verbose=1 "$APP"
echo "==> Done: $APP"
