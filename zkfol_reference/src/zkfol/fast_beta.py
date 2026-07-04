"""Fast ``beta(mkQ)``-equivalent evaluation without SymPy construction.

The symbolic implementation in :mod:`zkfol.compiler` constructs the paper's
``mkQ`` polynomials explicitly and substitutes B-variable bits.  This module
follows the same recursive clauses but evaluates immediately against a concrete
witness.

Why this is legitimate for the bundled checks: Figure 4 and Definition 3.6 are
compositional.  Applying beta immediately at each AST node gives the same result
as first building the full polynomial and then applying beta.  The unit tests run
both routes on representative examples; ``./run --symbolic`` forces the
explicit route.
"""

from __future__ import annotations

from .ast import Add, And, Const, Eq, Formula, Index, Len, MatrixCell, Mul, Or, Term
from .witness import MatrixInterpretation


def beta_matrix_cell_fast(term: MatrixCell, witness: MatrixInterpretation, x: int) -> int:
    """Evaluate beta(mkQ^x(C_i(...))) for a matrix-cell term.

    For composed cells C_i(C_j(X)), an out-of-range pointer evaluates to zero,
    matching Definition 3.6 of the paper and the symbolic beta implementation.
    """

    witness.validate_column(x)
    witness.validate_row(term.row)
    if term.pointer_row is None:
        value = witness.value(term.row, x)
    else:
        witness.validate_row(term.pointer_row)
        pointed_column = witness.value(term.pointer_row, x)
        if not 1 <= pointed_column <= witness.length:
            return 0
        value = witness.value(term.row, pointed_column)
    # Figure 4 reads the cell as b2int over its max_bits bit expansion, and
    # b2int(bits(value)) == value because witness.max_bits bounds every entry,
    # so the decompose/recompose round trip is the identity.
    return value


def beta_term_fast(term: Term, witness: MatrixInterpretation, x: int) -> int:
    """Evaluate ``beta(mkQ^x(<term>))`` directly from witness bits."""

    witness.validate_column(x)
    if isinstance(term, Const):
        return term.value
    if isinstance(term, Index):
        return x
    if isinstance(term, Len):
        return witness.length
    if isinstance(term, MatrixCell):
        return beta_matrix_cell_fast(term, witness, x)
    if isinstance(term, Add):
        return beta_term_fast(term.left, witness, x) + beta_term_fast(term.right, witness, x)
    if isinstance(term, Mul):
        return beta_term_fast(term.left, witness, x) * beta_term_fast(term.right, witness, x)
    raise TypeError(f"unsupported term type: {type(term).__name__}")


def beta_formula_fast(formula: Formula, witness: MatrixInterpretation, x: int) -> int:
    """Evaluate ``beta(mkQ^x(<formula>))`` directly from witness bits."""

    witness.validate_column(x)
    if isinstance(formula, Eq):
        diff = beta_term_fast(formula.left, witness, x) - beta_term_fast(formula.right, witness, x)
        return diff * diff
    if isinstance(formula, And):
        return sum(beta_formula_fast(part, witness, x) for part in formula.parts)
    if isinstance(formula, Or):
        product = 1
        for part in formula.parts:
            product *= beta_formula_fast(part, witness, x)
        return product
    raise TypeError(f"unsupported formula type: {type(formula).__name__}")


def beta_all_fast(formula: Formula, witness: MatrixInterpretation) -> tuple[int, ...]:
    """Evaluate the fast beta(mkQ) value at every witness column."""

    return tuple(beta_formula_fast(formula, witness, x) for x in range(1, witness.length + 1))
