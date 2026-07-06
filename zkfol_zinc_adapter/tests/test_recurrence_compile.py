"""Detector-driven compilation: FOL predicate -> doubling export.

The emitter must be driven by the extracted descriptor alone (coefficients
p, q and bases), not by delegation to the hand-written Fibonacci export.
The non-vacuous evidence is the Lucas-style case: a recurrence never
hand-optimized anywhere in this repo, compiled end to end and judged
against an independent naive evaluation. Fibonacci is judged the same way
(by claimed value and relation check), plus a shape check that the compiled
trace is logarithmic like the hand one.
"""

import pytest

from zkfol.ast import cell, conj, disj
from zkfol.examples import factorial_predicate, fibonacci_predicate

from zkfol_zinc_adapter.r1cs import check_export_relation
from zkfol_zinc_adapter.recurrence_compile import (
    RecurrenceCompileError,
    compile_doubling_export,
)


def _naive(coeff1: int, coeff2: int, base1: int, base2: int, n: int) -> int:
    values = {1: base1, 2: base2}
    for k in range(3, n + 1):
        values[k] = coeff1 * values[k - 1] + coeff2 * values[k - 2]
    return values[n]


def _lucas_style_predicate():
    n = cell(1)
    value = cell(2)
    return disj(
        conj(n.eq(1), value.eq(7)),
        conj(n.eq(2), value.eq(4)),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2, 3) + cell(2, 3) + cell(2, 4) + cell(2, 4) + cell(2, 4)),
        ),
    )


@pytest.mark.parametrize("n", [1, 2, 3, 4, 10, 50, 100])
def test_compiles_fibonacci_predicate_by_value(n: int) -> None:
    export = compile_doubling_export(fibonacci_predicate(), n, check=True)
    check_export_relation(export)
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(_naive(1, 1, 1, 1, n))


def test_compiled_fibonacci_trace_is_logarithmic() -> None:
    export = compile_doubling_export(fibonacci_predicate(), 10000, check=True)
    assert export["dimensions"]["constraints"] < 60


def test_compiled_export_binds_claim_n_like_the_other_exporters() -> None:
    export = compile_doubling_export(fibonacci_predicate(), 100)
    bindings = {b["name"]: b["value"] for b in export["ccs"]["public_bindings"]}
    assert bindings["claim_n"] == "100"
    assert "claim_recurrence_n_exact" in bindings


@pytest.mark.parametrize("n", [1, 2, 3, 4, 5, 12, 50])
def test_compiles_never_hand_optimized_lucas_variant(n: int) -> None:
    export = compile_doubling_export(_lucas_style_predicate(), n, check=True)
    check_export_relation(export)
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(_naive(2, 3, 7, 4, n))


def test_surfaces_detector_reason_for_non_recurrences() -> None:
    with pytest.raises(RecurrenceCompileError, match="coefficient"):
        compile_doubling_export(factorial_predicate(), 100)


def test_compiled_claim_agrees_with_the_fol_judgement_at_small_n() -> None:
    """Semantic link between the two worlds, where both are computable.

    For small n the actual FOL judgement is checked by the reference
    evaluators (ExampleSpec.is_valid runs direct semantics, beta(mkQ), and
    pointer range checks), and the value cell of that valid witness must be
    exactly the constant the compiled circuit binds. This ties the compiled
    claim to the FOL statement empirically; for large n the equivalence
    rests on the value-claim legality argument.
    """
    from zkfol.examples import fibonacci_example

    for n in range(3, 21):
        example = fibonacci_example(n)
        assert example.is_valid()
        column = example.witness.row(1).index(n) + 1
        fol_value = example.witness.value(2, column)
        export = compile_doubling_export(example.predicate, n)
        claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
        assert claims["claim_recurrence_n_exact"] == str(fol_value)


def _zero_based_fibonacci_predicate():
    """Standard convention F(0)=0, F(1)=1 — bases start at index 0, not 1."""
    n = cell(1)
    value = cell(2)
    return disj(
        conj(n.eq(0), value.eq(0)),
        conj(n.eq(1), value.eq(1)),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2, 3) + cell(2, 4)),
        ),
    )


@pytest.mark.parametrize("n", [0, 1, 2, 3, 4, 10, 50])
def test_compiles_zero_based_fibonacci_bases(n: int) -> None:
    """The detector accepts any contiguous base start; the emitter must too,
    not crash with KeyError on the most common Fibonacci convention."""
    export = compile_doubling_export(_zero_based_fibonacci_predicate(), n, check=True)
    check_export_relation(export)
    values = {0: 0, 1: 1}
    for k in range(2, n + 1):
        values[k] = values[k - 1] + values[k - 2]
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(values[n])


def test_refuses_n_before_the_first_base_case() -> None:
    with pytest.raises(RecurrenceCompileError, match="precede"):
        compile_doubling_export(_zero_based_fibonacci_predicate(), -1)


def _pinned_base_power_predicate(pinned_base: int):
    """power_predicate whose base case also pins the base cell to a constant."""
    base = cell(1)
    exponent = cell(2)
    value = cell(3)
    previous = 4
    return disj(
        conj(exponent.eq(0), value.eq(1), base.eq(pinned_base)),
        conj(
            base.eq(cell(1, previous)),
            exponent.eq(cell(2, previous) + 1),
            value.eq(base * cell(3, previous)),
        ),
    )


def test_refuses_cell_values_contradicting_a_predicate_pinned_coefficient() -> None:
    """If the predicate pins the coefficient cell to 2, compiling under
    cell_values={1: 5} would claim 5^n, false for every FOL witness."""
    with pytest.raises(RecurrenceCompileError, match="pin"):
        compile_doubling_export(_pinned_base_power_predicate(2), 5, cell_values={1: 5})


def test_uses_the_predicate_pinned_coefficient_directly() -> None:
    export = compile_doubling_export(_pinned_base_power_predicate(2), 5, check=True)
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(2**5)
    # a consistent cell_values is also fine
    export = compile_doubling_export(_pinned_base_power_predicate(2), 5, cell_values={1: 2})
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(2**5)


def test_compiles_standard_power_statement_to_log_form() -> None:
    from zkfol.examples import power_predicate

    export = compile_doubling_export(power_predicate(), 32, cell_values={1: 2}, check=True)
    check_export_relation(export)
    claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
    assert claims["claim_recurrence_n_exact"] == str(2**32)
    assert export["dimensions"]["constraints"] < 15
    # length reports the geometric schedule actually emitted: bits of the
    # exponent after the leading one (5 for exponent 32), not the order-2 walk
    assert export["dimensions"]["length"] == 5


def test_compiled_power_agrees_with_the_fol_judgement_at_small_exponents() -> None:
    from zkfol.examples import power_example, power_predicate

    for exponent in range(1, 9):
        example = power_example(3, exponent)
        assert example.is_valid()
        column = example.witness.row(2).index(exponent) + 1
        fol_value = example.witness.value(3, column)
        export = compile_doubling_export(power_predicate(), exponent, cell_values={1: 3})
        claims = {c["name"]: c["value"] for c in export["ccs"]["public_claims"]}
        assert claims["claim_recurrence_n_exact"] == str(fol_value)
