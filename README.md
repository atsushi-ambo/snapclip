# SnapClip

Clipboard history for macOS — plus automatic screenshot capture.

Keep the last **30** clips (text + images), pick one from a list, and paste it.  
Built as a native menu-bar app (Swift). No network, no accounts, no telemetry.

> **Privacy:** History is stored **unencrypted** on disk and may include passwords or tokens you copy. Clear it when needed. The menu shows a short excerpt of text (the start and the end when a copy is long). Build only from this source; the app is ad-hoc signed. See [SECURITY.md](SECURITY.md).

## Features

| Feature | How |
|--------|-----|
| Clipboard history | Last **30** items (configurable) |
| Text + images | Including screenshots |
| Picker | **⌘⇧V** or click the menu-bar icon |
| Menu layout | **Paste 1** is the first row; latest **5** stay open; older clips are in one **Older** submenu |
| Paste | Select an item → restores clipboard + sends paste |
| Copy only | Hold **⌥ Option** while clicking a clip |
| Long text | Menu shows the opening and the ending; hover a row for a longer excerpt |
| Image previews | A small thumbnail large enough to recognize the screenshot, plus an **Image** label |
| Search | Menu → **Search History…**; full-text search, Text/Images filters, matching excerpts |
| Pause | Menu → **Pause History** / **Resume History**; pause survives restarts |
| Screenshots | **⌘⇧4** / **⌘⇧3** save image files in `~/Screenshots`; SnapClip also copies them to the clipboard and history |
| Clear | Menu → Clear History |

## Install

```bash
git clone https://github.com/atsushi-ambo/snapclip.git
cd snapclip
./install.sh
```

Requires Xcode Command Line Tools (`swiftc`). Install builds `SnapClip.app` into `~/Applications`, registers a login LaunchAgent, and sets macOS screenshots to save in `~/Screenshots` (configurable). SnapClip watches that folder and also copies each saved image to the clipboard and history.

### One app at a time

The installer registers a LaunchAgent for startup. Avoid adding SnapClip separately to **Open at Login**, which would start it twice. SnapClip also uses a process lock so simultaneous starts create only one menu-bar icon and one clipboard watcher. Crashes release the lock automatically. The agent restarts after failures; a normal quit or rejected duplicate does not trigger a restart loop.

### One-time permission

SnapClip may not appear in the list until you add it:

1. **System Settings → Privacy & Security → Accessibility**
2. Click **`+`**
3. Press **⌘⇧G**, go to `~/Applications`, select **SnapClip.app**
4. Turn **SnapClip** **on**

Needed so choosing a history item can type **⌘V** into the frontmost app.  
Without it, items still go to the clipboard — you paste manually.

If pasting stops after rebuilding or updating, remove the old SnapClip entry with **−**, then add `~/Applications/SnapClip.app` again with **+** and enable it. Local ad-hoc builds can invalidate the previous permission.

SnapClip checks permission each time you select a clip and explains how to enable it if needed. The selected clip remains available for manual **⌘V**.

## Use

1. Copy anything as usual (**⌘C**) — SnapClip remembers it  
2. Or take a screenshot (**⌘⇧4**) — saved as a file, then copied and remembered
3. Press **⌘⇧V** (or click the menu-bar icon)  
4. Pick an item (keys **1–5** work while the menu is open)
5. It pastes into the current app  

Normal **⌘V** pastes the *latest* clipboard, including your new screenshot. No history selection is needed for the latest screenshot. Original screenshot files remain in `~/Screenshots`, independently of the history limit. Copying happens after macOS finishes saving the screenshot; the floating thumbnail can delay this by a few seconds.

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

Search checks the full text, including content beyond menu previews. Use **↑/↓** to select, **Return** to paste, or the **Copy** button to copy without pasting.

Pausing stops new clipboard and screenshot entries from being added to SnapClip history, and pauses automatic copying from the screenshot folder. Screenshot files are still saved by macOS. Existing clips remain available, and normal copying and pasting still work. Copies made while paused are not added when recording resumes.

## Development checks

Run `./scripts/test.sh` to check clipboard restoration, exact text preservation, screenshot handling, missed-copy regressions, and simultaneous-start/crash recovery. Tests use temporary history storage and a separate clipboard.

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

Background apps cannot always read `~/Desktop` without Full Disk Access. SnapClip watches `~/Screenshots`, where macOS saves the original image files. It copies new screenshots to the clipboard without needing access to Desktop.

## License

MIT — see [LICENSE](LICENSE).
