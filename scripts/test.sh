#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build.sh"
"$ROOT/build/Pocket Pikachu.app/Contents/MacOS/PocketPikachu" --self-test
