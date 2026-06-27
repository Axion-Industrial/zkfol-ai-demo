"""Compilation from zkFOL ASTs to ``mkQ`` polynomials and beta evaluation.

This module is the executable counterpart of Definition 3.5/Figure 4 and
Definition 3.6 of the paper.  The flow is:

1. :class:`CompilationContext` fixes the arity, witness length, and bit width.
2. ``compile_term`` and ``compile_formula`` implement ``mkQ_F^x`` from Figure 4
   directly from the AST; they do not parse human-readable strings.
3. :func:`beta` substitutes witness bits for the quad-indexed ``B`` variables,
   following Definition 3.6.

The tests compare this symbolic route with the direct Figure 3 semantics.  That
comparison is precisely the content of Theorem 3.8 for the implemented fragment.
"""

from __future__ import annotations

from dataclasses import dataclass
import re
from typing import Mapping

import sympy as sp

from .ast import Add, And, Const, Eq, Formula, Index, Len, MatrixCell, Mul, Or, Term
from .bits import bit_at_lsb_first
from .witness import MatrixInterpretation, WitnessError


@dataclass(frozen=True, order=True)
class BIndex:
    """Index metadata for a quad-indexed ``B`` variable.

    Paper notation writes these as variables indexed by row ``i``, pointer row
    ``j``, column ``x``, and bit ``nu``.  This implementation stores those four
    pieces explicitly:

    * ``row`` is ``i`` in the selected matrix row.
    * ``pointer`` is ``j``; ``0`` means the non-composed case ``C_i(X)``.
    * ``x`` is the 1-based column at which ``mkQ`` is generated.
    * ``bit`` is ``nu``, the 1-based least-significant-bit-first index.

    Symbol names include separators, e.g. ``B_1_4_2_3``, to avoid ambiguity when
    indices become multi-digit.
    """

    row: int
    pointer: int
    x: int
    bit: int

    def __post_init__(self) -> None:
        if self.row < 1:
            raise ValueError("row must be positive")
        if self.pointer < 0:
            raise ValueError("pointer must be non-negative")
        if self.x < 1:
            raise ValueError("x must be positive")
        if self.bit < 1:
            raise ValueError("bit must be positive")

    @property
    def symbol_name(self) -> str:
        return f"B_{self.row}_{self.pointer}_{self.x}_{self.bit}"


_B_SYMBOL_RE = re.compile(r"^B_(\d+)_(\d+)_(\d+)_(\d+)$")


def parse_b_symbol(symbol: sp.Symbol) -> BIndex:
    """Parse a B variable name produced by this compiler."""
    match = _B_SYMBOL_RE.match(str(symbol))
    if match is None:
        raise ValueError(f"symbol {symbol!s} is not a zkFOL B symbol")
    row, pointer, x, bit = (int(group) for group in match.groups())
    return BIndex(row=row, pointer=pointer, x=x, bit=bit)


class CompilationContext:
    """Compilation parameters and symbol registry for ``mkQ``.

    Keeping ``arity``, ``length``, and bit width in this context makes the
    mathematical parameters of Definition 3.5 explicit and prevents one example
    from accidentally reusing another example's dimensions.
    """

    def __init__(self, arity: int, length: int, max_bits: int) -> None:
        if arity < 1:
            raise ValueError("arity must be positive")
        if length < 1:
            raise ValueError("length must be positive")
        if max_bits < 1:
            raise ValueError("max_bits must be positive")
        self.arity = arity
        self.length = length
        self.max_bits = max_bits
        self._symbols: dict[BIndex, sp.Symbol] = {}
        self._indices: dict[sp.Symbol, BIndex] = {}

    @classmethod
    def from_witness(cls, witness: MatrixInterpretation) -> "CompilationContext":
        return cls(arity=witness.arity, length=witness.length, max_bits=witness.max_bits)

    @property
    def symbol_indices(self) -> Mapping[sp.Symbol, BIndex]:
        return dict(self._indices)

    def validate_b_index(self, index: BIndex) -> None:
        if not 1 <= index.row <= self.arity:
            raise ValueError(f"B row {index.row} is outside [1, {self.arity}]")
        if not 0 <= index.pointer <= self.arity:
            raise ValueError(f"B pointer {index.pointer} is outside [0, {self.arity}]")
        if not 1 <= index.x <= self.length:
            raise ValueError(f"B x {index.x} is outside [1, {self.length}]")
        if not 1 <= index.bit <= self.max_bits:
            raise ValueError(f"B bit {index.bit} is outside [1, {self.max_bits}]")

    def symbol(self, index: BIndex) -> sp.Symbol:
        self.validate_b_index(index)
        if index not in self._symbols:
            symbol = sp.Symbol(index.symbol_name, integer=True)
            self._symbols[index] = symbol
            self._indices[symbol] = index
        return self._symbols[index]

    def b2int_symbols(self, *, row: int, pointer: int, x: int) -> sp.Expr:
        """Return b2int(B_row,pointer,x,1, ..., B_row,pointer,x,max_bits)."""
        total = sp.Integer(0)
        for bit in range(1, self.max_bits + 1):
            total += sp.Integer(2 ** (bit - 1)) * self.symbol(BIndex(row, pointer, x, bit))
        return total

    def compile_term(self, term: Term, x: int) -> sp.Expr:
        """Compile a term by the paper's ``mkQ`` rules.

        Constants, ``X``, ``len(C)``, addition, and multiplication follow Figure
        4 literally.  ``C_i(X)`` becomes ``b2int(B_i,0,x,*)`` and
        ``C_i(C_j(X))`` becomes ``b2int(B_i,j,x,*)``.
        """
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
            return self.b2int_symbols(row=term.row, pointer=pointer, x=x)
        raise TypeError(f"Unsupported term type: {type(term).__name__}")

    def compile_formula(self, formula: Formula, x: int) -> sp.Expr:
        """Compile a predicate to a multivariate polynomial.

        This applies the Figure 2 clauses after compiling the constituent terms:
        equality is squared difference, conjunction is sum, and disjunction is
        product.
        """
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

    def mkq(self, obj: Formula | Term, x: int, *, expand: bool = False) -> "CompiledPolynomial":
        """Compile a formula or term to the mkQ polynomial at 1-based x."""
        if isinstance(obj, Formula):
            expression = self.compile_formula(obj, x)
        elif isinstance(obj, Term):
            expression = self.compile_term(obj, x)
        else:
            raise TypeError(f"Expected Formula or Term, got {type(obj).__name__}")
        if expand:
            expression = sp.expand(expression)
        return CompiledPolynomial(expression=expression, x=x, context=self, source=obj)


