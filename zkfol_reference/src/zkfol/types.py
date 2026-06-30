"""A minimal two-type system (``num`` / ``ptr``) for the zkFOL fragment.

Paper pointer: Figure 4 (Definition 3.5) uses a *uniform* bitwise representation
-- every cell value ``C_i(X)`` and every composed value ``C_i(C_j(X))`` is
replaced by ``b2int(B_{...})``.  The paper itself flags this as a deliberate
simplification rather than a necessity: see the discussion of prover complexity
in Section 4 ("provers do not generate arbitrary phi ... there may be a design
space of optimal syntactic forms for predicates, which optimise proving").

The observation this module encodes is the smallest instance of that design
space:

* a cell value only needs a *bitwise* representation when it is consumed as a
  **pointer**, i.e. as the inner ``C_j`` of a composed lookup ``C_i(C_j(X))``,
  because that is the only construct in which a value indexes another column and
  therefore the only construct whose correctness depends on the digits of the
  value (and on the range check ``1 <= C_j(X) <= len(C)`` of Definition 3.1);
* every other cell value is consumed only by integer addition, multiplication,
  and the squared-difference of equality, and so needs nothing more than its
  integer value.

We make that distinction a two-element type system:

``ptr``
    A row whose entries are used as a column pointer.  These rows are exactly
    the ones that must be range-checked (Definition 3.1 / 3.7).

``num``
    Every other row.  Consumed only by arithmetic.

Crucially, the type of a row is read directly off the *syntax* of the predicate:
a row ``j`` is a pointer exactly when some term ``C_i(C_j(X))`` mentions ``j`` as
its ``pointer_row``.  This is the same information that an :class:`ExampleSpec`
records by hand in ``pointer_rows``; :func:`pointer_rows` lets a caller derive it
mechanically and check the two agree.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Iterator

from .ast import Add, And, Eq, Formula, MatrixCell, Mul, Or, Term


class CellType(Enum):
    """The two value kinds a matrix row can have in a predicate."""

    NUM = "num"
    PTR = "ptr"

    def __str__(self) -> str:  # pragma: no cover - trivial
        return self.value


def iter_matrix_cells(obj: Formula | Term) -> Iterator[MatrixCell]:
    """Yield every :class:`MatrixCell` occurring in a term or formula."""
    if isinstance(obj, MatrixCell):
        yield obj
        return
    if isinstance(obj, (Add, Mul)):
        yield from iter_matrix_cells(obj.left)
        yield from iter_matrix_cells(obj.right)
        return
    if isinstance(obj, Eq):
        yield from iter_matrix_cells(obj.left)
        yield from iter_matrix_cells(obj.right)
        return
    if isinstance(obj, (And, Or)):
        for part in obj.parts:
            yield from iter_matrix_cells(part)
        return
    # Const, Index, Len, and any other leaf carry no matrix cells.


def pointer_rows(obj: Formula | Term) -> frozenset[int]:
    """Return the set of rows used as inner pointers ``C_j`` in ``obj``.

    A row ``j`` is in the result exactly when some composed term
    ``C_i(C_j(X))`` appears, i.e. some :class:`MatrixCell` has
    ``pointer_row == j``.  These are precisely the rows requiring a range check
    and, in the bitwise encoding, the only rows that genuinely need bits.
    """
    return frozenset(
        cell.pointer_row
        for cell in iter_matrix_cells(obj)
        if cell.pointer_row is not None
    )


@dataclass(frozen=True)
class TypeEnv:
    """Assigns ``num`` or ``ptr`` to each row of the matrix variable ``C``.

    The environment is derived from a predicate's syntax via
    :meth:`from_predicate`.  ``arity`` is ``ar(C)`` and ``pointers`` is the set
    of pointer rows returned by :func:`pointer_rows`.
    """

    arity: int
    pointers: frozenset[int]

    def __post_init__(self) -> None:
        if self.arity < 1:
            raise ValueError("arity must be positive")
        for row in self.pointers:
            if not 1 <= row <= self.arity:
                raise ValueError(f"pointer row {row} is outside [1, {self.arity}]")

    @classmethod
    def from_predicate(cls, predicate: Formula | Term, arity: int) -> "TypeEnv":
        return cls(arity=arity, pointers=pointer_rows(predicate))

    def row_type(self, row: int) -> CellType:
        if not 1 <= row <= self.arity:
            raise ValueError(f"row {row} is outside [1, {self.arity}]")
        return CellType.PTR if row in self.pointers else CellType.NUM

    def is_pointer(self, row: int) -> bool:
        return self.row_type(row) is CellType.PTR

    def row_types(self) -> dict[int, CellType]:
        """Return the full ``row -> CellType`` map, 1-based."""
        return {row: self.row_type(row) for row in range(1, self.arity + 1)}
