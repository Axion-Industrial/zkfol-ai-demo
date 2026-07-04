"""Benchmark helpers for larger zkFOL -> Zinc examples and zkVM comparisons."""

from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

try:
    from zkfol.cli import ExampleInputs, select_examples
except ModuleNotFoundError:
    class ExampleInputs:  # type: ignore[no-redef]
        def __init__(self, **kwargs: Any) -> None:
            self.__dict__.update(kwargs)

    def select_examples(*_args: Any, **_kwargs: Any) -> list[Any]:  # type: ignore[no-redef]
        raise RuntimeError("zkfol_reference is not installed; run ./zkfol_zinc_adapter/folzinc setup first")

from . import __version__
from .constraint_summary import compute_constraint_summary, format_constraint_summary
from .direct_fibonacci import build_direct_fibonacci_ccs_export, fibonacci_trace
from .r1cs import build_ccs_export, check_export_relation
from .progress import run_with_progress
from .runner import usable_release_binary
from .resources import (
    DEFAULT_MAX_SINGLE_ALLOCATION_GIB,
    estimate_zinc_resources,
    format_resource_estimate,
    normalize_int_limb_request,
    skip_record,
    would_skip_for_resources,
)


@dataclass(frozen=True)
class BenchCase:
    stem: str
    selector: str
    inputs: ExampleInputs
    public_final: bool = True
    note: str = ""


BENCH_CASES: tuple[BenchCase, ...] = (
    BenchCase(
        stem="standard_power_2_32_public",
        selector="power",
        inputs=ExampleInputs(power_base=2, power_exponent=32),
        note="linear recursive witness for exact integer 2^32",
    ),
    BenchCase(
        stem="efficient_power_2_32_public",
        selector="efficient",
        inputs=ExampleInputs(efficient_base=2, efficient_exponent=32),
        note="repeated-squaring witness for exact integer 2^32",
    ),
    BenchCase(
        stem="efficient_power_2_256_public",
        selector="efficient",
        inputs=ExampleInputs(efficient_base=2, efficient_exponent=256),
        note="repeated-squaring witness for exact integer 2^256",
    ),
)

RISC0_FIBONACCI_N_VALUES: tuple[int, ...] = (100, 1000, 10000)

# The Zinc proof-of-concept currently has very large memory constants once CCS
# dimensions are padded to powers of two.  The efficient 2^32 case pads to 8192
# and is already a multi-GiB verifier run on typical machines.  The naive
# standard 2^32 case pads to 131072 and can request hundreds of GiB.  Benchmark
# suite runs therefore use a conservative safety guard; direct `folzinc run
# --input ...` remains under explicit user control.
DEFAULT_SAFE_PADDED_DIM = 16_384

