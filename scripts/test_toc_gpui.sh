#!/usr/bin/env bash
# Headless unit tests for toc-gpui (skipped when Rust/Cargo is missing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if ! command -v cargo >/dev/null 2>&1; then
  echo "test_toc_gpui: skip (cargo not installed)"
  exit 0
fi

(cd "${ROOT}/toc-gpui" && cargo test)
echo "test_toc_gpui: ok"