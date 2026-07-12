# Security Policy

## What SnapClip does

SnapClip is a **local** macOS menu-bar utility that:

1. Watches the system clipboard for new text and images  
2. Watches the screenshot folder for new image files  
3. Stores the last N items on disk under `~/Library/Application Support/SnapClip/`  
4. Restores a chosen item to the pasteboard and optionally synthesizes ⌘V  

It does **not** open network connections, upload data, or call remote APIs.

## Sensitive data warning

Clipboard history may contain passwords, API tokens, or personal data if you copy them. Treat the history folder like a secrets store:

- Files are created with mode `600` (owner read/write only)  
- Use **Clear History** from the menu when needed  
- Wipe with: `rm -rf ~/Library/Application\ Support/SnapClip`

## Permissions

| Permission | Why |
|------------|-----|
| Accessibility | Synthetic ⌘V after picking a history item |
| (none for read clipboard) | Uses standard `NSPasteboard` APIs |

## Threat notes

| Topic | Behavior |
|-------|----------|
| Network | None |
| Credentials | None required; history may *contain* copied secrets |
| Symlinks | Screenshot watcher ignores symlinks |
| Size limit | Images &gt; 50 MB skipped |
| Code signing | Ad-hoc signed on install for local use |

## Reporting a vulnerability

Please open a private security advisory on the GitHub repository.
