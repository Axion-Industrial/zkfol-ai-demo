"""C-finite recurrence recognition over the FOL fragment.

Pre-registered claim under test: a small syntactic analysis can decide, from
the predicate alone (no witness access), whether the inductive step is a
constant-coefficient linear recurrence over pointed predecessor cells - the
legality guard for the fast-doubling/matrix-power rewrite. It must fire on
Fibonacci, extract the right descriptor, and refuse factorial (coefficient
varies along the trace) and repeated-squaring power (nonlinear step) with
stated reasons. If this cannot be built small and sound, the "the doubling
pass generalizes" thesis is dead.
"""

from zkfol.ast import Index, cell, conj, disj
from zkfol.examples import (
    efficient_power_predicate,
    factorial_predicate,
    fibonacci_predicate,
)

from zkfol_zinc_adapter.recurrence import detect_linear_recurrence


def test_detects_fibonacci_and_extracts_descriptor() -> None:
    detection = detect_linear_recurrence(fibonacci_predicate())
    assert detection.reason is None
    d = detection.descriptor
    assert d is not None
    assert d.order == 2
    assert d.value_row == 2
    assert d.index_row == 1
    # offsets -1 and -2, both with coefficient 1: F(k) = 1*F(k-1) + 1*F(k-2)
    assert d.coefficients == ((-1, 1), (-2, 1))
    assert d.initial_values == ((1, 1), (2, 1))


def test_detects_synthetic_lucas_style_recurrence() -> None:
    n = cell(1)
    value = cell(2)
    predicate = disj(
        conj(n.eq(1), value.eq(7)),
        conj(n.eq(2), value.eq(4)),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2, 3) + cell(2, 3) + cell(2, 4) + cell(2, 4) + cell(2, 4)),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    d = detection.descriptor
    assert d is not None
    assert d.coefficients == ((-1, 2), (-2, 3))
    assert d.initial_values == ((1, 7), (2, 4))


def test_rejects_factorial_because_coefficient_varies() -> None:
    detection = detect_linear_recurrence(factorial_predicate())
    assert detection.descriptor is None
    assert "coefficient" in detection.reason


def test_rejects_efficient_power_because_step_is_nonlinear() -> None:
    detection = detect_linear_recurrence(efficient_power_predicate())
    assert detection.descriptor is None
    assert "linear" in detection.reason


def test_detects_standard_power_with_trace_constant_cell_coefficient() -> None:
    from zkfol.examples import power_predicate

    detection = detect_linear_recurrence(power_predicate())
    assert detection.reason is None
    d = detection.descriptor
    assert d is not None
    assert d.order == 1
    assert d.index_row == 2
    assert d.value_row == 3
    # coefficient is the base cell (row 1), licensed by its offset-0 constancy schedule
    assert d.coefficients == ((-1, ("cell", 1)),)
    # exponent counts from 0: base case pins index 0 to value 1
    assert d.initial_values == ((0, 1),)


def test_still_rejects_factorial_whose_coefficient_row_varies() -> None:
    detection = detect_linear_recurrence(factorial_predicate())
    assert detection.descriptor is None
    assert "coefficient" in detection.reason


def test_rejects_affine_cell_coefficient_instead_of_dropping_its_constant() -> None:
    """x(k) = (base + 5) * x(k-1) is not a pure cell-coefficient recurrence.

    Folding the multiplication must not silently discard the 5 * x(k-1)
    cross term; a compiled claim from the truncated descriptor would prove
    base^k where the predicate computes (base+5)^k.
    """
    base = cell(1)
    exponent = cell(2)
    value = cell(3)
    previous = 4
    predicate = disj(
        conj(exponent.eq(0), value.eq(1)),
        conj(
            base.eq(cell(1, previous)),
            exponent.eq(cell(2, previous) + 1),
            value.eq((base + 5) * cell(3, previous)),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    assert detection.descriptor is None
    assert "affine" in detection.reason


def test_rejects_mixed_literal_and_cell_coefficients_on_one_pointer() -> None:
    """x(k) = base*x(k-1) + x(k-1) puts two coefficient terms on the same
    pointer; assembling them must refuse, not let one overwrite the other."""
    base = cell(1)
    exponent = cell(2)
    value = cell(3)
    previous = 4
    predicate = disj(
        conj(exponent.eq(0), value.eq(1)),
        conj(
            base.eq(cell(1, previous)),
            exponent.eq(cell(2, previous) + 1),
            value.eq(base * cell(3, previous) + cell(3, previous)),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    assert detection.descriptor is None
    assert "coefficient" in detection.reason


def test_rejects_predicate_weakened_by_a_non_pinning_base_branch() -> None:
    """A bare value.eq(0) branch admits value 0 at any index.

    The predicate no longer determines F(n), so a definite value claim is
    unsound; the branch must force refusal rather than be skipped.
    """
    n = cell(1)
    value = cell(2)
    predicate = disj(
        conj(n.eq(1), value.eq(1)),
        conj(n.eq(2), value.eq(1)),
        value.eq(0),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2, 3) + cell(2, 4)),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    assert detection.descriptor is None
    assert "pin" in detection.reason


def test_rejects_conflicting_base_cases_instead_of_last_write_wins() -> None:
    """Two branches pinning index 1 to different values admit both traces;
    the compiled claim would silently bind whichever branch is listed last."""
    n = cell(1)
    value = cell(2)
    predicate = disj(
        conj(n.eq(1), value.eq(7)),
        conj(n.eq(1), value.eq(9)),
        conj(n.eq(2), value.eq(4)),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2, 3) + cell(2, 4)),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    assert detection.descriptor is None
    assert "conflict" in detection.reason


def test_refuses_index_valued_coefficients_without_crashing() -> None:
    """cell * Index() wraps an X atom inside cellmul; the guard must refuse
    it as out of fragment, not crash with IndexError."""
    n = cell(1)
    value = cell(2)
    predicate = disj(
        conj(n.eq(1), value.eq(1)),
        conj(n.eq(2), value.eq(1)),
        conj(
            n.eq(cell(1, 3) + 1),
            n.eq(cell(1, 4) + 2),
            value.eq(cell(2) * Index()),
        ),
    )
    detection = detect_linear_recurrence(predicate)
    assert detection.descriptor is None
    assert "index arithmetic" in detection.reason
