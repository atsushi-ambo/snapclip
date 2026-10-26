#!/usr/bin/env bash
# Remove SnapClip agent and app.
set -euo pipefail

LABEL="com.snapclip.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_DST="$HOME/Applications/SnapClip.app"
SUPPORT_DIR="$HOME/Library/Application Support/SnapClip"

for old in com.snapclip.app com.snapclip.agent com.user.screenshot-to-copy; do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/${old}.plist"
done

pkill -x "SnapClip" 2>/dev/null || true
pkill -x "snapclip.py" 2>/dev/null || true
rm -rf "$APP_DST"
rm -f "$PLIST"

if [[ "${RESTORE_DESKTOP:-1}" == "1" ]]; then
  defaults write com.apple.screencapture location "$HOME/Desktop"
  defaults delete com.apple.screencapture target 2>/dev/null || true
  killall SystemUIServer 2>/dev/null || true
  echo "Screenshot save location restored to Desktop."
fi

if [[ "${SNAPCLIP_PURGE:-0}" == "1" ]]; then
  rm -rf "$SUPPORT_DIR"
  echo "History purged: $SUPPORT_DIR"
else
  echo "  History left at: ~/Library/Application Support/SnapClip/"
  echo "  To wipe history: SNAPCLIP_PURGE=1 $0"
  echo "    or: rm -rf ~/Library/Application\\ Support/SnapClip"
fi

echo "  Screenshots left at: ~/Screenshots/ (or your SNAPCLIP_DIR)"
echo "SnapClip uninstalled."
