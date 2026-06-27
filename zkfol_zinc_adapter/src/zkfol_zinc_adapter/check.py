"""Pure-Python checker for exported zkFOL -> Zinc CCS JSON files."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from .r1cs import check_export_relation


def _load(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path} did not contain a JSON object")
    return data


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zkfol-zinc-check",
        description="Run the pure-Python integer R1CS/CCS relation checker on exported JSON files.",
    )
    parser.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s)")
    parser.add_argument("--quiet", action="store_true", help="print only failures")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    ok = True
    for path in args.paths:
        try:
            export = _load(path)
            check_export_relation(export)
        except Exception as exc:  # pragma: no cover - CLI diagnostic path
            ok = False
            print(f"FAIL {path}: {exc}")
        else:
            if not args.quiet:
                dims = export.get("dimensions", {})
                print(
                    f"OK   {path}  "
                    f"constraints={dims.get('constraints')} "
                    f"witness_vars={dims.get('witness_variables')} "
                    f"z_len={dims.get('z_len')}"
                )
    return 0 if ok else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
