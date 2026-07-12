#!/usr/bin/env bash
# Install SnapClip as a Login Item (LaunchAgent).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="SnapClip"
LABEL="com.snapclip.agent"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
SCRIPT="$ROOT/snapclip.py"
LOG_DIR="$HOME/Library/Logs"
# Custom folder (not Desktop) so a background agent can read it without
# Full Disk Access under macOS privacy rules.
SHOT_DIR="${SNAPCLIP_DIR:-$HOME/Screenshots}"

# Refuse to install from world-writable locations (basic hygiene)
if [[ ! -f "$SCRIPT" ]]; then
  echo "error: snapclip.py not found next to install.sh" >&2
  exit 1
fi

chmod 755 "$SCRIPT" "$ROOT/install.sh" "$ROOT/uninstall.sh" 2>/dev/null || true
mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/Application Support/${APP_NAME}"
mkdir -p "$SHOT_DIR"

# Point macOS screenshots here (Cmd+Shift+3/4)
defaults write com.apple.screencapture location "$SHOT_DIR"
# Apply without full logout (best-effort on recent macOS)
killall SystemUIServer 2>/dev/null || true

# Stop previous SnapClip or legacy agent if loaded
for old in "$LABEL" "com.user.screenshot-to-copy"; do
  if launchctl list 2>/dev/null | grep -q "$old"; then
    launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  fi
  rm -f "$HOME/Library/LaunchAgents/${old}.plist"
done
pkill -f "snapclip.py" 2>/dev/null || true
pkill -f "screenshot_to_copy.py" 2>/dev/null || true

# Plist is generated locally (never commit a user-specific plist)
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>${SCRIPT}</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/snapclip.stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/snapclip.stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SNAPCLIP_DIR</key>
    <string>${SHOT_DIR}</string>
    <key>SNAPCLIP_NOTIFY</key>
    <string>0</string>
  </dict>
</dict>
</plist>
EOF
chmod 644 "$PLIST"

launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load "$PLIST"
sleep 0.5

echo "SnapClip installed and started."
echo "  Plist:             $PLIST"
echo "  Script:            $SCRIPT"
echo "  Screenshot folder: $SHOT_DIR"
echo "  Logs:              $LOG_DIR/snapclip.log"
echo ""
echo "Usage:"
echo "  1. Take a screenshot with Cmd+Shift+4 (or Cmd+Shift+3)"
echo "  2. Paste anywhere with Cmd+V — no Cmd+C needed"
echo ""
echo "Screenshots are saved to: $SHOT_DIR"
echo "(Not Desktop — so the background agent can read them without Full Disk Access.)"
echo ""
echo "To uninstall: $ROOT/uninstall.sh"
