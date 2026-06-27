from __future__ import annotations

import argparse
import json
from pathlib import Path

import pytest

try:
    from zkfol.cli import ExampleInputs, select_examples
except ModuleNotFoundError:  # optional sibling package used by one integration-style test
    ExampleInputs = None
    select_examples = None

from zkfol_zinc_adapter import cli
from zkfol_zinc_adapter.direct_fibonacci import build_direct_fibonacci_ccs_export
from zkfol_zinc_adapter.r1cs import build_ccs_export


def test_bench_fib_export_ignores_stale_json(tmp_path, monkeypatch):
    out_root = tmp_path / "benchmark_inputs"
    suite_dir = out_root / "risc0_fib_exact"
    suite_dir.mkdir(parents=True)
    stale = suite_dir / "fibonacci_exact_n100_public.json"
    stale.write_text("{}\n", encoding="utf-8")
    active = suite_dir / "fibonacci_exact_n1000_public.json"

    def fake_bench_main(argv):
        active.write_text("{}\n", encoding="utf-8")
        return 0

    monkeypatch.setattr(cli.bench_mod, "main", fake_bench_main)
    args = argparse.Namespace(
        out=out_root,
        pretty=False,
        check=True,
        n=[1000],
        skip_10000=False,
        include_witness_rows=False,
        fib_profile="compact",
        quiet=True,
        clean=False,
    )

    assert cli.bench_export_fib(args) == [active]
    assert stale.exists()


def test_bench_clean_removes_stale_json(tmp_path, monkeypatch):
    out_root = tmp_path / "benchmark_inputs"
    suite_dir = out_root / "risc0_fib_exact"
    suite_dir.mkdir(parents=True)
    stale = suite_dir / "fibonacci_exact_n100_public.json"
    stale.write_text("{}\n", encoding="utf-8")
    active = suite_dir / "fibonacci_exact_n1000_public.json"

    def fake_bench_main(argv):
        active.write_text("{}\n", encoding="utf-8")
        return 0

    monkeypatch.setattr(cli.bench_mod, "main", fake_bench_main)
    args = argparse.Namespace(
        out=out_root,
        pretty=False,
        check=True,
        n=[1000],
        skip_10000=False,
        include_witness_rows=False,
        fib_profile="compact",
        quiet=True,
        clean=True,
    )

    assert cli.bench_export_fib(args) == [active]
    assert not stale.exists()


def test_bench_power_profile_selects_only_requested_files(tmp_path, monkeypatch):
    out_root = tmp_path / "benchmark_inputs"
    out_dir = out_root / "power"
    out_dir.mkdir(parents=True)
    stale = out_dir / "standard_power_2_32_public.json"
    stale.write_text("{}\n", encoding="utf-8")
    active = out_dir / "efficient_power_2_32_public.json"

    def fake_bench_main(argv):
        assert "--power-case" in argv
        assert "efficient" in argv
        active.write_text("{}\n", encoding="utf-8")
        return 0

    monkeypatch.setattr(cli.bench_mod, "main", fake_bench_main)
    args = argparse.Namespace(
        out=out_root,
        pretty=False,
        check=True,
        skip_256=True,
        skip_standard=False,
        power_profile="efficient",
        quiet=True,
        clean=False,
    )

    assert cli.bench_export_power(args) == [active]
    assert stale.exists()


def test_print_concrete_claims_only_prints_selected_fibonacci_file(tmp_path, capsys):
    old = build_direct_fibonacci_ccs_export(100, check=True)
    new = build_direct_fibonacci_ccs_export(1000, check=True)
    old_path = tmp_path / "fibonacci_exact_n100_public.json"
    new_path = tmp_path / "fibonacci_exact_n1000_public.json"
    old_path.write_text(json.dumps(old), encoding="utf-8")
    new_path.write_text(json.dumps(new), encoding="utf-8")

    cli._print_concrete_claims([new_path])
    out = capsys.readouterr().out
    assert "F_1000" in out
    assert "F_100 =" not in out


def test_run_command_prints_concrete_power_claim_before_runner(tmp_path, monkeypatch, capsys):
    if ExampleInputs is None or select_examples is None:
        pytest.skip("zkfol_reference is not installed")
    example = select_examples("power", ExampleInputs(power_base=3, power_exponent=5))[0]
    export = build_ccs_export(example, public_final=True)
    path = tmp_path / "power.json"
    path.write_text(json.dumps(export), encoding="utf-8")

    called = {}

    def fake_run_cargo_zinc(args, cmd, input_path):
        called["input"] = input_path
        return 0

    monkeypatch.setattr(cli, "run_cargo_zinc", fake_run_cargo_zinc)
    args = argparse.Namespace(
        input=path,
        input_pos=None,
        out=None,
        example="power",
        repeat=1,
        check_only=False,
        int_limbs=None,
        strict_int_limbs=False,
        json=False,
        runner=None,
        cargo_run=False,
        check=True,
        pretty=False,
        explain=False,
        public_final=True,
        include_sympy=False,
        quiet=False,
        progress=True,
        progress_interval=5.0,
        max_single_allocation_gib=128.0,
        allow_large=False,
    )
    assert cli.cmd_run(args) == 0
    out = capsys.readouterr().out
    assert "Concrete computation: exact integer 3^5 = 243." in out
    assert called["input"] == path


