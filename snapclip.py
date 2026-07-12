#!/usr/bin/env python3
"""
SnapClip — watch the macOS screenshot folder and copy new screenshots
to the clipboard so you can paste with Cmd+V (no manual copy).

Works with Cmd+Shift+3 / Cmd+Shift+4 (and related save-to-file shortcuts).
"""

from __future__ import annotations

import json
import logging
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

APP_NAME = "SnapClip"
POLL_INTERVAL = 0.35
WRITE_SETTLE_SECONDS = 0.4
MAX_AGE_ON_DISCOVER_SECONDS = 8.0

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg", ".tiff", ".tif", ".gif", ".heic", ".bmp"}
IGNORE_PREFIXES = (".", "~")
IGNORE_SUBSTRINGS = (".tmp", "Screen Recording")

# Dedicated folder avoids macOS Desktop privacy blocks for background agents
DEFAULT_WATCH_DIR = Path.home() / "Screenshots"

LOG_DIR = Path.home() / "Library" / "Logs"
LOG_FILE = LOG_DIR / "snapclip.log"
STATE_DIR = Path.home() / "Library" / "Application Support" / APP_NAME
STATE_FILE = STATE_DIR / "seen.json"


def setup_logging() -> None:
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=[
            logging.FileHandler(LOG_FILE),
            logging.StreamHandler(sys.stdout),
        ],
    )


