"""Example predicates, witness matrices, and paper cross-references.

The examples in this module are deliberately verbose.  A reader should be able
both to run the code and to see why the mathematical clauses correspond to the
paper.

General paper map
-----------------
The paper's core pipeline is:

1. Figure 1: terms and predicates contain constants, ``X``, ``len(C)``,
   ``C_i(X)``, and one level of pointer composition ``C_i(C_j(X))``.
2. Figure 2: equalities become squares, conjunctions become sums, and
   disjunctions become products.  This is the "zero means true" convention.
3. Figure 3: the same zero-is-true rules give the direct integer semantics.
4. Definition 3.5 / Figure 4: ``mkQ`` replaces each ``C_i(...)`` term by a
   ``b2int`` expression over quad-indexed ``B`` variables.
5. Definition 3.6: ``beta`` substitutes the relevant witness bits for those
   ``B`` variables.
6. Theorem 3.8: after range checks for pointer rows, ``beta(mkQ(<phi>))``
   agrees with the direct integer semantics of ``phi``.

Each ``ExampleSpec`` below carries a ``paper_reference`` explaining where to
look in the paper.  Only standard exponentiation is a named worked example
in Section 5 of the draft.  Efficient power, factorial, and Fibonacci are additional recursive examples;
their references point to the general machinery rather than to a dedicated
Section 5 subsection.
"""

from __future__ import annotations

from dataclasses import dataclass

from .ast import Formula, cell, conj, disj
from .paper import (
    EFFICIENT_POWER_REFERENCE,
    FACTORIAL_REFERENCE,
    FIBONACCI_REFERENCE,
    POWER_REFERENCE,
)
from .witness import MatrixInterpretation, PointerRangeCheck
from .witnesses import (
    efficient_power_witness,
    factorial_witness,
    fibonacci_witness,
    power_witness,
)


@dataclass(frozen=True)
class EvaluationResult:
    """Result of checking one witness column.

    ``direct_value`` is the integer semantics from the AST, mirroring Figure 3
    of the paper.  ``beta_value`` is the value of the compiled ``mkQ``
    polynomial after applying beta, mirroring Definition 3.5/Figure 4 followed
    by Definition 3.6.  Theorem 3.8 predicts that these two integers are equal
    whenever the pointer rows are in range.  For a valid witness, both should be
    zero at every column.
    """

    x: int
    direct_value: int
    beta_value: int


@dataclass(frozen=True)
class ExampleSpec:
    """A complete worked example.

    Attributes:
        name: Stable command-line/test identifier.
        predicate: FOL formula represented by the AST in :mod:`zkfol.ast`.
        witness: Matrix interpretation of the single matrix symbol ``C``.
        pointer_rows: Rows whose entries are used as columns by composed terms
            ``C_i(C_j(X))`` and must therefore satisfy ``1 <= C_j(X) <= len(C)``.
        description: One-line description for command-line output.
        paper_reference: Specific pointer to the paper, or an explicit
            note how the example relates to the paper.
        mathematical_description: Plain-language statement of the recurrence
            encoded by the predicate.
        witness_convention: Row-by-row explanation of what the matrix stores.
    """

    name: str
    predicate: Formula
    witness: MatrixInterpretation
    pointer_rows: tuple[int, ...]
    description: str
    paper_reference: str
    mathematical_description: str
    witness_convention: str

    @property
    def range_checks(self) -> tuple[PointerRangeCheck, ...]:
        """Return the pointer range checks required by Definition 3.1/3.7."""
        return tuple(PointerRangeCheck(row) for row in self.pointer_rows)

    @property
    def range_check_summary(self) -> str:
        if not self.pointer_rows:
            return "No composed C_i(C_j(X)) terms, so no pointer rows are required."
        rows = ", ".join(f"C{row}" for row in self.pointer_rows)
        return f"Pointer row(s) {rows} must satisfy 1 <= value <= len(C) in every column."

    def pointer_range_ok(self) -> bool:
        """Check that every pointer row points to a valid witness column."""
        return all(check.is_satisfied(self.witness) for check in self.range_checks)

    def evaluate_all(self, *, expand: bool = False) -> tuple[EvaluationResult, ...]:
        """Evaluate every ``mkQ_x`` polynomial and compare with Figure 3 semantics.

        This is the explicit symbolic route: it constructs the SymPy ``mkQ``
        polynomial at each 1-based column ``x`` and then applies beta.  The CLI's
        default fast backend computes the same value without constructing SymPy
        expressions; use ``./run --symbolic`` to exercise this method.
        """
        from .compiler import CompilationContext

        context = CompilationContext.from_witness(self.witness)
        out: list[EvaluationResult] = []
        for x in range(1, self.witness.length + 1):
            compiled = context.mkq(self.predicate, x, expand=expand)
            out.append(
                EvaluationResult(
                    x=x,
                    direct_value=self.predicate.evaluate(self.witness, x),
                    beta_value=compiled.beta(self.witness),
                )
            )
        return tuple(out)

    def is_valid(self) -> bool:
        """Return True exactly when range checks pass and every column is true."""
        return self.pointer_range_ok() and all(result.beta_value == 0 for result in self.evaluate_all())


