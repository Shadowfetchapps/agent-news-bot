#!/bin/bash
# Build Agent News Bot, install to /Applications, then remove NewsBot.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$PROJECT_DIR/Sources"
RES="$PROJECT_DIR/Resources"
BUILD="$PROJECT_DIR/build"
APP_NAME="Agent News Bot"
BIN_NAME="AgentNewsBot"
APP_DIR="$BUILD/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"
BUNDLE_ID="ai.shadowfetch.agentnewsbot"

cd "$PROJECT_DIR"
echo "==> Cleaning"
rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

echo "==> Icon"
swift "$RES/draw_icon.swift" "$RES/icon-1024.png"
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
PNG="$RES/icon-1024.png"
sips -z 16 16 "$PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$PNG" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Compiling"
# shellcheck disable=SC2046
swiftc \
  -O \
  -whole-module-optimization \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  -framework Foundation \
  -framework Combine \
  -framework CryptoKit \
  -framework Security \
  -framework Network \
  -lsqlite3 \
  -o "$APP_DIR/Contents/MacOS/$BIN_NAME" \
  $(find "$SRC" -name '*.swift' | sort)
chmod +x "$APP_DIR/Contents/MacOS/$BIN_NAME"

echo "==> Info.plist"
cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Agent News Bot</string>
    <key>CFBundleDisplayName</key><string>Agent News Bot</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.news</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>LSUIElement</key><false/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key><true/>
    </dict>
</dict>
</plist>
EOF

echo "==> Ad-hoc sign"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Install $INSTALL_PATH"
if pgrep -f "AgentNewsBot" >/dev/null 2>&1; then
  osascript -e 'tell application "Agent News Bot" to quit' 2>/dev/null || true
  sleep 1
fi
rm -rf "$INSTALL_PATH"
cp -R "$APP_DIR" "$INSTALL_PATH"
xattr -dr com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

echo "==> Removing NewsBot"
if pgrep -x "NewsBot" >/dev/null 2>&1; then
  osascript -e 'tell application "NewsBot" to quit' 2>/dev/null || pkill -x NewsBot || true
  sleep 1
fi
rm -rf /Applications/NewsBot.app
rm -rf "$HOME/Library/Application Support/NewsBot"

echo
echo "Installed: $INSTALL_PATH"
echo "NewsBot removed."
echo "Open with: open \"$INSTALL_PATH\""
