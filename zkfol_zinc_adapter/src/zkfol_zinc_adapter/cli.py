"""Single-command interface for the zkFOL -> Zinc adapter."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Sequence

from . import __version__
from . import bench as bench_mod
from . import check as check_mod
from . import explain as explain_mod
from . import export as export_mod
from . import view as view_mod
from .constraint_summary import format_constraint_summary
from .progress import run_with_progress
from .runner import usable_release_binary
from .resources import (
    DEFAULT_MAX_SINGLE_ALLOCATION_GIB,
    estimate_zinc_resources,
    format_resource_estimate,
    normalize_int_limb_request,
    would_skip_for_resources,
)

EXAMPLES = ("power", "efficient", "factorial", "fibonacci", "sk", "all")
EXAMPLE_ALIASES = {
    "standard": "power",
    "standard-power": "power",
    "efficient-power": "efficient",
    "fib": "fibonacci",
    "sk-combinator": "sk",
}


def adapter_dir() -> Path:
    # .../zkfol_zinc_adapter/src/zkfol_zinc_adapter/cli.py -> adapter root
    return Path(__file__).resolve().parents[2]


def project_dir() -> Path:
    return adapter_dir().parent


def runner_dir(path: Path | None = None) -> Path:
    if path is None:
        return adapter_dir() / "rust" / "zkfol-zinc-runner"
    path = Path(path)
    return path.parent if path.name == "Cargo.toml" else path


def runner_manifest(path: Path | None = None) -> Path:
    rd = runner_dir(path)
    return rd if rd.name == "Cargo.toml" else rd / "Cargo.toml"


def runner_binary(path: Path | None = None) -> Path:
    rd = runner_dir(path)
    return rd / "target" / "release" / ("zkfol-zinc-runner.exe" if sys.platform.startswith("win") else "zkfol-zinc-runner")


def print_header(title: str) -> None:
    print(title)
    print("=" * len(title))


def run_process(cmd: Sequence[str], *, quiet: bool = False) -> int:
    if not quiet:
        print("$ " + " ".join(cmd))
    return subprocess.run(list(cmd)).returncode


def cmd_options(_: argparse.Namespace) -> int:
    """Print the practical option reference from the bundled documentation."""
    path = adapter_dir() / "docs" / "OPTIONS_REFERENCE.md"
    print(path.read_text(encoding="utf-8"), end="")
    return 0





def prepare_int_limb_request(args: argparse.Namespace, input_path: Path) -> int:
    """Resolve a high-level limb request before constructing/preflighting a run."""
    try:
        effective, note = normalize_int_limb_request(
            input_path,
            getattr(args, "int_limbs", None),
            strict=bool(getattr(args, "strict_int_limbs", False) or getattr(args, "force_int_limbs", False)),
        )
    except ValueError as exc:
        print(f"Invalid limb profile for {input_path}: {exc}", file=sys.stderr, flush=True)
        return 2
    setattr(args, "_effective_int_limbs", effective)
    if note and not bool(getattr(args, "quiet", False)):
        print("Limb profile note: " + note, flush=True)
    return 0


def run_cargo_zinc(args: argparse.Namespace, cmd: Sequence[str], input_path: Path) -> int:
    max_gib = float(getattr(args, "max_single_allocation_gib", DEFAULT_MAX_SINGLE_ALLOCATION_GIB) or DEFAULT_MAX_SINGLE_ALLOCATION_GIB)
    effective_int_limbs = getattr(args, "_effective_int_limbs", getattr(args, "int_limbs", None))
    estimate = estimate_zinc_resources(input_path, int_limbs=effective_int_limbs)
    skip, reason = would_skip_for_resources(
        estimate,
        allow_large=bool(getattr(args, "allow_large", False)),
        check_only=bool(getattr(args, "check_only", False)),
        max_single_allocation_gib=max_gib,
    )
    if not bool(getattr(args, "quiet", False)):
        print("Resource preflight: " + format_resource_estimate(estimate), flush=True)
        try:
            import json
            with Path(input_path).open("r", encoding="utf-8") as f:
                print("Constraint shape:   " + format_constraint_summary(json.load(f), padded=estimate.estimated_padded_dim), flush=True)
        except Exception:
            pass
    if skip:
        print(
            "\nRefusing to launch Zinc for this input because the current Zinc proof-of-concept "
            "is predicted to allocate more memory than the safety limit.\n"
            f"Reason: {reason}.\n"
            "Use --check-only to validate the exported integer relation without proving, "
            "--allow-large to force the run on a suitably large machine, or use the "
            "efficient/compact benchmark profile for proof timings.",
            file=sys.stderr,
            flush=True,
        )
        return 75
    result = run_with_progress(
        cmd,
        input_path=input_path,
        repeat=int(getattr(args, "repeat", 1) or 1),
        check_only=bool(getattr(args, "check_only", False)),
        quiet=bool(getattr(args, "quiet", False)),
        progress=bool(getattr(args, "progress", True)),
        interval=float(getattr(args, "progress_interval", 5.0) or 5.0),
        capture_stdout=False,
        int_limbs=effective_int_limbs,
    )
    return result.returncode

def add_example_inputs(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--power-base", type=int, default=None, help="base for the standard recursive power example")
    parser.add_argument("--power-exponent", type=int, default=None, help="exponent for the standard recursive power example")
    parser.add_argument("--efficient-base", type=int, default=None, help="base for the repeated-squaring power example")
    parser.add_argument("--efficient-exponent", type=int, default=None, help="exponent for the repeated-squaring power example")
    parser.add_argument("--factorial-n", type=int, default=None, help="n for the factorial example")
    parser.add_argument("--fibonacci-n", type=int, default=None, help="n for the small generic Fibonacci example")


def export_argv(args: argparse.Namespace) -> list[str]:
    example = EXAMPLE_ALIASES.get(args.example, args.example)
    argv = ["--example", example, "--out", str(args.out)]
    if args.pretty:
        argv.append("--pretty")
    if args.check:
        argv.append("--check")
    if args.explain:
        argv.append("--explain")
    if args.public_final:
        argv.append("--public-final")
    if args.include_sympy:
        argv.append("--include-sympy")
    if args.quiet:
        argv.append("--quiet")
    for opt in (
        "power_base",
        "power_exponent",
        "efficient_base",
        "efficient_exponent",
        "factorial_n",
        "fibonacci_n",
    ):
        value = getattr(args, opt, None)
        if value is not None:
            argv.extend(["--" + opt.replace("_", "-"), str(value)])
    return argv


def cmd_doctor(args: argparse.Namespace) -> int:
    print_header(f"FOL-Zinc doctor ({__version__})")
    print(f"adapter: {adapter_dir()}")
    print(f"project: {project_dir()}")
    print(f"python:  {sys.executable}")
    print("")

    failures = 0

    def check(name: str, ok: bool, detail: str = "") -> None:
        nonlocal failures
        print(f"[{'OK' if ok else 'MISS':<4}] {name:<28} {detail}")
        if not ok:
            failures += 1

    check("zkfol_reference sibling", (project_dir() / "zkfol_reference").exists(), str(project_dir() / "zkfol_reference"))
    try:
        import zkfol  # noqa: F401
    except Exception as exc:
        check("import zkfol", False, repr(exc))
    else:
        check("import zkfol", True)
    try:
        import sympy  # noqa: F401
    except Exception as exc:
        check("import sympy", False, repr(exc))
    else:
        check("import sympy", True)

    manifest = runner_manifest(args.runner)
    check("Rust runner Cargo.toml", manifest.exists(), str(manifest))
    cargo = shutil.which("cargo")
    check("cargo", cargo is not None, (cargo or "not needed for export/check") + "; Rust/Cargo >= 1.85 required for the Zinc runner")
    if cargo is not None:
        try:
            cargo_version = subprocess.run([cargo, "--version"], text=True, capture_output=True, timeout=10).stdout.strip()
        except Exception as exc:
            cargo_version = f"could not query cargo version: {exc!r}"
        print(f"      Rust toolchain note: runner Cargo.toml uses edition 2024 and rust-version 1.85; cargo reports: {cargo_version}")
    check("bundled sample JSON", (adapter_dir() / "generated" / "standard_power.json").exists())

    if args.build:
        if cargo is None:
            print("\nCannot build: cargo was not found.", file=sys.stderr)
            return 1
        return run_process([cargo, "build", "--release", "--manifest-path", str(manifest)], quiet=args.quiet)

    print("\nReady commands:")
    print("  ./zkfol_zinc_adapter/folzinc demo")
    print("  ./zkfol_zinc_adapter/folzinc run --example power --repeat 3")
    return 1 if failures and args.strict else 0


def cmd_examples(_: argparse.Namespace) -> int:
    print_header("Examples and benchmark suites")
    print("Small generic mkQ/beta examples:")
    print("  power       standard recursive power witness")
    print("  efficient   repeated-squaring power witness")
    print("  factorial   factorial witness")
    print("  fibonacci   small generic Fibonacci witness")
    print("  sk          SK combinator-reduction witness")
    print("  all         export all small examples")
    print("\nBenchmark suites:")
    print("  bench power  public-output power cases: 2^32 and 2^256")
    print("  bench fib    exact, non-modular F_100, F_1000, F_10000")
    print("\nUseful commands:")
    print("  ./zkfol_zinc_adapter/folzinc demo --zinc")
    print("  ./zkfol_zinc_adapter/folzinc inspect out/demo_power_2_4_public.json --constraints")
    print("  ./zkfol_zinc_adapter/folzinc run --example efficient --efficient-base 2 --efficient-exponent 256 --public-final --int-limbs 16")
    print("  ./zkfol_zinc_adapter/folzinc bench fib --n 100 --run --repeat 3")
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    example_option = getattr(args, "example_option", None)
    if example_option is not None:
        if getattr(args, "example", None) not in (None, example_option):
            print("folzinc export: use either the positional example or --example, not two different examples", file=sys.stderr)
            return 2
        args.example = example_option
    if getattr(args, "example", None) is None:
        args.example = "power"
    return export_mod.main(export_argv(args))


def cmd_explain(args: argparse.Namespace) -> int:
    argv = [str(p) for p in args.paths]
    if args.compact:
        argv.append("--compact")
    if args.no_witness_preview:
        argv.append("--no-witness-preview")
    return explain_mod.main(argv)


def cmd_check(args: argparse.Namespace) -> int:
    argv = [str(p) for p in args.paths]
    if args.quiet:
        argv.append("--quiet")
    return check_mod.main(argv)


def cmd_inspect(args: argparse.Namespace) -> int:
    argv = [str(p) for p in args.paths]
    if not args.matrix:
        argv.append("--no-matrix")
    if args.constraints:
        argv.append("--constraints")
    argv.extend(["--matrix-head", str(args.matrix_head), "--matrix-tail", str(args.matrix_tail)])
    argv.extend(["--constraint-head", str(args.constraint_head), "--constraint-tail", str(args.constraint_tail)])
    if args.full_matrix:
        argv.append("--full-matrix")
    if args.full_constraints:
        argv.append("--full-constraints")
    return view_mod.main(argv)


def cmd_build(args: argparse.Namespace) -> int:
    cargo = shutil.which("cargo")
    if cargo is None:
        print("cargo not found. Install Rust/Cargo before building the Zinc runner.", file=sys.stderr)
        return 1
    manifest = runner_manifest(args.runner)
    return run_process([cargo, "build", "--release", "--manifest-path", str(manifest)], quiet=args.quiet)


def cargo_runner_cmd(args: argparse.Namespace, input_path: Path) -> list[str]:
    binary = runner_binary(args.runner)
    use_cargo_run = bool(getattr(args, "cargo_run", False))
    binary_ok, binary_note = usable_release_binary(binary, __version__)
    if binary_note and not use_cargo_run and not bool(getattr(args, "quiet", False)):
        print("Runner binary note: " + binary_note, file=sys.stderr, flush=True)
    if binary_ok and not use_cargo_run:
        cmd = [str(binary), "--input", str(input_path), "--repeat", str(args.repeat)]
    else:
        # Do not fail here if Cargo is absent: resource preflight should still be
        # able to refuse impossible large runs before checking tool availability.
        cargo = shutil.which("cargo") or "cargo"
        manifest = runner_manifest(args.runner)
        cmd = [cargo, "run", "--release", "--manifest-path", str(manifest), "--", "--input", str(input_path), "--repeat", str(args.repeat)]
    if args.check_only:
        cmd.append("--check-only")
    effective_limbs = getattr(args, "_effective_int_limbs", None)
    if effective_limbs is None:
        effective_limbs = getattr(args, "int_limbs", None)
    if effective_limbs:
        cmd.extend(["--int-limbs", str(effective_limbs)])
    if bool(getattr(args, "allow_large", False)):
        cmd.append("--allow-large")
    max_gib = getattr(args, "max_single_allocation_gib", None)
    if max_gib is not None:
        cmd.extend(["--max-single-allocation-gib", str(max_gib)])
    if args.json:
        cmd.append("--json")
    if bool(getattr(args, "progress", True)) and not bool(getattr(args, "quiet", False)):
        cmd.append("--progress")
    return cmd


def cmd_run(args: argparse.Namespace) -> int:
    input_path = args.input
    if input_path is None:
        if args.out is None:
            label = EXAMPLE_ALIASES.get(args.example, args.example).replace("-", "_")
            args.out = Path("out") / f"{label}.json"
        rc = cmd_export(args)
        if rc != 0:
            return rc
        input_path = args.out
    if not bool(getattr(args, "quiet", False)):
        _print_concrete_claims([input_path], title="Concrete claim being sent to Zinc")
    rc = prepare_int_limb_request(args, input_path)
    if rc != 0:
        return rc
    return run_cargo_zinc(args, cargo_runner_cmd(args, input_path), input_path)


def _demo_output_path(args: argparse.Namespace) -> Path:
    if args.out is not None:
        return args.out
    example = EXAMPLE_ALIASES.get(args.example or "power", args.example or "power")
    if example == "power":
        base = args.power_base if args.power_base is not None else 2
        exponent = args.power_exponent if args.power_exponent is not None else 4
        suffix = "public" if args.public_final else "private"
        return Path("out") / f"demo_power_{base}_{exponent}_{suffix}.json"
    label = example.replace("-", "_")
    suffix = "public" if args.public_final else "private"
    return Path("out") / f"demo_{label}_{suffix}.json"


def _print_next_steps(path: Path, *, zinc_attempted: bool) -> None:
    print("\n" + view_mod.format_next_steps(path, include_zinc_hint=True))


def _print_concrete_claims(paths: list[Path], *, title: str = "Concrete benchmark claim(s)") -> None:
    if not paths:
        return
    print("\n" + title)
    print("-" * len(title))
    for path in paths:
        try:
            export = view_mod.load_export(path)
        except Exception as exc:
            print(f"{path}: could not inspect concrete claim: {exc}")
            continue
        lines = view_mod.concrete_statement_lines(export)
        main = next((line for line in lines if line.startswith("Concrete computation:")), None)
        if main is None and lines:
            main = lines[0]
        if main is None:
            main = f"Concrete computation: {export.get('name', path.stem)}"
        print(f"{path.name}: {view_mod.emphasize_concrete_line(main)}")
        for line in lines[1:3]:
            if line.startswith("Concrete computation:"):
                continue
            print(f"  {line}")


def cmd_demo(args: argparse.Namespace) -> int:
    args.example = args.example or "power"
    if args.example == "power":
        if args.power_base is None:
            args.power_base = 2
        if args.power_exponent is None:
            args.power_exponent = 4
    args.out = _demo_output_path(args)
    args.pretty = True
    args.check = True
    args.explain = bool(args.full_explain)
    args.include_sympy = False
    args.quiet = False

    print_header("Demo: a concrete FOL statement compiled to Zinc")
    print(
        "This demo exports a small FOL witness, checks the mkQ/beta semantics, "
        "compiles the result to signed integer CCS/R1CS, and optionally invokes Zinc."
    )
    if args.example == "power":
        output = args.power_base ** args.power_exponent
        visibility = "public" if args.public_final else "private"
        line = f"Concrete computation: exact integer {args.power_base}^{args.power_exponent} = {output}."
        print(view_mod.emphasize_concrete_line(line))
        print(f"Visibility: {visibility} final claim.")
    print("")

    rc = cmd_export(args)
    if rc != 0:
        return rc

    try:
        export = view_mod.load_export(args.out)
    except Exception as exc:
        print(f"\nCould not inspect exported file {args.out}: {exc}", file=sys.stderr)
        return 1

    if args.matrix or args.constraints:
        print("")
        print(
            view_mod.format_inspection(
                export,
                path=args.out,
                matrix=args.matrix,
                constraints=args.constraints,
                matrix_head=args.matrix_head,
                matrix_tail=args.matrix_tail,
                constraint_head=args.constraint_head,
                constraint_tail=args.constraint_tail,
                full_matrix=args.full_matrix,
                full_constraints=args.full_constraints,
            )
        )

    zinc_rc = 0
    if args.zinc:
        print("\nRunning Zinc on the demo instance...")
        try:
            limb_rc = prepare_int_limb_request(args, args.out)
            if limb_rc != 0:
                return limb_rc
            cmd = cargo_runner_cmd(args, args.out)
        except SystemExit as exc:
            print(str(exc), file=sys.stderr)
            zinc_rc = 1
        else:
            zinc_rc = run_cargo_zinc(args, cmd, args.out)
        if zinc_rc == 0:
            print("\nZinc run completed: the Rust runner generated and verified a proof for the exported CCS relation.")
        else:
            print("\nZinc run did not complete successfully. The JSON was still exported and locally checked above.", file=sys.stderr)
    else:
        print("\nDemo export/check completed. Add --zinc to run the Rust Zinc prover/verifier as part of the demo.")

    _print_next_steps(args.out, zinc_attempted=args.zinc)
    return zinc_rc


def _clean_benchmark_dir(out_dir: Path, *, quiet: bool) -> None:
    """Remove old generated benchmark artifacts from one suite output directory.

    The default behaviour is non-destructive: stale files are ignored rather
    than run.  This helper is used only when the user explicitly passes
    --clean/--clean-output.
    """
    if not out_dir.exists():
        return
    removed = 0
    for pattern in ("*.json", "*.csv", "*.md"):
        for path in out_dir.glob(pattern):
            if path.is_file():
                path.unlink()
                removed += 1
    if removed and not quiet:
        print(f"cleaned {removed} old generated file(s) from {out_dir}")


def _note_ignored_stale_json(out_dir: Path, active_paths: list[Path], *, quiet: bool) -> None:
    if quiet or not out_dir.exists():
        return
    active = {path.resolve() for path in active_paths}
    stale = [path for path in sorted(out_dir.glob("*.json")) if path.resolve() not in active]
    if not stale:
        return
    names = ", ".join(path.name for path in stale[:5])
    more = "" if len(stale) <= 5 else f", ... ({len(stale)} total)"
    print(f"Note: ignoring stale JSON file(s) already present in {out_dir}: {names}{more}")
    print("      Only the benchmark inputs requested by this command will be explained/run. Use --clean to remove stale generated files first.")


def _selected_power_paths(args: argparse.Namespace, out_dir: Path) -> list[Path]:
    cases = list(bench_mod.BENCH_CASES)
    profile = getattr(args, "power_profile", "all")
    if getattr(args, "skip_standard", False):
        cases = [case for case in cases if not case.stem.startswith("standard_power")]
    elif profile == "efficient":
        cases = [case for case in cases if case.stem.startswith("efficient_")]
    elif profile == "standard":
        cases = [case for case in cases if case.stem.startswith("standard_")]
    if args.skip_256:
        cases = [case for case in cases if "256" not in case.stem]
    return [out_dir / f"{case.stem}.json" for case in cases]


def _selected_fib_paths(args: argparse.Namespace, out_dir: Path) -> list[Path]:
    n_values = tuple(args.n) if args.n else tuple(bench_mod.RISC0_FIBONACCI_N_VALUES)
    if args.skip_10000:
        n_values = tuple(n for n in n_values if n != 10000)
    return [out_dir / f"fibonacci_exact_n{int(n)}_public.json" for n in n_values]


def bench_export_power(args: argparse.Namespace) -> list[Path]:
    out_dir = args.out / "power"
    if getattr(args, "clean", False):
        _clean_benchmark_dir(out_dir, quiet=args.quiet)
    argv = ["export-power", "--out", str(out_dir)]
    if args.pretty:
        argv.append("--pretty")
    if not args.check:
        argv.append("--no-check")
    if args.skip_256:
        argv.append("--skip-256")
    if getattr(args, "skip_standard", False):
        argv.extend(["--power-case", "efficient"])
    elif getattr(args, "power_profile", "all") != "all":
        argv.extend(["--power-case", str(args.power_profile)])
    if args.quiet:
        argv.append("--quiet")
    rc = bench_mod.main(argv)
    if rc != 0:
        return []
    paths = [path for path in _selected_power_paths(args, out_dir) if path.exists()]
    _note_ignored_stale_json(out_dir, paths, quiet=args.quiet)
    return paths


def bench_export_fib(args: argparse.Namespace) -> list[Path]:
    out_dir = args.out / "risc0_fib_exact"
    if getattr(args, "clean", False):
        _clean_benchmark_dir(out_dir, quiet=args.quiet)
    argv = ["export-risc0-fib", "--out", str(out_dir)]
    if args.pretty:
        argv.append("--pretty")
    if not args.check:
        argv.append("--no-check")
    for n in args.n or []:
        argv.extend(["--n", str(n)])
    if args.skip_10000:
        argv.append("--skip-10000")
    if args.include_witness_rows:
        argv.append("--include-witness-rows")
    if getattr(args, "fib_profile", None):
        argv.extend(["--fib-profile", str(args.fib_profile)])
    if args.quiet:
        argv.append("--quiet")
    rc = bench_mod.main(argv)
    if rc != 0:
        return []
    paths = [path for path in _selected_fib_paths(args, out_dir) if path.exists()]
    _note_ignored_stale_json(out_dir, paths, quiet=args.quiet)
    return paths


def cmd_bench(args: argparse.Namespace) -> int:
    suites = ["power", "fib"] if args.suite == "all" else ["fib" if args.suite == "fibonacci" else args.suite]
    inputs: list[Path] = []
    if "power" in suites:
        print_header("Exporting power benchmark inputs")
        inputs.extend(bench_export_power(args))
    if "fib" in suites:
        print_header("Exporting exact non-modular Fibonacci benchmark inputs")
        print("Arithmetic note: FOL-Zinc uses exact integers here, not RISC Zero's modulo-2^64 Fibonacci arithmetic.")
        inputs.extend(bench_export_fib(args))
    if not inputs:
        print("no benchmark inputs were produced", file=sys.stderr)
        return 1
    if not bool(getattr(args, "quiet", False)):
        _print_concrete_claims(inputs)
    if not args.run:
        print("\nInputs exported. Add --run to invoke Zinc and write timing summaries.")
        return 0

    args.results.mkdir(parents=True, exist_ok=True)
    runs = args.results / f"fol_zinc_{args.suite}_runs.jsonl"
    run_argv = ["run-zinc", *[str(p) for p in inputs], "--repeat", str(args.repeat), "--out", str(runs), "--runner", str(runner_dir(args.runner))]
    if args.check_only:
        run_argv.append("--check-only")
    if args.int_limbs:
        run_argv.extend(["--int-limbs", str(args.int_limbs)])
    if bool(getattr(args, "strict_int_limbs", False)):
        run_argv.append("--strict-int-limbs")
    if not args.progress:
        run_argv.append("--no-progress")
    if getattr(args, "cargo_run", False):
        run_argv.append("--cargo-run")
    run_argv.extend(["--progress-interval", str(args.progress_interval)])
    run_argv.extend(["--max-single-allocation-gib", str(args.max_single_allocation_gib)])
    if args.allow_large:
        run_argv.append("--allow-large")
    if args.quiet:
        run_argv.append("--quiet")
    run_rc = bench_mod.main(run_argv)
    if run_rc != 0:
        print(
            "\nZinc run failed, so no run-based summary was written. "
            "Try the same command with --check-only to validate the exported integer relation, "
            "or rerun with --no-progress to see only Cargo/Zinc output.",
            file=sys.stderr,
        )
        return int(run_rc)

    summary = args.results / f"FOL_ZINC_{args.suite.upper()}_SUMMARY.md"
    csv_path = args.results / f"fol_zinc_{args.suite}_sizes.csv"
    sum_argv = ["summarize", *[str(p) for p in inputs], "--runs", str(runs), "--out", str(summary), "--csv", str(csv_path)]
    if args.zkvm_csv:
        sum_argv.extend(["--zkvm-csv", str(args.zkvm_csv)])
    if args.quiet:
        sum_argv.append("--quiet")
    bench_mod.main(sum_argv)
    print(f"\nRun data: {runs}")
    print(f"Summary:  {summary}")
    return 0


def cmd_estimate(args: argparse.Namespace) -> int:
    print_header("Zinc resource preflight estimate")
    any_skip = False
    for path in args.paths:
        try:
            effective_int_limbs, limb_note = normalize_int_limb_request(
                path,
                getattr(args, "int_limbs", None),
                strict=bool(getattr(args, "strict_int_limbs", False) or getattr(args, "force_int_limbs", False)),
            )
        except ValueError as exc:
            print(f"Invalid limb profile for {path}: {exc}", file=sys.stderr, flush=True)
            return 2
        if limb_note:
            print("Limb profile note: " + limb_note)
        estimate = estimate_zinc_resources(path, int_limbs=effective_int_limbs)
        skip, reason = would_skip_for_resources(
            estimate,
            allow_large=bool(args.allow_large),
            check_only=False,
            max_single_allocation_gib=float(args.max_single_allocation_gib or DEFAULT_MAX_SINGLE_ALLOCATION_GIB),
        )
        print(format_resource_estimate(estimate))
        try:
            import json
            with Path(path).open("r", encoding="utf-8") as f:
                print("  constraint shape: " + format_constraint_summary(json.load(f), padded=estimate.estimated_padded_dim))
        except Exception:
            pass
        if skip:
            any_skip = True
            print(f"  default action: skip/refuse ({reason})")
        else:
            print("  default action: run allowed")
    return 2 if any_skip and args.strict else 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="folzinc",
        description="One command for zkFOL -> Zinc export, explanation, proofs, and benchmarks.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--version", action="version", version=f"zkfol-zinc-adapter {__version__}")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("doctor", help="check layout, Python imports, Cargo, and runner status")
    p.add_argument("--runner", type=Path, default=None, help="Rust runner directory or Cargo.toml to check instead of the bundled runner")
    p.add_argument("--build", action="store_true", help="also run cargo build --release for the Rust runner")
    p.add_argument("--strict", action="store_true", help="return nonzero if an optional dependency such as Cargo is missing")
    p.add_argument("--quiet", action="store_true", help="suppress command echoing during the optional build")
    p.set_defaults(func=cmd_doctor)

    p = sub.add_parser("examples", help="list examples and benchmark suites")
    p.set_defaults(func=cmd_examples)

    p = sub.add_parser("options", aliases=["option-reference"], help="print the practical option reference")
    p.set_defaults(func=cmd_options)

    p = sub.add_parser("export", help="export one example to Zinc-compatible CCS/R1CS JSON")
    p.add_argument("example", nargs="?", choices=EXAMPLES + tuple(EXAMPLE_ALIASES.keys()), default=None, help="example family to export; default is power")
    p.add_argument("--example", dest="example_option", choices=EXAMPLES + tuple(EXAMPLE_ALIASES.keys()), default=None, help="alias for the positional example argument; useful when copying commands from run/bench examples")
    p.add_argument("--out", type=Path, default=Path("out/power.json"), help="output JSON path, or directory when exporting all examples")
    p.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python relation checker after export")
    p.add_argument("--pretty", action="store_true", help="write indented JSON for easier inspection")
    p.add_argument("--explain", action="store_true", help="print a field-by-field explanation of the exported relation")
    p.add_argument("--public-final", action="store_true", help="bind the final input/output cells as public inputs where the example supports it")
    p.add_argument("--include-sympy", action="store_true", help="embed textual SymPy mkQ expressions; useful for small-case auditing, large for big cases")
    p.add_argument("--quiet", action="store_true", help="print less status output; useful in scripts")
    add_example_inputs(p)
    p.set_defaults(func=cmd_export)

    p = sub.add_parser("explain", help="explain exported JSON")
    p.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s) to explain")
    p.add_argument("--compact", action="store_true", help="print a shorter summary instead of the full explanation")
    p.add_argument("--no-witness-preview", action="store_true", help="omit witness-row previews from the explanation")
    p.set_defaults(func=cmd_explain)

    p = sub.add_parser("check", help="pure-Python relation check on exported JSON")
    p.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s) to check")
    p.add_argument("--quiet", action="store_true", help="print only failures")
    p.set_defaults(func=cmd_check)

    p = sub.add_parser("estimate", aliases=["preflight", "resources"], help="estimate padded Zinc dimensions and large dense allocations before running")
    p.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s) to estimate before running Zinc")
    p.add_argument("--int-limbs", default=None, help="maximum Zinc integer profile to consider: auto, 2, 4, 8, 16, 32, 64, or 128")
    p.add_argument("--strict-int-limbs", "--force-int-limbs", dest="strict_int_limbs", action="store_true", help="honour --int-limbs exactly even when a smaller safe profile would suffice")
    p.add_argument("--max-single-allocation-gib", type=float, default=DEFAULT_MAX_SINGLE_ALLOCATION_GIB, help="preflight safety limit for one predicted dense Zinc allocation")
    p.add_argument("--allow-large", "--allow-large-zinc", "--run-large", dest="allow_large", action="store_true", help="show estimates but do not mark large cases as skipped")
    p.add_argument("--strict", action="store_true", help="return nonzero if any input would be skipped")
    p.set_defaults(func=cmd_estimate)

    p = sub.add_parser("inspect", aliases=["show", "matrix"], help="show concrete claim, witness matrix, and optional CCS rows")
    p.add_argument("paths", nargs="+", type=Path, help="exported JSON file(s) to inspect")
    p.add_argument("--matrix", action=argparse.BooleanOptionalAction, default=True, help="show the finite FOL witness matrix C")
    p.add_argument("--constraints", action="store_true", help="also show an abbreviated CCS/R1CS row preview")
    p.add_argument("--matrix-head", type=int, default=8, help="number of first witness-matrix columns to show")
    p.add_argument("--matrix-tail", type=int, default=4, help="number of last witness-matrix columns to show")
    p.add_argument("--constraint-head", type=int, default=4, help="number of first CCS/R1CS rows to show")
    p.add_argument("--constraint-tail", type=int, default=4, help="number of last CCS/R1CS rows to show")
    p.add_argument("--full-matrix", action="store_true", help="print every witness-matrix column; safe only for small examples")
    p.add_argument("--full-constraints", action="store_true", help="print every CCS/R1CS row; can be very large")
    p.set_defaults(func=cmd_inspect)

    p = sub.add_parser("build", help="cargo build --release for the Rust/Zinc runner")
    p.add_argument("--runner", type=Path, default=None, help="Rust runner directory or Cargo.toml to build instead of the bundled runner")
    p.add_argument("--quiet", action="store_true", help="do not echo the cargo command before running it")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("run", aliases=["prove"], help="run Zinc on an exported JSON file, or export first")
    p.add_argument("input_pos", nargs="?", type=Path, help="optional shorthand for --input")
    p.add_argument("--input", type=Path, default=None, help="existing exported JSON")
    p.add_argument("--example", choices=EXAMPLES[:-1] + tuple(EXAMPLE_ALIASES.keys()), default="power", help="example to export first when --input is not supplied")
    p.add_argument("--out", type=Path, default=None, help="JSON path when exporting first")
    p.add_argument("--repeat", type=int, default=3, help="number of prove/verify repetitions to average")
    p.add_argument("--check-only", action="store_true", help="check the integer relation locally and skip Zinc prove/verify")
    p.add_argument("--int-limbs", default=None, help="maximum Zinc Int<N> profile: auto, 2, 4, 8, 16, 32, 64, or 128")
    p.add_argument("--strict-int-limbs", "--force-int-limbs", dest="strict_int_limbs", action="store_true", help="honour --int-limbs exactly even when a smaller safe profile would suffice")
    p.add_argument("--json", action="store_true", help="print machine-readable JSON from the Rust runner instead of the human report")
    p.add_argument("--runner", type=Path, default=None, help="Rust runner directory or Cargo.toml to use instead of the bundled runner")
    p.add_argument("--cargo-run", action="store_true", help="force cargo run even if a built release binary exists")
    p.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python relation checker after exporting first")
    p.add_argument("--pretty", action="store_true", help="pretty-print exported JSON when exporting first")
    p.add_argument("--explain", action="store_true", help="print the exporter explanation before running Zinc")
    p.add_argument("--public-final", action="store_true", help="bind the final input/output cells as public inputs when exporting first")
    p.add_argument("--include-sympy", action="store_true", help="embed textual SymPy mkQ expressions when exporting first; use only for small/auditing cases")
    p.add_argument("--quiet", action="store_true", help="suppress wrapper status output where possible")
    p.add_argument("--progress", action=argparse.BooleanOptionalAction, default=True, help="show elapsed time, coarse progress, ETA estimate, CPU usage, and RSS memory while Cargo/Zinc runs")
    p.add_argument("--progress-interval", type=float, default=5.0, help="seconds between progress heartbeat lines")
    p.add_argument("--max-single-allocation-gib", type=float, default=DEFAULT_MAX_SINGLE_ALLOCATION_GIB, help="refuse proof runs whose estimated current-Zinc largest dense allocation exceeds this many GiB")
    p.add_argument("--allow-large", "--allow-large-zinc", "--run-large", dest="allow_large", action="store_true", help="override the memory preflight and launch Zinc even when the estimate is above the safety limit")
    add_example_inputs(p)
    p.set_defaults(func=cmd_run)

    p = sub.add_parser("demo", help="export/check/show a small concrete example; add --zinc to prove it")
    p.add_argument("--example", choices=EXAMPLES[:-1], default="power", help="small example to demonstrate; default is public 2^4 = 16")
    p.add_argument("--out", type=Path, default=None, help="where to write the demo JSON; default is out/demo_*.json")
    p.add_argument("--zinc", action="store_true", help="after exporting and inspecting, run the Rust/Zinc prover and verifier")
    p.add_argument("--repeat", type=int, default=1, help="number of Zinc prove/verify repetitions when --zinc is supplied")
    p.add_argument("--check-only", action="store_true", help="with --zinc, run only the Rust local relation check")
    p.add_argument("--int-limbs", default=None, help="maximum Zinc Int<N> profile: auto, 2, 4, 8, 16, 32, 64, or 128")
    p.add_argument("--strict-int-limbs", "--force-int-limbs", dest="strict_int_limbs", action="store_true", help="honour --int-limbs exactly even when a smaller safe profile would suffice")
    p.add_argument("--json", action="store_true", help="with --zinc, print machine-readable JSON from the Rust runner")
    p.add_argument("--runner", type=Path, default=None, help="Rust runner directory or Cargo.toml to use instead of the bundled runner")
    p.add_argument("--cargo-run", action="store_true", help="force cargo run even if a built release binary exists")
    p.add_argument("--public-final", action=argparse.BooleanOptionalAction, default=True, help="bind the final claim as public inputs")
    p.add_argument("--matrix", action=argparse.BooleanOptionalAction, default=True, help="show the FOL witness matrix preview")
    p.add_argument("--constraints", action="store_true", help="also show first/last CCS/R1CS rows")
    p.add_argument("--matrix-head", type=int, default=8, help="number of first witness-matrix columns to show")
    p.add_argument("--matrix-tail", type=int, default=4, help="number of last witness-matrix columns to show")
    p.add_argument("--constraint-head", type=int, default=4, help="number of first CCS/R1CS rows to show when --constraints is used")
    p.add_argument("--constraint-tail", type=int, default=4, help="number of last CCS/R1CS rows to show when --constraints is used")
    p.add_argument("--full-matrix", action="store_true", help="print every witness-matrix column; safe only for small examples")
    p.add_argument("--full-constraints", action="store_true", help="print every CCS/R1CS row; can be very large")
    p.add_argument("--full-explain", action="store_true", help="print the long field-by-field explanation during demo")
    p.add_argument("--progress", action=argparse.BooleanOptionalAction, default=True, help="show elapsed time, coarse progress, ETA estimate, CPU usage, and RSS memory while Cargo/Zinc runs")
    p.add_argument("--progress-interval", type=float, default=5.0, help="seconds between progress heartbeat lines")
    p.add_argument("--max-single-allocation-gib", type=float, default=DEFAULT_MAX_SINGLE_ALLOCATION_GIB, help="refuse proof runs whose estimated current-Zinc largest dense allocation exceeds this many GiB")
    p.add_argument("--allow-large", "--allow-large-zinc", "--run-large", dest="allow_large", action="store_true", help="override the memory preflight and launch Zinc even when the estimate is above the safety limit")
    add_example_inputs(p)
    p.set_defaults(func=cmd_demo)

    p = sub.add_parser("bench", help="export and optionally run benchmark suites")
    p.add_argument("suite", choices=("power", "fib", "fibonacci", "all"), help="benchmark suite to export/run")
    p.add_argument("--out", type=Path, default=Path("benchmark_inputs"), help="root directory for exported benchmark input JSON and size summaries")
    p.add_argument("--results", type=Path, default=Path("benchmark_results"), help="directory for run JSONL and Markdown/CSV summaries")
    p.add_argument("--run", action="store_true", help="invoke Zinc after exporting")
    p.add_argument("--repeat", type=int, default=3, help="number of prove/verify repetitions for each case when --run is supplied")
    p.add_argument("--check-only", action="store_true", help="when --run is supplied, run only the Rust local integer relation check")
    p.add_argument("--int-limbs", default=None, help="maximum Zinc Int<N> profile: auto, 2, 4, 8, 16, 32, 64, or 128")
    p.add_argument("--strict-int-limbs", "--force-int-limbs", dest="strict_int_limbs", action="store_true", help="honour --int-limbs exactly even when a smaller safe profile would suffice")
    p.add_argument("--runner", type=Path, default=None, help="Rust runner directory or Cargo.toml to use instead of the bundled runner")
    p.add_argument("--cargo-run", action="store_true", help="force cargo run even if a built release binary exists")
    p.add_argument("--n", type=int, action="append", help="Fibonacci index to export; repeat for several n values; default is 100, 1000, 10000")
    p.add_argument("--skip-10000", action="store_true", help="for the Fibonacci suite, omit F_10000")
    p.add_argument("--skip-256", action="store_true", help="for the power suite, omit the larger efficient 2^256 case")
    p.add_argument("--skip-standard", action="store_true", help="do not export the naive standard recursive 2^32 power case")
    p.add_argument("--power-profile", choices=("all", "efficient", "standard"), default="all", help="choose which power benchmark profile(s) to export")
    p.add_argument("--include-witness-rows", action="store_true", help="include duplicate full witness rows in Fibonacci metadata; off by default to keep large JSON smaller")
    p.add_argument("--fib-profile", choices=("compact", "full"), default="compact", help="for exact Fibonacci: compact is faster; full keeps the older explicit four-row direct trace")
    p.add_argument("--clean", "--clean-output", dest="clean", action="store_true", help="remove old generated JSON/CSV/Markdown files in this suite output directory before exporting")
    p.add_argument("--check", action=argparse.BooleanOptionalAction, default=True, help="run the pure-Python relation checker after each export")
    p.add_argument("--pretty", action="store_true", help="write indented JSON; slower/larger but easier to inspect")
    p.add_argument("--zkvm-csv", type=Path, default=None, help="optional CSV of external zkVM measurements to include in the benchmark summary")
    p.add_argument("--quiet", action="store_true", help="print less wrapper/exporter output")
    p.add_argument("--progress", action=argparse.BooleanOptionalAction, default=True, help="show elapsed time, coarse progress, ETA estimate, CPU usage, and RSS memory while Cargo/Zinc runs")
    p.add_argument("--progress-interval", type=float, default=5.0, help="seconds between progress heartbeat lines")
    p.add_argument("--max-single-allocation-gib", type=float, default=DEFAULT_MAX_SINGLE_ALLOCATION_GIB, help="skip proof runs whose estimated current-Zinc largest dense allocation exceeds this many GiB")
    p.add_argument("--allow-large", "--allow-large-zinc", "--run-large", dest="allow_large", action="store_true", help="override the memory preflight and launch Zinc even when the estimate is above the safety limit")
    p.set_defaults(func=cmd_bench)


    p = sub.add_parser("test", help="run the integrated regression suite")
    p.add_argument("paths", nargs="*", type=Path, help="optional pytest file/directory selection")
    p.add_argument("--install-dev", action="store_true", help="install requirements-dev.txt if pytest is missing")
    p.add_argument("--cargo", action="store_true", help="also run the Cargo build regression test")
    p.add_argument("--zinc-smoke", action="store_true", help="also run a tiny real Zinc prove/verify smoke test")
    p.add_argument("--full", action="store_true", help="equivalent to --cargo --zinc-smoke")
    p.add_argument("-k", "--keyword", default=None, help="pytest -k expression")
    p.add_argument("-x", "--fail-fast", action="store_true", help="stop after the first failure")
    p.add_argument("-v", "--verbose", action="store_true", help="verbose pytest output")
    p.add_argument("-s", "--show-output", action="store_true", help="do not capture test stdout/stderr")
    p.set_defaults(func=cmd_test)

    p = sub.add_parser("raw", help="power-user pass-through to old lower-level CLIs")
    p.add_argument("tool", choices=("export", "explain", "check", "bench", "inspect"), help="lower-level tool to invoke")
    p.add_argument("args", nargs=argparse.REMAINDER, help="arguments passed unchanged to the selected lower-level tool")
    p.set_defaults(func=cmd_raw)

    return parser



def _ensure_pytest_available(*, install_dev: bool) -> bool:
    try:
        import pytest  # noqa: F401
    except Exception as exc:
        if install_dev:
            req = adapter_dir() / "requirements-dev.txt"
            print(f"pytest is not available ({exc!r}); installing development requirements from {req}")
            rc = subprocess.run([sys.executable, "-m", "pip", "install", "-r", str(req)]).returncode
            if rc != 0:
                return False
            try:
                import pytest  # noqa: F401
            except Exception as exc2:
                print(f"pytest is still unavailable after installing development requirements: {exc2!r}", file=sys.stderr)
                return False
            return True
        print(
            "pytest is not installed in this environment. Run one of:\n"
            "  ./zkfol_zinc_adapter/folzinc setup --dev\n"
            "  ./zkfol_zinc_adapter/folzinc test --install-dev\n",
            file=sys.stderr,
        )
        return False
    return True


def cmd_test(args: argparse.Namespace) -> int:
    """Run the integrated regression suite.

    Default mode is a Python-only suite designed to be fast enough for routine
    development. ``--cargo`` opts into the real Rust build check, and
    ``--zinc-smoke`` additionally runs a tiny real Zinc proof if Cargo/Zinc are
    available on the host.
    """
    print_header(f"FOL-Zinc regression tests ({__version__})")
    sys.stdout.flush()
    if not _ensure_pytest_available(install_dev=bool(args.install_dev)):
        return 2

    env = os.environ.copy()
    if args.full:
        args.cargo = True
        args.zinc_smoke = True
    if args.cargo:
        env["FOLZINC_RUN_CARGO_TESTS"] = "1"
    if args.zinc_smoke:
        env["FOLZINC_RUN_CARGO_TESTS"] = "1"
        env["FOLZINC_RUN_ZINC_SMOKE"] = "1"

    pytest_args: list[str] = []
    pytest_args.append("-vv" if args.verbose else "-q")
    if args.fail_fast:
        pytest_args.append("-x")
    if args.show_output:
        pytest_args.append("-s")
    if args.keyword:
        pytest_args.extend(["-k", args.keyword])
    pytest_args.extend(str(path) for path in (args.paths or [adapter_dir() / "tests"]))

    print("Running: " + " ".join([sys.executable, "-m", "pytest", *pytest_args]), flush=True)
    if not args.cargo and not args.zinc_smoke:
        print("Cargo/Zinc tests are skipped by default. Add --cargo to check the Rust build, or --zinc-smoke for a tiny real proof.", flush=True)
    rc = subprocess.run([sys.executable, "-m", "pytest", *pytest_args], cwd=adapter_dir(), env=env).returncode
    if rc == 0:
        print("\nRegression suite completed successfully.")
    return rc

def cmd_raw(args: argparse.Namespace) -> int:
    if args.tool == "export":
        return export_mod.main(args.args)
    if args.tool == "explain":
        return explain_mod.main(args.args)
    if args.tool == "check":
        return check_mod.main(args.args)
    if args.tool == "bench":
        return bench_mod.main(args.args)
    if args.tool == "inspect":
        return view_mod.main(args.args)
    raise AssertionError(args.tool)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "input", None) is None and getattr(args, "input_pos", None) is not None:
        args.input = args.input_pos
    return args.func(args)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
