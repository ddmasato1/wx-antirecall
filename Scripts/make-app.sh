#!/bin/bash
# Assembles AntiRecall.app from SwiftPM build products. Uses only system tools.
#
#   ARCHS="arm64"          (default) — matches reality: the silent patches are arm64-only.
#   ARCHS="arm64 x86_64"   universal — cosmetic.
#   CODESIGN_ID="-"        (default) — ad-hoc. Set to a Developer ID to sign properly.
#
# Output: dist/AntiRecall.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="AntiRecall"
GUI="WeChatAntiRecallGUI"
CLI="wechat-antirecall"
BUNDLE_ID="com.github.fzlzjerry.wechatantirecall"
SIGN_ID="${CODESIGN_ID:--}"
ARCHS="${ARCHS:-arm64}"
SHORT_VERSION="${APP_VERSION:-1.0.0}"
BUILD_NUMBER="${APP_BUILD:-1}"

echo ">> Building ($ARCHS, release)..."
FLAGS=(-c release --disable-sandbox)
for a in $ARCHS; do FLAGS+=(--arch "$a"); done
swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)"

APP="$ROOT/dist/$APP_NAME.app"
echo ">> Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/$GUI"          "$APP/Contents/MacOS/$GUI"
cp "$BIN/$CLI"          "$APP/Contents/Resources/$CLI"
cp "$ROOT/patches.json" "$APP/Contents/Resources/patches.json"

ICON_KEY=""
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY="  <key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>$GUI</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>微信防撤回</string>
  <key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
$ICON_KEY
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo ">> Code signing (nested first, bundle last)..."
# The CLI runs as its own process, so sign it before sealing the bundle.
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/Resources/$CLI"
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP/Contents/MacOS/$GUI"
codesign --force --timestamp=none --sign "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo ">> Done: $APP"
