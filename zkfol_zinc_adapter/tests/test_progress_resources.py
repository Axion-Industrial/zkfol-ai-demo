from __future__ import annotations

import json
import sys

import pytest

from zkfol_zinc_adapter.progress import (
    MemorySnapshot,
    ProgressState,
    _parse_proc_status,
    format_bytes,
    run_with_progress,
)
from zkfol_zinc_adapter.resources import estimate_zinc_resources, format_resource_estimate, would_skip_for_resources


def test_progress_heartbeat_mentions_memory():
    state = ProgressState.from_input(None, repeat=1, check_only=False)
    line = state.heartbeat(
        cpu_percent=123.4,
        memory=MemorySnapshot(
            rss_bytes=512 * 1024 * 1024,
            hwm_bytes=768 * 1024 * 1024,
            process_count=2,
            top_processes=[("zkfol-zinc-runner", 400 * 1024 * 1024)],
        ),
    )
    assert "CPU 123.4%" in line
    assert "RSS 512.0 MiB" in line
    assert "peak RSS 768.0 MiB" in line
    assert "procs 2" in line
    assert "top zkfol-zinc-runner:400.0 MiB" in line


def test_progress_state_counts_relation_field_prove_verify_units():
    state = ProgressState.from_input(None, repeat=1, check_only=False)
    assert state.total_units == 5
    for phase in ("relation_check", "field_setup", "field_relation_check", "prove", "verify"):
        state.handle_event({"phase": phase, "event": "end", "repeat": 1, "iteration": 1})
    assert state.completed_units == 5
    assert "100.0%" in state.heartbeat(cpu_percent=None)




def test_progress_state_reports_random_prime_setup_phase():
    state = ProgressState.from_input(None, repeat=1, check_only=False)
    state.handle_event(
        {
            "phase": "field_setup",
            "event": "start",
            "repeat": 1,
            "iteration": 1,
            "message": "sampling Zinc random prime for RandomField<256>",
        }
    )
    line = state.heartbeat(cpu_percent=99.9)
    assert "Zinc random-prime setup 1/1" in line
    assert "sampling Zinc random prime" in line


def test_proc_status_parser_reads_rss_and_hwm():
    status = """
Name:\tzkfol-zinc-runner
PPid:\t123
VmHWM:\t2048 kB
VmRSS:\t1024 kB
"""
    parsed = _parse_proc_status(status)
    assert parsed is not None
    assert parsed["ppid"] == 123
    assert parsed["rss_bytes"] == 1024 * 1024
    assert parsed["hwm_bytes"] == 2048 * 1024


def test_format_bytes_scales_to_gib():
    assert format_bytes(824633720832) == "768.0 GiB"


def test_resource_estimate_matches_observed_standard_power_allocation(synthetic_export):
    path = synthetic_export(
        name="standard_power_2_32_public",
        constraints=120_123,
        witness_variables=116_754,
        public_inputs=["0", "2", "32", str(2**32)],
        max_bits=64,
    )
    estimate = estimate_zinc_resources(path, int_limbs=2)
    assert estimate.estimated_padded_dim == 131_072
    assert estimate.largest_dense_allocation_bytes == 824_633_720_832
    assert "largest_dense=768.0 GiB" in format_resource_estimate(estimate)
    skip, reason = would_skip_for_resources(estimate, allow_large=False, check_only=False, max_single_allocation_gib=128.0)
    assert skip is True
    assert "above the configured" in str(reason)


def test_resource_estimate_normalizes_multi_public_inputs_to_runner_shape(synthetic_export):
    path = synthetic_export(
        name="public_claim_case",
        constraints=32,
        witness_variables=100,
        public_inputs=["0", "2", "32", str(2**32)],
        max_bits=64,
    )
    estimate = estimate_zinc_resources(path, int_limbs="auto")
    assert estimate.original_z_len == 105
    assert estimate.runner_z_len == 102
    assert estimate.public_inputs_original == 4
    assert estimate.public_inputs_runner == 1


def test_resource_estimate_rejects_unsupported_limb_profile(synthetic_export):
    path = synthetic_export()
    with pytest.raises(ValueError):
        estimate_zinc_resources(path, int_limbs=3)




def test_limb_normalization_downshifts_oversized_request(synthetic_export):
    from zkfol_zinc_adapter.resources import normalize_int_limb_request

    path = synthetic_export(name="tiny_fib", constraints=4, witness_variables=3, max_bits=2)
    effective, note = normalize_int_limb_request(path, 128)
    assert effective == 2
    assert note is not None
    assert "requested Int<128>" in note
    assert "using Int<2>" in note


def test_limb_normalization_strict_keeps_oversized_request(synthetic_export):
    from zkfol_zinc_adapter.resources import normalize_int_limb_request

    path = synthetic_export(name="tiny_fib", constraints=4, witness_variables=3, max_bits=2)
    effective, note = normalize_int_limb_request(path, 128, strict=True)
    assert effective == 128
    assert note is not None
    assert "oversized Int<128>" in note


def test_limb_normalization_rejects_too_small_request(synthetic_export):
    from zkfol_zinc_adapter.resources import normalize_int_limb_request

    path = synthetic_export(name="big_bits", constraints=4, witness_variables=3, max_bits=6942)
    with pytest.raises(ValueError, match="too small"):
        normalize_int_limb_request(path, 64)


def test_run_with_progress_captures_json_and_filters_machine_markers(tmp_path):
    script = tmp_path / "fake_runner.py"
    script.write_text(
        "import json, sys, time\n"
        "print('FOLZINC_PROGRESS ' + json.dumps({'phase':'relation_check','event':'end','repeat':1,'elapsed_ms':1}), file=sys.stderr, flush=True)\n"
        "time.sleep(0.05)\n"
        "print(json.dumps({'name':'fake','proved':True}))\n",
        encoding="utf-8",
    )
    result = run_with_progress(
        [sys.executable, str(script)],
        input_path=None,
        repeat=1,
        check_only=False,
        quiet=False,
        progress=True,
        interval=1.0,
        capture_stdout=True,
    )
    assert result.returncode == 0
    assert json.loads(result.stdout)["proved"] is True
    assert "FOLZINC_PROGRESS" not in result.stderr
