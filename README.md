# SnapClip

**SnapClip** automatically copies every new macOS screenshot to the clipboard so you can paste with **Cmd+V** — no manual copy step.

| Shortcut | Result |
|----------|--------|
| **Cmd+Shift+4** | Region → file saved + **clipboard** |
| **Cmd+Shift+3** | Full screen → file saved + **clipboard** |
| **Cmd+Shift+4**, then **Space** | Window → file saved + **clipboard** |

macOS-only. Uses system `python3` + `osascript`. No Homebrew dependencies, no network access, no accounts.

## Install

```bash
git clone https://github.com/atsushi-ambo/snapclip.git
cd snapclip
./install.sh
```

This will:

1. Create `~/Screenshots`
2. Point macOS screenshots there (so the background agent can read them)
3. Install a LaunchAgent that starts at login

## Use

1. `Cmd+Shift+4` (or `Cmd+Shift+3`)
2. `Cmd+V` to paste

Files are saved under **`~/Screenshots`**.

## Uninstall

```bash
./uninstall.sh
```

Stops the agent and restores screenshot saves to the Desktop.

## Logs

```bash
tail -f ~/Library/Logs/snapclip.log
```

## Optional notification

Edit `~/Library/LaunchAgents/com.snapclip.agent.plist` and set:

```xml
<key>SNAPCLIP_NOTIFY</key>
<string>1</string>
```

Then reinstall:

```bash
./uninstall.sh && ./install.sh
```

## Privacy & security

- **Local only** — no telemetry, no uploads, no network calls.
- **No secrets** — the agent only reads new image files in the screenshot folder and writes them to the pasteboard.
- **No Desktop access required** — default watch folder is `~/Screenshots` (Desktop is TCC-protected for background agents).
- **Symlinks ignored** — only regular image files directly in the watch folder are copied.
- **Size limit** — files larger than 50 MB are skipped.
- **State file** — `~/Library/Application Support/SnapClip/seen.json` is created with mode `600`.

See [SECURITY.md](SECURITY.md) for reporting issues.

## Why not Desktop?

Background agents cannot list `~/Desktop` without Full Disk Access. Install uses `~/Screenshots` so it works out of the box.

## Native macOS alternative

Clipboard only (**no file saved**):

- **Cmd+Control+Shift+4** — region  
- **Cmd+Control+Shift+3** — full screen  

SnapClip is for **save file + auto-copy**.

## License

MIT — see [LICENSE](LICENSE).
