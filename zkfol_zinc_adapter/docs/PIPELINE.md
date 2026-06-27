# Pipeline guide

For the complete practical meaning of every command-line option, see `docs/OPTIONS_REFERENCE.md` or run `./zkfol_zinc_adapter/folzinc options`.

The adapter follows the mathematical path in the paper, but materialises it as a
benchmark-friendly CCS/R1CS bridge.

## 1. FOL predicate and witness

The reference implementation defines a predicate `phi` and a finite matrix
witness `C`. A valid judgement means `phi` is true for every finite-model index
`x`, and all range checks hold.

## 2. Integer semantics

The paper's integer semantics uses zero as truth. Equality becomes a square,
conjunction becomes a sum, and disjunction becomes a product. Therefore the
compiled predicate is valid when all relevant values are exactly zero.

## 3. `mkQ_x(<phi>)` and `beta_F`

The FOL predicate is translated to an enriched polynomial `<phi>`, then to the
multivariate polynomial `mkQ_x(<phi>)`. The evaluator `beta_F` fills the paper's
`B` variables with bits from the matrix witness.

## 4. Pointer soundness

A term `C_i(C_j(x))` uses row `j` as a pointer. The adapter proves this is sound
by adding:

- one-hot selector bits for each possible target column;
- a range/value check tying the pointer value to the selected column;
- lookup constraints tying composed bits to the selected direct bits.


## 5a. Public benchmark claims

The default export has only a conventional public zero input.  For benchmarking
against zkVMs, pass `--public-final`.  The exporter then adds R1CS rows that bind
selected final witness entries to public inputs.  For power examples, these are
the final base, exponent, and output cells.

## 5. Integer R1CS/CCS

Each arithmetic expression is compiled into rows of the form:

```text
<A,z> * <B,z> = <C,z>
```

The JSON stores sparse signed integer rows. The Rust runner converts those rows
to Zinc `SparseMatrix<Int<N>>` values.

The package reports the practical constraint shape at this point:

```text
scalar z variables = public inputs + 1 constant-one coordinate + private witness variables
declared degree    = 2 for the R1CS/CCS row form
simplified degree  = degree after public inputs and the one coordinate are fixed
bit-bound delta    = max bit length of materialised values and coefficients
```

These are concrete scalar CCS measurements.  They complement, rather than replace, the paper-level AIR parameters such as arity, hypercube dimension, and bit-length bound.

## 6. Zinc

The Rust runner constructs `CCS_Z`, runs a local relation check, pads dimensions,
and invokes Zinc's prover and verifier. A successful run benchmarks this bridge
from FOL witness to Zinc proof.
