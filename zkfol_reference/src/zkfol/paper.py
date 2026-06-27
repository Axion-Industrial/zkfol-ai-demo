"""Human-readable pointers from the implementation to the included paper.

This module intentionally contains no executable mathematics.  It is a small
index for readers who are trying to line code up with the paper.  The strings
are used by the command-line interface and by the example specifications.

The most important correspondence is Theorem 3.8 of the included paper:

    beta_F(mkQ_F^x(<formula>)) = integer_semantics_x(formula)

whenever the pointer rows used by the formula are in range.  The package tests
that equality for each bundled example by comparing direct AST evaluation with
explicit or fast beta(mkQ) evaluation at every witness column.
"""

from __future__ import annotations

GENERAL_PIPELINE_REFERENCE = (
    "Paper map: Figure 1 gives the FOL syntax; Figure 2 maps terms and "
    "predicates to enriched polynomials; Figure 3 gives the zero-is-true "
    "integer semantics; Definition 3.5 and Figure 4 define mkQ; Definition 3.6 "
    "defines beta; Theorem 3.8 states that beta(mkQ(<phi>)) agrees with the "
    "integer semantics when pointer rows are range-checked."
)

POWER_REFERENCE = (
    "Paper Section 5, 'Arithmetising Power Functions', Definition 5.1 "
    "and the displayed predicate (phi_pow, R_pow).  The paper uses rows pow1, "
    "pow2, pow3, pow4 for base, exponent, output, and recursive pointer."
)

EFFICIENT_POWER_REFERENCE = (
    "Not a separately named worked example in the paper.  This is a "
    "repeated-squaring variant of the Section 5 power example, built with the "
    "same Figure 1 syntax, Figure 2 predicate-to-polynomial map, Figure 4 mkQ "
    "rules, and Definition 3.6 beta evaluation."
)

FACTORIAL_REFERENCE = (
    "Not a separately named worked example in the paper.  It is a small "
    "recursive-function example exercising the general machinery of Figures "
    "1-4 and Theorem 3.8."
)

FIBONACCI_REFERENCE = (
    "Not a separately named worked example in the paper.  It is a "
    "two-pointer recursive example exercising the same range-checked pointer "
    "semantics from Definition 3.1 and Definition 3.7, plus Theorem 3.8."
)

SK_REFERENCE = (
    "Paper Section 5, 'Arithmetising SK Combinator Reduction', "
    "Definition 5.2 for the shifted Cantor pairing function, and the displayed "
    "predicate (phi_SK, R_SK) with branches Kred, Sred, Id, Par, and Tran.  "
    "This implementation matches the paper's displayed S rule S x y z -> (x z)(y z), "
    "i.e. SK2(X) = <<SK3(X), SK5(X)>, <SK4(X), SK5(X)>>. "
    "Rows SK1..SK8 are input, output, three auxiliary arguments, two pointer "
    "rows, and a derivation-height row."
)

EXAMPLE_REFERENCES = {
    "standard_power": POWER_REFERENCE,
    "efficient_power": EFFICIENT_POWER_REFERENCE,
    "factorial": FACTORIAL_REFERENCE,
    "fibonacci": FIBONACCI_REFERENCE,
    "sk_combinator": SK_REFERENCE,
}
