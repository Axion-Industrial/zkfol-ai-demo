from __future__ import annotations

import argparse
import json
from pathlib import Path

import pytest

from zkfol_zinc_adapter import bench as bench_mod
from zkfol_zinc_adapter.progress import ProcessResult


def _run_args(tmp_path: Path, inputs: list[Path], *, quiet: bool = True) -> argparse.Namespace:
    runner = tmp_path / "runner"
    runner.mkdir(parents=True, exist_ok=True)
    (runner / "Cargo.toml").write_text("[package]\nname='fake'\nversion='0.0.0'\nedition='2021'\n", encoding="utf-8")
    return argparse.Namespace(
        inputs=[str(path) for path in inputs],
        runner=runner,
        cargo_run=False,
        out=tmp_path / "runs.jsonl",
        repeat=1,
        check_only=False,
        int_limbs=None,
        strict_int_limbs=False,
        force_int_limbs=False,
        quiet=quiet,
        progress=False,
        progress_interval=1.0,
        max_single_allocation_gib=128.0,
        allow_large=False,
    )


def test_benchmark_json_extractor_handles_nested_runner_report():
    pretty = """
    runner prelude
    {
      "name": "case",
      "schema": "zkfol-zinc-ccs-v2",
      "proved": true,
      "constraint_breakdown": {
        "direct_fibonacci_step_checks": 29994
      }
    }
    """
    parsed = bench_mod._extract_json_object(pretty)
    assert parsed["proved"] is True
    assert parsed["constraint_breakdown"]["direct_fibonacci_step_checks"] == 29994


def test_benchmark_json_extractor_rejects_empty_output():
    with pytest.raises(ValueError):
        bench_mod._extract_json_object("\n\t")


def test_filtered_failure_stderr_removes_progress_markers():
    stderr = "FOLZINC_PROGRESS {\"phase\":\"prove\"}\nreal error\nFOLZINC_PROGRESS {\"phase\":\"verify\"}\n"
    filtered = bench_mod._filtered_stderr_for_failure(stderr)
    assert "FOLZINC_PROGRESS" not in filtered
    assert "real error" in filtered