def test_cargo_runner_cmd_prefers_built_release_binary(tmp_path):
    runner = tmp_path / "runner"
    binary = runner / "target" / "release" / "zkfol-zinc-runner"
    binary.parent.mkdir(parents=True)
    binary.write_text(f"#!/bin/sh\nprintf 'zkfol-zinc-runner {cli.__version__}\\n'\nexit 0\n", encoding="utf-8")
    binary.chmod(0o755)
    args = argparse.Namespace(
        runner=runner,
        repeat=3,
        cargo_run=False,
        check_only=False,
        int_limbs=None,
        strict_int_limbs=False,
        allow_large=False,
        max_single_allocation_gib=None,
        json=True,
        progress=True,
        quiet=False,
    )
    cmd = cli.cargo_runner_cmd(args, Path("input.json"))
    assert Path(cmd[0]) == binary
    assert Path(cmd[0]).name == "zkfol-zinc-runner"




def test_cargo_runner_cmd_ignores_stale_release_binary(tmp_path, monkeypatch, capsys):
    runner = tmp_path / "runner"
    binary = runner / "target" / "release" / "zkfol-zinc-runner"
    binary.parent.mkdir(parents=True)
    binary.write_text("#!/bin/sh\necho zkfol-zinc-runner 0.0.1\n", encoding="utf-8")
    binary.chmod(0o755)
    (runner / "Cargo.toml").write_text(f"[package]\nname='fake'\nversion='{cli.__version__}'\nedition='2021'\n", encoding="utf-8")
    monkeypatch.setattr(cli.shutil, "which", lambda name: "cargo" if name == "cargo" else None)
    args = argparse.Namespace(
        runner=runner,
        repeat=1,
        cargo_run=False,
        check_only=False,
        int_limbs=None,
        strict_int_limbs=False,
        allow_large=False,
        max_single_allocation_gib=None,
        json=True,
        progress=True,
        quiet=False,
    )
    cmd = cli.cargo_runner_cmd(args, Path("input.json"))
    assert cmd[0] == "cargo"
    assert "--manifest-path" in cmd
    assert "reports version 0.0.1" in capsys.readouterr().err


def test_cargo_runner_cmd_uses_current_release_binary(tmp_path):
    runner = tmp_path / "runner"
    binary = runner / "target" / "release" / "zkfol-zinc-runner"
    binary.parent.mkdir(parents=True)
    binary.write_text(f"#!/bin/sh\necho zkfol-zinc-runner {cli.__version__}\n", encoding="utf-8")
    binary.chmod(0o755)
    args = argparse.Namespace(
        runner=runner,
        repeat=1,
        cargo_run=False,
        check_only=False,
        int_limbs=None,
        strict_int_limbs=False,
        allow_large=False,
        max_single_allocation_gib=None,
        json=True,
        progress=True,
        quiet=False,
    )
    cmd = cli.cargo_runner_cmd(args, Path("input.json"))
    assert Path(cmd[0]) == binary


def test_parser_includes_test_command():
    parser = cli.build_parser()
    assert "test" in parser.format_help()


def test_export_accepts_example_option_alias(monkeypatch, tmp_path):
    captured = {}

    def fake_export_main(argv):
        captured["argv"] = list(argv)
        return 0

    monkeypatch.setattr(cli.export_mod, "main", fake_export_main)
    args = argparse.Namespace(
        example=None,
        example_option="efficient",
        out=tmp_path / "efficient.json",
        pretty=False,
        check=True,
        explain=False,
        public_final=True,
        include_sympy=False,
        quiet=False,
        power_base=None,
        power_exponent=None,
        efficient_base=2,
        efficient_exponent=8,
        factorial_n=None,
        fibonacci_n=None,
    )
    assert cli.cmd_export(args) == 0
    assert captured["argv"][:4] == ["--example", "efficient", "--out", str(tmp_path / "efficient.json")]
    assert "--public-final" in captured["argv"]


def test_export_rejects_conflicting_positional_and_example_option(tmp_path, capsys):
    args = argparse.Namespace(
        example="power",
        example_option="efficient",
        out=tmp_path / "x.json",
        pretty=False,
        check=True,
        explain=False,
        public_final=False,
        include_sympy=False,
        quiet=False,
        power_base=None,
        power_exponent=None,
        efficient_base=None,
        efficient_exponent=None,
        factorial_n=None,
        fibonacci_n=None,
    )
    assert cli.cmd_export(args) == 2
    assert "positional example or --example" in capsys.readouterr().err
