from __future__ import annotations

from zkfol_zinc_adapter.direct_fibonacci import build_direct_fibonacci_ccs_export, fibonacci_trace
from zkfol_zinc_adapter.r1cs import check_export_relation


def test_direct_fibonacci_exact_compact_export_checks():
    export = build_direct_fibonacci_ccs_export(10, check=True)
    check_export_relation(export)
    assert export["schema"] == "zkfol-zinc-ccs-v2"
    assert export["exact_arithmetic"]["modulus"] is None
    assert export["ccs"]["public_inputs"] == ["0"]
    assert export["ccs"]["public_claims"][0]["value"] == "10"
    assert export["ccs"]["public_claims"][1]["value"] == "55"
    assert export["ccs"]["public_claims"][1]["encoded_as"] == "public_ccs_constant"
    assert export["fibonacci_profile"] == "compact"
    assert export["dimensions"]["constraints"] == 11
    assert export["dimensions"]["witness_variables"] == 10
    assert export["constraint_breakdown"]["direct_fibonacci_step_checks"] == 8
    assert export["constraint_breakdown"]["direct_fibonacci_pointer_checks"] == 0
    assert "no modulo 2^64" in "\n".join(export["exposition"]["concrete_statement"])


def test_direct_fibonacci_full_profile_remains_available():
    full = build_direct_fibonacci_ccs_export(10, check=True, profile="full")
    check_export_relation(full)
    assert full["fibonacci_profile"] == "full"
    assert full["dimensions"]["constraints"] == 50
    assert full["constraint_breakdown"]["direct_fibonacci_pointer_checks"] > 0


def test_compact_fibonacci_rows_are_positive_oriented_without_negative_coefficients():
    export = build_direct_fibonacci_ccs_export(20, check=True, profile="compact")
    assert export["row_orientation"] == "positive_left_times_one_equals_right"
    negatives = []
    for row in export["ccs"]["constraints"]:
        for side in ("a", "b", "c"):
            negatives.extend(int(coeff) for _idx, coeff in row[side] if int(coeff) < 0)
    assert negatives == []


def test_fibonacci_trace_uses_standard_exact_values_not_modulo_2_64():
    trace = fibonacci_trace(100)
    assert trace.output == 354224848179261915075
    assert trace.output > 2**64
    assert trace.output % (2**64) != trace.output


def test_compact_fibonacci_size_scales_linearly():
    export = build_direct_fibonacci_ccs_export(100, check=True, profile="compact")
    assert export["dimensions"]["constraints"] == 101
    assert export["dimensions"]["witness_variables"] == 100
    assert export["exact_arithmetic"]["output_bit_length"] == 69