# ---------------------------------------------------------------------------
# Predicates
# ---------------------------------------------------------------------------


def power_predicate() -> Formula:
    """Predicate for standard recursive exponentiation.

    Paper pointer: Section 5 of the draft, "Arithmetising Power Functions",
    Definition 5.1, and the displayed predicate ``(phi_pow, R_pow)``.

    Row convention, matching the paper's pow_i notation:
        C1 / pow1: fixed base ``a``.
        C2 / pow2: exponent ``b``.
        C3 / pow3: value ``a**b``.
        C4 / pow4: pointer to the column for exponent ``b-1``.

    Mathematical meaning:
        A column is valid if it is either the base case ``b = 0`` and value 1,
        or an inductive step whose pointer column has the same base, exponent
        one smaller, and value multiplied by the base.  The outer disjunction is
        important: Figure 2 makes OR into multiplication, so only one branch
        needs to evaluate to zero for the whole predicate to be true.
    """
    base = cell(1)
    exponent = cell(2)
    value = cell(3)
    previous = 4

    base_case = conj(exponent.eq(0), value.eq(1))
    inductive_step = conj(
        base.eq(cell(1, previous)),
        exponent.eq(cell(2, previous) + 1),
        value.eq(base * cell(3, previous)),
    )
    return disj(base_case, inductive_step)


def efficient_power_predicate() -> Formula:
    """Predicate for exponentiation by repeated squaring.

    Paper pointer: this is not a named worked example in the paper.  It is
    a direct variation on the Section 5 power example, using the same syntax and
    semantics from Figures 1-4.

    Row convention:
        C1: fixed base ``a``.
        C2: exponent ``b``.
        C3: value ``a**b``.
        C4: pointer to the column for ``floor(b/2)``.

    Mathematical meaning:
        The base case is ``b = 0`` and value 1.  If ``b`` is even, the value is
        the pointed half-value squared.  If ``b`` is odd, multiply that square by
        the base.  The even and odd branches are represented as separate OR
        branches, so one matching branch makes the whole predicate zero.
    """
    base = cell(1)
    exponent = cell(2)
    value = cell(3)
    half = 4

    base_case = conj(exponent.eq(0), value.eq(1))
    even_step = conj(
        base.eq(cell(1, half)),
        exponent.eq(2 * cell(2, half)),
        value.eq(cell(3, half) * cell(3, half)),
    )
    odd_step = conj(
        base.eq(cell(1, half)),
        exponent.eq(2 * cell(2, half) + 1),
        value.eq(base * cell(3, half) * cell(3, half)),
    )
    return disj(base_case, even_step, odd_step)


def factorial_predicate() -> Formula:
    """Predicate matching :func:`factorial_witness`.

    Paper pointer: factorial is not a named worked example in the paper;
    it is a compact test of the general FOL-to-polynomial pipeline in Figures
    1-4 and Theorem 3.8.

    Row convention:
        C1: argument ``n``.
        C2: value ``n!``.
        C3: pointer to the column for ``(n-1)!``.

    Mathematical meaning:
        The witness builder starts at ``1! = 1``.  Therefore the predicate's
        base case is ``C1(X)=1`` and ``C2(X)=1``.  The recursive step says
        that the current ``n`` is one more than the pointed previous ``n`` and
        that ``n! = n * (n-1)!``.
    """
    n = cell(1)
    value = cell(2)
    previous = 3

    base_case = conj(n.eq(1), value.eq(1))
    inductive_step = conj(
        n.eq(cell(1, previous) + 1),
        value.eq(n * cell(2, previous)),
    )
    return disj(base_case, inductive_step)


