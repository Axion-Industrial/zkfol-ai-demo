"""Helpers for invoking the bundled Rust/Zinc runner safely."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


def runner_binary_version(binary: Path, *, timeout: float = 2.0) -> str | None:
    """Return the version reported by ``zkfol-zinc-runner --version``.

    Older bundled binaries did not implement ``--version``.  Treat those as
    unknown/stale so the wrapper falls back to ``cargo run`` or asks the user to
    rebuild instead of silently using an old proof path.
    """
    try:
        proc = subprocess.run(
            [str(binary), "--version"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except Exception:
        return None
    text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    match = re.search(r"zkfol-zinc-runner\s+([0-9]+(?:\.[0-9]+){1,3})", text)
    if match:
        return match.group(1)
    return None


def usable_release_binary(binary: Path, expected_version: str) -> tuple[bool, str | None]:
    """Return whether a prebuilt release binary should be used.

    The package is often upgraded by replacing ``zkfol_zinc_adapter`` while
    leaving ``rust/zkfol-zinc-runner/target`` behind.  Without a version check,
    the high-level wrapper can accidentally run an old binary whose behaviour no
    longer matches the Python wrapper and documentation.
    """
    if not binary.exists():
        return False, None
    try:
        if not binary.is_file() or not binary.stat().st_mode:
            return False, None
    except Exception:
        return False, None
    import os

    if not os.access(binary, os.X_OK):
        return False, None
    actual = runner_binary_version(binary)
    if actual == expected_version:
        return True, None
    if actual is None:
        return False, (
            f"built runner {binary} does not report a version; treating it as stale. "
            "Run `./zkfol_zinc_adapter/folzinc build` to refresh the release binary."
        )
    return False, (
        f"built runner {binary} reports version {actual}, but this Python package is {expected_version}; "
        "using Cargo so the matching runner source is built/run. Run `./zkfol_zinc_adapter/folzinc build` "
        "to refresh the release binary."
    )
