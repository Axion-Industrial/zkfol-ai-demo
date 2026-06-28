"""Typed (``num``/``ptr``) compilation: the optimised counterpart of ``mkQ``.

Paper pointer: this module implements the optimisation alluded to in Section 4 of
the paper.  The paper-faithful :mod:`zkfol.compiler` follows Figure 4 literally
and replaces *every* cell value -- ``C_i(X)`` and ``C_i(C_j(X))`` alike -- by a
``b2int`` expansion over the quad-indexed ``B`` variables, so that numbers are
represented bitwise throughout.  That uniformity is convenient for a page-limited
exposition but is not required: only values consumed as pointers (the inner
``C_j`` of a composed lookup) actually depend on their bits.  See
:mod:`zkfol.types` for the type system that records this.

Here ``mkQ`` instead replaces each cell value by a single integer *value symbol*:

* ``C_i(X)``        becomes  ``V_{i,0,x}``;
* ``C_i(C_j(X))``   becomes  ``V_{i,j,x}``.

No bit variables and no ``b2int`` sums appear.  Constants, ``X``, ``len(C)``,
``+``, ``*`` and the Figure 2 clauses (equality is a squared difference,
conjunction is a sum, disjunction is a product) are unchanged.

:func:`beta_typed` plays the role of Definition 3.6: it evaluates a value symbol
to the *integer value* of the corresponding witness entry (rather than to one of
its bits), using the same out-of-range pointer convention -- a composed value is
``0`` whenever its pointer ``C_j(x)`` falls outside ``[1, len(C)]``.

Because ``b2int`` of the bits of ``v`` is just ``v``, this typed route computes
exactly the same integers as the bitwise route.  Concretely, for every column
``x``::

    beta_typed(mkq_typed(<phi>, x)) == beta(mkq(<phi>, x)) == <phi> evaluated directly

which is the Theorem 3.8 equivalence, now witnessed by the optimised
representation.  ``tests/test_typed_compiler.py`` asserts it for every bundled
example.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Mapping

import sympy as sp

from .ast import Add, And, Const, Eq, Formula, Index, Len, MatrixCell, Mul, Or, Term
from .witness import MatrixInterpretation, WitnessError


@dataclass(frozen=True, order=True)
class ValueIndex:
    """Index metadata for a single integer value symbol ``V_{row,pointer,x}``.

    * ``row`` is the selected matrix row ``i``.
    * ``pointer`` is ``j``; ``0`` denotes the direct case ``C_i(X)``.
    * ``x`` is the 1-based column at which ``mkQ`` is generated.

    Unlike :class:`zkfol.compiler.BIndex` there is no ``bit`` field: a value
    symbol stands for the whole integer entry, not one of its bits.
    """

    row: int
    pointer: int
    x: int

    def __post_init__(self) -> None:
        if self.row < 1:
            raise ValueError("row must be positive")
        if self.pointer < 0:
            raise ValueError("pointer must be non-negative")
        if self.x < 1:
            raise ValueError("x must be positive")

    @property
    def symbol_name(self) -> str:
        return f"V_{self.row}_{self.pointer}_{self.x}"


_V_SYMBOL_RE = re.compile(r"^V_(\d+)_(\d+)_(\d+)$")


def parse_value_symbol(symbol: sp.Symbol) -> ValueIndex:
    """Parse a value symbol name produced by this compiler."""
    match = _V_SYMBOL_RE.match(str(symbol))
    if match is None:
        raise ValueError(f"symbol {symbol!s} is not a zkFOL value symbol")
    row, pointer, x = (int(group) for group in match.groups())
    return ValueIndex(row=row, pointer=pointer, x=x)


class TypedCompilationContext:
    """Compilation parameters and symbol registry for the typed ``mkQ``.

    Mirrors :class:`zkfol.compiler.CompilationContext` but needs no bit width:
    values are kept whole, so only ``arity`` and ``length`` are required.
    """

    def __init__(self, arity: int, length: int) -> None:
        if arity < 1:
            raise ValueError("arity must be positive")
        if length < 1:
            raise ValueError("length must be positive")
        self.arity = arity
        self.length = length
        self._symbols: dict[ValueIndex, sp.Symbol] = {}
        self._indices: dict[sp.Symbol, ValueIndex] = {}

    @classmethod
    def from_witness(cls, witness: MatrixInterpretation) -> "TypedCompilationContext":
        return cls(arity=witness.arity, length=witness.length)

    @property
    def symbol_indices(self) -> Mapping[sp.Symbol, ValueIndex]:
        return dict(self._indices)

    def validate_value_index(self, index: ValueIndex) -> None:
        if not 1 <= index.row <= self.arity:
            raise ValueError(f"value row {index.row} is outside [1, {self.arity}]")
        if not 0 <= index.pointer <= self.arity:
            raise ValueError(f"value pointer {index.pointer} is outside [0, {self.arity}]")
        if not 1 <= index.x <= self.length:
            raise ValueError(f"value x {index.x} is outside [1, {self.length}]")

    def symbol(self, index: ValueIndex) -> sp.Symbol:
        self.validate_value_index(index)
        if index not in self._symbols:
            symbol = sp.Symbol(index.symbol_name, integer=True)
            self._symbols[index] = symbol
            self._indices[symbol] = index
        return self._symbols[index]

    def compile_term(self, term: Term, x: int) -> sp.Expr:
        """Compile a term, replacing each cell value by a single value symbol."""
        if not 1 <= x <= self.length:
            raise ValueError(f"x {x} is outside [1, {self.length}]")
        if isinstance(term, Const):
            return sp.Integer(term.value)
        if isinstance(term, Index):
            return sp.Integer(x)
        if isinstance(term, Len):
            return sp.Integer(self.length)
        if isinstance(term, Add):
            return self.compile_term(term.left, x) + self.compile_term(term.right, x)
        if isinstance(term, Mul):
            return self.compile_term(term.left, x) * self.compile_term(term.right, x)
        if isinstance(term, MatrixCell):
            pointer = 0 if term.pointer_row is None else term.pointer_row
            return self.symbol(ValueIndex(row=term.row, pointer=pointer, x=x))
        raise TypeError(f"Unsupported term type: {type(term).__name__}")

    def compile_formula(self, formula: Formula, x: int) -> sp.Expr:
        """Compile a predicate using the Figure 2 clauses over value symbols."""
        if isinstance(formula, Eq):
            diff = self.compile_term(formula.left, x) - self.compile_term(formula.right, x)
            return diff * diff
        if isinstance(formula, And):
            return sum((self.compile_formula(part, x) for part in formula.parts), sp.Integer(0))
        if isinstance(formula, Or):
            product = sp.Integer(1)
            for part in formula.parts:
                product *= self.compile_formula(part, x)
            return product
        raise TypeError(f"Unsupported formula type: {type(formula).__name__}")

    def mkq(self, obj: Formula | Term, x: int, *, expand: bool = False) -> "TypedCompiledPolynomial":
        if isinstance(obj, Formula):
            expression = self.compile_formula(obj, x)
        elif isinstance(obj, Term):
            expression = self.compile_term(obj, x)
        else:
            raise TypeError(f"Expected Formula or Term, got {type(obj).__name__}")
        if expand:
            expression = sp.expand(expression)
        return TypedCompiledPolynomial(expression=expression, x=x, context=self, source=obj)


@dataclass(frozen=True)
class TypedCompiledPolynomial:
    """A typed ``mkQ`` polynomial plus enough metadata to evaluate beta."""

    expression: sp.Expr
    x: int
    context: TypedCompilationContext
    source: Formula | Term | None = None

    def beta(self, witness: MatrixInterpretation) -> int:
        return beta_typed(self.expression, witness, self.context.symbol_indices)

    def direct_value(self, witness: MatrixInterpretation) -> int:
        if self.source is None:
            raise ValueError("direct_value is unavailable without a source AST")
        return self.source.evaluate(witness, self.x)


def mkq_typed(obj: Formula | Term, witness: MatrixInterpretation, x: int, *, expand: bool = False) -> TypedCompiledPolynomial:
    """Convenience wrapper: build a typed context from ``witness`` and compile."""
    return TypedCompilationContext.from_witness(witness).mkq(obj, x, expand=expand)


def beta_value_symbol(index: ValueIndex, witness: MatrixInterpretation) -> int:
    """Evaluate one value symbol under the typed beta.

    For direct symbols this is the integer entry ``C_i(x)``.  For composed
    symbols it is ``C_i(C_j(x))``, or ``0`` if ``C_j(x)`` is out of range -- the
    same convention as Definition 3.6, but returning the whole value instead of a
    single bit.
    """
    witness.validate_row(index.row)
    if not 1 <= index.x <= witness.length:
        raise WitnessError(f"value x {index.x} is outside witness length {witness.length}")
    if index.pointer == 0:
        return witness.value(index.row, index.x)
    witness.validate_row(index.pointer)
    pointed_column = witness.value(index.pointer, index.x)
    if not 1 <= pointed_column <= witness.length:
        return 0
    return witness.value(index.row, pointed_column)


def beta_typed(
    expression: sp.Expr,
    witness: MatrixInterpretation,
    symbol_indices: Mapping[sp.Symbol, ValueIndex] | None = None,
) -> int:
    """Evaluate a typed ``mkQ`` polynomial by substituting integer cell values.

    Structurally identical to :func:`zkfol.compiler.beta`, but each free symbol
    resolves to a whole integer entry via :func:`beta_value_symbol` rather than
    to a single bit.
    """
    known = symbol_indices or {}
    symbol_values: dict[sp.Symbol, int] = {}
    for symbol in expression.free_symbols:
        index = known.get(symbol)
        if index is None:
            index = parse_value_symbol(symbol)
        symbol_values[symbol] = beta_value_symbol(index, witness)

    def eval_expr(expr: sp.Expr) -> int:
        if expr.is_Integer:
            return int(expr)
        if expr.is_Symbol:
            try:
                return symbol_values[expr]
            except KeyError as exc:  # pragma: no cover - defensive guard
                raise ValueError(f"No beta value for symbol {expr}") from exc
        if expr.is_Add:
            return sum(eval_expr(arg) for arg in expr.args)
        if expr.is_Mul:
            product = 1
            for arg in expr.args:
                product *= eval_expr(arg)
            return product
        if expr.is_Pow:
            base, exponent = expr.args
            exponent_value = eval_expr(exponent)
            if exponent_value < 0:
                raise ValueError("Negative powers are not supported in mkQ polynomials")
            return eval_expr(base) ** exponent_value
        if expr.is_Number and int(expr) == expr:
            return int(expr)
        raise ValueError(f"Unsupported expression node in typed beta evaluation: {expr!r}")

    return eval_expr(expression)
