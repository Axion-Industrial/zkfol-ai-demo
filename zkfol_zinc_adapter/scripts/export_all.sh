#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ADAPTER_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-generated}"
exec "$ADAPTER_DIR/folzinc" raw export --example all --out "$OUT_DIR" --pretty --check
