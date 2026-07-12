# Security Policy

## What SnapClip does

SnapClip is a local macOS utility that:

1. Watches a screenshot folder for new image files
2. Copies those images to the system clipboard

It does **not** open network connections, collect analytics, or upload files.

## Threat notes (for reviewers)

| Topic | Behavior |
|-------|----------|
| Network | None |
| Credentials | None stored or required |
| Clipboard | Overwrites pasteboard with the latest screenshot image only |
| File access | Only the configured screenshot directory (default `~/Screenshots`) |
| Symlinks | Ignored |
| Code injection | File paths are passed to `osascript` as argv, not string-interpolated into scripts |
| LaunchAgent | Generated locally by `install.sh`; not shipped with user-specific absolute paths in git |

## Reporting a vulnerability

Please open a private security advisory on the GitHub repository, or email the maintainer listed on the repo profile. Do not open a public issue for exploitable bugs until a fix is available.
