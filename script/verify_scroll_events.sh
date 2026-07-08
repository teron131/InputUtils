#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROBE_BINARY="$ROOT_DIR/.build/probes/scroll_event_probe"

mkdir -p "$(dirname "$PROBE_BINARY")"

swiftc \
  "$ROOT_DIR/Sources/InputUtils/Services/NaturalScrollPreference.swift" \
  "$ROOT_DIR/Sources/InputUtils/Services/ScrollDirectionController.swift" \
  "$ROOT_DIR/script/scroll_event_probe.swift" \
  -o "$PROBE_BINARY"

"$PROBE_BINARY"