def screenshot_dir() -> Path:
    """
    Resolve the folder where screenshots are saved.

    Prefer SNAPCLIP_DIR, then macOS screencapture location, then ~/Screenshots.
    """
    env = os.environ.get("SNAPCLIP_DIR", "").strip()
    if env:
        path = Path(env).expanduser()
        path.mkdir(parents=True, exist_ok=True)
        return path.resolve()

    try:
        result = subprocess.run(
            ["defaults", "read", "com.apple.screencapture", "location"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            location = result.stdout.strip()
            if location:
                path = Path(location).expanduser()
                path.mkdir(parents=True, exist_ok=True)
                if path.is_dir():
                    return path.resolve()
    except Exception as exc:  # noqa: BLE001
        logging.warning("Could not read screenshot location: %s", exc)

    DEFAULT_WATCH_DIR.mkdir(parents=True, exist_ok=True)
    return DEFAULT_WATCH_DIR.resolve()


def load_seen() -> set[str]:
    try:
        if STATE_FILE.is_file():
            data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
            if isinstance(data, list):
                return set(str(x) for x in data)
    except Exception:  # noqa: BLE001
        pass
    return set()


def save_seen(seen: set[str]) -> None:
    try:
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        items = sorted(seen)[-500:]
        STATE_FILE.write_text(json.dumps(items), encoding="utf-8")
        # Owner-only state file
        os.chmod(STATE_FILE, 0o600)
    except Exception as exc:  # noqa: BLE001
        logging.warning("Could not save state: %s", exc)


def file_key(path: Path) -> str:
    try:
        st = path.stat()
        return f"{path.resolve()}::{st.st_ino}::{st.st_size}::{int(st.st_mtime)}"
    except OSError:
        return str(path)


def is_safe_file(path: Path, watch_dir: Path) -> bool:
    """
    Only process real files that live directly under the watch directory.
    Blocks symlinks and path tricks.
    """
    try:
        if path.is_symlink():
            return False
        if not path.is_file():
            return False
        resolved = path.resolve()
        parent = resolved.parent
        if parent != watch_dir.resolve():
            return False
        # Reject oversized files (screenshots are small; 50MB cap)
        if resolved.stat().st_size > 50 * 1024 * 1024:
            logging.warning("Skipping oversized file: %s", resolved.name)
            return False
        return True
    except OSError:
        return False


def should_consider(path: Path, watch_dir: Path) -> bool:
    name = path.name
    if not is_safe_file(path, watch_dir):
        return False
    if name.startswith(IGNORE_PREFIXES):
        return False
    if any(s in name for s in IGNORE_SUBSTRINGS):
        return False
    if path.suffix.lower() not in IMAGE_EXTENSIONS:
        return False
    return True


def wait_until_stable(path: Path, timeout: float = 3.0) -> bool:
    """Wait until file size stops changing (write finished)."""
    deadline = time.time() + timeout
    last_size = -1
    stable_count = 0
    while time.time() < deadline:
        try:
            size = path.stat().st_size
        except OSError:
            return False
        if size > 0 and size == last_size:
            stable_count += 1
            if stable_count >= 2:
                return True
        else:
            stable_count = 0
            last_size = size
        time.sleep(0.15)
    try:
        return path.is_file() and path.stat().st_size > 0
    except OSError:
        return False


def run_osascript(*lines: str, args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    """Run osascript with argv to avoid string injection from file paths."""
    cmd = ["osascript"]
    for line in lines:
        cmd.extend(["-e", line])
    if args:
        cmd.extend(args)
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def copy_image_to_clipboard(path: Path) -> bool:
    """Put an image file on the macOS clipboard (paste with Cmd+V)."""
    suffix = path.suffix.lower()
    posix = str(path.resolve())

    if suffix == ".png":
        as_type = "«class PNGf»"
    elif suffix in {".jpg", ".jpeg"}:
        as_type = "JPEG picture"
    elif suffix in {".tif", ".tiff"}:
        as_type = "TIFF picture"
    else:
        return copy_via_temp_png(path)

    # Path passed as argv — not interpolated into AppleScript source
    result = run_osascript(
        "on run argv",
        "  set p to item 1 of argv",
        f"  set the clipboard to (read (POSIX file p) as {as_type})",
        "end run",
        args=[posix],
    )
    if result.returncode == 0:
        return True

    logging.error(
        "osascript failed: %s",
        (result.stderr or result.stdout or "").strip(),
    )
    if suffix != ".png":
        return copy_via_temp_png(path)
    return False


def copy_via_temp_png(path: Path) -> bool:
    import tempfile

    try:
        with tempfile.TemporaryDirectory(prefix="snapclip-") as tmp:
            out = Path(tmp) / "shot.png"
            conv = subprocess.run(
                ["sips", "-s", "format", "png", str(path), "--out", str(out)],
                capture_output=True,
                text=True,
                check=False,
            )
            if conv.returncode != 0 or not out.is_file():
                logging.error("sips convert failed: %s", (conv.stderr or "").strip())
                return False
            return copy_image_to_clipboard(out)
    except Exception as exc:  # noqa: BLE001
        logging.exception("Temp PNG copy failed: %s", exc)
        return False


def notify(title: str, message: str) -> None:
    try:
        run_osascript(
            "on run argv",
            "  display notification (item 2 of argv) with title (item 1 of argv)",
            "end run",
            args=[title, message],
        )
    except Exception:  # noqa: BLE001
        pass


def process_file(path: Path, watch_dir: Path, seen: set[str]) -> None:
    key = file_key(path)
    if key in seen:
        return

    try:
        age = time.time() - path.stat().st_mtime
    except OSError:
        return

    if age > MAX_AGE_ON_DISCOVER_SECONDS:
        seen.add(key)
        return

    time.sleep(WRITE_SETTLE_SECONDS)
    if not wait_until_stable(path):
        logging.warning("File never stabilized, skipping: %s", path.name)
        return

    if not is_safe_file(path, watch_dir):
        return

    key = file_key(path)
    if key in seen:
        return

    logging.info("Copying to clipboard: %s", path.name)
    if copy_image_to_clipboard(path):
        seen.add(key)
        save_seen(seen)
        logging.info("Ready to paste (Cmd+V): %s", path.name)
        if os.environ.get("SNAPCLIP_NOTIFY", "0") == "1":
            notify(APP_NAME, "Screenshot copied — paste with Cmd+V")
    else:
        logging.error("Failed to copy: %s", path.name)


def seed_existing(directory: Path, seen: set[str]) -> None:
    """Mark existing images as already seen so we only act on new ones."""
    try:
        for path in directory.iterdir():
            if should_consider(path, directory):
                seen.add(file_key(path))
    except PermissionError:
        logging.error(
            "Permission denied listing %s. "
            "Use ~/Screenshots (default install) or grant Full Disk Access "
            "to /usr/bin/python3 in System Settings → Privacy & Security.",
            directory,
        )
        raise
    except OSError as exc:
        logging.warning("Could not seed directory %s: %s", directory, exc)
    save_seen(seen)


def main() -> int:
    setup_logging()
    directory = screenshot_dir()
    logging.info("%s started", APP_NAME)
    logging.info("Watching: %s", directory)
    logging.info("Log file: %s", LOG_FILE)

    seen = load_seen()
    try:
        seed_existing(directory, seen)
    except PermissionError:
        return 1

    running = True

    def stop(_signum, _frame):  # type: ignore[no-untyped-def]
        nonlocal running
        logging.info("Stopping…")
        running = False

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    perm_errors = 0
    while running:
        try:
            # Re-resolve in case location defaults change
            if not directory.is_dir():
                logging.warning("Screenshot directory missing: %s", directory)
                time.sleep(2)
                directory = screenshot_dir()
                continue

            for path in directory.iterdir():
                if should_consider(path, directory):
                    process_file(path, directory, seen)
            perm_errors = 0
        except PermissionError:
            perm_errors += 1
            if perm_errors == 1 or perm_errors % 30 == 0:
                logging.error(
                    "Cannot read %s (macOS privacy). "
                    "Re-run install.sh so screenshots go to ~/Screenshots, "
                    "or grant Full Disk Access to /usr/bin/python3.",
                    directory,
                )
            time.sleep(2)
        except Exception as exc:  # noqa: BLE001
            logging.exception("Watch loop error: %s", exc)
            time.sleep(1)

        time.sleep(POLL_INTERVAL)

    save_seen(seen)
    logging.info("Exited cleanly")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
