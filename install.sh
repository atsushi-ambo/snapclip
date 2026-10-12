#!/usr/bin/env bash
# Install SnapClip as a login agent (menu bar clipboard history + screenshots).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.snapclip.app"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_SRC="$ROOT/dist/SnapClip.app"
APP_DST="$HOME/Applications/SnapClip.app"
LOG_DIR="$HOME/Library/Logs"

# --- Validate config (prevents plist XML injection / broken paths) ---
xml_escape() {
  # Escape for XML text nodes
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  s=${s//\"/&quot;}
  s=${s//\'/&apos;}
  printf '%s' "$s"
}

# Expand and normalize screenshot dir
SHOT_DIR="${SNAPCLIP_DIR:-$HOME/Screenshots}"
SHOT_DIR="${SHOT_DIR/#\~/$HOME}"
# Must be absolute
if [[ "$SHOT_DIR" != /* ]]; then
  echo "error: SNAPCLIP_DIR must be an absolute path (got: $SHOT_DIR)" >&2
  exit 1
fi
# Reject characters that would break or inject into the LaunchAgent plist.
# (Do not use $'\0' in bash [[ ]] patterns — it matches incorrectly.)
if [[ "$SHOT_DIR" == *$'\n'* || "$SHOT_DIR" == *$'\r'* || "$SHOT_DIR" == *$'\t'* ]]; then
  echo "error: SNAPCLIP_DIR contains invalid control characters" >&2
  exit 1
fi
if [[ "$SHOT_DIR" == *'<'* || "$SHOT_DIR" == *'>'* || "$SHOT_DIR" == *'&'* || "$SHOT_DIR" == *'"'* ]]; then
  echo "error: SNAPCLIP_DIR must not contain < > & \"" >&2
  exit 1
fi

MAX_ITEMS="${SNAPCLIP_MAX_ITEMS:-30}"
if ! [[ "$MAX_ITEMS" =~ ^[0-9]+$ ]]; then
  echo "error: SNAPCLIP_MAX_ITEMS must be an integer (got: $MAX_ITEMS)" >&2
  exit 1
fi
if (( MAX_ITEMS < 1 || MAX_ITEMS > 100 )); then
  echo "error: SNAPCLIP_MAX_ITEMS must be between 1 and 100 (got: $MAX_ITEMS)" >&2
  exit 1
fi

# APP_DST is fixed under $HOME — still escape for the plist
if [[ "$APP_DST" == *'<'* || "$APP_DST" == *'>'* || "$APP_DST" == *'&'* ]]; then
  echo "error: install path contains invalid characters" >&2
  exit 1
fi

chmod +x "$ROOT/scripts/build.sh" "$ROOT/install.sh" "$ROOT/uninstall.sh" 2>/dev/null || true

echo "==> Building SnapClip…"
"$ROOT/scripts/build.sh"

echo "==> Installing app to $APP_DST"
mkdir -p "$HOME/Applications"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"
# Re-sign after copy (ad-hoc; build from this source tree only)
codesign --force --deep --sign - "$APP_DST" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR" "$SHOT_DIR"
mkdir -p "$HOME/Library/Application Support/SnapClip/items"
chmod 700 "$HOME/Library/Application Support/SnapClip" \
          "$HOME/Library/Application Support/SnapClip/items" 2>/dev/null || true

# Owner-only log files (create empty if missing, then tighten mode)
: >>"$LOG_DIR/snapclip.stdout.log"
: >>"$LOG_DIR/snapclip.stderr.log"
chmod 600 "$LOG_DIR/snapclip.stdout.log" "$LOG_DIR/snapclip.stderr.log" 2>/dev/null || true

# Save an original screenshot file; ScreenshotWatcher also copies it to the clipboard.
defaults write com.apple.screencapture location "$SHOT_DIR"
defaults delete com.apple.screencapture target 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

# Stop legacy Python agent + previous app agent
for old in com.snapclip.app com.snapclip.agent com.user.screenshot-to-copy; do
  launchctl bootout "gui/$(id -u)/$old" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/${old}.plist"
done
# Prefer exact process name; keep a narrow legacy pattern for the old agent only
pkill -x "SnapClip" 2>/dev/null || true
pkill -x "snapclip.py" 2>/dev/null || true
# Also quit if already running from Applications
osascript -e 'tell application "SnapClip" to quit' 2>/dev/null || true
sleep 0.3

APP_BIN_XML="$(xml_escape "${APP_DST}/Contents/MacOS/SnapClip")"
SHOT_DIR_XML="$(xml_escape "$SHOT_DIR")"
LOG_OUT_XML="$(xml_escape "${LOG_DIR}/snapclip.stdout.log")"
LOG_ERR_XML="$(xml_escape "${LOG_DIR}/snapclip.stderr.log")"
MAX_ITEMS_XML="$(xml_escape "$MAX_ITEMS")"
LABEL_XML="$(xml_escape "$LABEL")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL_XML}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${APP_BIN_XML}</string>
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
  <string>${LOG_OUT_XML}</string>
  <key>StandardErrorPath</key>
  <string>${LOG_ERR_XML}</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SNAPCLIP_DIR</key>
    <string>${SHOT_DIR_XML}</string>
    <key>SNAPCLIP_MAX_ITEMS</key>
    <string>${MAX_ITEMS_XML}</string>
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
echo "NOTE: macOS screenshots are saved in: $SHOT_DIR"
echo "      SnapClip also copies each saved screenshot to the clipboard and history."
echo "      (uninstall restores Desktop unless RESTORE_DESKTOP=0)"
echo ""
echo "PRIVACY: Clipboard history can store passwords/tokens you copy."
echo "  Clear via menu, or: rm -rf ~/Library/Application\\ Support/SnapClip"
echo "  Build only from this source tree; the app is ad-hoc signed."
echo ""
echo "IMPORTANT — one-time permission:"
echo "  System Settings → Privacy & Security → Accessibility"
echo "  → click +, open ~/Applications/SnapClip.app, turn it on"
echo "  (needed so picking a history item can paste)."
echo ""
echo "Uninstall: $ROOT/uninstall.sh"
echo "  Wipe history too: SNAPCLIP_PURGE=1 $ROOT/uninstall.sh"
