# SnapClip development

Native macOS menu-bar app, compiled with `swiftc`; no SwiftPM package or external dependencies.

- Build: `./scripts/build.sh`
- Test: `./scripts/test.sh` (temporary history, isolated preferences and pasteboard)
- Lint: `./scripts/lint.sh` (toolchain-bundled `swift format`; configured with 6.4.4)
- Verify: run lint, test, build, then `codesign --verify --deep --strict dist/SnapClip.app`.

The formatter uses four spaces and a 120-character line limit. `DoNotUseSemicolons`
and `OneVariableDeclarationPerLine` are disabled to preserve existing compact UI
assignments and related declarations. Whitespace formatting remains enforced.

Keep tests isolated from personal clipboard/history data. Do not run install/uninstall
or change macOS permissions/settings as part of verification. Preserve security
reasons, invariants, and macOS/API constraints when trimming comments.

## Goal

Provide macOS clipboard history and automatic screenshot capture so a user can select and paste previous text or images ([README](README.md)).

## Source of truth

- Product purpose and user workflow: [README](README.md); privacy, storage and permission contracts: [SECURITY.md](SECURITY.md). Ask the owner about conflicting purpose or permission requirements rather than inferring changes.
- Clipboard/history and screenshot-file lifetimes differ: follow [Use](README.md#use) and [Privacy & security](README.md#privacy--security); history retention does not remove original screenshots.
- Current behavior: source and isolated tests described in [Development checks](README.md#development-checks); do not use personal history as test data.

## Done means

See [Development checks](README.md#development-checks): requested clipboard/screenshot behavior is covered by isolated tests, and lint, test, build and signature verification pass. Native menu, Accessibility and actual paste behavior without automated coverage require manual confirmation or an unverified report. Installation and macOS settings changes are separate from verification and require authorization, as stated above.
