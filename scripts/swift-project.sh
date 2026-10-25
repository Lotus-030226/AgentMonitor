#!/usr/bin/env bash
# Keep compiler caches inside this project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/.cache/clang" "$ROOT/.cache/swift"
export CLANG_MODULE_CACHE_PATH="$ROOT/.cache/clang"
export SWIFT_MODULECACHE_PATH="$ROOT/.cache/swift"
COMMAND="${1:-build}"
if [[ $# -gt 0 ]]; then shift; fi
# Select Xcode for this process. Keep the global developer directory unchanged.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
SWIFT_BIN="$(xcrun --find swift)"
if [[ "$COMMAND" == test ]]; then
  TESTING_PLUGINS="$(dirname "$SWIFT_BIN")/../lib/swift/host/plugins/testing"
  if [[ -f "$TESTING_PLUGINS/libTestingMacros.dylib" ]]; then
    set -- -Xswiftc -plugin-path -Xswiftc "$TESTING_PLUGINS" "$@"
  fi
fi
exec "$SWIFT_BIN" "$COMMAND" --package-path "$ROOT" --scratch-path "$ROOT/.build" --disable-sandbox "$@"
