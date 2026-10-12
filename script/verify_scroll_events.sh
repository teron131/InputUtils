#!/usr/bin/env bash
# Compiles the app's scroll-event rules with the probe and runs it, so classification and inversion are checked without the app or input devices.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_BINARY="$ROOT_DIR/.build/probes/scroll_event_probe"

mkdir -p "$(dirname "$PROBE_BINARY")"

swiftc \
  "$ROOT_DIR/Sources/InputUtils/ScrollEvents.swift" \
  "$ROOT_DIR/script/scroll_event_probe.swift" \
  -o "$PROBE_BINARY"

"$PROBE_BINARY"