RISC0_FIBONACCI_REFERENCE_ROWS: tuple[dict[str, str], ...] = (
    {
        "source": "RISC Zero official docs",
        "system": "RISC Zero",
        "case": "cargo bench --bench fib",
        "hardware": "user machine",
        "arithmetic": "mod 2^64",
        "n": "100;1000;10000",
        "time": "not fixed by docs; run locally",
        "notes": "Official docs define the benchmark as 100th, 1000th, and 10000th Fibonacci numbers modulo 2^64, ten times each, with separate execution and proving statistics.",
    },
    {
        "source": "zkbenchmarks.com / Aligned, RTX A6000",
        "system": "Risc0",
        "case": "Fibonacci",
        "hardware": "NVIDIA RTX A6000 48GB, Ubuntu 22 LTS",
        "arithmetic": "as implemented by that benchmark suite",
        "n": "10000",
        "time": "1.7s",
        "notes": "External benchmark number; not the official RISC Zero fib harness and not the exact-integer FOL-Zinc arithmetic here.",
    },
    {
        "source": "zkbenchmarks.com / Aligned, AMD EPYC 8534P",
        "system": "Risc0",
        "case": "Fibonacci",
        "hardware": "AMD EPYC 8534P 64-core, 576GB RAM, Ubuntu 24 LTS",
        "arithmetic": "as implemented by that benchmark suite",
        "n": "10000",
        "time": "10.8s",
        "notes": "External benchmark number; not the official RISC Zero fib harness and not the exact-integer FOL-Zinc arithmetic here.",
    },
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


def _load_json(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _write_csv(path: Path, rows: Iterable[dict[str, Any]]) -> None:
    rows = list(rows)
    if not rows:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def _first_statement_line(statement: Any) -> str:
    """First line of concrete_statement; a plain string is taken whole
    (iterating a string would yield its first character)."""
    if isinstance(statement, str):
        return statement
    return next(iter(statement or []), "")


def _size_summary_from_export(case: str, path: Path, export: dict[str, Any]) -> dict[str, Any]:
    dims = export["dimensions"]
    stats = export.get("stats", {})
    exact = export.get("exact_arithmetic", {})
    shape = compute_constraint_summary(export)
    return {
        "case": case,
        "path": str(path),
        "name": export.get("name", ""),
        "length": dims.get("length"),
        "max_bits": dims.get("max_bits"),
        "public_inputs": dims.get("public_inputs"),
        "constraints": dims.get("constraints"),
        "witness_variables": dims.get("witness_variables"),
        "z_len": dims.get("z_len"),
        "max_abs_value_bit_length": stats.get("max_abs_value_bit_length"),
        "zinc_scalar_variables": shape["scalar_variables_unpadded"],
        "zinc_ccs_declared_degree": shape["ccs_declared_degree"],
        "zinc_max_simplified_degree": shape["max_simplified_degree_over_private_witness"],
        "zinc_bit_bound_delta": shape["bit_bound_delta"],
        "zinc_coefficient_bit_bound": shape["max_constraint_coefficient_bit_length"],
        "zinc_witness_bit_bound": shape["max_witness_value_bit_length"],
        "zinc_padded_dim_estimate": shape["padded_ccs_dimension_estimate"],
        "exact_output_bits": exact.get("output_bit_length", ""),
        "exact_output_decimal_digits": exact.get("output_decimal_digits", ""),
        "claim": _first_statement_line(export.get("benchmark_claim", {}).get("concrete_statement", [])),
        "arithmetic": "exact integers" if exact else export.get("benchmark_claim", {}).get("arithmetic", ""),
        "profile": export.get("fibonacci_profile", export.get("adapter_kind", "")),
    }


def _size_row(path: Path) -> dict[str, Any]:
    export = _load_json(path)
    case = export.get("benchmark_case", {}).get("stem", path.stem)
    return _size_summary_from_export(case, path, export)


def _next_power_of_two(value: int) -> int:
    value = max(1, int(value))
    return 1 << (value - 1).bit_length()


def _zinc_padding_summary(path: Path) -> dict[str, Any]:
    export = _load_json(path)
    dims = export.get("dimensions", {})
    constraints = int(dims.get("constraints") or 1)
    z_len = int(dims.get("z_len") or 1)
    padded_m = _next_power_of_two(constraints)
    padded_n = _next_power_of_two(z_len)
    return {
        "case": export.get("benchmark_case", {}).get("stem") or export.get("name") or path.stem,
        "constraints": constraints,
        "z_len": z_len,
        "padded_m": padded_m,
        "padded_n": padded_n,
        "max_padded_dim": max(padded_m, padded_n),
    }


def _preflight_skip_reason(args: argparse.Namespace, summary: dict[str, Any]) -> str | None:
    if bool(getattr(args, "check_only", False)):
        return None
    if bool(getattr(args, "allow_large_zinc", False)):
        return None
    limit = int(getattr(args, "max_padded_dim", DEFAULT_SAFE_PADDED_DIM) or DEFAULT_SAFE_PADDED_DIM)
    if int(summary["max_padded_dim"]) <= limit:
        return None
    return (
        f"padded CCS dimension {summary['max_padded_dim']:,} exceeds the default safety limit {limit:,}. "
        "The current Zinc proof-of-concept can require very large memory at this size, especially during verification."
    )


def _print_preflight_skip(path: Path, summary: dict[str, Any], reason: str, *, quiet: bool) -> None:
    if quiet:
        return
    print(f"Skipping Zinc proof for {path}:")
    print(f"  case:        {summary['case']}")
    print(f"  constraints: {summary['constraints']:,}")
    print(f"  z length:    {summary['z_len']:,}")
    print(f"  padded rows: {summary['padded_m']:,}")
    print(f"  padded z:    {summary['padded_n']:,}")
    print(f"  reason:      {reason}")
    print("  To validate semantics without proving, rerun with --check-only.")
    print("  To deliberately attempt the large Zinc proof, rerun with --allow-large-zinc.")


def export_power_cases(args: argparse.Namespace) -> int:
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    cases = list(BENCH_CASES)
    power_case = getattr(args, "power_case", "all")
    if power_case == "efficient":
        cases = [case for case in cases if case.stem.startswith("efficient_")]
    elif power_case == "standard":
        cases = [case for case in cases if case.stem.startswith("standard_")]
    if args.skip_256:
        cases = [case for case in cases if "256" not in case.stem]
    if getattr(args, "skip_standard", False):
        cases = [case for case in cases if not case.stem.startswith("standard_power")]

    rows: list[dict[str, Any]] = []
    for case in cases:
        example = select_examples(case.selector, case.inputs)[0]
        export = build_ccs_export(example, public_final=case.public_final)
        if args.check:
            check_export_relation(export)
        path = out_dir / f"{case.stem}.json"
        export.setdefault("benchmark_case", {})
        export["benchmark_case"].update({"stem": case.stem, "note": case.note, "public_final": case.public_final})
        _write_json(path, export, pretty=args.pretty)
        row = _size_summary_from_export(case.stem, path, export)
        rows.append(row)
        if not args.quiet:
            print(
                f"wrote {path}  constraints={row['constraints']} "
                f"witness_vars={row['witness_variables']} max_value_bits={row['max_abs_value_bit_length']}"
            )
            print("  Zinc constraint shape: " + format_constraint_summary(export))

    _write_csv(out_dir / "fol_zinc_size_summary.csv", rows)
    write_markdown_summary(out_dir / "FOL_ZINC_SIZE_SUMMARY.md", rows, [], title="FOL+Zinc benchmark input summary")
    return 0


def write_risc0_fibonacci_reference_csv(path: Path) -> None:
    _write_csv(path, RISC0_FIBONACCI_REFERENCE_ROWS)


def export_risc0_fibonacci_cases(args: argparse.Namespace) -> int:
    """Export exact-integer FOL-Zinc inputs for RISC Zero Fibonacci n-values.

    RISC Zero's documented Fibonacci benchmark is modulo 2^64.  These exports
    intentionally do not match that arithmetic; they keep the full exact integer
    F_n as the public output.
    """
    out_dir: Path = args.out
    out_dir.mkdir(parents=True, exist_ok=True)
    n_values = tuple(args.n) if args.n else RISC0_FIBONACCI_N_VALUES
    if args.skip_10000:
        n_values = tuple(n for n in n_values if n != 10000)

    rows: list[dict[str, Any]] = []
    for n in n_values:
        export = build_direct_fibonacci_ccs_export(
            int(n),
            check=args.check,
            include_witness_rows=args.include_witness_rows,
            profile=args.fib_profile,
        )
        stem = f"fibonacci_exact_n{n}_public"
        export.setdefault("benchmark_case", {})
        export["benchmark_case"].update(
            {
                "stem": stem,
                "note": f"exact non-modular integer F_{n}; same n-value as RISC Zero fib benchmark but not mod 2^64",
                "public_final": True,
                "comparison_warning": "RISC Zero's documented fib benchmark is modulo 2^64; this FOL-Zinc input is exact integer arithmetic.",
            }
        )
        path = out_dir / f"{stem}.json"
        _write_json(path, export, pretty=args.pretty)
        row = _size_summary_from_export(stem, path, export)
        rows.append(row)
        if not args.quiet:
            print(
                f"wrote {path}  n={n} profile={args.fib_profile} exact_bits={row['exact_output_bits']} "
                f"constraints={row['constraints']} witness_vars={row['witness_variables']} "
                f"int_bits={row['max_abs_value_bit_length']}"
            )
            print("  Zinc constraint shape: " + format_constraint_summary(export))
            try:
                from .view import concrete_statement_lines, emphasize_concrete_line

                statement = next(
                    (line for line in concrete_statement_lines(export) if line.startswith("Concrete computation:")),
                    None,
                )
                if statement:
                    print("  " + emphasize_concrete_line(statement))
            except Exception:
                pass

    _write_csv(out_dir / "fol_zinc_risc0_fib_exact_size_summary.csv", rows)
    write_risc0_fibonacci_reference_csv(out_dir / "risc0_fibonacci_reference_notes.csv")
    write_markdown_summary(
        out_dir / "FOL_ZINC_RISC0_FIB_EXACT_SUMMARY.md",
        rows,
        [],
        title="FOL+Zinc exact-integer Fibonacci inputs for RISC Zero benchmark n-values",
    )
    write_generic_fibonacci_estimates(out_dir / "GENERIC_MKQ_FIBONACCI_ESTIMATE.md", n_values)
    if not args.quiet:
        print(f"wrote {out_dir / 'fol_zinc_risc0_fib_exact_size_summary.csv'}")
        print(f"wrote {out_dir / 'risc0_fibonacci_reference_notes.csv'}")
        print(f"wrote {out_dir / 'FOL_ZINC_RISC0_FIB_EXACT_SUMMARY.md'}")
        print(f"wrote {out_dir / 'GENERIC_MKQ_FIBONACCI_ESTIMATE.md'}")
    return 0


def estimate_generic_mkq_fibonacci(n: int) -> dict[str, Any]:
    """Conservative shape estimate for the literal current mkQ/beta bridge.

    This is not used by the exported benchmark.  It exists to explain why the
    benchmarkable Fibonacci path is trace-specialised for n=1000 and n=10000.
    """
    trace = fibonacci_trace(n)
    max_bits = trace.max_bits
    arity = 4
    pointer_rows = 2
    # Direct B bits for C_i(x), plus composed B bits for C_i(C_j(x)) for the two
    # pointer rows used by Fibonacci.  The selector estimate models the current
    # one-hot lookup bridge shape.
    direct_b_wires = arity * n * max_bits
    composed_b_bits = arity * pointer_rows * n * max_bits
    selector_wires = pointer_rows * n * n
    lookup_products = composed_b_bits * n
    bool_wires_lower_bound = direct_b_wires + composed_b_bits + selector_wires
    constraint_lower_bound = bool_wires_lower_bound + lookup_products + 4 * pointer_rows * n + n
    return {
        "n": n,
        "arithmetic": "ordinary integers; no modulo 2^64",
        "fib_n_bit_length": trace.output.bit_length(),
        "fib_n_decimal_digits": len(str(trace.output)),
        "max_bits": max_bits,
        "direct_b_wires": direct_b_wires,
        "composed_b_bits_lower_bound": composed_b_bits,
        "selector_wires": selector_wires,
        "lookup_product_constraints_lower_bound": lookup_products,
        "constraints_lower_bound_current_generic_bridge": constraint_lower_bound,
        "note": "Lower-bound/shape estimate for the explicit bit-level bridge, not a measured Zinc run.",
    }


def write_generic_fibonacci_estimates(path: Path, ns: Iterable[int]) -> None:
    estimates = [estimate_generic_mkq_fibonacci(int(n)) for n in ns]
    lines: list[str] = []
    lines.append("# Literal generic mkQ/beta Fibonacci size estimate")
    lines.append("")
    lines.append("These are ordinary-integer, non-modular Fibonacci sizes. They estimate the current explicit bit-level mkQ/beta bridge, not the direct benchmark export.")
    lines.append("")
    lines.append("| n | F(n) bits | F(n) decimal digits | max bits | direct B wires | composed B bits | selector wires | lookup product lower bound | current generic constraint lower bound |")
    lines.append("| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for est in estimates:
        lines.append(
            f"| {est['n']} | {est['fib_n_bit_length']} | {est['fib_n_decimal_digits']} | {est['max_bits']} | "
            f"{est['direct_b_wires']} | {est['composed_b_bits_lower_bound']} | {est['selector_wires']} | "
            f"{est['lookup_product_constraints_lower_bound']} | {est['constraints_lower_bound_current_generic_bridge']} |"
        )
    lines.append("")
    lines.append("The direct Fibonacci export exists because the current generic bit bridge would be dominated by private pointer lookup products for n=1000 and n=10000.")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def estimate_fibonacci(args: argparse.Namespace) -> int:
    estimates = [estimate_generic_mkq_fibonacci(int(n)) for n in args.n]
    if args.json:
        print(json.dumps(estimates, indent=2))
    else:
        write_generic_fibonacci_estimates(args.out, args.n)
        if not args.quiet:
            print(f"wrote {args.out}")
    return 0


def _extract_json_object(text: str) -> dict[str, Any]:
    """Extract the Rust runner JSON report from captured stdout.

    The runner prints pretty JSON when called with ``--json``.  A previous
    implementation used ``rfind("{")``, which breaks as soon as the report
    contains nested objects such as ``constraint_breakdown``.  In normal Cargo
    runs stdout is just the JSON report, but this parser is deliberately
    tolerant of a few surrounding status lines.
    """
    stripped = text.strip()
    if not stripped:
        raise ValueError("runner output did not contain JSON")
    try:
        parsed = json.loads(stripped)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError:
        pass

    decoder = json.JSONDecoder()
    for idx, char in enumerate(stripped):
        if char != "{":
            continue
        try:
            parsed, end = decoder.raw_decode(stripped[idx:])
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict) and ("proved" in parsed or "schema" in parsed or "name" in parsed):
            return parsed
    raise ValueError("runner output did not contain a parseable JSON object")


def _filtered_stderr_for_failure(stderr: str) -> str:
    """Keep useful errors but avoid replaying every machine progress marker."""
    lines = []
    for line in stderr.splitlines():
        if line.startswith("FOLZINC_PROGRESS "):
            continue
        lines.append(line)
    return "\n".join(lines).strip() + ("\n" if lines else "")


def run_zinc(args: argparse.Namespace) -> int:
    runner = args.runner
    if (runner / "Cargo.toml").exists():
        manifest = runner / "Cargo.toml"
    else:
        manifest = Path(__file__).resolve().parents[2] / "rust" / "zkfol-zinc-runner" / "Cargo.toml"
    if not manifest.exists():
        raise SystemExit(f"could not find runner Cargo.toml at {manifest}; pass --runner")

    inputs = [Path(p) for p in args.inputs]
    binary = manifest.parent / "target" / "release" / ("zkfol-zinc-runner.exe" if sys.platform.startswith("win") else "zkfol-zinc-runner")
    binary_ok, binary_note = usable_release_binary(binary, __version__)
    use_binary = binary_ok and not bool(getattr(args, "cargo_run", False))
    if binary_note and not bool(getattr(args, "cargo_run", False)) and not bool(getattr(args, "quiet", False)):
        print("Runner binary note: " + binary_note, file=sys.stderr, flush=True)
    max_gib = float(getattr(args, "max_single_allocation_gib", DEFAULT_MAX_SINGLE_ALLOCATION_GIB) or DEFAULT_MAX_SINGLE_ALLOCATION_GIB)
    allow_large = bool(getattr(args, "allow_large", False))
    args.out.parent.mkdir(parents=True, exist_ok=True)
    ran_any = False
    skipped_any = False
    with args.out.open("w", encoding="utf-8") as outf:
        for path in inputs:
            try:
                effective_int_limbs, limb_note = normalize_int_limb_request(
                    path,
                    getattr(args, "int_limbs", None),
                    strict=bool(getattr(args, "strict_int_limbs", False)),
                )
            except ValueError as exc:
                print(f"Invalid limb profile for {path}: {exc}", file=sys.stderr, flush=True)
                return 2
            estimate = estimate_zinc_resources(path, int_limbs=effective_int_limbs)
            skip, reason = would_skip_for_resources(
                estimate,
                allow_large=allow_large,
                check_only=bool(args.check_only),
                max_single_allocation_gib=max_gib,
            )
            if not args.quiet:
                if limb_note:
                    print("Limb profile note: " + limb_note, flush=True)
                print("Resource preflight: " + format_resource_estimate(estimate), flush=True)
                try:
                    print("Constraint shape:   " + format_constraint_summary(_load_json(path), padded=estimate.estimated_padded_dim), flush=True)
                except Exception:
                    pass
            if skip:
                skipped_any = True
                record = skip_record(estimate, reason)
                record["repeat"] = int(args.repeat)
                record["max_single_allocation_gib"] = max_gib
                record["requested_int_limbs"] = str(getattr(args, "int_limbs", None) or "auto")
                record["effective_int_limbs"] = estimate.int_limbs
                record["strict_int_limbs"] = bool(getattr(args, "strict_int_limbs", False))
                outf.write(json.dumps(record, sort_keys=True) + "\n")
                outf.flush()
                if not args.quiet:
                    print(
                        f"Skipping {estimate.case or estimate.name}: {reason}.\n"
                        "Use --allow-large to override, --check-only to validate without Zinc proving, "
                        "or prefer the efficient/compact benchmark profile.",
                        file=sys.stderr,
                        flush=True,
                    )
                continue

            ran_any = True
            if use_binary:
                cmd = [
                    str(binary),
                    "--input",
                    str(path),
                    "--repeat",
                    str(args.repeat),
                    "--json",
                ]
            else:
                cmd = [
                    "cargo",
                    "run",
                    "--release",
                    "--manifest-path",
                    str(manifest),
                    "--",
                    "--input",
                    str(path),
                    "--repeat",
                    str(args.repeat),
                    "--json",
                ]
            if args.check_only:
                cmd.append("--check-only")
            if effective_int_limbs is not None:
                cmd += ["--int-limbs", str(effective_int_limbs)]
            if allow_large:
                cmd.append("--allow-large")
            cmd += ["--max-single-allocation-gib", str(max_gib)]
            if bool(getattr(args, "progress", True)) and not bool(getattr(args, "quiet", False)):
                cmd.append("--progress")
            result = run_with_progress(
                cmd,
                input_path=path,
                repeat=int(args.repeat),
                check_only=bool(args.check_only),
                quiet=bool(args.quiet),
                progress=bool(getattr(args, "progress", True)),
                interval=float(getattr(args, "progress_interval", 5.0) or 5.0),
                capture_stdout=True,
                int_limbs=effective_int_limbs,
            )
            if result.returncode != 0:
                if result.stdout:
                    sys.stderr.write(result.stdout)
                filtered = _filtered_stderr_for_failure(result.stderr)
                if filtered:
                    sys.stderr.write(filtered)
                return result.returncode
            try:
                report = _extract_json_object(result.stdout)
            except Exception:
                sys.stderr.write(result.stdout)
                filtered = _filtered_stderr_for_failure(result.stderr)
                if filtered:
                    sys.stderr.write(filtered)
                raise
            report["input_path"] = str(path)
            report["case"] = _load_json(path).get("benchmark_case", {}).get("stem", path.stem)
            report["requested_int_limbs"] = str(getattr(args, "int_limbs", None) or "auto")
            report["effective_int_limbs"] = estimate.int_limbs
            report["strict_int_limbs"] = bool(getattr(args, "strict_int_limbs", False))
            report.setdefault("resource_preflight", skip_record(estimate, None))
            report["resource_preflight"]["skipped"] = False
            outf.write(json.dumps(report, sort_keys=True) + "\n")
            outf.flush()
            if not args.quiet:
                prove_call = report.get("zinc_prove_call_ms", report.get("prove_ms"))
                verify_call = report.get("zinc_verify_call_ms", report.get("verify_ms"))
                print(
                    f"{report['case']}: variables={report.get('scalar_variables_unpadded')} "
                    f"degree={report.get('ccs_declared_degree')}/simp≤{report.get('max_simplified_degree_over_private_witness')} "
                    f"bit_bound_delta={report.get('bit_bound_delta')} "
                    f"zinc_prove_call_ms={prove_call} "
                    f"zinc_verify_call_ms={verify_call} "
                    f"field_setup_ms={report.get('field_setup_ms')} "
                    f"field_relation_check_ms={report.get('field_relation_check_ms')} "
                    f"measured_iteration_ms={report.get('measured_iteration_ms')} "
                    f"local_check_ms={report.get('relation_check_ms')}"
                )
                try:
                    if prove_call is not None and verify_call is not None and float(verify_call) > float(prove_call):
                        print(
                            "  Timing note: verifier-call time exceeded prover-call time. "
                            "This can happen in the current Zinc proof-of-concept; see docs/OUTPUT_GUIDE.md."
                        )
                except Exception:
                    pass
    if skipped_any and not ran_any and not args.quiet:
        print("No Zinc proofs were run because every input exceeded the resource preflight gate.", file=sys.stderr)
    return 0

def _load_jsonl(path: Path | None) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if path is None or not path.exists():
        return rows
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
    return rows


def _load_zkvm_csv(path: Path | None) -> list[dict[str, Any]]:
    if path is None or not path.exists():
        return []
    with path.open("r", newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _fmt_duration_ms(ms: float) -> str:
    """Render a millisecond duration in humane units for summary prose."""
    if ms >= 1000.0:
        return f"{ms / 1000.0:.2f} s"
    if ms >= 100.0:
        return f"{ms:.0f} ms"
    if ms >= 10.0:
        return f"{ms:.1f} ms"
    return f"{ms:.2f} ms"


def _fmt_bytes(count: int) -> str:
    """Render a byte count in humane binary units for summary prose."""
    value = float(count)
    for unit in ("B", "KiB", "MiB", "GiB", "TiB"):
        if value < 1024.0 or unit == "TiB":
            if unit == "B":
                return f"{count} B"
            if value >= 100.0:
                return f"{value:.0f} {unit}"
            if value >= 10.0:
                return f"{value:.1f} {unit}"
            return f"{value:.2f} {unit}"
        value /= 1024.0
    raise AssertionError("unreachable")


def _duration_cell(part_ms: Any, total_ms: Any) -> str:
    if part_ms is None:
        return "n/a"
    text = _fmt_duration_ms(float(part_ms))
    if total_ms:
        text += f" ({100.0 * float(part_ms) / float(total_ms):.0f}%)"
    return text


def _bytes_cell(count: Any) -> str:
    return _fmt_bytes(int(count)) if count is not None else "n/a"


def _headline_lines(size_rows: list[dict[str, Any]], run_rows: list[dict[str, Any]]) -> list[str]:
    """Plain-English lead section: what was proved, where the time went."""
    by_case = {row.get("case", row.get("name", "")): row for row in run_rows}
    paired = [(row, by_case[row["case"]]) for row in size_rows if row["case"] in by_case]
    if not paired:
        return []
    lines = ["## Headline results", ""]
    completed = [(row, run) for row, run in paired if not run.get("skipped")]
    if completed:
        lines.append(
            "| what was proved | total wall clock | making the proof | checking the proof "
            "| prime setup | proof size | peak memory |"
        )
        lines.append("| --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for row, run in completed:
            claim = (row.get("claim") or row["case"]).removeprefix("Concrete computation: ").rstrip(".")
            total = run.get("measured_iteration_ms")
            lines.append(
                f"| {claim} | {_fmt_duration_ms(float(total)) if total else 'n/a'} | "
                f"{_duration_cell(run.get('zinc_prove_call_ms', run.get('prove_ms')), total)} | "
                f"{_duration_cell(run.get('zinc_verify_call_ms', run.get('verify_ms')), total)} | "
                f"{_duration_cell(run.get('field_setup_ms'), total)} | "
                f"{_bytes_cell(run.get('proof_size_bytes_estimate'))} | "
                f"{_bytes_cell(run.get('peak_rss_bytes'))} |"
            )
        lines.append("")
        lines.append(
            "Reading guide: `making the proof` is the Zinc prover call. `checking the proof` and "
            "`prime setup` are overheads of the current Zinc proof-of-concept, not of the FOL "
            "compilation; on these inputs they dominate the wall clock."
        )
    for row, run in paired:
        if run.get("skipped"):
            claim = (row.get("claim") or row["case"]).removeprefix("Concrete computation: ").rstrip(".")
            lines.append("")
            lines.append(
                f"- {claim}: **not run** — the resource guard predicted a "
                f"{run.get('estimated_largest_dense_allocation', 'very large')} dense allocation."
            )
    if any("fib" in (row.get("case") or "") for row in size_rows):
        lines.append("")
        lines.append(
            "External reference points (published numbers; different, weaker mod-2^64 arithmetic):"
        )
        for ref in RISC0_FIBONACCI_REFERENCE_ROWS:
            if ref["time"][:1].isdigit():
                lines.append(
                    f"- {ref['system']} Fibonacci n={ref['n']} on {ref['hardware']}: "
                    f"{ref['time']} ({ref['source']})."
                )
    lines.append("")
    return lines


def write_markdown_summary(
    path: Path,
    size_rows: list[dict[str, Any]],
    run_rows: list[dict[str, Any]],
    *,
    zkvm_rows: list[dict[str, Any]] | None = None,
    title: str = "FOL+Zinc benchmark summary",
) -> None:
    zkvm_rows = zkvm_rows or []
    lines: list[str] = []
    lines.append(f"# {title}")
    lines.append("")
    lines.append("These cases bind final input/output cells as public benchmark claims. Power cases use Zinc public-input coordinates; the direct exact-Fibonacci cases use public CCS constants to avoid a multi-public-input edge case in the current Zinc proof-of-concept.")
    lines.append("")
    lines.append("For Fibonacci, the FOL+Zinc exports in this package use exact, non-modular integer arithmetic. They deliberately do not match RISC Zero's documented modulo-2^64 Fibonacci arithmetic.")
    lines.append("")
    lines.extend(_headline_lines(size_rows, run_rows))
    lines.append("## FOL+Zinc input sizes")
    lines.append("")
    lines.append("| case | profile | len(C) | constraints | scalar vars | private vars | degree | simplified degree | bit bound delta | coeff bits | witness bits | padded dim est. | exact output bits | exact output digits |")
    lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |")
    for row in size_rows:
        lines.append(
            f"| {row['case']} | {row.get('profile','')} | {row['length']} | "
            f"{row['constraints']} | {row.get('zinc_scalar_variables', row.get('z_len',''))} | {row['witness_variables']} | "
            f"{row.get('zinc_ccs_declared_degree','')} | {row.get('zinc_max_simplified_degree','')} | "
            f"{row.get('zinc_bit_bound_delta', row.get('max_abs_value_bit_length',''))} | {row.get('zinc_coefficient_bit_bound','')} | "
            f"{row.get('zinc_witness_bit_bound','')} | {row.get('zinc_padded_dim_estimate','')} | "
            f"{row.get('exact_output_bits','')} | {row.get('exact_output_decimal_digits','')} |"
        )
    if run_rows:
        lines.append("")
        lines.append("## FOL+Zinc measured runs")
        lines.append("")
        lines.append("| case | status | int limbs | variables | degree | bit bound | constraints | padded rows | padded z | relation check ms | field setup ms | field check ms | Zinc prove call ms | Zinc verify call ms | measured iteration ms | repeat | proved |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |")
        by_case = {row.get("case", row.get("name", "")): row for row in run_rows}
        for row in size_rows:
            run = by_case.get(row["case"])
            if not run:
                continue
            status = "skipped-resource-guard" if run.get("skipped") else "completed"
            lines.append(
                f"| {row['case']} | {status} | {run.get('int_limbs','')} | "
                f"{run.get('scalar_variables_unpadded', row.get('zinc_scalar_variables',''))} | "
                f"{run.get('ccs_declared_degree', row.get('zinc_ccs_declared_degree',''))} | "
                f"{run.get('bit_bound_delta', row.get('zinc_bit_bound_delta',''))} | "
                f"{run.get('constraints_unpadded','')} | {run.get('ccs_m_padded','')} | {run.get('ccs_n_padded','')} | "
                f"{run.get('relation_check_ms','')} | {run.get('field_setup_ms','')} | {run.get('field_relation_check_ms','')} | "
                f"{run.get('zinc_prove_call_ms', run.get('prove_ms',''))} | {run.get('zinc_verify_call_ms', run.get('verify_ms',''))} | "
                f"{run.get('measured_iteration_ms','')} | {run.get('repeat','')} | {run.get('proved','')} |"
            )
        skipped = [run for run in run_rows if run.get("skipped")]
        if skipped:
            lines.append("")
            lines.append("### Resource-preflight skips")
            lines.append("")
            for run in skipped:
                lines.append(
                    f"- `{run.get('case', run.get('name', 'unknown'))}` was not launched: "
                    f"{run.get('skip_reason', 'resource guard')} "
                    f"(estimated largest dense allocation {run.get('estimated_largest_dense_allocation', 'n/a')})."
                )
    lines.append("")
    lines.append("## Direct zkVM comparison slots")
    lines.append("")
    if zkvm_rows:
        lines.append("| system | case | arithmetic | n | prove ms | verify ms | proof bytes | cycles/steps | notes |")
        lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |")
        for row in zkvm_rows:
            lines.append(
                f"| {row.get('system','')} | {row.get('case','')} | {row.get('arithmetic','')} | {row.get('n','')} | "
                f"{row.get('prove_ms','')} | {row.get('verify_ms','')} | {row.get('proof_bytes','')} | "
                f"{row.get('cycles_or_steps','')} | {row.get('notes','')} |"
            )
    else:
        lines.append("No zkVM timing CSV was supplied. The generated `risc0_fibonacci_reference_notes.csv` records the source/arithmetic notes; fill `docs/zkvm_result_template.csv` with local RISC Zero/Jolt/Cairo/RISC0 results and rerun `zkfol-zinc-bench summarize --zkvm-csv ...`.")
    lines.append("")
    lines.append("Interpretation note: the current FOL+Zinc numbers measure a deliberately explicit CCS bridge or, for the large exact Fibonacci cases, a clearly labelled trace-specialised exact-integer CCS. They are research baselines, not native-AIR lower bounds. `zinc_prove_call_ms` and `zinc_verify_call_ms` are timed library calls; setup and adapter field checks are reported separately, and current proof-of-concept verifier calls can exceed prover calls on these inputs.")
    lines.append("")
    lines.append("Resource note: run rows with `status = skipped-resource-guard` were not failed proofs. They were deliberately not launched because the adapter predicted that the current Zinc proof-of-concept would request a very large dense allocation after power-of-two padding. Use `folzinc estimate`, `--check-only`, or `--allow-large` as appropriate.")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def summarize(args: argparse.Namespace) -> int:
    inputs = [Path(p) for p in args.inputs]
    size_rows = [_size_row(path) for path in inputs]
    run_rows = _load_jsonl(args.runs)
    zkvm_rows = _load_zkvm_csv(args.zkvm_csv)
    if args.csv:
        _write_csv(args.csv, size_rows)
    write_markdown_summary(args.out, size_rows, run_rows, zkvm_rows=zkvm_rows)
    if not args.quiet:
        print(f"wrote {args.out}")
        if args.csv:
            print(f"wrote {args.csv}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="zkfol-zinc-bench",
        description="Export and summarize FOL+Zinc benchmark cases, including exact-integer Fibonacci comparisons.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    p_export = sub.add_parser("export-power", help="export public-claim power benchmark JSON inputs")
    p_export.add_argument("--out", type=Path, default=Path("benchmark_inputs"), help="output root for power benchmark JSON and summaries")
    p_export.add_argument("--pretty", action="store_true", help="write indented JSON for easier inspection")
    p_export.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python R1CS checker after each export (default: true)")
    p_export.add_argument("--skip-256", action="store_true", help="skip the larger 2^256 export")
    p_export.add_argument("--skip-standard", action="store_true", help="skip the naive standard recursive 2^32 power export")
    p_export.add_argument("--power-case", "--power-profile", dest="power_case", choices=("all", "efficient", "standard"), default="all", help="which power benchmark family to export")
    p_export.add_argument("--quiet", action="store_true", help="print less exporter output")
    p_export.set_defaults(func=export_power_cases)

    p_fib = sub.add_parser("export-risc0-fib", help="export exact-integer Fibonacci inputs for n=100,1000,10000")
    p_fib.add_argument("--out", type=Path, default=Path("benchmark_inputs/risc0_fib_exact"), help="output directory for exact Fibonacci JSON and summaries")
    p_fib.add_argument("--n", type=int, action="append", help="Fibonacci index to export; repeat for multiple values. Default: 100, 1000, 10000")
    p_fib.add_argument("--pretty", action="store_true", help="write indented JSON for easier inspection")
    p_fib.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python R1CS checker after each export (default: true)")
    p_fib.add_argument("--skip-10000", action="store_true", help="skip the largest exact-integer case")
    p_fib.add_argument("--include-witness-rows", action="store_true", help="include duplicate full witness rows in metadata; off by default to keep large JSON smaller")
    p_fib.add_argument("--fib-profile", choices=("compact", "full"), default="compact", help="compact is the faster default; full keeps the older explicit four-row direct trace")
    p_fib.add_argument("--quiet", action="store_true", help="print less exporter output")
    p_fib.set_defaults(func=export_risc0_fibonacci_cases)

    for alias_name, alias_help in (
        ("export-fibonacci-exact", "alias for export-risc0-fib"),
        ("export-fibonacci", "alias for export-risc0-fib"),
    ):
        p_fib_alias = sub.add_parser(alias_name, help=alias_help)
        p_fib_alias.add_argument("--out", type=Path, default=Path("benchmark_inputs/risc0_fib_exact"), help="output directory for exact Fibonacci JSON and summaries")
        p_fib_alias.add_argument("--n", type=int, action="append", help="Fibonacci index to export; repeat for multiple values. Default: 100, 1000, 10000")
        p_fib_alias.add_argument("--pretty", action="store_true", help="write indented JSON for easier inspection")
        p_fib_alias.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python R1CS checker after each export")
        p_fib_alias.add_argument("--skip-10000", action="store_true", help="skip the largest exact-integer case")
        p_fib_alias.add_argument("--include-witness-rows", action="store_true", help="include duplicate full witness rows in metadata; off by default to keep large JSON smaller")
        p_fib_alias.add_argument("--fib-profile", choices=("compact", "full"), default="compact", help="compact is the faster default; full keeps the older explicit four-row direct trace")
        p_fib_alias.add_argument("--quiet", action="store_true", help="print less exporter output")
        p_fib_alias.set_defaults(func=export_risc0_fibonacci_cases)

    p_fib_est = sub.add_parser("estimate-fibonacci-generic", help="estimate the literal mkQ/beta bridge size for exact non-modular Fibonacci")
    p_fib_est.add_argument("--n", type=int, nargs="+", default=list(RISC0_FIBONACCI_N_VALUES), help="Fibonacci index values to estimate")
    p_fib_est.add_argument("--out", type=Path, default=Path("benchmark_inputs/risc0_fib_exact/GENERIC_MKQ_FIBONACCI_ESTIMATE.md"), help="Markdown output path for the estimate")
    p_fib_est.add_argument("--json", action="store_true", help="print machine-readable JSON instead of writing Markdown")
    p_fib_est.add_argument("--quiet", action="store_true", help="suppress status output")
    p_fib_est.set_defaults(func=estimate_fibonacci)

    p_run = sub.add_parser("run-zinc", help="run the Rust Zinc runner on exported inputs and collect JSONL")
    p_run.add_argument("inputs", nargs="+")
    p_run.add_argument("--runner", type=Path, default=Path("rust/zkfol-zinc-runner"), help="Rust runner directory or Cargo.toml to use")
    p_run.add_argument("--cargo-run", action="store_true", help="force cargo run even if a built release binary exists")
    p_run.add_argument("--out", type=Path, default=Path("benchmark_results/fol_zinc_runs.jsonl"), help="JSONL file receiving one run record per input")
    p_run.add_argument("--repeat", type=int, default=3, help="number of prove/verify repetitions per input")
    p_run.add_argument("--check-only", action="store_true", help="run only the Rust local integer relation check")
    p_run.add_argument("--int-limbs", default=None, help="auto, 2, 4, 8, 16, 32, 64, or 128; high-level runner uses the smallest safe profile unless --strict-int-limbs is supplied")
    p_run.add_argument("--strict-int-limbs", "--force-int-limbs", dest="strict_int_limbs", action="store_true", help="force the exact --int-limbs value even when a smaller profile is sufficient; can make random-field setup very slow")
    p_run.add_argument("--quiet", action="store_true", help="print less wrapper output")
    p_run.add_argument("--progress", action=argparse.BooleanOptionalAction, default=True, help="show elapsed time, coarse progress, ETA estimate, CPU usage, and RSS memory while Cargo/Zinc runs")
    p_run.add_argument("--progress-interval", type=float, default=5.0, help="seconds between progress heartbeat lines")
    p_run.add_argument("--max-single-allocation-gib", type=float, default=DEFAULT_MAX_SINGLE_ALLOCATION_GIB, help="skip proof runs whose estimated current-Zinc largest dense allocation exceeds this many GiB")
    p_run.add_argument("--allow-large", "--allow-large-zinc", "--run-large", dest="allow_large", action="store_true", help="override the memory preflight and launch Zinc even when the estimate is above the safety limit")
    p_run.set_defaults(func=run_zinc)

    p_sum = sub.add_parser("summarize", help="write Markdown/CSV summaries from benchmark inputs and optional run results")
    p_sum.add_argument("inputs", nargs="+")
    p_sum.add_argument("--runs", type=Path, default=None, help="JSONL from run-zinc")
    p_sum.add_argument("--zkvm-csv", type=Path, default=None, help="optional direct-comparison zkVM CSV")
    p_sum.add_argument("--out", type=Path, default=Path("benchmark_results/FOL_ZINC_BENCHMARK_SUMMARY.md"), help="Markdown summary output path")
    p_sum.add_argument("--csv", type=Path, default=None, help="optional CSV summary output path")
    p_sum.add_argument("--quiet", action="store_true", help="suppress status output")
    p_sum.set_defaults(func=summarize)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
