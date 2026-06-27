"""Typed abstract syntax for the zkFOL fragment.

Paper pointer: Figure 1 of the paper defines the term and predicate
syntax implemented here.  Terms are built from integer constants, addition,
multiplication, ``len(C)``, the index variable ``X``, direct matrix lookups
``C_i(X)``, and one level of composed lookup ``C_i(C_j(X))``.  Predicates are
equalities combined by conjunction and disjunction.

The implementation keeps those mathematical constructors explicit instead of
encoding them as strings.  This makes the later clauses easy to audit:

* :class:`Eq` evaluates/compiles as a square ``(left - right)^2``.
* :class:`And` evaluates/compiles as a sum.
* :class:`Or` evaluates/compiles as a product.

These are exactly the zero-is-true rules described around Figure 2 and Figure 3
of the paper: zero means true, and any nonzero natural number is a flavour of
false.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import reduce
from operator import mul
from typing import Union

if False:  # pragma: no cover - typing only
    from .witness import MatrixInterpretation

TermLike = Union["Term", int]
FormulaLike = "Formula"


class Term:
    """Base class for FOL terms.

    ``evaluate`` implements the direct integer semantics of Figure 3 for terms.
    Compilation to ``mkQ`` is intentionally separate and lives in
    :mod:`zkfol.compiler`; the tests compare the two routes.
    """

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        """Evaluate the term in the integer semantics at 1-based column ``x``."""
        raise NotImplementedError

    def eq(self, other: TermLike) -> "Eq":
        """Build the equality predicate ``self = other``."""
        return Eq(self, as_term(other))

    def equals(self, other: TermLike) -> "Eq":
        """Alias for :meth:`eq`, useful when avoiding Python's ``==`` operator."""
        return self.eq(other)

    def __add__(self, other: TermLike) -> "Term":
        return Add(self, as_term(other))

    def __radd__(self, other: TermLike) -> "Term":
        return Add(as_term(other), self)

    def __mul__(self, other: TermLike) -> "Term":
        return Mul(self, as_term(other))

    def __rmul__(self, other: TermLike) -> "Term":
        return Mul(as_term(other), self)

    def __neg__(self) -> "Term":
        return Mul(Const(-1), self)

    def __sub__(self, other: TermLike) -> "Term":
        return Add(self, -as_term(other))

    def __rsub__(self, other: TermLike) -> "Term":
        return Add(as_term(other), -self)

    def __bool__(self) -> bool:  # pragma: no cover - defensive API guard
        raise TypeError("FOL terms do not have Python truth values")


@dataclass(frozen=True)
class Const(Term):
    """Integer constant ``q`` from Figure 1."""

    value: int

    def __post_init__(self) -> None:
        if not isinstance(self.value, int):
            raise TypeError("Const value must be an int")

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return self.value

    def __str__(self) -> str:
        return str(self.value)


@dataclass(frozen=True)
class Index(Term):
    """The index variable ``X``.

    In direct semantics, ``X`` evaluates to the current 1-based column ``x``.
    In ``mkQ`` compilation, Figure 4 likewise maps ``X`` to the chosen ``x``.
    """

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        witness.validate_column(x)
        return x

    def __str__(self) -> str:
        return "X"


@dataclass(frozen=True)
class Len(Term):
    """The term ``len(C)``."""

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return witness.length

    def __str__(self) -> str:
        return "len(C)"


@dataclass(frozen=True)
class MatrixCell(Term):
    """A matrix lookup ``C_i(X)``, or a composed lookup ``C_i(C_j(X))``.

    ``row`` is the paper's 1-based index ``i``.  ``pointer_row`` is ``None`` for
    a direct lookup and is the 1-based row ``j`` for a composed lookup.

    Composed lookups are why range checks matter: Definition 3.1 and Definition
    3.7 require every pointer value ``C_j(X)`` used in ``C_i(C_j(X))`` to lie in
    ``[1, len(C)]``.  The package represents those checks with
    :class:`zkfol.witness.PointerRangeCheck`.
    """

    row: int
    pointer_row: int | None = None

    def __post_init__(self) -> None:
        if self.row < 1:
            raise ValueError("row must be 1-based and positive")
        if self.pointer_row is not None and self.pointer_row < 1:
            raise ValueError("pointer_row must be 1-based and positive")

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        if self.pointer_row is None:
            return witness.value(self.row, x)
        pointer = witness.value(self.pointer_row, x)
        return witness.value(self.row, pointer)

    def __str__(self) -> str:
        if self.pointer_row is None:
            return f"C{self.row}(X)"
        return f"C{self.row}(C{self.pointer_row}(X))"


