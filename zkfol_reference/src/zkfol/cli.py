"""Command-line interface for the zkFOL reference implementation.

The default command validates the bundled examples using a fast bit-level
``beta(mkQ)``-equivalent evaluator.  Pass ``--symbolic`` to use the explicit
SymPy ``mkQ``/``beta`` compiler path for the arithmetic examples.  The full SK
combinator predicate is intentionally large, so the CLI uses the fast equivalent
for that example and points to symbolic smoke tests instead.

The output is explanatory by design: it prints the witness rows, the paper
pointer for each example, and the direct-vs-compiled semantic values.  For the
SK example it also prints decoded combinators next to the raw integer codes.
The main invariant to check is

    direct integer semantics == beta(mkQ) == 0

for every witness column.  This is the executable form of Theorem 3.8 together
with validity of the concrete witness.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence

from .paper import GENERAL_PIPELINE_REFERENCE

EXAMPLE_ALIASES = {
    "all": "all",
    "power": "standard_power",
    "standard-power": "standard_power",
    "efficient": "efficient_power",
    "efficient-power": "efficient_power",
    "factorial": "factorial",
    "fibonacci": "fibonacci",
    "fib": "fibonacci",
    "sk": "sk_combinator",
    "sk-combinator": "sk_combinator",
}


@dataclass(frozen=True)
class ExampleInputs:
    """Input numbers used by the default CLI examples.

    These are command-line defaults only.  The broader unit-test grid lives in
    ``tests/test_parameter_grid.py`` so that readers can add cases without
    changing package code.
    """

    power_base: int = 3
    power_exponent: int = 3
    efficient_base: int = 2
    efficient_exponent: int = 8
    factorial_n: int = 4
    fibonacci_n: int = 5


@dataclass(frozen=True)
class ExampleValidation:
    """Validation summary for one bundled example."""

    name: str
    description: str
    paper_reference: str
    mathematical_description: str
    witness_convention: str
    range_check_summary: str
    witness_rows: list[list[int]]
    pointer_range_ok: bool
    direct_values: tuple[int, ...]
    beta_values: tuple[int, ...]
    beta_backend: str
    semantics_agree: bool
    all_zero: bool
    valid: bool
    readable_witness_lines: tuple[str, ...] = ()


@dataclass(frozen=True)
class CliReport:
    """Complete command-line validation report."""

    backend: str
    ok: bool
    examples: tuple[ExampleValidation, ...]


def build_parser() -> argparse.ArgumentParser:
    """Build the ``run --help`` parser.

    The help text intentionally names the files and constants to edit.  Users
    who want different examples or broader tests should not have to search the
    source tree.
    """

    parser = argparse.ArgumentParser(
        prog="zkfol",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        description=(
            "Validate and display the bundled zkFOL reference examples. "
            "With no arguments, this runs all examples from the source tree."
        ),
        epilog="""
Where to tweak examples and tests
---------------------------------
* Quick command-line experiments: use the input override flags below, e.g.
  ./run --example power --power-base 5 --power-exponent 4
  ./run --example factorial --factorial-n 7
* Default CLI example numbers: edit ExampleInputs in src/zkfol/cli.py.
* Unit-test input grids: edit POWER_CASES, EFFICIENT_POWER_CASES,
  FACTORIAL_CASES, and FIBONACCI_CASES in tests/test_parameter_grid.py.
* Arithmetic predicates and example descriptions: edit src/zkfol/examples.py.
* Arithmetic witness builders: edit src/zkfol/witnesses.py.
* SK-combinator predicate, witness, and pretty-printer: edit src/zkfol/sk.py.
* Additional positive and negative tests: add cases in tests/test_parameter_grid.py,
  tests/test_negative_controls.py, and tests/test_sk.py.
