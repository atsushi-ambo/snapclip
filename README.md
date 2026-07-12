# SnapClip

Clipboard history for macOS — plus automatic screenshot capture.

Keep the last **30** clips (text + images), pick one from a list, and paste it.  
Built as a native menu-bar app (Swift). No network, no accounts, no telemetry.

## Features

| Feature | How |
|--------|-----|
| Clipboard history | Last **30** items (configurable) |
| Text + images | Including screenshots |
| Picker | **⌘⇧V** or click the menu-bar icon |
| Paste | Select an item → restores clipboard + sends paste |
| Screenshots | **⌘⇧4** / **⌘⇧3** auto-saved into history and clipboard |
| Clear | Menu → Clear History |

## Install

```bash
git clone https://github.com/atsushi-ambo/snapclip.git
cd snapclip
./install.sh
```

Requires Xcode Command Line Tools (`swiftc`). Install builds `SnapClip.app` into `~/Applications` and starts it at login.

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

## Config

| Env / install var | Default | Meaning |
|-------------------|---------|---------|
| `SNAPCLIP_MAX_ITEMS` | `30` | History length (1–100) |
| `SNAPCLIP_DIR` | `~/Screenshots` | Screenshot watch folder |

Example:

```bash
SNAPCLIP_MAX_ITEMS=50 ./install.sh
```

## Logs

```bash
tail -f ~/Library/Logs/snapclip.stderr.log
```

History files (mode `600`):

```text
~/Library/Application Support/SnapClip/history.json
~/Library/Application Support/SnapClip/items/
```

## Privacy & security

- **Local only** — no network calls  
- History can include secrets if you copy them (passwords, tokens). Clear history when needed.  
- Item files and index use permissions `600`  
- Symlinks in the screenshot folder are ignored; images over 50 MB are skipped  

See [SECURITY.md](SECURITY.md).

## Why not Desktop for screenshots?

Background apps cannot always read `~/Desktop` without Full Disk Access. Install points screenshots at `~/Screenshots`.

## License

MIT — see [LICENSE](LICENSE).
