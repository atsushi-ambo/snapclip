#!/usr/bin/env bash
# Remove SnapClip LaunchAgent.
set -euo pipefail

LABEL="com.snapclip.agent"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

if launchctl list 2>/dev/null | grep -q "$LABEL"; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || \
    launchctl unload "$PLIST" 2>/dev/null || true
fi
pkill -f "snapclip.py" 2>/dev/null || true
rm -f "$PLIST"

# Also clean legacy label if present
LEGACY="com.user.screenshot-to-copy"
if launchctl list 2>/dev/null | grep -q "$LEGACY"; then
  launchctl bootout "gui/$(id -u)/$LEGACY" 2>/dev/null || true
fi
rm -f "$HOME/Library/LaunchAgents/${LEGACY}.plist"

# Optionally restore screenshot location to Desktop
if [[ "${RESTORE_DESKTOP:-1}" == "1" ]]; then
  defaults write com.apple.screencapture location "$HOME/Desktop"
  killall SystemUIServer 2>/dev/null || true
  echo "Screenshot save location restored to Desktop."
fi

echo "SnapClip uninstalled."
echo "  Logs (left in place):  ~/Library/Logs/snapclip*.log"
echo "  State (left in place): ~/Library/Application Support/SnapClip/"
echo "  Files (left in place): ~/Screenshots/"
