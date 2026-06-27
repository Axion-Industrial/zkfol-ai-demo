"""SK-combinator example kept separate from the smaller arithmetic examples.

Paper pointer: the included paper's second worked example is "Arithmetising SK
Combinator Reduction" in Section 5, beginning with Definition 5.2.  The paper
uses an arity-8 matrix symbol ``SK`` and a predicate ``phi_SK`` with five OR
branches:

* ``Kred``: ``((K a) b)`` reduces to ``a``;
* ``Sred``: ``(((S x) y) z)`` reduces to ``((x z) (y z))``;
* ``Id``: a term reduces to itself;
* ``Par``: two subreductions can be lifted through application; and
* ``Tran``: two reductions can be composed transitively.

The code below follows the standard SK-calculus rule for ``S`` and matches the
included paper's displayed ``Sred`` equality:
``SK2(X) = <<SK3(X), SK5(X)>, <SK4(X), SK5(X)>>``, i.e.
``S x y z -> (x z)(y z)``.  It lives in this separate module because the
predicate is intentionally larger than the power/factorial/Fibonacci examples
in :mod:`zkfol.examples`.

Encoding convention
-------------------
The paper reserves ``0`` and ``1`` for the atomic combinators ``S`` and ``K``.
Application is encoded by the shifted Cantor-style polynomial pairing function
from Definition 5.2:

    pair(x, y) = (x + y) * (x + y + 1) + 2*x + 2

The ``+ 2`` keeps every application code at least 2, leaving 0 and 1 free for
``S`` and ``K``.  This implementation provides both an integer version for
building concrete witnesses and an AST-term version for building the FOL
predicate.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from .ast import Formula, TermLike, as_term, cell, conj, disj
from .paper import SK_REFERENCE
from .witness import MatrixInterpretation

S_COMBINATOR = 0
K_COMBINATOR = 1


def sk_pair_int(left: int, right: int) -> int:
    """Integer shifted Cantor pairing from Definition 5.2 of the paper.

    The paper calls the unshifted polynomial ``<x,y>'`` and then uses
    ``<x,y> := <x,y>' + 2`` in the SK predicate.  This function is the shifted
    version used for concrete term encodings.
    """

    if not isinstance(left, int) or not isinstance(right, int):
        raise TypeError("SK pair arguments must be integers")
    if left < 0 or right < 0:
        raise ValueError("SK term codes must be non-negative")
    return (left + right) * (left + right + 1) + 2 * left + 2

def sk_unpair_int(code: int) -> tuple[int, int]:
    """Invert :func:`sk_pair_int` on valid application codes.

    Atomic codes ``0`` and ``1`` are not applications and therefore cannot be
    unpaired.  For a valid application code ``z >= 2`` this returns the unique
    pair ``(left, right)`` satisfying ``sk_pair_int(left, right) == z``.
    """

    if not isinstance(code, int):
        raise TypeError("SK code must be an integer")
    if code < 2:
        raise ValueError("atomic SK codes are not paired applications")

    target = code - 2
    total = 0
    while total * (total + 1) <= target:
        remainder = target - total * (total + 1)
        if remainder % 2 == 0:
            left = remainder // 2
            right = total - left
            if 0 <= left <= total and right >= 0 and sk_pair_int(left, right) == code:
                return left, right
        total += 1
    raise ValueError(f"{code} is not a valid shifted Cantor SK application code")


def pretty_sk_term(code: int, *, max_depth: int = 16) -> str:
    """Pretty-print an integer SK term code.

    ``0`` prints as ``S`` and ``1`` prints as ``K``.  Application codes are
    recursively decoded using :func:`sk_unpair_int` and printed as ``(left right)``.
    Invalid non-atomic codes are displayed as ``#<number>`` rather than raising;
    this makes corrupted negative-test witnesses easy to inspect.
    """

    if code == S_COMBINATOR:
        return "S"
    if code == K_COMBINATOR:
        return "K"
    if max_depth <= 0:
        return f"...{code}"
    try:
        left, right = sk_unpair_int(code)
    except (TypeError, ValueError):
        return f"#{code}"
    return f"({pretty_sk_term(left, max_depth=max_depth - 1)} {pretty_sk_term(right, max_depth=max_depth - 1)})"


def format_sk_witness_rows(witness: MatrixInterpretation) -> tuple[str, ...]:
    """Return human-readable SK rows for CLI output.

    Rows 1--5 contain SK term codes and are displayed as ``raw:pretty``.  Rows
    6--7 are column pointers and row 8 is the derivation height counter, so they
    remain numeric with short labels.  The raw numbers are preserved in the main
    CLI output; these lines sit next to them for readability.
    """

    if witness.arity != 8:
        raise ValueError("SK pretty-printer expects an arity-8 witness")
    labels = {
        1: "C1 input",
        2: "C2 output",
        3: "C3 S-arg x",
        4: "C4 aux y",
        5: "C5 aux z",
        6: "C6 left pointer",
        7: "C7 right pointer",
        8: "C8 height",
    }
    lines: list[str] = []
    for row_index in range(1, 9):
        entries: list[str] = []
        for column, value in enumerate(witness.row(row_index), start=1):
            if row_index <= 5:
                entries.append(f"x={column}: {value}:{pretty_sk_term(value)}")
            elif row_index in (6, 7):
                entries.append(f"x={column}: {value}->col{value}")
            else:
                entries.append(f"x={column}: {value}")
        lines.append(f"{labels[row_index]} | " + " | ".join(entries))
    return tuple(lines)



def sk_pair_term(left: TermLike, right: TermLike):
    """AST term for the same shifted Cantor pairing polynomial.

    This is the code-level counterpart of every displayed ``<...,...>`` in the
    paper's SK example.  Since it is built from addition and multiplication, it
    remains inside the Figure 1 term language.
    """

    left_t = as_term(left)
    right_t = as_term(right)
    total = left_t + right_t
    return total * (total + 1) + 2 * left_t + 2


def sk_sred_source_int(x: int, y: int, z: int) -> int:
    """Encode the left-hand side ``(((S x) y) z)`` of S reduction."""

    return sk_pair_int(sk_pair_int(sk_pair_int(S_COMBINATOR, x), y), z)


def sk_sred_target_int(x: int, y: int, z: int) -> int:
    """Encode the paper's S-reduction target ``((x z) (y z))``.

    This is the ordinary SK-combinator rule ``S x y z -> (x z) (y z)`` and
    matches the included paper's displayed line
    ``SK2(X) = <<SK3(X), SK5(X)>, <SK4(X), SK5(X)>>``.
    """

    return sk_pair_int(sk_pair_int(x, z), sk_pair_int(y, z))


def sk_sred_incorrect_target_int(x: int, y: int, z: int) -> int:
    """Encode an intentionally incorrect S target ``((x y) (x z))``.

    This helper is used only in tests as a negative control: a column satisfying
    this alternative target should fail the implemented predicate unless it
    coincidentally satisfies another branch.  The included paper does not use
    this target.
    """

    return sk_pair_int(sk_pair_int(x, y), sk_pair_int(x, z))


def sk_sred_source_term(x: TermLike, y: TermLike, z: TermLike):
    """AST term for ``(((S x) y) z)``."""

    return sk_pair_term(sk_pair_term(sk_pair_term(S_COMBINATOR, x), y), z)


def sk_sred_target_term(x: TermLike, y: TermLike, z: TermLike):
    """AST term for the paper's target ``((x z) (y z))``."""

    return sk_pair_term(sk_pair_term(x, z), sk_pair_term(y, z))


