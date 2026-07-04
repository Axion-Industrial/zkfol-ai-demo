"""Fast-doubling exact-Fibonacci export.

The doubling formulation proves the same public claim as the compact direct
trace (exact integer F_n bound as a public relation constant) with a
logarithmic trace: per bit of n, three multiplication rows
(t1 = a*(2b-a), t2 = a^2, t3 = b^2) and no state-copy rows, since the next
state is expressible as linear forms over existing wires.
"""

import pytest

from zkfol_zinc_adapter.constraint_summary import compute_constraint_summary
from zkfol_zinc_adapter.fast_doubling_fibonacci import (
    build_fast_doubling_fibonacci_ccs_export,
)
from zkfol_zinc_adapter.r1cs import R1CSError, check_export_relation


def _reference_fib(n: int) -> int:
    a, b = 1, 1
    for _ in range(n - 1):
        a, b = b, a + b
    return a


def test_small_export_satisfies_relation_and_claims_f10() -> None:
    export = build_fast_doubling_fibonacci_ccs_export(10, check=True)
    check_export_relation(export)
    claims = {claim["name"]: claim["value"] for claim in export["ccs"]["public_claims"]}
    assert claims["claim_fibonacci_n_exact"] == "55"


@pytest.mark.parametrize("n", [1, 2, 3, 7, 10, 30, 100, 1000])
def test_claimed_value_matches_reference(n: int) -> None:
    export = build_fast_doubling_fibonacci_ccs_export(n, check=True)
    claims = {claim["name"]: claim["value"] for claim in export["ccs"]["public_claims"]}
    assert claims["claim_fibonacci_n_exact"] == str(_reference_fib(n))


def test_trace_is_logarithmic_in_n() -> None:
    export = build_fast_doubling_fibonacci_ccs_export(1000)
    assert export["dimensions"]["constraints"] < 50
    assert export["dimensions"]["witness_variables"] < 50
    summary = compute_constraint_summary(export)
    assert summary["padded_ccs_dimension_estimate"] <= 64


def test_tampered_claim_fails_relation_check() -> None:
    export = build_fast_doubling_fibonacci_ccs_export(10)
    binding = export["ccs"]["constraints"][-1]
    assert "public_binding" in binding["label"]
    binding["c"] = [[idx, ("56" if coeff == "55" else coeff)] for idx, coeff in binding["c"]]
    with pytest.raises(R1CSError):
        check_export_relation(export)
