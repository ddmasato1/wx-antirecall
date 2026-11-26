#!/bin/bash
# Writes patches.json.sha256 next to patches.json. This fork has no OTA catalog, but the
# checksum is kept so the single-build catalog stays verifiable. Run this whenever
# patches.json changes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASH="$(shasum -a 256 "$ROOT/patches.json" | awk '{print $1}')"
printf '%s  patches.json\n' "$HASH" > "$ROOT/patches.json.sha256"
echo ">> wrote patches.json.sha256: $HASH"