@dataclass(frozen=True)
class SkTermNames:
    """Small record of named SK term codes used in the bundled witness."""

    S: int = S_COMBINATOR
    K: int = K_COMBINATOR
    KS: int = sk_pair_int(K_COMBINATOR, S_COMBINATOR)
    SK: int = sk_pair_int(S_COMBINATOR, K_COMBINATOR)


def sk_predicate() -> Formula:
    """Return the Section 5 predicate ``phi_SK``.

    Row convention, matching the paper's displayed arity-8 matrix:

    * ``C1`` / ``SK1``: input term of a reduction.
    * ``C2`` / ``SK2``: output term of that reduction.
    * ``C3`` / ``SK3``: the ``x`` argument used by the S-reduction branch.
    * ``C4`` / ``SK4``: the ``y``/auxiliary argument used by K/S branches.
    * ``C5`` / ``SK5``: the ``z`` argument used by the S-reduction branch.
    * ``C6`` / ``SK6``: first pointer row used by ``Par`` and ``Tran``.
    * ``C7`` / ``SK7``: second pointer row used by ``Par`` and ``Tran``.
    * ``C8`` / ``SK8``: a simple derivation-height counter.

    Paper correspondence:
    the five local variables below are named exactly after the paper display:
    ``Kred(X)``, ``Sred(X)``, ``Id(X)``, ``Par(X)``, and ``Tran(X)``.  The return
    value is their disjunction, i.e. Figure 2 will compile it as the product of
    the five branch polynomials.  A column is valid when at least one branch is
    zero.
    """

    source = cell(1)
    target = cell(2)
    s_arg_x = cell(3)
    aux_y = cell(4)
    aux_z = cell(5)
    left_pointer = 6
    right_pointer = 7
    height = cell(8)

    # Kred(X) = SK1(X) = < <1, SK2(X)>, SK4(X) >.
    kred = source.eq(sk_pair_term(sk_pair_term(K_COMBINATOR, target), aux_y))

    # Sred(X) = two equalities for the paper's S rule:
    #   SK1(X) = (((S SK3(X)) SK4(X)) SK5(X))
    #   SK2(X) = ((SK3(X) SK5(X)) (SK4(X) SK5(X)))
    sred = conj(
        source.eq(sk_sred_source_term(s_arg_x, aux_y, aux_z)),
        target.eq(sk_sred_target_term(s_arg_x, aux_y, aux_z)),
    )

    # Id(X) = SK1(X) = SK2(X).
    identity = source.eq(target)

    # Par(X): lift two pointed reductions through application.
    parallel = conj(
        source.eq(sk_pair_term(cell(1, left_pointer), cell(1, right_pointer))),
        target.eq(sk_pair_term(cell(2, left_pointer), cell(2, right_pointer))),
        height.eq(cell(8, left_pointer) + 1),
        height.eq(cell(8, right_pointer) + 1),
    )

    # Tran(X): compose two pointed reductions source -> middle -> target.
    transitive = conj(
        source.eq(cell(1, left_pointer)),
        target.eq(cell(2, right_pointer)),
        cell(2, left_pointer).eq(cell(1, right_pointer)),
        height.eq(cell(8, left_pointer) + 1),
        height.eq(cell(8, right_pointer) + 1),
    )

    return disj(kred, sred, identity, parallel, transitive)