def test_run_zinc_resource_skip_writes_skip_record_without_launching(tmp_path, synthetic_export, monkeypatch):
    large = synthetic_export(
        name="standard_power_2_32_public",
        constraints=120_123,
        witness_variables=116_754,
        public_inputs=["0", "2", "32", str(2**32)],
        max_bits=64,
    )

    def should_not_launch(*_args, **_kwargs):
        raise AssertionError("run_with_progress should not be called for resource-skipped input")

    monkeypatch.setattr(bench_mod, "run_with_progress", should_not_launch)
    args = _run_args(tmp_path, [large])
    assert bench_mod.run_zinc(args) == 0
    rows = [json.loads(line) for line in args.out.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == 1
    assert rows[0]["skipped"] is True
    assert rows[0]["mode"] == "skipped-by-resource-preflight"
    assert rows[0]["estimated_largest_dense_allocation"] == "768.0 GiB"




def test_run_zinc_downsizes_oversized_int_limb_request_for_tiny_case(tmp_path, synthetic_export, monkeypatch, capsys):
    tiny = synthetic_export(name="fibonacci_exact_n3_public", constraints=4, witness_variables=3, max_bits=2)
    seen_cmds: list[list[str]] = []

    def fake_run_with_progress(cmd, **kwargs):
        seen_cmds.append(list(cmd))
        return ProcessResult(
            0,
            json.dumps(
                {
                    "name": "fibonacci_exact_n3_public",
                    "schema": "zkfol-zinc-ccs-v2",
                    "proved": True,
                    "relation_check_ms": 1.0,
                    "prove_ms": 2.0,
                    "verify_ms": 3.0,
                    "constraint_breakdown": {"other": 4},
                }
            ),
            "",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [tiny], quiet=False)
    args.int_limbs = "128"
    assert bench_mod.run_zinc(args) == 0
    assert seen_cmds
    cmd = seen_cmds[0]
    assert "--int-limbs" in cmd
    assert cmd[cmd.index("--int-limbs") + 1] == "2"
    captured = capsys.readouterr()
    assert "requested Int<128>/RandomField<256>" in captured.out
    assert "using Int<2>" in captured.out


def test_run_zinc_passes_field_limbs_through_to_the_runner(tmp_path, synthetic_export, monkeypatch):
    """The decoupled Int<N>/RandomField<4> profile the CRT exports recommend
    must be reachable through the wrapper, not only by invoking the Rust
    runner by hand."""
    small = synthetic_export(name="crt_case", constraints=8, witness_variables=4, max_bits=900)
    seen_cmds: list[list[str]] = []

    def fake_run_with_progress(cmd, **kwargs):
        seen_cmds.append(list(cmd))
        return ProcessResult(
            0,
            json.dumps({"name": "crt_case", "schema": "zkfol-zinc-ccs-v2", "proved": True}),
            "",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [small])
    args.field_limbs = "4"
    assert bench_mod.run_zinc(args) == 0
    cmd = seen_cmds[0]
    assert cmd[cmd.index("--field-limbs") + 1] == "4"
    # auto (the default) leaves the runner in the legacy F=2N pairing
    seen_cmds.clear()
    args = _run_args(tmp_path, [small])
    assert bench_mod.run_zinc(args) == 0
    assert "--field-limbs" not in seen_cmds[0]


def test_run_zinc_can_force_oversized_int_limb_request(tmp_path, synthetic_export, monkeypatch):
    tiny = synthetic_export(name="fibonacci_exact_n3_public", constraints=4, witness_variables=3, max_bits=2)
    seen_cmds: list[list[str]] = []

    def fake_run_with_progress(cmd, **kwargs):
        seen_cmds.append(list(cmd))
        return ProcessResult(
            0,
            json.dumps({"name": "fibonacci_exact_n3_public", "schema": "zkfol-zinc-ccs-v2", "proved": True}),
            "",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [tiny])
    args.int_limbs = "128"
    args.strict_int_limbs = True
    assert bench_mod.run_zinc(args) == 0
    cmd = seen_cmds[0]
    assert cmd[cmd.index("--int-limbs") + 1] == "128"


def test_run_zinc_success_collects_pretty_nested_json(tmp_path, synthetic_export, monkeypatch):
    small = synthetic_export(name="small_case", constraints=8, witness_variables=4, max_bits=64)

    def fake_run_with_progress(cmd, **kwargs):
        assert "--json" in cmd
        return ProcessResult(
            0,
            json.dumps(
                {
                    "name": "small_case",
                    "schema": "zkfol-zinc-ccs-v2",
                    "proved": True,
                    "relation_check_ms": 1.0,
                    "prove_ms": 2.0,
                    "verify_ms": 3.0,
                    "constraint_breakdown": {"other": 8},
                },
                indent=2,
            ),
            "FOLZINC_PROGRESS {\"phase\":\"finish\"}\n",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [small])
    assert bench_mod.run_zinc(args) == 0
    rows = [json.loads(line) for line in args.out.read_text(encoding="utf-8").splitlines()]
    assert rows[0]["case"] == "small_case"
    assert rows[0]["proved"] is True
    assert rows[0]["resource_preflight"]["skipped"] is False


def test_run_zinc_failure_returns_nonzero_and_filters_progress(tmp_path, synthetic_export, monkeypatch, capsys):
    small = synthetic_export(name="failing_case", constraints=8, witness_variables=4, max_bits=64)

    def fake_run_with_progress(cmd, **kwargs):
        return ProcessResult(
            101,
            "partial stdout\n",
            "FOLZINC_PROGRESS {\"phase\":\"prove\"}\nZinc proof verification failed\n",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [small], quiet=False)
    assert bench_mod.run_zinc(args) == 101
    captured = capsys.readouterr()
    assert "Zinc proof verification failed" in captured.err
    assert "FOLZINC_PROGRESS" not in captured.err




def test_run_zinc_downshifts_oversized_limb_request(tmp_path, synthetic_export, monkeypatch, capsys):
    tiny = synthetic_export(name="fibonacci_exact_n3_public", constraints=4, witness_variables=3, max_bits=2)

    def fake_run_with_progress(cmd, **kwargs):
        assert "--int-limbs" in cmd
        idx = cmd.index("--int-limbs")
        assert cmd[idx + 1] == "2"
        assert "128" not in cmd[idx : idx + 2]
        return ProcessResult(
            0,
            json.dumps({"name": "fibonacci_exact_n3_public", "schema": "zkfol-zinc-ccs-v2", "proved": True}),
            "",
        )

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [tiny], quiet=False)
    args.int_limbs = 128
    assert bench_mod.run_zinc(args) == 0
    captured = capsys.readouterr()
    assert "requested Int<128>" in captured.out
    rows = [json.loads(line) for line in args.out.read_text(encoding="utf-8").splitlines()]
    assert rows[0]["effective_int_limbs"] == 2


def test_run_zinc_strict_limb_request_is_passed_through(tmp_path, synthetic_export, monkeypatch):
    tiny = synthetic_export(name="fibonacci_exact_n3_public", constraints=4, witness_variables=3, max_bits=2)

    def fake_run_with_progress(cmd, **kwargs):
        assert "--int-limbs" in cmd
        idx = cmd.index("--int-limbs")
        assert cmd[idx + 1] == "128"
        assert "--strict-int-limbs" not in cmd  # strict/force is handled by the Python wrapper, not by Rust
        return ProcessResult(0, json.dumps({"name": "fibonacci_exact_n3_public", "proved": True}), "")

    monkeypatch.setattr(bench_mod, "run_with_progress", fake_run_with_progress)
    args = _run_args(tmp_path, [tiny])
    args.int_limbs = 128
    args.strict_int_limbs = True
    assert bench_mod.run_zinc(args) == 0


def test_markdown_summary_includes_resource_skip_explanation(tmp_path):
    size_rows = [
        {
            "case": "standard_power_2_32_public",
            "profile": "generic",
            "length": 33,
            "max_bits": 33,
            "public_inputs": 4,
            "constraints": 120_123,
            "witness_variables": 116_754,
            "z_len": 116_759,
            "max_abs_value_bit_length": 64,
            "exact_output_bits": "",
            "exact_output_decimal_digits": "",
        }
    ]
    run_rows = [
        {
            "case": "standard_power_2_32_public",
            "skipped": True,
            "skip_reason": "estimated largest dense Zinc allocation is 768.0 GiB",
            "estimated_largest_dense_allocation": "768.0 GiB",
        }
    ]
    out = tmp_path / "summary.md"
    bench_mod.write_markdown_summary(out, size_rows, run_rows)
    text = out.read_text(encoding="utf-8")
    assert "skipped-resource-guard" in text
    assert "not failed proofs" in text
    assert "768.0 GiB" in text
