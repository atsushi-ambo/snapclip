# SnapClip

Clipboard history for macOS — plus automatic screenshot capture.

Keep the last **30** clips (text + images), pick one from a list, and paste it.  
Built as a native menu-bar app (Swift). No network, no accounts, no telemetry.

> **Privacy:** History is stored **unencrypted** on disk and may include passwords or tokens you copy. Clear it when needed. Menu previews show the first ~60 characters of text. Build only from this source; the app is ad-hoc signed. See [SECURITY.md](SECURITY.md).

## Features

| Feature | How |
|--------|-----|
| Clipboard history | Last **30** items (configurable) |
| Text + images | Including screenshots |
| Picker | **⌘⇧V** or click the menu-bar icon |
| Menu layout | Latest **5** items open; older ones in folders **6–10**, **11–15**, … |
| Paste | Select an item → restores clipboard + sends paste |
| Screenshots | **⌘⇧4** / **⌘⇧3** auto-saved into history and clipboard |
| Clear | Menu → Clear History |

## Install

```bash
git clone https://github.com/atsushi-ambo/snapclip.git
cd snapclip
./install.sh
```

Requires Xcode Command Line Tools (`swiftc`). Install builds `SnapClip.app` into `~/Applications`, registers a login LaunchAgent, and points macOS screenshots at `~/Screenshots` (configurable).

### One-time permission

SnapClip may not appear in the list until you add it:

1. **System Settings → Privacy & Security → Accessibility**
2. Click **`+`**
3. Press **⌘⇧G**, go to `~/Applications`, select **SnapClip.app**
4. Turn **SnapClip** **on**

Needed so choosing a history item can type **⌘V** into the frontmost app.  
Without it, items still go to the clipboard — you paste manually.

Then quit SnapClip from the menu bar (or `pkill -x SnapClip`) so it relaunches with permission.

## Use

1. Copy anything as usual (**⌘C**) — SnapClip remembers it  
2. Or take a screenshot (**⌘⇧4**) — also remembered  
3. Press **⌘⇧V** (or click the menu-bar icon)  
4. Pick an item (keys **1–9** work while the menu is open)  
5. It pastes into the current app  

Normal **⌘V** still pastes only the *latest* clipboard (macOS default).

## Uninstall

```bash
./uninstall.sh
```

Wipe history as well:

```bash
SNAPCLIP_PURGE=1 ./uninstall.sh
```

## Config

| Env / install var | Default | Meaning |
|-------------------|---------|---------|
| `SNAPCLIP_MAX_ITEMS` | `30` | History length (1–100) |
| `SNAPCLIP_DIR` | `~/Screenshots` | Screenshot watch folder (absolute path) |
| `SNAPCLIP_PURGE` | `0` | On uninstall, delete history if `1` |
| `RESTORE_DESKTOP` | `1` | On uninstall, restore screenshot location to Desktop |

Example:

```bash
SNAPCLIP_MAX_ITEMS=50 ./install.sh
```

## Logs

```bash
tail -f ~/Library/Logs/snapclip.stderr.log
```

History (dirs `700`, files `600`):

```text
~/Library/Application Support/SnapClip/history.json
~/Library/Application Support/SnapClip/items/
```

## Privacy & security

- **Local only** — no network calls  
- History can include secrets if you copy them (passwords, tokens). Clear history when needed.  
- Support directory `700`; item files and index `600`  
- Text &gt; **2 MB** and images &gt; **50 MB** are skipped  
- Symlinks and non-direct children in the screenshot folder are ignored  
- History paths are validated so entries cannot escape the support directory  
- Ad-hoc code signing for local use only — prefer building from this repo  

See [SECURITY.md](SECURITY.md).

## Why not Desktop for screenshots?

Background apps cannot always read `~/Desktop` without Full Disk Access. Install points screenshots at `~/Screenshots`.

## License

MIT — see [LICENSE](LICENSE).
