#!/usr/bin/env bash
# Build SnapClip.app (menu bar clipboard history).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Sources/SnapClip"
APP_DIR="$ROOT/dist/SnapClip.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
BIN="$MACOS_DIR/SnapClip"

mkdir -p "$MACOS_DIR" "$RES_DIR" "$ROOT/dist"

echo "Compiling SnapClip…"
swiftc \
  -O \
  -whole-module-optimization \
  -framework AppKit \
  -framework Carbon \
  -framework Cocoa \
  -o "$BIN" \
  "$SRC"/*.swift

chmod 755 "$BIN"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>SnapClip</string>
  <key>CFBundleDisplayName</key>
  <string>SnapClip</string>
  <key>CFBundleIdentifier</key>
  <string>com.snapclip.app</string>
  <key>CFBundleVersion</key>
  <string>2.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>SnapClip</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>MIT</string>
</dict>
</plist>
PLIST

# ad-hoc sign so macOS will run it as a local agent
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

echo "Built: $APP_DIR"
ls -la "$BIN"
