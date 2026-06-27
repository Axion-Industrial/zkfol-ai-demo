# Assurance notes

The reference CLI is meant to be auditable.  Its output is computed on each run rather than copied from stored expected strings.

What is recomputed:

1. The witness matrix is built by ordinary Python functions in `src/zkfol/witnesses.py` or `src/zkfol/sk.py`.
2. The predicate is evaluated directly with the Figure 3 integer semantics.
3. The same predicate is evaluated by the `beta(mkQ)` route, either through the explicit symbolic compiler or through the fast bit-level evaluator.
4. The CLI reports success only when pointer range checks pass and both semantic routes give zero in every column.

The reference test suite covers positive parameter grids, small symbolic-vs-fast checks, SK reduction checks, and negative controls that deliberately corrupt witnesses or pointer rows.  Run it with:

```bash
./run tests
# or
make test
```

The broader adapter regression suite lives in `../zkfol_zinc_adapter/tests` and adds checks for JSON export, CCS/R1CS relation checking, resource preflight, progress reporting, Rust-source contracts, and optional Cargo/Zinc smoke tests.
