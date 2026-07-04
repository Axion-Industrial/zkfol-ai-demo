"""C-finite recurrence detection over the FOL fragment (prototype pass).

This is the legality guard for the fast-doubling / matrix-power rewrite: a
purely syntactic analysis of the predicate (no witness access) that decides
whether the inductive step is a constant-coefficient linear recurrence over
pointed predecessor cells, and if so extracts the descriptor a doubling
emitter needs. Statements outside the class are refused with a stated
reason; refusal is the correct answer for factorial (its coefficient is the
index cell, which varies along the trace) and for repeated-squaring power
(its step is nonlinear).

Recognized shape, up to And/Or flattening:

    Or( base_1, ..., base_k, step )

    base_i: And of equalities pinning direct cells to constants
            (C_idx(X) = i and C_val(X) = v_i)
    step:   And of
              schedule equations   C_idx(X) = C_idx(P_j(X)) + d_j
              one recurrence       C_val(X) = sum_j a_j * C_val(P_j(X))
            with every a_j an integer literal.

Structure: every equality is normalized exactly once into a linear form
(atoms, constant), classified exactly once into a typed fact (Pin, Schedule,
or Recurrence), and the descriptor is assembled from the facts. The output
descriptor is public data derived from public data; the rewrite it licenses
is sound only for value claims (endpoint bindings), which is the caller's
obligation to check.
"""

from __future__ import annotations

from dataclasses import dataclass

from zkfol.ast import Add, And, Const, Eq, Formula, Index, Len, MatrixCell, Mul, Or, Term


@dataclass(frozen=True)
class RecurrenceDescriptor:
    order: int
    index_row: int
    value_row: int
    # ((offset, coefficient), ...) sorted by offset descending: F(k) = sum coeff * F(k + offset)
    coefficients: tuple[tuple[int, int], ...]
    # ((index, value), ...) for indices 1..order
    initial_values: tuple[tuple[int, int], ...]
    # ((pointer_row, offset), ...)
    pointer_offsets: tuple[tuple[int, int], ...]


@dataclass(frozen=True)
class Detection:
    descriptor: RecurrenceDescriptor | None
    reason: str | None

    @staticmethod
    def rejected(reason: str) -> "Detection":
        return Detection(None, reason)


class _Unrecognized(Exception):
    """An equality or term outside the recognized fragment; str() says why."""


_Atom = tuple  # ("direct", row) | ("composed", row, ptr) | ("X",) | ("len",)


def _merge(into: dict[_Atom, int], frm: dict[_Atom, int], scale: int = 1) -> None:
    for atom, coeff in frm.items():
        into[atom] = into.get(atom, 0) + scale * coeff
        if into[atom] == 0:
            del into[atom]


def _linear_form(term: Term) -> tuple[dict[_Atom, int], int]:
    """Term as (atom -> coefficient, constant); raises _Unrecognized otherwise."""
    if isinstance(term, Const):
        return {}, term.value
    if isinstance(term, MatrixCell):
        atom = ("composed", term.row, term.pointer_row) if term.pointer_row is not None else ("direct", term.row)
        return {atom: 1}, 0
    if isinstance(term, Index):
        return {("X",): 1}, 0
    if isinstance(term, Len):
        return {("len",): 1}, 0
    if isinstance(term, Add):
        atoms, const = _linear_form(term.left)
        right_atoms, right_const = _linear_form(term.right)
        _merge(atoms, right_atoms)
        return atoms, const + right_const
    if isinstance(term, Mul):
        left_atoms, left_const = _linear_form(term.left)
        right_atoms, right_const = _linear_form(term.right)
        if not left_atoms:
            return {a: left_const * c for a, c in right_atoms.items()}, left_const * right_const
        if not right_atoms:
            return {a: right_const * c for a, c in left_atoms.items()}, left_const * right_const
        raise _Unrecognized(
            "not linear with constant coefficients: multiplication of two "
            "non-constant terms (a cell-valued coefficient varies along the "
            "trace, or the step is nonlinear)"
        )
    raise _Unrecognized(f"unsupported term {type(term).__name__}")


def _normalize(equality: Eq) -> tuple[dict[_Atom, int], int]:
    """Equality as left - right = 0 in linear form."""
    atoms, const = _linear_form(equality.left)
    right_atoms, right_const = _linear_form(equality.right)
    _merge(atoms, right_atoms, scale=-1)
    return atoms, const - right_const


# --- typed facts, one per classified equality ------------------------------


@dataclass(frozen=True)
class _Pin:
    row: int
    value: int


@dataclass(frozen=True)
class _Schedule:
    row: int
    pointer: int
    offset: int


@dataclass(frozen=True)
class _Recurrence:
    row: int
    coefficients: dict[int, int]  # pointer_row -> coefficient


def _classify(equality: Eq) -> _Pin | _Schedule | _Recurrence:
    atoms, const = _normalize(equality)
    if any(atom[0] in ("X", "len") for atom in atoms):
        raise _Unrecognized("index arithmetic over X or len(C) is out of prototype scope")
    rows = {atom[1] for atom in atoms}
    if len(rows) != 1:
        raise _Unrecognized("equation mixes cell rows; out of prototype scope")
    row = rows.pop()
    sign = atoms.get(("direct", row))
    composed = {atom[2]: coeff for atom, coeff in atoms.items() if atom[0] == "composed"}
    if sign not in (1, -1):
        raise _Unrecognized("equation does not constrain a direct cell with unit coefficient")
    if not composed:
        # sign*C_row(X) + const = 0
        return _Pin(row, -const * sign)
    if len(composed) == 1 and next(iter(composed.values())) == -sign:
        # sign*(C_row(X) - C_row(P)) + const = 0  =>  P sits at offset const*sign
        return _Schedule(row, next(iter(composed)), const * sign)
    if const != 0:
        raise _Unrecognized("affine recurrence constants are out of prototype scope")
    return _Recurrence(row, {ptr: -coeff * sign for ptr, coeff in composed.items()})


