"""Witness matrix representation and pointer range checks.

Paper pointer: Definition 2.16 interprets the single matrix symbol ``C`` as a
non-negative integer matrix, and Notation 2.1 writes ``C@i,x`` for the entry in
row ``i`` and column ``x``.  This module stores exactly that object, while using
Python tuples internally.

Rows and columns exposed through the public API are 1-based, matching the paper.
Pointer rows are checked by :class:`PointerRangeCheck`, corresponding to the
range conditions required by Definition 3.1 and Definition 3.7 whenever a formula
uses a composed term ``C_i(C_j(X))``.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import cached_property
from typing import Iterable, Sequence

from .bits import max_bit_length


class WitnessError(ValueError):
    """Raised when a witness matrix is malformed or out of range."""


@dataclass(frozen=True)
class MatrixInterpretation:
    """A non-negative integer matrix interpretation for a single ``C`` symbol.

    This is the witness object ``zeta(C)`` of the paper.  The constructor checks
    the basic well-formedness properties needed by the arithmetic semantics:
    rectangular shape, at least one row/column, integer entries, and no negative
    entries.

    Rows and columns are exposed via the paper's 1-based indexing convention:
    ``C@i,x`` is ``value(row=i, column=x)``.
    """

    rows: tuple[tuple[int, ...], ...]
    name: str = "C"

    def __init__(self, rows: Sequence[Sequence[int]], name: str = "C") -> None:
        if not rows:
            raise WitnessError("witness must have at least one row")
        normalised = tuple(tuple(row) for row in rows)
        if not normalised[0]:
            raise WitnessError("witness must have at least one column")
        width = len(normalised[0])
        for row_index, row in enumerate(normalised, start=1):
            if len(row) != width:
                raise WitnessError("witness rows must all have the same length")
            for col_index, value in enumerate(row, start=1):
                if not isinstance(value, int):
                    raise WitnessError(f"entry ({row_index}, {col_index}) is not an int")
                if value < 0:
                    raise WitnessError(f"entry ({row_index}, {col_index}) is negative")
        object.__setattr__(self, "rows", normalised)
        object.__setattr__(self, "name", name)

    @classmethod
    def from_columns(cls, columns: Sequence[Sequence[int]], name: str = "C") -> "MatrixInterpretation":
        """Build an interpretation from memory columns.

        Many recursive witness builders naturally accumulate a list of columns.
        The FOL semantics uses rows, so this constructor converts columns to rows.
        """
        if not columns:
            raise WitnessError("columns must not be empty")
        arity = len(columns[0])
        for index, column in enumerate(columns, start=1):
            if len(column) != arity:
                raise WitnessError(f"column {index} has inconsistent arity")
        rows = tuple(tuple(column[row] for column in columns) for row in range(arity))
        return cls(rows, name=name)

    @property
    def arity(self) -> int:
        return len(self.rows)

    @property
    def length(self) -> int:
        return len(self.rows[0])

    @cached_property
    def max_bits(self) -> int:
        # The matrix is immutable (validated tuples), so this full scan is
        # computed once; evaluators consult it per matrix-cell visit.
        return max_bit_length(value for row in self.rows for value in row)

    def validate_row(self, row: int) -> None:
        if not 1 <= row <= self.arity:
            raise WitnessError(f"row {row} is outside [1, {self.arity}]")

    def validate_column(self, column: int) -> None:
        if not 1 <= column <= self.length:
            raise WitnessError(f"column {column} is outside [1, {self.length}]")

    def value(self, row: int, column: int) -> int:
        self.validate_row(row)
        self.validate_column(column)
        return self.rows[row - 1][column - 1]

    def row(self, row: int) -> tuple[int, ...]:
        self.validate_row(row)
        return self.rows[row - 1]

    def column(self, column: int) -> tuple[int, ...]:
        self.validate_column(column)
        return tuple(row[column - 1] for row in self.rows)

    def columns(self) -> tuple[tuple[int, ...], ...]:
        return tuple(self.column(column) for column in range(1, self.length + 1))

    def pointer_values_in_range(self, row: int) -> bool:
        self.validate_row(row)
        return all(1 <= value <= self.length for value in self.row(row))

    def as_lists(self) -> list[list[int]]:
        return [list(row) for row in self.rows]


@dataclass(frozen=True)
class PointerRangeCheck:
    """Range check ``1 <= C_row(X) <= len(C)`` for all columns.

    If a predicate contains ``C_i(C_row(X))``, then row ``C_row`` is being used
    as a column pointer.  Definition 3.1 requires such rows to be range-checked
    so that the direct semantics and beta/mkQ semantics agree on composed cells.
    """

    row: int

    def is_satisfied(self, witness: MatrixInterpretation) -> bool:
        return witness.pointer_values_in_range(self.row)

    def violations(self, witness: MatrixInterpretation) -> tuple[tuple[int, int], ...]:
        witness.validate_row(self.row)
        out: list[tuple[int, int]] = []
        for column, value in enumerate(witness.row(self.row), start=1):
            if not 1 <= value <= witness.length:
                out.append((column, value))
        return tuple(out)