""",
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=("examples", "tests"),
        default="examples",
        help="what to run: examples (default) or tests",
    )
    parser.add_argument(
        "--example",
        default="all",
        choices=tuple(sorted(EXAMPLE_ALIASES)),
        help="limit example validation to one bundled example",
    )
    parser.add_argument("--quiet", action="store_true", help="print only a one-line pass/fail summary")
    parser.add_argument("--json", action="store_true", help="emit the example report as JSON")
    parser.add_argument(
        "--symbolic",
        action="store_true",
        help=(
            "use explicit SymPy mkQ/beta evaluation for arithmetic examples; "
            "the full SK predicate is large, so the CLI reports and uses the fast equivalent for SK"
        ),
    )

    inputs = parser.add_argument_group(
        "example input overrides",
        "These affect the CLI examples only; the broader test grid is in tests/test_parameter_grid.py.",
    )
    inputs.add_argument("--power-base", type=int, default=ExampleInputs.power_base, help="base for --example power")
    inputs.add_argument(
        "--power-exponent", type=int, default=ExampleInputs.power_exponent, help="exponent for --example power"
    )
    inputs.add_argument(
        "--efficient-base", type=int, default=ExampleInputs.efficient_base, help="base for --example efficient"
    )
    inputs.add_argument(
        "--efficient-exponent",
        type=int,
        default=ExampleInputs.efficient_exponent,
        help="exponent for --example efficient",
    )
    inputs.add_argument("--factorial-n", type=int, default=ExampleInputs.factorial_n, help="n for --example factorial")
    inputs.add_argument("--fibonacci-n", type=int, default=ExampleInputs.fibonacci_n, help="n for --example fibonacci")
    return parser


def standard_examples(inputs: ExampleInputs | None = None) -> tuple[Any, ...]:
    """Construct the bundled examples lazily."""

    from .examples import efficient_power_example, factorial_example, fibonacci_example, power_example
    from .sk import sk_example

    values = inputs or ExampleInputs()
    return (
        power_example(values.power_base, values.power_exponent),
        efficient_power_example(values.efficient_base, values.efficient_exponent),
        factorial_example(values.factorial_n),
        fibonacci_example(values.fibonacci_n),
        sk_example(),
    )


def select_examples(selector: str, inputs: ExampleInputs | None = None) -> tuple[Any, ...]:
    key = selector.strip().lower()
    if key not in EXAMPLE_ALIASES:
        allowed = ", ".join(sorted(EXAMPLE_ALIASES))
        raise ValueError(f"unknown example {selector!r}; expected one of: {allowed}")
    target = EXAMPLE_ALIASES[key]
    examples = standard_examples(inputs)
    if target == "all":
        return examples
    selected = tuple(example for example in examples if example.name == target)
    if not selected:
        raise RuntimeError(f"internal error: example alias {selector!r} maps to missing example {target!r}")
    return selected


def _beta_values(example: Any, *, symbolic: bool) -> tuple[tuple[int, ...], str]:
    if symbolic and example.name != "sk_combinator":
        return tuple(result.beta_value for result in example.evaluate_all()), "symbolic-sympy"

    from .fast_beta import beta_all_fast

    backend = "fast-bit-evaluator"
    if symbolic and example.name == "sk_combinator":
        backend = "fast-bit-evaluator (full SK SymPy mkQ is intentionally avoided; see tests/test_sk.py)"
    return beta_all_fast(example.predicate, example.witness), backend


def _direct_values(example: Any) -> tuple[int, ...]:
    return tuple(example.predicate.evaluate(example.witness, x) for x in range(1, example.witness.length + 1))


def _readable_witness_lines(example: Any) -> tuple[str, ...]:
    if example.name != "sk_combinator":
        return ()
    from .sk import format_sk_witness_rows

    return format_sk_witness_rows(example.witness)


def validate_example(example: Any, *, symbolic: bool = False) -> ExampleValidation:
    direct_values = _direct_values(example)
    beta_values, beta_backend = _beta_values(example, symbolic=symbolic)
    semantics_agree = direct_values == beta_values
    all_zero = all(value == 0 for value in direct_values)
    pointer_range_ok = example.pointer_range_ok()
    return ExampleValidation(
        name=example.name,
        description=example.description,
        paper_reference=example.paper_reference,
        mathematical_description=example.mathematical_description,
        witness_convention=example.witness_convention,
        range_check_summary=example.range_check_summary,
        witness_rows=example.witness.as_lists(),
        pointer_range_ok=pointer_range_ok,
        direct_values=direct_values,
        beta_values=beta_values,
        beta_backend=beta_backend,
        semantics_agree=semantics_agree,
        all_zero=all_zero,
        valid=semantics_agree and all_zero and pointer_range_ok,
        readable_witness_lines=_readable_witness_lines(example),
    )


def build_report(
    *,
    example_selector: str = "all",
    symbolic: bool = False,
    inputs: ExampleInputs | None = None,
) -> CliReport:
    examples = tuple(validate_example(example, symbolic=symbolic) for example in select_examples(example_selector, inputs))
    ok = all(example.valid for example in examples)
    per_example_backends = {example.beta_backend for example in examples}
    if symbolic and len(per_example_backends) > 1:
        backend = "mixed: symbolic-sympy where tractable; fast-bit-evaluator for full SK"
    elif per_example_backends:
        backend = next(iter(per_example_backends))
    else:
        backend = "symbolic-sympy" if symbolic else "fast-bit-evaluator"
    return CliReport(backend=backend, ok=ok, examples=examples)


def format_text_report(report: CliReport, *, quiet: bool = False) -> str:
    passed = sum(1 for example in report.examples if example.valid)
    total = len(report.examples)
    if quiet:
        status = "PASS" if report.ok else "FAIL"
        return (
            f"{status}: {passed}/{total} zkFOL examples valid; "
            f"backend={report.backend}; beta(mkQ) agrees with direct semantics."
        )

    lines: list[str] = [
        "zkFOL source-tree validation",
        "============================",
        f"backend: {report.backend}",
        "",
        "Implementation-to-paper check",
        "-----------------------------",
        GENERAL_PIPELINE_REFERENCE,
        "",
        "For every example below, each pointer row is checked to contain valid 1-based",
        "column indices.  Then the direct Figure 3 semantics is compared with beta(mkQ).",
        "A valid witness has zeros in both value rows because zero is the designated truth value.",
        "",
        "Assurance against decorative output",
        "-----------------------------------",
        "The displayed values are recomputed from the AST and witness rows on this run; they are",
        "not stored expected-output strings.  The unit tests include symbolic-vs-fast cross-checks,",
        "broader parameter grids, and negative controls that deliberately corrupt witnesses and",
        "assert failure.  See ASSURANCE.md and the tests/ directory for details.",
        "",
    ]
    for example in report.examples:
        lines.extend(
            [
                example.name,
                f"  description: {example.description}",
                f"  paper pointer: {example.paper_reference}",
                f"  mathematical content: {example.mathematical_description}",
                f"  witness convention: {example.witness_convention}",
                f"  range checks: {example.range_check_summary}",
                f"  witness rows: {example.witness_rows}",
            ]
        )
        if example.readable_witness_lines:
            lines.append("  readable SK witness rows:")
            lines.extend(f"    {line}" for line in example.readable_witness_lines)
        lines.extend(
            [
                f"  pointer range checks ok: {example.pointer_range_ok}",
                f"  direct integer semantics: {example.direct_values}",
                f"  beta(mkQ) backend:         {example.beta_backend}",
                f"  beta(mkQ) values:          {example.beta_values}",
                f"  semantics agree: {example.semantics_agree}",
                f"  all zero: {example.all_zero}",
                f"  status: {'PASS' if example.valid else 'FAIL'}",
                "",
            ]
        )

    lines.append(f"Summary: {'PASS' if report.ok else 'FAIL'} ({passed}/{total} examples valid)")
    return "\n".join(lines)


def run_unittests() -> int:
    """Run the source-tree unittest suite.

    When the source-tree helper exists, replace the current process with it.
    That makes ``./run tests`` behave like the known-good direct command
    ``python3 -S scripts/run_tests.py`` and avoids finalizer-related hangs from
    optional symbolic packages.  The fallback path is for installed-package
    contexts where the source-tree ``scripts`` directory is absent.
    """

    import os
    import sys
    import unittest

    root = Path(__file__).resolve().parents[2]
    runner = root / "scripts" / "run_tests.py"
    if runner.is_file():
        os.execv(sys.executable, [sys.executable, "-S", str(runner)])

    tests = root / "tests"
    src = root / "src"
    for path in (root, src):
        text = str(path)
        if text not in sys.path:
            sys.path.insert(0, text)
    if not tests.is_dir():
        print(f"Could not find test directory: {tests}", file=sys.stderr)
        return 2

    suite = unittest.TestLoader().discover(str(tests))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(0 if result.wasSuccessful() else 1)


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.command == "tests":
        if args.json:
            parser.error("--json is only supported for the examples command")
            return 2
        return run_unittests()

    try:
        inputs = ExampleInputs(
            power_base=args.power_base,
            power_exponent=args.power_exponent,
            efficient_base=args.efficient_base,
            efficient_exponent=args.efficient_exponent,
            factorial_n=args.factorial_n,
            fibonacci_n=args.fibonacci_n,
        )
        report = build_report(example_selector=args.example, symbolic=args.symbolic, inputs=inputs)
    except ValueError as exc:
        parser.error(str(exc))
        return 2

    if args.json:
        import json

        print(json.dumps(asdict(report), indent=2))
    else:
        print(format_text_report(report, quiet=args.quiet))
    return 0 if report.ok else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
