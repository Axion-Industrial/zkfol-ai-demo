"""Command-line exporter for zkFOL examples to Zinc CCS JSON."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

try:
    from zkfol.cli import ExampleInputs, select_examples
except ModuleNotFoundError:
    class ExampleInputs:  # type: ignore[no-redef]
        power_base = 2
        power_exponent = 4
        efficient_base = 2
        efficient_exponent = 16
        factorial_n = 5
        fibonacci_n = 8

        def __init__(self, **kwargs: Any) -> None:
            self.__dict__.update(kwargs)

    def select_examples(*_args: Any, **_kwargs: Any) -> list[Any]:  # type: ignore[no-redef]
        raise RuntimeError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

from .explain import format_export_summary
from .r1cs import build_ccs_export, check_export_relation


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zkfol-zinc-export",
        description=(
            "Import the zkFOL reference examples, compile their mkQ/beta checks "
            "to integer R1CS/CCS, and write JSON for the Rust Zinc runner."
        ),
    )
    parser.add_argument(
        "--example",
        default="power",
        choices=(
            "power",
            "standard-power",
            "efficient",
            "efficient-power",
            "factorial",
            "fibonacci",
            "fib",
            "sk",
            "sk-combinator",
            "all",
        ),
        help="which bundled zkFOL example to export",
    )
    parser.add_argument("--out", type=Path, default=Path("zkfol_zinc_out"), help="output JSON file or directory")
    parser.add_argument("--include-sympy", action="store_true", help="include mkQ SymPy strings in the JSON for auditing")
    parser.add_argument("--pretty", action="store_true", help="pretty-print JSON")
    parser.add_argument("--check", action="store_true", help="run the pure-Python R1CS checker after exporting")
    parser.add_argument(
        "--public-final",
        action="store_true",
        help=(
            "bind the final-column input/output cells as public inputs. "
            "Use this for direct comparisons with zkVM guests proving the same public claim."
        ),
    )
    parser.add_argument("--quiet", action="store_true", help="print only output paths, for scripts")
    parser.add_argument("--explain", action="store_true", help="print a fuller explanation of each exported instance")

    inputs = parser.add_argument_group("example input overrides")
    inputs.add_argument("--power-base", type=int, default=ExampleInputs.power_base, help="base for the standard recursive power example")
    inputs.add_argument("--power-exponent", type=int, default=ExampleInputs.power_exponent, help="exponent for the standard recursive power example")
    inputs.add_argument("--efficient-base", type=int, default=ExampleInputs.efficient_base, help="base for the repeated-squaring power example")
    inputs.add_argument("--efficient-exponent", type=int, default=ExampleInputs.efficient_exponent, help="exponent for the repeated-squaring power example")
    inputs.add_argument("--factorial-n", type=int, default=ExampleInputs.factorial_n, help="n for the factorial example")
    inputs.add_argument("--fibonacci-n", type=int, default=ExampleInputs.fibonacci_n, help="n for the small generic Fibonacci example")
    return parser


def _inputs_from_args(args: argparse.Namespace) -> ExampleInputs:
    return ExampleInputs(
        power_base=args.power_base,
        power_exponent=args.power_exponent,
        efficient_base=args.efficient_base,
        efficient_exponent=args.efficient_exponent,
        factorial_n=args.factorial_n,
        fibonacci_n=args.fibonacci_n,
    )


def _write_json(path: Path, data: dict[str, Any], *, pretty: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        if pretty:
            json.dump(data, f, indent=2)
            f.write("\n")
        else:
            json.dump(data, f, separators=(",", ":"))
            f.write("\n")


def export_examples(args: argparse.Namespace) -> list[tuple[Path, dict[str, Any]]]:
    examples = select_examples(args.example, _inputs_from_args(args))
    out_items: list[tuple[Path, dict[str, Any]]] = []
    multiple = len(examples) > 1 or args.example == "all"
    if multiple:
        args.out.mkdir(parents=True, exist_ok=True)
    for example in examples:
        export = build_ccs_export(
            example,
            include_sympy_strings=args.include_sympy,
            public_final=args.public_final,
        )
        if args.check:
            check_export_relation(export)
        path = args.out / f"{example.name}.json" if multiple else args.out
        if path.suffix == "" and not multiple:
            path.mkdir(parents=True, exist_ok=True)
            path = path / f"{example.name}.json"
        _write_json(path, export, pretty=args.pretty)
        out_items.append((path, export))
    return out_items


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    items = export_examples(args)
    for n, (path, export) in enumerate(items):
        if args.quiet:
            print(path)
        else:
            print(
                format_export_summary(
                    export,
                    path=path,
                    compact=not args.explain,
                    include_witness_preview=args.explain,
                )
            )
            if n + 1 < len(items):
                print()
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