@dataclass(frozen=True)
class CompiledPolynomial:
    """A mkQ polynomial plus enough metadata to evaluate beta safely."""

    expression: sp.Expr
    x: int
    context: CompilationContext
    source: Formula | Term | None = None

    def beta(self, witness: MatrixInterpretation) -> int:
        return beta(self.expression, witness, self.context.symbol_indices)

    def direct_value(self, witness: MatrixInterpretation) -> int:
        if self.source is None:
            raise ValueError("direct_value is unavailable without a source AST")
        return self.source.evaluate(witness, self.x)


def mkq(obj: Formula | Term, witness: MatrixInterpretation, x: int, *, expand: bool = False) -> CompiledPolynomial:
    """Convenience wrapper: build a context from ``witness`` and compile at ``x``.

    This is the function most closely corresponding to ``mkQ_F^x`` in Figure 4.
    The witness supplies arity, length, and maximum bit length.
    """
    return CompilationContext.from_witness(witness).mkq(obj, x, expand=expand)


def beta_symbol(index: BIndex, witness: MatrixInterpretation) -> int:
    """Evaluate one B variable under beta.

    For non-composed symbols, this is the selected bit of C_i(x). For composed
    symbols, it is the selected bit of C_i(C_j(x)), or 0 if C_j(x) is out of
    range. The latter follows Definition 3.6 in the paper.
    """
    witness.validate_row(index.row)
    if not 1 <= index.x <= witness.length:
        raise WitnessError(f"B x {index.x} is outside witness length {witness.length}")
    if index.pointer == 0:
        value = witness.value(index.row, index.x)
    else:
        witness.validate_row(index.pointer)
        pointed_column = witness.value(index.pointer, index.x)
        if not 1 <= pointed_column <= witness.length:
            return 0
        value = witness.value(index.row, pointed_column)
    return bit_at_lsb_first(value, index.bit)


def beta(
    expression: sp.Expr,
    witness: MatrixInterpretation,
    symbol_indices: Mapping[sp.Symbol, BIndex] | None = None,
) -> int:
    """Evaluate a compiled mkQ polynomial by substituting beta bits.

    SymPy's general ``subs`` machinery can be very slow on large, deliberately
    unexpanded mkQ expressions. The polynomials generated here use only integer
    constants, symbols, addition, multiplication, and non-negative integer powers,
    so a small recursive evaluator is both clearer and much faster.
    """
    known = symbol_indices or {}
    symbol_values: dict[sp.Symbol, int] = {}
    for symbol in expression.free_symbols:
        index = known.get(symbol)
        if index is None:
            index = parse_b_symbol(symbol)
        symbol_values[symbol] = beta_symbol(index, witness)

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
        raise ValueError(f"Unsupported expression node in beta evaluation: {expr!r}")

    return eval_expr(expression)


def to_enriched_polynomial(obj: Formula | Term, *, expand: bool = False) -> sp.Expr:
    """Render the paper's enriched-polynomial semantics as a SymPy expression.

    This function is for inspection and debugging. mkQ compilation does not
    parse this string/expression; it compiles from the AST directly.
    """
    X = sp.Symbol("X", integer=True)

    def term_to_expr(term: Term) -> sp.Expr:
        if isinstance(term, Const):
            return sp.Integer(term.value)
        if isinstance(term, Index):
            return X
        if isinstance(term, Len):
            return sp.Symbol("len_C", integer=True)
        if isinstance(term, Add):
            return term_to_expr(term.left) + term_to_expr(term.right)
        if isinstance(term, Mul):
            return term_to_expr(term.left) * term_to_expr(term.right)
        if isinstance(term, MatrixCell):
            function = sp.Function(f"C{term.row}")
            if term.pointer_row is None:
                return function(X)
            pointer_function = sp.Function(f"C{term.pointer_row}")
            return function(pointer_function(X))
        raise TypeError(f"Unsupported term type: {type(term).__name__}")

    def formula_to_expr(formula: Formula) -> sp.Expr:
        if isinstance(formula, Eq):
            diff = term_to_expr(formula.left) - term_to_expr(formula.right)
            return diff * diff
        if isinstance(formula, And):
            return sum((formula_to_expr(part) for part in formula.parts), sp.Integer(0))
        if isinstance(formula, Or):
            product = sp.Integer(1)
            for part in formula.parts:
                product *= formula_to_expr(part)
            return product
        raise TypeError(f"Unsupported formula type: {type(formula).__name__}")

    if isinstance(obj, Formula):
        expression = formula_to_expr(obj)
    elif isinstance(obj, Term):
        expression = term_to_expr(obj)
    else:
        raise TypeError(f"Expected Formula or Term, got {type(obj).__name__}")
    return sp.expand(expression) if expand else expression
