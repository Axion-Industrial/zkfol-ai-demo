"""Witness matrix builders for the examples.

These functions construct concrete interpretations of the matrix symbol ``C``.
They are deliberately ordinary recursive/memoised computations: first compute a
small table of values and recursive-call pointers, then reorient it into the
row-major :class:`zkfol.witness.MatrixInterpretation` expected by the FOL
semantics.

Paper pointer: the standard power witness corresponds to the row convention in
Section 5 of the paper.  The other witness builders are additional small recursive examples that
exercise the same Figure 1 syntax and Definition 3.6 pointer semantics.
"""

from __future__ import annotations

from .witness import MatrixInterpretation


def _require_non_negative(value: int, name: str) -> None:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be an int")
    if value < 0:
        raise ValueError(f"{name} must be non-negative")


def _require_positive(value: int, name: str) -> None:
    if not isinstance(value, int):
        raise TypeError(f"{name} must be an int")
    if value < 1:
        raise ValueError(f"{name} must be positive")


def power_witness(base: int, exponent: int) -> MatrixInterpretation:
    """Return rows [base, exponent, base**exponent, pointer_to_exponent_minus_1]."""
    _require_non_negative(base, "base")
    _require_non_negative(exponent, "exponent")
    memory: list[list[int]] = []
    index_by_args: dict[tuple[int, int], int] = {}

    def remember(key: tuple[int, int], column: list[int]) -> tuple[list[int], int]:
        index = len(memory) + 1
        memory.append(column)
        index_by_args[key] = index
        return column, index

    def f(a: int, b: int) -> tuple[list[int], int]:
        key = (a, b)
        if key in index_by_args:
            index = index_by_args[key]
            return memory[index - 1], index
        if b == 0:
            return remember(key, [a, 0, 1, 1])
        previous_column, previous_index = f(a, b - 1)
        return remember(key, [a, b, a * previous_column[2], previous_index])

    f(base, exponent)
    return MatrixInterpretation.from_columns(memory, name="pow")


def efficient_power_witness(base: int, exponent: int) -> MatrixInterpretation:
    """Return rows [base, exponent, base**exponent, pointer_to_exponent_floor_half]."""
    _require_non_negative(base, "base")
    _require_non_negative(exponent, "exponent")
    memory: list[list[int]] = []
    index_by_args: dict[tuple[int, int], int] = {}

    def remember(key: tuple[int, int], column: list[int]) -> tuple[list[int], int]:
        index = len(memory) + 1
        memory.append(column)
        index_by_args[key] = index
        return column, index

    def f(a: int, b: int) -> tuple[list[int], int]:
        key = (a, b)
        if key in index_by_args:
            index = index_by_args[key]
            return memory[index - 1], index
        if b == 0:
            return remember(key, [a, 0, 1, 1])
        half_column, half_index = f(a, b // 2)
        square = half_column[2] * half_column[2]
        value = square if b % 2 == 0 else a * square
        return remember(key, [a, b, value, half_index])

    f(base, exponent)
    return MatrixInterpretation.from_columns(memory, name="epow")


def factorial_witness(n: int) -> MatrixInterpretation:
    """Return rows [n, n!, pointer_to_(n-1)!]. Uses the base case 1! = 1."""
    _require_positive(n, "n")
    memory: list[list[int]] = []
    index_by_n: dict[int, int] = {}

    def remember(key: int, column: list[int]) -> tuple[list[int], int]:
        index = len(memory) + 1
        memory.append(column)
        index_by_n[key] = index
        return column, index

    def f(k: int) -> tuple[list[int], int]:
        if k in index_by_n:
            index = index_by_n[k]
            return memory[index - 1], index
        if k == 1:
            return remember(k, [1, 1, 1])
        previous_column, previous_index = f(k - 1)
        return remember(k, [k, k * previous_column[1], previous_index])

    f(n)
    return MatrixInterpretation.from_columns(memory, name="fact")


def fibonacci_witness(n: int) -> MatrixInterpretation:
    """Return rows [n, fib(n), pointer_to_fib(n-1), pointer_to_fib(n-2)].

    This uses the common 1-based convention fib(1) = fib(2) = 1.
    """
    _require_positive(n, "n")
    memory: list[list[int]] = []
    index_by_n: dict[int, int] = {}

    def remember(key: int, column: list[int]) -> tuple[list[int], int]:
        index = len(memory) + 1
        memory.append(column)
        index_by_n[key] = index
        return column, index

    def f(k: int) -> tuple[list[int], int]:
        if k in index_by_n:
            index = index_by_n[k]
            return memory[index - 1], index
        if k in (1, 2):
            return remember(k, [k, 1, 1, 1])
        minus_two_column, minus_two_index = f(k - 2)
        minus_one_column, minus_one_index = f(k - 1)
        return remember(
            k,
            [k, minus_one_column[1] + minus_two_column[1], minus_one_index, minus_two_index],
        )

    f(n)
    return MatrixInterpretation.from_columns(memory, name="fib")
