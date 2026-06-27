# zkFOL reference implementation

This source tree implements the core arithmetisation pipeline described in
`../paper/fol-zinc.pdf`:

```text
FOL predicate -> enriched polynomial -> mkQ polynomial -> beta evaluation
```

The implemented fragment is the paper's single-matrix-symbol language with
integer constants, addition, multiplication, `len(C)`, the index variable `X`,
direct cells `C_i(X)`, composed cells `C_i(C_j(X))`, equality, conjunction, and
disjunction.  The code follows the paper's zero-is-true semantics: a predicate
is true at a witness column exactly when its integer value is `0`.

For the Zinc/CCS export and proof path, use the sibling adapter in
`../zkfol_zinc_adapter/` or the top-level `../folzinc` wrapper.

## Run from the source tree

From this directory:

```bash
./run
```

or equivalently:

```bash
python3 run.py
```

The default command validates all bundled examples with the fast bit-level
`beta(mkQ)` evaluator.  For the arithmetic examples, the explicit SymPy
`mkQ`/`beta` route is also available:

```bash
./run --symbolic
```

To run one example:

```bash
./run --example power
./run --example factorial --factorial-n 7
./run --example sk
```

To run the reference unit tests:

```bash
./run tests
# or
make test
```

## Where to change inputs

`./run --help` names the relevant files.  The most common edits are:

| Goal | File or command |
| --- | --- |
| Try one CLI input quickly | `./run --example power --power-base 5 --power-exponent 4` |
| Change default CLI inputs | `ExampleInputs` in `src/zkfol/cli.py` |
| Add arithmetic test cases | `POWER_CASES`, `EFFICIENT_POWER_CASES`, `FACTORIAL_CASES`, and `FIBONACCI_CASES` in `tests/test_parameter_grid.py` |
| Edit arithmetic predicates | `src/zkfol/examples.py` |
| Edit arithmetic witnesses | `src/zkfol/witnesses.py` |
| Edit the SK example | `src/zkfol/sk.py` |
| Add negative controls | `tests/test_negative_controls.py` and `tests/test_sk.py` |

## Bundled examples

| Example | CLI selector | Paper pointer |
| --- | --- | --- |
| Standard power | `--example power` | Section 5, Definition 5.1, and the displayed `(phi_pow, R_pow)` predicate |
| Efficient power | `--example efficient` | A repeated-squaring variant using the same Figures 1--4 and Theorem 3.8 pipeline |
| Factorial | `--example factorial` | Additional recursive-function example using Figures 1--4 and Theorem 3.8 |
| Fibonacci | `--example fibonacci` | Additional two-pointer recursive example using Definitions 3.1/3.7 and Theorem 3.8 |
| SK combinator reduction | `--example sk` | Section 5, Definition 5.2, and `(phi_SK, R_SK)` with the displayed `S x y z -> (x z)(y z)` target |

The SK example prints both raw integer witness rows and decoded combinators.  For
example, `70:((K S) K)` means that the integer code `70` decodes to the term
`((K S) K)` under the shifted Cantor pairing from Definition 5.2.  The `Sred`
column shows the target `232:((K K) (S K))` for
`(((S K) S) K) -> ((K K) (S K))`, matching the paper's displayed rule
`S x y z -> (x z)(y z)`.

## What counts as success

For each witness column, the program computes two values:

1. direct integer semantics from the AST, following Figure 3; and
2. compiled semantics, obtained by applying `beta` to the `mkQ` polynomial from
   Definition 3.5/Figure 4 and Definition 3.6.

Theorem 3.8 says these agree when pointer rows are in range.  A valid example
therefore reports:

```text
direct integer semantics: (0, ..., 0)
beta(mkQ) values:          (0, ..., 0)
semantics agree: True
all zero: True
```

## Files of interest

```text
src/zkfol/ast.py          typed FOL terms and predicates
src/zkfol/compiler.py     symbolic mkQ and beta evaluation
src/zkfol/fast_beta.py    direct bit-level beta(mkQ)-equivalent evaluator
src/zkfol/witness.py      witness matrices and pointer range checks
src/zkfol/witnesses.py    arithmetic witness builders
src/zkfol/examples.py     arithmetic predicates and example specs
src/zkfol/sk.py           SK predicate, witness, pairing, and pretty-printer
src/zkfol/paper.py        paper-reference strings used by CLI output
tests/                    positive grids, symbolic checks, and negative controls
PAPER_GUIDE.md            map from paper definitions to code
ASSURANCE.md              why the output is computed rather than decorative
```

## Scope

This is a reference implementation of the arithmetisation and witness-evaluation
layer.  It does not implement Zinc, AIR generation, polynomial commitments, a
PIOP, or a production zk-SNARK prover/verifier.  The sibling
`../zkfol_zinc_adapter/` package provides the experimental Zinc proof-of-concept
bridge.