def fibonacci_predicate() -> Formula:
    """Predicate matching :func:`fibonacci_witness`.

    Paper pointer: Fibonacci is not a named worked example in the paper;
    it demonstrates the two-pointer case of the general pointer semantics in
    Definition 3.1/3.7 and the beta/mkQ equivalence in Theorem 3.8.

    Row convention:
        C1: argument ``n``.
        C2: value ``fib(n)``.
        C3: pointer to the column for ``fib(n-1)``.
        C4: pointer to the column for ``fib(n-2)``.

    Mathematical meaning:
        The witness builder uses the 1-based Fibonacci convention
        ``fib(1)=fib(2)=1``.  The recursive step says that the C3 pointer is one
        step behind, the C4 pointer is two steps behind, and the current value is
        the sum of the two pointed values.
    """
    n = cell(1)
    value = cell(2)
    minus_one = 3
    minus_two = 4

    base_one = conj(n.eq(1), value.eq(1))
    base_two = conj(n.eq(2), value.eq(1))
    inductive_step = conj(
        n.eq(cell(1, minus_one) + 1),
        n.eq(cell(1, minus_two) + 2),
        value.eq(cell(2, minus_one) + cell(2, minus_two)),
    )
    return disj(base_one, base_two, inductive_step)


# ---------------------------------------------------------------------------
# Bundled example specifications
# ---------------------------------------------------------------------------


def power_example(base: int = 3, exponent: int = 3) -> ExampleSpec:
    return ExampleSpec(
        name="standard_power",
        predicate=power_predicate(),
        witness=power_witness(base, exponent),
        pointer_rows=(4,),
        description="Standard recursive exponentiation predicate from the paper.",
        paper_reference=POWER_REFERENCE,
        mathematical_description=(
            "Encodes pow(a,0)=1 and pow(a,b+1)=a*pow(a,b), with row C4 pointing "
            "from each inductive column to the previous exponent column."
        ),
        witness_convention="Rows are C1=base, C2=exponent, C3=base**exponent, C4=previous-column pointer.",
    )


def efficient_power_example(base: int = 2, exponent: int = 8) -> ExampleSpec:
    return ExampleSpec(
        name="efficient_power",
        predicate=efficient_power_predicate(),
        witness=efficient_power_witness(base, exponent),
        pointer_rows=(4,),
        description="Repeated-squaring exponentiation predicate.",
        paper_reference=EFFICIENT_POWER_REFERENCE,
        mathematical_description=(
            "Encodes pow(a,0)=1 and, for b>0, a recursive call at floor(b/2); "
            "even b squares the half-value and odd b multiplies that square by a."
        ),
        witness_convention="Rows are C1=base, C2=exponent, C3=base**exponent, C4=floor-half pointer.",
    )


def factorial_example(n: int = 4) -> ExampleSpec:
    return ExampleSpec(
        name="factorial",
        predicate=factorial_predicate(),
        witness=factorial_witness(n),
        pointer_rows=(3,),
        description="Factorial predicate using the 1-based witness convention.",
        paper_reference=FACTORIAL_REFERENCE,
        mathematical_description="Encodes 1!=1 and n!=n*(n-1)! using one recursive pointer row.",
        witness_convention="Rows are C1=n, C2=n!, C3=pointer to the column for (n-1)!; the first column is 1!.",
    )


def fibonacci_example(n: int = 5) -> ExampleSpec:
    return ExampleSpec(
        name="fibonacci",
        predicate=fibonacci_predicate(),
        witness=fibonacci_witness(n),
        pointer_rows=(3, 4),
        description="Fibonacci predicate using fib(1)=fib(2)=1 and two pointer rows.",
        paper_reference=FIBONACCI_REFERENCE,
        mathematical_description="Encodes fib(1)=fib(2)=1 and fib(n)=fib(n-1)+fib(n-2).",
        witness_convention=(
            "Rows are C1=n, C2=fib(n), C3=pointer to fib(n-1), C4=pointer to fib(n-2); "
            "the first two columns are the two base cases."
        ),
    )
