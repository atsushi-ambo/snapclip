#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/snapclip-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
cp "$ROOT/Tests/ClipboardRestoreTests.swift" "$TEST_DIR/main.swift"
swiftc -D SNAPCLIP_TESTING -framework AppKit -o "$TEST_DIR/check" \
  "$ROOT/Sources/SnapClip/HistoryStore.swift" \
  "$ROOT/Sources/SnapClip/ScreenshotWatcher.swift" \
  "$ROOT/Sources/SnapClip/HistorySearch.swift" \
  "$ROOT/Sources/SnapClip/ClipPreview.swift" \
  "$ROOT/Sources/SnapClip/ClipThumbnail.swift" "$TEST_DIR/main.swift"
"$TEST_DIR/check"
cp "$ROOT/Tests/SingleInstanceTests.swift" "$TEST_DIR/main.swift"
swiftc -o "$TEST_DIR/instance-check" \
  "$ROOT/Sources/SnapClip/SingleInstanceLock.swift" "$TEST_DIR/main.swift"
"$TEST_DIR/instance-check"
