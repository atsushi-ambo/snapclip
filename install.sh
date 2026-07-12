#!/usr/bin/env bash
# Install SnapClip as a login agent (menu bar clipboard history + screenshots).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.snapclip.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_SRC="$ROOT/dist/SnapClip.app"
APP_DST="$HOME/Applications/SnapClip.app"
SHOT_DIR="${SNAPCLIP_DIR:-$HOME/Screenshots}"
LOG_DIR="$HOME/Library/Logs"
MAX_ITEMS="${SNAPCLIP_MAX_ITEMS:-30}"

chmod +x "$ROOT/scripts/build.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" 2>/dev/null || true

echo "==> Building SnapClip…"
"$ROOT/scripts/build.sh"

echo "==> Installing app to $APP_DST"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
# Re-sign after copy
codesign --force --deep --sign - "$APP_DST" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$SHOT_DIR"
mkdir -p "$HOME/Library/Application Support/SnapClip"

# Point macOS screenshots to a folder the agent can read
defaults write com.apple.screencapture location "$SHOT_DIR"
killall SystemUIServer 2>/dev/null || true

# Stop legacy Python agent + previous app agent
for old in com.snapclip.app com.snapclip.agent com.user.screenshot-to-copy; do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/${old}.plist"
done
pkill -f "snapclip.py" 2>/dev/null || true
pkill -x "SnapClip" 2>/dev/null || true
# Also quit if already running from Applications
osascript -e 'tell application "SnapClip" to quit' 2>/dev/null || true
sleep 0.3

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_DST}/Contents/MacOS/SnapClip</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/snapclip.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/snapclip.stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SNAPCLIP_DIR</key>
    <string>${SHOT_DIR}</string>
    <key>SNAPCLIP_MAX_ITEMS</key>
    <string>${MAX_ITEMS}</string>
  </dict>
</dict>
</plist>
EOF
chmod 644 "$PLIST"

launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"
sleep 0.8

echo ""
echo "SnapClip 2.0 installed."
echo "  App:               $APP_DST"
echo "  History size:      $MAX_ITEMS clips"
echo "  Screenshot folder: $SHOT_DIR"
echo "  Menu bar:          clipboard icon (doc.on.clipboard)"
echo "  History picker:    ⌘⇧V  (or click the menu bar icon)"
echo "  Logs:              $LOG_DIR/snapclip.stderr.log"
echo ""
echo "IMPORTANT — one-time permission:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → enable SnapClip (needed so picking a history item can paste)."
echo ""
echo "You can uninstall Clipy now if you want — SnapClip replaces it for history paste."
echo "Uninstall SnapClip: $ROOT/uninstall.sh"
