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

from zkfol.ast import cell, conj, disj
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