def sk_demo_columns() -> tuple[tuple[int, ...], ...]:
    """Return six human-auditable columns satisfying ``phi_SK``.

    The columns are deliberately small and named in comments, because a reader
    should be able to recompute the interesting entries by hand:

    1. ``S -> S`` by ``Id``.
    2. ``K -> K`` by ``Id``.
    3. ``((K S) K) -> S`` by ``Kred``.
    4. ``(((S K) S) K) -> ((K K) (S K))`` by the paper's ``Sred`` rule.
    5. A ``Par`` step combining columns 3 and 2.
    6. A ``Tran`` step composing column 3 with column 1.

    Rows ``C6`` and ``C7`` are pointers.  Even in columns where a branch does not
    use them, they are kept in the range ``[1, len(C)]`` to satisfy the range
    checks required by Definition 3.1/3.7.
    """

    S = S_COMBINATOR
    K = K_COMBINATOR

    # Column 1: S -> S, via Id.
    col1 = (S, S, 0, 0, 0, 1, 1, 1)

    # Column 2: K -> K, via Id.
    col2 = (K, K, 0, 0, 0, 1, 1, 1)

    # Column 3: ((K S) K) -> S, via Kred.
    k_input = sk_pair_int(sk_pair_int(K, S), K)
    col3 = (k_input, S, 0, K, 0, 1, 1, 1)

    # Column 4: (((S K) S) K) -> ((K K) (S K)), via Sred.
    x = K
    y = S
    z = K
    s_input = sk_sred_source_int(x, y, z)
    s_output = sk_sred_target_int(x, y, z)
    col4 = (s_input, s_output, x, y, z, 1, 1, 1)

    # Column 5: Par using columns 3 and 2.
    par_input = sk_pair_int(col3[0], col2[0])
    par_output = sk_pair_int(col3[1], col2[1])
    col5 = (par_input, par_output, 0, 0, 0, 3, 2, 2)

    # Column 6: Tran using columns 3 and 1: ((K S) K)->S and S->S.
    col6 = (col3[0], col1[1], 0, 0, 0, 3, 1, 2)

    return (col1, col2, col3, col4, col5, col6)


def sk_witness(columns: Sequence[Sequence[int]] | None = None) -> MatrixInterpretation:
    """Build the arity-8 SK witness matrix.

    ``columns`` may be supplied by tests or experiments.  When omitted, the
    bundled six-column demonstration from :func:`sk_demo_columns` is used.
    """

    return MatrixInterpretation.from_columns(columns or sk_demo_columns(), name="SK")


def sk_example():
    """Return an ``ExampleSpec`` for the bundled SK-combinator reduction demo.

    The import of :class:`zkfol.examples.ExampleSpec` is intentionally local to
    avoid a circular import: the small examples live in ``examples.py`` while this
    larger Section 5 example lives here.
    """

    from .examples import ExampleSpec

    return ExampleSpec(
        name="sk_combinator",
        predicate=sk_predicate(),
        witness=sk_witness(),
        pointer_rows=(6, 7),
        description="SK combinator reduction predicate from the paper's second Section 5 example.",
        paper_reference=SK_REFERENCE,
        mathematical_description=(
            "Encodes the five local reduction clauses Kred, Sred, Id, Par, and Tran using the "
            "shifted Cantor pairing function from Definition 5.2."
        ),
        witness_convention=(
            "Rows are C1=input term, C2=output term, C3/C4/C5=auxiliary S/K-rule arguments, "
            "C6/C7=subreduction pointers, and C8=derivation height."
        ),
    )
