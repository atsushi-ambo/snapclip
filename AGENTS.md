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
