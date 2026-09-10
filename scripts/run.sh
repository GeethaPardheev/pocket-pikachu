#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -x "$ROOT/build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" ]]; then
  "$ROOT/scripts/build.sh"
fi
open "$ROOT/build/Pocket Pikachu.app"
