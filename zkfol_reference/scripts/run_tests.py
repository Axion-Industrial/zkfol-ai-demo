#!/usr/bin/env python3
"""Run the zkFOL reference unittest suite from a source checkout."""
from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT.parent
for path in (ROOT / "src", ROOT, PROJECT / "vendor"):
    text = str(path)
    if path.exists() and text not in sys.path:
        sys.path.insert(0, text)

TESTS = ROOT / "tests"
suite = unittest.TestLoader().discover(str(TESTS))
result = unittest.TextTestRunner(verbosity=2).run(suite)
sys.stdout.flush()
sys.stderr.flush()
os._exit(0 if result.wasSuccessful() else 1)