@dataclass(frozen=True)
class Add(Term):
    """Term addition."""

    left: Term
    right: Term

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return self.left.evaluate(witness, x) + self.right.evaluate(witness, x)

    def __str__(self) -> str:
        return f"({self.left} + {self.right})"


@dataclass(frozen=True)
class Mul(Term):
    """Term multiplication."""

    left: Term
    right: Term

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return self.left.evaluate(witness, x) * self.right.evaluate(witness, x)

    def __str__(self) -> str:
        return f"({self.left} * {self.right})"


class Formula:
    """Base class for predicates in zero-is-true semantics.

    The returned integer is a truth value in the paper's sense: ``0`` means the
    predicate is true at the current column, while any nonzero value means false.
    Lemma 2.17 explains why predicate evaluations are non-negative.
    """

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        """Evaluate to a non-negative integer.  Zero means true."""
        raise NotImplementedError

    def __and__(self, other: FormulaLike) -> "Formula":
        return conj(self, other)

    def __or__(self, other: FormulaLike) -> "Formula":
        return disj(self, other)

    def __bool__(self) -> bool:  # pragma: no cover - defensive API guard
        raise TypeError("FOL formulae do not have Python truth values; use & and |")


@dataclass(frozen=True)
class Eq(Formula):
    """Predicate ``t = t'``.

    Figure 2 and Figure 3 translate equality to ``(t - t')^2``.  Squaring makes
    equality zero exactly when the two integer term values coincide.
    """

    left: Term
    right: Term

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        diff = self.left.evaluate(witness, x) - self.right.evaluate(witness, x)
        return diff * diff

    def __str__(self) -> str:
        return f"({self.left} = {self.right})"


@dataclass(frozen=True)
class And(Formula):
    """Conjunction.

    Figure 2/Figure 3 translate conjunction to a sum.  Because every predicate
    value is non-negative, the sum is zero exactly when every conjunct is zero.
    """

    parts: tuple[Formula, ...]

    def __post_init__(self) -> None:
        if not self.parts:
            raise ValueError("And requires at least one part")

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return sum(part.evaluate(witness, x) for part in self.parts)

    def __str__(self) -> str:
        return "(" + " AND ".join(str(p) for p in self.parts) + ")"


@dataclass(frozen=True)
class Or(Formula):
    """Disjunction.

    Figure 2/Figure 3 translate disjunction to a product.  Since zero is true,
    the product is zero exactly when at least one disjunct is zero.
    """

    parts: tuple[Formula, ...]

    def __post_init__(self) -> None:
        if not self.parts:
            raise ValueError("Or requires at least one part")

    def evaluate(self, witness: "MatrixInterpretation", x: int) -> int:
        return reduce(mul, (part.evaluate(witness, x) for part in self.parts), 1)

    def __str__(self) -> str:
        return "(" + " OR ".join(str(p) for p in self.parts) + ")"


def as_term(value: TermLike) -> Term:
    """Coerce an ``int`` or :class:`Term` into a :class:`Term`."""
    if isinstance(value, Term):
        return value
    if isinstance(value, int):
        return Const(value)
    raise TypeError(f"Expected Term or int, got {type(value).__name__}")


def const(value: int) -> Const:
    """Construct an integer constant term."""
    return Const(value)


def cell(row: int, pointer_row: int | None = None) -> MatrixCell:
    """Construct ``C_row(X)`` or ``C_row(C_pointer_row(X))``.

    This is the main convenience function used in the examples.  For instance,
    ``cell(3, 4)`` is the paper's term ``C_3(C_4(X))``.
    """
    return MatrixCell(row, pointer_row)


def conj(*parts: Formula) -> Formula:
    """Build a conjunction, flattening nested :class:`And` nodes."""
    flat: list[Formula] = []
    for part in parts:
        if isinstance(part, And):
            flat.extend(part.parts)
        elif isinstance(part, Formula):
            flat.append(part)
        else:
            raise TypeError(f"Expected Formula, got {type(part).__name__}")
    if not flat:
        return truth()
    if len(flat) == 1:
        return flat[0]
    return And(tuple(flat))


def disj(*parts: Formula) -> Formula:
    """Build a disjunction, flattening nested :class:`Or` nodes."""
    flat: list[Formula] = []
    for part in parts:
        if isinstance(part, Or):
            flat.extend(part.parts)
        elif isinstance(part, Formula):
            flat.append(part)
        else:
            raise TypeError(f"Expected Formula, got {type(part).__name__}")
    if not flat:
        return falsehood()
    if len(flat) == 1:
        return flat[0]
    return Or(tuple(flat))


def truth() -> Formula:
    """The true predicate, represented as ``0 = 0``."""
    return Eq(Const(0), Const(0))


def falsehood() -> Formula:
    """The false predicate, represented as ``0 = 1``."""
    return Eq(Const(0), Const(1))


X = Index()
