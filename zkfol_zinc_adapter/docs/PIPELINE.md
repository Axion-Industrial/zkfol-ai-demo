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
multivariate polynomial `mkQ_x(<phi>)`, then evaluated by `beta_F`.

The adapter supports two representations of the cell values inside `mkQ`,
selected with `build_ccs_export(..., representation=...)`:

- **`typed`** (the default): the `num`/`ptr` optimisation. A row is `ptr` when it
  is used as the inner pointer `C_j` of a composed term `C_i(C_j(x))`, otherwise
  it is `num`. A `num` cell is a single integer witness; only `ptr` cells carry
  the range machinery. No per-cell bit decomposition is used.
- **`bitwise`**: the paper-faithful uniform encoding, where every cell value is a
  `b2int` over private `B` bit wires. Kept for audit and before/after
  benchmarking; both routes feed identical `mkQ_x(<phi>) = 0` checks to Zinc.

See `zkfol/types.py` and `zkfol/typed_compiler.py` for the typed route; this is
the optimisation the paper alludes to in its Section 4 discussion of optimal
syntactic forms.

## 4. Pointer soundness

A term `C_i(C_j(x))` uses row `j` as a pointer. The adapter proves this is sound
by adding:

- one-hot selector bits for each possible target column;
- a one-hot constraint, which simultaneously range-checks the pointer into
  `1..len(C)` (its integer value is `sum_k k * sel_k`);
- a lookup tying the composed cell to the selected column's value: in the typed
  route, the single integer equality `C_i(C_j(x)) = sum_k sel_k * C_i(k)`; in the
  bitwise route, one equality per bit tying composed bits to selected direct bits.


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