# --- branch handling and assembly ------------------------------------------


def _equalities(formula: Formula) -> list[Eq] | None:
    if isinstance(formula, Eq):
        return [formula]
    if isinstance(formula, And):
        out: list[Eq] = []
        for part in formula.parts:
            inner = _equalities(part)
            if inner is None:
                return None
            out.extend(inner)
        return out
    return None


def _uses_pointer(formula: Formula) -> bool:
    if isinstance(formula, Eq):
        def term_uses(term: Term) -> bool:
            if isinstance(term, MatrixCell):
                return term.pointer_row is not None
            if isinstance(term, (Add, Mul)):
                return term_uses(term.left) or term_uses(term.right)
            return False
        return term_uses(formula.left) or term_uses(formula.right)
    if isinstance(formula, (And, Or)):
        return any(_uses_pointer(part) for part in formula.parts)
    return False


def _base_pins(branch: Formula) -> dict[int, int]:
    """row -> pinned constant for one base branch.

    Every equality must be a constant pin: a pointer-free branch that leaves
    anything unpinned weakens the predicate (it admits columns the recurrence
    does not describe), so anything else raises _Unrecognized.
    """
    equalities = _equalities(branch)
    if equalities is None:
        raise _Unrecognized("not a conjunction of equalities")
    pins: dict[int, int] = {}
    for equality in equalities:
        fact = _classify(equality)
        if not isinstance(fact, _Pin):
            raise _Unrecognized("contains a non-pin equality")
        if pins.setdefault(fact.row, fact.value) != fact.value:
            raise _Unrecognized(f"pins row {fact.row} to conflicting values")
    return pins


def detect_linear_recurrence(predicate: Formula) -> Detection:
    branches = list(predicate.parts) if isinstance(predicate, Or) else [predicate]
    step_branches = [b for b in branches if _uses_pointer(b)]
    base_branches = [b for b in branches if not _uses_pointer(b)]
    if len(step_branches) != 1:
        return Detection.rejected(
            f"found {len(step_branches)} pointer-using branches; cannot identify "
            "a single linear recurrence step"
        )
    equalities = _equalities(step_branches[0])
    if equalities is None:
        return Detection.rejected("inductive step is not a conjunction of equalities")

    try:
        facts = [_classify(equality) for equality in equalities]
    except _Unrecognized as exc:
        return Detection.rejected(f"inductive step: {exc}")

    recurrences = [f for f in facts if isinstance(f, _Recurrence)]
    schedules = [f for f in facts if isinstance(f, _Schedule)]
    if len(recurrences) != 1:
        return Detection.rejected(f"expected exactly one recurrence equation, found {len(recurrences)}")
    if any(isinstance(f, _Pin) for f in facts):
        return Detection.rejected("unexpected constant pin inside the inductive step")
    recurrence = recurrences[0]

    offset_by_pointer: dict[int, int] = {}
    for schedule in schedules:
        if offset_by_pointer.setdefault(schedule.pointer, schedule.offset) != schedule.offset:
            return Detection.rejected(f"pointer row {schedule.pointer} has conflicting offsets")
    index_rows = {schedule.row for schedule in schedules}
    if len(index_rows) != 1 or recurrence.row in index_rows:
        return Detection.rejected("schedule equations do not identify a unique index row")
    index_row = index_rows.pop()

    missing = sorted(set(recurrence.coefficients) - set(offset_by_pointer))
    if missing:
        return Detection.rejected(f"pointer rows {missing} have no schedule equation")

    offsets = sorted((offset_by_pointer[ptr] for ptr in recurrence.coefficients), reverse=True)
    order = -min(offsets)
    if offsets != list(range(-1, -order - 1, -1)):
        return Detection.rejected(f"offsets {offsets} are not contiguous -1..-order")

    initial: dict[int, int] = {}
    for branch in base_branches:
        try:
            pins = _base_pins(branch)
        except _Unrecognized as exc:
            return Detection.rejected(f"base branch: {exc}")
        if index_row not in pins or recurrence.row not in pins:
            return Detection.rejected(
                "a pointer-free branch does not pin both the index and value rows; "
                "the predicate admits columns the recurrence does not determine"
            )
        index, value = pins[index_row], pins[recurrence.row]
        if initial.setdefault(index, value) != value:
            return Detection.rejected(
                f"conflicting base cases pin index {index} to different values"
            )
    if sorted(initial) != list(range(1, order + 1)):
        return Detection.rejected(
            f"base cases pin indices {sorted(initial)} but the recurrence has order {order}"
        )

    coefficients = tuple(
        (offset_by_pointer[ptr], coeff)
        for ptr, coeff in sorted(
            recurrence.coefficients.items(), key=lambda item: offset_by_pointer[item[0]], reverse=True
        )
    )
    return Detection(
        RecurrenceDescriptor(
            order=order,
            index_row=index_row,
            value_row=recurrence.row,
            coefficients=coefficients,
            initial_values=tuple(sorted(initial.items())),
            pointer_offsets=tuple(sorted(offset_by_pointer.items())),
        ),
        None,
    )
