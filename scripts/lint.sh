#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
swift format --version
swift format lint --recursive --strict Sources Tests
for script in install.sh uninstall.sh scripts/*.sh; do
  bash -n "$script"
done
