#!/usr/bin/env python3
"""Source-tree launcher for the zkFOL reference implementation."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJECT = ROOT.parent
for path in (ROOT / "src", PROJECT / "vendor"):
    text = str(path)
    if path.exists() and text not in sys.path:
        sys.path.insert(0, text)

from zkfol.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
