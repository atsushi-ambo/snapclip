# Security Policy

## What SnapClip does

SnapClip is a **local** macOS menu-bar utility that:

1. Watches the system clipboard for new text and images  
2. Watches the screenshot folder for new image files  
3. Stores the last N items on disk under `~/Library/Application Support/SnapClip/`  
4. Restores a chosen item to the pasteboard and optionally synthesizes ⌘V  

It does **not** open network connections, upload data, or call remote APIs.

## Sensitive data warning

**Clipboard history is a plaintext secrets store.** If you copy passwords, API tokens, private keys, or 2FA codes, they are written to disk. Menu previews also show a short excerpt of that text.

Treat the history folder like a secrets store:

- Support directory mode `700`; item files and index mode `600`  
- Text clips larger than **2 MB** and images larger than **50 MB** are skipped  
- Use **Clear History** from the menu when needed  
- Wipe with: `rm -rf ~/Library/Application\ Support/SnapClip`  
  or: `SNAPCLIP_PURGE=1 ./uninstall.sh`

## Permissions

| Permission | Why |
|------------|-----|
| Accessibility | Synthetic ⌘V / Ctrl+V after picking a history item |
| (none for read clipboard) | Uses standard `NSPasteboard` APIs |

Accessibility + keystroke synthesis is a **high privilege**. Only grant it to a binary you built from this repository.

## Threat notes

| Topic | Behavior |
|-------|----------|
| Network | None |
| Credentials | None required; history may *contain* copied secrets |
| Symlinks | Screenshot watcher ignores symlinks; only direct children of the watch folder |
| Path safety | History `relativePath` values must be `items/<id>.<ext>` under the support dir |
| Size limit | Text &gt; 2 MB and images &gt; 50 MB skipped |
| Code signing | Ad-hoc signed on install for local use — not notarized |
| Persistence | LaunchAgent with `KeepAlive`; replacing `~/Applications/SnapClip.app` restarts that binary |

### Trust model

- Prefer **building from source** via `./install.sh` rather than downloading a prebuilt `.app`  
- The install script is ad-hoc signed and installs under your home directory  
- A local attacker who overwrites the app and already has your user privileges can abuse Accessibility if you granted it  

## Install side effects

- Sets macOS screenshot save location to `SNAPCLIP_DIR` (default `~/Screenshots`)  
- Uninstall restores Desktop unless `RESTORE_DESKTOP=0`  

## Reporting a vulnerability

Please open a **private security advisory** on the GitHub repository  
(Security → Advisories → New draft security advisory), or contact the maintainer via the GitHub profile email if advisories are unavailable.

Do not file public issues for unfixed vulnerabilities that could harm users’ clipboard data.
