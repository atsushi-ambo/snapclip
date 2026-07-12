#!/usr/bin/env bash
# Remove SnapClip agent and app.
set -euo pipefail

LABEL="com.snapclip.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_DST="$HOME/Applications/SnapClip.app"

for old in com.snapclip.app com.snapclip.agent com.user.screenshot-to-copy; do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/${old}.plist"
done

osascript -e 'tell application "SnapClip" to quit' 2>/dev/null || true
pkill -x "SnapClip" 2>/dev/null || true
pkill -f "snapclip.py" 2>/dev/null || true
rm -rf "$APP_DST"
rm -f "$PLIST"

if [[ "${RESTORE_DESKTOP:-1}" == "1" ]]; then
  defaults write com.apple.screencapture location "$HOME/Desktop"
  killall SystemUIServer 2>/dev/null || true
  echo "Screenshot save location restored to Desktop."
fi

echo "SnapClip uninstalled."
echo "  History left at: ~/Library/Application Support/SnapClip/"
echo "  Screenshots left at: ~/Screenshots/"
echo "  To wipe history: rm -rf ~/Library/Application\\ Support/SnapClip"
